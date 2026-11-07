local addonName, ns = ...

-- LeanPad's own window for NPCs and quests, answered from the pad: A confirms, B backs out, the D-pad chooses and the
-- bumpers scroll long text. A panel whose edges melt into the world, at any of nine places on screen, with the NPC in
-- 3D beside their words. Out of combat it stands in for Blizzard's gossip and quest windows, which stop hearing the events that open
-- them. In combat they hear them again, as the pad belongs to the player's bindings there; a window already open stays,
-- for the mouse. With Blizzard's Gamepad UI on, or another dialogue addon, it stays out.
-- shortcut: titles, skill points and plain faction reputation show in the quest text only. Add them if missed.
local CONFIRM_KEY, BACK_KEY = "PAD1", "PAD2"
local MOVE = { PADDUP = -1, PADDLEFT = -1, PADDDOWN = 1, PADDRIGHT = 1 }
local SCROLL = { PADLSHOULDER = -1, PADRSHOULDER = 1 }
-- A card: the NPC beside their words, a column narrow enough to read in one sweep (about 70 characters), text that
-- scrolls only when long, and a footer bar for the prompts.
local PAD, FOOTER, TEXT_HEIGHT, SCROLL_STEP, COLUMN = 24, 64, 260, 60, 540
local TILE_GAP, TILE_HEIGHT, TILES_PER_ROW = 10, 44, 3
local TILE_WIDTH = (COLUMN - (TILES_PER_ROW - 1) * TILE_GAP) / TILES_PER_ROW
local MODEL_WIDTH, MODEL_HEIGHT, PORTRAIT = 170, 200, 64
ns.DIALOGUE_TEXT_SIZES = { { "15", "Small" }, { "17", "Medium" }, { "19", "Large" }, { "22", "Largest" } }
ns.DIALOGUE_POSITIONS = {
	{ "TOPLEFT", "Top left" }, { "TOP", "Top centre" }, { "TOPRIGHT", "Top right" },
	{ "LEFT", "Centre left" }, { "CENTER", "Centre" }, { "RIGHT", "Centre right" },
	{ "BOTTOMLEFT", "Bottom left" }, { "BOTTOM", "Bottom centre" }, { "BOTTOMRIGHT", "Bottom right" },
}
local ZOOM_TO = 4 -- camera distance, in yards, that frames the NPC over the character's shoulder
local TALK = 60 -- EmoteTalk in the client's AnimationData
local REVEAL_SPEED, REVEAL_SOFTNESS, REVEAL_DONE = 90, 24, 100000 -- characters a second, how many fade in at once, past any text
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUEST_PAGES = { QUEST_GREETING = "greeting", QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete" }
local UNITS = { gossip = "npc", preview = "player" } -- whom each page shows; quest pages show questnpc
local OTHER_DIALOGUES = { "DialogueUI", "Immersion" }
local PREVIEW_TEXT = "This is where NPCs speak, at the size and in the place you set. A confirms, B backs out, the D-pad chooses and the bumpers scroll text that runs long."
local C = ns.COLORS

local window, mode, pick, armed, claimed, zoomed, tipShown, revealAt = nil, nil, 0, false, false, nil, false, nil
local besideHeight, questFace, titleFace = 0, nil, nil -- how tall the NPC beside the words stands, and Blizzard's quest faces
local entries, lines, tiles = {}, {}, {}

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

local function add(list, text, icon, choose, item, quality)
	table.insert(list, { text = text or "...", icon = icon, choose = choose, item = item, quality = quality })
end

local function questIcon(complete) return complete and "QuestTurnin" or "Quest-In-Progress-Icon-yellow" end

local function counted(name, amount)
	return name and amount and amount > 1 and ("%s x%d"):format(name, amount) or name
end

-- Quest items of one kind, each with its tooltip.
local function addItems(list, kind, count)
	for i = 1, count do
		local name, texture, amount, quality = GetQuestItemInfo(kind, i)
		add(list, counted(name, amount), texture, nil, { kind, i }, quality)
	end
end

-- Choices first, so a pick's index is the reward's: items, or currencies where the loot type says so; then fixed
-- items, currencies and spells not known yet.
local function rewards()
	local list, questID = {}, GetQuestID()
	for i = 1, GetNumQuestChoices() do
		if GetQuestItemInfoLootType("choice", i) == 1 then
			local info = C_QuestOffer.GetQuestRewardCurrencyInfo("choice", i)
			add(list, counted(info.name, info.totalRewardAmount), info.texture, nil, { "choice", i, "currency" }, info.quality)
		else
			local name, texture, amount, quality = GetQuestItemInfo("choice", i)
			add(list, counted(name, amount), texture, nil, { "choice", i }, quality)
		end
	end
	addItems(list, "reward", GetNumQuestRewards())
	for i, info in ipairs(C_QuestInfoSystem.GetQuestRewardCurrencies(questID) or {}) do
		add(list, counted(info.name, info.totalRewardAmount), info.texture, nil, { "reward", i, "currency" }, info.quality)
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
local function questTitle() return GetTitleText() end

-- Each page's text, and the entries the D-pad walks: lines that do something when chosen, or items that show a tooltip.
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
		title = questTitle,
		text = function() return GetQuestText() .. "\n\n|cfff6b73cObjectives|r\n" .. GetObjectiveText() end,
		entries = rewards,
	},
	progress = {
		title = questTitle,
		text = function() return GetProgressText() end,
		entries = function()
			local list = {}
			addItems(list, "required", GetNumQuestItems())
			return list
		end,
	},
	complete = { title = questTitle, text = function() return GetRewardText() end, entries = rewards },
	-- What the settings page shows, where and as large as the real one, with the player standing in for the NPC.
	preview = {
		title = function() return "A word before you go" end,
		text = function() return PREVIEW_TEXT end,
		entries = function()
			local list, none = {}, function() end
			add(list, "I'm looking for work.", "QuestNormal", none)
			add(list, "The boars are dealt with.", "QuestTurnin", none)
			add(list, "How is the hunt going?", "Quest-In-Progress-Icon-yellow", none)
			return list
		end,
	},
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

