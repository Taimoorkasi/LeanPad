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

	it("lays out Setup, Gamepad and Soft targeting sections", function()
		local headers = {}
		for _, item in ipairs(w.layout) do
			if item.kind == "header" then table.insert(headers, item.text) end
		end
		assert.same({ "Setup", "Gamepad", "Soft targeting" }, headers)
	end)

	describe("buttons", function()
		local function click(name)
			local button = find(w.layout, "name", name)
			assert.is_truthy(button, name)
			assert.is_true(button.searchable)
			assert.is_string(button.tooltip)
			button.click()
		end

		it("Set up shows the confirm dialog", function()
			click("Controller setup")
			assert.same({ "LEANPAD_SETUP" }, w.popups)
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

	describe("controls", function()
		it("has a gamepad on/off checkbox", function()
			local control = find(w.controls, "variable", "GamePadEnable")
			assert.equal("checkbox", control.kind)
		end)

		it("picks modifier buttons by pad key, with None to turn one off", function()
			for _, cvar in ipairs({ "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }) do
				local control = find(w.controls, "variable", cvar)
				assert.equal("string", control.type)
				local options = control.options()
				assert.same({ value = "none", label = NONE }, options[1])
				assert.same({ value = "PADLTRIGGER", label = "text:PADLTRIGGER" }, find(options, "value", "PADLTRIGGER"))
				assert.is_truthy(find(options, "value", "PADPADDLE4"))
			end
		end)

		it("offers every button the setup preset assigns to a cursor click", function()
			for _, cvar in ipairs({ "GamePadCursorLeftClick", "GamePadCursorRightClick" }) do
				local options = find(w.controls, "variable", cvar).options()
				assert.is_truthy(find(options, "value", ns.CVARS[cvar]), cvar)
				assert.is_truthy(find(options, "value", "PADRTRIGGER"), "Blizzard's default")
			end
		end)

		it("offers every modifier button the setup preset assigns", function()
			for _, cvar in ipairs({ "GamePadEmulateShift", "GamePadEmulateCtrl" }) do
				assert.is_truthy(find(find(w.controls, "variable", cvar).options(), "value", ns.CVARS[cvar]), cvar)
			end
		end)

		it("sets soft targeting per target type with Blizzard's enable flags", function()
			local flags = Enum.SoftTargetEnableFlags
			for _, cvar in ipairs({ "SoftTargetEnemy", "SoftTargetFriend", "SoftTargetInteract" }) do
				local control = find(w.controls, "variable", cvar)
				assert.equal("number", control.type)
				assert.same({
					{ value = flags.None, label = OFF },
					{ value = flags.Gamepad, label = "Gamepad" },
					{ value = flags.Kbm, label = "Keyboard and mouse" },
					{ value = flags.Any, label = ALWAYS },
				}, control.options())
			end
		end)
	end)
end)
