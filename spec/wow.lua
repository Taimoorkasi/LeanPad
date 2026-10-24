-- Fake of the WoW client API that LeanPad touches. Each stub records what the addon did,
-- so specs can assert on CVars, bindings, popups and settings without a game client.
local M = {}

local realPrint = print

-- Widget methods LeanPad may call. Any other PascalCase name errors, so a misspelt method fails the
-- specs; lowercase data fields read as nil, as on real frames.
local NO_OP_METHODS = {
	"SetSize", "SetWidth", "SetHeight", "SetJustifyH", "SetToplevel", "SetClampedToScreen", "SetMovable", "RegisterForDrag",
	"SetThickness", "AddMaskTexture", "SetBlendMode", "SetBackdrop", "SetBackdropBorderColor", "StartMoving", "StopMovingOrSizing",
	"SetAllPoints", "SetDrawSwipe", "SetFont", "SetTextColor", "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject",
	"SetNormalAtlas", "SetHighlightAtlas", "SetSpacing",
}

local Widget = {}
Widget.__index = function(_, key)
	if Widget[key] then return Widget[key] end
	if type(key) == "string" and key:find("^%u") then error("widget method not allowed by spec/wow.lua: " .. key, 2) end
end
for _, method in ipairs(NO_OP_METHODS) do Widget[method] = function() end end

local function newWidget(kind, name, parent, template)
	local widget = setmetatable({
		kind = kind, name = name, parent = parent, template = template,
		scripts = {}, events = {}, shown = true, gamePadButton = false,
	}, Widget)
	table.insert(M.state.widgets, widget)
	if name then _G[name] = widget end
	return widget
end

function Widget:GetName() return self.name end
function Widget:SetScript(script, handler) self.scripts[script] = handler end
function Widget:SetPoint(...) self.point = { ... } end
function Widget:ClearAllPoints() self.point = nil end
function Widget:GetPoint() return unpack(self.point) end
function Widget:EnableMouse(enabled) self.mouse = enabled end
function Widget:EnableMouseWheel(enabled) self.wheel = enabled end
function Widget:GetCenter() return self.cx or 0, self.cy or 0 end
function Widget:GetEffectiveScale() return self.effectiveScale or 1 end
function Widget:SetText(text) self.text = text end
function Widget:GetText() return self.text end
function Widget:SetTexture(texture) self.texture, self.color = texture, nil end
function Widget:SetColorTexture(...) self.texture, self.color = nil, { ... } end
function Widget:SetAtlas(atlas) self.atlas = atlas end
function Widget:SetTexCoord(...) self.texCoord = { ... } end
function Widget:SetVertexColor(...) self.vertexColor = { ... } end
function Widget:SetStartPoint(...) self.startPoint = { ... } end
function Widget:SetEndPoint(...) self.endPoint = { ... } end
function Widget:SetEnabled(enabled) self.enabled = enabled end
function Widget:SetScale(scale) self.scale = scale end
function Widget:SetAlpha(alpha) self.alpha = alpha end
function Widget:SetSwipeTexture(texture) self.swipeTexture = texture end
function Widget:SetUseCircularEdge(circular) self.circularEdge = circular end
function Widget:Clear() self.duration = nil end
function Widget:CreateMaskTexture() return newWidget("MaskTexture", nil, self) end
function Widget:RegisterEvent(event) self.events[event] = true end
function Widget:UnregisterAllEvents() self.events = {} end
function Widget:EnableGamePadButton(enable) self.gamePadButton = enable end
function Widget:SetPropagateKeyboardInput(propagate) self.propagate = propagate end
-- Animation groups and their animations record their settings, plays and stops.
function Widget:CreateAnimationGroup()
	local group = newWidget("AnimationGroup", nil, self)
	group.plays, group.stops = 0, 0
	return group
end
function Widget:CreateAnimation(type)
	local animation = newWidget("Animation", nil, self)
	animation.animationType = type
	return animation
