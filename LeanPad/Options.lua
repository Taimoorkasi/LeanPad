local addonName, ns = ...

-- LeanPad's own settings page inside the controller window. Blizzard's Settings panel stays the way in.
local C = ns.COLORS
-- CONTROL: every row's control, wide enough for the longest crossbar view.
local MARGIN, GAP, COLUMN, ROW, CONTROL = 16, 16, 432, 32, 250
local SOFT_TARGETS = { "SoftTargetEnemy", "SoftTargetFriend", "SoftTargetInteract" }
local SOFT_TARGET_LABELS = { "Enemies", "Friends", "Interact" }
local STYLES = { { "auto", "Auto" }, { "xbox", "Xbox" }, { "playstation", "PlayStation" } }
local CROSSBARS = {
	{ "off", OFF }, { "active", "One set, swaps with the held layer" }, { "all", "All layers, the held one large" },
	{ "strip", "One row, swaps with the held layer" }, { "ghost", "One row, faint until a layer is held" },
	{ "grid", "Square grid, swaps with the held layer" }, { "rows", "Square rows, one per layer" }, { "stacked", "Stacked rows, one per layer" },
}
local SCALES = { { "0.6", "60%" }, { "0.8", "80%" }, { "1", "100%" }, { "1.2", "120%" } }
local OPACITIES = { { "1", "100%" }, { "0.8", "80%" }, { "0.6", "60%" }, { "0.4", "40%" } }
local PLAYSTYLES = { { "manual", "Keep my own settings" }, { "auto", "Auto" }, { "tank", "Tank" }, { "melee", "Melee" }, { "ranged", "Ranged" }, { "healer", "Healer" } }
local SPEEDS = { { "0.6", "Slow" }, { "1", "Normal" }, { "1.5", "Fast" } }
local WINDOW_SCALES = { { "0.8", "80%" }, { "0.9", "90%" }, { "1", "100%" }, { "1.1", "110%" }, { "1.25", "125%" } }
local STICK_HIDES ={ { "0", "Never" }, { "1", "When the character moves" }, { "2", "When either stick moves" } }
local CLICKS = { { "GamePadCursorLeftClick", "Left click" }, { "GamePadCursorRightClick", "Right click" } }
local INFO_ICON = "Interface\\common\\help-i" -- Blizzard's own (i), from its help plates
-- What each row does, shown on hovering its (i); rows whose label isn't unique pass their own.
local HELP = {
	["Gamepad input"] = "Turns WoW's own gamepad support on or off. LeanPad needs it on.",
	["Active pad"] = "Which connected controller WoW listens to. All connected takes input from every pad.",
	["Button labels"] = "The button names and glyphs LeanPad shows: Xbox or PlayStation. Auto follows the pad in use.",
	["Style"] = "How your character turns and whom the pad aims at, set for your role: tanks keep facing the pack, healers move freely and aim at friends. Auto follows your spec; Keep my own settings leaves them alone.",
	["Enemies"] = "When the pad aims at enemies by itself, without you picking a target first.",
	["Friends"] = "When the pad aims at friendly players and NPCs by itself, for heals and buffs.",
	["Interact"] = "When the pad picks the nearest NPC or object for the Interact button, to talk, loot or gather.",
	["View"] = "How the crossbar shows your layers: one set that swaps as you hold a layer button, all of them at once, or a row or grid. Off hides it.",
	["Opacity"] = "How see-through the crossbar is.",
	["Show empty buttons"] = "Shows crossbar buttons with nothing on them, so you can see where spells can go.",
	["Mouse: click, drop spells, see tooltips"] = "Lets the mouse or gamepad cursor click crossbar buttons, drop spells on them and show their tooltips. Off, the crossbar ignores the mouse.",
	["Left click"] = "The pad button that clicks like the mouse's left button while the cursor is up.",
	["Right click"] = "The pad button that clicks like the mouse's right button while the cursor is up.",
	["Speed"] = "How fast the gamepad cursor moves.",
	["Toggle starts it at x, y"] = "Where Toggle gamepad cursor puts the cursor, as an offset from the screen's centre. Blank leaves it where it was; Pick sets it by clicking the spot.",
	["Show it when a window opens"] = "Brings the cursor up by itself when a window such as your bags or a vendor opens.",
	["Hide it"] = "Puts the cursor away when you move your character, or when either stick moves.",
	["Touchpad moves it"] = "On pads with a touchpad, such as the DualSense, sliding a finger moves the cursor.",
	["Talk and do quests in LeanPad's window"] = "Uses LeanPad's window instead of Blizzard's for talking to NPCs and doing quests, answered from the pad.",
	["Show the NPC in 3D, talking"] = "The NPC stands beside their words as a 3D model, talking. Off shows a round portrait.",
	["Text writes itself in"] = "The NPC's words appear a few letters at a time. A first shows them all, then answers.",
	["Zoom the camera in on the NPC"] = "Moves the camera in close while you talk, and back out after.",
	["Answer pop-ups with the pad"] = "Lets the pad press the buttons on Blizzard's pop-ups, such as group invites, Release Spirit and the dungeon queue.",
	["See it in place"] = "Shows the window with sample words, where and as large as it will appear, so you can try your settings.",
}

