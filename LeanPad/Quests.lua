local _, ns = ...

-- Answering quests and NPCs from the pad: A confirms, B backs out, the D-pad chooses, with a footer naming each under
-- Blizzard's own window, whose buttons fade while it shows. It calls the game's quest API and does nothing else to that
-- window. With Blizzard's Gamepad UI on it stays out of the way, as the Gamepad UI does this itself.
-- shortcut: a quest or gossip line chosen shows in the footer, not on Blizzard's list, and quest text doesn't scroll
-- from the pad; the cursor does both. Add both if players miss them.
local CONFIRM_KEY, BACK_KEY = "PAD1", "PAD2"
local DPAD = { PADDUP = -1, PADDLEFT = -1, PADDDOWN = 1, PADDRIGHT = 1 }
local BAR_WIDTH = 384
local C = ns.COLORS

local bar, mode, pick, hovered

local function unhover()
	if not hovered then return end
	hovered:OnLeave()
	hovered = nil
end

-- A reward chosen on the pad acts as one moused over and clicked: Blizzard's own button highlights it and shows its
-- tooltip, with the comparison to what's equipped.
local function hoverReward()
	unhover()
	if mode ~= "complete" or pick == 0 then return end
	for _, button in ipairs(QuestInfoFrame.rewardsFrame.RewardButtons) do
		if button.type == "choice" and button:GetID() == pick and button:IsVisible() then
			QuestInfoItem_OnClick(button)
			button:OnEnter()
			hovered = button
			return
		end
	end
end

-- The buttons Blizzard's Gamepad UI hides for its own prompts. Faded, not hidden, as Blizzard's pages show them again.
-- A cursor needs them back: they're how it answers.
function ns.UpdateQuestButtons()
	local alpha = mode and not IsGamePadCursorControlEnabled() and 0 or 1
	for _, button in ipairs({ QuestFrameAcceptButton, QuestFrameDeclineButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton,
		QuestFrameGoodbyeButton, QuestFrameGreetingGoodbyeButton, QuestFrameCloseButton, GossipFrame.GreetingPanel.GoodbyeButton, GossipFrameCloseButton }) do
		button:SetAlpha(alpha)
	end
end

-- Saved choice, else this client's default: on for Forever, off for retail.
function ns.QuestPromptsEnabled()
	if ns.db.questPrompts ~= nil then return ns.db.questPrompts end
	return ns.QUEST_PROMPTS_DEFAULT == true
end

local function add(entries, text, select)
	table.insert(entries, { text, select })
end

-- What the D-pad chooses between on each page, each with what picking it does.
local OPTIONS = {
	greeting = function()
		local entries = {}
		for i = 1, GetNumAvailableQuests() do add(entries, GetAvailableTitle(i), function() SelectAvailableQuest(i) end) end
		for i = 1, GetNumActiveQuests() do add(entries, GetActiveTitle(i), function() SelectActiveQuest(i) end) end
		return entries
	end,
	gossip = function()
		local entries = {}
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
			add(entries, quest.title, function() C_GossipInfo.SelectAvailableQuest(quest.questID) end)
		end
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
			add(entries, quest.title, function() C_GossipInfo.SelectActiveQuest(quest.questID) end)
		end
		for _, option in ipairs(C_GossipInfo.GetOptions()) do
			add(entries, option.name, function() C_GossipInfo.SelectOptionByIndex(option.orderIndex) end)
		end
		return entries
	end,
	-- A lone reward needs no choosing, and nothing is chosen for you among several.
	complete = function()
		local entries, count = {}, GetNumQuestChoices()
		for i = 1, count > 1 and count or 0 do
			local name, texture = GetQuestItemInfo("choice", i)
			add(entries, (texture and ("|T%s:16|t "):format(texture) or "") .. (name or "..."))
		end
		return entries
	end,
}

local function options()
	local build = OPTIONS[mode]
	return build and build() or {}
end

-- A PvP quest or one that costs gold asks Blizzard's confirmation, which reads Blizzard's own state, so the cursor does those.
local function needsCursor()
	if mode == "detail" then return QuestFlagsPVP() end
	if mode == "complete" then
		local money = GetQuestMoneyToGet()
		return money and money > 0
	end
end