end
function Widget:Play() self.plays, self.playing = self.plays + 1, true end
function Widget:Stop() self.stops, self.playing = self.stops + 1, false end
function Widget:IsPlaying() return self.playing == true end
function Widget:SetLooping(loop) self.looping = loop end
function Widget:SetFromAlpha(alpha) self.fromAlpha = alpha end
function Widget:SetToAlpha(alpha) self.toAlpha = alpha end
function Widget:SetDuration(seconds) self.seconds = seconds end
function Widget:SetTarget(target) self.target = target end
function Widget:SetDesaturated(desaturated) self.desaturated = desaturated end
function Widget:SetCooldownFromDurationObject(duration) self.duration = duration end
function Widget:SetHideCountdownNumbers(hide) self.hideNumbers = hide end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:GetFrameLevel() return rawget(self, "level") or 1 end
function Widget:IsShown() return self.shown end
function Widget:SetShown(shown)
	if shown == self.shown then return end
	self.shown = shown
	local script = self.scripts[shown and "OnShow" or "OnHide"]
	if script then script(self) end
end
function Widget:Show() self:SetShown(true) end
function Widget:Hide() self:SetShown(false) end
function Widget:CreateTexture() return newWidget("Texture", nil, self) end
function Widget:CreateFontString() return newWidget("FontString", nil, self) end
function Widget:CreateLine() return newWidget("Line", nil, self) end
function Widget:SetBackdropColor(...) self.backdropColor = { ... } end
function Widget:SetFontObject(font) self.font = font end
function Widget:GetTextWidth() return 40 end
function Widget:SetHighlightTexture(texture) self:GetHighlightTexture().texture = texture end
function Widget:GetHighlightTexture()
	self.highlight = self.highlight or newWidget("Texture", nil, self)
	return self.highlight
end
function Widget:GetFontString()
	self.fontString = self.fontString or newWidget("FontString", nil, self)
	return self.fontString
end
-- Runs a script the way the client would, with the widget as self.
function Widget:Fire(script, ...) return self.scripts[script](self, ...) end

-- A fake Blizzard menu description: records titles and buttons so specs can read and click them.
local function newMenuDescription(text, callback)
	local description = { text = text, callback = callback, entries = {} }
	function description:CreateTitle(title)
		self.title = self.title or title
		self.titles = self.titles or {}
		table.insert(self.titles, title)
	end
	function description:CreateButton(label, onClick)
		local entry = newMenuDescription(label, onClick)
		table.insert(self.entries, entry)
		return entry
	end
	function description:SetScrollMode(extent) self.scrollExtent = extent end
	function description:CreateRadio(label, isSelected, setSelected, data)
		local entry = newMenuDescription(label, function() setSelected(data) end)
		entry.selected = function() return isSelected(data) end
		table.insert(self.entries, entry)
		return entry
	end
	return description
end

