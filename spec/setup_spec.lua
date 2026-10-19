local wow = require("spec.wow")

-- Generic gamepad key names from Blizzard_SharedXML/SharedConstants.lua, build 12.1.5 (70448).
local PAD_KEYS = {}
for key in ([[PADDUP PADDRIGHT PADDDOWN PADDLEFT PAD1 PAD2 PAD3 PAD4 PAD5 PAD6 PADLSTICK PADRSTICK
	PADLSHOULDER PADRSHOULDER PADLTRIGGER PADRTRIGGER PADLSTICKUP PADLSTICKRIGHT PADLSTICKDOWN PADLSTICKLEFT
	PADRSTICKUP PADRSTICKRIGHT PADRSTICKDOWN PADRSTICKLEFT PADPADDLE1 PADPADDLE2 PADPADDLE3 PADPADDLE4
	PADFORWARD PADBACK PADSYSTEM PADSOCIAL]]):gmatch("%S+") do
	PAD_KEYS[key] = true
end

-- Binding commands LeanPad uses, as defined in Blizzard_FrameXML/Bindings_Standard.xml, build 12.1.5 (70448).
local COMMANDS = {}
for command in ([[JUMP INTERACTTARGET TARGETNEARESTENEMY TARGETPREVIOUSENEMY TOGGLEAUTORUN OPENALLBAGS
	TOGGLEGAMEMENU TOGGLEWORLDMAP TOGGLECHARACTER0 TOGGLESPELLBOOK]]):gmatch("%S+") do
	COMMANDS[command] = true
end
for i = 1, 12 do
	COMMANDS["ACTIONBUTTON" .. i] = true
	for bar = 1, 7 do COMMANDS["MULTIACTIONBAR" .. bar .. "BUTTON" .. i] = true end
end

local MODIFIER_PREFIXES = { [""] = true, ["SHIFT-"] = true, ["CTRL-"] = true, ["CTRL-SHIFT-"] = true }

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

