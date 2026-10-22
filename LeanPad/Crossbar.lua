local _, ns = ...

-- Button centres from a cluster's centre: D-pad and face diamonds on the outside,
-- shoulder, trigger and stick click columns between them.
ns.CROSSBAR = {
	PADDUP = { -150, 46 }, PADDLEFT = { -196, 0 }, PADDRIGHT = { -104, 0 }, PADDDOWN = { -150, -46 },
	PADLSHOULDER = { -50, 28 }, PADLTRIGGER = { -50, -28 }, PADLSTICK = { -50, -84 },
	PADRSHOULDER = { 50, 28 }, PADRTRIGGER = { 50, -28 }, PADRSTICK = { 50, -84 },
	PAD4 = { 150, 46 }, PAD3 = { 104, 0 }, PAD2 = { 196, 0 }, PAD1 = { 150, -46 },
}
-- Cluster centres from the bar's centre, in ns.Layers() order: Base on top, then the first modifier left,
-- the second right and both together below, as WoW: Forever lays out its controller bars.
-- shortcut: only the first four layers get a cluster, so Alt layers are not drawn in the all-layers view; add slots if Alt is used.
ns.CROSSBAR_CLUSTERS = { { 0, 60 }, { -420, 60 }, { 420, 60 }, { 0, -135 } }
ns.CROSSBAR_BUTTON_SIZE = 46
ns.CROSSBAR_PRESSED_SCALE = 0.88
ns.CROSSBAR_IDLE_SCALE = 0.75
ns.CROSSBAR_IDLE_ALPHA = 0.6
ns.CROSSBAR_EMPTY_ALPHA = 0.35

-- Blizzard's circular alpha mask makes icons, sweeps and the rim round without any art of LeanPad's own.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- Rim colours: dark at rest, gold while pressed or, in the editor, hovered.
ns.RIM, ns.RIM_LIT = { 0.05, 0.05, 0.05, 0.9 }, { 1, 0.82, 0, 1 }

-- Cooldowns, charges and usability change often; only these refresh the filled buttons' state.
local STATE_EVENTS = { ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true, ACTIONBAR_UPDATE_STATE = true, SPELL_UPDATE_CHARGES = true }
-- Blizzard re-points its bar buttons on these, possibly after LeanPad's handler runs.
local PAGE_EVENTS = { ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true, PLAYER_ENTERING_WORLD = true }
local LAYOUT_EVENTS = { "UPDATE_BINDINGS", "MODIFIER_STATE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED" }

local bar
local clusters = {}
local watched = {}

local function eachButton(fn)
	for _, cluster in ipairs(clusters) do
		for _, button in pairs(cluster.buttons) do fn(button) end
	end
end

local function setPressed(button, pressed)
	button.Face:SetScale(pressed and ns.CROSSBAR_PRESSED_SCALE or 1)
	button.Rim:SetColorTexture(unpack(pressed and ns.RIM_LIT or ns.RIM))
	button.Flash:SetShown(pressed)
end

-- Blizzard's binding handlers push its bar button on press and release it on key up; mirror that.
local function watch(source)
	if watched[source] then return end
	watched[source] = true
	hooksecurefunc(source, "SetButtonState", function(self, state)
		eachButton(function(button)
			if button.source == self then setPressed(button, state == "PUSHED") end
		end)
	end)
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
end

-- Pad keys worth a button: those firing a Blizzard bar button on some layer.
local function actionKeys(layers)
	local used = {}
	for key in pairs(ns.CROSSBAR) do
		for _, layer in ipairs(layers) do
			if ns.ButtonForCommand(GetBindingAction(layer.prefix .. key)) then used[key] = true end
		end
	end
	return used
end

local function refreshButton(button, key, prefix, hideNumbers)
	-- Start as a faint empty slot, which is also what a button whose action can't be read keeps showing.
	button.slot, button.source = nil, nil
	button:SetAlpha(ns.CROSSBAR_EMPTY_ALPHA)
	button.Icon:SetDesaturated(false)
	button.Icon:SetColorTexture(0, 0, 0, 0.5)
	button.Cooldown:Clear()
	button.ChargeCooldown:Clear()
	button.Count:SetText("")
	setPressed(button, false)
	ns.SetGlyph(button, key)

	local source = ns.ButtonForCommand(GetBindingAction(prefix .. key))
	local slot = source and source.action
	if not (slot and C_ActionBar.HasAction(slot)) then return end
	button.slot, button.source = slot, source
	watch(source)
	button:SetAlpha(1)
	button.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
	button.Cooldown:SetHideCountdownNumbers(hideNumbers)
	-- Refreshes can land mid-press, e.g. a cast changing its slot; keep a held button looking held.
	setPressed(button, source:GetButtonState() == "PUSHED")
	updateState(button)