function M.reset()
	local w = {
		cvars = {}, bindings = {}, saved = {}, printed = {}, popups = {}, opened = {},
		onLoaded = {}, onceEvents = {}, metricCalls = {}, controls = {}, layout = {},
		combat = false, widgets = {}, held = {}, placed = {}, actions = {}, nextFrame = {},
		glyphs = {}, devices = {}, deviceIDs = {}, power = 5, timers = {}, callbacks = {}, pickups = {}, cleared = 0,
		barsShown = { true, true, true, true, true, true, true }, -- Action Bars 2-8, as GetActionBarToggles returns them
		bar = { page = 1 },
		forms = {}, form = 0, addons = {},
		procs = {},
		-- A paladin's spellbook: General and the active spec's tab show; an off-spec tab and a hidden one don't.
		skillLines = {
			{ name = "General", iconID = 1, itemIndexOffset = 0, numSpellBookItems = 2 },
			{ name = "Retribution", iconID = 2, itemIndexOffset = 2, numSpellBookItems = 3, specID = 70 },
			{ name = "Holy", iconID = 3, itemIndexOffset = 5, numSpellBookItems = 1, offSpecID = 65 },
			{ name = "Hidden", iconID = 4, itemIndexOffset = 6, numSpellBookItems = 0, shouldHide = true },
		},
		spellBook = {
			{ name = "Divine Shield", iconID = 135896, itemType = 1 }, { name = "Plate Specialization", iconID = 5, itemType = 1, isPassive = true },
			{ name = "Judgment", iconID = 135959, itemType = 1 }, { name = "Blessings", iconID = 6, itemType = 4 },
			{ name = "Beacon of Light", iconID = 7, itemType = 1, isOffSpec = true }, { name = "Holy Shock", iconID = 8, itemType = 1 },
		},
		macros = { { name = "Mount up", icon = 9 } }, characterMacros = { { name = "Focus", icon = 10 } },
		bindingList = {
			{ "HEADER_BLANK", "BINDING_HEADER_MOVEMENT" },
			{ "JUMP", "BINDING_HEADER_MOVEMENT" },
			{ "PREFACE_ACTIONBAR", "BINDING_HEADER_ACTIONBAR" },
			{ "ACTIONBUTTON1", "BINDING_HEADER_ACTIONBAR" },
			{ "MULTIACTIONBAR1BUTTON1", "BINDING_HEADER_MULTIACTIONBAR" },
			{ "SOME_ADDON_COMMAND", nil },
		},
	}
	M.state = w

	LeanPadDB = nil
	LeanPadControllerFrame, LeanPadCrossbar = nil, nil
	SLASH_LEANPAD1 = nil
	SlashCmdList = {}
	StaticPopupDialogs = {}
	UISpecialFrames = {}
	UIParent = newWidget("Frame", "UIParent")
	NONE, OFF, ALWAYS, ACCEPT, CANCEL = "None", "Off", "Always", "Accept", "Cancel"
	UNBIND, NOT_BOUND, KEY_BINDINGS = "Unbind Key", "Not Bound", "Key Bindings"
	BINDING_HEADER_MOVEMENT, BINDING_HEADER_ACTIONBAR, BINDING_HEADER_OTHER = "Movement", "Action Bar", "Other"
	BINDING_HEADER_MULTIACTIONBAR = nil
	NUM_ACTIONBAR_BUTTONS = 12
	SETTINGS = "Settings"
	GameFontHighlightMedium = {}

	CreateFrame = function(kind, name, parent, template)
		local frame = newWidget(kind, name, parent, template)
		-- Blizzard's spell alert: a birth flipbook, then a loop it starts itself, hidden until shown.
		if template == "ActionButtonSpellAlertTemplate" then
			frame.ProcStartAnim, frame.ProcLoop = frame:CreateAnimationGroup(), frame:CreateAnimationGroup()
			frame.shown = false
		end
		return frame
	end
	CreateFont = function(name) return newWidget("Font", name) end
	ButtonFrameTemplate_HidePortrait = function(frame) frame.portraitHidden = true end
	PanelTemplates_SetNumTabs = function(frame, count) frame.numTabs = count end
	PanelTemplates_SetTab = function(frame, index) frame.selectedTab = index end
	PanelTemplates_TabResize = function(tab) tab.resized = true end
	MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local root = newMenuDescription()
			generator(owner, root)
			w.menu = { owner = owner, root = root }
		end,
	}

	-- Two Blizzard bar buttons: Action Bar 1 slot 1 (no icon) and Action Bar 2 slot 1, which holds slot 61.
	ActionButtonUtil = { ActionBarButtonNames = { "ActionButton", "MultiBarBottomLeftButton" } }
	ActionButton1 = { bindingAction = "ACTIONBUTTON1", action = 1 }
	MultiBarBottomLeftButton1 = { bindingAction = "MULTIACTIONBAR1BUTTON1", action = 61 }
	w.actions[61] = { texture = 135808, kind = "spell", id = 1953, cooldown = "cooldown:61", charge = "charge:61", count = "2", usable = true }

	GetNumBindings = function() return #w.bindingList end
	-- The action, its category, then every key bound to it, as the client returns them.
	GetBinding = function(index)
		local action, keys = w.bindingList[index][1], {}
		for key, bound in pairs(w.bindings) do
			if bound == action then table.insert(keys, key) end
		end
		table.sort(keys)
		return action, w.bindingList[index][2], unpack(keys)
	end
	GetBindingName = function(action) return "name:" .. action end
	-- Slots in w.actions hold an action; cooldowns come back as opaque duration objects, as in Midnight.
	local function action(slot) return w.actions[slot] or {} end
	C_ActionBar = {
		HasAction = function(slot) return w.actions[slot] ~= nil end,
		-- Action Bar 1's paging state, in w.bar: its page, and the vehicle, override, temporary or bonus bar index if any.
		GetActionBarPage = function() return w.bar.page end,
		HasVehicleActionBar = function() return w.bar.vehicle ~= nil end,
		GetVehicleBarIndex = function() return w.bar.vehicle end,
		HasOverrideActionBar = function() return w.bar.override ~= nil end,
		GetOverrideBarIndex = function() return w.bar.override end,
		HasTempShapeshiftActionBar = function() return w.bar.temp ~= nil end,
		GetTempShapeshiftBarIndex = function() return w.bar.temp end,
		HasBonusActionBar = function() return w.bar.bonus ~= nil end,
		GetBonusBarIndex = function() return w.bar.bonus end,
		GetActionTexture = function(slot) return action(slot).texture end,
		GetActionCooldownDuration = function(slot) return action(slot).cooldown end,
		GetActionChargeDuration = function(slot) return action(slot).charge end,
		GetActionDisplayCount = function(slot) return action(slot).count end,
		IsUsableAction = function(slot) return action(slot).usable end,
		IsActionInRange = function(slot) return action(slot).inRange end,
		GetActionText = function(slot) return action(slot).text end,
	}
	GetActionInfo = function(slot) return action(slot).kind, action(slot).id end
	-- Spells lit by a proc, in w.procs.
	C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return w.procs[id] == true end }
	C_Spell = { GetSpellName = function(id) return "spell:" .. id end }
	-- Forms in w.forms, each { spell, icon }, the one taken in w.form (0 for none), and stealth in w.stealthed.
	GetNumShapeshiftForms = function() return #w.forms end
	GetShapeshiftForm = function() return w.form end
	GetShapeshiftFormInfo = function(index) return w.forms[index].icon, index == w.form, true, w.forms[index].spell end
	IsStealthed = function() return w.stealthed end
	C_AddOns = { IsAddOnLoaded = function(name) return w.addons[name] == true end }
	C_Item = { GetItemNameByID = function(id) return "item:" .. id end }
	GetCVarBool = function(name) return w.cvars[name] == "1" end
	RunNextFrame = function(callback) table.insert(w.nextFrame, callback) end
	C_Timer = { After = function(seconds, callback) table.insert(w.timers, { seconds = seconds, callback = callback }) end }
	-- A Beast Mastery hunter until a spec says otherwise.
	w.spec, w.specID, w.role = 1, 253, "DAMAGER"
	GetSpecialization = function() return w.spec end
	GetSpecializationInfo = function() return w.specID end
	GetSpecializationRole = function() return w.role end
	EventRegistry = { RegisterCallback = function(_, event, callback) w.callbacks[event] = callback end }
	-- Like the client's: an error goes to the error handler and the caller carries on.
	w.errors = {}
	securecallfunction = function(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then table.insert(w.errors, err) end
	end
	GetCursorInfo = function() return w.cursor end
	ClearCursor = function()
		w.cursor = nil
		w.cleared = w.cleared + 1
	end
	C_SpellBook = {
		GetNumSpellBookSkillLines = function() return #w.skillLines end,
		GetSpellBookSkillLineInfo = function(index) return w.skillLines[index] end,
		GetSpellBookItemInfo = function(index) return w.spellBook[index] end,
		PickupSpellBookItem = function(index, bank)
			w.cursor = "spell"
			table.insert(w.pickups, { "spell", index, bank })
		end,
	}
	Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120 } }
	GetNumMacros = function() return #w.macros, #w.characterMacros end
	GetMacroInfo = function(index)
		local macro = index > 120 and w.characterMacros[index - 120] or w.macros[index]
		return macro.name, macro.icon
	end
	PickupMacro = function(index)
		w.cursor = "macro"
		table.insert(w.pickups, { "macro", index })
	end
	GetBindingKey = function(command)
		local keys = {}
		for key, action in pairs(w.bindings) do
			if action == command then table.insert(keys, key) end
		end
		table.sort(keys)
		return unpack(keys)
	end
	GameTooltip = {
		SetOwner = function(_, owner, anchor) w.tooltip = { owner = owner, anchor = anchor } end,
		SetAction = function(_, slot) w.tooltip.slot = slot end,
		SetText = function(_, text) w.tooltip.text = text end,
		Show = function() w.tooltip.shown = true end,
		Hide = function() w.tooltip = nil end,
	}
	PlaceAction = function(slot) table.insert(w.placed, slot) end
	PickupAction = function(slot) table.insert(w.pickups, { "action", slot }) end
	IsAltKeyDown = function() return w.held.alt end
	IsControlKeyDown = function() return w.held.ctrl end
	IsShiftKeyDown = function() return w.held.shift end
	C_GamePad = {
		GetDeviceMappedState = function(id)
			if id then return w.devices[id] end
			return w.padState
		end,
		GetAllDeviceIDs = function() return w.deviceIDs end,
		GetPowerLevel = function() return w.power end,
	}
	w.cursorControl = false
	SetGamePadCursorControl = function(enabled) w.cursorControl = enabled end
	IsGamePadCursorControlEnabled = function() return w.cursorControl end

	Enum = {
		SoftTargetEnableFlags = { None = 0, Gamepad = 1, Kbm = 2, Any = 3 },
		AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4 },
		BindingSet = { Default = 0, Account = 1, Character = 2, Current = 3 },
		SpellBookSpellBank = { Player = 0, Pet = 1 },
		SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
	}
	w.bindingSet = Enum.BindingSet.Account

	print = function(...) table.insert(w.printed, table.concat({ ... }, " ")) end
	InCombatLockdown = function() return w.combat end
	GetCVar = function(name) return w.cvars[name] end
	SetCVar = function(name, value) w.cvars[name] = value end
	GetBindingAction = function(key) return w.bindings[key] or "" end
	SetBinding = function(key, action) w.bindings[key] = action end
	SaveBindings = function(set) table.insert(w.saved, set) end
	GetActionBarToggles = function() return unpack(w.barsShown) end
	GetCurrentBindingSet = function() return w.bindingSet end
	GetBindingText = function(key) return w.glyphs[key] or ("text:" .. key) end
	StaticPopup_Show = function(which) table.insert(w.popups, which) end

	C_AddOnProfiler = {
		GetAddOnMetric = function(name, metric)
			table.insert(w.metricCalls, { name, metric })
			return metric + 0.5
		end,
	}

	EventUtil = {
		ContinueOnAddOnLoaded = function(name, callback) table.insert(w.onLoaded, { name, callback }) end,
		RegisterOnceFrameEventAndCallback = function(event, callback) table.insert(w.onceEvents, { event, callback }) end,
	}

	local category = { GetID = function() return 42 end }
	local layout = { AddInitializer = function(_, initializer) table.insert(w.layout, initializer) end }
	Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		ACTION_BAR_CATEGORY_ID = 9,
		KEYBINDINGS_CATEGORY_ID = 7,
		RegisterVerticalLayoutCategory = function(name)
			w.categoryName = name
			return category, layout
		end,
		RegisterAddOnCategory = function(registered) w.registered = registered end,
		OpenToCategory = function(id) table.insert(w.opened, id) end,
		RegisterProxySetting = function(_, variable, variableType, label, default, getValue, setValue)
			return { variable = variable, type = variableType, label = label, default = default, getValue = getValue, setValue = setValue }
		end,
		CreateDropdown = function(_, setting, options, tooltip)
			table.insert(w.controls, { kind = "dropdown", variable = setting.variable, setting = setting, options = options, tooltip = tooltip })
		end,
		CreateCheckbox = function(_, setting, tooltip)
			table.insert(w.controls, { kind = "checkbox", variable = setting.variable, setting = setting, tooltip = tooltip })
		end,
		SetupCVarCheckbox = function(_, variable, label)
			table.insert(w.controls, { kind = "checkbox", variable = variable, label = label })
		end,
		SetupCVarDropdown = function(_, variable, variableType, options, label)
			table.insert(w.controls, { kind = "dropdown", variable = variable, type = variableType, options = options, label = label })
		end,
		CreateControlTextContainer = function()
			local data = {}
			return {
				Add = function(_, value, label) table.insert(data, { value = value, label = label }) end,
				GetData = function() return data end,
			}
		end,
	}
	w.category = category

	CreateSettingsListSectionHeaderInitializer = function(text) return { kind = "header", text = text } end
	CreateSettingsButtonInitializer = function(name, text, click, tooltip, searchable)
		return { kind = "button", name = name, text = text, click = click, tooltip = tooltip, searchable = searchable }
	end

	return w
