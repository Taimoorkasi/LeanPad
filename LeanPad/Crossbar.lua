local addonName, ns = ...

-- Button centres from a cluster's centre: D-pad and face diamonds on the outside,
-- shoulder, trigger and stick click columns between them.
-- Along the centre line the gaps are even: 32 from the D-pad's right button to the first socket, between the two
-- sockets, and from the second socket to the face diamond.
ns.CROSSBAR = {
	PADDUP = { -163, 46 }, PADDLEFT = { -209, 0 }, PADDRIGHT = { -117, 0 }, PADDDOWN = { -163, -46 },
	PADLSHOULDER = { -39, 54 }, PADLTRIGGER = { -39, 0 }, PADLSTICK = { -39, -54 },
	PADRSHOULDER = { 39, 54 }, PADRTRIGGER = { 39, 0 }, PADRSTICK = { 39, -54 },
	PAD4 = { 163, 46 }, PAD3 = { 117, 0 }, PAD2 = { 209, 0 }, PAD1 = { 163, -46 },
}
-- Between the diamonds each side stacks only the sockets it shows, centred on the diamonds' line: one socket
-- sits level with the D-pad and face buttons, two straddle that line, three fill the column.
ns.CROSSBAR_INNER = { { -39, "PADLSHOULDER", "PADLTRIGGER", "PADLSTICK" }, { 39, "PADRSHOULDER", "PADRTRIGGER", "PADRSTICK" } }
ns.CROSSBAR_CLUSTER_SIZE = { 470, 220 }
-- Cluster centres from the bar's centre, in ns.Layers() order: Base on top, then the first modifier left,
-- the second right and both together below, as WoW: Forever lays out its controller bars.
-- shortcut: only the first four layers get a cluster, so Alt layers are not drawn in the all-layers view; add slots if Alt is used.
ns.CROSSBAR_CLUSTERS = { { 0, 60 }, { -420, 60 }, { 420, 60 }, { 0, -135 } }
ns.CROSSBAR_BUTTON_SIZE = 46
ns.CROSSBAR_BLINK = 0.25 -- seconds a press blink takes to fade
ns.CROSSBAR_IDLE_SCALE = 0.75
ns.CROSSBAR_IDLE_ALPHA = 0.6
ns.CROSSBAR_QUIET_ALPHA = 0.35
ns.CROSSBAR_EMPTY_ALPHA = 0.35

