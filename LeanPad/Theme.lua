local _, ns = ...

-- The editor's look: slate panels, one amber accent and Blizzard's Arial Narrow, drawn with colour textures only.
ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.COLORS = {
	bg = { 0.039, 0.051, 0.071 }, panel = { 0.063, 0.082, 0.11 }, raised = { 0.106, 0.141, 0.188 }, hover = { 0.133, 0.176, 0.231 },
	line = { 0.133, 0.188, 0.251 }, edge = { 0.169, 0.216, 0.278 }, leader = { 0.227, 0.29, 0.369 },
	text = { 0.91, 0.933, 0.957 }, text2 = { 0.624, 0.69, 0.753 }, muted = { 0.4, 0.471, 0.541 },
	accent = { 0.965, 0.718, 0.235 }, accentHover = { 1, 0.824, 0.478 }, ink = { 0.102, 0.071, 0 },
}
local C = ns.COLORS
ns.MUTED_HEX = "|cff66788a"

local fonts, fontCount = {}, 0
-- One font object per size and colour, shared by every text that uses it.
function ns.Font(size, color)
	local key = size .. table.concat(color, ",")
	if not fonts[key] then
		fontCount = fontCount + 1
		local font = CreateFont("LeanPadFont" .. fontCount)
		font:SetFont("Fonts\\ARIALN.TTF", size, "")
		font:SetTextColor(unpack(color))
		fonts[key] = font
	end
	return fonts[key]
end

function ns.Text(parent, size, color, justify)
	local text = parent:CreateFontString(nil, "ARTWORK")
	text:SetFontObject(ns.Font(size, color))
	text:SetJustifyH(justify or "LEFT")
	return text
end

function ns.Backdrop(frame, fill, edge)
	frame:SetBackdrop({ bgFile = ns.WHITE, edgeFile = edge and ns.WHITE or nil, edgeSize = 1 })
	frame:SetBackdropColor(unpack(fill))
	if edge then frame:SetBackdropBorderColor(unpack(edge)) end
end

function ns.Panel(parent, fill, edge)
	local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	ns.Backdrop(panel, fill, edge)
	return panel
end

function ns.Rule(parent)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(unpack(C.line))
	rule:SetHeight(1)
	return rule
end

-- A flat button. Primary ones are amber with dark text; the rest are raised slate. Hover lifts the fill and shows
-- the tooltip, if any.
function ns.Button(parent, text, width, onClick, primary, tooltip)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, 32)
	local fill, hover = primary and C.accent or C.raised, primary and C.accentHover or C.hover
	ns.Backdrop(button, fill, primary and C.accent or C.edge)
	button:SetNormalFontObject(ns.Font(13, primary and C.ink or C.text))
	button:SetDisabledFontObject(ns.Font(13, C.muted))
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(unpack(hover))
		if tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropColor(unpack(fill))
		if tooltip then GameTooltip:Hide() end
	end)
	return button
end

-- A flat dropdown: getLabel names the current choice, fill(root) adds the menu's entries.
function ns.Dropdown(parent, width, getLabel, fill)
	local dropdown = ns.Button(parent, "", width, function(self)
		MenuUtil.CreateContextMenu(self, function(_, root) fill(root) end)
	end)
	dropdown:SetHeight(28)
	local chevron = dropdown:CreateTexture(nil, "ARTWORK")
	chevron:SetAtlas("uitools-icon-chevron-down")
	chevron:SetSize(10, 10)
	chevron:SetPoint("RIGHT", -10, 0)
	-- A label too long for the box ends in an ellipsis before the chevron rather than running out of it.
	dropdown.Label = ns.Text(dropdown, 13, C.text)
	dropdown.Label:SetPoint("LEFT", 10, 0)
	dropdown.Label:SetPoint("RIGHT", chevron, "LEFT", -6, 0)
	dropdown.Label:SetWordWrap(false)
	function dropdown:Refresh() self.Label:SetText(getLabel()) end
	dropdown:Refresh()
	return dropdown
end

-- One radio per option, each a { value, label } pair, ticking the one current() returns.
function ns.Radios(root, options, current, set)
	for _, option in ipairs(options) do
		root:CreateRadio(option[2], function(value) return current() == value end, set, option[1])
	end
end

function ns.LabelOf(options, value)
	for _, option in ipairs(options) do
		if option[1] == value then return option[2] end
	end
	return value
end

-- A flat one-line text box. It commits on Enter or when it loses focus; Escape puts back what was there.
function ns.Input(parent, width, getText, onCommit)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, 28)
	ns.Backdrop(box, C.raised, C.edge)
	box:SetFontObject(ns.Font(13, C.text))
	box:SetTextInsets(8, 8, 0, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(6)
	function box:Refresh() self:SetText(getText()) end
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self)
		self:Refresh()
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", function(self) onCommit(self:GetText()) end)
	box:Refresh()
	return box
end

-- A flat checkbox: amber with a check while on.
function ns.Checkbox(parent, isChecked, onToggle)
	local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
	box:SetSize(18, 18)
	ns.Backdrop(box, C.raised, C.edge)
	box.Check = box:CreateTexture(nil, "ARTWORK")
	box.Check:SetAtlas("common-icon-checkmark")
	box.Check:SetSize(12, 12)
	box.Check:SetPoint("CENTER")
	box.Check:SetVertexColor(unpack(C.ink))
	function box:Refresh()
		local on = isChecked()
		self:SetBackdropColor(unpack(on and C.accent or C.raised))
		self.Check:SetShown(on)
	end
	box:SetScript("OnClick", function(self)
		onToggle(not isChecked())
		self:Refresh()
	end)
	box:Refresh()
	return box
end
