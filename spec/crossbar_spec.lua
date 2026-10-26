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

		it("hear the pad from a child of the bar, passing every press on to its binding", function()
			assert.is_true(bar.Pad.gamePadButton)
			assert.is_true(bar.Pad.propagate)
			assert.equal(bar, bar.Pad.parent) -- deaf while the crossbar is hidden
		end)

		it("blink: a white flash fading out, with a faint socket shown in full meanwhile", function()
			local button = buttonFor("PAD3")
			assert.equal(0, button.Flash.alpha)
			local full, fade
			for _, widget in ipairs(w.widgets) do
				if widget.kind == "Animation" and widget.parent == button.Blink then
					if widget.target then fade = widget else full = widget end
				end
			end
			assert.same({ "Alpha", 1, 1, ns.CROSSBAR_BLINK }, { full.animationType, full.fromAlpha, full.toAlpha, full.seconds })
			assert.same({ "Alpha", 1, 0, ns.CROSSBAR_BLINK }, { fade.animationType, fade.fromAlpha, fade.toAlpha, fade.seconds })
			assert.equal(button.Flash, fade.target)
			assert.equal(button, button.Blink.parent)
		end)

		it("light a round gold glow with a spinning spark while the slot's spell is procced, a macro's too", function()
			local button = buttonFor("PAD3") -- slot 61, spell 1953
			local alert = button.Glow
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\ProcGlow", alert.Ring.texture)
			assert.same(ns.PROC, alert.Ring.vertexColor)
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\ProcSpark", alert.Spark.texture)
			assert.equal("REPEAT", alert.Spin.looping)
			assert.equal("BOUNCE", alert.Breathe.looping)
			assert.is_false(alert:IsShown())
			w.procs[1953] = true
			bar:Fire("OnEvent", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1953)
			assert.is_true(alert:IsShown())
			assert.equal(1, alert.Birth.plays)
			assert.is_true(alert.Spin:IsPlaying())
			bar:Fire("OnEvent", "ACTIONBAR_UPDATE_COOLDOWN") -- refreshes leave a lit glow alone
			assert.equal(1, alert.Birth.plays)
			w.procs[1953] = nil
			bar:Fire("OnEvent", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 1953)
			assert.is_false(alert:IsShown())
			assert.is_false(alert.Spin:IsPlaying())
			assert.is_false(alert.Breathe:IsPlaying())
			w.procs[1953] = true
			w.actions[61].kind = "macro"
			bar:Fire("OnEvent", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1953)
			assert.is_true(button.Glow:IsShown())
			w.actions[61].kind = "item"
			bar:Fire("OnEvent", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1953)
			assert.is_false(button.Glow:IsShown())
			w.actions[61].kind, w.actions[61].id = "spell", nil
			bar:Fire("OnEvent", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1953)
			assert.is_false(button.Glow:IsShown())
		end)

		it("blink the pressed button's socket, restarting on every press", function()
			bar.Pad:Fire("OnGamePadButtonDown", "PAD3")
			bar.Pad:Fire("OnGamePadButtonDown", "PAD3")
			assert.equal(2, buttonFor("PAD3").Blink.plays)
			assert.equal(2, buttonFor("PAD3").Blink.stops)
			assert.equal(0, buttonFor("PAD1").Blink.plays)
			assert.has_no.errors(function() bar.Pad:Fire("OnGamePadButtonDown", "PADSYSTEM") end) -- no socket
		end)

		it("blink on an empty slot or a command too", function()
			w.bindings.PAD4 = "ACTIONBUTTON1" -- an empty slot
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			bar.Pad:Fire("OnGamePadButtonDown", "PAD4")
			bar.Pad:Fire("OnGamePadButtonDown", "PAD1") -- Jump, on no bar
			assert.equal(1, buttonFor("PAD4").Blink.plays)
			assert.equal(1, buttonFor("PAD1").Blink.plays)
		end)

		it("blink only the held layer's set when all layers show", function()
			ns.SetCrossbarStyle("all")
			bar.Pad:Fire("OnGamePadButtonDown", "PAD3")
			assert.equal(1, buttonFor("PAD3", 1).Blink.plays)
			assert.equal(0, buttonFor("PAD3", 2).Blink.plays)
		end)

		it("start hearing the pad after combat when built during it", function()
			ns, w = wow.boot(nil)
			w.combat = true
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(rawget(LeanPadCrossbar, "Pad"))
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_true(LeanPadCrossbar.Pad.gamePadButton)
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

		it("re-read Blizzard's buttons a frame after login, when they get their slots", function()
			ns, w = wow.boot({ prompted = true })
			MultiBarBottomLeftButton1.action = nil -- not yet pointed at a slot when PLAYER_ENTERING_WORLD reaches LeanPad
			w.bindings.PAD4 = "MULTIACTIONBAR1BUTTON1"
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(buttonFor("PAD4").slot)
			MultiBarBottomLeftButton1.action = 61
			wow.nextFrame()
			assert.equal(135808, buttonFor("PAD4").Icon.texture)
		end)

		it("follow Action Bar 1 onto a form's page, and onto vehicle and override bars", function()
			w.bindings.PAD4 = "ACTIONBUTTON1"
			w.actions[97] = { texture = 977 }
			w.bar.bonus = 9 -- Bear Form
			bar:Fire("OnEvent", "UPDATE_BONUS_ACTIONBAR")
			wow.nextFrame()
			assert.equal(97, buttonFor("PAD4").slot)
			assert.equal(977, buttonFor("PAD4").Icon.texture)
			w.actions[133] = { texture = 1333 }
			w.bar.vehicle = 12
			bar:Fire("OnEvent", "UPDATE_VEHICLE_ACTIONBAR")
			wow.nextFrame()
			assert.equal(1333, buttonFor("PAD4").Icon.texture)
			w.bar.vehicle, w.bar.override = nil, 12
			bar:Fire("OnEvent", "UPDATE_OVERRIDE_ACTIONBAR")
			wow.nextFrame()
			assert.equal(1333, buttonFor("PAD4").Icon.texture)
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
			assert.is_true(#w.errors > 0) -- one per socket on a bar slot
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

	describe("styles", function()
		before_each(function()
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
		end)

		it("place every key in every style, no two sockets overlapping", function()
			local size = ns.CROSSBAR_BUTTON_SIZE
			for name, s in pairs(ns.CROSSBAR_STYLES) do
				for a in pairs(ns.CROSSBAR) do
					assert.truthy(s.points[a], name .. " " .. a)
					for b in pairs(ns.CROSSBAR) do
						local pa, pb = s.points[a], s.points[b]
						if a ~= b then assert.is_true(math.abs(pa[1] - pb[1]) >= size or math.abs(pa[2] - pb[2]) >= size, name .. " " .. a .. " " .. b) end
					end
				end
			end
		end)

		it("order the row by hand: left bumper and D-pad, face buttons and right bumper", function()
			ns.SetCrossbarStyle("strip")
			local xs = {}
			for i, key in ipairs({ "PADLSHOULDER", "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1", "PADRSHOULDER" }) do
				xs[i] = buttonFor(key).point[4]
				assert.equal(0, buttonFor(key).point[5])
				if i > 1 then assert.is_true(xs[i] > xs[i - 1], key) end
			end
			assert.equal(0, ns.CROSSBAR_STYLES.strip.points.PADDDOWN[1] + ns.CROSSBAR_STYLES.strip.points.PAD3[1]) -- centred
			for _, widget in ipairs(w.widgets) do
				if widget.kind == "FontString" and widget.parent == clusters()[1] then
					assert.same({ "CENTER", clusters()[1], "CENTER", 0, 50 }, widget.point)
				end
			end
		end)

		it("keep the ghost row faint until a layer is held", function()
			ns.SetCrossbarStyle("ghost")
			assert.equal(ns.CROSSBAR_QUIET_ALPHA, clusters()[1].alpha)
			w.held.shift = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal(1, clusters()[1].alpha)
			assert.equal(61, buttonFor("PAD1").slot)
		end)

		it("draw the grid square, columns by direction, and go round again in the classic style", function()
			ns.SetCrossbarStyle("grid")
			local x = buttonFor("PAD3")
			assert.equal(ns.WHITE, x.IconMask.texture)
			assert.equal(ns.WHITE, x.RimMask.texture)
			assert.equal(ns.WHITE, x.Cooldown.swipeTexture)
			assert.is_false(x.Cooldown.circularEdge)
			assert.same({ "BOTTOMLEFT", x.Face, "BOTTOMLEFT", 1, 1 }, x.Glyph.point)
			local points = ns.CROSSBAR_STYLES.grid.points
			assert.equal(points.PADDLEFT[1], points.PAD3[1]) -- X under left
			assert.equal(points.PADDDOWN[1], points.PAD1[1]) -- A under down
			assert.is_true(points.PADDUP[2] > points.PAD4[2])
			ns.SetCrossbarStyle("active")
			assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", x.IconMask.texture)
			assert.is_true(x.Cooldown.circularEdge)
			assert.same({ "BOTTOM", x.Face, "TOP", 0, -6 }, x.Glyph.point)
		end)

		it("give every layer its own row in the row styles, the held one in front, nothing shrunk", function()
			for _, name in ipairs({ "rows", "stacked" }) do
				ns.SetCrossbarStyle(name)
				local all = clusters()
				for index, cluster in ipairs(all) do
					assert.is_true(cluster:IsShown())
					assert.equal(1, cluster.scale)
					local point = ns.CROSSBAR_STYLES[name].clusters[index]
					assert.same({ "CENTER", bar, "CENTER", point[1], point[2] }, cluster.point)
				end
				assert.equal(1, all[1].alpha)
				assert.equal(ns.CROSSBAR_IDLE_ALPHA, all[2].alpha)
				assert.equal(61, buttonFor("PAD1", 2).slot)
			end
			assert.is_true(ns.CROSSBAR_STYLES.rows.clusters[1][2] > ns.CROSSBAR_STYLES.rows.clusters[2][2]) -- Base on top
			assert.is_true(ns.CROSSBAR_STYLES.stacked.clusters[1][2] < ns.CROSSBAR_STYLES.stacked.clusters[2][2]) -- Base at the bottom
			w.held.shift = true
			bar:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal(1, clusters()[2].alpha)
			assert.equal(1, clusters()[2].scale)
		end)

		it("aim each row's click twins at its own layer", function()
			ns.SetCrossbarMouse(true)
			ns.SetCrossbarStyle("rows")
			local socket = buttonFor("PAD1", 2)
			for _, twin in ipairs(wow.widgets("Button", "SecureActionButtonTemplate")) do
				if twin.scripts.OnEnter == socket.tooltip then
					assert.equal(61, twin:GetAttribute("", "action", "1"))
					assert.equal("action", twin:GetAttribute("ctrl-", "type", "1")) -- holding another layer changes nothing
					assert.equal(61, twin:GetAttribute("ctrl-", "action", "2"))
				end
			end
		end)

		it("keep dragged spots and sizes per style, and reset only the style shown", function()
			ns.SetCrossbarStyle("strip")
			ns.SetCrossbarLocked(false)
			local set, x = clusters()[1], buttonFor("PAD3")
			x.cx, x.cy, set.cx, set.cy = 11, 21, 0, 0
			x:Fire("OnDragStart")
			x:Fire("OnDragStop")
			assert.same({ 8, 24 }, ns.db["socketPoints.strip"].PAD3)
			assert.is_nil(ns.db.socketPoints)
			set:Fire("OnMouseWheel", 1)
			assert.near(1.05, ns.db["clusterScales.strip"][1], 0.0001)
			ns.db.socketPoints = { PAD3 = { 1, 1 } }
			local reset
			for _, widget in ipairs(w.widgets) do
				if widget.parent == bar.Outline and widget.text == "Reset layout" then reset = widget end
			end
			reset:Fire("OnClick")
			assert.is_nil(ns.db["socketPoints.strip"])
			assert.is_nil(ns.db["clusterScales.strip"])
			assert.same({ PAD3 = { 1, 1 } }, ns.db.socketPoints)
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

	describe("clicks", function()
		-- The secure twin laid over a socket: the one handing its tooltip to that socket.
		local function twinFor(key, index)
			local socket = buttonFor(key, index)
			for _, twin in ipairs(wow.widgets("Button", "SecureActionButtonTemplate")) do
				if twin.scripts.OnEnter == socket.tooltip then return twin end
			end
		end

		local function header() return wow.widgets("Frame", "SecureHandlerStateTemplate")[1] end

		before_each(function()
			w.bindings.PAD4 = "ACTIONBUTTON1" -- Action Bar 1 on Base
			wow.fire("PLAYER_ENTERING_WORLD")
			bar = LeanPadCrossbar
		end)

		it("need the mouse on, then put a twin over each shown socket and above it", function()
			assert.is_false(twinFor("PAD3"):IsShown())
			local socket = buttonFor("PAD3")
			socket.cx, socket.cy, socket.effectiveScale, UIParent.effectiveScale = 100, 50, 1.5, 0.75
			ns.SetCrossbarMouse(true)
			local twin = twinFor("PAD3")
			assert.is_true(twin:IsShown())
			assert.same({ "CENTER", UIParent, "BOTTOMLEFT", 200, 100 }, twin.point)
			assert.equal(socket.Overlay:GetFrameLevel() + 1, twin:GetFrameLevel())
			assert.is_false(twinFor("PADRSTICK"):IsShown()) -- the cursor toggle shows no socket
			assert.is_false(twinFor("PAD3", 2):IsShown()) -- sets the held-layer view doesn't show
		end)

		it("fire the slot of the layer the click's modifiers pick, and nothing off the bars", function()
			ns.SetCrossbarMouse(true)
			local x, a = twinFor("PAD3"), twinFor("PAD1")
			assert.equal("action", x:GetAttribute("", "type", "1"))
			assert.equal(61, x:GetAttribute("", "action", "1"))
			assert.equal(ATTRIBUTE_NOOP, a:GetAttribute("", "type", "1")) -- Jump
			assert.equal("action", a:GetAttribute("shift-", "type", "1")) -- LT + A, by a left click
			assert.equal(61, a:GetAttribute("shift-", "action", "1"))
			assert.equal(61, a:GetAttribute("shift-", "action", "2")) -- or a right one
			assert.equal(ATTRIBUTE_NOOP, a:GetAttribute("ctrl-", "type", "1")) -- a bar button the fake lacks
			assert.is_nil(a:GetAttribute("alt-", "type", "1")) -- no Alt layer: no fall back to Base
		end)

		it("follow Action Bar 1's page as forms and bars change it, by the client's own conditions", function()
			ns.SetCrossbarMouse(true)
			local y = twinFor("PAD4")
			assert.equal("action", y:GetAttribute("", "type", "1"))
			assert.equal(1, y:GetAttribute("", "action", "1"))
			local driver = w.stateDrivers.page
			assert.equal(header(), driver.frame)
			assert.truthy(driver.values:find("[bonusbar:1] b1", 1, true))
			w.bar.bonus = 7 -- Cat Form
			header():SetAttribute("state-page", "b1")
			assert.equal(73, y:GetAttribute("", "action", "1"))
			w.bar.page = 2 -- a paged bar wins over the form, as in mainBarPage
			header():SetAttribute("state-page", "2")
			assert.equal(13, y:GetAttribute("", "action", "1"))
			for state, index in pairs({ v = "vehicle", o = "override", s = "temp" }) do
				w.bar[index] = 12
				header():SetAttribute("state-page", state)
				assert.equal(133, y:GetAttribute("", "action", "1"), state)
				w.bar[index] = nil
			end
		end)

		it("fire each set's own layer in the all-layers view", function()
			ns.SetCrossbarMouse(true)
			ns.SetCrossbarStyle("all")
			local a = twinFor("PAD1", 2) -- the LT set
			assert.is_true(a:IsShown())
			assert.equal("action", a:GetAttribute("", "type", "1"))
			assert.equal(61, a:GetAttribute("", "action", "1"))
			assert.equal(61, a:GetAttribute("shift-", "action", "1")) -- whatever is held
			assert.equal(1, twinFor("PAD4", 1):GetAttribute("shift-", "action", "1")) -- Action Bar 1, paged by the snippet
		end)

		it("hide while unlocked, with the mouse off or with the bar", function()
			ns.SetCrossbarMouse(true)
			ns.SetCrossbarLocked(false)
			assert.is_false(twinFor("PAD3"):IsShown())
			ns.SetCrossbarLocked(true)
			assert.is_true(twinFor("PAD3"):IsShown())
			ns.SetCrossbarShown(false)
			assert.is_false(twinFor("PAD3"):IsShown())
			ns.SetCrossbarShown(true)
			ns.SetCrossbarMouse(false)
			assert.is_false(twinFor("PAD3"):IsShown())
		end)

		it("wait for combat to end before moving or aiming", function()
			w.combat = true
			ns.SetCrossbarMouse(true)
			bar:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_false(twinFor("PAD3"):IsShown())
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_true(twinFor("PAD3"):IsShown())
		end)

		it("hand tooltips, drops and drags to their socket", function()
			ns.SetCrossbarMouse(true)
			local twin = twinFor("PAD3")
			twin:Fire("OnEnter")
			assert.same({ owner = twin, anchor = "ANCHOR_RIGHT", slot = 61, shown = true }, w.tooltip)
			twin:Fire("OnLeave")
			assert.is_nil(w.tooltip)
			twin:Fire("OnReceiveDrag")
			assert.same({ 61 }, w.placed)
			twin:Fire("OnDragStart")
			assert.same({ { "action", 61 } }, w.pickups)
			w.cursor = "spell" -- a drag carrying a spell is a drop, not a pickup
			twin:Fire("OnDragStart")
			assert.same({ { "action", 61 } }, w.pickups)
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
