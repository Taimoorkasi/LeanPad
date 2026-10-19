local addonName, ns = ...

local MODIFIER_KEYS = { "none", "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4" }
local CLICK_KEYS = { "none", "PAD1", "PAD2", "PAD3", "PAD4", "PADLSTICK", "PADRSTICK", "PADLSHOULDER", "PADRSHOULDER", "PADRTRIGGER" }

local function keyOptions(keys)
	return function()
		local container = Settings.CreateControlTextContainer()
		for _, key in ipairs(keys) do
			container:Add(key, key == "none" and NONE or GetBindingText(key))
		end
		return container:GetData()
	end
end

local function softTargetOptions()
	local flags, container = Enum.SoftTargetEnableFlags, Settings.CreateControlTextContainer()
	container:Add(flags.None, OFF)
	container:Add(flags.Gamepad, "Gamepad")
	container:Add(flags.Kbm, "Keyboard and mouse")
	container:Add(flags.Any, ALWAYS)
	return container:GetData()
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	local category, layout = Settings.RegisterVerticalLayoutCategory("LeanPad")
	ns.category = category

	local function header(text) layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end
	local function button(name, text, click, tooltip)
		layout:AddInitializer(CreateSettingsButtonInitializer(name, text, click, tooltip, true))
	end

	header("Setup")
	button("Controller setup", "Set up", function() StaticPopup_Show("LEANPAD_SETUP") end,
		"Turn on the gamepad, set the trigger modifiers and soft targeting, and bind the controller to Action Bars 1-4.")
	button("Undo setup", "Restore", function() ns.OutOfCombat(ns.Restore) end,
		"Put back the controller settings and bindings from before LeanPad's setup.")
	button("Crossbar layers", "Action Bars", function() Settings.OpenToCategory(Settings.ACTION_BAR_CATEGORY_ID) end,
		"LT, RT and LT+RT use Action Bars 2, 3 and 4. Show them here, then place them in Edit Mode.")
	button("Edit bindings", "Key Bindings", function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end,
		"Change any binding in Blizzard's key binding editor.")

	header("Gamepad")
	Settings.SetupCVarCheckbox(category, "GamePadEnable", "Enable gamepad")
	local S = Settings.VarType.String
	Settings.SetupCVarDropdown(category, "GamePadEmulateShift", S, keyOptions(MODIFIER_KEYS), "Shift button")
	Settings.SetupCVarDropdown(category, "GamePadEmulateCtrl", S, keyOptions(MODIFIER_KEYS), "Ctrl button")
	Settings.SetupCVarDropdown(category, "GamePadEmulateAlt", S, keyOptions(MODIFIER_KEYS), "Alt button")
	Settings.SetupCVarDropdown(category, "GamePadCursorLeftClick", S, keyOptions(CLICK_KEYS), "Cursor left click")
	Settings.SetupCVarDropdown(category, "GamePadCursorRightClick", S, keyOptions(CLICK_KEYS), "Cursor right click")

	header("Soft targeting")
	local N = Settings.VarType.Number
	Settings.SetupCVarDropdown(category, "SoftTargetEnemy", N, softTargetOptions, "Enemies")
	Settings.SetupCVarDropdown(category, "SoftTargetFriend", N, softTargetOptions, "Friends")
	Settings.SetupCVarDropdown(category, "SoftTargetInteract", N, softTargetOptions, "Interact")

	Settings.RegisterAddOnCategory(category)
end)