-- The settings page, the tab or page the helpers below are building on, and every control to refresh.
local page, parent, controls

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
	dropdown = ns.Dropdown(parent, CONTROL, function() return ns.LabelOf(list(), current()) end, function(root)
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
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(CONTROL, 28)
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
		boxes[axis] = ns.Input(holder, 74, function()
			local spot = ns.db.cursorStart
			return spot and tostring(spot[axis]) or ""
		end, commit)
		boxes[axis]:SetPoint("RIGHT", holder, "RIGHT", (axis - 3) * 88, 0)
	end
	holder.X, holder.Y = boxes[1], boxes[2]
	holder.Pick = ns.Button(holder, "Pick...", 74, function()
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
	local box = ns.Checkbox(parent, function() return GetCVar(cvar) == "1" end, function(on) ns.WriteCVar(cvar, on and "1" or "0") end)
	table.insert(controls, box)
	return box
end

-- A section heading: small amber capitals over a hairline across the column, so sections read apart from rows.
local function heading(x, y, text)
	local title = ns.Text(parent, 11, C.accent)
	title:SetPoint("TOPLEFT", x, -y)
	title:SetText(text:upper())
	local rule = ns.Rule(parent)
	rule:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + 17))
	rule:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + COLUMN, -(y + 17))
	return y + 26, title
end

-- A row: its label, an (i) that says what it does on hover, and its control at the column's right.
local function row(x, y, label, control, help)
	local text = ns.Text(parent, 13, C.text2)
	text:SetPoint("LEFT", parent, "TOPLEFT", x, -(y + ROW / 2))
	text:SetText(label)
	help = help or HELP[label]
	if help then
		text.Info = CreateFrame("Button", nil, parent)
		text.Info:SetSize(18, 18)
		text.Info:SetPoint("LEFT", text, "RIGHT", 4, 0)
		local mark = text.Info:CreateTexture(nil, "ARTWORK")
		mark:SetAllPoints()
		mark:SetTexture(INFO_ICON)
		text.Info:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(help, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		text.Info:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	control:SetPoint("RIGHT", parent, "TOPLEFT", x + COLUMN, -(y + ROW / 2))
	return y + ROW
end

-- Muted help under a section, in as many lines as given.
local function note(x, y, text, lines)
	local line = ns.Text(parent, 11, C.muted)
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
	for _, layer in ipairs(ns.LayerButtons()) do
		y = row(x, y, layer[2], choice(ns.KeyOptions(ns.MODIFIER_KEYS), function() return ns.LayerButtonKey(layer[1]) end,
			function(key) ns.SetLayerButton(layer[1], key) end), "The button you hold to use this layer's set of actions.")
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
	if addon then note(x, y + 8 + GAP, ns.BarAddonNote(addon), 3) end
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
	local button = ns.Button(parent, "", CONTROL, function(self)
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
	end), "How large the crossbar is drawn.")
	y = row(x, y, "Opacity", choice(OPACITIES, function() return tostring(ns.db.crossbarAlpha or 1) end, function(value)
		ns.SetCrossbarOpacity(tonumber(value))
		ns.Saved()
	end))
	y = row(x, y, "Position", lockButton(), "Unlock to drag the crossbar, its sets or single buttons where you want them; lock to keep them there.")
	local empty = ns.Checkbox(parent, ns.ShowEmptySockets, function(on)
		ns.SetCrossbarEmpty(on)
		ns.Saved()
	end)
	table.insert(controls, empty)
	y = row(x, y, "Show empty buttons", empty)
	local mouse = ns.Checkbox(parent, function() return ns.db.crossbarMouse == true end, function(on)
		ns.SetCrossbarMouse(on)
		ns.Saved()
	end)
	table.insert(controls, mouse)
	y = row(x, y, "Mouse: click, drop spells, see tooltips", mouse) + GAP
	local cursorTitle
	y, cursorTitle = heading(x, y, "Cursor")
	-- Beside the heading when nothing can bring the cursor up, since its clicks would then do nothing.
	local warning = ns.Text(parent, 11, { 1, 0.314, 0.314 })
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
		local spec, specName = C_SpecializationInfo.GetSpecializationInfo(index)
		local submenu = root:CreateButton(("%s: %s"):format(specName, ns.char.specs[spec] or NONE))
		ns.Radios(submenu, links, function() return ns.char.specs[spec] or false end, function(name) ns.LinkSpec(spec, name) end)
	end