local function backLabel()
	if mode == "preview" then return "Close" end
	return mode == "detail" and not QuestGetAutoAccept() and "Decline" or "Goodbye"
end

local function stopReveal()
	revealAt = nil
	window.Reveal:SetScript("OnUpdate", nil)
	window.Body:SetAlphaGradient(REVEAL_DONE, REVEAL_SOFTNESS)
end

-- Text writes itself in; the gradient reports when it has passed the last character.
local function revealStep(_, elapsed)
	revealAt = revealAt + elapsed * REVEAL_SPEED
	if not window.Body:SetAlphaGradient(revealAt, REVEAL_SOFTNESS) then stopReveal() end
end

-- A first press while text is still writing itself in shows it all.
local function confirm()
	if revealAt then return stopReveal() end
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
	if mode == "preview" then return ns.CloseDialogue() end
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
	GameTooltip:SetOwner(tiles[pick], "ANCHOR_RIGHT")
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

-- A click picks the entry, and chooses it if it's a line rather than an item.
local function clickEntry(i)
	pick, armed = i, false
	ns.RefreshDialogue()
	if entries[i].choose then confirm() end
end

-- Narrative text in Blizzard's quest faces, which follow the client's language; the rest in LeanPad's own.
local function text(parent, size, color, font)
	local label = ns.Text(parent, size, color, "LEFT", font and (font:GetFont()))
	label:SetShadowOffset(1, -1)
	label:SetShadowColor(0, 0, 0, 0.9)
	return label
end

local function setIcon(texture, icon)
	if type(icon) == "string" then texture:SetAtlas(icon) else texture:SetTexture(icon) end
end

local function line(i)
	if lines[i] then return lines[i] end
	local button = CreateFrame("Button", nil, window.Content)
	button:SetWidth(COLUMN)
	button.Lit = button:CreateTexture(nil, "BACKGROUND")
	button.Lit:SetAllPoints()
	button.Lit:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 0.75)
	button.Bar = button:CreateTexture(nil, "ARTWORK")
	button.Bar:SetColorTexture(unpack(C.accent))
	button.Bar:SetPoint("TOPLEFT")
	button.Bar:SetPoint("BOTTOMLEFT")
	button.Bar:SetWidth(3)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetSize(18, 18)
	button.Icon:SetPoint("LEFT", 14, 0)
	button.Label = text(button, 16, C.text, QuestFont)
	button.Label:SetPoint("LEFT", button.Icon, "RIGHT", 10, 0)
	button.Label:SetPoint("RIGHT", -10, 0)
	button.Label:SetWordWrap(false)
	button:SetScript("OnClick", function() clickEntry(i) end)
	lines[i] = button
	return button
end

local function tile(i)
	if tiles[i] then return tiles[i] end
	local button = CreateFrame("Button", nil, window.Content, "BackdropTemplate")
	ns.Backdrop(button, C.raised, C.edge)
	button:SetSize(TILE_WIDTH, TILE_HEIGHT)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetSize(36, 36)
	button.Icon:SetPoint("LEFT", 4, 0)
	button.Label = text(button, 13, C.text)
	button.Label:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
	button.Label:SetPoint("RIGHT", -6, 0)
	button.Label:SetMaxLines(2)
	button:SetScript("OnClick", function() clickEntry(i) end)
	tiles[i] = button
	return button
