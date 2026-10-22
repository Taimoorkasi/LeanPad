local addonName, ns = ...

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

-- Pad keys that emulate a modifier, each with its binding prefix, such as SHIFT-.
function ns.ModifierKeys()
	local keys = {}
	for _, entry in ipairs(emulatedModifiers()) do keys[entry.key] = entry.modifier end
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

-- The controller drawings in Art/, made by tools/draw-pads.js, and where each button sits on them in the
-- drawing's own units: centre x, centre y, width, height. Keep in step with draw-pads.js.
local ART = "Interface\\AddOns\\" .. addonName .. "\\Art\\"
ns.PADS = {
	playstation = {
		texture = ART .. "PadPlayStation",
		viewBox = { 150, 420, 1748, 1200 },
		keys = {
			PADLTRIGGER = { 497, 496, 210, 36 }, PADRTRIGGER = { 1551, 496, 210, 36 },
			PADLSHOULDER = { 512, 524, 240, 30 }, PADRSHOULDER = { 1536, 524, 240, 30 },
			PADBACK = { 712, 650, 30, 62 }, PADFORWARD = { 1336, 650, 30, 62 },
			PADDUP = { 468, 752, 80, 104 }, PADDDOWN = { 468, 908, 80, 104 },
			PADDLEFT = { 390, 830, 104, 80 }, PADDRIGHT = { 546, 830, 104, 80 },
			PAD4 = { 1580, 708, 112, 112 }, PAD3 = { 1458, 830, 112, 112 }, PAD2 = { 1702, 830, 112, 112 }, PAD1 = { 1580, 952, 112, 112 },
			PADLSTICK = { 772, 1112, 224, 224 }, PADRSTICK = { 1276, 1112, 224, 224 }, PADSYSTEM = { 1024, 1108, 68, 68 },
		},
	},
	xbox = {
		texture = ART .. "PadXbox",
		viewBox = { 200, 470, 1648, 1150 },
		keys = {
			PADLTRIGGER = { 520, 560, 200, 34 }, PADRTRIGGER = { 1528, 560, 200, 34 },
			PADLSHOULDER = { 535, 588, 230, 30 }, PADRSHOULDER = { 1513, 588, 230, 30 },
			PADBACK = { 900, 830, 52, 52 }, PADFORWARD = { 1148, 830, 52, 52 }, PADSYSTEM = { 1024, 700, 104, 104 },
			PADDUP = { 830, 1025, 70, 78 }, PADDDOWN = { 830, 1155, 70, 78 },
			PADDLEFT = { 765, 1090, 78, 70 }, PADDRIGHT = { 895, 1090, 78, 70 },
			PAD4 = { 1410, 720, 100, 100 }, PAD3 = { 1300, 830, 100, 100 }, PAD2 = { 1520, 830, 100, 100 }, PAD1 = { 1410, 940, 100, 100 },
			PADLSTICK = { 640, 830, 224, 224 }, PADRSTICK = { 1218, 1090, 224, 224 },
		},
	},
}

-- Blizzard's KEY_PAD* strings are glyph markup only, so buttons get their printed names here.
local KEY_NAMES = {
	playstation = {
		PAD1 = "Cross", PAD2 = "Circle", PAD3 = "Square", PAD4 = "Triangle", PADLSHOULDER = "L1", PADRSHOULDER = "R1",
		PADLTRIGGER = "L2", PADRTRIGGER = "R2", PADLSTICK = "L3", PADRSTICK = "R3", PADBACK = "Create", PADFORWARD = "Options", PADSYSTEM = "PS button",
	},
	xbox = {
		PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
		PADLTRIGGER = "LT", PADRTRIGGER = "RT", PADLSTICK = "Left stick click", PADRSTICK = "Right stick click", PADBACK = "View", PADFORWARD = "Menu", PADSYSTEM = "Guide button",
	},
}
local SHARED_NAMES = {
	PADDUP = "D-pad Up", PADDDOWN = "D-pad Down", PADDLEFT = "D-pad Left", PADDRIGHT = "D-pad Right",
	PADPADDLE1 = "Paddle 1", PADPADDLE2 = "Paddle 2", PADPADDLE3 = "Paddle 3", PADPADDLE4 = "Paddle 4",
}

function ns.KeyName(key)
	return KEY_NAMES[ns.ControllerStyle()][key] or SHARED_NAMES[key] or key
end

