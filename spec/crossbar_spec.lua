local wow = require("spec.wow")

describe("Crossbar", function()
	local ns, w, bar

	-- Crossbar buttons in creation order; ns.CROSSBAR keys are iterated with pairs, so find them by position.
	local function buttonFor(key)
		local point = ns.CROSSBAR[key]
		for _, widget in ipairs(w.widgets) do
			local p = rawget(widget, "point")
			if rawget(widget, "Face") and p and p[4] == point[1] and p[5] == point[2] then return widget end
		end
	end

	before_each(function()
		ns, w = wow.boot(nil)
		ns.Apply() -- LT is Shift, RT is Ctrl
		w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
		w.bindings.PAD3 = "MULTIACTIONBAR1BUTTON1"
	end)
	after_each(wow.restore)

	describe("layout", function()
		it("covers the D-pad, face buttons, shoulders, triggers and stick clicks without overlap", function()
			local keys = {}
			for key in pairs(ns.CROSSBAR) do table.insert(keys, key) end
			assert.equal(14, #keys)
			local size = ns.CROSSBAR_BUTTON_SIZE
			for _, a in ipairs(keys) do
				for _, b in ipairs(keys) do
					if a ~= b then
						local pa, pb = ns.CROSSBAR[a], ns.CROSSBAR[b]
						local apart = math.abs(pa[1] - pb[1]) >= size or math.abs(pa[2] - pb[2]) >= size
						assert.is_true(apart, a .. " overlaps " .. b)
					end
				end
			end
		end)

		it("fits every button inside the bar", function()
			for key, point in pairs(ns.CROSSBAR) do
				assert.is_true(math.abs(point[1]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= 220, key)
				assert.is_true(math.abs(point[2]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= 90, key)
			end
		end)
	end)

	describe("on login", function()
		it("shows by default", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
			assert.is_true(bar:IsShown())
			assert.same({ "BOTTOM", UIParent, "BOTTOM", 0, 220 }, bar.point)
			assert.is_true(bar.events.MODIFIER_STATE_CHANGED)
			assert.is_true(bar.events.ACTIONBAR_UPDATE_COOLDOWN)
			assert.is_true(bar.events.ACTIONBAR_PAGE_CHANGED)
			assert.is_true(bar.events.GAME_PAD_ACTIVE_CHANGED)
		end)

		it("stays hidden when the player turned it off", function()
			ns, w = wow.boot({ crossbar = false, prompted = true })
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_false(LeanPadCrossbar:IsShown())
			assert.same({}, LeanPadCrossbar.events)
		end)
	end)

	describe("buttons", function()
		before_each(function()
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
		end)

		it("are round: circle-masked icon, round cooldown sweeps and a ring", function()
			local button = buttonFor("PAD3")
			local mask
			for _, widget in ipairs(w.widgets) do
				if widget.kind == "MaskTexture" and widget.parent == button.Face then mask = widget end
			end
			assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", mask.texture)
			assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", button.Cooldown.swipeTexture)
			assert.is_true(button.Cooldown.circularEdge)
			assert.is_true(button.ChargeCooldown.circularEdge)
			assert.equal("talents-node-circle-gray", button.Ring.atlas)
		end)

		it("show buttons that fire a bar action on any layer, plus the layer modifiers, and hide the rest", function()
			local shown = {}
			for key in pairs(ns.CROSSBAR) do
				if buttonFor(key):IsShown() then table.insert(shown, key) end
			end
			table.sort(shown)
			-- PAD3 on Base, PAD1 and PADDUP on LT; LT and RT switch layers. The fake has two Blizzard bar buttons.
			assert.same({ "PAD1", "PAD3", "PADDUP", "PADLTRIGGER", "PADRTRIGGER" }, shown)
		end)

		it("show a button with nothing on the held layer as a dark disc", function()
			local jump = buttonFor("PAD1") -- Jump on Base, a bar action on LT
			assert.is_true(jump:IsShown())
			assert.is_nil(jump.Icon.texture)
			assert.same({ 0, 0, 0, 0.6 }, jump.Icon.color)
			assert.is_nil(jump.slot)
		end)

		it("show and hide buttons as bindings change", function()
			assert.is_false(buttonFor("PAD2"):IsShown())
			w.bindings["CTRL-PAD2"] = "ACTIONBUTTON1"
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_true(buttonFor("PAD2"):IsShown())
		end)

		it("show the held layer's bar actions with icon, cooldowns and count", function()
			local button = buttonFor("PAD3")
			assert.equal(135808, button.Icon.texture)
			assert.equal("cooldown:61", button.Cooldown.duration)
			assert.equal("charge:61", button.ChargeCooldown.duration)
			assert.equal("2", button.Count:GetText())
			assert.is_false(button.Icon.desaturated)
			assert.is_true(button.Cooldown.hideNumbers)
		end)

		it("clear sweeps for actions without a cooldown or charge duration", function()
			w.actions[61].cooldown, w.actions[61].charge = nil, nil
			bar:Fire("OnEvent", "ACTIONBAR_UPDATE_COOLDOWN")
			local button = buttonFor("PAD3")
			assert.is_nil(button.Cooldown.duration)
			assert.is_nil(button.ChargeCooldown.duration)
			assert.same({}, w.errors)
		end)

		it("show the controller's own glyph atlas, or none when the key has no glyph", function()
			assert.is_false(buttonFor("PAD3").Glyph:IsShown())
			local getText = _G.GetBindingText -- busted sandboxes spec globals; the addon reads _G
			_G.GetBindingText = function(key) return "|A:Gamepad_Shp_" .. key .. "_64:24:24|a" end
			bar:Fire("OnEvent", "GAME_PAD_ACTIVE_CHANGED")
			assert.is_true(buttonFor("PAD3").Glyph:IsShown())
			assert.equal("Gamepad_Shp_PAD3_64", buttonFor("PAD3").Glyph.atlas)
			_G.GetBindingText = getText
		end)

		it("switch to the layer of the held modifiers and light up the held modifier", function()
			assert.is_nil(buttonFor("PAD1").slot)
			w.held.shift = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal(61, buttonFor("PAD1").slot)
			assert.equal("talents-node-circle-yellow", buttonFor("PADLTRIGGER").Ring.atlas)
			assert.equal(ns.CROSSBAR_PRESSED_SCALE, buttonFor("PADLTRIGGER").Face.scale)
			assert.equal("talents-node-circle-gray", buttonFor("PADRTRIGGER").Ring.atlas)
			w.held.shift = nil
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.is_nil(buttonFor("PAD1").slot)
			assert.equal(1, buttonFor("PADLTRIGGER").Face.scale)
		end)

		it("press in and light up while Blizzard's button is pushed", function()
			local button = buttonFor("PAD3")
			MultiBarBottomLeftButton1:SetButtonState("PUSHED")
			assert.equal(ns.CROSSBAR_PRESSED_SCALE, button.Face.scale)
			assert.equal("talents-node-circle-yellow", button.Ring.atlas)
			assert.equal(1, buttonFor("PAD4").Face.scale)
			MultiBarBottomLeftButton1:SetButtonState("NORMAL")
			assert.equal(1, button.Face.scale)
			assert.equal("talents-node-circle-gray", button.Ring.atlas)
		end)

		it("hook each Blizzard button once, however often the bar refreshes", function()
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal(1, w.hooks)
		end)

		it("show countdown numbers when Blizzard's countdown option is on", function()
			w.cvars.countdownForCooldowns = "1"
			bar:Fire("OnEvent", "CVAR_UPDATE")
			assert.is_false(buttonFor("PAD3").Cooldown.hideNumbers)
		end)

		it("update cooldowns, count and usability on state events without a full refresh", function()
			w.actions[61].cooldown = "cooldown:61b"
			w.actions[61].count = "1"
			w.actions[61].usable = false
			w.actions[61].texture = 999 -- not re-read on a state event
			bar:Fire("OnEvent", "ACTIONBAR_UPDATE_COOLDOWN")
			local button = buttonFor("PAD3")
			assert.equal("cooldown:61b", button.Cooldown.duration)
			assert.equal("1", button.Count:GetText())
			assert.is_true(button.Icon.desaturated)
			assert.equal(135808, button.Icon.texture)
		end)

		it("empty a button whose action is gone", function()
			w.bindings.PAD3 = "ACTIONBUTTON1" -- a real button whose slot is empty
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			local button = buttonFor("PAD3")
			assert.is_nil(button.slot)
			assert.is_nil(button.Icon.texture)
			assert.is_nil(button.Cooldown.duration)
			assert.equal("", button.Count:GetText())
		end)

		it("re-read Blizzard's buttons a frame after an action bar page change", function()
			MultiBarBottomLeftButton1.action = 62
			w.actions[62] = { texture = 4242 }
			bar:Fire("OnEvent", "ACTIONBAR_PAGE_CHANGED")
			assert.equal(135808, buttonFor("PAD3").Icon.texture)
			wow.nextFrame()
			assert.equal(4242, buttonFor("PAD3").Icon.texture)
		end)

		it("re-read Blizzard's buttons a frame after login, when the main bar gets its slots", function()
			ns, w = wow.boot({ prompted = true })
			ActionButton1.action = nil -- not yet pointed at a slot when PLAYER_ENTERING_WORLD reaches LeanPad
			w.actions[7] = { texture = 777 }
			w.bindings.PAD4 = "ACTIONBUTTON1"
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(buttonFor("PAD4").slot)
			ActionButton1.action = 7
			wow.nextFrame()
			assert.equal(777, buttonFor("PAD4").Icon.texture)
		end)

		it("re-read Blizzard's buttons a frame after a loading screen", function()
			wow.nextFrame()
			bar:Fire("OnEvent", "PLAYER_ENTERING_WORLD")
			assert.equal(1, #w.nextFrame)
		end)

		it("keep refreshing the other buttons when one errors, and report it", function()
			w.bindings.PAD4 = "MULTIACTIONBAR1BUTTON1"
			local getCount = C_ActionBar.GetActionDisplayCount
			C_ActionBar.GetActionDisplayCount = function() error("boom") end
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal(2, #w.errors)
			assert.equal(135808, buttonFor("PAD3").Icon.texture)
			assert.equal(135808, buttonFor("PAD4").Icon.texture)
			bar:Fire("OnEvent", "ACTIONBAR_UPDATE_COOLDOWN")
			assert.equal(4, #w.errors)
			C_ActionBar.GetActionDisplayCount = getCount
		end)

		it("leave a button empty when its refresh fails before it knows its action", function()
			local hasAction = C_ActionBar.HasAction
			C_ActionBar.HasAction = function() error("boom") end
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_nil(buttonFor("PAD3").slot)
			assert.is_nil(buttonFor("PAD3").Icon.texture)
			assert.equal(1, #w.errors)
			C_ActionBar.HasAction = hasAction
		end)

		it("keep ring, glyph and count above both cooldown frames", function()
			local button = buttonFor("PAD3")
			assert.equal(button.ChargeCooldown:GetFrameLevel() + 1, button.Ring.parent.level)
			assert.equal(button.Ring.parent, button.Glyph.parent)
			assert.equal(button.Ring.parent, button.Count.parent)
		end)
	end)

	describe("setting", function()
		local setting
		before_each(function()
			for _, control in ipairs(w.controls) do
				if control.variable == "LEANPAD_SHOW_CROSSBAR" then setting = control.setting end
			end
		end)

		it("is a checkbox, on by default", function()
			assert.equal("boolean", setting.type)
			assert.is_true(setting.default)
			assert.is_true(setting.getValue())
		end)

		it("hides and shows the bar and remembers the choice", function()
			setting.setValue(false)
			assert.is_false(ns.db.crossbar)
			assert.is_false(setting.getValue())
			assert.is_false(LeanPadCrossbar:IsShown())
			assert.same({}, LeanPadCrossbar.events)
			setting.setValue(true)
			assert.is_true(LeanPadCrossbar:IsShown())
		end)
	end)
end)