end

function M.restore()
	print = realPrint
end

-- Runs callbacks queued with RunNextFrame, as the next frame would.
function M.nextFrame()
	local queued = M.state.nextFrame
	M.state.nextFrame = {}
	for _, callback in ipairs(queued) do callback() end
end

-- Fires every timer queued with C_Timer.After, as if their time had passed.
function M.tick()
	local due = M.state.timers
	M.state.timers = {}
	for _, timer in ipairs(due) do timer.callback() end
end

-- Fires an EventRegistry callback, as Blizzard's UI would.
function M.trigger(event)
	M.state.callbacks[event]()
end

-- Finds a menu entry by its exact label.
function M.entry(description, text)
	for _, entry in ipairs(description.entries) do
		if entry.text == text then return entry end
	end
end

-- Widgets of a kind and template, in creation order.
function M.widgets(kind, template)
	local found = {}
	for _, widget in ipairs(M.state.widgets) do
		if widget.kind == kind and rawget(widget, "template") == template then table.insert(found, widget) end
	end
	return found
end

-- Files in TOC order, the order the client loads them.
function M.tocFiles()
	local files = {}
	for line in io.lines("LeanPad/LeanPad.toc") do
		line = line:gsub("%s+$", "")
		if line ~= "" and not line:find("^#") then table.insert(files, line) end
	end
	return files
