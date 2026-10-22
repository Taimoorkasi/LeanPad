local addonName, ns = ...

-- Blizzard's Settings panel is the way in: it opens LeanPad's window, runs setup and links to Key Bindings.
-- The options themselves live on the window's Settings page, in Options.lua.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	local category, layout = Settings.RegisterVerticalLayoutCategory("LeanPad")
	ns.category = category

	local function button(name, text, click, tooltip)
		layout:AddInitializer(CreateSettingsButtonInitializer(name, text, click, tooltip, true))
	end

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Setup"))
	button("Controller layout", "Open", function() ns.ToggleController() end,
		"See and change what every controller button does, per layer. Also /lp.")
	button("Settings", "Open", function() ns.OpenOptions() end,
		"Layer buttons, controller, cursor clicks, crossbar and soft targeting. Also /lp settings.")
	button("Controller setup", "Set up", ns.ShowSetup,
		"Turn on the gamepad. If you have no layout yet, also set the trigger modifiers and soft targeting and bind the controller to Action Bars 1-4; an existing layout is kept unless you choose otherwise.")
	button("Undo setup", "Restore", function() ns.OutOfCombat(ns.Restore) end,
		"Put back the controller settings and bindings from before LeanPad's setup.")
	button("Crossbar layers", "Action Bars", function() Settings.OpenToCategory(Settings.ACTION_BAR_CATEGORY_ID) end,
		"LT, RT and LT+RT use Action Bars 2, 3 and 4. Show them here, then place them in Edit Mode.")
	button("Edit bindings", "Key Bindings", function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end,
		"Change any binding in Blizzard's key binding editor.")

	Settings.RegisterAddOnCategory(category)
end)
