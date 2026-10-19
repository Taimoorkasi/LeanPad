local _, ns = ...

-- Tabs list modifier layers left trigger first; binding keys spell them ALT-CTRL-SHIFT-, WoW's order.
local TAB_ORDER = { "SHIFT-", "CTRL-", "ALT-" }
local CANONICAL = { "ALT-", "CTRL-", "SHIFT-" }
local MODIFIER_CVARS = { ["SHIFT-"] = "GamePadEmulateShift", ["CTRL-"] = "GamePadEmulateCtrl", ["ALT-"] = "GamePadEmulateAlt" }

local function prefixOf(held)
	local prefix = ""
	for _, modifier in ipairs(CANONICAL) do
		if held[modifier] then prefix = prefix .. modifier end
	end
	return prefix
end

local function emulatedModifiers()
	local active = {}
	for _, modifier in ipairs(TAB_ORDER) do
		local key = GetCVar(MODIFIER_CVARS[modifier])
		if key and key ~= "" and key ~= "none" then
			table.insert(active, { modifier = modifier, key = key })
		end
	end
	return active
end

local function bitCount(mask)
	local count = 0
	while mask > 0 do
		count = count + mask % 2
		mask = math.floor(mask / 2)
	end
	return count
end

-- One layer per combination of the emulated modifiers: Base, LT, RT, LT+RT with the preset.
function ns.Layers()
	local active = emulatedModifiers()
	local masks = {}
	for mask = 0, 2 ^ #active - 1 do table.insert(masks, mask) end
	table.sort(masks, function(a, b)
		if bitCount(a) ~= bitCount(b) then return bitCount(a) < bitCount(b) end
		return a < b
	end)
	local layers = {}
	for _, mask in ipairs(masks) do
		local held, glyphs = {}, {}
		for i, entry in ipairs(active) do
			if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
				held[entry.modifier] = true
				table.insert(glyphs, GetBindingText(entry.key))
			end
		end
		table.insert(layers, { prefix = prefixOf(held), label = #glyphs > 0 and table.concat(glyphs, " + ") or "Base" })
	end
	return layers
end

function ns.ModifierKeys()
	local keys = {}
	for _, entry in ipairs(emulatedModifiers()) do keys[entry.key] = true end
	return keys
end

function ns.HeldPrefix()
	return prefixOf({ ["ALT-"] = IsAltKeyDown(), ["CTRL-"] = IsControlKeyDown(), ["SHIFT-"] = IsShiftKeyDown() })
end

function ns.ControllerStyle()
	local state = C_GamePad.GetDeviceMappedState()
	return state and state.labelStyle == "Shapes" and "playstation" or "xbox"
end

-- The pad keys whose emulated modifier is held right now.
function ns.HeldModifierKeys()
	local down = { ["SHIFT-"] = IsShiftKeyDown(), ["CTRL-"] = IsControlKeyDown(), ["ALT-"] = IsAltKeyDown() }
	local held = {}
	for _, entry in ipairs(emulatedModifiers()) do
		if down[entry.modifier] then held[entry.key] = true end
	end
	return held
end

-- The Blizzard bar button a binding command presses.
function ns.ButtonForCommand(command)
	for _, name in ipairs(ActionButtonUtil.ActionBarButtonNames) do
		for i = 1, NUM_ACTIONBAR_BUTTONS do
			local button = _G[name .. i]
			if button and button.bindingAction == command then return button end
		end
	end
end

-- The action slot that button shows, read from the button itself so paging is respected.
function ns.SlotForCommand(command)
	local button = ns.ButtonForCommand(command)
	return button and button.action
end

function ns.ActionInfo(binding)
	local action = GetBindingAction(binding)
	if action == "" then return end
	local slot = ns.SlotForCommand(action)
	return GetBindingName(action), slot and C_ActionBar.GetActionTexture(slot)
end

function ns.Assign(binding, action)
	ns.OutOfCombat(function()
		SetBinding(binding, action)
		SaveBindings(GetCurrentBindingSet())
	end)
end

-- Drops what is on the cursor into the Blizzard bar slot this button fires, so the action stays in WoW's slots.
function ns.PlaceOnButton(binding)
	if InCombatLockdown() then return print("LeanPad: action bars can't change in combat.") end
	local slot = ns.SlotForCommand(GetBindingAction(binding))
	if not slot then return print("LeanPad: bind this button to an action bar slot first, then drop actions on it.") end
	PlaceAction(slot)
end

local function commandLabel(action)
	local slot = ns.SlotForCommand(action)
	local icon = slot and C_ActionBar.GetActionTexture(slot)
	return (icon and ("|T%s:16|t "):format(icon) or "") .. GetBindingName(action)
end

-- Every Blizzard binding command, grouped by the categories of Blizzard's own key binding list.
function ns.BuildAssignMenu(root, binding)
	root:CreateTitle(GetBindingText(binding))
	if GetBindingAction(binding) ~= "" then
		root:CreateButton(UNBIND, function() ns.Assign(binding, nil) end)
	end
	local categories, order = {}, {}
	for i = 1, GetNumBindings() do
		local action, category = GetBinding(i)
		if not action:find("^HEADER") and not action:find("^PREFACE") then
			category = category or "BINDING_HEADER_OTHER"
			if not categories[category] then
				categories[category] = {}
				table.insert(order, category)
			end
			table.insert(categories[category], action)
		end
	end
	for _, category in ipairs(order) do
		local submenu = root:CreateButton(_G[category] or category)
		submenu:SetScrollMode(400)
		for _, action in ipairs(categories[category]) do
			submenu:CreateButton(commandLabel(action), function() ns.Assign(binding, action) end)
		end
	end
end

-- Button positions on a 360x240 controller drawing, and the order of each side's list, top to bottom.
local PADDLES = { PADPADDLE1 = { 120, 222 }, PADPADDLE2 = { 160, 222 }, PADPADDLE3 = { 200, 222 }, PADPADDLE4 = { 240, 222 } }
local SHOULDERS = { PADLTRIGGER = { 95, 14 }, PADLSHOULDER = { 80, 44 }, PADRSHOULDER = { 280, 44 }, PADRTRIGGER = { 265, 14 } }
local FACE = { PAD4 = { 275, 72 }, PAD3 = { 252, 95 }, PAD2 = { 298, 95 }, PAD1 = { 275, 118 } }

local function layout(own, left, right)
	local positions = {}
	for _, group in ipairs({ PADDLES, SHOULDERS, FACE, own }) do
		for key, point in pairs(group) do positions[key] = point end
	end
	return { positions = positions, left = left, right = right }
end

ns.LAYOUTS = {
	-- Left stick high and D-pad low, as on Xbox and most PC pads.
	xbox = layout({
		PADLSTICK = { 90, 95 }, PADBACK = { 152, 92 }, PADFORWARD = { 208, 92 }, PADRSTICK = { 225, 155 },
		PADDUP = { 135, 135 }, PADDLEFT = { 115, 155 }, PADDRIGHT = { 155, 155 }, PADDDOWN = { 135, 175 },
	},
	{ "PADLTRIGGER", "PADLSHOULDER", "PADLSTICK", "PADDUP", "PADDLEFT", "PADDRIGHT", "PADDDOWN", "PADBACK", "PADPADDLE1", "PADPADDLE2" },
	{ "PADRTRIGGER", "PADRSHOULDER", "PAD4", "PAD3", "PAD2", "PAD1", "PADRSTICK", "PADFORWARD", "PADPADDLE3", "PADPADDLE4" }),
	-- D-pad high and both sticks low, as on DualSense.
	playstation = layout({
		PADDUP = { 85, 75 }, PADDLEFT = { 63, 95 }, PADDRIGHT = { 107, 95 }, PADDDOWN = { 85, 115 },
		PADBACK = { 125, 58 }, PADFORWARD = { 235, 58 }, PADLSTICK = { 140, 160 }, PADRSTICK = { 220, 160 },
	},
	{ "PADLTRIGGER", "PADLSHOULDER", "PADDUP", "PADDLEFT", "PADDRIGHT", "PADDDOWN", "PADBACK", "PADLSTICK", "PADPADDLE1", "PADPADDLE2" },
	{ "PADRTRIGGER", "PADRSHOULDER", "PAD4", "PAD3", "PAD2", "PAD1", "PADFORWARD", "PADRSTICK", "PADPADDLE3", "PADPADDLE4" }),
}

local OUTLINE = {
	{ 60, 40 }, { 120, 30 }, { 240, 30 }, { 300, 40 }, { 335, 90 }, { 350, 170 }, { 335, 212 }, { 300, 218 },
	{ 262, 182 }, { 98, 182 }, { 60, 218 }, { 25, 212 }, { 10, 170 }, { 25, 90 }, { 60, 40 },
}

local SHOWN_EVENTS = { "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED", "PLAYER_REGEN_DISABLED" }
local ROW_HEIGHT, ROW_WIDTH, MAX_TABS = 34, 290, 8

local frame, diagram, status, layers, tabIndex
local glyphs, rows, tabs = {}, {}, {}

local function currentPrefix() return layers[tabIndex].prefix end

local function openMenu(owner, key)
	MenuUtil.CreateContextMenu(owner, function(_, root) ns.BuildAssignMenu(root, currentPrefix() .. key) end)
end

local function onButtonClick(self)
	if GetCursorInfo() then return ns.PlaceOnButton(currentPrefix() .. self.key) end
	openMenu(self, self.key)
end

local function onReceiveDrag(self) ns.PlaceOnButton(currentPrefix() .. self.key) end

local function makeButton(parent, width, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", onButtonClick)
	button:SetScript("OnReceiveDrag", onReceiveDrag)
	return button
end

local function makeRow(side, index)
	local row = makeButton(frame, ROW_WIDTH, ROW_HEIGHT)
	local x = side == "left" and 16 or -16
	row:SetPoint(side == "left" and "TOPLEFT" or "TOPRIGHT", frame, side == "left" and "TOPLEFT" or "TOPRIGHT", x, -40 - (index - 1) * ROW_HEIGHT)
	row.Glyph = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Glyph:SetPoint("LEFT", 4, 0)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(24, 24)
	row.Icon:SetPoint("LEFT", 36, 0)
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Name:SetPoint("LEFT", 66, 0)
	row.Name:SetPoint("RIGHT", -4, 0)
	row.Name:SetJustifyH("LEFT")
	return row
end

local function refresh()
	layers = ns.Layers()
	if not layers[tabIndex] then tabIndex = 1 end
	for i = 1, MAX_TABS do
		local layer = layers[i]
		tabs[i]:SetShown(layer ~= nil)
		if layer then
			tabs[i]:SetText(layer.label)
			PanelTemplates_TabResize(tabs[i], 0)
		end
	end
	PanelTemplates_SetNumTabs(frame, #layers)
	PanelTemplates_SetTab(frame, tabIndex)

	local style = ns.LAYOUTS[ns.ControllerStyle()]
	for key, glyph in pairs(glyphs) do
		local point = style.positions[key]
		glyph:ClearAllPoints()
		glyph:SetPoint("CENTER", diagram, "TOPLEFT", point[1], -point[2])
		glyph.Text:SetText(GetBindingText(key))
	end

	local modifierKeys = ns.ModifierKeys()
	for _, side in ipairs({ "left", "right" }) do
		for index, key in ipairs(style[side]) do
			local row = rows[side][index]
			row.key = key
			local name, icon = ns.ActionInfo(currentPrefix() .. key)
			row.Glyph:SetText(GetBindingText(key))
			row.Icon:SetTexture(icon)
			local text = name or ("|cff808080" .. NOT_BOUND .. "|r")
			row.Name:SetText(modifierKeys[key] and text .. " |cff808080(modifier)|r" or text)
		end
	end
end

local function selectTab(index)
	tabIndex = index
	refresh()
end

local function stopDetect()
	frame:EnableGamePadButton(false)
	frame:SetScript("OnGamePadButtonDown", nil)
	status:SetText("")
end

-- Detect: the next pad press (modifiers held) picks the layer and opens that button's menu.
local function onDetectedButton(_, key)
	if ns.ModifierKeys()[key] then return end -- the modifier itself; wait for the button pressed with it
	stopDetect()
	local prefix = ns.HeldPrefix()
	for index, layer in ipairs(layers) do
		if layer.prefix == prefix then selectTab(index) end
	end
	MenuUtil.CreateContextMenu(glyphs[key] or frame, function(_, root) ns.BuildAssignMenu(root, prefix .. key) end)
end

local function startDetect()
	status:SetText("Press a button on your controller...")
	frame:EnableGamePadButton(true)
	frame:SetScript("OnGamePadButtonDown", onDetectedButton)
end

local function onEvent(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		frame:Hide()
	else
		refresh()
	end
end

local function footerButton(text, width, onClick, anchor)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:SetPoint(unpack(anchor))
	return button
end

local function build()
	frame = CreateFrame("Frame", "LeanPadControllerFrame", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetTitle("LeanPad Controller")
	frame:SetSize(980, 440)
	frame:SetPoint("CENTER")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	table.insert(UISpecialFrames, frame:GetName())

	diagram = CreateFrame("Frame", nil, frame)
	diagram:SetSize(360, 240)
	diagram:SetPoint("TOP", 0, -60)
	for i = 2, #OUTLINE do
		local line = diagram:CreateLine(nil, "BACKGROUND")
		line:SetThickness(2)
		line:SetColorTexture(0.6, 0.6, 0.6, 0.8)
		line:SetStartPoint("TOPLEFT", diagram, OUTLINE[i - 1][1], -OUTLINE[i - 1][2])
		line:SetEndPoint("TOPLEFT", diagram, OUTLINE[i][1], -OUTLINE[i][2])
	end
	for key in pairs(ns.LAYOUTS.xbox.positions) do
		local glyph = makeButton(diagram, 30, 30)
		glyph.key = key
		glyph.Text = glyph:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		glyph.Text:SetPoint("CENTER")
		glyphs[key] = glyph
	end

	rows.left, rows.right = {}, {}
	for index = 1, #ns.LAYOUTS.xbox.left do
		rows.left[index] = makeRow("left", index)
		rows.right[index] = makeRow("right", index)
	end

	frame.Tabs = tabs
	for i = 1, MAX_TABS do
		local tab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
		tab:SetScript("OnClick", function() selectTab(i) end)
		tabs[i] = tab
	end
	tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)

	status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	status:SetPoint("BOTTOM", diagram, "BOTTOM", 0, -24)
	footerButton("Detect button", 140, startDetect, { "BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 6 })
	footerButton("Default layout", 140, function() StaticPopup_Show("LEANPAD_SETUP") end, { "BOTTOM", frame, "BOTTOM", 0, 6 })
	footerButton(KEY_BINDINGS, 140, function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end, { "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6 })

	-- Listen only while open, so the editor costs nothing when closed.
	frame:SetScript("OnShow", function()
		for _, event in ipairs(SHOWN_EVENTS) do frame:RegisterEvent(event) end
		refresh()
	end)
	frame:SetScript("OnHide", function()
		frame:UnregisterAllEvents()
		stopDetect()
	end)
	frame:SetScript("OnEvent", onEvent)
	frame:Hide()
	tabIndex = 1
end

function ns.ToggleController()
	if InCombatLockdown() then return print("LeanPad: the controller editor opens out of combat.") end
	if not frame then build() end
	frame:SetShown(not frame:IsShown())
end
