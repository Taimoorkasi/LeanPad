-- Fake of the WoW client API that LeanPad touches. Each stub records what the addon did,
-- so specs can assert on CVars, bindings, popups and settings without a game client.
local M = {}

local realPrint = print

function M.reset()
	local w = {
		cvars = {}, bindings = {}, saved = {}, printed = {}, popups = {}, opened = {},
		onLoaded = {}, onceEvents = {}, metricCalls = {}, controls = {}, layout = {},
		combat = false,
	}
	M.state = w

	LeanPadDB = nil
	SLASH_LEANPAD1 = nil
	SlashCmdList = {}
	StaticPopupDialogs = {}
	NONE, OFF, ALWAYS, ACCEPT, CANCEL = "None", "Off", "Always", "Accept", "Cancel"

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