end

-- Offsets are in the cluster's own scale, so they are divided by it to keep the cluster centred on its slot.
local function placeCluster(cluster, index, active)
	local scale = active and 1 or ns.CROSSBAR_IDLE_SCALE
	local point = ns.CROSSBAR_CLUSTERS[index]
	cluster.frame:SetScale(scale)
	cluster.frame:SetAlpha(active and 1 or ns.CROSSBAR_IDLE_ALPHA)
	cluster.frame:SetPoint("CENTER", bar, "CENTER", point[1] / scale, point[2] / scale)
end

local function heldLayer(layers, held)
	for _, layer in ipairs(layers) do
		if layer.prefix == held then return layer end
	end
	return { prefix = held, label = "Base" }
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
			cluster.Label:SetText(layer.prefix ~= "" and layer.label or "")
			for key, button in pairs(cluster.buttons) do
				button:SetShown(used[key] == true)
				securecallfunction(refreshButton, button, key, layer.prefix, hideNumbers)
			end
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

local function makeButton(parent, point)
	local button = ns.MakeSocket("Frame", parent, ns.CROSSBAR_BUTTON_SIZE)
	button:SetPoint("CENTER", parent, "CENTER", point[1], point[2])
	button.Cooldown = makeCooldown(button.Face)
	button.ChargeCooldown = makeCooldown(button.Face)
	button.ChargeCooldown:SetDrawSwipe(false)

	-- Flash, glyph and count sit above both cooldowns, which would otherwise cover them.
	local overlay = button.Overlay
	overlay:SetFrameLevel(button.ChargeCooldown:GetFrameLevel() + 1)
	button.Flash = overlay:CreateTexture(nil, "OVERLAY")
	button.Flash:SetAllPoints()
	button.Flash:SetColorTexture(1, 1, 1, 0.45)
	button.Flash:SetBlendMode("ADD")
	button.Flash:AddMaskTexture(button.IconMask)
	button.Flash:Hide()
	button.Count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	return button
end

local function makeCluster()
	local frame = CreateFrame("Frame", nil, bar)
	frame:SetSize(460, 220)
	local cluster = { frame = frame, buttons = {} }
	frame.buttons = cluster.buttons
	for key, point in pairs(ns.CROSSBAR) do cluster.buttons[key] = makeButton(frame, point) end
	cluster.Label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	cluster.Label:SetPoint("CENTER", frame, "CENTER", 0, 92)
	return cluster
end

local function build()
	bar = CreateFrame("Frame", "LeanPadCrossbar", UIParent)
	bar:SetSize(1140, 420)
	local point = ns.db.crossbarPoint or { "BOTTOM", "BOTTOM", 0, 60 }
	bar:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	bar:SetScale(ns.db.crossbarScale or 1)
	for index = 1, #ns.CROSSBAR_CLUSTERS do clusters[index] = makeCluster() end
	-- Unlocked from the settings page, the bar takes the mouse and can be dragged; the spot is kept.
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		local anchor, _, relativePoint, x, y = bar:GetPoint(1)
		ns.db.crossbarPoint = { anchor, relativePoint, x, y }
	end)
	bar.Outline = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	bar.Outline:SetAllPoints()
	bar.Outline:SetBackdrop({ edgeFile = ns.WHITE, edgeSize = 2 })
	bar.Outline:SetBackdropBorderColor(unpack(ns.COLORS.accent))
	local hint = ns.Text(bar.Outline, 14, ns.COLORS.accent, "CENTER")
	hint:SetPoint("TOP", 0, -8)
	hint:SetText("Drag the crossbar, then lock it on the settings page")
	bar.Outline:Hide()
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

-- Locked, the bar ignores the mouse so it never gets in the way of play; unlocking lasts until reload.
local locked = true
function ns.SetCrossbarLocked(lock)
	locked = lock
	if not bar then build() end
	bar:EnableMouse(not locked)
	bar.Outline:SetShown(not locked)
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
