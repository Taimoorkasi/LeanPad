local addonName, ns = ...

-- Tabs list modifier layers left trigger first; binding keys spell them ALT-CTRL-SHIFT-, WoW's order.
local TAB_ORDER = { "SHIFT-", "CTRL-", "ALT-" }
local CANONICAL = { "ALT-", "CTRL-", "SHIFT-" }
local MODIFIER_CVARS = { ["SHIFT-"] = "GamePadEmulateShift", ["CTRL-"] = "GamePadEmulateCtrl", ["ALT-"] = "GamePadEmulateAlt" }
local MODIFIER_NAMES = { ["SHIFT-"] = "Shift", ["CTRL-"] = "Ctrl", ["ALT-"] = "Alt" }

-- Pad keys that can be a layer button, and keys that can be the cursor's clicks.
ns.MODIFIER_KEYS = { "none", "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4" }
ns.CLICK_KEYS = { "none", "PAD1", "PAD2", "PAD3", "PAD4", "PADLSTICK", "PADRSTICK", "PADLSHOULDER", "PADRSHOULDER", "PADRTRIGGER" }

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

-- The drawing and names the connected pad asks for; the Button labels setting can override it.
function ns.DetectedStyle()
	local state = C_GamePad.GetDeviceMappedState()
	return state and state.labelStyle == "Shapes" and "playstation" or "xbox"
end

function ns.ControllerStyle()
	local forced = ns.db and ns.db.padStyle
	if forced and forced ~= "auto" then return forced end
	return ns.DetectedStyle()
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

-- What a bar slot holds, by name, so the editor says Blink rather than Action Button 2.
local function slotName(slot)
	local kind, id = GetActionInfo(slot)
	if kind == "spell" then return C_Spell.GetSpellName(id) end
	if kind == "item" then return C_Item.GetItemNameByID(id) end
	if kind == "macro" then return C_ActionBar.GetActionText(slot) end
end

-- A binding's action as the player knows it, and its icon: the slot's spell, an empty slot, or the command itself.
function ns.ActionInfo(binding)
	local action = GetBindingAction(binding)
	if action == "" then return end
	local slot = ns.SlotForCommand(action)
	if not slot then return GetBindingName(action) end
	if not C_ActionBar.HasAction(slot) then return ns.MUTED_HEX .. "Empty slot|r" end
	return slotName(slot) or GetBindingName(action), C_ActionBar.GetActionTexture(slot)
end

function ns.Assign(binding, action)
	ns.OutOfCombat(function()
		SetBinding(binding, action)
		SaveBindings(GetCurrentBindingSet())
		ns.Saved()
	end)
end

