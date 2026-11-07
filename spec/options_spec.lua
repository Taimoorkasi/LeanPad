local wow = require("spec.wow")

describe("Options page", function()
	local ns, w, frame, page

	local function find(kind, test)
		for _, widget in ipairs(w.widgets) do
			if widget.kind == kind and test(widget) then return widget end
		end
	end

	-- The control on a row, found through its label: both sit on the row's centre line.
	-- On the Controls tab unless another is given.
	local function controlFor(label, on)
		on = on or page.Controls
		local text = find("FontString", function(widget) return widget.parent == on and widget.text == label end)
		assert.is_truthy(text, label)
		return find("Button", function(widget)
			return widget.parent == on and widget.point[1] == "RIGHT" and widget.point[4] == text.point[4] + 432 and widget.point[5] == text.point[5]
		end)
	end

	-- On the page itself or its Controls tab unless another is given.
	local function button(text, on)
		return find("Button", function(widget)
			if on then return widget.parent == on and widget.text == text end
			return (widget.parent == page or widget.parent == page.Controls) and widget.text == text
		end)
	end

	local function labels(description)
		local list = {}
		for _, entry in ipairs(description.entries) do table.insert(list, entry.text) end
		return list
	end

	before_each(function()
		ns, w = wow.boot(nil)
		ns.Apply()
		w.deviceIDs = { 1 }
		w.devices[1] = { name = "DualSense Wireless Controller" }
		ns.OpenOptions()
		frame = LeanPadControllerFrame
		page = frame.Options
	end)
	after_each(wow.restore)

	it("replaces the editor page, is built once, and goes back", function()
		assert.is_true(page:IsShown())
		assert.is_false(frame.Editor:IsShown())
		ns.BuildOptions(frame)
		assert.equal(page, frame.Options)
		button("Controller"):Fire("OnClick")
		assert.is_true(frame.Editor:IsShown())
		assert.is_false(page:IsShown())
	end)

	it("says what every setting does, on hovering the (i) after its label", function()
		local label = find("FontString", function(widget) return widget.parent == page.Controls and widget.text == "Gamepad input" end)
		label.Info:Fire("OnEnter")
		assert.equal("Gamepad input", w.tooltip.text)
		assert.equal("Turns WoW's own gamepad support on or off. LeanPad needs it on.", w.tooltip.lines[1])
		label.Info:Fire("OnLeave")
		assert.is_nil(w.tooltip)
		local rows = 0
		for _, widget in ipairs(w.widgets) do
			local onTab = widget.parent == page.Controls or widget.parent == page.Dialogue
			if widget.kind == "FontString" and onTab and widget.font == ns.Font(13, ns.COLORS.text2) then
				assert.is_truthy(rawget(widget, "Info"), widget.text)
				rows = rows + 1
			end
		end
		assert.is_true(rows > 25)
	end)

	it("switches empty crossbar buttons on and off, starting off on retail", function()
		local box = controlFor("Show empty buttons")
		assert.is_false(box.Check:IsShown())
		box:Fire("OnClick")
		assert.is_true(ns.db.crossbarEmpty)
		assert.is_true(box.Check:IsShown())
	end)

	describe("the Dialogue tab", function()
		local dialogue

		before_each(function()
			button("Dialogue", page):Fire("OnClick")
			dialogue = page.Dialogue
		end)

		it("swaps the Controls tab for its own settings, lit and underlined, and back", function()
			local tabs = page.Tabs
			assert.is_true(dialogue:IsShown())
			assert.is_false(page.Controls:IsShown())
			assert.is_true(tabs[2].Underline:IsShown())
			assert.is_false(tabs[1].Underline:IsShown())
			assert.is_nil(button("Undo setup", dialogue)) -- the layout's actions stay with the controls
			tabs[1]:Fire("OnClick")
			assert.is_true(page.Controls:IsShown())
			assert.is_false(dialogue:IsShown())
		end)

		it("switches the window on, taking Blizzard's events at once, and pop-ups apart from it", function()
			local box = controlFor("Talk and do quests in LeanPad's window", dialogue)
			assert.is_false(box.Check:IsShown())
			box:Fire("OnClick")
			assert.is_true(ns.db.questPrompts)
			assert.is_nil(QuestFrame.events.QUEST_DETAIL)
			assert.equal("Saved", page.Saved.text:match("Saved$"))
			local popups = controlFor("Answer pop-ups with the pad", dialogue)
			popups:Fire("OnClick")
			assert.is_true(ns.db.padPopups)
			StaticPopup1:Show()
			assert.equal("StaticPopup1Button1", w.overrides.PAD1.click)
		end)

		it("sets where the window shows and how large, the NPC in 3D, text writing itself in and the camera", function()
			local position = controlFor("Position", dialogue)
			assert.equal("Bottom centre", position.Label:GetText())
			position:Fire("OnClick")
			assert.equal(9, #w.menu.root.entries)
			wow.entry(w.menu.root, "Top left").callback()
			assert.equal("TOPLEFT", ns.db.dialoguePosition)
			controlFor("Size", dialogue):Fire("OnClick")
			wow.entry(w.menu.root, "125%").callback()
			assert.equal(1.25, ns.db.dialogueScale)
			for label, key in pairs({ ["Show the NPC in 3D, talking"] = "dialogueModel", ["Text writes itself in"] = "dialogueReveal" }) do
				controlFor(label, dialogue):Fire("OnClick")
				assert.is_false(ns.db[key])
			end
			controlFor("Zoom the camera in on the NPC", dialogue):Fire("OnClick")
			assert.is_true(ns.db.dialogueCamera)
		end)

		it("previews the window in place, and closes the preview on leaving", function()
			local preview = controlFor("See it in place", dialogue)
			preview:Fire("OnClick")
			assert.is_true(ns.DialoguePreviewing())
			preview:Fire("OnClick")
			assert.is_false(ns.DialoguePreviewing())
			preview:Fire("OnClick")
			ns.ShowSettingsTab("Controls")
			assert.is_false(ns.DialoguePreviewing())
		end)
	end)

	it("switches gamepad input on and off", function()
		local box = controlFor("Gamepad input")
		assert.is_true(box.Check:IsShown())
		box:Fire("OnClick")
		assert.equal("0", w.cvars.GamePadEnable)
		assert.is_false(box.Check:IsShown())
	end)

	it("picks the pad to use, All connected by default", function()
		local dropdown = controlFor("Active pad")
		assert.equal("All connected", dropdown.Label:GetText())
		dropdown:Fire("OnClick")
		local root = w.menu.root
		assert.same({ "All connected", "DualSense Wireless Controller" }, labels(root))
		assert.is_true(root.entries[1].selected())
		root.entries[2].callback()
		assert.equal("1", w.cvars.GamePadSingleActiveID)
		frame:Fire("OnEvent", "CVAR_UPDATE")
		assert.equal("DualSense Wireless Controller", dropdown.Label:GetText())
		w.devices[1] = nil
		dropdown:Fire("OnClick")
		assert.same({ "All connected", "Controller 1" }, labels(w.menu.root))
	end)

	it("overrides the detected button labels, redrawing the pad", function()
		local dropdown = controlFor("Button labels")
		assert.equal("Auto (Xbox)", dropdown.Label:GetText())
		dropdown:Fire("OnClick")
		wow.entry(w.menu.root, "PlayStation").callback()
		assert.equal("playstation", ns.db.padStyle)
		assert.equal("PlayStation", dropdown.Label:GetText())
		assert.equal("Interface\\AddOns\\LeanPad\\Art\\PadPlayStation", frame.Editor.Art.texture)
		w.padState = { labelStyle = "Shapes", name = "DualSense Wireless Controller" }
		wow.entry(w.menu.root, "Auto (Xbox)").callback()
		dropdown:Fire("OnClick")
		assert.equal("Auto (PlayStation)", w.menu.root.entries[1].text)
	end)

	it("sets the three layer buttons and the cursor clicks by pad key", function()
		local shift = controlFor("Layer 1, acts as Shift")
		assert.equal("LT", shift.Label:GetText())
		shift:Fire("OnClick")
		assert.equal(NONE, w.menu.root.entries[1].text)
		assert.is_true(wow.entry(w.menu.root, "LT").selected())
		wow.entry(w.menu.root, "LB").callback()
		assert.equal("PADLSHOULDER", w.cvars.GamePadEmulateShift)
		assert.is_nil(w.bindings.PADLSHOULDER) -- a layer button holds no action
		assert.equal(NONE, controlFor("Layer 3, acts as Alt").Label:GetText())
		local left = controlFor("Left click")
		assert.equal("A", left.Label:GetText())
		left:Fire("OnClick")
		wow.entry(w.menu.root, "B").callback()
		assert.equal("PAD2", w.cvars.GamePadCursorLeftClick)
	end)

	it("picks the crossbar's view with one control: off, one swapping set, or all layers", function()
		local crossbar = controlFor("View")
		assert.equal("One set, swaps with the held layer", crossbar.Label:GetText())
		crossbar:Fire("OnClick")
		assert.same({ OFF, "One set, swaps with the held layer", "All layers, the held one large", "One row, swaps with the held layer",
			"One row, faint until a layer is held", "Square grid, swaps with the held layer", "Square rows, one per layer", "Stacked rows, one per layer" }, labels(w.menu.root))
		wow.entry(w.menu.root, "All layers, the held one large").callback()
		assert.equal("all", ns.db.crossbarStyle)
		assert.is_true(ns.db.crossbar)
		assert.is_true(LeanPadCrossbar:IsShown())
		wow.entry(w.menu.root, OFF).callback()
		assert.is_false(ns.db.crossbar)
		assert.equal("all", ns.db.crossbarStyle)
		assert.is_false(LeanPadCrossbar:IsShown())
		assert.equal(OFF, crossbar.Label:GetText())
	end)

	it("sizes the crossbar and unlocks it for dragging", function()
		local size = controlFor("Size")
		assert.equal("100%", size.Label:GetText())
		size:Fire("OnClick")
		wow.entry(w.menu.root, "80%").callback()
		assert.equal(0.8, ns.db.crossbarScale)
		assert.equal("80%", size.Label:GetText())
		assert.is_true(page.Saved:IsShown())
		local opacity = controlFor("Opacity")
		assert.equal("100%", opacity.Label:GetText())
		opacity:Fire("OnClick")
		wow.entry(w.menu.root, "60%").callback()
		assert.equal(0.6, ns.db.crossbarAlpha)
		local mouse = controlFor("Mouse: click, drop spells, see tooltips")
		assert.is_false(mouse.Check:IsShown())
		mouse:Fire("OnClick")
		assert.is_true(ns.db.crossbarMouse)
		local lock = controlFor("Position")
		assert.equal("Unlock to drag", lock:GetText())
		lock:Fire("OnClick")
		assert.is_false(ns.CrossbarLocked())
		assert.equal("Lock in place", lock:GetText())
		lock:Fire("OnClick")
		assert.is_true(ns.CrossbarLocked())
	end)

	it("takes the cursor's start spot as x, y from the screen's centre; blank keeps it where it was", function()
		local start = find("Frame", function(widget) return widget.parent == page.Controls and widget.X end)
		assert.equal("", start.X:GetText())
		start.X:SetText("200")
		start.X:Fire("OnEnterPressed") -- Enter drops focus, which commits
		assert.same({ 200, 0 }, ns.db.cursorStart) -- a blank axis reads as 0
		assert.equal("0", start.Y:GetText())
		start.Y:SetText("-150")
		start.Y:ClearFocus()
		assert.same({ 200, -150 }, ns.db.cursorStart)
		start.Y:SetText("9")
		start.Y:Fire("OnEscapePressed") -- puts back what was there
		assert.equal("-150", start.Y:GetText())
		assert.same({ 200, -150 }, ns.db.cursorStart)
		start.X:SetText("")
		start.Y:SetText("abc")
		start.Y:ClearFocus()
		assert.is_nil(ns.db.cursorStart)
		assert.equal("", start.X:GetText())
	end)

	it("picks the cursor's start spot on screen: centre lines, a ring on the spot set now, a click sets it", function()
		local start = find("Frame", function(widget) return widget.parent == page.Controls and widget.X end)
		UIParent.width, UIParent.height, UIParent.effectiveScale = 1920, 1080, 0.5
		start.Pick:Fire("OnClick")
		local picker = LeanPadCursorPicker
		assert.is_true(picker:IsShown())
		assert.is_false(picker.Marker:IsShown()) -- no spot set yet
		assert.equal(0, frame.alpha) -- LeanPad's window steps aside while picking, still open
		assert.is_true(frame:IsShown())
		picker:Fire("OnKeyDown", "SPACE")
		assert.is_true(picker:IsShown())
		picker:Fire("OnKeyDown", "ESCAPE") -- cancels, without closing LeanPad's window as UISpecialFrames would
		assert.is_false(picker:IsShown())
		assert.equal(1, frame.alpha)
		start.Pick:Fire("OnClick")
		w.mouseAt = { 600, 135 } -- screen pixels; at scale 0.5, UI point 1200, 270: 240 right of centre, 270 below
		picker:Fire("OnClick", "LeftButton")
		assert.is_false(picker:IsShown())
		assert.same({ 240, -270 }, ns.db.cursorStart)
		assert.equal("240", start.X:GetText())
		assert.equal("-270", start.Y:GetText())
		start.Pick:Fire("OnClick")
		assert.is_true(picker.Marker:IsShown())
		assert.same({ "CENTER", UIParent, "CENTER", 240, -270 }, picker.Marker.point)
		w.mouseAt = { 0, 0 }
		picker:Fire("OnClick", "RightButton") -- cancels
		assert.is_false(picker:IsShown())
		assert.same({ 240, -270 }, ns.db.cursorStart)
	end)

	it("tunes the native cursor", function()
		local speed = controlFor("Speed")
		assert.equal("Normal", speed.Label:GetText())
		speed:Fire("OnClick")
		wow.entry(w.menu.root, "Fast").callback()
		assert.equal("1.5", w.cvars.GamePadCursorSpeedMax)
		w.cvars.GamePadCursorAutoEnable = "1"
		local auto = controlFor("Show it when a window opens")
		auto:Refresh()
		assert.is_true(auto.Check:IsShown())
		auto:Fire("OnClick")
		assert.equal("0", w.cvars.GamePadCursorAutoEnable)
		local hide = controlFor("Hide it")
		assert.equal("When either stick moves", hide.Label:GetText())
		hide:Fire("OnClick")
		wow.entry(w.menu.root, "Never").callback()
		assert.equal("0", w.cvars.GamePadCursorAutoDisableSticks)
		controlFor("Touchpad moves it"):Fire("OnClick")
		assert.equal("1", w.cvars.GamePadTouchCursorEnable)
	end)

	it("picks a play style, Auto naming the one the spec plays", function()
		local style = controlFor("Style")
		assert.equal("Keep my own settings", style.Label:GetText())
		style:Fire("OnClick")
		assert.equal("Auto (Ranged)", w.menu.root.entries[2].text)
		wow.entry(w.menu.root, "Healer").callback()
		assert.equal("healer", ns.db.playstyle)
		assert.equal("0", w.cvars.GamePadFaceMovementMaxAngleCombat)
		assert.equal("1", w.cvars.SoftTargetFriend)
		assert.equal("Healer", style.Label:GetText())
		wow.entry(w.menu.root, "Keep my own settings").callback()
		assert.is_nil(ns.db.playstyle)
		w.spec = nil
		style:Fire("OnClick")
		assert.equal("Auto", w.menu.root.entries[2].text)
	end)

	it("sets soft targeting with Blizzard's flags", function()
		local enemies = controlFor("Enemies")
		assert.equal("Gamepad", enemies.Label:GetText())
		enemies:Fire("OnClick")
		assert.same({ OFF, "Gamepad", "Keyboard and mouse", ALWAYS }, labels(w.menu.root))
		wow.entry(w.menu.root, ALWAYS).callback()
		assert.equal("3", w.cvars.SoftTargetEnemy)
		w.cvars.SoftTargetFriend = nil
		ns.RefreshOptions()
		assert.equal(OFF, controlFor("Friends").Label:GetText())
	end)

	it("runs the setup actions and opens Blizzard's key bindings", function()
		button("Reset layout..."):Fire("OnClick")
		assert.same({ "LEANPAD_SETUP" }, w.popups)
		button("Undo reset"):Fire("OnClick")
		assert.is_nil(ns.db.undo)
		assert.is_table(ns.db.backup)
		button("Undo setup"):Fire("OnClick")
		assert.is_nil(ns.db.backup)
		button(KEY_BINDINGS):Fire("OnClick")
		assert.same({ Settings.KEYBINDINGS_CATEGORY_ID }, w.opened)
	end)

	it("names the bar addon that runs the action bars, if any", function()
		assert.is_nil(find("FontString", function(widget) return widget.parent == page.Controls and (widget.text or ""):find("runs your action bars") end))
		ns, w = wow.boot(nil)
		w.addons.Dominos = true
		ns.OpenOptions()
		page = LeanPadControllerFrame.Options
		assert.is_truthy(find("FontString", function(widget) return widget.parent == page.Controls and widget.text == ns.BarAddonNote("Dominos") end))
	end)

	it("sizes its own window on top of the UI scale, and keeps the size for next time", function()
		local size = find("Button", function(widget) return widget.parent == page and widget.point and widget.point[1] == "TOPRIGHT" and widget.point[3] == -42 end)
		assert.equal("100%", size.Label:GetText())
		size:Fire("OnClick")
		wow.entry(w.menu.root, "125%").callback()
		assert.equal(1.25, ns.db.windowScale)
		assert.equal(1.25, frame.scale)
		local fresh = wow.boot({ windowScale = 0.9 })
		fresh.SetWindowScale(0.8) -- no window yet
		fresh.ToggleController()
		assert.equal(0.8, LeanPadControllerFrame.scale)
	end)

	it("explains each Setup action in the footer on hover", function()
		local undo = button("Undo reset")
		undo:Fire("OnEnter")
		assert.equal("Bring back the controller layout from before the last reset. Also /lp undo.", w.tooltip.text)
		undo:Fire("OnLeave")
		assert.is_nil(w.tooltip)
	end)

	it("has nothing to refresh before the page exists", function()
		local fresh = wow.boot(nil)
		assert.has_no.errors(fresh.RefreshOptions)
	end)
end)
