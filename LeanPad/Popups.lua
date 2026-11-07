local _, ns = ...

-- Blizzard's pop-ups answered from the pad: A presses the first button and B the second, named under the pop-up.
-- The presses are session-only override bindings that click the buttons, so they count as the player's own clicks and
-- a confirm that does something protected, such as entering a dungeon, still works. As with the dialogue window, the
-- pad is the player's bindings again in combat, where a pop-up waits for the cursor; one still up after is bound then.
local DIALOGS = {
	{ "StaticPopup1", "StaticPopup1Button1", "StaticPopup1Button2" },
	{ "StaticPopup2", "StaticPopup2Button1", "StaticPopup2Button2" },
	{ "StaticPopup3", "StaticPopup3Button1", "StaticPopup3Button2" },
	{ "StaticPopup4", "StaticPopup4Button1", "StaticPopup4Button2" },
	{ "LFGDungeonReadyDialog", "LFGDungeonReadyDialogEnterDungeonButton", "LFGDungeonReadyDialogLeaveQueueButton" },
	{ "ReadyCheckFrame", "ReadyCheckFrameYesButton", "ReadyCheckFrameNoButton" },
}
local KEYS = { "PAD1", "PAD2" }

local owner = CreateFrame("Frame")
local hint, answering

function ns.PopupAnswering() return answering ~= nil end

local function release()
	ClearOverrideBindings(owner)
	answering = nil
	if hint then hint:Hide() end
end

local function showHint(frame, names)
	if not hint then
		hint = ns.Panel(UIParent, ns.COLORS.panel, ns.COLORS.edge)
		hint:SetFrameStrata("FULLSCREEN_DIALOG")
		hint:SetHeight(30)
		hint.Text = ns.Text(hint, 13, ns.COLORS.text, "CENTER")
		hint.Text:SetPoint("CENTER")
	end
	local prompts = {}
	for i = 1, 2 do
		if names[i] then table.insert(prompts, ns.Glyphed(KEYS[i], _G[names[i]]:GetText(), 18)) end
	end
	hint.Text:SetText(table.concat(prompts, "    "))
	hint:SetWidth(hint.Text:GetStringWidth() + 32)
	hint:ClearAllPoints()
	hint:SetPoint("TOP", frame, "BOTTOM", 0, -6)
	hint:Show()
end

-- The first pop-up showing takes A and B, for whichever of its buttons show.
local function update()
	if InCombatLockdown() then return end
	release()
	if ns.UsesGamepadUI() or not ns.QuestPromptsEnabled() then return end
	for _, dialog in ipairs(DIALOGS) do
		local frame = _G[dialog[1]]
		if frame and frame:IsVisible() then
			local names = {}
			for i = 1, 2 do
				local button = _G[dialog[i + 1]]
				if button and button:IsVisible() then
					SetOverrideBindingClick(owner, true, KEYS[i], dialog[i + 1])
					names[i] = dialog[i + 1]
				end
			end
			if next(names) then
				answering = frame
				return showHint(frame, names)
			end
		end
	end
end
ns.UpdatePopups = update

for _, dialog in ipairs(DIALOGS) do
	local frame = _G[dialog[1]]
	if frame then
		frame:HookScript("OnShow", update)
		frame:HookScript("OnHide", update)
	end
end
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Combat's start is the last moment override bindings can change.
owner:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then return release() end
	update()
end)
