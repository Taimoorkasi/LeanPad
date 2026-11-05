local _, ns = ...

-- WoW: Forever with its Gamepad UI on. Blizzard's own gamepad bars hold the actions and its modifiers open the layers,
-- so LeanPad's layers map onto those bars: Base is the top bar, LT the left, RT the right, LT+RT the bottom. Everything
-- here replaces a function only while the Gamepad UI is on; with it off, Forever runs LeanPad as retail does.
-- A client that ignores the TOC's game type condition has none of this.
if not C_GamepadUI then return end

local CONTEXT = Enum.BindingContext.GamepadModeInGameCore
local LEFT, RIGHT, BOTH = "LEFT-", "RIGHT-", "BOTH-"
local BARS = { [""] = "topBar", [LEFT] = "leftBar", [RIGHT] = "rightBar", [BOTH] = "bottomBar" }
-- The top bar's right half is Blizzard's own, with no action slots: buttons 5-8 of a bar are X, Y, B and A by default.
local RESERVED = { [5] = "INTERACTTARGET", [6] = "LEANPAD_INSPECT", [7] = "LEANPAD_BACK", [8] = "JUMP" }
local RESERVED_COMMANDS = { INTERACTTARGET = true, LEANPAD_INSPECT = true, LEANPAD_BACK = true, JUMP = true }
local LAYER_BUTTONS = { { "GAMEPADLEFTMOD", "Left layer" }, { "GAMEPADRIGHTMOD", "Right layer" } }
local CONTEXT_ACTIONS = {
	"GAMEPADACTIONBUTTON1", "GAMEPADACTIONBUTTON2", "GAMEPADACTIONBUTTON3", "GAMEPADACTIONBUTTON4",
	"GAMEPADACTIONBUTTON5", "GAMEPADACTIONBUTTON6", "GAMEPADACTIONBUTTON7", "GAMEPADACTIONBUTTON8",
	"OPENRADIAL", "TOGGLEUIFOCUS", "TOGGLEPINGSYSTEM", "GAMEPADLEFTMOD", "GAMEPADRIGHTMOD",
	"GAMEPADLEFTTARGETMODIFIER", "GAMEPADRIGHTTARGETMODIFIER",
}
local PAGES, SLOTS_PER_PAGE = 3, 32
-- LeanPad's crossbar shows these instead; the targeting bars stay Blizzard's.
local MIRRORED_BARS = { "topBar", "leftBar", "rightBar", "bottomBar", "possessBar", "stanceBar" }
local CONTEXT_PREFIX = "CONTEXT:" -- marks a context binding among the plain ones a profile saves

ns.HIDDEN_NAMES.LEANPAD_INSPECT, ns.HIDDEN_NAMES.LEANPAD_BACK = "Inspect", "Back"
ns.COMMAND_ICONS.LEANPAD_INSPECT = { atlas = "gamepad-radial-icon-inspecthud-up" }
ns.COMMAND_ICONS.LEANPAD_BACK = { atlas = "common-icon-backarrow" }
ns.COMMAND_ICONS.JUMP = { atlas = "gamepad-ability-icon-jump" } -- Blizzard's own, which retail doesn't have

-- Forever players come for the controller, so the quest prompts start on here, for when the Gamepad UI is off.
ns.QUEST_PROMPTS_DEFAULT = true
-- New controller players need to see where spells can go, before they've placed any.
ns.CROSSBAR_EMPTY_DEFAULT = true
-- What Blizzard's Gamepad UI sets for its interact icons, for LeanPad's layout to set with it off.
ns.CVARS.SoftTargetIconGameObject, ns.CVARS.SoftTargetInteractRange = "1", "20"

local function active() return InputUtil.IsGamepadUIEnabled() end
local function pageUnit() return GamepadMainActionBarFrame.PageUnit end

-- Replaces ns[name] while the Gamepad UI is on; fn gets the original first.
local function wrap(name, fn)
	local base = ns[name]
	ns[name] = function(...)
		if active() then return fn(base, ...) end
		return base(...)
	end
end

local function split(binding)
	return binding:match("^(.-)(PAD[%u%d]+)$")
