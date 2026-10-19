local _, ns = ...

-- Button centres from the bar's centre: D-pad and face diamonds on the outside,
-- shoulder, trigger and stick click columns between them.
ns.CROSSBAR = {
	PADDUP = { -150, 44 }, PADDLEFT = { -194, 0 }, PADDRIGHT = { -106, 0 }, PADDDOWN = { -150, -44 },
	PADLSHOULDER = { -56, 30 }, PADLTRIGGER = { -56, -16 }, PADLSTICK = { -56, -62 },
	PADRSHOULDER = { 56, 30 }, PADRTRIGGER = { 56, -16 }, PADRSTICK = { 56, -62 },
	PAD4 = { 150, 44 }, PAD3 = { 106, 0 }, PAD2 = { 194, 0 }, PAD1 = { 150, -44 },
}
ns.CROSSBAR_BUTTON_SIZE = 40

-- Cooldowns, charges and usability change often; only these refresh the shown buttons' state.
local STATE_EVENTS = { ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true, ACTIONBAR_UPDATE_STATE = true, SPELL_UPDATE_CHARGES = true }
-- Blizzard re-points its bar buttons on these, possibly after LeanPad's handler runs.
local PAGE_EVENTS = { ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true, PLAYER_ENTERING_WORLD = true }
local LAYOUT_EVENTS = { "UPDATE_BINDINGS", "MODIFIER_STATE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "CVAR_UPDATE" }

local bar
local buttons = {}

-- Duration objects let the Cooldown widget animate secret combat cooldowns without addon code reading them.
local function updateState(button)
	local slot = button.slot
	button.Cooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionCooldownDuration(slot))
	button.ChargeCooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionChargeDuration(slot))
	button.Count:SetText(C_ActionBar.GetActionDisplayCount(slot))
	button.Icon:SetDesaturated(not C_ActionBar.IsUsableAction(slot))
end

-- Shows what each button fires on the held layer: only buttons bound to a filled Blizzard bar slot appear.
function ns.RefreshCrossbar()
	local prefix = ns.HeldPrefix()
	local hideNumbers = not GetCVarBool("countdownForCooldowns")
	for key, button in pairs(buttons) do
		local slot = ns.SlotForCommand(GetBindingAction(prefix .. key))
		button.slot = slot and C_ActionBar.HasAction(slot) and slot or nil
		button:SetShown(button.slot ~= nil)
		if button.slot then
			button.Icon:SetTexture(C_ActionBar.GetActionTexture(slot))
			button.Cooldown:SetHideCountdownNumbers(hideNumbers)
			updateState(button)
		end
	end
end

local function onEvent(_, event)
	if STATE_EVENTS[event] then
		for _, button in pairs(buttons) do
			if button.slot then updateState(button) end
		end
	elseif PAGE_EVENTS[event] then
		RunNextFrame(ns.RefreshCrossbar) -- read Blizzard's buttons once its own handlers have run
	else
		ns.RefreshCrossbar()
	end
end

local function makeButton(key, point)
	local size = ns.CROSSBAR_BUTTON_SIZE
	local button = CreateFrame("Frame", nil, bar)
	button:SetSize(size, size)
	button:SetPoint("CENTER", bar, "CENTER", point[1], point[2])
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.Cooldown:SetAllPoints()
	button.ChargeCooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.ChargeCooldown:SetAllPoints()
	button.ChargeCooldown:SetDrawSwipe(false)
	-- Text sits on its own frame above both cooldowns, which would otherwise cover it.
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(button.ChargeCooldown:GetFrameLevel() + 1)
	button.Glyph = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.Glyph:SetPoint("BOTTOM", button, "TOP", 0, -6)
	button.Glyph:SetText(GetBindingText(key, 1))
	button.Count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	return button
end

local function build()
	bar = CreateFrame("Frame", "LeanPadCrossbar", UIParent)
	bar:SetSize(440, 170)
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
	for key, point in pairs(ns.CROSSBAR) do buttons[key] = makeButton(key, point) end
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
