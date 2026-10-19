local _, ns = ...

-- Button centres from the bar's centre: D-pad and face diamonds on the outside,
-- shoulder, trigger and stick click columns between them.
ns.CROSSBAR = {
	PADDUP = { -150, 46 }, PADDLEFT = { -196, 0 }, PADDRIGHT = { -104, 0 }, PADDDOWN = { -150, -46 },
	PADLSHOULDER = { -56, 30 }, PADLTRIGGER = { -56, -18 }, PADLSTICK = { -56, -66 },
	PADRSHOULDER = { 56, 30 }, PADRTRIGGER = { 56, -18 }, PADRSTICK = { 56, -66 },
	PAD4 = { 150, 46 }, PAD3 = { 104, 0 }, PAD2 = { 196, 0 }, PAD1 = { 150, -46 },
}
ns.CROSSBAR_BUTTON_SIZE = 44
ns.CROSSBAR_PRESSED_SCALE = 0.88

-- Native round art: Blizzard's circular alpha mask, and the talent tree's node rings.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING, RING_PRESSED = "talents-node-circle-gray", "talents-node-circle-yellow"

-- Cooldowns, charges and usability change often; only these refresh the filled buttons' state.
local STATE_EVENTS = { ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true, ACTIONBAR_UPDATE_STATE = true, SPELL_UPDATE_CHARGES = true }
-- Blizzard re-points its bar buttons on these, possibly after LeanPad's handler runs.
local PAGE_EVENTS = { ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true, PLAYER_ENTERING_WORLD = true }
local LAYOUT_EVENTS = { "UPDATE_BINDINGS", "MODIFIER_STATE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE", "GAME_PAD_ACTIVE_CHANGED" }

local bar
local buttons = {}
local watched = {}

local function setPressed(button, pressed)
	button.Face:SetScale(pressed and ns.CROSSBAR_PRESSED_SCALE or 1)
	button.Ring:SetAtlas(pressed and RING_PRESSED or RING)
end

-- Blizzard's binding handlers push its bar button on press and release it on key up; mirror that.
local function watch(source)
	if watched[source] then return end
	watched[source] = true
	hooksecurefunc(source, "SetButtonState", function(self, state)
		for _, button in pairs(buttons) do
			if button.source == self then setPressed(button, state == "PUSHED") end
		end
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

-- Pad keys worth a button: those firing a Blizzard bar button on some layer, plus the modifiers that switch layers.
local function usedKeys(modifierKeys)
	local used = {}
	for key in pairs(ns.CROSSBAR) do
		used[key] = modifierKeys[key]
		for _, layer in ipairs(ns.Layers()) do
			if ns.ButtonForCommand(GetBindingAction(layer.prefix .. key)) then used[key] = true end
		end
	end
	return used
end

local function refreshButton(button, key, prefix, hideNumbers, heldKeys)
	-- Start empty, so a button whose action can't be read shows as an empty disc.
	button.slot, button.source = nil, nil
	button.Icon:SetDesaturated(false)
	button.Icon:SetColorTexture(0, 0, 0, 0.6)
	button.Cooldown:Clear()
	button.ChargeCooldown:Clear()
	button.Count:SetText("")
	setPressed(button, heldKeys[key])
	local glyph = GetBindingText(key):match("|A:([^:|]+)")
	button.Glyph:SetShown(glyph ~= nil)
	if glyph then button.Glyph:SetAtlas(glyph) end

	local source = ns.ButtonForCommand(GetBindingAction(prefix .. key))
	local slot = source and source.action
	if not (slot and C_ActionBar.HasAction(slot)) then return end
	button.slot, button.source = slot, source
	watch(source)
	button.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
	button.Cooldown:SetHideCountdownNumbers(hideNumbers)
	updateState(button)
end

-- Shows the pad buttons in use with what they fire on the held layer.
-- Each button updates in its own securecallfunction, so one error is reported without stopping the rest.
function ns.RefreshCrossbar()
	local prefix = ns.HeldPrefix()
	local hideNumbers = not GetCVarBool("countdownForCooldowns")
	local heldKeys = ns.HeldModifierKeys()
	local used = usedKeys(ns.ModifierKeys())
	for key, button in pairs(buttons) do
		button:SetShown(used[key] == true)
		securecallfunction(refreshButton, button, key, prefix, hideNumbers, heldKeys)
	end
end

local function onEvent(_, event)
	if STATE_EVENTS[event] then
		for _, button in pairs(buttons) do
			if button.slot then securecallfunction(updateState, button) end
		end
	elseif PAGE_EVENTS[event] then
		RunNextFrame(ns.RefreshCrossbar) -- read Blizzard's buttons once its own handlers have run
	else
		ns.RefreshCrossbar()
	end
end

local function makeCooldown(parent)
	local cooldown = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetSwipeTexture(CIRCLE)
	cooldown:SetUseCircularEdge(true)
	return cooldown
end

local function makeButton(point)
	local size = ns.CROSSBAR_BUTTON_SIZE
	local button = CreateFrame("Frame", nil, bar)
	button:SetSize(size, size)
	button:SetPoint("CENTER", bar, "CENTER", point[1], point[2])
	-- Everything sits on Face, centred on the button, so a press can shrink it in place.
	local face = CreateFrame("Frame", nil, button)
	face:SetSize(size, size)
	face:SetPoint("CENTER")
	button.Face = face

	local mask = face:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints()
	button.Icon = face:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:AddMaskTexture(mask)
	button.Cooldown = makeCooldown(face)
	button.ChargeCooldown = makeCooldown(face)
	button.ChargeCooldown:SetDrawSwipe(false)

	-- Ring, glyph and count sit on their own frame above both cooldowns, which would otherwise cover them.
	local overlay = CreateFrame("Frame", nil, face)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button.ChargeCooldown:GetFrameLevel() + 1)
	button.Ring = overlay:CreateTexture(nil, "OVERLAY")
	button.Ring:SetPoint("CENTER")
	button.Ring:SetSize(size + 8, size + 8)
	button.Glyph = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	button.Glyph:SetSize(18, 18)
	button.Glyph:SetPoint("CENTER", face, "TOP")
	button.Count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	return button
end

local function build()
	bar = CreateFrame("Frame", "LeanPadCrossbar", UIParent)
	bar:SetSize(440, 180)
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
	for key, point in pairs(ns.CROSSBAR) do buttons[key] = makeButton(point) end
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

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	ns.SetCrossbarShown(ns.db.crossbar ~= false)
end)
