local addonName, ns = ...

-- LeanPad's own window for NPCs and quests, answered from the pad: A confirms, B backs out, the D-pad chooses and the
-- bumpers scroll long text. Out of combat it stands in for Blizzard's gossip and quest windows, which stop hearing the
-- events that open them. In combat they hear them again, as the pad belongs to the player's bindings there; a window
-- already open stays, for the mouse. With Blizzard's Gamepad UI on, or another dialogue addon, it stays out.
-- shortcut: titles, skill points and plain faction reputation show in the quest text only. Add them if missed.
local CONFIRM_KEY, BACK_KEY = "PAD1", "PAD2"
local MOVE = { PADDUP = -1, PADDLEFT = -1, PADDDOWN = 1, PADDRIGHT = 1 }
local SCROLL = { PADLSHOULDER = -1, PADRSHOULDER = 1 }
local WIDTH, HEADER, FOOTER, ROW_HEIGHT, TEXT_HEIGHT, SCROLL_STEP = 560, 72, 56, 28, 150, 60
local ZOOM_TO = 4 -- camera distance, in yards, that frames the NPC over the character's shoulder
local BOOK_ICON = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"
local QUEST_PAGES = { QUEST_GREETING = "greeting", QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete" }
local OTHER_DIALOGUES = { "DialogueUI", "Immersion" }
local C = ns.COLORS

local window, mode, pick, armed, claimed, zoomed, tipShown = nil, nil, 0, false, false, nil, false
local entries, rows = {}, {}

-- Saved choice, else this client's default: on for Forever, off for retail.
function ns.QuestPromptsEnabled()
	if ns.db.questPrompts ~= nil then return ns.db.questPrompts end
	return ns.QUEST_PROMPTS_DEFAULT == true
end

local function owns()
	if InCombatLockdown() or ns.UsesGamepadUI() or not ns.QuestPromptsEnabled() then return false end
	for _, name in ipairs(OTHER_DIALOGUES) do
		if C_AddOns.IsAddOnLoaded(name) then return false end
	end
	return true
end

-- Blizzard's windows hear the events that open them only while LeanPad's doesn't answer them.
function ns.ClaimDialogues()
	local take = owns()
	if take == claimed then return end
	claimed = take
	local method = take and "UnregisterEvent" or "RegisterEvent"
	for event in pairs(QUEST_PAGES) do QuestFrame[method](QuestFrame, event) end
	CustomGossipFrameManager[method](CustomGossipFrameManager, "GOSSIP_SHOW")
end

-- Hands Blizzard's window an event it no longer hears, for a page LeanPad leaves to it.
local function forward(event, ...)
	local frame = event == "GOSSIP_SHOW" and CustomGossipFrameManager or QuestFrame
	frame:GetScript("OnEvent")(frame, event, ...)
end

-- Pages Blizzard handles its own way: a quest from an item or an area goes to the tracker's pop-ups, one from the
-- adventure map stays on that map, a gossip with its own look opens its own frame, and a lone option marked for it is
-- picked without asking.
local function special(event, arg)
	if event == "QUEST_DETAIL" then
		return QuestIsFromAdventureMap() or (arg ~= nil and arg ~= 0) or (QuestGetAutoAccept() and QuestIsFromAreaTrigger())
	end
	if event ~= "GOSSIP_SHOW" then return false end
	if CustomGossipFrameManager:GetHandler(arg) or CustomGossipFrameManager.baseHandler then return true end
	local options = C_GossipInfo.GetOptions()
	return C_GossipInfo.GetNumAvailableQuests() == 0 and C_GossipInfo.GetNumActiveQuests() == 0 and #options == 1
		and options[1].selectOptionWhenOnlyOption and not C_GossipInfo.ForceGossip()
end

local function add(list, text, icon, choose, item)
	table.insert(list, { text = text or "...", icon = icon, choose = choose, item = item })
end

local function questIcon(complete) return complete and "QuestTurnin" or "Quest-In-Progress-Icon-yellow" end

local function counted(name, amount)
	return name and amount and amount > 1 and ("%s x%d"):format(name, amount) or name
end

-- Quest items of one kind, each with its tooltip.
local function addItems(list, kind, count)
	for i = 1, count do
		local name, texture, amount = GetQuestItemInfo(kind, i)
		add(list, counted(name, amount), texture, nil, { kind, i })
	end
end

-- Choices first, so a pick's index is the reward's: items, or currencies where the loot type says so; then fixed
-- items, currencies and spells not known yet.
local function rewards()
	local list, questID = {}, GetQuestID()
	for i = 1, GetNumQuestChoices() do
		if GetQuestItemInfoLootType("choice", i) == 1 then
			local info = C_QuestOffer.GetQuestRewardCurrencyInfo("choice", i)
			add(list, counted(info.name, info.totalRewardAmount), info.texture, nil, { "choice", i, "currency" })
		else
			local name, texture, amount = GetQuestItemInfo("choice", i)
			add(list, counted(name, amount), texture, nil, { "choice", i })
		end
	end
	addItems(list, "reward", GetNumQuestRewards())
	for i, info in ipairs(C_QuestInfoSystem.GetQuestRewardCurrencies(questID) or {}) do
		add(list, counted(info.name, info.totalRewardAmount), info.texture, nil, { "reward", i, "currency" })
	end
	for _, spellID in ipairs(C_QuestInfoSystem.GetQuestRewardSpells(questID) or {}) do
		local info = C_QuestInfoSystem.GetQuestRewardSpellInfo(questID, spellID)
		if info and not C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player, true) then
			add(list, info.name, info.texture, nil, { "spell", spellID, "spell" })
		end
	end
	return list