end

local function checkbox(isChecked, onToggle)
	local box = ns.Checkbox(parent, isChecked, function(on)
		onToggle(on)
		ns.Saved()
	end)
	table.insert(controls, box)
	return box
end

-- How the dialogue window looks, set and saved, then shown where it stands.
local function look(key, convert)
	return function(value)
		ns.db[key] = convert and convert(value) or value
		ns.PlaceDialogue()
		ns.Saved()
	end
end

-- LeanPad's window for NPCs and quests, and pop-ups, with the real window to preview.
local function buildDialogue(x, y)
	y = heading(x, y, "NPCs and quests")
	y = row(x, y, "Talk and do quests in LeanPad's window", checkbox(ns.QuestPromptsEnabled, function(on)
		ns.db.questPrompts = on
		ns.ClaimDialogues()
	end))
	y = row(x, y, "Position", choice(ns.DIALOGUE_POSITIONS, ns.DialoguePosition, look("dialoguePosition")),
		"Where on screen the window appears, at any of nine places.")
	y = row(x, y, "Size", choice(WINDOW_SCALES, function() return tostring(ns.db.dialogueScale or 1) end, look("dialogueScale", tonumber)),
		"How large the window and its words are.")
	y = row(x, y, "Show the NPC in 3D, talking", checkbox(function() return ns.db.dialogueModel ~= false end, look("dialogueModel")))
	y = row(x, y, "Text writes itself in", checkbox(function() return ns.db.dialogueReveal ~= false end, function(on) ns.db.dialogueReveal = on end))
	y = row(x, y, "Zoom the camera in on the NPC", checkbox(function() return ns.db.dialogueCamera == true end, function(on) ns.db.dialogueCamera = on end))
	y = note(x, y, "A confirms, B backs out, the D-pad chooses and the bumpers scroll. A conversation started in combat opens in Blizzard's window, so the pad stays on your abilities.", 2) + GAP
	y = heading(x, y, "Pop-ups")
	y = row(x, y, "Answer pop-ups with the pad", checkbox(ns.PopupsEnabled, function(on)
		ns.db.padPopups = on
		ns.UpdatePopups()
	end))
	note(x, y, "A, B, X and Y press a pop-up's buttons from left to right, the dungeon queue and ready checks included. In combat they wait for the cursor.", 2)

	x = MARGIN + COLUMN + GAP
	y = heading(x, 97, "Preview")
	local preview = ns.Button(parent, "Show or hide", CONTROL, function() ns.PreviewDialogue(not ns.DialoguePreviewing()) end)
	preview:SetHeight(28)
	y = row(x, y, "See it in place", preview)
	note(x, y, "It follows your changes here as you make them. B closes it too.", 1)
	-- Leaving the tab, or the window, closes it.
	parent:SetScript("OnHide", function() ns.PreviewDialogue(false) end)
end

-- Tabs under the title bar, each with its own settings: the controller's, and the dialogue window's and pop-ups'.
local TABS = { { "Controls", "Controls" }, { "Dialogue", "Dialogue" } }

