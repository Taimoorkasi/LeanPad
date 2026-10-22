local wow = require("spec.wow")

describe("Options page", function()
	local ns, w, frame, page

	local function find(kind, test)
		for _, widget in ipairs(w.widgets) do
			if widget.kind == kind and test(widget) then return widget end
		end
	end

	-- The control on a row, found through its label: both sit on the row's centre line.
	local function controlFor(label)
		local text = find("FontString", function(widget) return widget.parent == page and widget.text == label end)
		assert.is_truthy(text, label)
		return find("Button", function(widget)
			return widget.parent == page and widget.point[1] == "RIGHT" and widget.point[4] == text.point[4] + 432 and widget.point[5] == text.point[5]
		end)
	end

	local function button(text)
		return find("Button", function(widget) return widget.parent == page and widget.text == text end)
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
		assert.equal(NONE, controlFor("Layer 3, acts as Alt").Label:GetText())
		local left = controlFor("Left click")
		assert.equal("A", left.Label:GetText())
		left:Fire("OnClick")
		wow.entry(w.menu.root, "B").callback()
		assert.equal("PAD2", w.cvars.GamePadCursorLeftClick)
	end)

	it("toggles the crossbar and its layers", function()
		local show = controlFor("Show crossbar")
		assert.is_true(show.Check:IsShown())
		show:Fire("OnClick")
		assert.is_false(ns.db.crossbar)
		assert.is_false(show.Check:IsShown())
		local layers = controlFor("Layers shown")
		assert.equal("Held layer only", layers.Label:GetText())
		layers:Fire("OnClick")
		wow.entry(w.menu.root, "All layers").callback()
		assert.equal("all", ns.db.crossbarStyle)
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
		button("Reset to default layout..."):Fire("OnClick")
		assert.same({ "LEANPAD_SETUP" }, w.popups)
		button("Undo setup"):Fire("OnClick")
		assert.is_nil(ns.db.backup)
		button(KEY_BINDINGS):Fire("OnClick")
		assert.same({ Settings.KEYBINDINGS_CATEGORY_ID }, w.opened)
	end)

	it("has nothing to refresh before the page exists", function()
		local fresh = wow.boot(nil)
		assert.has_no.errors(fresh.RefreshOptions)
	end)
end)
