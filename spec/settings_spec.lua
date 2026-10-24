local wow = require("spec.wow")

local function find(list, field, value)
	for _, item in ipairs(list) do
		if item[field] == value then return item end
	end
end

describe("Settings", function()
	local ns, w
	before_each(function() ns, w = wow.boot(nil) end)
	after_each(wow.restore)

	it("registers a LeanPad category with Blizzard's settings panel", function()
		assert.equal("LeanPad", w.categoryName)
		assert.equal(w.category, w.registered)
		assert.equal(w.category, ns.category)
	end)

	it("is one Setup section of buttons; the options live on the window's own settings page", function()
		local headers = {}
		for _, item in ipairs(w.layout) do
			if item.kind == "header" then table.insert(headers, item.text) end
		end
		assert.same({ "Setup" }, headers)
		assert.same({}, w.controls)
	end)

	describe("buttons", function()
		local function click(name)
			local button = find(w.layout, "name", name)
			assert.is_truthy(button, name)
			assert.is_true(button.searchable)
			assert.is_string(button.tooltip)
			button.click()
		end

		it("Open shows the controller editor", function()
			click("Controller layout")
			assert.is_true(LeanPadControllerFrame:IsShown())
			assert.is_true(LeanPadControllerFrame.Editor:IsShown())
		end)

		it("Settings shows the window's settings page", function()
			click("Settings")
			assert.is_true(LeanPadControllerFrame:IsShown())
			assert.is_true(LeanPadControllerFrame.Options:IsShown())
		end)

		it("Set up shows the confirm dialog", function()
			click("Controller setup")
			assert.same({ "LEANPAD_SETUP" }, w.popups)
		end)

		it("Set up offers to keep an existing layout", function()
			w.bindings.PAD1 = "JUMP"
			click("Controller setup")
			assert.same({ "LEANPAD_SETUP_EXISTING" }, w.popups)
		end)

		it("Undo reset puts back the layout the last reset replaced", function()
			ns.Apply()
			click("Undo reset")
			assert.is_nil(ns.db.undo)
			assert.is_table(ns.db.backup)
		end)

		it("Restore restores, out of combat", function()
			ns.Apply()
			w.combat = true
			click("Undo setup")
			assert.is_table(ns.db.backup)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_nil(ns.db.backup)
		end)

		it("Action Bars opens Blizzard's action bar settings", function()
			click("Crossbar layers")
			assert.same({ Settings.ACTION_BAR_CATEGORY_ID }, w.opened)
		end)

		it("Key Bindings opens Blizzard's key binding editor", function()
			click("Edit bindings")
			assert.same({ Settings.KEYBINDINGS_CATEGORY_ID }, w.opened)
		end)
	end)
end)
