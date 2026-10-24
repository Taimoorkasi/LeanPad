local _, ns = ...

-- LT/RT become Shift/Ctrl, giving three crossbar layers: LT, RT and LT+RT.
-- Cursor clicks move off RT, Blizzard's default, so they don't share it with Ctrl.
ns.CVARS = {
	GamePadEnable = "1",
	GamePadEmulateShift = "PADLTRIGGER",
	GamePadEmulateCtrl = "PADRTRIGGER",
	GamePadCursorLeftClick = "PAD1",
	GamePadCursorRightClick = "PAD2",
	SoftTargetEnemy = tostring(Enum.SoftTargetEnableFlags.Gamepad),
	SoftTargetFriend = tostring(Enum.SoftTargetEnableFlags.Gamepad),
	SoftTargetInteract = tostring(Enum.SoftTargetEnableFlags.Gamepad),
}

ns.BINDINGS = {
	PAD1 = "JUMP",
	PAD2 = "INTERACTTARGET",
	PAD3 = "ACTIONBUTTON1",
	PAD4 = "ACTIONBUTTON2",
	PADLSHOULDER = "ACTIONBUTTON3",
	PADRSHOULDER = "ACTIONBUTTON4",
	PADDUP = "ACTIONBUTTON5",
	PADDDOWN = "ACTIONBUTTON6",
	PADDLEFT = "TARGETPREVIOUSENEMY",
	PADDRIGHT = "TARGETNEARESTENEMY",
	-- The triggers are Shift and Ctrl now; clear their own bindings so a tap doesn't fire a leftover action.
	PADLTRIGGER = "",
	PADRTRIGGER = "",
	PADLSTICK = "TOGGLEAUTORUN",
	PADRSTICK = "LEANPAD_TOGGLE_CURSOR", -- the cursor, for clicking NPCs, objects and UI; A and B then click
	PADBACK = "OPENALLBAGS",
	PADFORWARD = "TOGGLEGAMEMENU",
	["SHIFT-PADBACK"] = "TOGGLEWORLDMAP",
	["CTRL-PADBACK"] = "TOGGLECHARACTER0",
	["SHIFT-PADFORWARD"] = "TOGGLESPELLBOOK",
}

-- Each trigger layer puts the D-pad and face buttons, clockwise from the top, onto slots 1-8 of one Blizzard bar,
-- so the bar placed in Edit Mode is that layer's crossbar and Blizzard draws cooldowns, glows and range.
local CROSS = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT", "PAD4", "PAD2", "PAD1", "PAD3" }
-- Each layer's own bar, where the editor finds a free slot for a button that fires none yet.
ns.LAYER_BARS = {
	[""] = "ACTIONBUTTON", -- Action Bar 1
	["SHIFT-"] = "MULTIACTIONBAR1BUTTON", -- Action Bar 2
	["CTRL-"] = "MULTIACTIONBAR2BUTTON", -- Action Bar 3
	["CTRL-SHIFT-"] = "MULTIACTIONBAR3BUTTON", -- Action Bar 4
}
for prefix, bar in pairs(ns.LAYER_BARS) do
	if prefix ~= "" then
		for slot, key in ipairs(CROSS) do
			ns.BINDINGS[prefix .. key] = bar .. slot
		end
	end
end

-- Bindings and CVars are only written out of combat; a request made in combat runs once it ends.
function ns.OutOfCombat(fn)
	if not InCombatLockdown() then return fn() end
	print("LeanPad: will apply when combat ends.")
	EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", fn)
end

local function bind(key, action)
	SetBinding(key, action ~= "" and action or nil)
end

-- Every gamepad binding on any modifier, key to action; keyboard and mouse keys are left alone.
local function padBindings()
	local found = {}
	for i = 1, GetNumBindings() do
		local binding = { GetBinding(i) } -- action, category, then each key bound to it
		for k = 3, #binding do
			if binding[k]:gsub("^.*%-", ""):match("^PAD") then found[binding[k]] = binding[1] end
		end
	end
	return found
end

local function clearPad()
	for key in pairs(padBindings()) do SetBinding(key, nil) end
end

-- The controller CVars and every pad binding, so putting it back leaves nothing of what came after.
local function snapshot()
	local saved = { cvars = {}, bindings = padBindings(), all = true }
	for cvar in pairs(ns.CVARS) do saved.cvars[cvar] = GetCVar(cvar) end
	return saved
end

-- Backups made before 0.3 hold only the preset's keys and no `all`: the pad keys outside it were never touched,
-- so they are kept rather than cleared.
local function putBack(saved)
	if saved.all then clearPad() end
	for cvar, value in pairs(saved.cvars) do SetCVar(cvar, value) end
	for key, action in pairs(saved.bindings) do bind(key, action) end
	SaveBindings(GetCurrentBindingSet())
end

