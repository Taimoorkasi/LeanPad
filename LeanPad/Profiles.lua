local _, ns = ...

-- A profile is the whole controller setup under a name: LeanPad's settings, every pad binding, the controller
-- CVars and what the pad's bar slots hold. Profiles are account-wide in LeanPadDB.profiles; each character keeps
-- which one it uses and which spec switches to which in LeanPadCharDB. The active profile is saved from the live
-- setup when the character switches away, and at logout or reload, which is when WoW writes saved variables anyway.

-- LeanPad's own bookkeeping stays out of profiles.
local BOOKKEEPING = { prompted = true, backup = true, undo = true, formPages = true, profiles = true }
-- Every CVar the setup, play styles and settings page write, but the active pad: a device ID put back after
-- the pads change could leave no controller working.
local CVARS = {
	GamePadEmulateAlt = true, GamePadCursorSpeedMax = true, GamePadCursorAutoEnable = true,
	GamePadCursorAutoDisableSticks = true, GamePadTouchCursorEnable = true,
}
for cvar in pairs(ns.CVARS) do CVARS[cvar] = true end
for _, preset in pairs(ns.PLAYSTYLES) do
	for cvar in pairs(preset) do CVARS[cvar] = true end
end

local function specID()
	local spec = GetSpecialization()
	return spec and GetSpecializationInfo(spec)
end

-- The bar slots pad bindings fire: Bar 1's on its normal page and every learned form's, the others' own.
local function padSlots(bindings)
	local slots = {}
	for _, action in pairs(bindings) do
		local index = tonumber(action:match("^ACTIONBUTTON(%d+)$"))
		if index then
			for _, page in ipairs(ns.PageOptions()) do slots[index + (page[1] - 1) * NUM_ACTIONBAR_BUTTONS] = true end
		else
			local slot = ns.SlotForCommand(action)
			if slot then slots[slot] = true end
		end
	end
	return slots
end

-- What a slot holds, as kind and id; a macro by name, since its index shifts as macros come and go. False when empty.
local function slotEntry(slot)
	local kind, id = GetActionInfo(slot)
	if kind == "macro" then id = C_ActionBar.GetActionText(slot) end
	return kind and { kind, id } or false
end

local function same(a, b)
	return (a and a[1] .. tostring(a[2])) == (b and b[1] .. tostring(b[2]))
end

local function pickupMacro(name)
	local account, character = GetNumMacros()
	for i = 1, account + character do
		local index = i > account and Constants.MacroConsts.MAX_ACCOUNT_MACROS + i - account or i
		if GetMacroInfo(index) == name then return PickupMacro(index) end
	end
end

-- Puts each saved slot back, leaving slots that already match, and returns how many it couldn't: a spell the
-- character doesn't know, a macro since deleted, an item not on them, or a kind such as a mount or flyout.
local function restoreSlots(slots)
	local skipped = 0
	for slot, want in pairs(slots or {}) do
		if not same(slotEntry(slot), want) then
			ClearCursor()
			if not want then
				PickupAction(slot)
			elseif want[1] == "spell" then
				C_Spell.PickupSpell(want[2])
			elseif want[1] == "item" then
				C_Item.PickupItem(want[2])
			elseif want[1] == "macro" then
				pickupMacro(want[2])
			end
			if want and GetCursorInfo() then
				PlaceAction(slot)
			elseif want then
				skipped = skipped + 1
			end
			ClearCursor()
		end
	end
	return skipped
end

-- The live setup as a profile. Bar slots are kept per spec, as WoW keeps bars, so one profile serves every spec
-- and class that uses it; withSlots adds this spec's to the ones given.
local function capture(slots, withSlots)
	local profile = ns.Snapshot(CVARS)
	profile.settings = {}
	for key, value in pairs(ns.db) do
		if not BOOKKEEPING[key] then profile.settings[key] = type(value) == "table" and CopyTable(value) or value end
	end
	profile.slots = slots or {}
	local spec = withSlots and specID()
	if spec then
		local saved = {}
		for slot in pairs(padSlots(profile.bindings)) do saved[slot] = slotEntry(slot) end
		profile.slots[spec] = saved
	end
	return profile
end

local function save(withSlots)
	local name = ns.char.profile
	local old = ns.db.profiles and ns.db.profiles[name]
	if old then ns.db.profiles[name] = capture(old.slots, withSlots) end
end