-- One row of groups, centred: LB and the D-pad under the left thumb, the face buttons and RB under the right,
-- the stick clicks and triggers (when they are plain buttons) on the outside.
local function row(step, gap)
	local points, x = {}, 0
	for _, group in ipairs({ { "PADLTRIGGER", "PADLSTICK", "PADLSHOULDER" }, { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN" },
		{ "PAD3", "PAD4", "PAD2", "PAD1" }, { "PADRSHOULDER", "PADRSTICK", "PADRTRIGGER" } }) do
		for _, key in ipairs(group) do
			points[key] = { x, 0 }
			x = x + step
		end
		x = x + gap
	end
	for _, point in pairs(points) do point[1] = point[1] - (x - step - gap) / 2 end
	return points
end

-- Two rows, one per hand, each column one direction: left, up, right, down, with the face buttons in the same
-- order under the D-pad; the bumpers, then the stick clicks, to the right, the triggers to the left.
local function grid(pitch)
	local points = {}
	for c, column in ipairs({ { "PADLTRIGGER", "PADRTRIGGER" }, { "PADDLEFT", "PAD3" }, { "PADDUP", "PAD4" }, { "PADDRIGHT", "PAD2" },
		{ "PADDDOWN", "PAD1" }, { "PADLSHOULDER", "PADRSHOULDER" }, { "PADLSTICK", "PADRSTICK" } }) do
		points[column[1]] = { (c - 4) * pitch, pitch / 2 }
		points[column[2]] = { (c - 4) * pitch, -pitch / 2 }
	end
	return points
end

-- Crossbar styles: where each key's socket sits in a set, and for the all-layers ones where each layer's set sits.
-- The rest show one set that swaps as a layer is held. Square ones draw tiles; a quiet one fades its set until a
-- layer is held. The all-layers styles past the classic one step back by fading only, so in combat the click twins
-- still lie over their sockets.
ns.CROSSBAR_STYLES = {
	active = { points = ns.CROSSBAR, inner = true },
	all = { points = ns.CROSSBAR, inner = true, all = true, clusters = ns.CROSSBAR_CLUSTERS, idleScale = ns.CROSSBAR_IDLE_SCALE },
	strip = { points = row(54, 16), label = { 0, 50 }, size = { 780, 70 } },
	ghost = { points = row(54, 16), label = { 0, 50 }, size = { 780, 70 }, quiet = true },
	grid = { points = grid(48), label = { 0, 64 }, size = { 360, 110 }, square = true },
	rows = { points = row(48, 6), all = true, clusters = { { 0, 72 }, { 0, 24 }, { 0, -24 }, { 0, -72 } }, label = { -392, 0 }, size = { 720, 50 }, square = true },
	stacked = { points = row(54, 16), all = true, clusters = { { 0, -90 }, { 0, -30 }, { 0, 30 }, { 0, 90 } }, label = { -440, 0 }, size = { 780, 56 } },
}

-- Blizzard's circular alpha mask makes icons, sweeps and the rim round without any art of LeanPad's own.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- The rim: a dark ring around the icon.
ns.RIM = { 0.05, 0.05, 0.05, 0.9 }
-- Icon tints: plain, or red while the target is out of the action's range.
ns.IN_RANGE, ns.OUT_OF_RANGE = { 1, 1, 1 }, { 1, 0.25, 0.25 }
-- The proc glow: Blizzard's spell alert gold, and a paler spark.
ns.PROC, ns.PROC_SPARK = { 1, 0.82, 0 }, { 1, 0.95, 0.7 }

-- Cooldowns, charges and usability change often; only these refresh the filled buttons' state.
-- Range changes come from the checks Blizzard's own bar buttons enable for these same slots.
local STATE_EVENTS = {
	ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true, ACTIONBAR_UPDATE_STATE = true, SPELL_UPDATE_CHARGES = true,
	ACTION_RANGE_CHECK_UPDATE = true, SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true,
}
-- Blizzard re-points its bar buttons on these, possibly after LeanPad's handler runs.
local PAGE_EVENTS = {
	ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true, UPDATE_VEHICLE_ACTIONBAR = true,
	UPDATE_OVERRIDE_ACTIONBAR = true, PLAYER_ENTERING_WORLD = true,
}
local LAYOUT_EVENTS = { "UPDATE_BINDINGS", "MODIFIER_STATE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED" }

local bar
local locked = true -- unlocked from the settings page or Edit Mode, the bar, its sets and buttons take the mouse
-- Toggles that make no sense on a hotbar keep their face in the editor only.
local HUD_SKIP = { LEANPAD_TOGGLE_CURSOR = true, TOGGLEAUTORUN = true }
local NOT_BOUND = "Not bound"
local clusters = {}

local function eachButton(fn)
	for _, cluster in ipairs(clusters) do
		for _, button in pairs(cluster.buttons) do fn(button) end
	end
end

-- Each press blinks the key's socket on the set of the layer held now, whatever the button does: an empty slot, a
-- spell on cooldown or a command. A blink ends on its own, since a bound button's release never reaches addons.
local function blink(key)
	local prefix = ns.HeldPrefix()
	for _, cluster in ipairs(clusters) do
		if cluster.frame.prefix == prefix then
			local button = cluster.buttons[key]
			button.Blink:Stop()
			button.Blink:Play()
		end
	end
end

-- On 12.x the client presses bar slots for pad bindings outside Lua, so Blizzard's buttons never show them; the
-- crossbar listens to the pad itself and passes every press on to its binding. Both calls are combat-restricted
-- and keep once made. A child of the bar, it hears nothing while the crossbar is hidden.
local function listen()
	local pad = CreateFrame("Frame", nil, bar)
	pad:EnableGamePadButton(true)
	pad:SetPropagateKeyboardInput(true)
	pad:SetScript("OnGamePadButtonDown", function(_, key)
		if ns.CROSSBAR[key] then blink(key) end
	end)
	bar.Pad = pad
end

-- The proc glow pops in, then breathes and spins until it goes. A lit glow stays as is through state refreshes.
local function setGlow(button, on)
	local glow = button.Glow
	if on and not glow:IsShown() then
		glow:Show()
		glow.Birth:Play()
		glow.Breathe:Play()
		glow.Spin:Play()
	elseif not on and glow:IsShown() then
		glow:Hide()
		glow.Breathe:Stop()
		glow.Spin:Stop()
	end
end

-- One additive layer of the proc glow, from LeanPad's Art/, tinted.
local function glowTexture(glow, name, color)
	local texture = glow:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Art\\" .. name)
	texture:SetVertexColor(unpack(color))
	texture:SetBlendMode("ADD")
	return texture
end

-- Some actions have no cooldown or charge duration object; clear the sweep for those.
local function setDuration(cooldown, duration)
	if duration then
		cooldown:SetCooldownFromDurationObject(duration)
	else
		cooldown:Clear()
	end
end

-- Duration objects let the Cooldown widget animate secret combat cooldowns without addon code reading them.
local function updateState(button)
	local slot = button.slot
	setDuration(button.Cooldown, C_ActionBar.GetActionCooldownDuration(slot))
	setDuration(button.ChargeCooldown, C_ActionBar.GetActionChargeDuration(slot))
	button.Count:SetText(C_ActionBar.GetActionDisplayCount(slot))
	button.Icon:SetDesaturated(not C_ActionBar.IsUsableAction(slot))
	-- Red when the target is out of range; nil, no range to check, stays plain.
	button.Icon:SetVertexColor(unpack(C_ActionBar.IsActionInRange(slot) == false and ns.OUT_OF_RANGE or ns.IN_RANGE))
	-- A proc lights the socket as it does Blizzard's button: asked of the slot's spell, as UpdateSpellAlert does,
	-- so no event payload is compared. A macro's id is its spell's when it casts one.
	local kind, id = GetActionInfo(slot)
	setGlow(button, (kind == "spell" or kind == "macro") and id ~= nil and C_SpellActivationOverlay.IsSpellOverlayed(id))
end

local function faced(action)
	local face = ns.CommandIcon(action)
	return face and not HUD_SKIP[action] and face or nil
end

-- Pad keys worth a button: those firing a Blizzard bar button, or a command with a face, on some layer.
-- Layer buttons never do.
local function actionKeys(layers)
	local used, layerButtons = {}, ns.ModifierKeys()
	for key in pairs(ns.CROSSBAR) do
		for _, layer in ipairs(layers) do
			local action = GetBindingAction(layer.prefix .. key)
			if not layerButtons[key] and (ns.ButtonForCommand(action) or faced(action)) then used[key] = true end
		end
	end
	return used
end

-- A faint empty slot, which is also what a button whose action can't be read keeps showing.
local function clearButton(button)
	button.slot = nil
	button:SetAlpha(ns.CROSSBAR_EMPTY_ALPHA)
	button.Icon:SetDesaturated(false)
	button.Icon:SetVertexColor(unpack(ns.IN_RANGE))
	button.Icon:SetColorTexture(0, 0, 0, 0.5)
	button.Cooldown:Clear()
	button.ChargeCooldown:Clear()
	button.Count:SetText("")
	setGlow(button, false)
end

local function refreshButton(button, key, prefix, hideNumbers)
	clearButton(button)
	ns.SetGlyph(button, key)

	local action = GetBindingAction(prefix .. key)
	local slot = ns.SlotForCommand(action)
	if slot and C_ActionBar.HasAction(slot) then
		button.slot = slot
		button:SetAlpha(1)
		button.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
		button.Cooldown:SetHideCountdownNumbers(hideNumbers)
		updateState(button)
	else
		-- Commands off the bars have no cooldown to show, just their face and badge.
		local face = faced(action)
		if face then
			button:SetAlpha(1)
			ns.ShowIcon(button.Icon, face)
			button.Count:SetText(face.badge or "")
		end
	end
end

-- Drops land on an 8-unit grid and pull level with a neighbour within 12 on one axis, so sets and buttons
-- line up by hand without landing on top of each other. Shift drops exactly where the mouse let go.
local SNAP_GRID, SNAP_PULL = 8, 12
local function snap(x, y, neighbours)
	if IsShiftKeyDown() then return x, y end
	x, y = math.floor(x / SNAP_GRID + 0.5) * SNAP_GRID, math.floor(y / SNAP_GRID + 0.5) * SNAP_GRID
	for _, point in ipairs(neighbours) do
		local dx, dy = math.abs(x - point[1]), math.abs(y - point[2])
		if dx <= SNAP_PULL and dy > SNAP_PULL then
			x = point[1]
		elseif dy <= SNAP_PULL and dx > SNAP_PULL then
			y = point[2]
		end
	end
	return x, y
end

local function style()
	return ns.CROSSBAR_STYLES[ns.db.crossbarStyle] or ns.CROSSBAR_STYLES.active
end

-- Dragged spots and sizes are kept per style; the two classic styles share the original fields.
local function field(name)
	local id = ns.db.crossbarStyle
	return (id == nil or id == "active" or id == "all") and name or name .. "." .. id
end

local function saved(name)
	return ns.db[field(name)] or {}
end

local function clusterPoint(index)
	return saved("clusterPoints")[index] or (style().clusters or ns.CROSSBAR_CLUSTERS)[index]
end

local function socketPoint(key)
	return saved("socketPoints")[key] or style().points[key]
end

local function otherPoints(points, except)
	local list = {}
	for key in pairs(points) do
		if key ~= except then table.insert(list, type(key) == "number" and clusterPoint(key) or socketPoint(key)) end
	end
	return list
end

local function heldLayer(layers, held)
	for _, layer in ipairs(layers) do
		if layer.prefix == held then return layer end
	end
	return { prefix = held, label = "Base" }
end

-- A set sits where the player dragged it, else on its slot; offsets are in the set's own scale, so they are
-- divided by it to keep the set centred there. The wheel's per-set size multiplies the idle shrink.
local function placeCluster(cluster, index, active)
	local s = style()
	local scale = (active and 1 or s.idleScale or 1) * (saved("clusterScales")[index] or 1)
	local point = clusterPoint(index)
	cluster.frame:SetSize(unpack(s.size or ns.CROSSBAR_CLUSTER_SIZE))
	cluster.frame:SetScale(scale)
	cluster.frame:SetAlpha(active and 1 or (s.quiet and ns.CROSSBAR_QUIET_ALPHA or ns.CROSSBAR_IDLE_ALPHA))
	cluster.frame:ClearAllPoints()
	cluster.frame:SetPoint("CENTER", bar, "CENTER", point[1] / scale, point[2] / scale)
	cluster.Label:ClearAllPoints()
	cluster.Label:SetPoint("CENTER", cluster.frame, "CENTER", unpack(s.label or { 0, 92 }))
end

-- Every button sits where the player dragged it, else on its spot; in the classic styles the sockets between the
-- diamonds that were not dragged stack on the diamonds' line.
local function placeSockets(cluster)
	local dragged = saved("socketPoints")
	for key, button in pairs(cluster.buttons) do
		local point = socketPoint(key)
		button:ClearAllPoints()
		button:SetPoint("CENTER", cluster.frame, "CENTER", point[1], point[2])
	end
	if not style().inner then return end
	for _, side in ipairs(ns.CROSSBAR_INNER) do
		local shown = {}
		for i = 2, #side do
			local button = cluster.buttons[side[i]]
			if button:IsShown() and not dragged[side[i]] then table.insert(shown, button) end
		end
		for i, button in ipairs(shown) do
			button:ClearAllPoints()
			button:SetPoint("CENTER", cluster.frame, "CENTER", side[1], ((#shown + 1) / 2 - i) * (ns.CROSSBAR_BUTTON_SIZE + 8))
		end
	end
end

-- Where a dragged frame's centre landed, from its parent's centre, in the parent's units.
local function droppedOffset(frame, parent)
	local x, y = frame:GetCenter()
	local px, py = parent:GetCenter()
	local scale, parentScale = frame:GetEffectiveScale(), parent:GetEffectiveScale()
	return (x * scale - px * parentScale) / parentScale, (y * scale - py * parentScale) / parentScale
end

-- Only an unlocked frame moves, and never while a spell rides the cursor: that drag is a drop.
-- Locked, a drag goes to onLockedDrag, if any.
local function draggable(frame, onDrop, onLockedDrag)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if GetCursorInfo() then return end
		if locked then return onLockedDrag and onLockedDrag(self) end
		self.moving = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = nil
		self:StopMovingOrSizing()
		onDrop(self)
	end)
end

local function remember(name, key, value)
	local f = field(name)
	ns.db[f] = ns.db[f] or {}
	ns.db[f][key] = value
	ns.RefreshCrossbar()
end

-- Mouse clicks. WoW casts from a click only through a secure button, and a frame holding one can't move in combat,
-- while the sets move whenever a layer is held. So each socket gets a secure twin under UIParent, laid over it out of
-- combat. A twin carries every layer as modifier attributes (shift-action* and the like), so a click while holding a
-- trigger fires that layer, as the pad does. Each ends in * for any mouse button: the client looks a click up as
-- shift-action1, *action1, shift-action*, *action*, then plain action, never shift-action. Action Bar 1's slots follow its page through a state driver that wakes
-- on any paging change; its snippet repeats mainBarPage's rule with the restricted API.
-- shortcut: in combat twins stay where the sets were as it began, so in the all-layers view a set that grows while a
-- layer is held leaves them behind, and a crossbar hidden in combat stays clickable until it ends; move them in a
-- snippet if that bites.
local PAGE_STATES = "[vehicleui] v; [possessbar] p; [overridebar] o; [shapeshift] s; [bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; [bonusbar:1] b1; [bonusbar:2] b2; [bonusbar:3] b3; [bonusbar:4] b4; [bonusbar:5] b5; 1"
local PAGE_UPDATE = [[
	local page = GetActionBarPage()
	if HasVehicleActionBar() then
		page = GetVehicleBarIndex()
	elseif HasOverrideActionBar() then
		page = GetOverrideBarIndex()
	elseif HasTempShapeshiftActionBar() then
		page = GetTempShapeshiftBarIndex()
	elseif page == 1 and HasBonusActionBar() then
		page = GetBonusBarIndex()
	end
	for i = 1, self:GetAttribute("count") do
		local twin = self:GetFrameRef("twin" .. i)
		for mod, index in gmatch(twin:GetAttribute("bar1"), "([%a%-%*]*)=(%d+)") do
			twin:SetAttribute(mod .. "action*", tonumber(index) + (page - 1) * 12)
		end
	end
]]
-- Every modifier prefix a click can carry, in SecureButton_GetModifierPrefix's order, and * for any of them.
local CLICK_PREFIXES = { "", "shift-", "ctrl-", "ctrl-shift-", "alt-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-", "*" }
local header, twins, twinsQueued

local function makeTwins()
	header = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
	twins = {}
	for _, cluster in ipairs(clusters) do
		for key, socket in pairs(cluster.buttons) do
			local twin = CreateFrame("Button", nil, header, "SecureActionButtonTemplate")
			twin:RegisterForClicks("AnyUp", "AnyDown") -- it acts on one of them, by ActionButtonUseKeyDown
			twin:RegisterForDrag("LeftButton")
			twin:SetScript("OnEnter", socket.tooltip)
			twin:SetScript("OnLeave", function() GameTooltip:Hide() end)
			twin:SetScript("OnReceiveDrag", socket.drop)
			twin:SetScript("OnDragStart", function() if not GetCursorInfo() then socket.pickup() end end)
			twin:SetAttribute("bar1", "") -- no Action Bar 1 slots until aimed
			twin:Hide()
			table.insert(twins, { twin = twin, socket = socket, cluster = cluster, key = key })
			header:SetFrameRef("twin" .. #twins, twin)
		end
	end
	header:SetAttribute("count", #twins)
	header:SetAttribute("_onstate-page", PAGE_UPDATE)
	RegisterStateDriver(header, "page", PAGE_STATES)
end

-- Points a twin at what its socket's key fires on each layer, keyed by click prefix. Action Bar 1 waits for the
-- page snippet; anything off the bars does nothing, rather than falling back to the plain click's action.
local function aim(twin, key, layers)
	local bar1 = {}
	for _, mod in ipairs(CLICK_PREFIXES) do
		twin:SetAttribute(mod .. "type*", nil)
		twin:SetAttribute(mod .. "action*", nil)
	end
	for mod, prefix in pairs(layers) do
		local action = GetBindingAction(prefix .. key)
		local index = action:match("^ACTIONBUTTON(%d+)$")
		local slot = not index and ns.SlotForCommand(action)
		twin:SetAttribute(mod .. "type*", (index or slot) and "action" or ATTRIBUTE_NOOP)
		if index then table.insert(bar1, mod .. "=" .. index) end
		if slot then twin:SetAttribute(mod .. "action*", slot) end
	end
	twin:SetAttribute("bar1", table.concat(bar1, ";"))
end

-- Lays each shown socket's twin over it and aims it, out of combat; in combat, once it ends. The held-layer view
-- fires the layer the click's modifiers pick; the all-layers view fires each set's own layer, whatever is held.
local function syncTwins()
	if InCombatLockdown() then
		if not twinsQueued then
			twinsQueued = true
			EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
				twinsQueued = nil
				syncTwins()
			end)
		end
		return
	end
	if not header then makeTwins() end
	local on = locked and ns.db.crossbarMouse == true and bar:IsShown()
	local allLayers, uiScale = style().all, UIParent:GetEffectiveScale()
	local byModifiers = {}
	for _, layer in ipairs(ns.Layers()) do byModifiers[layer.prefix:lower()] = layer.prefix end
	for _, entry in ipairs(twins) do
		local socket, twin = entry.socket, entry.twin
		local shown = on and entry.cluster.frame:IsShown() and socket:IsShown()
		twin:SetShown(shown)
		if shown then
			local scale = socket:GetEffectiveScale() / uiScale
			local x, y = socket:GetCenter()
			twin:ClearAllPoints()
			twin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
			twin:SetSize(ns.CROSSBAR_BUTTON_SIZE * scale, ns.CROSSBAR_BUTTON_SIZE * scale)
			twin:SetFrameLevel(socket.Overlay:GetFrameLevel() + 1)
			aim(twin, entry.key, allLayers and { ["*"] = entry.cluster.frame.prefix } or byModifiers)
		end
	end
	header:Execute(PAGE_UPDATE)
end

-- Square styles swap the round masks for square ones, square the sweeps and tuck the glyph into the corner.
local function shape(button, square)
	local mask = square and ns.WHITE or CIRCLE
	button.IconMask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	button.RimMask:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	for _, cooldown in ipairs({ button.Cooldown, button.ChargeCooldown }) do
		cooldown:SetSwipeTexture(mask)
		cooldown:SetUseCircularEdge(not square)
	end
	button.Glyph:ClearAllPoints()
	if square then
		button.Glyph:SetPoint("BOTTOMLEFT", button.Face, "BOTTOMLEFT", 1, 1)
	else
		button.Glyph:SetPoint("BOTTOM", button.Face, "TOP", 0, -6)
	end
end

-- Held-layer styles: one cluster that switches as modifiers are held, labelled with them; a quiet one stays faint
-- until a layer is held. All-layers styles: one cluster per layer, labelled, the held one in front.
-- Each button updates in its own securecallfunction, so one error is reported without stopping the rest.
function ns.RefreshCrossbar()
	local layers = ns.Layers()
	local held = ns.HeldPrefix()
	local s = style()
	local allLayers = s.all
	local hideNumbers = not GetCVarBool("countdownForCooldowns")
	local used = actionKeys(layers)
	for index, cluster in ipairs(clusters) do
		local layer = allLayers and layers[index] or (index == 1 and heldLayer(layers, held)) or nil
		cluster.frame:SetShown(layer ~= nil)
		if layer then
			placeCluster(cluster, index, allLayers and layer.prefix == held or not allLayers and (not s.quiet or held ~= ""))
			cluster.frame.prefix = layer.prefix
			cluster.Label:SetText(layer.prefix ~= "" and layer.label or "")
			for key, button in pairs(cluster.buttons) do
				button:SetShown(used[key] == true)
				shape(button, s.square)
				securecallfunction(refreshButton, button, key, layer.prefix, hideNumbers)
			end
			placeSockets(cluster)
		end
	end
	syncTwins()
end

local function onEvent(_, event)
	if STATE_EVENTS[event] then
		eachButton(function(button)
			if button.slot then securecallfunction(updateState, button) end
		end)
	elseif PAGE_EVENTS[event] then
		RunNextFrame(ns.RefreshCrossbar) -- read Blizzard's buttons once its own handlers have run
	else
		ns.RefreshCrossbar()
	end
end

local function circleMask(parent, size)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetSize(size, size)
	mask:SetPoint("CENTER")
	return mask
end

local function makeCooldown(parent)
	local cooldown = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetSwipeTexture(CIRCLE)
	cooldown:SetUseCircularEdge(true)
	return cooldown
end

-- A round icon with a thin rim and the pad glyph just above it.
function ns.MakeSocket(frameType, parent, size)
	local button = CreateFrame(frameType, nil, parent)
	button:SetSize(size, size)
	-- Everything sits on Face, centred on the button, so a press can shrink it in place.
	local face = CreateFrame("Frame", nil, button)
	face:SetSize(size, size)
	face:SetPoint("CENTER")
	button.Face = face

	-- A slightly larger dark disc behind the icon reads as a thin rim.
	button.Rim = face:CreateTexture(nil, "BACKGROUND")
	button.Rim:SetSize(size + 4, size + 4)
	button.Rim:SetPoint("CENTER")
	button.RimMask = circleMask(face, size + 4)
	button.Rim:AddMaskTexture(button.RimMask)
	button.Rim:SetColorTexture(unpack(ns.RIM))
	button.IconMask = circleMask(face, size)
	button.Icon = face:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:AddMaskTexture(button.IconMask)

	-- The glyph sits on its own frame, which callers raise above anything they add, such as cooldowns.
	button.Overlay = CreateFrame("Frame", nil, face)
	button.Overlay:SetAllPoints()
	button.Glyph = button.Overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	button.Glyph:SetSize(18, 18)
	button.Glyph:SetPoint("BOTTOM", face, "TOP", 0, -6) -- mostly above the icon, so it does not cover the art
	return button
end

-- Shows the pad glyph atlas from the key's binding text, or nothing when the key has no glyph.
function ns.SetGlyph(button, key)
	local glyph = ns.GlyphAtlas(key)
	button.Glyph:SetShown(glyph ~= nil)
	if glyph then button.Glyph:SetAtlas(glyph) end
end

local function makeButton(parent, key)
	local button = ns.MakeSocket("Frame", parent, ns.CROSSBAR_BUTTON_SIZE)
	-- Unlocked, a button can be dragged to a new spot, shared by every set. Locked, with the mouse on, dragging
	-- it takes its action out of the bar slot, as on Blizzard's bars.
	function button.pickup() ns.PickupFromButton(parent.prefix .. key) end
	draggable(button, function(self)
		local x, y = droppedOffset(self, parent)
		remember("socketPoints", key, { snap(x, y, otherPoints(style().points, key)) })
	end, button.pickup)
	-- With the mouse on, a spell dropped on a socket goes into the bar slot its button fires, and hovering tells the action.
	-- The secure twin over a socket hands its tooltip and drops back here.
	function button.drop() ns.PlaceOnButton(parent.prefix .. key) end
	function button.tooltip(owner)
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		if button.slot then
			GameTooltip:SetAction(button.slot)
		else
			GameTooltip:SetText(ns.ActionInfo(parent.prefix .. key) or NOT_BOUND)
		end
		GameTooltip:Show()
	end
	button:SetScript("OnReceiveDrag", button.drop)
	button:SetScript("OnMouseUp", function() if GetCursorInfo() then button.drop() end end)
	button:SetScript("OnEnter", button.tooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button.Cooldown = makeCooldown(button.Face)
	button.ChargeCooldown = makeCooldown(button.Face)
	button.ChargeCooldown:SetDrawSwipe(false)

	-- Flash, glyph and count sit above both cooldowns, which would otherwise cover them.
	local overlay = button.Overlay
	overlay:SetFrameLevel(button.ChargeCooldown:GetFrameLevel() + 1)
	button.Flash = overlay:CreateTexture(nil, "OVERLAY")
	button.Flash:SetAllPoints()
	button.Flash:SetColorTexture(1, 1, 1, 0.6)
	button.Flash:SetBlendMode("ADD")
	button.Flash:AddMaskTexture(button.IconMask)
	button.Flash:SetAlpha(0) -- seen only while a blink plays
	-- A press blinks: the flash fades out, and a faint empty socket shows in full meanwhile. The client runs it.
	local blink = button:CreateAnimationGroup()
	local full = blink:CreateAnimation("Alpha")
	full:SetFromAlpha(1)
	full:SetToAlpha(1)
	full:SetDuration(ns.CROSSBAR_BLINK)
	local fade = blink:CreateAnimation("Alpha")
	fade:SetTarget(button.Flash)
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(ns.CROSSBAR_BLINK)
	button.Blink = blink
	-- A proc lights the round take on Blizzard's square spell alert, in LeanPad's own art: a gold ring that pops in
	-- and breathes, and a spark running round it. The client runs all three animations while it shows.
	local glow = CreateFrame("Frame", nil, overlay)
	glow:SetSize(ns.CROSSBAR_BUTTON_SIZE * 1.6, ns.CROSSBAR_BUTTON_SIZE * 1.6)
	glow:SetPoint("CENTER")
	glow:Hide()
	glow.Ring = glowTexture(glow, "ProcGlow", ns.PROC)
	glow.Spark = glowTexture(glow, "ProcSpark", ns.PROC_SPARK)
	glow.Birth = glow.Ring:CreateAnimationGroup()
	local pop = glow.Birth:CreateAnimation("Scale")
	pop:SetScaleFrom(1.5, 1.5)
	pop:SetScaleTo(1, 1)
	pop:SetDuration(0.25)
	glow.Breathe = glow.Ring:CreateAnimationGroup()
	glow.Breathe:SetLooping("BOUNCE")
	local breathe = glow.Breathe:CreateAnimation("Alpha")
	breathe:SetFromAlpha(1)
	breathe:SetToAlpha(0.55)
	breathe:SetDuration(0.6)
	glow.Spin = glow.Spark:CreateAnimationGroup()
	glow.Spin:SetLooping("REPEAT")
	local spin = glow.Spin:CreateAnimation("Rotation")
	spin:SetDegrees(-360) -- clockwise
	spin:SetDuration(1.2)
	button.Glow = glow
	button.Count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	return button
end

local function makeCluster(index)
	local frame = CreateFrame("Frame", nil, bar)
	frame:SetSize(unpack(ns.CROSSBAR_CLUSTER_SIZE))
	local cluster = { frame = frame, buttons = {} }
	frame.buttons = cluster.buttons
	-- Unlocked, a set can be dragged anywhere on the bar and sized with the wheel, in steps of 5%.
	draggable(frame, function(self)
		local x, y = droppedOffset(self, bar)
		remember("clusterPoints", index, { snap(x, y, otherPoints(style().clusters or ns.CROSSBAR_CLUSTERS, index)) })
	end)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local scale = saved("clusterScales")[index] or 1
		remember("clusterScales", index, math.max(0.5, math.min(2, scale + delta * 0.05)))
	end)
	for key in pairs(ns.CROSSBAR) do cluster.buttons[key] = makeButton(frame, key) end
	cluster.Label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	cluster.Label:SetPoint("CENTER", frame, "CENTER", 0, 92)
	return cluster
end

-- Sets take the mouse only while unlocked; buttons also when the player wants drops and tooltips.
local function applyMouse()
	local buttons = not locked or ns.db.crossbarMouse == true
	for _, cluster in ipairs(clusters) do
		cluster.frame:EnableMouse(not locked)
		cluster.frame:EnableMouseWheel(not locked)
		for _, button in pairs(cluster.buttons) do button:EnableMouse(buttons) end
	end
end

local DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 60 }

local function anchor()
	local point = ns.db.crossbarPoint or DEFAULT_POINT
	bar:ClearAllPoints()
	bar:SetPoint(point[1], UIParent, point[2], point[3], point[4])
end

local function build()
	bar = CreateFrame("Frame", "LeanPadCrossbar", UIParent)
	bar:SetSize(1200, 420)
	anchor()
	bar:SetScale(ns.db.crossbarScale or 1)
	bar:SetAlpha(ns.db.crossbarAlpha or 1)
	for index = 1, #ns.CROSSBAR_CLUSTERS do clusters[index] = makeCluster(index) end
	-- Unlocked from the settings page, the bar takes the mouse and can be dragged; the spot is kept.
	bar:SetClampedToScreen(true)
	draggable(bar, function()
		local point, _, relativePoint, x, y = bar:GetPoint(1)
		ns.db.crossbarPoint = { point, relativePoint, x, y }
	end)
	bar.Outline = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	bar.Outline:SetAllPoints()
	bar.Outline:SetBackdrop({ edgeFile = ns.WHITE, edgeSize = 2 })
	bar.Outline:SetBackdropBorderColor(unpack(ns.COLORS.accent))
	local hint = ns.Text(bar.Outline, 14, ns.COLORS.accent, "CENTER")
	hint:SetPoint("TOP", 0, -8)
	hint:SetText("Drag the bar, a set or a single button; they snap to a grid and line up with neighbours, Shift drags freely. Scroll over a set to size it. Lock it on the settings page.")
	local reset = ns.Button(bar.Outline, "Reset layout", 140, function()
		ns.db.crossbarPoint = nil
		for _, name in ipairs({ "clusterPoints", "clusterScales", "socketPoints" }) do ns.db[field(name)] = nil end
		anchor()
		ns.RefreshCrossbar()
	end)
	reset:SetPoint("TOP", hint, "BOTTOM", 0, -8)
	bar.Outline:Hide()
	applyMouse()
	-- A reload in combat starts hearing the pad once combat ends.
	if InCombatLockdown() then
		EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", listen)
	else
		listen()
	end
	-- Listen only while shown, so a hidden crossbar costs nothing.
	bar:SetScript("OnShow", function()
		for _, event in ipairs(LAYOUT_EVENTS) do bar:RegisterEvent(event) end
		for event in pairs(STATE_EVENTS) do bar:RegisterEvent(event) end
		for event in pairs(PAGE_EVENTS) do bar:RegisterEvent(event) end
		ns.RefreshCrossbar()
		-- First shown during login, when Blizzard may not have pointed its main bar buttons at slots yet.
		RunNextFrame(ns.RefreshCrossbar)
	end)
	bar:SetScript("OnHide", function()
		bar:UnregisterAllEvents()
		syncTwins()
	end)
	bar:SetScript("OnEvent", onEvent)
	bar:Hide()
end

function ns.SetCrossbarShown(shown)
	ns.db.crossbar = shown
	if not bar then build() end
	bar:SetShown(shown)
end

function ns.SetCrossbarStyle(style)
	ns.db.crossbarStyle = style
	if bar and bar:IsShown() then ns.RefreshCrossbar() end
end

function ns.SetCrossbarScale(scale)
	ns.db.crossbarScale = scale
	if bar then bar:SetScale(scale) end
end

function ns.SetCrossbarOpacity(alpha)
	ns.db.crossbarAlpha = alpha
	if bar then bar:SetAlpha(alpha) end
end

-- Locked, the bar ignores the mouse so it never gets in the way of play; unlocking lasts until reload.
function ns.SetCrossbarLocked(lock)
	locked = lock
	if not bar then build() end
	bar:EnableMouse(not locked)
	bar.Outline:SetShown(not locked)
	applyMouse()
	syncTwins()
end

function ns.SetCrossbarMouse(on)
	ns.db.crossbarMouse = on
	if bar then
		applyMouse()
		syncTwins()
	end
end

function ns.CrossbarLocked() return locked end

-- Reads every crossbar setting again, once a profile switch has replaced them.
function ns.ApplyCrossbarSettings()
	ns.SetCrossbarShown(ns.db.crossbar ~= false)
	anchor()
	bar:SetScale(ns.db.crossbarScale or 1)
	bar:SetAlpha(ns.db.crossbarAlpha or 1)
	applyMouse()
	ns.RefreshCrossbar()
end

-- Blizzard's Edit Mode unlocks the crossbar too, so it moves along with the rest of the HUD.
EventRegistry:RegisterCallback("EditMode.Enter", function()
	if ns.db.crossbar ~= false then ns.SetCrossbarLocked(false) end
end)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	if not locked then ns.SetCrossbarLocked(true) end
end)

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	ns.SetCrossbarShown(ns.db.crossbar ~= false)
end)