-- Starts over on LeanPad's layout: every pad binding is cleared first, so no old chord fires alongside it.
-- Two backups: the state from before LeanPad's first setup, for Undo setup, and the layout each reset
-- replaced, for Undo reset.
function ns.Apply()
	local db, before = ns.db, snapshot()
	db.backup = db.backup or before
	db.undo = before
	clearPad()
	for cvar, value in pairs(ns.CVARS) do SetCVar(cvar, value) end
	for key, action in pairs(ns.BINDINGS) do bind(key, action) end
	SaveBindings(GetCurrentBindingSet())
	print("LeanPad: controller set up. Show Action Bars 2-4 to see the LT, RT and LT+RT layers. Undo reset brings back your previous layout.")
end

-- shortcut: restores into the current binding set, wrong if the user switched account/character sets since Apply; store the set if that comes up.
function ns.Restore()
	local backup = ns.db.backup
	if not backup then return print("LeanPad: nothing to restore.") end
	putBack(backup)
	ns.db.backup, ns.db.undo = nil, nil
	print("LeanPad: previous controller settings and bindings restored.")
end

function ns.UndoReset()
	local undo = ns.db.undo
	if not undo then return print("LeanPad: no reset to undo.") end
	putBack(undo)
	ns.db.undo = nil
	print("LeanPad: your layout from before the last reset is back.")
end

-- True when any chord the preset would write is already bound, i.e. the player has a layout of their own.
function ns.HasPadLayout()
	for key in pairs(ns.BINDINGS) do
		if GetBindingAction(key) ~= "" then return true end
	end
	return false
end

function ns.KeepLayout()
	SetCVar("GamePadEnable", "1")
	print("LeanPad: gamepad on, your layout is unchanged. /lp shows it.")
end

-- Never offers to overwrite an existing layout without asking; keeping it is the default.
function ns.ShowSetup()
	StaticPopup_Show(ns.HasPadLayout() and "LEANPAD_SETUP_EXISTING" or "LEANPAD_SETUP")
end

StaticPopupDialogs.LEANPAD_SETUP_EXISTING = {
	text = "LeanPad found a controller layout already bound.\n\nKeep it, and LeanPad only makes sure the gamepad is on. Or switch to LeanPad's layout; yours is saved so Undo reset, or /lp undo, brings it back.",
	button1 = "Keep my layout",
	button2 = CANCEL,
	button3 = "Use LeanPad layout",
	OnAccept = function() ns.OutOfCombat(ns.KeepLayout) end,
	OnAlt = function() ns.OutOfCombat(ns.Apply) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs.LEANPAD_SETUP = {
	text = "Set up LeanPad?\n\nThis turns on the gamepad, makes LT and RT act as Shift and Ctrl, clears your controller bindings and binds the controller to Action Bars 1-4. Your current layout is saved first: Undo reset, or /lp undo, brings it back.",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function() ns.OutOfCombat(ns.Apply) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	if ns.db.prompted then return end
	ns.db.prompted = true
	ns.ShowSetup()
end)

-- Play styles: how the body answers the stick in combat, and whom soft targeting looks for, per role.
-- Tanks never show the pack their back; melee and ranged strafe but spin to run when pushed straight back;
-- healers run free, since heals need no facing, and get friendly soft targeting.
ns.PLAYSTYLES = {
	tank = { GamePadFaceMovementMaxAngleCombat = "180", SoftTargetEnemyArc = "1", SoftTargetFriend = "0" },
	melee = { GamePadFaceMovementMaxAngleCombat = "115", SoftTargetEnemyArc = "1", SoftTargetFriend = "0" },
	ranged = { GamePadFaceMovementMaxAngleCombat = "115", SoftTargetEnemyArc = "2", SoftTargetFriend = "0" },
	healer = { GamePadFaceMovementMaxAngleCombat = "0", SoftTargetEnemyArc = "2", SoftTargetFriend = "1", SoftTargetFriendArc = "2" },
}
-- Damage specs the role API can't tell apart: these cast from range. shortcut: hand-kept, add any new ranged spec.
local RANGED_SPECS = {
	[62] = true, [63] = true, [64] = true, [102] = true, [253] = true, [254] = true, [258] = true,
	[262] = true, [265] = true, [266] = true, [267] = true, [1467] = true, [1473] = true,
}

-- The style the current spec plays, or nil before a spec is chosen.
function ns.SpecStyle()
	local spec = GetSpecialization()
	if not spec then return end
	local role = GetSpecializationRole(spec)
	if role == "TANK" then return "tank" end
	if role == "HEALER" then return "healer" end
	return RANGED_SPECS[GetSpecializationInfo(spec)] and "ranged" or "melee"
end

-- Writes the chosen style's CVars; Auto follows the spec. Unset means the player keeps their own values.
-- shortcut: these CVars are not in the setup backup, so Undo setup leaves them; add them if that bites.
function ns.ApplyPlaystyle()
	local style = ns.db.playstyle
	if style == "auto" then style = ns.SpecStyle() end
	local preset = style and ns.PLAYSTYLES[style]
	if not preset then return end
	ns.OutOfCombat(function()
		for cvar, value in pairs(preset) do SetCVar(cvar, value) end
	end)
end

local specWatcher = CreateFrame("Frame")
specWatcher:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
specWatcher:SetScript("OnEvent", function()
	if ns.db.playstyle == "auto" then ns.ApplyPlaystyle() end
end)
EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", ns.ApplyPlaystyle)
