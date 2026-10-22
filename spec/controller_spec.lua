local wow = require("spec.wow")

local function prefixes(layers)
	local list = {}
	for _, layer in ipairs(layers) do table.insert(list, layer.prefix) end
	return list
end

local function setModifiers(w, shift, ctrl, alt)
	w.cvars.GamePadEmulateShift, w.cvars.GamePadEmulateCtrl, w.cvars.GamePadEmulateAlt = shift, ctrl, alt
end

describe("Controller", function()
	local ns, w
	before_each(function() ns, w = wow.boot(nil) end)
	after_each(wow.restore)

	describe("Layers", function()
		it("is just Base when no modifier is emulated", function()
			setModifiers(w, "none", "", nil)
			assert.same({ { prefix = "", label = "Base" } }, ns.Layers())
		end)

		it("gives Base, LT, RT and LT+RT with the preset's trigger modifiers", function()
			setModifiers(w, "PADLTRIGGER", "PADRTRIGGER", "none")
			assert.same({
				{ prefix = "", label = "Base" },
				{ prefix = "SHIFT-", label = "text:PADLTRIGGER" },
				{ prefix = "CTRL-", label = "text:PADRTRIGGER" },
				{ prefix = "CTRL-SHIFT-", label = "text:PADLTRIGGER + text:PADRTRIGGER" },
			}, ns.Layers())
		end)

		it("adds Alt layers, fewest modifiers first, with prefixes in WoW's ALT-CTRL-SHIFT- order", function()
			setModifiers(w, "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER")
			assert.same({ "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-", "ALT-CTRL-SHIFT-" }, prefixes(ns.Layers()))
		end)
	end)

	it("knows which pad keys emulate modifiers", function()
		setModifiers(w, "PADLTRIGGER", "none", "PADLSHOULDER")
		assert.same({ PADLTRIGGER = "SHIFT-", PADLSHOULDER = "ALT-" }, ns.ModifierKeys())
	end)

	it("knows which modifier pad keys are held", function()
		setModifiers(w, "PADLTRIGGER", "PADRTRIGGER", "none")
		assert.same({}, ns.HeldModifierKeys())
		w.held = { ctrl = true, alt = true }
		assert.same({ PADRTRIGGER = true }, ns.HeldModifierKeys())
	end)

	it("finds the Blizzard bar button behind a binding command", function()
		assert.equal(MultiBarBottomLeftButton1, ns.ButtonForCommand("MULTIACTIONBAR1BUTTON1"))
		assert.is_nil(ns.ButtonForCommand("JUMP"))
	end)

	it("reads held modifiers as a binding prefix", function()
		assert.equal("", ns.HeldPrefix())
		w.held = { shift = true, ctrl = true, alt = true }
		assert.equal("ALT-CTRL-SHIFT-", ns.HeldPrefix())
	end)

	it("uses the PlayStation layout only for the Shapes label style", function()
		assert.equal("xbox", ns.ControllerStyle())
		w.padState = { labelStyle = "Letters" }
		assert.equal("xbox", ns.ControllerStyle())
		w.padState = { labelStyle = "Shapes" }
		assert.equal("playstation", ns.ControllerStyle())
	end)

	describe("controller drawings", function()
		it("place the same buttons on both pads, inside each drawing", function()
			local keys = {}
			for key in pairs(ns.PADS.xbox.keys) do keys[key] = true end
			for style, pad in pairs(ns.PADS) do
				local vx, vy, vw, vh = unpack(pad.viewBox)
				local count = 0
				for key, spot in pairs(pad.keys) do
					count = count + 1
					assert.is_true(keys[key], style .. " " .. key)
					assert.is_true(spot[1] - spot[3] / 2 >= vx and spot[1] + spot[3] / 2 <= vx + vw, style .. " " .. key)
					assert.is_true(spot[2] - spot[4] / 2 >= vy and spot[2] + spot[4] / 2 <= vy + vh, style .. " " .. key)
				end
				assert.equal(17, count)
				assert.matches("^Interface\\AddOns\\LeanPad\\Art\\Pad", pad.texture)
			end
		end)

		it("measures a button from the drawing's centre in UI units, y up", function()
			local pad = { viewBox = { 0, 0, 1200, 1000 }, keys = { PAD1 = { 900, 250, 100, 50 } } }
			assert.same({ 75, 62.5, 25, 12.5 }, { ns.KeyGeometry(pad, "PAD1") })
			assert.is_nil(ns.KeyGeometry(pad, "PAD2"))
		end)

		it("names buttons as printed on the connected pad", function()
			assert.equal("A", ns.KeyName("PAD1"))
			assert.equal("LB", ns.KeyName("PADLSHOULDER"))
			w.padState = { labelStyle = "Shapes" }
			assert.equal("Cross", ns.KeyName("PAD1"))
			assert.equal("D-pad Up", ns.KeyName("PADDUP"))
			assert.equal("PADSOCIAL", ns.KeyName("PADSOCIAL"))
		end)

		it("says where an action lives in Blizzard's Action Bars terms", function()
			assert.equal("Action Bar 1, slot 5", ns.ActionPlace("ACTIONBUTTON5"))
			assert.equal("Action Bar 2, slot 1", ns.ActionPlace("MULTIACTIONBAR1BUTTON1"))
			assert.equal("Key binding command", ns.ActionPlace("JUMP"))
		end)
	end)

	describe("actions", function()
		it("finds the action slot a binding command presses, from Blizzard's bar buttons", function()
			assert.equal(61, ns.SlotForCommand("MULTIACTIONBAR1BUTTON1"))
			assert.equal(1, ns.SlotForCommand("ACTIONBUTTON1"))
			assert.is_nil(ns.SlotForCommand("JUMP"))
		end)

		it("describes a binding by command name and slot icon", function()
			assert.is_nil(ns.ActionInfo("PAD1"))
			w.bindings.PAD1 = "JUMP"
			assert.same({ "name:JUMP" }, { ns.ActionInfo("PAD1") })
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			assert.same({ "name:MULTIACTIONBAR1BUTTON1", 135808 }, { ns.ActionInfo("SHIFT-PAD1") })
		end)

		it("assigns and unbinds, saving the current binding set", function()
			ns.Assign("SHIFT-PAD1", "JUMP")
			assert.equal("JUMP", w.bindings["SHIFT-PAD1"])
			ns.Assign("SHIFT-PAD1", nil)
			assert.is_nil(w.bindings["SHIFT-PAD1"])
			assert.same({ Enum.BindingSet.Account, Enum.BindingSet.Account }, w.saved)
		end)

		it("waits for combat to end before assigning", function()
			w.combat = true
			ns.Assign("PAD1", "JUMP")
			assert.is_nil(w.bindings.PAD1)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal("JUMP", w.bindings.PAD1)
		end)

		it("drops the cursor's action into the bar slot the button fires", function()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			ns.PlaceOnButton("SHIFT-PAD1")
			assert.same({ 61 }, w.placed)
		end)

		it("refuses drops on buttons that don't fire a bar slot", function()
			w.bindings.PAD1 = "JUMP"
			ns.PlaceOnButton("PAD1")
			assert.same({}, w.placed)
			assert.matches("action bar slot first", w.printed[1])
		end)

		it("refuses drops in combat", function()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			w.combat = true
			ns.PlaceOnButton("SHIFT-PAD1")
			assert.same({}, w.placed)
			assert.matches("in combat", w.printed[1])
		end)
	end)

	describe("assign menu", function()
		local function menuFor(binding)
			MenuUtil.CreateContextMenu(nil, function(_, root) ns.BuildAssignMenu(root, binding) end)
			return w.menu.root
		end

		it("titles the menu with the button and groups commands by Blizzard's categories", function()
			local root = menuFor("SHIFT-PAD1")
			assert.equal("text:SHIFT-PAD1", root.title)
			local labels = {}
			for _, entry in ipairs(root.entries) do table.insert(labels, entry.text) end
			assert.same({ "Movement", "Action Bar", "BINDING_HEADER_MULTIACTIONBAR", "Other" }, labels)
		end)

		it("skips headers and prefaces, scrolls long lists, and shows slot icons", function()
			local root = menuFor("PAD1")
			assert.same({ "name:JUMP" }, { wow.entry(root, "Movement").entries[1].text })
			assert.equal(1, #wow.entry(root, "Action Bar").entries)
			assert.equal("name:ACTIONBUTTON1", wow.entry(root, "Action Bar").entries[1].text)
			assert.equal("|T135808:16|t name:MULTIACTIONBAR1BUTTON1", wow.entry(root, "BINDING_HEADER_MULTIACTIONBAR").entries[1].text)
			assert.equal(400, wow.entry(root, "Movement").scrollExtent)
		end)

		it("assigns the picked command to the button", function()
			wow.entry(menuFor("SHIFT-PAD1"), "Movement").entries[1].callback()
			assert.equal("JUMP", w.bindings["SHIFT-PAD1"])
		end)

		it("offers Unbind only for bound buttons", function()
			assert.is_nil(wow.entry(menuFor("PAD1"), UNBIND))
			w.bindings.PAD1 = "JUMP"
			wow.entry(menuFor("PAD1"), UNBIND).callback()
			assert.is_nil(w.bindings.PAD1)
		end)
	end)

	describe("editor window", function()
		local frame, card

		local function find(kind, test)
			for _, widget in ipairs(w.widgets) do
				if widget.kind == kind and test(widget) then return widget end
			end
		end

		local function open()
			ns.ToggleController()
			frame = LeanPadControllerFrame
			card = find("Frame", function(widget) return widget.template == "BackdropTemplate" end)
		end

		local function press(key) frame:Fire("OnGamePadButtonDown", key) end
		local function tab(index) return wow.widgets("Button", "PanelTopTabButtonTemplate")[index] end
		local function hitFor(key)
			return find("Button", function(widget) return widget.parent == frame and widget.key == key end)
		end
		local function art() return find("Texture", function(widget) return widget.parent == frame and widget.texCoord ~= nil end) end
		local function ring() return find("Texture", function(widget) return widget.vertexColor ~= nil end) end
		local function line() return wow.widgets("Line")[1] end
		local function button(text)
			return find("Button", function(widget) return widget.text == text end)
		end

		before_each(function()
			ns.Apply()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
		end)

		it("won't open in combat", function()
			w.combat = true
			ns.ToggleController()
			assert.is_nil(LeanPadControllerFrame)
			assert.matches("out of combat", w.printed[#w.printed])
		end)

		it("opens as a closable Blizzard ButtonFrame that takes pad presses only while open", function()
			open()
			assert.equal("ButtonFrameTemplate", frame.template)
			assert.is_true(frame.portraitHidden)
			assert.same({ "LeanPadControllerFrame" }, UISpecialFrames)
			assert.is_true(frame.events.MODIFIER_STATE_CHANGED)
			assert.is_true(frame.gamePadButton)
			ns.ToggleController()
			assert.is_false(frame:IsShown())
			assert.same({}, frame.events)
			assert.is_false(frame.gamePadButton)
			assert.is_nil(frame.scripts.OnGamePadButtonDown)
		end)

		it("shows one tab per layer along the top", function()
			open()
			assert.equal(8, #wow.widgets("Button", "PanelTopTabButtonTemplate"))
			assert.equal(4, frame.numTabs)
			assert.equal(1, frame.selectedTab)
			assert.equal("text:PADLTRIGGER", tab(2):GetText())
			assert.is_false(tab(5):IsShown())
		end)

		it("waits with the connected pad's drawing in the middle and no card", function()
			open()
			assert.same({ "CENTER", frame, "CENTER", 0, 30 }, art().point)
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\PadXbox", art().texture)
			local width = 250 * 1648 / 1150
			local crop = (1 - width / 500) / 2
			assert.same({ crop, 1 - crop, 0, 1 }, art().texCoord)
			assert.is_false(card:IsShown())
			assert.is_false(ring():IsShown())
			w.padState = { labelStyle = "Shapes" }
			frame:Fire("OnEvent", "GAME_PAD_CONNECTED")
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\PadPlayStation", art().texture)
		end)

		it("shows what a pressed button does, with the card on its side of the pad", function()
			open()
			press("PAD1")
			assert.is_true(card:IsShown())
			assert.equal("A", card.Key:GetText())
			assert.equal("Base layer", card.Layer:GetText())
			assert.equal("name:JUMP", card.Name:GetText())
			assert.equal("Key binding command", card.Place:GetText())
			assert.is_false(card.Icon:IsShown())
			assert.is_true(card.Clear.enabled)
			-- A is on the right of the pad, so the card sits right and the drawing moves left.
			local x, y, size = ns.KeyGeometry(ns.PADS.xbox, "PAD1")
			assert.equal(230, card.point[4])
			local artX = 230 - (160 + 40 + 250 * 1648 / 1150 / 2)
			assert.same({ "CENTER", frame, "CENTER", artX, 30 }, art().point)
			assert.same({ "CENTER", frame, "CENTER", artX + x, 30 + y }, ring().point)
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\Ring", ring().texture)
			assert.same({ "CENTER", frame, 70, 30 + y }, line().startPoint)
			assert.same({ "CENTER", frame, artX + x + size / 2 + 6, 30 + y }, line().endPoint)
		end)

		it("puts the card left for left-hand buttons and uses a box ring for D-pad arms", function()
			open()
			press("PADDUP")
			assert.equal(-230, card.point[4])
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\RingSquare", ring().texture)
			assert.equal("name:ACTIONBUTTON5", card.Name:GetText())
		end)

		it("reads the layer from the held modifiers and lists the other layers", function()
			open()
			w.held.shift = true
			press("PADLTRIGGER") -- the modifier alone only switches layer
			assert.is_false(card:IsShown())
			press("PAD1")
			assert.equal(2, frame.selectedTab)
			assert.equal("name:MULTIACTIONBAR1BUTTON1", card.Name:GetText())
			assert.equal("Action Bar 2, slot 1", card.Place:GetText())
			assert.equal(135808, card.Icon.texture)
			assert.equal("Base", card.rows[1].Layer:GetText())
			assert.equal("name:JUMP", card.rows[1].Name:GetText())
			assert.equal("text:PADRTRIGGER", card.rows[2].Layer:GetText())
			assert.equal("name:MULTIACTIONBAR2BUTTON7", card.rows[2].Name:GetText())
			card.rows[1]:Fire("OnClick")
			assert.equal(1, frame.selectedTab)
			assert.equal("name:JUMP", card.Name:GetText())
		end)

		it("follows held modifiers while open", function()
			open()
			w.held.ctrl = true
			frame:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal(3, frame.selectedTab)
			w.held.ctrl = false
			frame:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.equal(1, frame.selectedTab) -- letting go returns to Base
		end)

		it("warns about the cursor's buttons and explains modifiers", function()
			open()
			press("PAD1")
			assert.equal("Also the cursor's left-click.", card.Note:GetText())
			press("PAD2")
			assert.equal("Also the cursor's right-click.", card.Note:GetText())
			press("PADRSTICK")
			assert.equal("Keeps the gamepad cursor reachable.", card.Note:GetText())
			press("PAD3")
			assert.equal("", card.Note:GetText())
			hitFor("PADLTRIGGER"):Fire("OnClick")
			assert.equal("Works as Shift while held, opening its layer.", card.Note:GetText())
		end)

		it("says so when a button is unbound, and can't clear it", function()
			open()
			press("PADPADDLE1")
			assert.equal("|cff808080Not bound|r", card.Name:GetText())
			assert.matches("drop a spell", card.Place:GetText())
			assert.is_false(card.Clear.enabled)
			assert.is_false(ring():IsShown()) -- paddles aren't on the drawing
			assert.equal(230, card.point[4])
		end)

		it("changes, clears, and takes dropped spells for the picked button", function()
			open()
			w.held.shift = true
			press("PAD1")
			button("Change action..."):Fire("OnClick")
			assert.equal("text:SHIFT-PAD1", w.menu.root.title)
			w.cursor = "spell"
			card:Fire("OnReceiveDrag")
			card:Fire("OnMouseUp")
			assert.same({ 61, 61 }, w.placed)
			w.cursor = nil
			card:Fire("OnMouseUp")
			assert.same({ 61, 61 }, w.placed)
			button("Clear"):Fire("OnClick")
			assert.is_nil(w.bindings["SHIFT-PAD1"])
		end)

		it("lets cursor users click and drop on the drawing", function()
			open()
			hitFor("PAD4"):Fire("OnClick")
			assert.equal("Y", card.Key:GetText())
			w.held.shift = true
			w.cursor = "spell"
			hitFor("PAD1"):Fire("OnReceiveDrag")
			assert.equal("A", card.Key:GetText())
			assert.same({ 61 }, w.placed)
		end)

		it("closes on the pad's Menu button and when combat starts, forgetting the pick", function()
			open()
			press("PAD1")
			press("PADFORWARD")
			assert.is_false(frame:IsShown())
			ns.ToggleController()
			assert.is_false(card:IsShown())
			frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
			assert.is_false(frame:IsShown())
		end)

		it("refreshes the card when bindings change", function()
			open()
			press("PAD1")
			w.bindings.PAD1 = "SITORSTAND"
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal("name:SITORSTAND", card.Name:GetText())
		end)

		it("says which binding set changes save to", function()
			open()
			local status = find("FontString", function(widget) return widget.parent == frame and (widget.text or ""):find("Changes save") end)
			assert.equal("Changes save to your account's key bindings", status:GetText())
			w.bindingSet = Enum.BindingSet.Character
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal("Changes save to this character's key bindings", status:GetText())
		end)

		it("footer opens the setup dialog and Blizzard's key bindings", function()
			open()
			button("Reset to default layout..."):Fire("OnClick")
			assert.same({ "LEANPAD_SETUP" }, w.popups)
			button(KEY_BINDINGS):Fire("OnClick")
			assert.same({ Settings.KEYBINDINGS_CATEGORY_ID }, w.opened)
		end)
	end)
end)
