local wow = require("spec.wow")

describe("Core", function()
	after_each(wow.restore)

	it("creates LeanPadDB on first load and shares it as ns.db", function()
		local ns = wow.boot(nil)
		assert.same({}, LeanPadDB)
		assert.equal(LeanPadDB, ns.db)
	end)

	it("keeps saved variables from a previous session", function()
		local ns = wow.boot({ prompted = true })
		assert.is_true(ns.db.prompted)
	end)

	it("registers /lp", function()
		wow.boot(nil)
		assert.equal("/lp", SLASH_LEANPAD1)
		assert.is_function(SlashCmdList.LEANPAD)
	end)

	it("/lp perf prints the addon's own profiler averages", function()
		local _, w = wow.boot(nil)
		SlashCmdList.LEANPAD("perf")
		assert.same({ "LeanPad ms/tick: session 0.500, recent 1.500, encounter 2.500, peak 4.500" }, w.printed)
		local M = Enum.AddOnProfilerMetric
		assert.same({
			{ "LeanPad", M.SessionAverageTime }, { "LeanPad", M.RecentAverageTime },
			{ "LeanPad", M.EncounterAverageTime }, { "LeanPad", M.PeakTime },
		}, w.metricCalls)
	end)

	it("/lp with anything else opens the LeanPad settings page", function()
		local _, w = wow.boot(nil)
		SlashCmdList.LEANPAD("")
		SlashCmdList.LEANPAD("help")
		assert.same({ 42, 42 }, w.opened)
	end)
end)