end

local function contextKeys(action)
	return { GetBindingKey(action, nil, CONTEXT) }
end

-- Which of a bar's eight buttons a pad key presses, read from the key's binding so a rebound pad stays right.
local function barIndex(key)
	return tonumber(GetBindingAction(key, nil, CONTEXT):match("^GAMEPADACTIONBUTTON(%d)$"))
end

-- The command LeanPad's code passes around for a bar button: it has no real binding, as the layer isn't in the key.
local function parseBarCommand(command)
	local bar, index = command:match("^GAMEPADBAR:(%a+):(%d)$")
	return bar, tonumber(index)
end

-- The bar on screen in a position: a stance or possess bar replaces the one it overrides.
local function barFor(name)
	local bars = pageUnit().actionBars
	for _, over in ipairs({ bars.possessBar, bars.stanceBar }) do
		if over:IsBarActivelyOverridingActionBar(bars[name]) then return over, true end
	end
	return bars[name], false
end

wrap("BindingAction", function(_, binding)
	local prefix, key = split(binding)
	local index = barIndex(key)
	if index then
		if prefix == "" and RESERVED[index] then return RESERVED[index] end
		return ("GAMEPADBAR:%s:%d"):format(BARS[prefix], index)
	end
	if prefix ~= "" then return "" end -- only a bar's D-pad and face buttons exist on a layer
	local action = GetBindingAction(key, nil, CONTEXT)
	return action ~= "" and action or GetBindingAction(key)
end)

wrap("ButtonForCommand", function(base, command)
	local name, index = parseBarCommand(command)
	if not name then return base(command) end
	return (barFor(name)):GetActionButtonByIndex(index)
end)

-- Pageable bars keep a slot per page, so the editor can show any page; an override bar has only the one it shows.
wrap("SlotForCommand", function(base, command)
	local name, index = parseBarCommand(command)
	if not name then return base(command) end
	local bar, overridden = barFor(name)
	local button = bar:GetActionButtonByIndex(index)
	if overridden then return button.action end
	return GamepadActionBarBindingUtil.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(ns.MainBarPage(), button:GetGamepadPageUnitSlotID()) or button.action
end)

wrap("ActionPlace", function(base, action)
	if parseBarCommand(action) then return ("Gamepad bar, page %d"):format(ns.MainBarPage()) end
	if RESERVED_COMMANDS[action] then return "Kept by Blizzard's Gamepad UI" end
	return base(action)
end)

wrap("LivePage", function() return pageUnit():GetCurrentPage() end)
wrap("PageName", function(_, page) return "Page " .. page end)
wrap("PageOptions", function()
	local options = {}
	for page = 1, PAGES do table.insert(options, { page, ns.PageName(page) }) end
	return options
end)

wrap("UsesGamepadUI", function() return true end)

wrap("BindingTitle", function(_, binding)
	local prefix, key = split(binding)
	for _, layer in ipairs(ns.Layers()) do
		if layer.prefix == prefix and prefix ~= "" then return layer.label .. " + " .. GetBindingText(key) end
	end
	return GetBindingText(key)
end)

-- A bar position takes spells and macros, into its slot; keys off the bars can also fire commands.
wrap("SlotOnly", function(_, binding)
	local prefix, key = split(binding)
	return prefix ~= "" or barIndex(key) ~= nil
end)

-- Layers: read from Blizzard's own modifier state. Forever also emulates Shift on LT and Ctrl on LB by default, and LB
-- is a targeting modifier there, so Shift and Ctrl can't say which layer is open.
local function layerLabel(action, fallback)
	local key = contextKeys(action)[1]
	return key and GetBindingText(key) or fallback
end

wrap("Layers", function()
	local left, right = layerLabel("GAMEPADLEFTMOD", "Left"), layerLabel("GAMEPADRIGHTMOD", "Right")
	return {
		{ prefix = "", label = "Base" }, { prefix = LEFT, label = left },
		{ prefix = RIGHT, label = right }, { prefix = BOTH, label = left .. " + " .. right },
	}
end)