end

-- The pad's prompts, as glyph and word; clickable too, for the mouse in combat.
local function prompt(color, onClick)
	local button = CreateFrame("Button", nil, window)
	button:SetHeight(30)
	button:SetNormalFontObject(ns.Font(16, color))
	button:SetHighlightFontObject(ns.Font(16, C.accentHover))
	button:SetScript("OnClick", onClick)
	return button
end

local function setPrompt(button, key, label)
	button:SetShown(label ~= nil)
	if not label then return end
	button:SetText(ns.Glyphed(key, label, 24))
	button:SetWidth(button:GetTextWidth() + 8)
end

-- The NPC beside their words: in 3D, talking, unless turned off, else their portrait. With nobody to show, such as an
-- item or a missive, which has no model or face, the words take the room; the object is still named.
local function dress()
	local unit = UNITS[mode] or "questnpc"
	local hasUnit = UnitExists(unit)
	local shown = hasUnit and not UnitIsGameObject(unit)
	local model = shown and ns.db.dialogueModel ~= false
	window.Model:SetShown(model)
	window.Portrait:SetShown(shown and not model)
	if model then
		window.Model:SetUnit(unit)
	elseif shown then
		SetPortraitTexture(window.Portrait, unit)
	end
	local beside = model and MODEL_WIDTH or shown and PORTRAIT + 20 or 0
	besideHeight = model and MODEL_HEIGHT or shown and PORTRAIT or 0
	window.Content:SetPoint("TOPLEFT", PAD + beside, -PAD)
	window:SetWidth(2 * PAD + beside + COLUMN)
	-- Over a quest's title the NPC is named small, otherwise in the headline. UnitName goes straight to the text.
	local named, plain = window.Headline, window.Kicker
	if PAGES[mode].title then named, plain = window.Kicker, window.Headline end
	plain:SetText("")
	if hasUnit then named:SetText(UnitName(unit)) else named:SetText("") end
end