-- The confirm prompt for this page, or nil while there is nothing to confirm.
local function confirmLabel(entries)
	if needsCursor() then return "Use the cursor" end
	if mode == "detail" then return "Accept" end
	if mode == "progress" then return IsQuestCompletable() and "Continue" or nil end
	if mode == "complete" then return (#entries == 0 or pick > 0) and "Complete" or nil end
	return #entries > 0 and "Select" or nil
end

local function refresh()
	local entries = options()
	local prompts = {}
	if #entries > 1 then table.insert(prompts, ns.Glyphed("PADDUP", "Choose", 18)) end
	local label = confirmLabel(entries)
	if label then table.insert(prompts, ns.Glyphed(CONFIRM_KEY, label, 18)) end
	table.insert(prompts, ns.Glyphed(BACK_KEY, mode == "detail" and "Decline" or "Goodbye", 18))
	bar.Prompts:SetText(table.concat(prompts, "    "))
	local choice = entries[pick]
	bar.Choice:SetText(choice and choice[1] or (#entries > 0 and "Choose your reward" or ""))
	bar:SetHeight(#entries > 0 and 60 or 36)
end

local function confirm()
	if needsCursor() then
		SetGamePadCursorControl(true)
		return ns.UpdateQuestButtons()
	end
	if mode == "detail" then
		if QuestFrame.autoQuest then return AcknowledgeAutoAcceptQuest() end
		AcceptQuest()
	elseif mode == "progress" then
		if IsQuestCompletable() then CompleteQuest() end
	elseif mode == "complete" then
		local count = GetNumQuestChoices()
		if count == 1 then
			GetQuestReward(1)
		elseif count == 0 or pick > 0 then
			GetQuestReward(pick)
		end
	else
		local entry = options()[pick]
		if entry then entry[2]() end
	end
end

local function back()
	if mode == "gossip" then return C_GossipInfo.CloseGossip() end
	CloseQuest()
end

local function move(step)
	local count = #options()
	if count < 2 then return false end
	pick = pick == 0 and (step > 0 and 1 or count) or (pick - 1 + step) % count + 1
	refresh()
	hoverReward()
	return true
end

-- Only A, B and a D-pad with something to choose are taken; the rest reach their bindings. A cursor the player
-- brought up keeps every button, as its clicks are on them.
local function onPress(self, key)
	local handled = false
	ns.UpdateQuestButtons()
	if not IsGamePadCursorControlEnabled() then
		if key == CONFIRM_KEY then
			confirm()
			handled = true
		elseif key == BACK_KEY then
			back()
			handled = true
		elseif DPAD[key] then
			handled = move(DPAD[key])
		end
	end
	self:SetPropagateKeyboardInput(not handled)
end

local function build()
	bar = ns.Panel(UIParent, C.panel, C.edge)
	bar:SetWidth(BAR_WIDTH)
	bar:SetFrameStrata("DIALOG")
	bar:SetClampedToScreen(true)
	bar.Choice = ns.Text(bar, 14, C.text, "CENTER")
	bar.Choice:SetPoint("TOP", 0, -10)
	bar.Choice:SetWidth(BAR_WIDTH - 20)
	bar.Choice:SetWordWrap(false)
	bar.Prompts = ns.Text(bar, 13, C.text2, "CENTER")
	bar.Prompts:SetPoint("BOTTOM", 0, 10)
	bar:SetScript("OnGamePadButtonDown", onPress)
	bar:Hide()
end

-- Never starts in combat, where the pad can't be taken and the player's buttons matter more. Blizzard turns the
-- cursor on as a window opens, and A and B would click with it.
local function open(newMode, owner)
	if InCombatLockdown() or ns.UsesGamepadUI() or not ns.QuestPromptsEnabled() then return end
	if not bar then build() end
	unhover()
	mode = newMode
	pick = OPTIONS[mode] and mode ~= "complete" and 1 or 0
	bar:EnableGamePadButton(true)
	if IsGamePadCursorControlEnabled() then SetGamePadCursorControl(false) end
	bar:ClearAllPoints()
	bar:SetPoint("TOP", owner, "BOTTOM", 0, -6)
	refresh()
	bar:Show()
	ns.UpdateQuestButtons()
end

-- With the prompts off, mode stays nil and Blizzard's buttons are never touched.
local function close()
	if not mode then return end
	unhover()
	mode = nil
	bar:Hide()
	ns.UpdateQuestButtons()
end

local OPENS = { QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete", QUEST_GREETING = "greeting" }

local watcher = CreateFrame("Frame")
for event in pairs(OPENS) do watcher:RegisterEvent(event) end
watcher:RegisterEvent("GOSSIP_SHOW")
watcher:RegisterEvent("QUEST_FINISHED")
watcher:RegisterEvent("GOSSIP_CLOSED")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
-- A gossip window closes as the quest it led to opens, and a quest as its gossip reopens, so each closes only its own.
watcher:SetScript("OnEvent", function(_, event)
	if OPENS[event] then
		open(OPENS[event], QuestFrame)
	elseif event == "GOSSIP_SHOW" then
		open("gossip", GossipFrame)
	elseif event == "PLAYER_REGEN_DISABLED" then
		close() -- a hidden frame hears nothing, so the pad is the player's again the moment combat starts
	elseif (event == "GOSSIP_CLOSED") == (mode == "gossip") then
		close()
	end
end)
