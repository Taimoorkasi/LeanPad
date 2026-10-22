local wow = require("spec.wow")

describe("Crossbar", function()
	local ns, w, bar

	-- Cluster frames in creation order, which is ns.Layers() order.
	local function clusters()
		local found = {}
		for _, widget in ipairs(w.widgets) do
			if rawget(widget, "buttons") then table.insert(found, widget) end
		end
		return found
	end

	local function buttonFor(key, index)
		return clusters()[index or 1].buttons[key]
	end

	local function label(index)
		for _, widget in ipairs(w.widgets) do
			if widget.kind == "FontString" and widget.parent == clusters()[index] then return widget:GetText() end
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

		it("fits every button inside its cluster", function()
			for key, point in pairs(ns.CROSSBAR) do
				assert.is_true(math.abs(point[1]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= 230, key)
				assert.is_true(math.abs(point[2]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= 110, key)
			end
		end)

		it("keeps clusters apart even when one is held at full size", function()
			local half = { 230, 110 }
			for a, pa in ipairs(ns.CROSSBAR_CLUSTERS) do
				for b, pb in ipairs(ns.CROSSBAR_CLUSTERS) do
					if a ~= b then
						local apart = math.abs(pa[1] - pb[1]) >= half[1] * (1 + ns.CROSSBAR_IDLE_SCALE)
							or math.abs(pa[2] - pb[2]) >= half[2] * (1 + ns.CROSSBAR_IDLE_SCALE)
						assert.is_true(apart, a .. " overlaps " .. b)
					end
				end
			end
		end)
	end)

	describe("on login", function()
		it("shows by default", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
			assert.is_true(bar:IsShown())
			assert.same({ "BOTTOM", UIParent, "BOTTOM", 0, 60 }, bar.point)
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

		it("are round: circle-masked icon and rim, round cooldown sweeps", function()
			local button = buttonFor("PAD3")
			local masks = 0
			for _, widget in ipairs(w.widgets) do
				if widget.kind == "MaskTexture" and widget.parent == button.Face then
					assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", widget.texture)
					masks = masks + 1
				end
			end
			assert.equal(2, masks) -- icon and rim
			assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", button.Cooldown.swipeTexture)
			assert.is_true(button.Cooldown.circularEdge)
			assert.is_true(button.ChargeCooldown.circularEdge)
			assert.same({ 0.05, 0.05, 0.05, 0.9 }, button.Rim.color)
		end)

		it("show buttons with a bar action or a faced command on any layer, plus the layer buttons as hints", function()
			local shown = {}
			for key in pairs(ns.CROSSBAR) do
				if buttonFor(key):IsShown() then table.insert(shown, key) end
			end
			table.sort(shown)
			-- Bar actions: PAD3 on Base, PAD1 and PADDUP on LT. Faced commands: interact, targeting, the cursor toggle.
			-- Auto-run and the shoulders' missing bar buttons stay hidden.
			assert.same({ "PAD1", "PAD2", "PAD3", "PADDLEFT", "PADDRIGHT", "PADDUP", "PADLTRIGGER", "PADRSTICK", "PADRTRIGGER" }, shown)
		end)

		it("give commands off the bars a Blizzard face with a badge, and no cooldown or press", function()
			local right = buttonFor("PADDRIGHT") -- Target nearest enemy in the preset
			assert.equal("Crosshair_Attack_64", right.Icon.atlas)
			assert.equal("|A:common-icon-forwardarrow:12:12|a", right.Count:GetText())
			assert.equal(1, right.alpha)
			assert.is_nil(right.slot)
			assert.equal("|A:common-icon-backarrow:12:12|a", buttonFor("PADDLEFT").Count:GetText())
			assert.equal("common-icon-move", buttonFor("PADRSTICK").Icon.atlas)
			assert.is_false(buttonFor("PADLSTICK"):IsShown())
		end)

		it("show a layer button as a hint socket, lit while held, never its stale action", function()
			w.bindings.PADRTRIGGER = "ACTIONBUTTON1"
			w.glyphs.PADRTRIGGER = "|A:Gamepad_Shp_RTrigger_64:0:0|a"
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			local rt = buttonFor("PADRTRIGGER")
			assert.is_true(rt:IsShown())
			assert.is_nil(rt.Icon.texture)
			assert.is_true(rt.BigGlyph:IsShown())
			assert.equal("Gamepad_Shp_RTrigger_64", rt.BigGlyph.atlas)
			assert.is_false(rt.Glyph:IsShown())
			assert.equal("Ctrl", rt.Hint:GetText())
			assert.is_true(rt.Hint:IsShown())
			assert.equal(1, rt.alpha)
			assert.same(ns.RIM, rt.Rim.color)
			w.held.ctrl = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.same(ns.RIM_LIT, rt.Rim.color)
			w.held.ctrl = false
			w.cvars.GamePadEmulateCtrl = "none" -- no longer a layer button: its own action shows again
			bar:Fire("OnEvent", "CVAR_UPDATE")
			assert.is_true(rt:IsShown())
			assert.is_false(rt.Hint:IsShown())
			assert.is_false(rt.BigGlyph:IsShown())
		end)

		it("show a button with nothing on the held layer as a faint empty slot", function()
			local jump = buttonFor("PAD1") -- Jump on Base, a bar action on LT
			assert.is_true(jump:IsShown())
			assert.equal(ns.CROSSBAR_EMPTY_ALPHA, jump.alpha)
			assert.is_nil(jump.Icon.texture)
			assert.is_nil(jump.slot)
		end)

		it("show and hide buttons as bindings change", function()
			assert.is_false(buttonFor("PADLSHOULDER"):IsShown())
			w.bindings["CTRL-PADLSHOULDER"] = "ACTIONBUTTON1"
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_true(buttonFor("PADLSHOULDER"):IsShown())
		end)

		it("show the held layer's bar actions with icon, cooldowns and count", function()
			local button = buttonFor("PAD3")
			assert.equal(1, button.alpha)
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

		it("press in, flash and turn the rim gold while Blizzard's button is pushed", function()
			local button = buttonFor("PAD3")
			MultiBarBottomLeftButton1:SetButtonState("PUSHED")
			assert.equal(ns.CROSSBAR_PRESSED_SCALE, button.Face.scale)
			assert.is_true(button.Flash:IsShown())
			assert.same({ 1, 0.82, 0, 1 }, button.Rim.color)
			assert.is_false(buttonFor("PAD1").Flash:IsShown())
			MultiBarBottomLeftButton1:SetButtonState("NORMAL")
			assert.equal(1, button.Face.scale)
			assert.is_false(button.Flash:IsShown())
			assert.same({ 0.05, 0.05, 0.05, 0.9 }, button.Rim.color)
		end)

		it("stay pressed through a refresh while Blizzard's button is still pushed", function()
			MultiBarBottomLeftButton1:SetButtonState("PUSHED")
			bar:Fire("OnEvent", "ACTIONBAR_SLOT_CHANGED")
			assert.is_true(buttonFor("PAD3").Flash:IsShown())
			MultiBarBottomLeftButton1:SetButtonState("NORMAL")
			assert.is_false(buttonFor("PAD3").Flash:IsShown())
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

		it("keep flash, glyph and count above both cooldown frames", function()
			local button = buttonFor("PAD3")
			assert.equal(button.ChargeCooldown:GetFrameLevel() + 1, button.Flash.parent.level)
			assert.equal(button.Flash.parent, button.Glyph.parent)
			assert.equal(button.Flash.parent, button.Count.parent)
		end)
	end)

	describe("held layer only (default)", function()
		before_each(function()
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
		end)

		it("shows one full-size cluster with no label on Base", function()
			local all = clusters()
			assert.is_true(all[1]:IsShown())
			for index = 2, #all do assert.is_false(all[index]:IsShown()) end
			assert.equal(1, all[1].scale)
			assert.equal(1, all[1].alpha)
			assert.equal("", label(1))
		end)

		it("switches to the held layer and labels it with its modifier", function()
			assert.is_nil(buttonFor("PAD1").slot)
			w.held.shift = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal(61, buttonFor("PAD1").slot)
			assert.equal("text:PADLTRIGGER", label(1))
			w.held.shift = nil
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.is_nil(buttonFor("PAD1").slot)
		end)

		it("still shows a held modifier combination that has no layer of its own", function()
			w.held.alt = true -- Alt isn't emulated by the preset
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal("Base", label(1))
		end)
	end)

	describe("all layers", function()
		before_each(function()
			ns.db.crossbarStyle = "all"
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
		end)

		it("shows a labelled cluster per layer, Base full size, the rest dimmed", function()
			local all = clusters()
			assert.equal(4, #all)
			for _, cluster in ipairs(all) do assert.is_true(cluster:IsShown()) end
			assert.equal(1, all[1].scale)
			assert.equal(ns.CROSSBAR_IDLE_SCALE, all[2].scale)
			assert.equal(ns.CROSSBAR_IDLE_ALPHA, all[2].alpha)
			assert.equal("", label(1))
			assert.equal("text:PADLTRIGGER", label(2))
			assert.equal("text:PADRTRIGGER", label(3))
			assert.equal("text:PADLTRIGGER + text:PADRTRIGGER", label(4))
			assert.equal(61, buttonFor("PAD1", 2).slot)
		end)

		it("keeps each cluster centred on its slot whatever its scale", function()
			local all = clusters()
			local slot = ns.CROSSBAR_CLUSTERS[2]
			assert.same({ "CENTER", bar, "CENTER", slot[1] / ns.CROSSBAR_IDLE_SCALE, slot[2] / ns.CROSSBAR_IDLE_SCALE }, all[2].point)
		end)

		it("brings the held layer to full size and dims Base", function()
			w.held.shift = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			local all = clusters()
			assert.equal(1, all[2].scale)
			assert.equal(ns.CROSSBAR_IDLE_SCALE, all[1].scale)
		end)

		it("hides clusters for layers that don't exist", function()
			w.cvars.GamePadEmulateCtrl = "none"
			bar:Fire("OnEvent", "CVAR_UPDATE")
			local all = clusters()
			assert.is_true(all[2]:IsShown())
			assert.is_false(all[3]:IsShown())
			assert.is_false(all[4]:IsShown())
		end)
	end)

	describe("settings", function()
		it("Show crossbar hides and shows the bar and remembers the choice", function()
			ns.SetCrossbarShown(false)
			assert.is_false(ns.db.crossbar)
			assert.is_false(LeanPadCrossbar:IsShown())
			assert.same({}, LeanPadCrossbar.events)
			ns.SetCrossbarShown(true)
			assert.is_true(LeanPadCrossbar:IsShown())
		end)

		it("Crossbar layers redraws the shown bar straight away", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			ns.SetCrossbarStyle("all")
			assert.equal("all", ns.db.crossbarStyle)
			assert.is_true(clusters()[4]:IsShown())
		end)

		it("Crossbar layers is remembered while the bar is hidden", function()
			ns.SetCrossbarStyle("all")
			assert.equal("all", ns.db.crossbarStyle)
			assert.is_nil(LeanPadCrossbar)
		end)

		it("scales the bar and remembers the size", function()
			ns.SetCrossbarScale(0.8)
			assert.equal(0.8, ns.db.crossbarScale)
			assert.is_nil(LeanPadCrossbar)
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.equal(0.8, LeanPadCrossbar.scale)
			ns.SetCrossbarScale(1.2)
			assert.equal(1.2, LeanPadCrossbar.scale)
		end)

		it("takes the mouse only while unlocked, and keeps where it was dragged to", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			local bar = LeanPadCrossbar
			assert.same({ "BOTTOM", UIParent, "BOTTOM", 0, 60 }, bar.point)
			assert.is_true(ns.CrossbarLocked())
			assert.is_false(bar.Outline:IsShown())
			assert.is_falsy(bar.mouse)
			ns.SetCrossbarLocked(false)
			assert.is_true(bar.Outline:IsShown())
			assert.is_true(bar.mouse)
			bar:Fire("OnDragStart")
			bar.point = { "TOPLEFT", UIParent, "TOPLEFT", 300, -400 } -- where the client left it
			bar:Fire("OnDragStop")
			assert.same({ "TOPLEFT", "TOPLEFT", 300, -400 }, ns.db.crossbarPoint)
			ns.SetCrossbarLocked(true)
			assert.is_false(bar.Outline:IsShown())
		end)

		it("unlocks with Blizzard's Edit Mode and locks again when it closes", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			wow.trigger("EditMode.Enter")
			assert.is_false(ns.CrossbarLocked())
			assert.is_true(LeanPadCrossbar.Outline:IsShown())
			wow.trigger("EditMode.Exit")
			assert.is_true(ns.CrossbarLocked())
			wow.trigger("EditMode.Exit") -- already locked: nothing to do
			assert.is_true(ns.CrossbarLocked())
			ns.SetCrossbarShown(false)
			wow.trigger("EditMode.Enter") -- a crossbar that is off stays locked
			assert.is_true(ns.CrossbarLocked())
		end)

		it("fades to the chosen opacity and resets its position from the outline", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			local bar = LeanPadCrossbar
			ns.SetCrossbarOpacity(0.6)
			assert.equal(0.6, ns.db.crossbarAlpha)
			assert.equal(0.6, bar.alpha)
			ns.db.crossbarPoint = { "TOPLEFT", "TOPLEFT", 300, -400 }
			local reset
			for _, widget in ipairs(w.widgets) do
				if widget.parent == bar.Outline and widget.text == "Reset position" then reset = widget end
			end
			reset:Fire("OnClick")
			assert.is_nil(ns.db.crossbarPoint)
			assert.same({ "BOTTOM", UIParent, "BOTTOM", 0, 60 }, bar.point)
		end)

		it("comes back where it was left, at the saved size and opacity", function()
			ns, w = wow.boot({ crossbarPoint = { "TOPLEFT", "TOPLEFT", 300, -400 }, crossbarScale = 0.6, crossbarAlpha = 0.4 })
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 300, -400 }, LeanPadCrossbar.point)
			assert.equal(0.6, LeanPadCrossbar.scale)
			assert.equal(0.4, LeanPadCrossbar.alpha)
		end)
	end)
end)