describe("Setup", function()
	local ns, w
	before_each(function() ns, w = wow.boot(nil) end)
	after_each(wow.restore)

	describe("preset", function()
		it("uses only real pad keys, modifier prefixes and binding commands", function()
			for key, action in pairs(ns.BINDINGS) do
				local prefix, button = key:match("^(.-)(PAD.*)$")
				assert.is_truthy(button, key)
				assert.is_true(MODIFIER_PREFIXES[prefix], "modifier prefix of " .. key)
				assert.is_true(PAD_KEYS[button], "pad key " .. key)
				assert.is_true(COMMANDS[action], "command " .. action)
			end
		end)

		it("binds 17 base keys plus three 8-slot crossbar layers", function()
			assert.equal(17 + 3 * 8, count(ns.BINDINGS))
		end)

		it("maps each trigger layer onto slots 1-8 of its own Blizzard bar, clockwise from the top", function()
			local cross = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT", "PAD4", "PAD2", "PAD1", "PAD3" }
			local layers = { ["SHIFT-"] = 1, ["CTRL-"] = 2, ["CTRL-SHIFT-"] = 3 }
			for prefix, bar in pairs(layers) do
				for slot, key in ipairs(cross) do
					assert.equal(("MULTIACTIONBAR%dBUTTON%d"):format(bar, slot), ns.BINDINGS[prefix .. key])
				end
			end
		end)

		it("makes the triggers Shift and Ctrl and keeps cursor clicks off them", function()
			assert.equal("1", ns.CVARS.GamePadEnable)
			assert.equal("PADLTRIGGER", ns.CVARS.GamePadEmulateShift)
			assert.equal("PADRTRIGGER", ns.CVARS.GamePadEmulateCtrl)
			for _, cvar in ipairs({ "GamePadCursorLeftClick", "GamePadCursorRightClick" }) do
				assert.not_equal(ns.CVARS.GamePadEmulateShift, ns.CVARS[cvar])
				assert.not_equal(ns.CVARS.GamePadEmulateCtrl, ns.CVARS[cvar])
			end
		end)

		it("turns on gamepad soft targeting for enemies, friends and interact", function()
			for _, cvar in ipairs({ "SoftTargetEnemy", "SoftTargetFriend", "SoftTargetInteract" }) do
				assert.equal("1", ns.CVARS[cvar])
			end
		end)
	end)

	describe("OutOfCombat", function()
		it("runs right away out of combat", function()
			local ran = 0
			ns.OutOfCombat(function() ran = ran + 1 end)
			assert.equal(1, ran)
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal(1, ran)
		end)

		it("waits for PLAYER_REGEN_ENABLED in combat", function()
			local ran = 0
			w.combat = true
			ns.OutOfCombat(function() ran = ran + 1 end)
			assert.equal(0, ran)
			assert.same({ "LeanPad: will apply when combat ends." }, w.printed)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal(1, ran)
		end)
	end)

	describe("Apply", function()
		it("writes every CVar and binding and saves the current binding set", function()
			w.bindingSet = Enum.BindingSet.Character
			ns.Apply()
			for cvar, value in pairs(ns.CVARS) do assert.equal(value, w.cvars[cvar]) end
			for key, action in pairs(ns.BINDINGS) do assert.equal(action, w.bindings[key]) end
			assert.same({ Enum.BindingSet.Character }, w.saved)
			assert.matches("controller set up", w.printed[1])
		end)

		it("backs up the previous values of everything it touches", function()
			w.cvars.GamePadEmulateCtrl = "PADLSHOULDER"
			w.bindings.PAD1 = "MOVEFORWARD"
			ns.Apply()
			assert.equal("PADLSHOULDER", ns.db.backup.cvars.GamePadEmulateCtrl)
			assert.equal("MOVEFORWARD", ns.db.backup.bindings.PAD1)
			assert.equal("", ns.db.backup.bindings["CTRL-SHIFT-PAD3"])
			assert.equal(count(ns.BINDINGS), count(ns.db.backup.bindings))
		end)

		it("keeps the first backup when run again", function()
			w.bindings.PAD1 = "MOVEFORWARD"
			ns.Apply()
			ns.Apply()
			assert.equal("MOVEFORWARD", ns.db.backup.bindings.PAD1)
		end)
	end)

	describe("Restore", function()
		it("says so when there is nothing to restore", function()
			ns.Restore()
			assert.same({ "LeanPad: nothing to restore." }, w.printed)
			assert.same({}, w.saved)
		end)

		it("puts back CVars and bindings, unbinding keys that were free, then drops the backup", function()
			w.cvars.GamePadEnable = "0"
			w.bindings.PAD1 = "MOVEFORWARD"
			ns.Apply()
			ns.Restore()
			assert.equal("0", w.cvars.GamePadEnable)
			assert.equal("MOVEFORWARD", w.bindings.PAD1)
			assert.is_nil(w.bindings["SHIFT-PADDUP"])
			assert.is_nil(ns.db.backup)
			assert.same({ Enum.BindingSet.Account, Enum.BindingSet.Account }, w.saved)
			assert.matches("restored", w.printed[2])
		end)
	end)

	describe("setup prompt", function()
		it("is a confirm dialog that applies on accept", function()
			local dialog = StaticPopupDialogs.LEANPAD_SETUP
			assert.equal(ACCEPT, dialog.button1)
			assert.equal(CANCEL, dialog.button2)
			assert.equal(0, dialog.timeout)
			assert.is_true(dialog.whileDead)
			assert.is_true(dialog.hideOnEscape)
			dialog.OnAccept()
			assert.equal("PADRTRIGGER", w.cvars.GamePadEmulateCtrl)
		end)

		it("defers accepting until combat ends", function()
			w.combat = true
			StaticPopupDialogs.LEANPAD_SETUP.OnAccept()
			assert.is_nil(w.cvars.GamePadEnable)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal("1", w.cvars.GamePadEnable)
		end)

		it("shows once on the first login", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.same({ "LEANPAD_SETUP" }, w.popups)
			assert.is_true(ns.db.prompted)
		end)

		it("does not show again in a later session", function()
			ns, w = wow.boot({ prompted = true })
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.same({}, w.popups)
		end)
	end)
end)
