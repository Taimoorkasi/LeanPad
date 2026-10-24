local addonName, ns = ...

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	LeanPadDB = LeanPadDB or {}
	ns.db = LeanPadDB
end)

-- Names for Bindings.xml, which the client loads from the addon folder on its own.
BINDING_HEADER_LEANPAD = "LeanPad"
BINDING_NAME_LEANPAD_TOGGLE_CURSOR = "Toggle gamepad cursor"

-- The minimap's addon compartment entry, named in the TOC.
function LeanPad_OnCompartmentClick() ns.ToggleController() end

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
	else
		ns.ToggleController()
	end
end