end

local function byOrder(a, b) return a.orderIndex < b.orderIndex end

-- Each page's text, and the rows the D-pad walks: lines that do something when chosen, or items that show a tooltip.
local PAGES = {
	gossip = {
		text = function() return C_GossipInfo.GetText() end,
		entries = function()
			local list = {}
			for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
				add(list, quest.title, "QuestNormal", function() C_GossipInfo.SelectAvailableQuest(quest.questID) end)
			end
			for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
				add(list, quest.title, questIcon(quest.isComplete), function() C_GossipInfo.SelectActiveQuest(quest.questID) end)
			end
			local options = C_GossipInfo.GetOptions()
			table.sort(options, byOrder)
			for _, option in ipairs(options) do
				add(list, option.name, option.overrideIconID or option.icon, function() C_GossipInfo.SelectOptionByIndex(option.orderIndex) end)
			end
			return list
		end,
	},
	greeting = {
		text = function() return GetGreetingText() end,
		entries = function()
			local list = {}
			for i = 1, GetNumAvailableQuests() do add(list, GetAvailableTitle(i), "QuestNormal", function() SelectAvailableQuest(i) end) end
			for i = 1, GetNumActiveQuests() do
				local title, complete = GetActiveTitle(i)
				add(list, title, questIcon(complete), function() SelectActiveQuest(i) end)
			end
			return list
		end,
	},
	detail = {
		title = true,
		text = function() return GetQuestText() .. "\n\n|cfff6b73cObjectives|r\n" .. GetObjectiveText() end,
		entries = rewards,
	},
	progress = {
		title = true,
		text = function() return GetProgressText() end,
		entries = function()
			local list = {}
			addItems(list, "required", GetNumQuestItems())
			return list
		end,
	},
	complete = { title = true, text = function() return GetRewardText() end, entries = rewards },
}

-- Accepting a PvP quest or paying for one takes a second press, as Blizzard's own confirmation does.
local function risky()
	if mode == "detail" then return QuestFlagsPVP() and not QuestGetAutoAccept() end
	if mode == "complete" then
		local cost = GetQuestMoneyToGet()
		return cost ~= nil and cost > 0
	end
	return false
end

local function chosenReward()
	local count = GetNumQuestChoices()
	if count <= 1 then return count end
	return pick >= 1 and pick <= count and pick or nil
end

-- The confirm prompt for this page, or nil while there is nothing to confirm.
local function confirmLabel()
	if armed then return "Confirm" end
	if mode == "detail" then
		if QuestGetAutoAccept() then return "OK" end
		return risky() and "Accept (PvP)" or "Accept"
	end
	if mode == "progress" then return IsQuestCompletable() and "Continue" or nil end
	if mode == "complete" then
		if not chosenReward() then return nil end
		return risky() and "Complete (costs gold)" or "Complete"
	end
	local entry = entries[pick]
	return entry and entry.choose and "Select" or nil
