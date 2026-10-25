local addonName, ns = ...

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	LeanPadDB = LeanPadDB or {}
	ns.db = LeanPadDB
	-- Profiles are account-wide, in LeanPadDB; each character keeps which one it uses and its spec links.
	LeanPadCharDB = LeanPadCharDB or { specs = {} }
	ns.char = LeanPadCharDB
end)

-- Names for Bindings.xml, which the client loads from the addon folder on its own.
BINDING_HEADER_LEANPAD = "LeanPad"
BINDING_NAME_LEANPAD_TOGGLE_CURSOR = "Toggle gamepad cursor"

-- The minimap's addon compartment entry, named in the TOC.
function LeanPad_OnCompartmentClick() ns.ToggleController() end

-- The Toggle gamepad cursor binding. Turning the cursor on puts it on the start spot set in settings, an x, y
-- offset in UI units from the screen's centre: the client lets addon code move the cursor once per pad press, and
-- this runs on one. SetCursorPosition takes the space GetCursorPosition returns, UI units times the UI scale, from
-- the bottom left: in game, UI units landed top right and screen fractions bottom left.
function LeanPad_ToggleCursor()
	local on = not IsGamePadCursorControlEnabled()
	SetGamePadCursorControl(on)
	local spot = ns.db.cursorStart
	if on and type(spot) == "table" then
		local scale = UIParent:GetEffectiveScale()
		SetCursorPosition((UIParent:GetWidth() / 2 + spot[1]) * scale, (UIParent:GetHeight() / 2 + spot[2]) * scale)
	end
end

SLASH_LEANPAD1 = "/lp"
SLASH_LEANPAD2 = "/leanpad"
SlashCmdList.LEANPAD = function(msg)
	if msg == "perf" then
		local M, get = Enum.AddOnProfilerMetric, C_AddOnProfiler.GetAddOnMetric
		print(("LeanPad ms/tick: session %.3f, recent %.3f, encounter %.3f, peak %.3f"):format(
			get(addonName, M.SessionAverageTime), get(addonName, M.RecentAverageTime),
			get(addonName, M.EncounterAverageTime), get(addonName, M.PeakTime)))
	elseif msg == "restore" then
		ns.OutOfCombat(ns.Restore)
	elseif msg == "undo" then
		ns.OutOfCombat(ns.UndoReset)
	elseif msg == "settings" then
		ns.OpenOptions()
	elseif msg:find("^profile ") then
		ns.SwitchProfile(msg:match("^profile%s+(.-)%s*$"))
	else
		ns.ToggleController()
	end
end