local ART_HEIGHT, ART_Y = 250, 30
local FRAME_WIDTH, FRAME_HEIGHT = 820, 540
local CARD_WIDTH, CARD_HEIGHT, GAP = 320, 300, 40
local MAX_TABS, MAX_OTHER_LAYERS = 8, 3
local MENU_KEY = "PADFORWARD" -- closes the editor, as it opens and closes Blizzard's own panels
local MODIFIER_NAMES = { ["SHIFT-"] = "Shift", ["CTRL-"] = "Ctrl", ["ALT-"] = "Alt" }
local SHOWN_EVENTS = {
	"UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED",
	"MODIFIER_STATE_CHANGED", "PLAYER_REGEN_DISABLED",
}

-- Where a key sits on the drawing, as an offset from the drawing's centre in UI units, and its size.
function ns.KeyGeometry(pad, key)
	local spot = pad.keys[key]
	if not spot then return end
	local vx, vy, vw, vh = unpack(pad.viewBox)
	local scale = ART_HEIGHT / vh
	return (spot[1] - vx - vw / 2) * scale, (vy + vh / 2 - spot[2]) * scale, spot[3] * scale, spot[4] * scale
end

-- Where a binding command's action lives, in the names of Blizzard's Action Bars settings.
function ns.ActionPlace(action)
	local bar, slot = action:match("^MULTIACTIONBAR(%d)BUTTON(%d+)$")
	if bar then return ("Action Bar %d, slot %s"):format(bar + 1, slot) end
	slot = action:match("^ACTIONBUTTON(%d+)$")
	if slot then return ("Action Bar 1, slot %s"):format(slot) end
	return "Key binding command"
end

-- A button's other job, so the player doesn't rebind their way out of the cursor.
local function reservedNote(key, action)
	if action == "LEANPAD_TOGGLE_CURSOR" then return "Keeps the gamepad cursor reachable." end
	if GetCVar("GamePadCursorLeftClick") == key then return "Also the cursor's left-click." end
	if GetCVar("GamePadCursorRightClick") == key then return "Also the cursor's right-click." end
end

local frame, art, ring, line, card, prompt, hint, status, layers, tabIndex, selected
local hits, tabs = {}, {}

local function currentPrefix() return layers[tabIndex].prefix end

local function layerIndexFor(prefix)
	for index, layer in ipairs(layers) do
		if layer.prefix == prefix then return index end
	end
end

local function fillCard()
	local key = selected
	local binding = currentPrefix() .. key
	local action = GetBindingAction(binding)
	ns.SetGlyph(card, key)
	card.Key:SetText(ns.KeyName(key))
	card.Layer:SetText(layers[tabIndex].label .. " layer")
	local name, icon = ns.ActionInfo(binding)
	card.Icon:SetTexture(icon)
	card.Icon:SetShown(icon ~= nil)
	card.Name:SetText(name or "|cff808080Not bound|r")
	card.Place:SetText(name and ns.ActionPlace(action) or "Pick an action, or drop a spell here.")
	local modifier = ns.ModifierKeys()[key]
	card.Note:SetText(modifier and ("Works as " .. MODIFIER_NAMES[modifier] .. " while held, opening its layer.") or reservedNote(key, action) or "")
	card.Clear:SetEnabled(action ~= "")

	local shown = 0
	for index, layer in ipairs(layers) do
		if index ~= tabIndex and shown < MAX_OTHER_LAYERS then -- shortcut: Alt layers past the first three are left out; list them if Alt gets used
			shown = shown + 1
			local row = card.rows[shown]
			local otherName, otherIcon = ns.ActionInfo(layer.prefix .. key)
			row.index = index
			row.Layer:SetText(layer.label)
			row.Icon:SetTexture(otherIcon)
			row.Name:SetText(otherName or "|cff808080Not bound|r")
			row:Show()
		end
	end
	for i = shown + 1, MAX_OTHER_LAYERS do card.rows[i]:Hide() end
end