wrap("ModifierKeys", function()
	local keys = {}
	for _, key in ipairs(contextKeys("GAMEPADLEFTMOD")) do keys[key] = LEFT end
	for _, key in ipairs(contextKeys("GAMEPADRIGHTMOD")) do keys[key] = RIGHT end
	return keys
end)

wrap("HeldPrefix", function()
	local left, right = GamepadMode.IsLeftModifierDown(), GamepadMode.IsRightModifierDown()
	if left and right then return BOTH end
	return left and LEFT or right and RIGHT or ""
end)

wrap("LayerKeyNames", function()
	local names = {}
	for _, button in ipairs(LAYER_BUTTONS) do
		local key = contextKeys(button[1])[1]
		if key then table.insert(names, { key, button[2] }) end
	end
	return names
end)

wrap("LayerButtons", function() return LAYER_BUTTONS end)
wrap("LayerButtonKey", function(_, id) return contextKeys(id)[1] or "none" end)

-- What a key did before LeanPad first changed it, so Reset can put back only what LeanPad touched.
local function remember(key)
	ns.db.contextDefaults = ns.db.contextDefaults or {}
	if not ns.db.contextDefaults[key] then ns.db.contextDefaults[key] = GetBindingAction(key, nil, CONTEXT) end
end

wrap("SetLayerButton", function(_, action, key)
	ns.OutOfCombat(function()
		for _, old in ipairs(contextKeys(action)) do
			remember(old)
			SetBinding(old, nil, CONTEXT)
		end
		if key ~= "none" then
			remember(key)
			SetBinding(key, action, CONTEXT)
		end
		SaveBindings(GetCurrentBindingSet())
		ns.Saved()
	end)
end)

wrap("LayerMenu", function(_, _, root)
	for _, button in ipairs(LAYER_BUTTONS) do
		ns.Radios(root:CreateButton(button[2]), ns.KeyOptions(ns.MODIFIER_KEYS), function() return ns.LayerButtonKey(button[1]) end,
			function(key) ns.SetLayerButton(button[1], key) end)
	end
end)

-- A bar position's action lives in its slot, so there is no binding to write: only clearing means anything. Other
-- keys leave Blizzard's context, where a binding would outrank a plain one, and take the plain binding.
wrap("Assign", function(_, binding, action)
	ns.OutOfCombat(function()
		local prefix, key = split(binding)
		if not ns.SlotOnly(binding) then
			remember(key)
			SetBinding(key, nil, CONTEXT)
			SetBinding(key, action)
			SaveBindings(GetCurrentBindingSet())
			return ns.Saved()
		end
		local slot = ns.SlotForCommand(ns.BindingAction(binding))
		if not slot and prefix == "" and barIndex(key) then return print("LeanPad: Blizzard's Gamepad UI keeps this button for its own action.") end
		if not slot then return print("LeanPad: on a layer, only the D-pad and face buttons hold actions.") end
		if C_ActionBar.HasAction(slot) then
			PickupAction(slot)
			ClearCursor()
		end
		ns.Saved()
	end)
end)

wrap("EnsureSlot", function(_, binding)
	local slot = ns.SlotForCommand(ns.BindingAction(binding))
	if slot then return slot end
	print("LeanPad: this button holds no spell in Blizzard's Gamepad UI; use the D-pad or a face button on a layer.")
end)

-- The Gamepad UI's defaults already work, so there is nothing to set up; a reset undoes only LeanPad's own changes.
wrap("ShowSetup", function() end)
wrap("ShowReset", function() StaticPopup_Show("LEANPAD_RESET_GAMEPAD") end)
wrap("Apply", function()
	for key, action in pairs(ns.db.contextDefaults or {}) do
		SetBinding(key, nil)
		SetBinding(key, action ~= "" and action or nil, CONTEXT)
	end
	ns.db.contextDefaults = nil
	SaveBindings(GetCurrentBindingSet())
	print("LeanPad: Blizzard's gamepad buttons are back. Actions on your bars stay where they are.")
end)