-- Shows one tab's settings, its name lit and underlined in amber.
function ns.ShowSettingsTab(key)
	for _, tab in ipairs(page.Tabs) do
		local on = tab.key == key
		page[tab.key]:SetShown(on)
		tab:SetNormalFontObject(ns.Font(16, on and C.text or C.text2))
		tab.Underline:SetShown(on)
	end
end

function ns.BuildOptions(frame)
	if page then return page end
	page = CreateFrame("Frame", nil, frame)
	page:SetAllPoints()
	frame.Options = page
	parent, controls = page, {}

	local back = ns.Button(page, "Controller", 110, function() ns.ShowPage("editor") end)
	back:SetHeight(28)
	back:SetPoint("TOPLEFT", MARGIN, -42)
	local arrow = back:CreateTexture(nil, "ARTWORK")
	arrow:SetAtlas("common-icon-backarrow")
	arrow:SetSize(12, 12)
	arrow:SetPoint("LEFT", 10, 0)
	back:GetFontString():SetPoint("LEFT", 28, 0)
	page.Tabs = {}
	local anchor, gap = back, 14
	for i, info in ipairs(TABS) do
		local tab = CreateFrame("Button", nil, page)
		tab.key = info[1]
		tab:SetNormalFontObject(ns.Font(16, C.text2))
		tab:SetHighlightFontObject(ns.Font(16, C.text))
		tab:SetText(info[2])
		tab:SetSize(tab:GetTextWidth() + 24, 28)
		tab:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
		tab.Underline = tab:CreateTexture(nil, "ARTWORK")
		tab.Underline:SetColorTexture(unpack(C.accent))
		tab.Underline:SetHeight(2)
		tab.Underline:SetPoint("BOTTOMLEFT", 12, -2)
		tab.Underline:SetPoint("BOTTOMRIGHT", -12, -2)
		tab:SetScript("OnClick", function() ns.ShowSettingsTab(tab.key) end)
		page[tab.key] = CreateFrame("Frame", nil, page)
		page[tab.key]:SetAllPoints()
		page.Tabs[i], anchor, gap = tab, tab, 4
	end
	local profile = ns.Dropdown(page, 220, function() return "Profile: " .. (ns.char.profile or NONE) end, profileMenu)
	profile:SetPoint("LEFT", anchor, "RIGHT", 24, 0)
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

	local footer = ns.Rule(page)
	footer:SetPoint("TOPLEFT", 0, -616)
	footer:SetPoint("TOPRIGHT", 0, -616)
	page.Status = ns.Text(page, 12, C.muted)
	page.Status:SetPoint("LEFT", page, "TOPLEFT", MARGIN, -640)
	page.Status:SetText("Settings apply as you change them")
	page.Saved = ns.Text(page, 12, C.accent)
	page.Saved:SetPoint("LEFT", page, "TOPLEFT", MARGIN, -640)
	page.Saved:Hide()

	parent = page.Controls
	buildLeft(MARGIN, 97)
	buildRight(MARGIN + COLUMN + GAP, 97)
	-- Setup's actions share the footer with Key Bindings; each says what it does on hover.
	local bindings = ns.Button(parent, KEY_BINDINGS, 120, function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end)
	bindings:SetPoint("TOPRIGHT", -MARGIN, -624)
	local undo = ns.Button(parent, "Undo setup", 110, function() ns.OutOfCombat(ns.Restore) end, false,
		"Return to your controller settings and bindings from before LeanPad. Also /lp restore.")
	undo:SetPoint("RIGHT", bindings, "LEFT", -8, 0)
	local undoReset = ns.Button(parent, "Undo reset", 110, function() ns.OutOfCombat(ns.UndoReset) end, false,
		"Bring back the controller layout from before the last reset. Also /lp undo.")
	undoReset:SetPoint("RIGHT", undo, "LEFT", -8, 0)
	local reset = ns.Button(parent, "Reset layout...", 130, function() ns.ShowReset() end, false,
		"Clear your controller bindings and start over on LeanPad's layout. Your current layout is saved first.")
	reset:SetPoint("RIGHT", undoReset, "LEFT", -8, 0)
	parent = page.Dialogue
	buildDialogue(MARGIN, 97)
	parent = page
	ns.ShowSettingsTab("Controls")
	return page
end

-- Re-reads every control, after a CVar or saved-variable change.
function ns.RefreshOptions()
	if not page then return end
	for _, control in ipairs(controls) do control:Refresh() end
end
