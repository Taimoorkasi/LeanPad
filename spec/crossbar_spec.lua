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

		it("spaces the centre line evenly: D-pad, socket, socket, face buttons, 32 apart", function()
			local size, gap = ns.CROSSBAR_BUTTON_SIZE, 32
			local row = { ns.CROSSBAR.PADDRIGHT[1], ns.CROSSBAR_INNER[1][1], ns.CROSSBAR_INNER[2][1], ns.CROSSBAR.PAD3[1] }
			for i = 2, #row do assert.equal(size + gap, row[i] - row[i - 1]) end
			assert.equal(0, ns.CROSSBAR.PADDRIGHT[2])
			assert.equal(0, ns.CROSSBAR.PAD3[2])
		end)

		it("fits every button inside its cluster", function()
			for key, point in pairs(ns.CROSSBAR) do
				assert.is_true(math.abs(point[1]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= ns.CROSSBAR_CLUSTER_SIZE[1] / 2, key)
				assert.is_true(math.abs(point[2]) + ns.CROSSBAR_BUTTON_SIZE / 2 <= 110, key)
			end
		end)

		it("keeps clusters apart even when one is held at full size", function()
			local half = { ns.CROSSBAR_CLUSTER_SIZE[1] / 2, ns.CROSSBAR_CLUSTER_SIZE[2] / 2 }
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
			-- Bar actions: PAD3 on Base, PAD1 and PADDUP on LT. Faced commands: interact and targeting.
			-- The layer buttons, the cursor toggle, auto-run and the shoulders' missing bar buttons stay hidden.
			assert.same({ "PAD1", "PAD2", "PAD3", "PADDLEFT", "PADDRIGHT", "PADDUP" }, shown)
		end)

		it("stack the sockets between the diamonds on the diamonds' centre line, only the shown ones", function()
			w.bindings["SHIFT-PADRSHOULDER"] = "ACTIONBUTTON1" -- one socket sits level with the diamonds
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.same({ "CENTER", clusters()[1], "CENTER", 39, 0 }, buttonFor("PADRSHOULDER").point)
			w.bindings["SHIFT-PADRSTICK"] = "ACTIONBUTTON1" -- two straddle the line
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.same({ "CENTER", clusters()[1], "CENTER", 39, 27 }, buttonFor("PADRSHOULDER").point)
			assert.same({ "CENTER", clusters()[1], "CENTER", 39, -27 }, buttonFor("PADRSTICK").point)
			w.cvars.GamePadEmulateCtrl = "none" -- RT is a plain button again: three fill the column
			w.bindings.PADRTRIGGER = "ACTIONBUTTON1"
			bar:Fire("OnEvent", "CVAR_UPDATE")
			assert.same({ "CENTER", clusters()[1], "CENTER", 39, 54 }, buttonFor("PADRSHOULDER").point)
			assert.same({ "CENTER", clusters()[1], "CENTER", 39, 0 }, buttonFor("PADRTRIGGER").point)
			assert.same({ "CENTER", clusters()[1], "CENTER", 39, -54 }, buttonFor("PADRSTICK").point)
		end)

		it("give commands off the bars a face with a badge, and no cooldown or press", function()
			local right = buttonFor("PADDRIGHT") -- Target nearest enemy in the preset
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\IconTargetEnemy", right.Icon.texture)
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\IconJump", buttonFor("PAD1").Icon.texture)
			assert.equal("|A:common-icon-forwardarrow:12:12|a", right.Count:GetText())
			assert.equal(1, right.alpha)
			assert.is_nil(right.slot)
			assert.equal("|A:common-icon-backarrow:12:12|a", buttonFor("PADDLEFT").Count:GetText())
			assert.is_false(buttonFor("PADRSTICK"):IsShown()) -- the cursor toggle and auto-run stay off the bar
			assert.is_false(buttonFor("PADLSTICK"):IsShown())
		end)

		it("never show a layer button, even with a stale binding on it", function()
			w.bindings.PADRTRIGGER = "ACTIONBUTTON1"
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_false(buttonFor("PADRTRIGGER"):IsShown())
			w.cvars.GamePadEmulateCtrl = "none" -- no longer a layer button: its own action shows
			bar:Fire("OnEvent", "CVAR_UPDATE")
			assert.is_true(buttonFor("PADRTRIGGER"):IsShown())
		end)

		it("show a button with nothing on the held layer as a faint empty slot", function()
			w.bindings["SHIFT-PADLSHOULDER"] = "MULTIACTIONBAR1BUTTON1" -- a bar action on LT; on Base, a bar button the fake lacks
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			local lb = buttonFor("PADLSHOULDER")
			assert.is_true(lb:IsShown())
			assert.equal(ns.CROSSBAR_EMPTY_ALPHA, lb.alpha)
			assert.is_nil(lb.Icon.texture)
			assert.is_nil(lb.slot)
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

		it("press on an empty slot too, lit to full while held", function()
			w.bindings.PAD4 = "ACTIONBUTTON1" -- an empty slot
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			local button = buttonFor("PAD4")
			assert.equal(ns.CROSSBAR_EMPTY_ALPHA, button.alpha)
			ActionButton1:SetButtonState("PUSHED")
			assert.is_true(button.Flash:IsShown())
			assert.equal(1, button.alpha)
			ActionButton1:SetButtonState("NORMAL")
			assert.is_false(button.Flash:IsShown())
			assert.equal(ns.CROSSBAR_EMPTY_ALPHA, button.alpha)
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

		it("turn red while the target is out of range, and plain again in range or with no range to check", function()
			local button = buttonFor("PAD3")
			assert.same(ns.IN_RANGE, button.Icon.vertexColor)
			w.actions[61].inRange = false
			bar:Fire("OnEvent", "ACTION_RANGE_CHECK_UPDATE", 61, false, true)
			assert.same(ns.OUT_OF_RANGE, button.Icon.vertexColor)
			w.actions[61].inRange = true
			bar:Fire("OnEvent", "ACTION_RANGE_CHECK_UPDATE", 61, true, true)
			assert.same(ns.IN_RANGE, button.Icon.vertexColor)
			w.actions[61].inRange = false
			bar:Fire("OnEvent", "ACTION_RANGE_CHECK_UPDATE", 61, false, true)
			w.bindings.PAD3 = "ACTIONBUTTON1" -- an empty slot never stays red
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.same(ns.IN_RANGE, button.Icon.vertexColor)
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

	describe("mouse", function()
		before_each(function()
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
		end)

		it("stays off the buttons until asked, then takes drops and shows tooltips while locked", function()
			assert.is_false(buttonFor("PAD3").mouse)
			ns.SetCrossbarMouse(true)
			assert.is_true(ns.db.crossbarMouse)
			assert.is_true(buttonFor("PAD3").mouse)
			assert.is_false(clusters()[1].mouse)
			local x = buttonFor("PAD3") -- Action Bar 2, slot 1 on Base
			x:Fire("OnReceiveDrag")
			assert.same({ 61 }, w.placed)
			w.cursor = "spell"
			x:Fire("OnMouseUp")
			assert.same({ 61, 61 }, w.placed)
			w.cursor = nil
			x:Fire("OnMouseUp")
			assert.same({ 61, 61 }, w.placed)
			x:Fire("OnEnter")
			assert.same({ owner = x, anchor = "ANCHOR_RIGHT", slot = 61, shown = true }, w.tooltip)
			x:Fire("OnLeave")
			assert.is_nil(w.tooltip)
			buttonFor("PADDRIGHT"):Fire("OnEnter")
			assert.equal("name:TARGETNEARESTENEMY", w.tooltip.text)
			ns.SetCrossbarMouse(false)
			assert.is_false(buttonFor("PAD3").mouse)
		end)

		it("takes a socket's action out of its bar slot when dragged while locked, out of combat", function()
			ns.SetCrossbarMouse(true)
			buttonFor("PAD3"):Fire("OnDragStart")
			assert.same({ { "action", 61 } }, w.pickups)
			buttonFor("PAD1"):Fire("OnDragStart") -- JUMP lives on no slot
			assert.same({ { "action", 61 } }, w.pickups)
			w.combat = true
			buttonFor("PAD3"):Fire("OnDragStart")
			assert.same({ { "action", 61 } }, w.pickups)
			assert.equal("LeanPad: action bars can't change in combat.", w.printed[#w.printed])
		end)

		it("comes back on at login when it was left on", function()
			ns, w = wow.boot({ crossbarMouse = true })
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_true(buttonFor("PAD3").mouse)
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

		it("fades to the chosen opacity", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			ns.SetCrossbarOpacity(0.6)
			assert.equal(0.6, ns.db.crossbarAlpha)
			assert.equal(0.6, LeanPadCrossbar.alpha)
		end)

		describe("layout editing", function()
			local set
			before_each(function()
				wow.fire("PLAYER_ENTERING_WORLD")
				bar = LeanPadCrossbar
				ns.SetCrossbarLocked(false)
				set = clusters()[1]
			end)

			it("takes the mouse on sets and buttons only while unlocked", function()
				assert.is_true(set.mouse)
				assert.is_true(set.wheel)
				assert.is_true(buttonFor("PAD3").mouse)
				ns.SetCrossbarLocked(true)
				assert.is_false(set.mouse)
				assert.is_false(set.wheel)
				assert.is_false(buttonFor("PAD3").mouse)
			end)

			it("keeps where a set is dragged to, in the bar's units whatever the scales, on an 8-unit grid", function()
				set.cx, set.cy, set.effectiveScale = 700, 402, 0.5
				bar.cx, bar.cy, bar.effectiveScale = 600, 300, 1
				set:Fire("OnDragStart")
				set:Fire("OnDragStop")
				assert.same({ -248, -96 }, ns.db.clusterPoints[1]) -- (-250, -99) snapped
				assert.same({ "CENTER", bar, "CENTER", -248, -96 }, set.point)
			end)

			it("pulls a dropped set level with a neighbour on one axis, unless Shift is held", function()
				set.cx, set.cy = 5, -131 -- near the fourth set's slot at 0, -135: both axes within reach, so neither pulls
				set:Fire("OnDragStart")
				set:Fire("OnDragStop")
				assert.same({ 8, -128 }, ns.db.clusterPoints[1])
				set.cx, set.cy = 5, -70 -- level in x only: pulled onto the fourth set's column
				set:Fire("OnDragStart")
				set:Fire("OnDragStop")
				assert.same({ 0, -72 }, ns.db.clusterPoints[1])
				w.held.shift = true
				set.cx, set.cy = 5, -70
				set:Fire("OnDragStart")
				set:Fire("OnDragStop")
				assert.same({ 5, -70 }, ns.db.clusterPoints[1])
			end)

			it("sizes a set with the wheel in 5% steps, between half and double", function()
				set:Fire("OnMouseWheel", 1)
				assert.near(1.05, ns.db.clusterScales[1], 0.0001)
				assert.near(1.05, set.scale, 0.0001)
				assert.near(ns.CROSSBAR_CLUSTERS[1][2] / 1.05, set.point[5], 0.0001)
				for _ = 1, 30 do set:Fire("OnMouseWheel", -1) end
				assert.near(0.5, ns.db.clusterScales[1], 0.0001)
				for _ = 1, 40 do set:Fire("OnMouseWheel", 1) end
				assert.near(2, ns.db.clusterScales[1], 0.0001)
			end)

			it("keeps where a button is dragged to, for every set, and resets the whole layout from the outline", function()
				local x = buttonFor("PAD3")
				x.cx, x.cy, set.cx, set.cy = 11, 21, 0, 0
				x:Fire("OnDragStart")
				x:Fire("OnDragStop")
				assert.same({ 8, 24 }, ns.db.socketPoints.PAD3) -- on the grid; no neighbour near enough to pull
				assert.same({ "CENTER", set, "CENTER", 8, 24 }, x.point)
				ns.SetCrossbarStyle("all") -- the other sets, once shown, share the spot
				assert.same({ "CENTER", clusters()[2], "CENTER", 8, 24 }, buttonFor("PAD3", 2).point)
				x.cx, x.cy = 158, 10 -- nearly under Y and nearly level with B: pulled into Y's column and B's row
				x:Fire("OnDragStart")
				x:Fire("OnDragStop")
				assert.same({ ns.CROSSBAR.PAD4[1], ns.CROSSBAR.PAD2[2] }, ns.db.socketPoints.PAD3)
				-- A dragged socket between the diamonds leaves the stack.
				w.bindings["SHIFT-PADRSHOULDER"], w.bindings["SHIFT-PADRSTICK"] = "ACTIONBUTTON1", "ACTIONBUTTON1"
				ns.db.socketPoints.PADRSTICK = { 90, -90 }
				bar:Fire("OnEvent", "UPDATE_BINDINGS")
				assert.same({ "CENTER", set, "CENTER", 39, 0 }, buttonFor("PADRSHOULDER").point)
				assert.same({ "CENTER", set, "CENTER", 90, -90 }, buttonFor("PADRSTICK").point)
				ns.db.crossbarPoint = { "TOPLEFT", "TOPLEFT", 300, -400 }
				local reset
				for _, widget in ipairs(w.widgets) do
					if widget.parent == bar.Outline and widget.text == "Reset layout" then reset = widget end
				end
				reset:Fire("OnClick")
				assert.is_nil(ns.db.crossbarPoint)
				assert.is_nil(ns.db.clusterPoints)
				assert.is_nil(ns.db.clusterScales)
				assert.is_nil(ns.db.socketPoints)
				assert.same({ "BOTTOM", UIParent, "BOTTOM", 0, 60 }, bar.point)
				assert.same({ "CENTER", set, "CENTER", ns.CROSSBAR.PAD3[1], ns.CROSSBAR.PAD3[2] }, x.point)
				assert.same({ "CENTER", bar, "CENTER", 0, 60 }, set.point)
			end)

			it("moves nothing while locked, nor while a spell rides the cursor", function()
				ns.SetCrossbarLocked(true)
				set.cx, set.cy = 5, -70
				set:Fire("OnDragStart")
				set:Fire("OnDragStop")
				assert.is_nil(ns.db.clusterPoints)
				ns.SetCrossbarLocked(false)
				w.cursor = "spell"
				set:Fire("OnDragStart")
				set:Fire("OnDragStop")
				assert.is_nil(ns.db.clusterPoints)
			end)

			it("comes back with the sets and buttons where they were left", function()
				ns, w = wow.boot({ clusterPoints = { [1] = { 0, -200 } }, clusterScales = { [1] = 0.8 }, socketPoints = { PAD1 = { 5, 5 } } })
				wow.fire("PLAYER_ENTERING_WORLD")
				local first = clusters()[1]
				assert.near(0.8, first.scale, 0.0001)
				assert.near(-250, first.point[5], 0.0001)
				assert.same({ "CENTER", first, "CENTER", 5, 5 }, buttonFor("PAD1").point)
			end)
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
