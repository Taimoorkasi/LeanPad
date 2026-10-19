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
		assert.same({ PADLTRIGGER = true, PADLSHOULDER = true }, ns.ModifierKeys())
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

	describe("layouts", function()
		it("list every drawn button exactly once, on one side, inside the drawing", function()
			for style, layout in pairs(ns.LAYOUTS) do
				local listed = {}
				for _, side in ipairs({ "left", "right" }) do
					for _, key in ipairs(layout[side]) do
						assert.is_nil(listed[key], style .. " lists " .. key .. " twice")
						listed[key] = true
					end
				end
				for key, point in pairs(layout.positions) do
					assert.is_true(listed[key], style .. " draws " .. key .. " but does not list it")
					assert.is_true(point[1] >= 0 and point[1] <= 360 and point[2] >= 0 and point[2] <= 240, key)
				end
				for key in pairs(listed) do assert.is_table(layout.positions[key], key) end
			end
		end)

		it("puts the D-pad high on PlayStation and low on Xbox", function()
			assert.is_true(ns.LAYOUTS.playstation.positions.PADDUP[2] < ns.LAYOUTS.playstation.positions.PADLSTICK[2])
			assert.is_true(ns.LAYOUTS.xbox.positions.PADDUP[2] > ns.LAYOUTS.xbox.positions.PADLSTICK[2])
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
		local frame

		local function open()
			ns.ToggleController()
			frame = LeanPadControllerFrame
		end

		local function rowFor(key)
			for _, widget in ipairs(w.widgets) do
				if widget.kind == "Button" and rawget(widget, "Name") and widget.key == key then return widget end
			end
		end

		local function glyphFor(key)
			for _, widget in ipairs(w.widgets) do
				if widget.kind == "Button" and rawget(widget, "Text") and widget.key == key then return widget end
			end
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

		it("opens as a closable Blizzard ButtonFrame and toggles closed", function()
			open()
			assert.equal("ButtonFrameTemplate", frame.template)
			assert.is_true(frame.portraitHidden)
			assert.same({ "LeanPadControllerFrame" }, UISpecialFrames)
			assert.is_true(frame:IsShown())
			assert.is_true(frame.events.UPDATE_BINDINGS)
			ns.ToggleController()
			assert.is_false(frame:IsShown())
			assert.same({}, frame.events)
		end)

		it("draws the controller outline with native lines", function()
			open()
			assert.equal(14, #wow.widgets("Line"))
		end)

		it("shows one tab per layer", function()
			open()
			local tabs = wow.widgets("Button", "PanelTabButtonTemplate")
			assert.equal(8, #tabs)
			assert.equal(4, frame.numTabs)
			assert.equal(1, frame.selectedTab)
			assert.equal("text:PADLTRIGGER", tabs[2]:GetText())
			assert.is_true(tabs[2].resized)
			assert.is_true(tabs[4]:IsShown())
			assert.is_false(tabs[5]:IsShown())
		end)

		it("lists each button with its glyph, action, icon, and modifier role", function()
			open()
			local row = rowFor("PAD1")
			assert.equal("text:PAD1", row.Glyph:GetText())
			assert.equal("name:JUMP", row.Name:GetText())
			assert.equal("name:TOGGLEAUTORUN", rowFor("PADLSTICK").Name:GetText())
			assert.equal("|cff808080Not Bound|r", rowFor("PADPADDLE1").Name:GetText())
			assert.equal("|cff808080Not Bound|r |cff808080(modifier)|r", rowFor("PADLTRIGGER").Name:GetText())
		end)

		it("switches layer from the tabs", function()
			open()
			wow.widgets("Button", "PanelTabButtonTemplate")[2]:Fire("OnClick")
			assert.equal(2, frame.selectedTab)
			assert.equal("name:MULTIACTIONBAR1BUTTON1", rowFor("PAD1").Name:GetText())
			assert.equal(135808, rowFor("PAD1").Icon.texture)
		end)

		it("falls back to Base when the selected layer disappears", function()
			open()
			wow.widgets("Button", "PanelTabButtonTemplate")[4]:Fire("OnClick")
			w.cvars.GamePadEmulateCtrl = "none"
			frame:Fire("OnEvent", "CVAR_UPDATE")
			assert.equal(1, frame.selectedTab)
			assert.equal(2, frame.numTabs)
		end)

		it("lays buttons out for the connected controller", function()
			open()
			assert.same({ "CENTER", glyphFor("PADDUP").parent, "TOPLEFT", 135, -135 }, glyphFor("PADDUP").point)
			w.padState = { labelStyle = "Shapes" }
			frame:Fire("OnEvent", "GAME_PAD_CONNECTED")
			assert.same({ "CENTER", glyphFor("PADDUP").parent, "TOPLEFT", 85, -75 }, glyphFor("PADDUP").point)
			assert.equal("PADDUP", rowFor("PADDUP").key)
		end)

		it("opens the assign menu for the clicked button on the current layer", function()
			open()
			wow.widgets("Button", "PanelTabButtonTemplate")[2]:Fire("OnClick")
			glyphFor("PAD1"):Fire("OnClick")
			assert.equal("text:SHIFT-PAD1", w.menu.root.title)
			assert.equal(glyphFor("PAD1"), w.menu.owner)
		end)

		it("drops a dragged action into the clicked button's bar slot", function()
			open()
			wow.widgets("Button", "PanelTabButtonTemplate")[2]:Fire("OnClick")
			w.cursor = "spell"
			rowFor("PAD1"):Fire("OnClick")
			rowFor("PAD1"):Fire("OnReceiveDrag")
			assert.same({ 61, 61 }, w.placed)
			assert.is_nil(w.menu)
		end)

		it("refreshes on binding changes and closes when combat starts", function()
			open()
			w.bindings.PAD1 = "SITORSTAND"
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal("name:SITORSTAND", rowFor("PAD1").Name:GetText())
			frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
			assert.is_false(frame:IsShown())
		end)

		describe("detect", function()
			local function press(key) frame:Fire("OnGamePadButtonDown", key) end

			before_each(function()
				open()
				wow.widgets("Button", "UIPanelButtonTemplate")[1]:Fire("OnClick")
			end)

			it("listens to the pad until a button is pressed", function()
				assert.is_true(frame.gamePadButton)
				assert.matches("Press a button", wow.widgets("FontString")[#wow.widgets("FontString")]:GetText())
			end)

			it("ignores the modifier itself and opens the chord's menu on its layer", function()
				w.held.shift = true
				press("PADLTRIGGER")
				assert.is_true(frame.gamePadButton)
				press("PAD1")
				assert.is_false(frame.gamePadButton)
				assert.is_nil(frame.scripts.OnGamePadButtonDown)
				assert.equal(2, frame.selectedTab)
				assert.equal("text:SHIFT-PAD1", w.menu.root.title)
				assert.equal(glyphFor("PAD1"), w.menu.owner)
			end)

			it("anchors to the window for buttons the drawing doesn't show", function()
				press("PADSYSTEM")
				assert.equal("text:PADSYSTEM", w.menu.root.title)
				assert.equal(frame, w.menu.owner)
			end)

			it("stops listening when the window closes", function()
				frame:Hide()
				assert.is_false(frame.gamePadButton)
			end)
		end)

		it("footer opens the setup dialog and Blizzard's key bindings", function()
			open()
			local buttons = wow.widgets("Button", "UIPanelButtonTemplate")
			assert.equal("Default layout", buttons[2]:GetText())
			buttons[2]:Fire("OnClick")
			assert.same({ "LEANPAD_SETUP" }, w.popups)
			buttons[3]:Fire("OnClick")
			assert.same({ Settings.KEYBINDINGS_CATEGORY_ID }, w.opened)
		end)
	end)
end)