StaticPopupDialogs.LEANPAD_RESET_GAMEPAD = {
	text = "Put back Blizzard's gamepad buttons?\n\nThis undoes every button LeanPad changed. Actions on your gamepad bars stay where they are.",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function() ns.OutOfCombat(ns.Apply) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Profiles keep context bindings beside the plain ones, marked, and every slot of the gamepad bars.
wrap("ExtraPadBindings", function(_, found)
	for _, action in ipairs(CONTEXT_ACTIONS) do
		for _, key in ipairs(contextKeys(action)) do found[CONTEXT_PREFIX .. key] = action end
	end
end)

local bindKey = ns.BindKey
function ns.BindKey(key, action)
	local contextKey = key:match("^" .. CONTEXT_PREFIX .. "(.+)$")
	if not contextKey then return bindKey(key, action) end
	-- A profile saved with the Gamepad UI off lists none of these, and clearing them would leave the pad dead when it's on.
	if action ~= "" then SetBinding(contextKey, action, CONTEXT) end
end

wrap("ExtraProfileSlots", function(_, slots)
	for page = 1, PAGES do
		for id = 1, SLOTS_PER_PAGE do
			local slot = GamepadActionBarBindingUtil.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(page, id)
			if slot then slots[slot] = true end
		end
	end
end)

-- The Gamepad UI holds its soft target settings as temporary CVars, which outrank saved values.
wrap("WritePadCVar", function(base, cvar, value)
	if cvar:find("^SoftTarget") then return C_CVar.SetTempCVar(cvar, value) end
	base(cvar, value)
end)

-- LeanPad's own menu. Blizzard's gamepad navigation adds every Blizzard menu to its focus state with no way to opt out,
-- so one opened by an addon taints that state, and then every window or popup that opens is blocked at
-- SetPreferredGamepadInteractTarget. This takes the entries LeanPad's menu builders add, and is worked with the cursor.
local MENU_ROW, MENU_MIN_WIDTH, MENU_MAX_HEIGHT = 24, 160, 400
local C = ns.COLORS
local menuLevels, menuUI = {}, {}

local function newMenu(text, callback)
	local menu = { text = text, callback = callback, entries = {} }
	function menu:CreateButton(label, onClick)
		local entry = newMenu(label, onClick)
		table.insert(self.entries, entry)
		return entry
	end
	function menu:CreateTitle(title) table.insert(self.entries, { text = title, title = true, entries = {} }) end
	function menu:CreateDivider() table.insert(self.entries, { divider = true, entries = {} }) end
	function menu:CreateRadio(label, isSelected, set, data)
		local entry = self:CreateButton(label, function() set(data) end)
		entry.selected = isSelected(data)
	end
	function menu:SetScrollMode() end -- every level scrolls once it outgrows MENU_MAX_HEIGHT
	return menu
end

-- Fills the screen behind the menu, so a click anywhere else closes it. Named for Escape's UISpecialFrames list.
local menuCatcher = CreateFrame("Button", "LeanPadMenu", UIParent)
menuCatcher:SetAllPoints(UIParent)
menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
menuCatcher:Hide()
menuCatcher:SetScript("OnClick", function(self) self:Hide() end)
menuCatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
menuCatcher:SetScript("OnEvent", function(self) self:Hide() end)
table.insert(UISpecialFrames, "LeanPadMenu")

local function closeLevels(from)
	for depth = from, #menuLevels do menuLevels[depth]:Hide() end
end

local function makeMenuRow(panel)
	local row = CreateFrame("Button", nil, panel.Child)
	row:SetHeight(MENU_ROW)
	row.Hover = row:CreateTexture(nil, "BACKGROUND")
	row.Hover:SetAllPoints()
	row.Hover:SetColorTexture(unpack(C.hover))
	row.Hover:Hide()
	row.Text = ns.Text(row, 13, C.text)
	row.Text:SetPoint("LEFT", 24, 0)
	row.Check = row:CreateTexture(nil, "ARTWORK")
	row.Check:SetAtlas("common-icon-checkmark")
	row.Check:SetSize(12, 12)
	row.Check:SetPoint("LEFT", 6, 0)
	row.Arrow = row:CreateTexture(nil, "ARTWORK")
	row.Arrow:SetAtlas("common-icon-forwardarrow")
	row.Arrow:SetSize(12, 12)
	row.Arrow:SetPoint("RIGHT", -6, 0)
	row.Rule = ns.Rule(row)
	row.Rule:SetPoint("LEFT", 6, 0)
	row.Rule:SetPoint("RIGHT", -6, 0)
	row:SetScript("OnEnter", function(self)
		local entry = self.entry
		closeLevels(panel.depth + 1)
		self.Hover:SetShown(entry.callback ~= nil or #entry.entries > 0)
		if #entry.entries > 0 then menuUI.showLevel(panel.depth + 1, entry, self, true) end
	end)
	row:SetScript("OnLeave", function(self) self.Hover:Hide() end)
	row:SetScript("OnClick", function(self)
		if not self.entry.callback then return end
		menuCatcher:Hide()
		self.entry.callback()
	end)
	return row
end

local function makeMenuLevel(depth)
	local panel = ns.Panel(menuCatcher, C.raised, C.edge)
	panel.depth, panel.rows = depth, {}
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	panel:SetFrameLevel(menuCatcher:GetFrameLevel() + depth * 5)
	panel.Scroll = CreateFrame("ScrollFrame", nil, panel)
	panel.Scroll:SetPoint("TOPLEFT", 1, -1)
	panel.Scroll:SetPoint("BOTTOMRIGHT", -1, 1)
	panel.Child = CreateFrame("Frame", nil, panel.Scroll)
	panel.Scroll:SetScrollChild(panel.Child)
	panel.Scroll:EnableMouseWheel(true)
	panel.Scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * MENU_ROW, self:GetVerticalScrollRange())))
	end)
	return panel
