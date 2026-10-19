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
	PADLSTICK = "TOGGLEAUTORUN",
	PADRSTICK = "ACTIONBUTTON7",
	PADBACK = "OPENALLBAGS",
	PADFORWARD = "TOGGLEGAMEMENU",
	["SHIFT-PADBACK"] = "TOGGLEWORLDMAP",
	["CTRL-PADBACK"] = "TOGGLECHARACTER0",
	["SHIFT-PADFORWARD"] = "TOGGLESPELLBOOK",
}

-- Each trigger layer puts the D-pad and face buttons, clockwise from the top, onto slots 1-8 of one Blizzard bar,
-- so the bar placed in Edit Mode is that layer's crossbar and Blizzard draws cooldowns, glows and range.
local CROSS = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT", "PAD4", "PAD2", "PAD1", "PAD3" }
local LAYERS = {
	["SHIFT-"] = "MULTIACTIONBAR1BUTTON", -- Action Bar 2
	["CTRL-"] = "MULTIACTIONBAR2BUTTON", -- Action Bar 3
	["CTRL-SHIFT-"] = "MULTIACTIONBAR3BUTTON", -- Action Bar 4
}
for prefix, bar in pairs(LAYERS) do
	for slot, key in ipairs(CROSS) do
		ns.BINDINGS[prefix .. key] = bar .. slot
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

function ns.Apply()
	local db = ns.db
	if not db.backup then -- keep only the pre-LeanPad state, so Restore always gets back to it
		local backup = { cvars = {}, bindings = {} }
		for cvar in pairs(ns.CVARS) do backup.cvars[cvar] = GetCVar(cvar) end
		for key in pairs(ns.BINDINGS) do backup.bindings[key] = GetBindingAction(key) end
		db.backup = backup
	end
	for cvar, value in pairs(ns.CVARS) do SetCVar(cvar, value) end
	for key, action in pairs(ns.BINDINGS) do bind(key, action) end
	SaveBindings(GetCurrentBindingSet())
	print("LeanPad: controller set up. Show Action Bars 2-4 to see the LT, RT and LT+RT layers.")
end

-- shortcut: restores into the current binding set, wrong if the user switched account/character sets since Apply; store the set if that comes up.
function ns.Restore()
	local backup = ns.db.backup
	if not backup then return print("LeanPad: nothing to restore.") end
	for cvar, value in pairs(backup.cvars) do SetCVar(cvar, value) end
	for key, action in pairs(backup.bindings) do bind(key, action) end
	SaveBindings(GetCurrentBindingSet())
	ns.db.backup = nil
	print("LeanPad: previous controller settings and bindings restored.")
end

StaticPopupDialogs.LEANPAD_SETUP = {
	text = "Set up LeanPad?\n\nThis turns on the gamepad, makes LT and RT act as Shift and Ctrl, and binds your controller to Action Bars 1-4. Your current settings are saved so you can restore them from the LeanPad settings.",
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
	StaticPopup_Show("LEANPAD_SETUP")
end)
