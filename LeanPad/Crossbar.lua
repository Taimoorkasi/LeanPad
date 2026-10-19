local _, ns = ...

-- Button centres from a cluster's centre: D-pad and face diamonds on the outside,
-- shoulder, trigger and stick click columns between them.
ns.CROSSBAR = {
	PADDUP = { -150, 50 }, PADDLEFT = { -200, 0 }, PADDRIGHT = { -100, 0 }, PADDDOWN = { -150, -50 },
	PADLSHOULDER = { -50, 28 }, PADLTRIGGER = { -50, -28 }, PADLSTICK = { -50, -84 },
	PADRSHOULDER = { 50, 28 }, PADRTRIGGER = { 50, -28 }, PADRSTICK = { 50, -84 },
	PAD4 = { 150, 50 }, PAD3 = { 100, 0 }, PAD2 = { 200, 0 }, PAD1 = { 150, -50 },
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
local RIM, RIM_PRESSED = { 0.05, 0.05, 0.05, 0.9 }, { 1, 0.82, 0, 1 }

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
	button.Rim:SetColorTexture(unpack(pressed and RIM_PRESSED or RIM))
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
	local glyph = GetBindingText(key):match("|A:([^:|]+)")
	button.Glyph:SetShown(glyph ~= nil)
	if glyph then button.Glyph:SetAtlas(glyph) end

	local source = ns.ButtonForCommand(GetBindingAction(prefix .. key))
	local slot = source and source.action
	if not (slot and C_ActionBar.HasAction(slot)) then return end
	button.slot, button.source = slot, source
	watch(source)
	button:SetAlpha(1)
	button.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
	button.Cooldown:SetHideCountdownNumbers(hideNumbers)
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

local function makeButton(parent, point)
	local size = ns.CROSSBAR_BUTTON_SIZE
	local button = CreateFrame("Frame", nil, parent)
	button:SetSize(size, size)
	button:SetPoint("CENTER", parent, "CENTER", point[1], point[2])
	-- Everything sits on Face, centred on the button, so a press can shrink it in place.
	local face = CreateFrame("Frame", nil, button)
	face:SetSize(size, size)
	face:SetPoint("CENTER")
	button.Face = face

	-- A slightly larger dark disc behind the icon reads as a thin rim; it turns gold while pressed.
	button.Rim = face:CreateTexture(nil, "BACKGROUND")
	button.Rim:SetSize(size + 4, size + 4)
	button.Rim:SetPoint("CENTER")
	button.Rim:AddMaskTexture(circleMask(face, size + 4))
	local iconMask = circleMask(face, size)
	button.Icon = face:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:AddMaskTexture(iconMask)
	button.Cooldown = makeCooldown(face)
	button.ChargeCooldown = makeCooldown(face)
	button.ChargeCooldown:SetDrawSwipe(false)

	-- Flash, glyph and count sit on their own frame above both cooldowns, which would otherwise cover them.
	local overlay = CreateFrame("Frame", nil, face)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button.ChargeCooldown:GetFrameLevel() + 1)
	button.Flash = overlay:CreateTexture(nil, "OVERLAY")
	button.Flash:SetAllPoints()
	button.Flash:SetColorTexture(1, 1, 1, 0.45)
	button.Flash:SetBlendMode("ADD")
	button.Flash:AddMaskTexture(iconMask)
	button.Flash:Hide()
	button.Glyph = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	button.Glyph:SetSize(22, 22)
	button.Glyph:SetPoint("CENTER", face, "TOP", 0, 2)
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
	cluster.Label:SetPoint("CENTER", frame, "CENTER", 0, 70)
	return cluster
end

local function build()
	bar = CreateFrame("Frame", "LeanPadCrossbar", UIParent)
	bar:SetSize(1140, 420)
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
	for index = 1, #ns.CROSSBAR_CLUSTERS do clusters[index] = makeCluster() end
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

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	ns.SetCrossbarShown(ns.db.crossbar ~= false)
end)