function ns.WriteCVar(cvar, value)
	ns.OutOfCombat(function()
		SetCVar(cvar, value)
		ns.Saved()
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
-- drawing's own units: centre x, centre y, width, height, then the callout column (L or R) and row. Keep in
-- step with draw-pads.js.
local ART = "Interface\\AddOns\\" .. addonName .. "\\Art\\"
ns.PADS = {
	playstation = {
		texture = ART .. "PadPlayStation",
		viewBox = { 150, 420, 1748, 1200 },
		keys = {
			PADLTRIGGER = { 497, 496, 210, 36, "L", 1 }, PADRTRIGGER = { 1551, 496, 210, 36, "R", 1 },
			PADLSHOULDER = { 512, 524, 240, 30, "L", 2 }, PADRSHOULDER = { 1536, 524, 240, 30, "R", 2 },
			PADBACK = { 712, 650, 30, 62, "L", 3 }, PADFORWARD = { 1336, 650, 30, 62, "R", 3 },
			PADDUP = { 468, 752, 80, 104, "L", 4 }, PADDDOWN = { 468, 908, 80, 104, "L", 7 },
			PADDLEFT = { 390, 830, 104, 80, "L", 5 }, PADDRIGHT = { 546, 830, 104, 80, "L", 6 },
			PAD4 = { 1580, 708, 112, 112, "R", 4 }, PAD3 = { 1458, 830, 112, 112, "R", 6 }, PAD2 = { 1702, 830, 112, 112, "R", 5 }, PAD1 = { 1580, 952, 112, 112, "R", 7 },
			PADLSTICK = { 772, 1112, 224, 224, "L", 8 }, PADRSTICK = { 1276, 1112, 224, 224, "R", 8 }, PADSYSTEM = { 1024, 1108, 68, 68 },
		},
	},
	xbox = {
		texture = ART .. "PadXbox",
		viewBox = { 200, 470, 1648, 1150 },
		keys = {
			PADLTRIGGER = { 520, 560, 200, 34, "L", 1 }, PADRTRIGGER = { 1528, 560, 200, 34, "R", 1 },
			PADLSHOULDER = { 535, 588, 230, 30, "L", 2 }, PADRSHOULDER = { 1513, 588, 230, 30, "R", 2 },
			PADBACK = { 900, 830, 52, 52, "L", 4 }, PADFORWARD = { 1148, 830, 52, 52, "R", 6 }, PADSYSTEM = { 1024, 700, 104, 104 },
			PADDUP = { 830, 1025, 70, 78, "L", 5 }, PADDDOWN = { 830, 1155, 70, 78, "L", 8 },
			PADDLEFT = { 765, 1090, 78, 70, "L", 6 }, PADDRIGHT = { 895, 1090, 78, 70, "L", 7 },
			PAD4 = { 1410, 720, 100, 100, "R", 3 }, PAD3 = { 1300, 830, 100, 100, "R", 5 }, PAD2 = { 1520, 830, 100, 100, "R", 4 }, PAD1 = { 1410, 940, 100, 100, "R", 7 },
			PADLSTICK = { 640, 830, 224, 224, "L", 3 }, PADRSTICK = { 1218, 1090, 224, 224, "R", 8 },
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

-- The pad glyph atlas behind a key's binding text, or nil when the key has none.
function ns.GlyphAtlas(key)
	return GetBindingText(key):match("|A:([^:|]+)")
end

-- Text with the key's glyph before it, or after it when the glyph should sit nearest the drawing.
function ns.Glyphed(key, text, size, after)
	local atlas = ns.GlyphAtlas(key)
	if not atlas then return text end
	local glyph = ("|A:%s:%d:%d|a"):format(atlas, size, size)
	return after and (text .. " " .. glyph) or (glyph .. " " .. text)
end

-- Menu options for a list of pad keys: the glyph and printed name, or None.
function ns.KeyOptions(keys)
	local options = {}
	for _, key in ipairs(keys) do
		table.insert(options, { key, key == "none" and NONE or ns.Glyphed(key, ns.KeyName(key), 16) })
	end
	return options
end

-- The window: title bar, then a page. The editor page is the map, the strip and the footer; Options.lua adds the other.
local WIDTH, HEIGHT = 920, 664
local MARGIN, COL, ROW, ROW_TOP = 16, 200, 32, 186
local ART_HEIGHT, ART_CX, ART_CY = 300, WIDTH / 2, 298
local TITLE_HEIGHT, TOOLBAR_Y, DIVIDER_Y, STRIP_Y, FOOTER_Y = 36, 107, 480, 496, 616
local SEGMENTS = 6 -- straight pieces per leader curve
local MAX_TABS = 8
local MENU_KEY = "PADFORWARD" -- closes the editor, as it opens and closes Blizzard's own panels
local POWER = { "battery critical", "battery low", "battery medium", "battery high", "wired" } -- Enum.GamePadPowerLevel + 1
local SHOWN_EVENTS = {
	"UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED",
	"GAME_PAD_DISCONNECTED", "GAME_PAD_POWER_CHANGED", "MODIFIER_STATE_CHANGED", "PLAYER_REGEN_DISABLED",
}
local C = ns.COLORS
local NOT_BOUND = ns.MUTED_HEX .. "Not bound|r"

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

-- A button's other job, so the player doesn't rebind their way out of the cursor or a layer.
local function note(key, action)
	local modifier = ns.ModifierKeys()[key]
	if modifier then
		local text = "Works as " .. MODIFIER_NAMES[modifier] .. " while held, opening its layer."
		if action ~= "" then
			text = text .. (" A tap under %s ms still does the action above."):format(GetCVar("GamePadEmulateTapWindowMs") or 350)
		end
		return text
	end
	if action == "LEANPAD_TOGGLE_CURSOR" then return "Keeps the gamepad cursor reachable." end
	if GetCVar("GamePadCursorLeftClick") == key then return "Also the cursor's left-click." end
	if GetCVar("GamePadCursorRightClick") == key then return "Also the cursor's right-click." end
	return ""
end

local frame, editor, art, ring, strip, prompt, toolbar, status, layers, tabIndex, selected
local hits, tabs, callouts = {}, {}, {}

local function currentPrefix() return layers[tabIndex].prefix end

local function layerIndexFor(prefix)
	for index, layer in ipairs(layers) do
		if layer.prefix == prefix then return index end
	end
end

local function deviceLine()
	local state = C_GamePad.GetDeviceMappedState()
	if not state then return "No controller detected" end
	local level = POWER[C_GamePad.GetPowerLevel() + 1]
	return state.name .. (level and (" · " .. level) or "")
end

local function promptText()
	local keys = {}
	for key in pairs(ns.ModifierKeys()) do table.insert(keys, ns.KeyName(key)) end
	table.sort(keys)
	local hold = #keys > 0 and ("Hold %s first to see that layer. "):format(table.concat(keys, " or ")) or ""
	return hold .. ns.KeyName(MENU_KEY) .. " closes this window. Using the cursor? Click a button on the picture."
end

-- What a key's callout says on the current layer: its action, or that it opens a layer; nil leaves it blank.
local function calloutName(key)
	local name = ns.ActionInfo(currentPrefix() .. key)
	if name then return name end
	if ns.ModifierKeys()[key] then return "Opens the " .. ns.KeyName(key) .. " layer" end
end

-- The label at its row, and a leader that leaves it flat then bends into the button along the line between them.
local function placeCallout(key, spot, pad)
	local callout = callouts[key]
	local side, row = spot[5], spot[6]
	local name = side and calloutName(key)
	callout.text:SetShown(name ~= nil)
	for _, line in ipairs(callout.lines) do line:SetShown(name ~= nil) end
	if not name then return end
	local picked = key == selected
	local y = ROW_TOP + ROW * (row - 1)
	local lx
	callout.text:SetFontObject(ns.Font(13, picked and C.accent or C.text))
	callout.text:ClearAllPoints()
	if side == "L" then
		callout.text:SetText(ns.Glyphed(key, name, 18, true))
		callout.text:SetJustifyH("RIGHT")
		callout.text:SetPoint("RIGHT", editor, "TOPLEFT", MARGIN + COL, -y)
		lx = MARGIN + COL + 6
	else
		callout.text:SetText(ns.Glyphed(key, name, 18))
		callout.text:SetJustifyH("LEFT")
		callout.text:SetPoint("LEFT", editor, "TOPLEFT", WIDTH - MARGIN - COL, -y)
		lx = WIDTH - MARGIN - COL - 6
	end
	local kx, ky, kw, kh = ns.KeyGeometry(pad, key)
	local ex, ey = ART_CX + kx, ART_CY - ky
	local dx, dy = ex - lx, ey - y
	local len = math.sqrt(dx * dx + dy * dy)
	local r = math.max(kw, kh) / 2 + 6
	ex, ey = ex - dx / len * r, ey - dy / len * r
	dx, dy = ex - lx, ey - y
	local c1x, c2x, c2y = lx + dx * 0.5, ex - dx * 0.3, ey - dy * 0.3
	local color = picked and C.accent or C.leader
	local px, py = lx, y
	for i, line in ipairs(callout.lines) do
		local t = i / SEGMENTS
		local u = 1 - t
		local nx = u * u * u * lx + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * ex
		local ny = u * u * u * y + 3 * u * u * t * y + 3 * u * t * t * c2y + t * t * t * ey
		line:SetStartPoint("TOPLEFT", editor, px, -py)
		line:SetEndPoint("TOPLEFT", editor, nx, -ny)
		line:SetColorTexture(color[1], color[2], color[3], 1)
		line:SetThickness(picked and 2 or 1.5)
		px, py = nx, ny
	end
end

local function fillStrip()
	local key = selected
	local binding = currentPrefix() .. key
	local action = GetBindingAction(binding)
	ns.SetGlyph(strip, key)
	strip.Key:SetText(ns.KeyName(key))
	strip.Layer:SetText(layers[tabIndex].label .. " layer")
	local name, icon = ns.ActionInfo(binding)
	strip.Icon:SetTexture(icon)
	strip.Icon:SetShown(icon ~= nil)
	strip.Name:SetText(name or NOT_BOUND)
	strip.Place:SetText(name and ns.ActionPlace(action) or "Pick an action, or drop a spell here.")
	strip.Note:SetText(note(key, action))
	strip.Clear:SetEnabled(action ~= "")
	local others = {}
	for index, layer in ipairs(layers) do
		if index ~= tabIndex then
			table.insert(others, layer.label .. " " .. (ns.ActionInfo(layer.prefix .. key) or NOT_BOUND))
		end
	end
	strip.Others:SetText(#others > 0 and (ns.MUTED_HEX .. "Other layers|r   " .. table.concat(others, "   ")) or "")
end

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
	strip:SetShown(selected ~= nil)
	prompt:SetShown(selected == nil)
	ring:SetShown(x ~= nil)
	if selected then fillStrip() end
	if x then
		ring:SetTexture(ART .. (w == h and "Ring" or "RingSquare"))
		ring:SetSize(w + 12, h + 12)
		ring:SetPoint("CENTER", editor, "TOPLEFT", ART_CX + x, -(ART_CY - y))
	end
	for key, hit in pairs(hits) do
		local hx, hy, hw, hh = ns.KeyGeometry(pad, key)
		hit:SetShown(hx ~= nil)
		if hx then
			hit:SetSize(math.max(hw, 20) + 12, math.max(hh, 20) + 12)
			hit:SetPoint("CENTER", editor, "TOPLEFT", ART_CX + hx, -(ART_CY - hy))
			hit:SetHighlightTexture(ART .. (hw == hh and "Ring" or "RingSquare"))
			hit:GetHighlightTexture():SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
			placeCallout(key, pad.keys[key], pad)
		end
	end
end

local function refresh()
	layers = ns.Layers()
	if not layers[tabIndex] then tabIndex = 1 end
	local x = 12
	for i = 1, MAX_TABS do
		local layer, tab = layers[i], tabs[i]
		tab:SetShown(layer ~= nil)
		if layer then
			local on = i == tabIndex
			tab:SetNormalFontObject(ns.Font(13, on and C.text or C.text2))
			tab:SetText(layer.label)
			tab:SetWidth(tab:GetTextWidth() + 28)
			tab:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -TITLE_HEIGHT)
			tab.Underline:SetShown(on)
			x = x + tab:GetTextWidth() + 28
		end
	end
	local modifiers = {}
	for _, entry in ipairs(emulatedModifiers()) do
		table.insert(modifiers, ns.Glyphed(entry.key, MODIFIER_NAMES[entry.modifier], 18))
	end
	toolbar.Modifiers:SetText(#modifiers > 0 and table.concat(modifiers, "   ") or "none")
	toolbar.Device:SetText(deviceLine())
	prompt.Text:SetText(promptText())
	status:SetText(GetCurrentBindingSet() == Enum.BindingSet.Character
		and "Changes save to this character's key bindings" or "Changes save to your account's key bindings")
	place()
	if ns.RefreshOptions then ns.RefreshOptions() end
end
ns.RefreshController = refresh

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
	if not editor:IsShown() then return end -- the settings page takes no picks
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

-- The Change... menu beside the tabs: which pad button acts as Shift, Ctrl and Alt.
local function layerMenu(_, root)
	for _, modifier in ipairs(TAB_ORDER) do
		local submenu = root:CreateButton(MODIFIER_NAMES[modifier] .. " button")
		ns.Radios(submenu, ns.KeyOptions(ns.MODIFIER_KEYS), function() return GetCVar(MODIFIER_CVARS[modifier]) or "none" end,
			function(key) ns.WriteCVar(MODIFIER_CVARS[modifier], key) end)
	end
end

local function makeTab(index)
	local tab = CreateFrame("Button", nil, editor)
	tab:SetHeight(40)
	tab:SetHighlightFontObject(ns.Font(13, C.text))
	tab.Underline = tab:CreateTexture(nil, "ARTWORK")
	tab.Underline:SetColorTexture(unpack(C.accent))
	tab.Underline:SetHeight(2)
	tab.Underline:SetPoint("BOTTOMLEFT")
	tab.Underline:SetPoint("BOTTOMRIGHT")
	tab:SetScript("OnClick", function() selectTab(index) end)
	return tab
end

local function buildStrip()
	strip = CreateFrame("Frame", nil, editor)
	strip:SetPoint("TOPLEFT", MARGIN, -STRIP_Y)
	strip:SetSize(WIDTH - 2 * MARGIN, FOOTER_Y - STRIP_Y)
	-- A spell dropped anywhere on the strip goes into the bar slot this button fires.
	strip:EnableMouse(true)
	strip:SetScript("OnReceiveDrag", placeHere)
	strip:SetScript("OnMouseUp", function() if GetCursorInfo() then placeHere() end end)

	strip.Glyph = strip:CreateTexture(nil, "ARTWORK")
	strip.Glyph:SetSize(30, 30)
	strip.Glyph:SetPoint("TOPLEFT")
	strip.Key = ns.Text(strip, 18, C.text)
	strip.Key:SetPoint("LEFT", strip.Glyph, "RIGHT", 10, 0)
	strip.Layer = ns.Text(strip, 12, C.accent)
	strip.Layer:SetPoint("TOPLEFT", 40, -36)

	strip.Icon = strip:CreateTexture(nil, "ARTWORK")
	strip.Icon:SetSize(40, 40)
	strip.Icon:SetPoint("TOPLEFT", COL + 24, 0)
	strip.Name = ns.Text(strip, 15, C.text)
	strip.Name:SetPoint("TOPLEFT", COL + 76, -4)
	strip.Place = ns.Text(strip, 12, C.muted)
	strip.Place:SetPoint("TOPLEFT", strip.Name, "BOTTOMLEFT", 0, -3)
	strip.Others = ns.Text(strip, 12, C.text)
	strip.Others:SetPoint("TOPLEFT", COL + 24, -52)
	strip.Others:SetWidth(440)
	strip.Note = ns.Text(strip, 12, C.muted)
	strip.Note:SetPoint("TOPLEFT", strip.Others, "BOTTOMLEFT", 0, -6)
	strip.Note:SetWidth(440)

	local change = ns.Button(strip, "Change action...", COL, function(self)
		MenuUtil.CreateContextMenu(self, function(_, root) ns.BuildAssignMenu(root, currentPrefix() .. selected) end)
	end, true)
	change:SetPoint("TOPRIGHT")
	strip.Clear = ns.Button(strip, "Clear", COL, function() ns.Assign(currentPrefix() .. selected, nil) end)
	strip.Clear:SetPoint("TOP", change, "BOTTOM", 0, -8)
	local hint = ns.Text(strip, 12, C.muted, "CENTER")
	hint:SetPoint("TOP", strip.Clear, "BOTTOM", 0, -8)
	hint:SetText("or drag a spell from your spellbook here")
end

local function buildEditor()
	editor = CreateFrame("Frame", nil, frame)
	editor:SetAllPoints()
	for i = 1, MAX_TABS do tabs[i] = makeTab(i) end
	editor.Tabs, editor.Hits, editor.Callouts = tabs, hits, callouts

	toolbar = {}
	editor.Toolbar = toolbar
	toolbar.Device = ns.Text(editor, 13, C.muted)
	toolbar.Device:SetPoint("LEFT", editor, "TOPLEFT", MARGIN, -TOOLBAR_Y)
	local change = ns.Button(editor, "Change...", 84, function(self) MenuUtil.CreateContextMenu(self, layerMenu) end)
	change:SetHeight(28)
	change:SetPoint("RIGHT", editor, "TOPRIGHT", -MARGIN, -TOOLBAR_Y)
	toolbar.Modifiers = ns.Text(editor, 13, C.text)
	toolbar.Modifiers:SetPoint("RIGHT", change, "LEFT", -10, 0)
	local label = ns.Text(editor, 13, C.text2)
	label:SetPoint("RIGHT", toolbar.Modifiers, "LEFT", -10, 0)
	label:SetText("Layer buttons")

	art = editor:CreateTexture(nil, "ARTWORK")
	art:SetPoint("CENTER", editor, "TOPLEFT", ART_CX, -ART_CY)
	ring = editor:CreateTexture(nil, "OVERLAY")
	ring:SetVertexColor(unpack(C.accent))
	editor.Art, editor.Ring = art, ring
	-- Cursor users click the drawing; a spell dropped on a button goes into its bar slot.
	for key in pairs(ns.PADS.playstation.keys) do
		local hit = CreateFrame("Button", nil, editor)
		hit.key = key
		hit:SetScript("OnClick", function(self) pick(self.key) end)
		hit:SetScript("OnReceiveDrag", function(self)
			pick(self.key)
			placeHere()
		end)
		hits[key] = hit
		local callout = { text = ns.Text(editor, 13, C.text), lines = {} }
		for i = 1, SEGMENTS do
			callout.lines[i] = editor:CreateLine(nil, "ARTWORK")
		end
		callouts[key] = callout
	end
	local divider = ns.Rule(editor)
	divider:SetPoint("TOPLEFT", MARGIN, -DIVIDER_Y)
	divider:SetPoint("TOPRIGHT", -MARGIN, -DIVIDER_Y)
	buildStrip()
	editor.Strip = strip

	prompt = CreateFrame("Frame", nil, editor)
	editor.Prompt = prompt
	prompt:SetPoint("TOPLEFT", MARGIN, -DIVIDER_Y)
	prompt:SetSize(WIDTH - 2 * MARGIN, FOOTER_Y - DIVIDER_Y)
	prompt.Title = ns.Text(prompt, 20, C.text, "CENTER")
	prompt.Title:SetPoint("CENTER", 0, 14)
	prompt.Title:SetText("Press any button on your controller")
	prompt.Text = ns.Text(prompt, 13, C.text2, "CENTER")
	prompt.Text:SetPoint("TOP", prompt.Title, "BOTTOM", 0, -8)

	local footer = ns.Rule(editor)
	footer:SetPoint("TOPLEFT", 0, -FOOTER_Y)
	footer:SetPoint("TOPRIGHT", 0, -FOOTER_Y)
	local reset = ns.Button(editor, "Reset to default layout...", 190, function() StaticPopup_Show("LEANPAD_SETUP") end)
	reset:SetPoint("TOPLEFT", MARGIN, -(FOOTER_Y + 8))
	status = ns.Text(editor, 12, C.muted, "CENTER")
	editor.Status = status
	status:SetPoint("TOP", editor, "TOP", 0, -(FOOTER_Y + 17))
	editor.Saved = ns.Text(editor, 12, C.accent, "CENTER")
	editor.Saved:SetPoint("TOP", editor, "TOP", 0, -(FOOTER_Y + 17))
	editor.Saved:Hide()
	local bindings = ns.Button(editor, KEY_BINDINGS, 120, function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end)
	bindings:SetPoint("TOPRIGHT", -MARGIN, -(FOOTER_Y + 8))
	local settings = ns.Button(editor, SETTINGS, 100, function() ns.ShowPage("options") end)
	settings:SetPoint("RIGHT", bindings, "LEFT", -8, 0)
end

local function build()
	frame = CreateFrame("Frame", "LeanPadControllerFrame", UIParent, "BackdropTemplate")
	ns.Backdrop(frame, C.bg, C.line)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	table.insert(UISpecialFrames, frame:GetName())
	ns.window = frame

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	title:SetPoint("LEFT", frame, "TOPLEFT", MARGIN, -TITLE_HEIGHT / 2)
	title:SetText("LeanPad Controller")
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -10, -8)
	close:SetNormalAtlas("common-icon-redx")
	close:SetHighlightAtlas("common-icon-redx", "ADD")
	close:SetScript("OnClick", function() frame:Hide() end)
	local content = ns.Panel(frame, C.panel)
	content:SetPoint("TOPLEFT", 0, -(TITLE_HEIGHT + 41))
	content:SetPoint("BOTTOMRIGHT", 0, HEIGHT - FOOTER_Y)
	local rule = ns.Rule(frame)
	rule:SetPoint("TOPLEFT", 0, -(TITLE_HEIGHT + 40))
	rule:SetPoint("TOPRIGHT", 0, -(TITLE_HEIGHT + 40))
	buildEditor()
	frame.Editor = editor

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
		ns.ShowPage("editor")
	end)
	frame:SetScript("OnEvent", onEvent)
	frame:Hide()
	tabIndex = 1
end

-- Two seconds of Saved in the open page's footer, once a binding, CVar or setting has really been written.
local SAVED_FOR = 2
local options
function ns.Saved()
	if not (frame and frame:IsShown()) then return end
	local page = editor:IsShown() and editor or options
	local idle, saved = page.Status, page.Saved
	saved:SetText("|A:common-icon-checkmark:12:12|a " .. (page == editor and idle:GetText():gsub("^Changes save", "Saved") or "Saved"))
	idle:Hide()
	saved:Show()
	C_Timer.After(SAVED_FOR, function()
		saved:Hide()
		idle:Show()
	end)
end

-- Pages share the title bar; Options.lua builds the other one on first use.
function ns.ShowPage(page)
	editor:SetShown(page == "editor")
	if page == "options" then options = ns.BuildOptions(frame) end
	if options then options:SetShown(page == "options") end
end

local function open(page)
	if InCombatLockdown() then return print("LeanPad: the controller editor opens out of combat.") end
	if not frame then build() end
	ns.ShowPage(page)
	frame:Show()
end

function ns.ToggleController()
	if frame and frame:IsShown() then return frame:Hide() end
	open("editor")
end

function ns.OpenOptions()
	open("options")
end