-- Idle: the pad in the middle. A button picked: the card on that button's side, the pad beside it, one line between.
local function place()
	local pad = ns.PADS[ns.ControllerStyle()]
	local _, _, vw, vh = unpack(pad.viewBox)
	local width = ART_HEIGHT * vw / vh
	local crop = (1 - width / (2 * ART_HEIGHT)) / 2 -- the texture is 2:1 with the drawing centred at full height
	art:SetTexture(pad.texture)
	art:SetTexCoord(crop, 1 - crop, 0, 1)
	art:SetSize(width, ART_HEIGHT)

	local x, y, w, h
	if selected then x, y, w, h = ns.KeyGeometry(pad, selected) end
	local side = (x or 1) < 0 and -1 or 1
	local cardX = side * (FRAME_WIDTH / 2 - 20 - CARD_WIDTH / 2)
	local artX = selected and cardX - side * (CARD_WIDTH / 2 + GAP + width / 2) or 0
	art:SetPoint("CENTER", frame, "CENTER", artX, ART_Y)

	card:SetShown(selected ~= nil)
	prompt:SetShown(selected == nil)
	hint:SetShown(selected ~= nil)
	ring:SetShown(x ~= nil)
	line:SetShown(x ~= nil)
	if selected then
		local cardY = y and math.max(-60, math.min(60, ART_Y + y)) or 0
		card:SetPoint("CENTER", frame, "CENTER", cardX, cardY)
		hint:SetPoint("TOP", art, "BOTTOM", 0, -16)
		fillCard()
	end
	if x then
		ring:SetTexture(ART .. (w == h and "Ring" or "RingSquare"))
		ring:SetSize(w + 12, h + 12)
		ring:SetPoint("CENTER", frame, "CENTER", artX + x, ART_Y + y)
		line:SetStartPoint("CENTER", frame, cardX - side * CARD_WIDTH / 2, ART_Y + y)
		line:SetEndPoint("CENTER", frame, artX + x + side * (w / 2 + 6), ART_Y + y)
	end
	for key, hit in pairs(hits) do
		local hx, hy, hw, hh = ns.KeyGeometry(pad, key)
		hit:SetShown(hx ~= nil)
		if hx then
			hit:SetSize(math.max(hw, 20), math.max(hh, 20))
			hit:SetPoint("CENTER", frame, "CENTER", artX + hx, ART_Y + hy)
		end
	end
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
	status:SetText(GetCurrentBindingSet() == Enum.BindingSet.Character
		and "Changes save to this character's key bindings" or "Changes save to your account's key bindings")
	place()
end

local function selectTab(index)
	tabIndex = index
	refresh()
end

-- A press on the pad picks that button on the layer its held modifiers open.
local function pick(key)
	selected = key
	tabIndex = layerIndexFor(ns.HeldPrefix()) or tabIndex
	refresh()
end

local function onGamePadButtonDown(_, key)
	if key == MENU_KEY then return frame:Hide() end
	if ns.ModifierKeys()[key] then return end -- the modifier on its own only switches layer
	pick(key)
end

local function onEvent(_, event)
	if event == "PLAYER_REGEN_DISABLED" then return frame:Hide() end
	if event == "MODIFIER_STATE_CHANGED" then
		tabIndex = layerIndexFor(ns.HeldPrefix()) or tabIndex
	end
	refresh()
end

local function placeHere()
	if selected then ns.PlaceOnButton(currentPrefix() .. selected) end
end

local function makeText(parent, template, ...)
	local text = parent:CreateFontString(nil, "ARTWORK", template)
	text:SetPoint(...)
	text:SetJustifyH("LEFT")
	return text
end

local function makeButton(parent, text, width, onClick, ...)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:SetPoint(...)
	return button
end

