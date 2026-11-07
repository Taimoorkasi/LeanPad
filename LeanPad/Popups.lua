local _, ns = ...

-- Blizzard's pop-ups answered from the pad: the buttons showing, left to right, go to A, B, X and Y, named under the
-- pop-up. The presses are session-only override bindings that click the buttons, so they count as the player's own
-- clicks and a confirm that does something protected, such as entering a dungeon, still works. As with the dialogue
-- window, the pad is the player's bindings again in combat, where a pop-up waits for the cursor; one still up after is
-- bound then.
local KEYS = { "PAD1", "PAD2", "PAD3", "PAD4" }
local DIALOGS = {}
for i = 1, 4 do
	local name = "StaticPopup" .. i
	DIALOGS[i] = { name, name .. "Button1", name .. "Button2", name .. "Button3", name .. "Button4" }
end
table.insert(DIALOGS, { "LFGDungeonReadyDialog", "LFGDungeonReadyDialogEnterDungeonButton", "LFGDungeonReadyDialogLeaveQueueButton" })
table.insert(DIALOGS, { "ReadyCheckFrame", "ReadyCheckFrameYesButton", "ReadyCheckFrameNoButton" })

local owner = CreateFrame("Frame")
local hint, answering

-- Saved choice, else the same default as the dialogue window: on for Forever, off for retail.
function ns.PopupsEnabled()
	if ns.db.padPopups ~= nil then return ns.db.padPopups end
	return ns.QUEST_PROMPTS_DEFAULT == true
end

function ns.PopupAnswering() return answering ~= nil end

local function release()
	ClearOverrideBindings(owner)
	answering = nil
	if hint then hint:Hide() end
end

local function showHint(frame, names)
	if not hint then
		hint = ns.Panel(UIParent, ns.COLORS.bg)
		hint:SetFrameStrata("FULLSCREEN_DIALOG")
		hint:SetHeight(36)
		hint.Text = ns.Text(hint, 15, ns.COLORS.text, "CENTER")
		hint.Text:SetPoint("CENTER")
	end
	local prompts = {}
	for i, name in ipairs(names) do table.insert(prompts, ns.Glyphed(KEYS[i], _G[name]:GetText(), 22)) end
	hint.Text:SetText(table.concat(prompts, "      "))
	hint:SetWidth(hint.Text:GetStringWidth() + 40)
	hint:ClearAllPoints()
	hint:SetPoint("TOP", frame, "BOTTOM", 0, -8)
	hint:Show()
end

-- The first pop-up showing takes the pad, for whichever of its buttons show.
local function update()
	if InCombatLockdown() then return end
	release()
	if ns.UsesGamepadUI() or not ns.PopupsEnabled() then return end
	for _, dialog in ipairs(DIALOGS) do
		local frame = _G[dialog[1]]
		if frame and frame:IsVisible() then
			local names = {}
			for i = 2, #dialog do
				local button = _G[dialog[i]]
				if button and button:IsVisible() then
					table.insert(names, dialog[i])
					SetOverrideBindingClick(owner, true, KEYS[#names], dialog[i])
				end
			end
			if #names > 0 then
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
