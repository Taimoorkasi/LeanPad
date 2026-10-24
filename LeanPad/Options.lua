local _, ns = ...

-- LeanPad's own settings page inside the controller window. Blizzard's Settings panel stays the way in.
local C = ns.COLORS
local MARGIN, GAP, COLUMN, ROW = 16, 16, 432, 32
local SOFT_TARGETS = { "SoftTargetEnemy", "SoftTargetFriend", "SoftTargetInteract" }
local SOFT_TARGET_LABELS = { "Enemies", "Friends", "Interact" }
local STYLES = { { "auto", "Auto" }, { "xbox", "Xbox" }, { "playstation", "PlayStation" } }
local CROSSBARS = { { "off", OFF }, { "active", "One set, swaps with the held layer" }, { "all", "All layers, the held one large" } }
local SCALES = { { "0.6", "60%" }, { "0.8", "80%" }, { "1", "100%" }, { "1.2", "120%" } }
local OPACITIES = { { "1", "100%" }, { "0.8", "80%" }, { "0.6", "60%" }, { "0.4", "40%" } }
local PLAYSTYLES = { { "manual", "Keep my own settings" }, { "auto", "Auto" }, { "tank", "Tank" }, { "melee", "Melee" }, { "ranged", "Ranged" }, { "healer", "Healer" } }
local SPEEDS = { { "0.6", "Slow" }, { "1", "Normal" }, { "1.5", "Fast" } }
local STICK_HIDES = { { "0", "Never" }, { "1", "When the character moves" }, { "2", "When either stick moves" } }
local LAYER_BUTTONS = {
	{ "GamePadEmulateShift", "Layer 1, acts as Shift" }, { "GamePadEmulateCtrl", "Layer 2, acts as Ctrl" }, { "GamePadEmulateAlt", "Layer 3, acts as Alt" },
}
local CLICKS = { { "GamePadCursorLeftClick", "Left click" }, { "GamePadCursorRightClick", "Right click" } }

local page, controls

local function softTargetOptions()
	local flags = Enum.SoftTargetEnableFlags
	return { { tostring(flags.None), OFF }, { tostring(flags.Gamepad), "Gamepad" }, { tostring(flags.Kbm), "Keyboard and mouse" }, { tostring(flags.Any), ALWAYS } }
end

-- Every pad the client sees, after All connected, which is Blizzard's combined input.
local function deviceOptions()
	local options = { { "0", "All connected" } }
	for _, id in ipairs(C_GamePad.GetAllDeviceIDs()) do
		local state = C_GamePad.GetDeviceMappedState(id)
		table.insert(options, { tostring(id), state and state.name or ("Controller " .. id) })
	end
	return options
end

-- Auto names the style the current spec plays.
local function playstyleOptions()
	local options, spec = {}, ns.SpecStyle()
	for _, style in ipairs(PLAYSTYLES) do
		local label = style[2]
		if style[1] == "auto" and spec then label = ("Auto (%s)"):format(ns.LabelOf(PLAYSTYLES, spec)) end
		table.insert(options, { style[1], label })
	end
	return options
end

local function styleOptions()
	local options = {}
	for _, style in ipairs(STYLES) do
		local label = style[2]
		if style[1] == "auto" then label = ("Auto (%s)"):format(ns.LabelOf(STYLES, ns.DetectedStyle())) end
		table.insert(options, { style[1], label })
	end
	return options
end

-- A dropdown over value/label options; options may be a function when the choices depend on the pads connected.
local function choice(options, current, set)
	local function list() return type(options) == "function" and options() or options end
	local dropdown
	dropdown = ns.Dropdown(page, 200, function() return ns.LabelOf(list(), current()) end, function(root)
		ns.Radios(root, list(), current, function(value)
			set(value)
			dropdown:Refresh()
		end)
	end)
	table.insert(controls, dropdown)
	return dropdown
end

