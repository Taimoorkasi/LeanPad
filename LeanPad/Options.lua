local addonName, ns = ...

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
local WINDOW_SCALES = { { "0.8", "80%" }, { "0.9", "90%" }, { "1", "100%" }, { "1.1", "110%" }, { "1.25", "125%" } }
local STICK_HIDES ={ { "0", "Never" }, { "1", "When the character moves" }, { "2", "When either stick moves" } }
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

-- Where Toggle gamepad cursor puts the cursor, as an x, y offset from the screen's centre in UI units, the way
-- frames are placed. Both blank leaves it where it was; one blank reads as 0.
-- Pick on screen: the screen dims, lines cross at its centre and a ring marks the spot set now; a left click,
-- by mouse or the gamepad cursor, sets the spot there. A right click or Escape leaves it as it was.
local picker
local function pickSpot(onPicked)
	if not picker then
		picker = CreateFrame("Button", "LeanPadCursorPicker", UIParent)
		picker:SetAllPoints(UIParent)
		picker:SetFrameStrata("FULLSCREEN_DIALOG")
		picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local shade = picker:CreateTexture(nil, "BACKGROUND")
		shade:SetAllPoints()
		shade:SetColorTexture(0, 0, 0, 0.5)
		for _, across in ipairs({ true, false }) do
			local line = picker:CreateTexture(nil, "ARTWORK")
			line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
			line:SetPoint("CENTER")
			if across then line:SetSize(4000, 1) else line:SetSize(1, 4000) end
		end
		picker.Marker = picker:CreateTexture(nil, "OVERLAY")
		picker.Marker:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Art\\Ring")
		picker.Marker:SetVertexColor(unpack(C.accent))
		picker.Marker:SetSize(36, 36)
		local hint = ns.Text(picker, 16, C.text, "CENTER")
		hint:SetPoint("TOP", 0, -140)
		hint:SetText("Click where Toggle gamepad cursor should put the cursor. The lines cross at the screen's centre.\nRight-click or Escape cancels.")
		-- Escape cancels here rather than through UISpecialFrames, which would close LeanPad's window as well.
		picker:EnableKeyboard(true)
		picker:SetScript("OnKeyDown", function(self, key)
			if key == "ESCAPE" then self:Hide() end
		end)
		-- LeanPad's window turns invisible while picking, so the whole screen can be picked; hiding it would
		-- reset the editor and leave the settings page.
		picker:SetScript("OnShow", function() ns.window:SetAlpha(0) end)
		picker:SetScript("OnHide", function() ns.window:SetAlpha(1) end)
		picker:Hide()
	end
	local spot = ns.db.cursorStart
	picker.Marker:SetShown(spot ~= nil)
	picker.Marker:SetPoint("CENTER", UIParent, "CENTER", spot and spot[1] or 0, spot and spot[2] or 0)
	picker:SetScript("OnClick", function(self, button)
		self:Hide()
		if button ~= "LeftButton" then return end
		local scale, x, y = UIParent:GetEffectiveScale(), GetCursorPosition()
		onPicked(math.floor(x / scale - UIParent:GetWidth() / 2 + 0.5), math.floor(y / scale - UIParent:GetHeight() / 2 + 0.5))
	end)
	picker:Show()
end

local function cursorStartInput()
	local holder = CreateFrame("Frame", nil, page)
	holder:SetSize(220, 28)
	local boxes = {}
	local function commit()
		local x, y = tonumber(boxes[1]:GetText()), tonumber(boxes[2]:GetText())
		ns.db.cursorStart = (x or y) and { x or 0, y or 0 } or nil
		holder:Refresh()
		ns.Saved()
	end
	function holder:Refresh()
		for _, box in ipairs(boxes) do box:Refresh() end
	end
	for axis = 1, 2 do
		boxes[axis] = ns.Input(holder, 64, function()
			local spot = ns.db.cursorStart
			return spot and tostring(spot[axis]) or ""
		end, commit)
		boxes[axis]:SetPoint("RIGHT", holder, "RIGHT", (axis - 3) * 72, 0)
	end
	holder.X, holder.Y = boxes[1], boxes[2]
	holder.Pick = ns.Button(holder, "Pick...", 64, function()
		pickSpot(function(x, y)
			ns.db.cursorStart = { x, y }
			holder:Refresh()
			ns.Saved()
		end)
	end, false, "Pick the spot on screen: lines show the centre, a ring the spot set now.")
	holder.Pick:SetHeight(28)
	holder.Pick:SetPoint("RIGHT")
	table.insert(controls, holder)
	return holder
