local addonName, ns = ...

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")
	LeanPadDB = LeanPadDB or {}
	ns.db = LeanPadDB
end)

SLASH_LEANPAD1 = "/lp"
SlashCmdList.LEANPAD = function(msg)
	if msg == "perf" then
		local M, get = Enum.AddOnProfilerMetric, C_AddOnProfiler.GetAddOnMetric
		print(("LeanPad ms/tick: session %.3f, recent %.3f, encounter %.3f, peak %.3f"):format(
			get(addonName, M.SessionAverageTime), get(addonName, M.RecentAverageTime),
			get(addonName, M.EncounterAverageTime), get(addonName, M.PeakTime)))
	else
		print("LeanPad: /lp perf")
	end
end