end

function menuUI.showLevel(depth, menu, anchor, isSubmenu)
	menuLevels[depth] = menuLevels[depth] or makeMenuLevel(depth)
	local panel = menuLevels[depth]
	local width = MENU_MIN_WIDTH
	for index, entry in ipairs(menu.entries) do
		panel.rows[index] = panel.rows[index] or makeMenuRow(panel)
		local row = panel.rows[index]
		row.entry = entry
		row.Text:SetText(entry.text or "")
		row.Text:SetFontObject(ns.Font(13, entry.title and C.muted or C.text))
		row.Check:SetShown(entry.selected == true)
		row.Arrow:SetShown(#entry.entries > 0)
		row.Rule:SetShown(entry.divider == true)
		row.Hover:Hide()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel.Child, "TOPLEFT", 0, -(index - 1) * MENU_ROW)
		row:SetPoint("RIGHT", panel.Child, "RIGHT")
		row:Show()
		width = math.max(width, row.Text:GetStringWidth() + 48)
	end
	for index = #menu.entries + 1, #panel.rows do panel.rows[index]:Hide() end
	local height = #menu.entries * MENU_ROW
	panel.Child:SetSize(width, height)
	panel.Scroll:SetVerticalScroll(0)
	panel:SetSize(width + 2, math.min(height, MENU_MAX_HEIGHT) + 2)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", anchor, isSubmenu and "TOPRIGHT" or "BOTTOMLEFT")
	panel:Show()
end

wrap("ContextMenu", function(_, owner, generator)
	local root = newMenu()
	generator(owner, root)
	closeLevels(1)
	menuCatcher:Show()
	menuUI.showLevel(1, root, owner)
end)

-- The crossbar takes the place of the mirrored bars. Fading keeps them working: Blizzard's bindings press their buttons.
local function fadeNative()
	local alpha = active() and ns.db.crossbar ~= false and 0 or 1
	for _, name in ipairs(MIRRORED_BARS) do pageUnit().actionBars[name]:SetAlpha(alpha) end
end

local setCrossbarShown = ns.SetCrossbarShown
function ns.SetCrossbarShown(shown)
	setCrossbarShown(shown)
	fadeNative()
end

local function refresh()
	if LeanPadCrossbar and LeanPadCrossbar:IsShown() then ns.RefreshCrossbar() end
	if LeanPadControllerFrame and LeanPadControllerFrame:IsShown() then
		LeanPadControllerFrame:GetScript("OnEvent")(LeanPadControllerFrame, "MODIFIER_STATE_CHANGED")
	end