local function differs(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then return true end
	end
end

-- Makes a profile the live setup. Bindings and CVars are written only when they differ, so logging in on an
-- unchanged profile writes nothing.
local function apply(name, withSlots)
	local profile = ns.db.profiles[name]
	for key in pairs(ns.db) do
		if not BOOKKEEPING[key] then ns.db[key] = nil end
	end
	for key, value in pairs(CopyTable(profile.settings)) do ns.db[key] = value end
	local live = ns.Snapshot(CVARS)
	if differs(profile.bindings, live.bindings) or differs(live.bindings, profile.bindings) or differs(profile.cvars, live.cvars) then
		ns.PutBack(profile)
	end
	local skipped = withSlots and restoreSlots(profile.slots[specID()]) or 0
	if skipped > 0 then
		print(("LeanPad: %s has a spell, macro or item this character doesn't have in %d bar slot(s); they were left as they were."):format(name, skipped))
	end
	ns.ApplyPlaystyle()
	ns.ApplyCrossbarSettings()
	if ns.window then
		ns.window:SetScale(ns.db.windowScale or 1)
		if ns.window:IsShown() then ns.RefreshController() end
	end
end

function ns.ProfileNames()
	local names = {}
	for name in pairs(ns.db.profiles or {}) do table.insert(names, name) end
	table.sort(names)
	return names
end

-- Switching saves the profile in use first. A spec change leaves the bars to WoW, which already swapped them
-- for the new spec's; the profile's own slots move only when switched by hand or at login.
function ns.SwitchProfile(name, bySpec)
	if not (ns.db.profiles and ns.db.profiles[name]) then return print(("LeanPad: no profile named %s."):format(name)) end
	ns.OutOfCombat(function()
		if ns.char.profile then
			save(not bySpec)
		else
			ns.db.undo = ns.Snapshot() -- nothing else holds this character's own layout; Undo reset brings it back
		end
		ns.char.profile = name
		apply(name, not bySpec)
		print(("LeanPad: profile %s in use."):format(name))
	end)
end

-- A trimmed name no profile has yet, or nil.
local function freeName(name)
	name = name:match("^%s*(.-)%s*$")
	if name == "" then return end
	if ns.db.profiles[name] then return print(("LeanPad: there is already a profile named %s."):format(name)) end
	return name
end

function ns.NewProfile(name)
	name = freeName(name)
	if not name then return end
	save(true)
	ns.db.profiles[name] = capture(nil, true)
	ns.char.profile = name
	print(("LeanPad: profile %s made from your current setup, and in use."):format(name))
	ns.RefreshOptions()
end

function ns.CopyProfile(name)
	name = freeName(name)
	if not name then return end
	save(true)
	ns.db.profiles[name] = CopyTable(ns.db.profiles[ns.char.profile])
	print(("LeanPad: %s copied to %s."):format(ns.char.profile, name))
end

-- Other characters that use the old name lose their link to it and keep their setup as it is.
function ns.RenameProfile(name)
	name = freeName(name)
	if not name then return end
	local old = ns.char.profile
	ns.db.profiles[name], ns.db.profiles[old] = ns.db.profiles[old], nil
	ns.char.profile = name
	for spec, linked in pairs(ns.char.specs) do
		if linked == old then ns.char.specs[spec] = name end
	end
	ns.RefreshOptions()
end

-- The live setup stays as it is; the character just uses no profile until it picks one.
function ns.DeleteProfile(name)
	ns.db.profiles[name] = nil
	if ns.char.profile == name then ns.char.profile = nil end
	for spec, linked in pairs(ns.char.specs) do
		if linked == name then ns.char.specs[spec] = nil end
	end
	print(("LeanPad: profile %s deleted."):format(name))
	ns.RefreshOptions()
end

function ns.LinkSpec(spec, name)
	ns.char.specs[spec] = name or nil
end

-- Before profiles, every setting lived in one account-wide table: it becomes Default, used by the first
-- character to log in. Later, each login puts the character's profile in place, as another character may
-- have changed it.
EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	if not ns.db.profiles then
		ns.db.profiles = { Default = capture(nil, true) }
		ns.char.profile = "Default"
		return
	end
	local name = ns.char.profile
	if not ns.db.profiles[name] then
		ns.char.profile = nil
		return
	end
	ns.OutOfCombat(function() apply(name, true) end)
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" then return save(true) end
	local name = ns.char.specs[specID()]
	if name and name ~= ns.char.profile then ns.SwitchProfile(name, true) end
end)