end

local function confirm()
	if not confirmLabel() then return end
	if risky() and not armed then
		armed = true
		return ns.RefreshDialogue()
	end
	armed = false
	if mode == "detail" then
		if QuestGetAutoAccept() then return AcknowledgeAutoAcceptQuest() end
		AcceptQuest()
	elseif mode == "progress" then
		CompleteQuest()
	elseif mode == "complete" then
		GetQuestReward(chosenReward())
	else
		entries[pick].choose()
	end
end

-- An auto-accepted quest only needs acknowledging, as Blizzard's window allows no declining.
local function back()
	if mode == "gossip" then return C_GossipInfo.CloseGossip() end
	if mode == "detail" and QuestGetAutoAccept() then return AcknowledgeAutoAcceptQuest() end
	CloseQuest()
end

local function moneyLine()
	local parts = {}
	if mode == "detail" or mode == "complete" then
		local money, xp, honor = GetRewardMoney(), GetRewardXP(), GetRewardHonor()
		if money > 0 then table.insert(parts, GetMoneyString(money)) end
		if xp > 0 then table.insert(parts, xp .. " XP") end
		if honor > 0 then table.insert(parts, honor .. " Honor") end
		for _, rep in ipairs(C_QuestOffer.GetQuestOfferMajorFactionReputationRewards() or {}) do
			local faction = C_MajorFactions.GetMajorFactionData(rep.factionID)
			if faction then table.insert(parts, ("%s +%d"):format(faction.name, rep.rewardAmount)) end
		end
	end
	if mode == "progress" or mode == "complete" then
		local cost = GetQuestMoneyToGet()
		if cost and cost > 0 then table.insert(parts, "Costs " .. GetMoneyString(cost)) end
	end
	return table.concat(parts, "    ")
end

local function hideTip()
	if not tipShown then return end
	tipShown = false
	GameTooltip:Hide()
end

-- An item chosen on the pad shows its tooltip, with the comparison to what's equipped, as hovering it would.
local function showTip()
	hideTip()
	local entry = entries[pick]
	if not (entry and entry.item) then return end
	local kind, index, of = unpack(entry.item)
	GameTooltip:SetOwner(rows[pick], "ANCHOR_RIGHT")
	if of == "currency" then
		GameTooltip:SetQuestCurrency(kind, index)
	elseif of == "spell" then
		GameTooltip:SetSpellByID(index)
	else
		GameTooltip:SetQuestItem(kind, index)
		GameTooltip_ShowCompareItem(GameTooltip)
	end
	GameTooltip:Show()
	tipShown = true
end

local function row(i)
	if rows[i] then return rows[i] end
	local button = CreateFrame("Button", nil, window, "BackdropTemplate")
	ns.Backdrop(button, C.raised, C.raised)
	button:SetSize(WIDTH - 28, ROW_HEIGHT - 4)
	button:SetPoint("TOPLEFT", window.Scroll, "BOTTOMLEFT", 0, -(10 + (i - 1) * ROW_HEIGHT))
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetSize(18, 18)
	button.Icon:SetPoint("LEFT", 6, 0)
	button.Label = ns.Text(button, 14, C.text)
	button.Label:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
	button.Label:SetPoint("RIGHT", -8, 0)
	button.Label:SetWordWrap(false)
	-- A click picks the row, and chooses it if it's a line rather than an item.
	button:SetScript("OnClick", function()
		pick, armed = i, false
		ns.RefreshDialogue()
		if entries[i].choose then confirm() end
	end)
	rows[i] = button
	return button
end

