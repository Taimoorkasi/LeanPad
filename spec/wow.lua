-- Fake of the WoW client API that LeanPad touches. Each stub records what the addon did,
-- so specs can assert on CVars, bindings, popups and settings without a game client.
local M = {}

local realPrint = print

-- Widget methods LeanPad may call. Anything else errors, so a misspelt method fails the specs.
local NO_OP_METHODS = {
	"SetSize", "SetHighlightTexture", "RegisterForClicks", "SetJustifyH", "SetTitle", "SetToplevel",
	"SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "SetThickness", "SetColorTexture",
	"SetStartPoint", "SetEndPoint", "StartMoving", "StopMovingOrSizing",
}

local Widget = {}
Widget.__index = function(_, method)
	return Widget[method] or error("widget method not allowed by spec/wow.lua: " .. tostring(method), 2)
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
function Widget:SetText(text) self.text = text end
function Widget:GetText() return self.text end
function Widget:SetTexture(texture) self.texture = texture end
function Widget:RegisterEvent(event) self.events[event] = true end
function Widget:UnregisterAllEvents() self.events = {} end
function Widget:EnableGamePadButton(enable) self.gamePadButton = enable end
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
-- Runs a script the way the client would, with the widget as self.
function Widget:Fire(script, ...) return self.scripts[script](self, ...) end

-- A fake Blizzard menu description: records titles and buttons so specs can read and click them.
local function newMenuDescription(text, callback)
	local description = { text = text, callback = callback, entries = {} }
	function description:CreateTitle(title) self.title = title end
	function description:CreateButton(label, onClick)
		local entry = newMenuDescription(label, onClick)
		table.insert(self.entries, entry)
		return entry
	end
	function description:SetScrollMode(extent) self.scrollExtent = extent end
	return description
end

function M.reset()
	local w = {
		cvars = {}, bindings = {}, saved = {}, printed = {}, popups = {}, opened = {},
		onLoaded = {}, onceEvents = {}, metricCalls = {}, controls = {}, layout = {},
		combat = false, widgets = {}, held = {}, placed = {}, textures = {},
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
	LeanPadControllerFrame = nil
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

	CreateFrame = function(kind, name, parent, template) return newWidget(kind, name, parent, template) end
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
	w.textures[61] = 135808

	GetNumBindings = function() return #w.bindingList end
	GetBinding = function(index) return w.bindingList[index][1], w.bindingList[index][2] end
	GetBindingName = function(action) return "name:" .. action end
	GetActionTexture = function(slot) return w.textures[slot] end
	GetCursorInfo = function() return w.cursor end
	PlaceAction = function(slot) table.insert(w.placed, slot) end
	IsAltKeyDown = function() return w.held.alt end
	IsControlKeyDown = function() return w.held.ctrl end
	IsShiftKeyDown = function() return w.held.shift end
	C_GamePad = { GetDeviceMappedState = function() return w.padState end }

	Enum = {
		SoftTargetEnableFlags = { None = 0, Gamepad = 1, Kbm = 2, Any = 3 },
		AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4 },
		BindingSet = { Default = 0, Account = 1, Character = 2, Current = 3 },
	}
	w.bindingSet = Enum.BindingSet.Account

	print = function(...) table.insert(w.printed, table.concat({ ... }, " ")) end
	InCombatLockdown = function() return w.combat end
	GetCVar = function(name) return w.cvars[name] end
	SetCVar = function(name, value) w.cvars[name] = value end
	GetBindingAction = function(key) return w.bindings[key] or "" end
	SetBinding = function(key, action) w.bindings[key] = action end
	SaveBindings = function(set) table.insert(w.saved, set) end
	GetCurrentBindingSet = function() return w.bindingSet end
	GetBindingText = function(key) return "text:" .. key end
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