end

local function cvarCheckbox(cvar)
	local box = ns.Checkbox(page, function() return GetCVar(cvar) == "1" end, function(on) ns.WriteCVar(cvar, on and "1" or "0") end)
	table.insert(controls, box)
	return box
end

-- A section heading: small amber capitals over a hairline across the column, so sections read apart from rows.
local function heading(x, y, text)
	local title = ns.Text(page, 11, C.accent)
	title:SetPoint("TOPLEFT", x, -y)
	title:SetText(text:upper())
	local rule = ns.Rule(page)
	rule:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(y + 17))
	rule:SetPoint("TOPRIGHT", page, "TOPLEFT", x + COLUMN, -(y + 17))
	return y + 26, title
end

local function row(x, y, label, control)
	local text = ns.Text(page, 13, C.text2)
	text:SetPoint("LEFT", page, "TOPLEFT", x, -(y + ROW / 2))
	text:SetText(label)
	control:SetPoint("RIGHT", page, "TOPLEFT", x + COLUMN, -(y + ROW / 2))
	return y + ROW
end

-- Muted help under a section, in as many lines as given.
local function note(x, y, text, lines)
	local line = ns.Text(page, 11, C.muted)
	line:SetPoint("TOPLEFT", x, -(y + 2))
	line:SetWidth(COLUMN)
	line:SetSpacing(2)
	line:SetText(text)
	return y + lines * 14 + 6
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
	y = note(x, y, "Hold one to use its layer. It fires nothing itself, so it loses its own bindings.", 1) + GAP
	y = heading(x, y, "Play style")
	y = row(x, y, "Style", choice(playstyleOptions, function() return ns.db.playstyle or "manual" end, function(value)
		ns.db.playstyle = value ~= "manual" and value or nil
		ns.ApplyPlaystyle()
		ns.Saved()
	end))
	for i, cvar in ipairs(SOFT_TARGETS) do
		y = row(x, y, SOFT_TARGET_LABELS[i], cvarChoice(softTargetOptions(), cvar, "0"))
	end
	local addon = ns.BarAddon()
	if addon then note(x, y + 8, ns.BarAddonNote(addon), 3) end
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
	y = row(x, y, "Mouse: click, drop spells, see tooltips", mouse) + GAP
	local cursorTitle
	y, cursorTitle = heading(x, y, "Cursor")
	-- Beside the heading when nothing can bring the cursor up, since its clicks would then do nothing.
	local warning = ns.Text(page, 11, { 1, 0.314, 0.314 })
	warning:SetPoint("LEFT", cursorTitle, "RIGHT", 10, 0)
	warning:SetText("Nothing brings it up: tick Show it when a window opens")
	table.insert(controls, { Refresh = function() warning:SetShown(not ns.CursorReachable()) end })
	controls[#controls].Refresh()
	for _, click in ipairs(CLICKS) do
		y = row(x, y, click[2], keyChoice(ns.CLICK_KEYS, click[1]))
	end
	y = row(x, y, "Speed", cvarChoice(SPEEDS, "GamePadCursorSpeedMax", "1"))
	y = row(x, y, "Toggle starts it at x, y", cursorStartInput())
	y = row(x, y, "Show it when a window opens", cvarCheckbox("GamePadCursorAutoEnable"))
	y = row(x, y, "Hide it", cvarChoice(STICK_HIDES, "GamePadCursorAutoDisableSticks", "2"))
	row(x, y, "Touchpad moves it", cvarCheckbox("GamePadTouchCursorEnable"))
end

-- Names come from Blizzard's input box; text may carry %s for the profile in use.
local function askName(text, done)
	StaticPopup_ShowCustomGenericInputBox({ text = text, text_arg1 = ns.char.profile, callback = done, acceptText = ACCEPT, maxLetters = 24 })
end

-- Switch to a profile, make, copy, rename or delete one, and pick the profile each spec switches to.
local function profileMenu(root)
	local current, names = ns.char.profile, {}
	for _, name in ipairs(ns.ProfileNames()) do table.insert(names, { name, name }) end
	ns.Radios(root, names, function() return ns.char.profile end, function(name) ns.SwitchProfile(name) end)
	root:CreateDivider()
	root:CreateButton("New from current setup...", function() askName("Name the new profile. It starts as your current setup.", ns.NewProfile) end)
	if current then
		root:CreateButton("Copy...", function() askName("Name the copy of %s.", ns.CopyProfile) end)
		root:CreateButton("Rename...", function() askName("Rename %s to:", ns.RenameProfile) end)
		root:CreateButton("Delete...", function()
			StaticPopup_ShowCustomGenericConfirmation({ text = "Delete profile %s? Your setup stays as it is now.", text_arg1 = current, callback = function() ns.DeleteProfile(current) end })
		end)
	end
	root:CreateDivider()
	root:CreateTitle("Switch profile when you change spec")
	local links = { { false, NONE } }
	for _, option in ipairs(names) do table.insert(links, option) end
	for index = 1, GetNumSpecializations() do
		local spec, specName = GetSpecializationInfo(index)
		local submenu = root:CreateButton(("%s: %s"):format(specName, ns.char.specs[spec] or NONE))
		ns.Radios(submenu, links, function() return ns.char.specs[spec] or false end, function(name) ns.LinkSpec(spec, name) end)
	end
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
	local title = ns.Text(page, 16, C.text)
	title:SetPoint("LEFT", back, "RIGHT", 14, 0)
	title:SetText(SETTINGS)
	local profile = ns.Dropdown(page, 220, function() return "Profile: " .. (ns.char.profile or NONE) end, profileMenu)
	profile:SetPoint("LEFT", title, "RIGHT", 24, 0)
	table.insert(controls, profile)
	-- LeanPad's window sits on the UI scale, which bar addons such as ElvUI change; this sizes it on top of that.
	local size = choice(WINDOW_SCALES, function() return tostring(ns.db.windowScale or 1) end, function(value)
		ns.SetWindowScale(tonumber(value))
		ns.Saved()
	end)
	size:SetWidth(100)
	size:SetHeight(28)
	size:SetPoint("TOPRIGHT", -MARGIN, -42)
	local sizeLabel = ns.Text(page, 13, C.text2)
	sizeLabel:SetPoint("RIGHT", size, "LEFT", -10, 0)
	sizeLabel:SetText("Window size")

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
	-- Setup's actions share the footer with Key Bindings; each says what it does on hover.
	local bindings = ns.Button(page, KEY_BINDINGS, 120, function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end)
	bindings:SetPoint("TOPRIGHT", -MARGIN, -624)
	local undo = ns.Button(page, "Undo setup", 110, function() ns.OutOfCombat(ns.Restore) end, false,
		"Return to your controller settings and bindings from before LeanPad. Also /lp restore.")
	undo:SetPoint("RIGHT", bindings, "LEFT", -8, 0)
	local undoReset = ns.Button(page, "Undo reset", 110, function() ns.OutOfCombat(ns.UndoReset) end, false,
		"Bring back the controller layout from before the last reset. Also /lp undo.")
	undoReset:SetPoint("RIGHT", undo, "LEFT", -8, 0)
	local reset = ns.Button(page, "Reset layout...", 130, function() StaticPopup_Show("LEANPAD_SETUP") end, false,
		"Clear your controller bindings and start over on LeanPad's layout. Your current layout is saved first.")
	reset:SetPoint("RIGHT", undoReset, "LEFT", -8, 0)
	return page
end

-- Re-reads every control, after a CVar or saved-variable change.
function ns.RefreshOptions()
	if not page then return end
	for _, control in ipairs(controls) do control:Refresh() end
end