end

-- Asks the player to turn the Gamepad UI off, since LeanPad does more without it. The client blocks addons from
-- switching it, so this says where the setting is, and LeanPad's layout is on offer once it goes off. LeanPad's own
-- window: Blizzard's popups and settings panel join the Gamepad UI's focus state, and opening them from an addon would
-- taint it, as menus do.
local PROMPT_TEXT = "LeanPad does the most with this turned off: spells on every button, commands on every layer, mouse clicks on the crossbar and answering quests with the pad.\n\nYou would lose Blizzard's radial menus, controller menu navigation and group targeting, and use the cursor for windows instead.\n\nTo turn it off, untick Enable Gamepad UI in Options > Gameplay > Gamepad (Alpha). LeanPad then offers its layout."
local prompt, awaitingOff

local function willTurnOff()
	prompt:Hide()
	awaitingOff = true
	print("LeanPad: untick Enable Gamepad UI in Options > Gameplay > Gamepad (Alpha), and LeanPad will offer its layout.")
end

local function keepGamepadUI()
	prompt:Hide()
	ns.db.gamepadUIKept = true
	print("LeanPad: keeping Blizzard's Gamepad UI, so some of LeanPad's features are limited. LeanPad won't ask again.")
end

local function buildPrompt()
	prompt = ns.Panel(UIParent, C.bg, C.edge)
	prompt:SetSize(480, 270)
	prompt:SetPoint("CENTER")
	prompt:SetFrameStrata("DIALOG")
	local title = ns.Text(prompt, 18, C.text, "CENTER")
	title:SetPoint("TOP", 0, -18)
	title:SetText("Turn off Blizzard's Gamepad UI?")
	local text = ns.Text(prompt, 13, C.text2)
	text:SetPoint("TOP", title, "BOTTOM", 0, -14)
	text:SetWidth(440)
	text:SetText(PROMPT_TEXT)
	local gotIt = ns.Button(prompt, ns.Glyphed("PAD1", "Got it", 16), 200, willTurnOff, true)
	gotIt:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -6, 18)
	local keep = ns.Button(prompt, ns.Glyphed("PAD2", "Keep it on, don't ask again", 16), 200, keepGamepadUI)
	keep:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 6, 18)
	prompt:EnableMouse(true)
	prompt:EnableGamePadButton(true)
	prompt:SetScript("OnGamePadButtonDown", function(self, key)
		self:SetPropagateKeyboardInput(key ~= "PAD1" and key ~= "PAD2")
		if key == "PAD1" then willTurnOff() elseif key == "PAD2" then keepGamepadUI() end
	end)
	-- Hidden, it hears nothing, so a fight that starts now keeps every button. It asks again at the next login.
	prompt:RegisterEvent("PLAYER_REGEN_DISABLED")
	prompt:SetScript("OnEvent", prompt.Hide)
end

local function askGamepadUI()
	if not active() or ns.db.gamepadUIKept or awaitingOff then return end
	if InCombatLockdown() then return EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", askGamepadUI) end
	if not prompt then buildPrompt() end
	prompt:Show()
end

local styleWatcher = CreateFrame("Frame")
styleWatcher:RegisterEvent("CVAR_UPDATE")
styleWatcher:SetScript("OnEvent", function(_, _, cvar)
	if cvar ~= "InputDeviceInterfaceStyle" then return end
	-- The client finishes switching after the CVar changes, so this reads the result a frame later.
	RunNextFrame(function()
		fadeNative()
		refresh()
		askGamepadUI()
		if awaitingOff and not active() then
			awaitingOff = nil
			ns.ShowSetup()
		end
	end)
end)

-- Hooks, not Blizzard's callback lists: those run inside its secure paging and modifier code, which an addon's
-- function would taint, and then its action buttons could be blocked in combat.
EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	hooksecurefunc(GamepadMode, "OnCrossBarModifierChanged", refresh)
	hooksecurefunc(pageUnit(), "SetCurrentPage", refresh)
	fadeNative()
	askGamepadUI()
end)