local function buildCard()
	card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	card:SetBackdropColor(0.1, 0.086, 0.067, 0.95)
	card:SetBackdropBorderColor(0.48, 0.41, 0.31, 1)
	-- A spell dropped anywhere on the card goes into the bar slot this button fires.
	card:EnableMouse(true)
	card:SetScript("OnReceiveDrag", placeHere)
	card:SetScript("OnMouseUp", function() if GetCursorInfo() then placeHere() end end)

	card.Glyph = card:CreateTexture(nil, "ARTWORK")
	card.Glyph:SetSize(26, 26)
	card.Glyph:SetPoint("TOPLEFT", 16, -16)
	card.Key = makeText(card, "GameFontHighlightLarge", "LEFT", card.Glyph, "RIGHT", 8, 0)
	card.Layer = makeText(card, "GameFontNormalSmall", "TOPRIGHT", -16, -22)
	makeText(card, "GameFontDisableSmall", "TOPLEFT", 16, -58):SetText("Does now")
	card.Icon = card:CreateTexture(nil, "ARTWORK")
	card.Icon:SetSize(40, 40)
	card.Icon:SetPoint("TOPLEFT", 16, -76)
	card.Name = makeText(card, "GameFontNormalHuge", "TOPLEFT", 66, -78)
	card.Name:SetPoint("RIGHT", -16, 0)
	card.Place = makeText(card, "GameFontHighlightSmall", "TOPLEFT", card.Name, "BOTTOMLEFT", 0, -4)
	card.Note = makeText(card, "GameFontNormalSmall", "TOPLEFT", 16, -126)

	makeButton(card, "Change action...", 140, function(self)
		MenuUtil.CreateContextMenu(self, function(_, root) ns.BuildAssignMenu(root, currentPrefix() .. selected) end)
	end, "TOPLEFT", 16, -146)
	card.Clear = makeButton(card, "Clear", 80, function() ns.Assign(currentPrefix() .. selected, nil) end, "TOPLEFT", 164, -146)
	makeText(card, "GameFontHighlightSmall", "TOPLEFT", 16, -178):SetText("Or drag a spell from your spellbook onto this card.")

	makeText(card, "GameFontDisableSmall", "TOPLEFT", 16, -204):SetText("Same button on other layers")
	card.rows = {}
	for i = 1, MAX_OTHER_LAYERS do
		local row = CreateFrame("Button", nil, card)
		row:SetSize(CARD_WIDTH - 24, 24)
		row:SetPoint("TOPLEFT", 12, -218 - (i - 1) * 24)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:SetScript("OnClick", function(self) selectTab(self.index) end)
		row.Layer = makeText(row, "GameFontHighlightSmall", "LEFT", 4, 0)
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(18, 18)
		row.Icon:SetPoint("LEFT", 72, 0)
		row.Name = makeText(row, "GameFontNormal", "LEFT", 96, 0)
		card.rows[i] = row
	end
end

local function build()
	frame = CreateFrame("Frame", "LeanPadControllerFrame", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetTitle("LeanPad Controller")
	frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	table.insert(UISpecialFrames, frame:GetName())

	-- Layer tabs sit along the top, on the inset's edge, as in Blizzard's macro and appearance windows.
	frame.Tabs = tabs
	for i = 1, MAX_TABS do
		local tab = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate")
		tab:SetScript("OnClick", function() selectTab(i) end)
		tabs[i] = tab
	end
	tabs[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -28)

	art = frame:CreateTexture(nil, "ARTWORK")
	ring = frame:CreateTexture(nil, "OVERLAY")
	ring:SetVertexColor(1, 0.82, 0)
	line = frame:CreateLine(nil, "OVERLAY")
	line:SetThickness(2)
	line:SetColorTexture(1, 0.82, 0, 0.9)
	-- Cursor users click the drawing; a spell dropped on a button goes into its bar slot.
	for key in pairs(ns.PADS.playstation.keys) do
		local hit = CreateFrame("Button", nil, frame)
		hit.key = key
		hit:SetScript("OnClick", function(self) pick(self.key) end)
		hit:SetScript("OnReceiveDrag", function(self)
			pick(self.key)
			placeHere()
		end)
		hits[key] = hit
	end
	buildCard()

	prompt = CreateFrame("Frame", nil, frame)
	prompt:SetSize(FRAME_WIDTH - 40, 50)
	prompt:SetPoint("TOP", frame, "CENTER", 0, ART_Y - ART_HEIGHT / 2 - 20)
	prompt.Title = prompt:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	prompt.Title:SetPoint("TOP")
	prompt.Title:SetText("Press any button on your controller")
	prompt.Text = prompt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	prompt.Text:SetPoint("TOP", prompt.Title, "BOTTOM", 0, -6)
	prompt.Text:SetText("Hold a trigger first to see that layer. Using the cursor? Click a button on the picture.")
	hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetText("Press another button to look at it. Hold a trigger to switch layer. Menu closes this window.")

	makeButton(frame, "Reset to default layout...", 190, function() StaticPopup_Show("LEANPAD_SETUP") end, "BOTTOMLEFT", 12, 6)
	makeButton(frame, KEY_BINDINGS, 150, function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end, "BOTTOMRIGHT", -12, 6)
	status = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	status:SetPoint("BOTTOM", 0, 12)

	-- Listen only while open, so the editor costs nothing when closed. While open, pad presses pick buttons
	-- instead of firing their actions.
	frame:SetScript("OnShow", function()
		for _, event in ipairs(SHOWN_EVENTS) do frame:RegisterEvent(event) end
		frame:EnableGamePadButton(true)
		frame:SetScript("OnGamePadButtonDown", onGamePadButtonDown)
		refresh()
	end)
	frame:SetScript("OnHide", function()
		frame:UnregisterAllEvents()
		frame:EnableGamePadButton(false)
		frame:SetScript("OnGamePadButtonDown", nil)
		selected = nil
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