function ns.RefreshDialogue()
	if not mode then return end
	local page = PAGES[mode]
	local size = ns.db.dialogueTextSize or 17
	local lineHeight = size + 15
	window.Headline:SetFontObject(ns.Font(size + 9, C.text, titleFace))
	window.Body:SetFontObject(ns.Font(size, C.text, questFace))
	if page.title then window.Headline:SetText(page.title()) end
	window.Body:SetText(page.text() or "")
	window.Body:SetAlphaGradient(revealAt or REVEAL_DONE, REVEAL_SOFTNESS)
	local fullHeight = window.Body:GetStringHeight()
	local textHeight = math.min(fullHeight, TEXT_HEIGHT)
	window.Child:SetHeight(fullHeight)
	window.Scroll:SetHeight(textHeight)

	entries = page.entries()
	pick = math.min(pick, #entries)
	local items = entries[1] ~= nil and entries[1].item ~= nil
	local shownLines, shownTiles = items and 0 or #entries, items and #entries or 0
	for i = 1, math.max(shownLines, #lines) do
		local button, entry = line(i), entries[i]
		button:SetShown(i <= shownLines)
		if i <= shownLines then
			local lit = i == pick
			button:SetHeight(lineHeight - 2)
			button:SetPoint("TOPLEFT", window.Scroll, "BOTTOMLEFT", 0, -(14 + (i - 1) * lineHeight))
			button.Label:SetFontObject(ns.Font(size - 1, C.text, questFace))
			button.Label:SetText(entry.text)
			button.Label:SetTextColor(unpack(lit and C.text or C.text2))
			setIcon(button.Icon, entry.icon)
			button.Lit:SetShown(lit)
			button.Bar:SetShown(lit)
		end
	end
	local y = 14 + shownLines * lineHeight

	local money = moneyLine()
	if shownTiles > 0 or money ~= "" then
		window.Section:SetPoint("TOPLEFT", window.Scroll, "BOTTOMLEFT", 0, -y)
		window.Section:SetText(mode == "progress" and "REQUIRED" or GetNumQuestChoices() > 1 and "CHOOSE ONE REWARD" or "REWARDS")
		y = y + 24
	else
		window.Section:SetText("")
	end
	window.Money:SetText(money)
	for i = 1, math.max(shownTiles, #tiles) do
		local button, entry = tile(i), entries[i]
		button:SetShown(i <= shownTiles)
		if i <= shownTiles then
			local lit, column, row = i == pick, (i - 1) % TILES_PER_ROW, math.floor((i - 1) / TILES_PER_ROW)
			button:SetPoint("TOPLEFT", window.Scroll, "BOTTOMLEFT", column * (TILE_WIDTH + TILE_GAP), -(y + row * (TILE_HEIGHT + 8)))
			button.Label:SetText(entry.text)
			if entry.quality then
				local r, g, b = C_Item.GetItemQualityColor(entry.quality) -- a fourth return, its hex string, is no alpha
				button.Label:SetTextColor(r, g, b)
			else
				button.Label:SetTextColor(unpack(C.text))
			end
			setIcon(button.Icon, entry.icon)
			button:SetBackdropColor(unpack(lit and C.hover or C.raised))
			button:SetBackdropBorderColor(unpack(lit and C.accent or C.edge))
		end
	end
	y = y + math.ceil(shownTiles / TILES_PER_ROW) * (TILE_HEIGHT + 8)

	-- The header: the small name over the headline, its rule and the gap to the words, all growing with the text.
	local height = size + 53 + textHeight + y
	window.Content:SetHeight(height)
	window:SetHeight(PAD + math.max(height, besideHeight) + FOOTER)

	local hints = {}
	if #entries > 1 then table.insert(hints, ns.Glyphed("PADDUP", "Choose", 20)) end
	if fullHeight > TEXT_HEIGHT then table.insert(hints, ns.Glyphed("PADRSHOULDER", "Scroll", 20)) end
	window.Hint:SetText(table.concat(hints, "     "))
	setPrompt(window.Confirm, CONFIRM_KEY, confirmLabel())
	setPrompt(window.Back, BACK_KEY, backLabel())
	window.Back:ClearAllPoints()
	if window.Confirm:IsShown() then
		window.Back:SetPoint("RIGHT", window.Confirm, "LEFT", -28, 0)
	else
		window.Back:SetPoint("BOTTOMRIGHT", -PAD, 14)
	end
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
	if zoomed or mode == "preview" or not ns.db.dialogueCamera then return end
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

-- The saved place, if it's one of the nine, else bottom centre.
function ns.DialoguePosition()
	local saved = ns.db.dialoguePosition
	for _, position in ipairs(ns.DIALOGUE_POSITIONS) do
		if position[1] == saved then return saved end
	end
	return "BOTTOM"
end

-- The window at its place on screen, a little in from the edges and, at the bottom, over the action bars. Size scales it.
function ns.PlaceDialogue()
	if not window then return end
	local point = ns.DialoguePosition()
	local x = point:find("LEFT") and 40 or point:find("RIGHT") and -40 or 0
	local y = point:find("TOP") and -40 or point:find("BOTTOM") and 140 or 0
	window:SetScale(ns.db.dialogueScale or 1)
	window:ClearAllPoints()
	window:SetPoint(point, UIParent, point, x, y)
	if mode then
		dress()
		ns.RefreshDialogue()
	end
end

local function build()
	questFace, titleFace = (QuestFont:GetFont()), (QuestTitleFont:GetFont())
	window = CreateFrame("Frame", "LeanPadDialogue", UIParent, "BackdropTemplate")
	ns.Backdrop(window, C.bg, C.edge)
	window:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.94)
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window.Accent = window:CreateTexture(nil, "ARTWORK")
	window.Accent:SetColorTexture(unpack(C.accent))
	window.Accent:SetHeight(2)
	window.Accent:SetPoint("TOPLEFT", 1, -1)
	window.Accent:SetPoint("TOPRIGHT", -1, -1)
	window.Content = CreateFrame("Frame", nil, window)
	window.Content:SetWidth(COLUMN)
	window.Model = CreateFrame("PlayerModel", nil, window)
	window.Model:SetSize(MODEL_WIDTH, MODEL_HEIGHT)
	window.Model:SetPoint("TOPLEFT", PAD - 12, -PAD + 4)
	window.Model:SetScript("OnModelLoaded", function(self)
		self:SetPortraitZoom(0.65)
		self:SetAnimation(TALK)
	end)
	window.Portrait = window:CreateTexture(nil, "ARTWORK")
	window.Portrait:SetSize(PORTRAIT, PORTRAIT)
	window.Portrait:SetPoint("TOPLEFT", PAD, -PAD)
	window.Portrait:SetMask(ROUND_MASK)
	window.Kicker = text(window.Content, 13, C.accent)
	window.Kicker:SetPoint("TOPLEFT")
	window.Headline = text(window.Content, 26, C.text, QuestTitleFont)
	window.Headline:SetPoint("TOPLEFT", window.Kicker, "BOTTOMLEFT", 0, -4)
	window.Headline:SetPoint("RIGHT")
	window.Headline:SetWordWrap(false)
	window.Rule = window.Content:CreateTexture(nil, "ARTWORK")
	window.Rule:SetColorTexture(unpack(C.accent))
	window.Rule:SetSize(48, 2)
	window.Rule:SetPoint("TOPLEFT", window.Headline, "BOTTOMLEFT", 0, -10)
	window.Scroll = CreateFrame("ScrollFrame", nil, window.Content)
	window.Scroll:SetPoint("TOPLEFT", window.Rule, "BOTTOMLEFT", 0, -14)
	window.Scroll:SetWidth(COLUMN)
	window.Scroll:EnableMouseWheel(true)
	window.Scroll:SetScript("OnMouseWheel", function(_, delta) scroll(-delta) end)
	window.Child = CreateFrame("Frame", nil, window.Scroll)
	window.Child:SetWidth(COLUMN)
	window.Scroll:SetScrollChild(window.Child)
	window.Body = text(window.Child, 17, C.text, QuestFont)
	window.Body:SetPoint("TOPLEFT")
	window.Body:SetWidth(COLUMN)
	window.Body:SetSpacing(5)
	window.Section = text(window.Content, 12, C.accent)
	window.Money = text(window.Content, 14, C.text)
	window.Money:SetPoint("LEFT", window.Section, "RIGHT", 16, 0)
	-- The footer bar: a hairline across the card, the D-pad's and bumpers' hints at its left, the prompts at its right.
	window.Divider = window:CreateTexture(nil, "ARTWORK")
	window.Divider:SetColorTexture(unpack(C.line))
	window.Divider:SetHeight(1)
	window.Divider:SetPoint("BOTTOMLEFT", PAD, FOOTER - 12)
	window.Divider:SetPoint("BOTTOMRIGHT", -PAD, FOOTER - 12)
	window.Hint = text(window, 14, C.text2)
	window.Hint:SetPoint("BOTTOMLEFT", PAD, 22)
	window.Confirm = prompt(C.accent, confirm)
	window.Confirm:SetPoint("BOTTOMRIGHT", -PAD, 14)
	window.Back = prompt(C.text2, back)
	-- The pad listens on a child, hidden in combat, where frames can't take the pad from the player's bindings.
	window.Input = CreateFrame("Frame", nil, window)
	window.Input:EnableGamePadButton(true)
	window.Input:SetScript("OnGamePadButtonDown", onPress)
	-- Runs only while text writes itself in.
	window.Reveal = CreateFrame("Frame", nil, window)
	window.FadeIn = window:CreateAnimationGroup()
	local fade = window.FadeIn:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.25)
	-- Escape, or Blizzard closing every window, ends the conversation as closing its own window would.
	window:SetScript("OnHide", function()
		if not mode then return end
		if mode == "gossip" then C_GossipInfo.CloseGossip() elseif mode ~= "preview" then CloseQuest() end
		ns.CloseDialogue()
	end)
	table.insert(UISpecialFrames, "LeanPadDialogue")
	ns.PlaceDialogue()
	window:Hide()
end

local function open(page)
	if not window then build() end
	mode, pick, armed = page, (page == "gossip" or page == "greeting" or page == "preview") and 1 or 0, false
	revealAt = ns.db.dialogueReveal ~= false and 0 or nil
	-- A cursor still up from clicking the NPC would keep every button, so the D-pad would fire bar slots instead.
	if IsGamePadCursorControlEnabled() then SetGamePadCursorControl(false) end
	window.Scroll:SetVerticalScroll(0)
	dress()
	ns.RefreshDialogue()
	window.Reveal:SetScript("OnUpdate", revealAt and revealStep or nil)
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
	window.Reveal:SetScript("OnUpdate", nil)
	window:Hide()
	RunNextFrame(zoomOut)
end

-- The settings page's preview, which a real conversation replaces.
function ns.PreviewDialogue(on)
	if on and not mode then return open("preview") end
	if not on and mode == "preview" then ns.CloseDialogue() end
end

function ns.DialoguePreviewing() return mode == "preview" end

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
	-- A gossip window closes as the quest it led to opens, and a quest as its gossip reopens, so each closes only its
	-- own; the preview closes only on its own.
	if mode ~= "preview" and (event == "GOSSIP_CLOSED") == (mode == "gossip") then ns.CloseDialogue() end
end)

EventUtil.ContinueOnAddOnLoaded(addonName, ns.ClaimDialogues)
