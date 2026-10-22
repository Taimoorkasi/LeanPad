local wow = require("spec.wow")

describe("Play style", function()
	local ns, w
	before_each(function() ns, w = wow.boot(nil) end)
	after_each(wow.restore)

	local function specWatcher()
		for _, widget in ipairs(w.widgets) do
			if widget.events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED then return widget end
		end
	end

	it("reads the spec: tank and healer by role, damage by whether the spec casts from range", function()
		assert.equal("ranged", ns.SpecStyle()) -- Beast Mastery
		w.specID = 255 -- Survival
		assert.equal("melee", ns.SpecStyle())
		w.role = "TANK"
		assert.equal("tank", ns.SpecStyle())
		w.role = "HEALER"
		assert.equal("healer", ns.SpecStyle())
		w.spec = nil
		assert.is_nil(ns.SpecStyle())
	end)

	it("has a preset per style that only touches combat facing and soft targeting", function()
		for _, style in ipairs({ "tank", "melee", "ranged", "healer" }) do
			local preset = ns.PLAYSTYLES[style]
			assert.is_string(preset.GamePadFaceMovementMaxAngleCombat, style)
			assert.is_string(preset.SoftTargetEnemyArc, style)
			for cvar in pairs(preset) do assert.is_truthy(cvar:find("^GamePad") or cvar:find("^SoftTarget"), cvar) end
		end
		assert.equal("180", ns.PLAYSTYLES.tank.GamePadFaceMovementMaxAngleCombat)
		assert.equal("0", ns.PLAYSTYLES.healer.GamePadFaceMovementMaxAngleCombat)
		assert.equal("1", ns.PLAYSTYLES.healer.SoftTargetFriend)
	end)

	it("writes nothing until a style is chosen, or while Auto has no spec to read", function()
		wow.fire("PLAYER_ENTERING_WORLD")
		assert.is_nil(w.cvars.GamePadFaceMovementMaxAngleCombat)
		ns.db.playstyle = "auto"
		w.spec = nil
		ns.ApplyPlaystyle()
		specWatcher():Fire("OnEvent", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
		assert.is_nil(w.cvars.GamePadFaceMovementMaxAngleCombat)
	end)

	it("applies the chosen style at login and follows spec changes on Auto, out of combat", function()
		ns, w = wow.boot({ playstyle = "auto", prompted = true })
		wow.fire("PLAYER_ENTERING_WORLD")
		assert.equal("115", w.cvars.GamePadFaceMovementMaxAngleCombat) -- ranged
		assert.equal("2", w.cvars.SoftTargetEnemyArc)
		w.role = "TANK"
		w.combat = true
		specWatcher():Fire("OnEvent", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
		assert.equal("115", w.cvars.GamePadFaceMovementMaxAngleCombat)
		w.combat = false
		wow.fire("PLAYER_REGEN_ENABLED")
		assert.equal("180", w.cvars.GamePadFaceMovementMaxAngleCombat)
		assert.equal("1", w.cvars.SoftTargetEnemyArc)
		ns.db.playstyle = "healer" -- a fixed style ignores spec changes
		specWatcher():Fire("OnEvent", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
		assert.equal("180", w.cvars.GamePadFaceMovementMaxAngleCombat)
		ns.ApplyPlaystyle()
		assert.equal("0", w.cvars.GamePadFaceMovementMaxAngleCombat)
	end)
end)
