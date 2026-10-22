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

	it("/lp restore restores the saved layout, after combat if needed", function()
		local ns, w = wow.boot(nil)
		w.bindings.PAD1 = "SITORSTAND"
		ns.Apply()
		w.combat = true
		SlashCmdList.LEANPAD("restore")
		assert.equal("JUMP", w.bindings.PAD1)
		w.combat = false
		wow.fire("PLAYER_REGEN_ENABLED")
		assert.equal("SITORSTAND", w.bindings.PAD1)
	end)

	it("/lp settings opens the window on its settings page", function()
		wow.boot(nil)
		SlashCmdList.LEANPAD("settings")
		assert.is_true(LeanPadControllerFrame:IsShown())
		assert.is_true(LeanPadControllerFrame.Options:IsShown())
		assert.is_false(LeanPadControllerFrame.Editor:IsShown())
	end)

	it("opens the editor from the minimap's addon compartment", function()
		wow.boot(nil)
		assert.is_truthy(wow.tocHeader("AddonCompartmentFunc"))
		_G[wow.tocHeader("AddonCompartmentFunc")]()
		assert.is_true(LeanPadControllerFrame:IsShown())
	end)

	it("/lp toggles the controller editor", function()
		wow.boot(nil)
		SlashCmdList.LEANPAD("")
		assert.is_true(LeanPadControllerFrame:IsShown())
		SlashCmdList.LEANPAD("anything")
		assert.is_false(LeanPadControllerFrame:IsShown())
	end)
end)
