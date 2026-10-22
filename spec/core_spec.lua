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

	it("registers /lp and /leanpad", function()
		wow.boot(nil)
		assert.equal("/lp", SLASH_LEANPAD1)
		assert.equal("/leanpad", SLASH_LEANPAD2)
		assert.is_function(SlashCmdList.LEANPAD)
	end)

	it("adds only globals that carry the LeanPad name, so nothing collides with other addons", function()
		wow.reset()
		local before = {}
		for name in pairs(_G) do before[name] = true end
		local ns = wow.loadAddon()
		LeanPadDB = {}
		wow.addonLoaded("LeanPad")
		wow.fire("PLAYER_ENTERING_WORLD")
		ns.ToggleController()
		ns.OpenOptions()
		local added = {}
		for name in pairs(_G) do
			if not before[name] then table.insert(added, name) end
		end
		assert.is_true(#added >= 6, table.concat(added, ", "))
		for _, name in ipairs(added) do
			assert.is_truthy(name:find("^LeanPad") or name:find("^LEANPAD") or name:find("^SLASH_LEANPAD") or name:find("^BINDING_%u+_LEANPAD"), name)
		end
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

	it("shows its logo in the addon list and the compartment, from a texture it ships", function()
		local icon = wow.tocHeader("IconTexture")
		assert.equal("Interface\\AddOns\\LeanPad\\Art\\Logo", icon)
		assert.is_truthy(io.open("LeanPad/Art/Logo.tga", "rb"))
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