local function cvarChoice(options, cvar, default)
	return choice(options, function() return GetCVar(cvar) or default end, function(value) ns.WriteCVar(cvar, value) end)
end

local function keyChoice(keys, cvar)
	return choice(ns.KeyOptions(keys), function() return GetCVar(cvar) or "none" end, function(value) ns.WriteCVar(cvar, value) end)
end

local function cvarCheckbox(cvar)
	local box = ns.Checkbox(page, function() return GetCVar(cvar) == "1" end, function(on) ns.WriteCVar(cvar, on and "1" or "0") end)
	table.insert(controls, box)
	return box
end

local function heading(x, y, text)
	local title = ns.Text(page, 13, C.text)
	title:SetPoint("TOPLEFT", x, -y)
	title:SetText(text)
	return y + 20
end

local function row(x, y, label, control)
	local text = ns.Text(page, 13, C.text2)
	text:SetPoint("LEFT", page, "TOPLEFT", x, -(y + ROW / 2))
	text:SetText(label)
	control:SetPoint("RIGHT", page, "TOPLEFT", x + COLUMN, -(y + ROW / 2))
	return y + ROW
end

local function note(x, y, text)
	local line = ns.Text(page, 12, C.muted)
	line:SetPoint("TOPLEFT", x, -y)
	line:SetWidth(COLUMN)
	line:SetText(text)
	return y + 34
end

local function buildLeft(x, y)
	y = heading(x, y, "Controller")
	y = row(x, y, "Gamepad input", cvarCheckbox("GamePadEnable"))
	y = row(x, y, "Active pad", cvarChoice(deviceOptions, "GamePadSingleActiveID", "0"))
	y = row(x, y, "Button labels", choice(styleOptions, function() return ns.db.padStyle or "auto" end, function(value)
		ns.db.padStyle = value
		ns.RefreshController()
		ns.Saved()
	end))
	y = y + GAP
	y = heading(x, y, "Layer buttons")
	for _, layer in ipairs(LAYER_BUTTONS) do
		y = row(x, y, layer[2], choice(ns.KeyOptions(ns.MODIFIER_KEYS), function() return GetCVar(layer[1]) or "none" end,
			function(key) ns.SetLayerButton(layer[1], key) end))
	end
	y = note(x, y, "Hold a layer button to use its layer. Layer buttons fire nothing themselves: a button made one loses its own bindings.") + GAP
	y = heading(x, y, "Play style")
	y = row(x, y, "Style", choice(playstyleOptions, function() return ns.db.playstyle or "manual" end, function(value)
		ns.db.playstyle = value ~= "manual" and value or nil
		ns.ApplyPlaystyle()
		ns.Saved()
	end))
	for i, cvar in ipairs(SOFT_TARGETS) do
		y = row(x, y, SOFT_TARGET_LABELS[i], cvarChoice(softTargetOptions(), cvar, "0"))
	end
end

local function crossbarChoice()
	return choice(CROSSBARS, function() return ns.db.crossbar == false and "off" or (ns.db.crossbarStyle or "active") end, function(value)
		if value ~= "off" then ns.SetCrossbarStyle(value) end
		ns.SetCrossbarShown(value ~= "off")
		ns.Saved()
	end)
end

-- Unlocks the crossbar for dragging; the button reads as the next thing it will do.
local function lockButton()
	local button = ns.Button(page, "", 200, function(self)
		ns.SetCrossbarLocked(not ns.CrossbarLocked())
		self:Refresh()
	end)
	button:SetHeight(28)
	function button:Refresh() self:SetText(ns.CrossbarLocked() and "Unlock to drag" or "Lock in place") end
	button:Refresh()
	table.insert(controls, button)
	return button
end

