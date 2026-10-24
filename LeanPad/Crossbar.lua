local _, ns = ...

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
ns.CROSSBAR_EMPTY_ALPHA = 0.35

-- Blizzard's circular alpha mask makes icons, sweeps and the rim round without any art of LeanPad's own.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- The rim: a dark ring around the icon.
ns.RIM = { 0.05, 0.05, 0.05, 0.9 }
-- Icon tints: plain, or red while the target is out of the action's range.
ns.IN_RANGE, ns.OUT_OF_RANGE = { 1, 1, 1 }, { 1, 0.25, 0.25 }

-- Cooldowns, charges and usability change often; only these refresh the filled buttons' state.
-- Range changes come from the checks Blizzard's own bar buttons enable for these same slots.
local STATE_EVENTS = {
	ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true, ACTIONBAR_UPDATE_STATE = true, SPELL_UPDATE_CHARGES = true,
	ACTION_RANGE_CHECK_UPDATE = true,
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

local function clusterPoint(index)
	return (ns.db.clusterPoints or {})[index] or ns.CROSSBAR_CLUSTERS[index]
end

local function socketPoint(key)
	return (ns.db.socketPoints or {})[key] or ns.CROSSBAR[key]
end

local function otherPoints(points, except)
	local list = {}
	for key in pairs(points) do
		if key ~= except then table.insert(list, points == ns.CROSSBAR and socketPoint(key) or clusterPoint(key)) end
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
	local scale = (active and 1 or ns.CROSSBAR_IDLE_SCALE) * ((ns.db.clusterScales or {})[index] or 1)
	local point = clusterPoint(index)
	cluster.frame:SetScale(scale)
	cluster.frame:SetAlpha(active and 1 or ns.CROSSBAR_IDLE_ALPHA)
	cluster.frame:ClearAllPoints()
	cluster.frame:SetPoint("CENTER", bar, "CENTER", point[1] / scale, point[2] / scale)
end

-- Every button sits where the player dragged it, else on its spot; the sockets between the diamonds that
-- were not dragged stack on the diamonds' line.
local function placeSockets(cluster)
	local dragged = ns.db.socketPoints or {}
	for key, button in pairs(cluster.buttons) do
		local point = socketPoint(key)
		button:ClearAllPoints()
		button:SetPoint("CENTER", cluster.frame, "CENTER", point[1], point[2])
	end
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

local function remember(field, key, value)
	ns.db[field] = ns.db[field] or {}
	ns.db[field][key] = value
	ns.RefreshCrossbar()
end

-- Held layer only (default): one cluster that switches as modifiers are held, labelled with them.
-- All layers: one cluster per layer, labelled, the held one full size.
-- Each button updates in its own securecallfunction, so one error is reported without stopping the rest.
function ns.RefreshCrossbar()
	local layers = ns.Layers()
	local held = ns.HeldPrefix()
	local allLayers = ns.db.crossbarStyle == "all"
	local hideNumbers = not GetCVarBool("countdownForCooldowns")
	local used = actionKeys(layers)
	for index, cluster in ipairs(clusters) do
		local layer = allLayers and layers[index] or (index == 1 and heldLayer(layers, held)) or nil
		cluster.frame:SetShown(layer ~= nil)
		if layer then
			placeCluster(cluster, index, not allLayers or layer.prefix == held)
			cluster.frame.prefix = layer.prefix
			cluster.Label:SetText(layer.prefix ~= "" and layer.label or "")
			for key, button in pairs(cluster.buttons) do
				button:SetShown(used[key] == true)
				securecallfunction(refreshButton, button, key, layer.prefix, hideNumbers)
			end
			placeSockets(cluster)
		end
	end
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
	button.Rim:AddMaskTexture(circleMask(face, size + 4))
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
	draggable(button, function(self)
		local x, y = droppedOffset(self, parent)
		remember("socketPoints", key, { snap(x, y, otherPoints(ns.CROSSBAR, key)) })
	end, function() ns.PickupFromButton(parent.prefix .. key) end)
	-- With the mouse on, a spell dropped on a socket goes into the bar slot its button fires, and hovering tells the action.
	local function drop() ns.PlaceOnButton(parent.prefix .. key) end
	button:SetScript("OnReceiveDrag", drop)
	button:SetScript("OnMouseUp", function() if GetCursorInfo() then drop() end end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.slot then
			GameTooltip:SetAction(self.slot)
		else
			GameTooltip:SetText(ns.ActionInfo(parent.prefix .. key) or NOT_BOUND)
		end
		GameTooltip:Show()
	end)
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
		remember("clusterPoints", index, { snap(x, y, otherPoints(ns.CROSSBAR_CLUSTERS, index)) })
	end)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local scale = (ns.db.clusterScales or {})[index] or 1
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
		ns.db.crossbarPoint, ns.db.clusterPoints, ns.db.clusterScales, ns.db.socketPoints = nil, nil, nil, nil
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
	bar:SetScript("OnHide", function() bar:UnregisterAllEvents() end)
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
end

function ns.SetCrossbarMouse(on)
	ns.db.crossbarMouse = on
	if bar then applyMouse() end
end

function ns.CrossbarLocked() return locked end

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