end

-- A "## Key: value" line from the TOC.
function M.tocHeader(key)
	for line in io.lines("LeanPad/LeanPad.toc") do
		local value = line:match("^## " .. key .. ": (.+)$")
		if value then return value end
	end
end

-- Runs every addon file the way the client does: with the addon name and a shared namespace as varargs.
function M.loadAddon()
	local ns = {}
	for _, file in ipairs(M.tocFiles()) do
		assert(loadfile("LeanPad/" .. file))("LeanPad", ns)
	end
	return ns
end

function M.addonLoaded(name)
	for _, entry in ipairs(M.state.onLoaded) do
		if entry[1] == name then entry[2]() end
	end
end

-- Fires a one-shot event: matching callbacks run once and are dropped, like EventUtil's.
function M.fire(event)
	local pending = M.state.onceEvents
	M.state.onceEvents = {}
	for _, entry in ipairs(pending) do
		if entry[1] == event then
			entry[2]()
		else
			table.insert(M.state.onceEvents, entry)
		end
	end
end

-- Sets up a loaded, ready addon: saved variables in place and ADDON_LOADED fired.
function M.boot(savedVariables)
	M.reset()
	local ns = M.loadAddon()
	LeanPadDB = savedVariables
	M.addonLoaded("LeanPad")
	return ns, M.state
end

return M