local function buildRight(x, y)
	y = heading(x, y, "Crossbar")
	y = row(x, y, "View", crossbarChoice())
	y = row(x, y, "Size", choice(SCALES, function() return tostring(ns.db.crossbarScale or 1) end, function(value)
		ns.SetCrossbarScale(tonumber(value))
		ns.Saved()
	end))
	y = row(x, y, "Opacity", choice(OPACITIES, function() return tostring(ns.db.crossbarAlpha or 1) end, function(value)
		ns.SetCrossbarOpacity(tonumber(value))
		ns.Saved()
	end))
	y = row(x, y, "Position", lockButton())
	local mouse = ns.Checkbox(page, function() return ns.db.crossbarMouse == true end, function(on)
		ns.SetCrossbarMouse(on)
		ns.Saved()
	end)
	table.insert(controls, mouse)
	y = row(x, y, "Mouse: drop spells on it, see tooltips", mouse) + GAP
	y = heading(x, y, "Cursor")
	for _, click in ipairs(CLICKS) do
		y = row(x, y, click[2], keyChoice(ns.CLICK_KEYS, click[1]))
	end
	y = row(x, y, "Speed", cvarChoice(SPEEDS, "GamePadCursorSpeedMax", "1"))
	y = row(x, y, "Show it when a window opens", cvarCheckbox("GamePadCursorAutoEnable"))
	y = row(x, y, "Hide it", cvarChoice(STICK_HIDES, "GamePadCursorAutoDisableSticks", "2"))
	y = row(x, y, "Touchpad moves it", cvarCheckbox("GamePadTouchCursorEnable")) + GAP
	y = heading(x, y, "Setup") + 4
	local reset = ns.Button(page, "Reset to default layout...", 200, function() StaticPopup_Show("LEANPAD_SETUP") end)
	reset:SetPoint("TOPLEFT", x, -y)
	local undoReset = ns.Button(page, "Undo reset", 200, function() ns.OutOfCombat(ns.UndoReset) end)
	undoReset:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	local undo = ns.Button(page, "Undo setup", 200, function() ns.OutOfCombat(ns.Restore) end)
	undo:SetPoint("LEFT", undoReset, "RIGHT", 8, 0)
	note(x, y + 38, "Reset clears your controller bindings and starts over on LeanPad's layout, saving your current layout first. Undo reset brings that layout back; Undo setup returns to how things were before LeanPad.")
end

function ns.BuildOptions(frame)
	if page then return page end
	page = CreateFrame("Frame", nil, frame)
	page:SetAllPoints()
	frame.Options = page
	controls = {}

	local back = ns.Button(page, "Controller", 110, function() ns.ShowPage("editor") end)
	back:SetHeight(28)
	back:SetPoint("TOPLEFT", MARGIN, -42)
	local arrow = back:CreateTexture(nil, "ARTWORK")
	arrow:SetAtlas("common-icon-backarrow")
	arrow:SetSize(12, 12)
	arrow:SetPoint("LEFT", 10, 0)
	back:GetFontString():SetPoint("LEFT", 28, 0)
	local title = ns.Text(page, 14, C.text)
	title:SetPoint("LEFT", back, "RIGHT", 12, 0)
	title:SetText(SETTINGS)

	buildLeft(MARGIN, 97)
	buildRight(MARGIN + COLUMN + GAP, 97)

	local footer = ns.Rule(page)
	footer:SetPoint("TOPLEFT", 0, -616)
	footer:SetPoint("TOPRIGHT", 0, -616)
	page.Status = ns.Text(page, 12, C.muted)
	page.Status:SetPoint("LEFT", page, "TOPLEFT", MARGIN, -640)
	page.Status:SetText("Settings apply as you change them")
	page.Saved = ns.Text(page, 12, C.accent)
	page.Saved:SetPoint("LEFT", page, "TOPLEFT", MARGIN, -640)
	page.Saved:Hide()
	local bindings = ns.Button(page, KEY_BINDINGS, 120, function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end)
	bindings:SetPoint("TOPRIGHT", -MARGIN, -624)
	return page
end

-- Re-reads every control, after a CVar or saved-variable change.
function ns.RefreshOptions()
	if not page then return end
	for _, control in ipairs(controls) do control:Refresh() end
end
