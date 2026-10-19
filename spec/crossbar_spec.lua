local wow = require("spec.wow")

describe("Crossbar", function()
	local ns, w, bar

	local function buttonFor(key)
		for _, widget in ipairs(w.widgets) do
			if rawget(widget, "Glyph") and widget.Glyph:GetText() == "text:" .. key then return widget end
		end
	end

	before_each(function()
		ns, w = wow.boot(nil)
		ns.Apply() -- LT is Shift, LT+A fires Action Bar 2 slot 7; give slot 1 of that bar an action
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
				assert.is_true(math.abs(point[2]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= 85, key)
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

		it("show the held layer's bar actions with glyph, icon, cooldowns and count", function()
			local button = buttonFor("PAD3")
			assert.is_true(button:IsShown())
			assert.equal(135808, button.Icon.texture)
			assert.equal("cooldown:61", button.Cooldown.duration)
			assert.equal("charge:61", button.ChargeCooldown.duration)
			assert.equal("2", button.Count:GetText())
			assert.is_false(button.Icon.desaturated)
			assert.is_true(button.Cooldown.hideNumbers)
		end)

		it("hide buttons that fire no bar action or an empty slot", function()
			assert.is_false(buttonFor("PAD1"):IsShown()) -- Jump
			assert.is_false(buttonFor("PAD4"):IsShown()) -- Action Bar 1 slot 2, not a Blizzard button here
			w.bindings.PAD3 = "ACTIONBUTTON1" -- a real button whose slot is empty
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_false(buttonFor("PAD3"):IsShown())
		end)

		it("switch to the layer of the held modifiers", function()
			assert.is_false(buttonFor("PAD1"):IsShown())
			w.held.shift = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.is_true(buttonFor("PAD1"):IsShown())
			w.held.shift = nil
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.is_false(buttonFor("PAD1"):IsShown())
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
			assert.is_false(buttonFor("PAD4"):IsShown())
			ActionButton1.action = 7
			wow.nextFrame()
			assert.is_true(buttonFor("PAD4"):IsShown())
			assert.equal(777, buttonFor("PAD4").Icon.texture)
		end)

		it("re-read Blizzard's buttons a frame after a loading screen", function()
			wow.nextFrame()
			bar:Fire("OnEvent", "PLAYER_ENTERING_WORLD")
			assert.equal(1, #w.nextFrame)
		end)

		it("keep text above both cooldown frames", function()
			local button = buttonFor("PAD3")
			assert.equal(button.ChargeCooldown:GetFrameLevel() + 1, button.Glyph.parent.level)
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