function ns.RefreshDialogue()
	if not mode then return end
	local page = PAGES[mode]
	local unit = mode == "gossip" and "npc" or "questnpc"
	if UnitExists(unit) then
		SetPortraitTexture(window.Portrait, unit)
		window.Name:SetText(UnitName(unit))
	else
		window.Portrait:SetTexture(BOOK_ICON)
		window.Name:SetText("")
	end
	window.Title:SetText(page.title and GetTitleText() or "")
	window.Body:SetText(page.text() or "")
	local fullHeight = window.Body:GetStringHeight()
	local textHeight = math.min(fullHeight, TEXT_HEIGHT)
	window.Child:SetHeight(fullHeight)
	window.Scroll:SetHeight(textHeight)

	entries = page.entries()
	pick = math.min(pick, #entries)
	for i = 1, math.max(#entries, #rows) do
		local entry, button = entries[i], row(i)
		button:SetShown(entry ~= nil)
		if entry then
			button.Label:SetText(entry.text)
			if type(entry.icon) == "string" then button.Icon:SetAtlas(entry.icon) else button.Icon:SetTexture(entry.icon) end
			button:SetBackdropColor(unpack(i == pick and C.hover or C.raised))
			button:SetBackdropBorderColor(unpack(i == pick and C.accent or C.raised))
		end
	end
	local money = moneyLine()
	window.Money:SetText(money)
	window.Money:SetPoint("TOPLEFT", window.Scroll, "BOTTOMLEFT", 0, -(12 + #entries * ROW_HEIGHT))
	window:SetHeight(HEADER + textHeight + 10 + #entries * ROW_HEIGHT + (money ~= "" and 22 or 0) + FOOTER)

	local hints = {}
	if #entries > 1 then table.insert(hints, ns.Glyphed("PADDUP", "Choose", 18)) end
	if fullHeight > TEXT_HEIGHT then table.insert(hints, ns.Glyphed("PADRSHOULDER", "Scroll", 18)) end
	window.Hint:SetText(table.concat(hints, "    "))
	local label = confirmLabel()
	window.Confirm:SetShown(label ~= nil)
	window.Confirm:SetText(label and ns.Glyphed(CONFIRM_KEY, label, 18) or "")
	window.Back:SetText(ns.Glyphed(BACK_KEY, mode == "detail" and not QuestGetAutoAccept() and "Decline" or "Goodbye", 18))
	showTip()
end

local function move(step)
	local count = #entries
	if count == 0 or (count == 1 and pick == 1) then return false end
	pick = pick == 0 and (step > 0 and 1 or count) or (pick - 1 + step) % count + 1
	armed = false
	ns.RefreshDialogue()
	return true
end

-- Bumpers scroll only text taller than the window, else they reach their bindings.
local function scroll(step)
	local range = window.Scroll:GetVerticalScrollRange()
	if range <= 0 then return false end
	window.Scroll:SetVerticalScroll(math.max(0, math.min(range, window.Scroll:GetVerticalScroll() + step * SCROLL_STEP)))
	return true
end

-- Only the buttons with something to do are taken; the rest reach their bindings. A cursor the player brought up
-- keeps every button, as its clicks are on them, and so does a pop-up the pad answers, such as a gossip's confirm.
local function onPress(self, key)
	local handled = false
	if not IsGamePadCursorControlEnabled() and not ns.PopupAnswering() then
		if key == CONFIRM_KEY then
			confirm()
			handled = true
		elseif key == BACK_KEY then
			back()
			handled = true
		elseif MOVE[key] then
			handled = move(MOVE[key])
		elseif SCROLL[key] then
			handled = scroll(SCROLL[key])
		end
	end
	self:SetPropagateKeyboardInput(not handled)
end

-- Opt-in: the camera eases in on the NPC and back out once the talking is done.
local function zoomIn()
	if zoomed or not ns.db.dialogueCamera then return end
	local distance = GetCameraZoom()
	if distance <= ZOOM_TO then return end
	zoomed = distance - ZOOM_TO
	CameraZoomIn(zoomed)
end

local function zoomOut()
	if mode or not zoomed then return end
	CameraZoomOut(zoomed)
	zoomed = nil
end

local function build()
	window = CreateFrame("Frame", "LeanPadDialogue", UIParent, "BackdropTemplate")
	ns.Backdrop(window, C.panel, C.edge)
	window:SetWidth(WIDTH)
	window:SetPoint("BOTTOM", 0, 200)
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window.Portrait = window:CreateTexture(nil, "ARTWORK")
	window.Portrait:SetSize(48, 48)
	window.Portrait:SetPoint("TOPLEFT", 14, -14)
	window.Name = ns.Text(window, 16, C.accent)
	window.Name:SetPoint("TOPLEFT", window.Portrait, "TOPRIGHT", 12, -4)
	window.Title = ns.Text(window, 13, C.text2)
	window.Title:SetPoint("TOPLEFT", window.Name, "BOTTOMLEFT", 0, -6)
	window.Title:SetPoint("RIGHT", -14, 0)
	window.Scroll = CreateFrame("ScrollFrame", nil, window)
	window.Scroll:SetPoint("TOPLEFT", 14, -HEADER)
	window.Scroll:SetWidth(WIDTH - 28)
	window.Scroll:EnableMouseWheel(true)
	window.Scroll:SetScript("OnMouseWheel", function(_, delta) scroll(-delta) end)
	window.Child = CreateFrame("Frame", nil, window.Scroll)
	window.Child:SetWidth(WIDTH - 28)
	window.Scroll:SetScrollChild(window.Child)
	window.Body = ns.Text(window.Child, 15, C.text)
	window.Body:SetPoint("TOPLEFT")
	window.Body:SetWidth(WIDTH - 28)
	window.Body:SetSpacing(3)
	window.Money = ns.Text(window, 13, C.text2)
	window.Hint = ns.Text(window, 13, C.text2)
	window.Hint:SetPoint("BOTTOMLEFT", 14, 22)
	window.Confirm = ns.Button(window, "", 180, confirm, true)
	window.Confirm:SetPoint("BOTTOMRIGHT", -14, 12)
	window.Back = ns.Button(window, "", 150, back)
	window.Back:SetPoint("RIGHT", window.Confirm, "LEFT", -8, 0)
	-- The pad listens on a child, hidden in combat, where frames can't take the pad from the player's bindings.
	window.Input = CreateFrame("Frame", nil, window)
	window.Input:EnableGamePadButton(true)
	window.Input:SetScript("OnGamePadButtonDown", onPress)
	window.FadeIn = window:CreateAnimationGroup()
	local fade = window.FadeIn:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.2)
	-- Escape, or Blizzard closing every window, ends the conversation as closing its own window would.
	window:SetScript("OnHide", function()
		if not mode then return end
		if mode == "gossip" then C_GossipInfo.CloseGossip() else CloseQuest() end
		ns.CloseDialogue()
	end)
	table.insert(UISpecialFrames, "LeanPadDialogue")
	window:Hide()
end

local function open(page)
	if not window then build() end
	mode, pick, armed = page, (page == "gossip" or page == "greeting") and 1 or 0, false
	window.Scroll:SetVerticalScroll(0)
	ns.RefreshDialogue()
	if not window:IsShown() then
		window:Show()
		window.FadeIn:Play()
	end
	window.Input:Show()
	zoomIn()
end

-- A page that follows straight on, such as gossip leading to a quest, keeps the camera where it is.
function ns.CloseDialogue()
	if not mode then return end
	mode = nil
	hideTip()
	window:Hide()
	RunNextFrame(zoomOut)
end

local watcher = CreateFrame("Frame")
for event in pairs(QUEST_PAGES) do watcher:RegisterEvent(event) end
for _, event in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		if window then window.Input:SetShown(event == "PLAYER_REGEN_ENABLED") end
		return ns.ClaimDialogues()
	end
	if event == "QUEST_ITEM_UPDATE" then return ns.RefreshDialogue() end
	local page = QUEST_PAGES[event] or (event == "GOSSIP_SHOW" and "gossip")
	if page then
		local missed = claimed -- whether Blizzard's window missed this event
		ns.ClaimDialogues()
		if not missed then return ns.CloseDialogue() end -- Blizzard's window has it, and LeanPad's gives way
		if not claimed or special(event, ...) then
			ns.CloseDialogue()
			return forward(event, ...)
		end
		return open(page)
	end
	-- A gossip window closes as the quest it led to opens, and a quest as its gossip reopens, so each closes only its own.
	if (event == "GOSSIP_CLOSED") == (mode == "gossip") then ns.CloseDialogue() end
end)

EventUtil.ContinueOnAddOnLoaded(addonName, ns.ClaimDialogues)
