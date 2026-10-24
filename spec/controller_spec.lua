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

	it("draws the PlayStation pad for the Shapes label style, unless the Button labels setting says otherwise", function()
		assert.equal("xbox", ns.ControllerStyle())
		w.padState = { labelStyle = "Letters" }
		assert.equal("xbox", ns.ControllerStyle())
		w.padState = { labelStyle = "Shapes" }
		assert.equal("playstation", ns.ControllerStyle())
		ns.db.padStyle = "xbox"
		assert.equal("xbox", ns.ControllerStyle())
		assert.equal("playstation", ns.DetectedStyle())
		ns.db.padStyle = "auto"
		assert.equal("playstation", ns.ControllerStyle())
	end)

	describe("controller drawings", function()
		it("place the same buttons on both pads, inside each drawing, each in a callout row except the system button", function()
			local keys = {}
			for key in pairs(ns.PADS.xbox.keys) do keys[key] = true end
			for style, pad in pairs(ns.PADS) do
				local vx, vy, vw, vh = unpack(pad.viewBox)
				local count, rows = 0, {}
				for key, spot in pairs(pad.keys) do
					count = count + 1
					assert.is_true(keys[key], style .. " " .. key)
					assert.is_true(spot[1] - spot[3] / 2 >= vx and spot[1] + spot[3] / 2 <= vx + vw, style .. " " .. key)
					assert.is_true(spot[2] - spot[4] / 2 >= vy and spot[2] + spot[4] / 2 <= vy + vh, style .. " " .. key)
					if key == "PADSYSTEM" then
						assert.is_nil(spot[5])
					else
						local slot = spot[5] .. spot[6]
						assert.is_nil(rows[slot], style .. " " .. slot .. " used twice")
						rows[slot] = key
						assert.is_true((spot[5] == "L" or spot[5] == "R") and spot[6] >= 1 and spot[6] <= 8, style .. " " .. key)
					end
				end
				assert.equal(17, count)
				assert.matches("^Interface\\AddOns\\LeanPad\\Art\\Pad", pad.texture)
			end
		end)

		it("measures a button from the drawing's centre in UI units, y up", function()
			local pad = { viewBox = { 0, 0, 1200, 1000 }, keys = { PAD1 = { 900, 250, 100, 50 } } }
			assert.same({ 90, 75, 30, 15 }, { ns.KeyGeometry(pad, "PAD1") })
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

		it("puts the glyph from Blizzard's binding text before or after a label, or leaves it out", function()
			assert.equal("A", ns.Glyphed("PAD1", "A", 18))
			w.glyphs.PAD1 = "|A:Gamepad_Ltr_A_64:0:0|a"
			assert.equal("|A:Gamepad_Ltr_A_64:18:18|a Jump", ns.Glyphed("PAD1", "Jump", 18))
			assert.equal("Jump |A:Gamepad_Ltr_A_64:18:18|a", ns.Glyphed("PAD1", "Jump", 18, true))
			assert.same({ { "none", NONE }, { "PAD1", "|A:Gamepad_Ltr_A_64:16:16|a A" }, { "PAD2", "B" } }, ns.KeyOptions({ "none", "PAD1", "PAD2" }))
		end)

		it("says where an action lives in Blizzard's Action Bars terms", function()
			assert.equal("Action Bar 1, slot 5", ns.ActionPlace("ACTIONBUTTON5"))
			assert.equal("Action Bar 2, slot 1", ns.ActionPlace("MULTIACTIONBAR1BUTTON1"))
			assert.equal("Key binding command", ns.ActionPlace("JUMP"))
		end)

		it("knows which turned-off bars the pad fires, and warns in chat once per change", function()
			assert.is_nil(ns.BarOff("MULTIACTIONBAR2BUTTON1"))
			assert.is_nil(ns.BarOff("ACTIONBUTTON1")) -- Action Bar 1 can't be turned off
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			w.bindings["CTRL-PAD2"] = "MULTIACTIONBAR3BUTTON6"
			w.bindings["PAD3"] = "MULTIACTIONBAR3BUTTON1"
			w.barsShown[1], w.barsShown[3] = false, false
			w.cvars.GamePadEmulateShift, w.cvars.GamePadEmulateCtrl = "PADLTRIGGER", "PADRTRIGGER"
			assert.equal(4, ns.BarOff("MULTIACTIONBAR3BUTTON1"))
			assert.same({ 2, 4 }, ns.OffBars())

			wow.fire("SETTINGS_LOADED")
			local warning = "LeanPad: controller buttons bound to turned-off action bars do nothing (Action Bar 2, 4). Turn them on in Options > Gameplay > Action Bars."
			assert.equal(warning, w.printed[#w.printed])
			local count = #w.printed
			wow.trigger("ActionBarShownSettingUpdated") -- nothing new to say
			assert.equal(count, #w.printed)
			w.barsShown[1], w.barsShown[3] = true, true
			wow.trigger("ActionBarShownSettingUpdated")
			assert.equal(count, #w.printed)
			w.barsShown[3] = false
			wow.trigger("ActionBarShownSettingUpdated")
			assert.equal((warning:gsub("Bar 2, 4", "Bar 4")), w.printed[#w.printed])
		end)
	end)

	describe("actions", function()
		it("finds the action slot a binding command presses, from Blizzard's bar buttons", function()
			assert.equal(61, ns.SlotForCommand("MULTIACTIONBAR1BUTTON1"))
			assert.equal(1, ns.SlotForCommand("ACTIONBUTTON1"))
			assert.is_nil(ns.SlotForCommand("JUMP"))
		end)

		it("pages Action Bar 1 by the game's own state, never by Blizzard's possibly stale button", function()
			ActionButton1.action = 97 -- left on Bear's page by a bar addon that took the bar over
			assert.equal(1, ns.SlotForCommand("ACTIONBUTTON1"))
			w.bar.bonus = 7 -- Cat Form's bar, used while on page 1
			assert.equal(73, ns.SlotForCommand("ACTIONBUTTON1"))
			assert.equal(84, ns.SlotForCommand("ACTIONBUTTON12"))
			w.bar.page = 2 -- a page picked by hand wins over the form
			assert.equal(13, ns.SlotForCommand("ACTIONBUTTON1"))
			w.bar.temp = 14
			assert.equal(157, ns.SlotForCommand("ACTIONBUTTON1"))
			w.bar.override = 18
			assert.equal(205, ns.SlotForCommand("ACTIONBUTTON1"))
			w.bar.vehicle = 12
			assert.equal(133, ns.SlotForCommand("ACTIONBUTTON1"))
			assert.equal(61, ns.SlotForCommand("MULTIACTIONBAR1BUTTON1")) -- Bars 2-8 never page
		end)

		it("describes a binding by what its slot holds, with the slot's icon", function()
			assert.is_nil(ns.ActionInfo("PAD1"))
			w.bindings.PAD1 = "JUMP"
			assert.same({ "name:JUMP" }, { ns.ActionInfo("PAD1") })
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			assert.same({ "spell:1953", 135808 }, { ns.ActionInfo("SHIFT-PAD1") })
			w.actions[61] = { texture = 1, kind = "item", id = 6948 }
			assert.same({ "item:6948", 1 }, { ns.ActionInfo("SHIFT-PAD1") })
			w.actions[61] = { texture = 2, kind = "macro", id = 3, text = "Mount up" }
			assert.same({ "Mount up", 2 }, { ns.ActionInfo("SHIFT-PAD1") })
			w.actions[61] = { texture = 3, kind = "flyout", id = 1 }
			assert.same({ "name:MULTIACTIONBAR1BUTTON1", 3 }, { ns.ActionInfo("SHIFT-PAD1") })
			w.bindings.PAD2 = "ACTIONBUTTON1" -- slot 1 holds nothing
			assert.same({ "|cff66788aEmpty slot|r" }, { ns.ActionInfo("PAD2") })
		end)

		it("gives commands off the bars a face: LeanPad's own icons, Blizzard's atlases for its panels, badges for next, previous and party", function()
			local art = "Interface\\AddOns\\LeanPad\\Art\\"
			assert.same({ texture = art .. "IconTargetEnemy", badge = "|A:common-icon-forwardarrow:12:12|a" }, ns.CommandIcon("TARGETNEARESTENEMY"))
			assert.same({ texture = art .. "IconTargetEnemy", badge = "|A:common-icon-backarrow:12:12|a" }, ns.CommandIcon("TARGETPREVIOUSENEMY"))
			assert.same({ texture = art .. "IconTargetFriend", badge = "3" }, ns.CommandIcon("TARGETPARTYMEMBER3"))
			assert.same({ texture = art .. "IconJump" }, ns.CommandIcon("JUMP"))
			assert.same({ atlas = "UI-HUD-MicroMenu-SpecTalents-Up" }, ns.CommandIcon("TOGGLETALENTS"))
			assert.is_nil(ns.CommandIcon("SITORSTAND"))
			assert.is_nil(ns.CommandIcon(""))
			local texture = UIParent:CreateTexture()
			ns.ShowIcon(texture, ns.CommandIcon("JUMP"))
			assert.equal(art .. "IconJump", texture.texture)
			ns.ShowIcon(texture, ns.CommandIcon("TOGGLETALENTS"))
			assert.equal("UI-HUD-MicroMenu-SpecTalents-Up", texture.atlas)
		end)

		it("assigns and unbinds, saving the current binding set", function()
			ns.Assign("SHIFT-PAD1", "JUMP")
			assert.equal("JUMP", w.bindings["SHIFT-PAD1"])
			ns.Assign("SHIFT-PAD1", nil)
			assert.is_nil(w.bindings["SHIFT-PAD1"])
			assert.same({ Enum.BindingSet.Account, Enum.BindingSet.Account }, w.saved)
		end)

		it("waits for combat to end before assigning or writing a CVar", function()
			w.combat = true
			ns.Assign("PAD1", "JUMP")
			ns.WriteCVar("GamePadEmulateShift", "PADLSHOULDER")
			assert.is_nil(w.bindings.PAD1)
			assert.is_nil(w.cvars.GamePadEmulateShift)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal("JUMP", w.bindings.PAD1)
			assert.equal("PADLSHOULDER", w.cvars.GamePadEmulateShift)
		end)

		it("drops the cursor's action into the bar slot the button fires", function()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			ns.PlaceOnButton("SHIFT-PAD1")
			assert.same({ 61 }, w.placed)
		end)

		it("finds a dropped-on button a free slot on its layer's bar, ignoring keyboard keys on that slot", function()
			w.bindings.PAD1 = "JUMP"
			w.bindings["1"] = "ACTIONBUTTON1" -- the keyboard's own key for slot 1 leaves it free for a pad button
			ns.PlaceOnButton("PAD1")
			assert.equal("ACTIONBUTTON1", w.bindings.PAD1)
			assert.same({ 1 }, w.placed)
		end)

		it("refuses drops when the layer's bar has no slot left for the button", function()
			w.bindings.PAD1 = "JUMP"
			w.bindings.PAD3 = "ACTIONBUTTON1" -- another pad button fires slot 1, and slots 2-12 hold actions
			for slot = 2, 12 do w.actions[slot] = { texture = slot } end
			ns.PlaceOnButton("PAD1")
			assert.same({}, w.placed)
			assert.equal("JUMP", w.bindings.PAD1)
			assert.matches("Action Bar 1 has no free slot left", w.printed[1])
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

		local function labels(description)
			local list = {}
			for _, entry in ipairs(description.entries) do table.insert(list, entry.text) end
			return list
		end

		it("titles the menu with the button; spells and macros first, then bar slots and commands by Blizzard's categories", function()
			local root = menuFor("SHIFT-PAD1")
			assert.equal("text:SHIFT-PAD1", root.title)
			assert.same({ "Spells", "Macros", "Bar slots", "Commands" }, labels(root))
			assert.same({ "Action Bar", "BINDING_HEADER_MULTIACTIONBAR" }, labels(wow.entry(root, "Bar slots")))
			assert.same({ "Movement", "Other" }, labels(wow.entry(root, "Commands")))
		end)

		it("lists the spellbook by tab for this spec, castable spells only, with icons, and both kinds of macro", function()
			local root = menuFor("PAD1")
			local spells = wow.entry(root, "Spells")
			assert.same({ "|T1:16|t General", "|T2:16|t Retribution" }, labels(spells))
			assert.same({ "|T135896:16|t Divine Shield" }, labels(spells.entries[1]))
			assert.same({ "|T135959:16|t Judgment" }, labels(spells.entries[2]))
			assert.equal(400, spells.entries[1].scrollExtent)
			assert.same({ "|T9:16|t Mount up", "|T10:16|t Focus" }, labels(wow.entry(root, "Macros")))
		end)

		it("skips headers and prefaces, scrolls long lists, and shows slot icons", function()
			local root = menuFor("PAD1")
			local commands, slots = wow.entry(root, "Commands"), wow.entry(root, "Bar slots")
			assert.same({ "name:JUMP" }, { wow.entry(commands, "Movement").entries[1].text })
			assert.equal(1, #wow.entry(slots, "Action Bar").entries)
			assert.equal("name:ACTIONBUTTON1", wow.entry(slots, "Action Bar").entries[1].text)
			assert.equal("|T135808:16|t name:MULTIACTIONBAR1BUTTON1", wow.entry(slots, "BINDING_HEADER_MULTIACTIONBAR").entries[1].text)
			assert.equal(400, wow.entry(commands, "Movement").scrollExtent)
		end)

		it("assigns the picked command to the button", function()
			wow.entry(wow.entry(menuFor("SHIFT-PAD1"), "Commands"), "Movement").entries[1].callback()
			assert.equal("JUMP", w.bindings["SHIFT-PAD1"])
		end)

		it("puts a picked spell into the slot the button already fires, dropping what was there", function()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			wow.entry(menuFor("SHIFT-PAD1"), "Spells").entries[1].entries[1].callback()
			assert.same({ { "spell", 1, Enum.SpellBookSpellBank.Player } }, w.pickups)
			assert.same({ 61 }, w.placed)
			assert.equal(2, w.cleared) -- once before the pickup, once after the drop
			assert.is_nil(w.cursor)
		end)

		it("binds a button with no slot to the first free slot of its layer's bar, then places", function()
			_G.ActionButton2 = { bindingAction = "ACTIONBUTTON2", action = 2 } -- busted sandboxes spec globals; the addon reads _G
			w.bindings.PAD3 = "ACTIONBUTTON1" -- slot 1 is X's
			w.bindings["2"] = "ACTIONBUTTON2" -- a keyboard key on slot 2 doesn't take it
			w.bindings.PAD2 = "INTERACTTARGET"
			wow.entry(menuFor("PAD2"), "Macros").entries[2].callback() -- the character macro, numbered after the account's 120
			assert.equal("ACTIONBUTTON2", w.bindings.PAD2)
			assert.equal(Enum.BindingSet.Account, w.saved[#w.saved])
			assert.same({ { "macro", 121 } }, w.pickups)
			assert.same({ 2 }, w.placed)
			_G.ActionButton2 = nil
		end)

		it("says so when the layer's bar has no free slot, or the layer no bar", function()
			w.bindings.PAD3 = "ACTIONBUTTON1"
			for slot = 2, 12 do w.actions[slot] = { texture = slot } end
			w.bindings.PAD2 = "INTERACTTARGET"
			ns.PutSpell("PAD2", 1)
			assert.same({}, w.placed)
			assert.equal("INTERACTTARGET", w.bindings.PAD2)
			assert.equal("LeanPad: Action Bar 1 has no free slot left; clear one or bind the button to a slot by hand.", w.printed[#w.printed])
			ns.PutSpell("ALT-PAD1", 1)
			assert.matches("no bar of its own", w.printed[#w.printed])
		end)

		it("waits for combat to end before placing", function()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			w.combat = true
			ns.PutSpell("SHIFT-PAD1", 3)
			assert.same({}, w.placed)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.same({ 61 }, w.placed)
		end)

		it("offers Unbind only for bound buttons", function()
			assert.is_nil(wow.entry(menuFor("PAD1"), UNBIND))
			w.bindings.PAD1 = "JUMP"
			wow.entry(menuFor("PAD1"), UNBIND).callback()
			assert.is_nil(w.bindings.PAD1)
		end)
	end)

	describe("editor window", function()
		local frame, editor, strip
		local LT = "|A:Gamepad_Ltr_LTrigger_64:18:18|a"
		local LT_RAW = "|A:Gamepad_Ltr_LTrigger_64:0:0|a" -- layer labels are Blizzard's binding text as is

		local function find(kind, test)
			for _, widget in ipairs(w.widgets) do
				if widget.kind == kind and test(widget) then return widget end
			end
		end

		local function open()
			ns.ToggleController()
			frame = LeanPadControllerFrame
			editor = frame.Editor
			strip = editor.Strip
		end

		local function press(key) frame:Fire("OnGamePadButtonDown", key) end
		local function tab(index) return editor.Tabs[index] end
		local function callout(key) return editor.Callouts[key] end
		local function button(text)
			return find("Button", function(widget) return widget.text == text and (widget.parent == editor or widget.parent == strip) end)
		end
		local function labels(description)
			local list = {}
			for _, entry in ipairs(description.entries) do table.insert(list, entry.text) end
			return list
		end

		before_each(function()
			ns.Apply()
			w.bindings["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1"
			w.padState = { labelStyle = "Letters", name = "Xbox Wireless Controller" }
			w.power = 3
			w.glyphs.PADLTRIGGER = "|A:Gamepad_Ltr_LTrigger_64:0:0|a"
		end)

		it("won't open in combat", function()
			w.combat = true
			ns.ToggleController()
			assert.is_nil(LeanPadControllerFrame)
			assert.matches("out of combat", w.printed[#w.printed])
		end)

		it("opens as a flat, closable window that takes pad presses only while open", function()
			open()
			assert.equal("BackdropTemplate", frame.template)
			assert.same(ns.COLORS.bg, frame.backdropColor)
			assert.same({ "LeanPadControllerFrame" }, UISpecialFrames)
			assert.is_true(frame.events.MODIFIER_STATE_CHANGED)
			assert.is_true(frame.events.GAME_PAD_POWER_CHANGED)
			assert.is_true(frame.gamePadButton)
			ns.ToggleController()
			assert.is_false(frame:IsShown())
			assert.same({}, frame.events)
			assert.is_false(frame.gamePadButton)
			assert.is_nil(frame.scripts.OnGamePadButtonDown)
		end)

		it("shows one flat tab per layer, underlining the current one", function()
			open()
			assert.equal(8, #editor.Tabs)
			assert.is_true(tab(1).Underline:IsShown())
			assert.is_false(tab(2).Underline:IsShown())
			assert.equal(LT_RAW, tab(2):GetText())
			assert.same({ "TOPLEFT", editor, "TOPLEFT", 80, -36 }, tab(2).point)
			assert.is_false(tab(5):IsShown())
			tab(3):Fire("OnClick")
			assert.is_true(tab(3).Underline:IsShown())
			assert.is_false(tab(1).Underline:IsShown())
		end)

		it("names the pad, its battery and the layer buttons above the drawing", function()
			open()
			assert.equal("Xbox Wireless Controller · battery high", editor.Toolbar.Device:GetText())
			assert.equal(LT .. " Shift   Ctrl", editor.Toolbar.Modifiers:GetText())
			w.padState, w.power = nil, 5
			frame:Fire("OnEvent", "GAME_PAD_DISCONNECTED")
			assert.equal("No controller detected", editor.Toolbar.Device:GetText())
			w.padState = { labelStyle = "Letters", name = "Pad" }
			frame:Fire("OnEvent", "GAME_PAD_CONNECTED")
			assert.equal("Pad", editor.Toolbar.Device:GetText())
			setModifiers(w, "none", "none", "none")
			frame:Fire("OnEvent", "CVAR_UPDATE")
			assert.equal("none", editor.Toolbar.Modifiers:GetText())
		end)

		it("changes the layer buttons from a menu beside them", function()
			open()
			button("Change..."):Fire("OnClick")
			local root = w.menu.root
			assert.same({ "Shift button", "Ctrl button", "Alt button" }, labels(root))
			local shift = root.entries[1]
			assert.equal(NONE, shift.entries[1].text)
			assert.is_false(shift.entries[1].selected())
			assert.is_true(wow.entry(shift, "|A:Gamepad_Ltr_LTrigger_64:16:16|a LT").selected())
			wow.entry(shift, "LB").callback()
			assert.equal("PADLSHOULDER", w.cvars.GamePadEmulateShift)
			-- LB only opens its layer now, so its own bindings went.
			assert.is_nil(w.bindings.PADLSHOULDER)
			assert.equal("LeanPad: LB is now a layer button, so its own bindings were cleared.", w.printed[#w.printed])
			assert.equal(Enum.BindingSet.Account, w.saved[#w.saved])
			frame:Fire("OnEvent", "CVAR_UPDATE")
			assert.equal("Opens the LB layer", callout("PADLSHOULDER").text:GetText())
		end)

		it("turning a layer button off clears nothing", function()
			open()
			ns.SetLayerButton("GamePadEmulateCtrl", "none")
			assert.equal("none", w.cvars.GamePadEmulateCtrl)
			assert.equal("ACTIONBUTTON4", w.bindings.PADRSHOULDER)
			assert.equal("ACTIONBUTTON3", w.bindings.PADLSHOULDER)
		end)

		it("draws the pad fixed in the middle, with a callout and a curved leader for every bound button", function()
			open()
			assert.same({ "CENTER", editor, "TOPLEFT", 460, -298 }, editor.Art.point)
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\PadXbox", editor.Art.texture)
			local width = 300 * 1648 / 1150
			local crop = (1 - width / 600) / 2
			assert.same({ crop, 1 - crop, 0, 1 }, editor.Art.texCoord)
			-- A is bound to Jump and sits in the right column's seventh row.
			local a = callout("PAD1")
			assert.is_true(a.text:IsShown())
			assert.equal("name:JUMP", a.text:GetText())
			assert.same({ "LEFT", editor, "TOPLEFT", 704, -378 }, a.text.point)
			assert.equal(ns.Font(13, ns.COLORS.text), a.text.font)
			assert.equal(6, #a.lines)
			assert.same({ "TOPLEFT", editor, 698, -378 }, a.lines[1].startPoint)
			assert.same({ ns.COLORS.leader[1], ns.COLORS.leader[2], ns.COLORS.leader[3], 1 }, a.lines[1].color)
			-- The leader stops short of the button, on the straight line from the label to its centre.
			local kx, ky, kw = ns.KeyGeometry(ns.PADS.xbox, "PAD1")
			local ex, ey = 460 + kx, 298 - ky
			local dx, dy = ex - 698, ey - 378
			local len = math.sqrt(dx * dx + dy * dy)
			local r = kw / 2 + 6
			assert.near(ex - dx / len * r, a.lines[6].endPoint[3], 0.001)
			assert.near(-(ey - dy / len * r), a.lines[6].endPoint[4], 0.001)
			assert.same(a.lines[1].endPoint, { "TOPLEFT", editor, a.lines[2].startPoint[3], a.lines[2].startPoint[4] })
			-- D-pad Up reads right-aligned in the left column, glyph nearest the pad.
			w.glyphs.PADDUP = "|A:Gamepad_Gen_Up_64:0:0|a"
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			local up = callout("PADDUP")
			assert.equal("|cff66788aEmpty slot|r |A:Gamepad_Gen_Up_64:18:18|a", up.text:GetText())
			assert.same({ "RIGHT", editor, "TOPLEFT", 216, -314 }, up.text.point)
			assert.same({ "TOPLEFT", editor, 222, -314 }, up.lines[1].startPoint)
			-- A layer button says so; the system button and unbound buttons get nothing.
			assert.equal("Opens the LT layer " .. LT, callout("PADLTRIGGER").text:GetText())
			assert.is_false(callout("PADSYSTEM").text:IsShown())
			w.bindings.PADBACK = nil
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.is_false(callout("PADBACK").text:IsShown())
			assert.is_false(callout("PADBACK").lines[1]:IsShown())
		end)

		it("waits with the prompt under the pad and no strip", function()
			open()
			assert.is_false(strip:IsShown())
			assert.is_true(editor.Prompt:IsShown())
			assert.is_false(editor.Ring:IsShown())
			assert.equal("Press any button on your controller", editor.Prompt.Title:GetText())
			assert.equal("Hold LT or RT first to see that layer. Menu closes this window. Using the cursor? Click a button on the picture.",
				editor.Prompt.Text:GetText())
			setModifiers(w, "none", "none", "none")
			w.padState = { labelStyle = "Shapes", name = "DualSense Wireless Controller" }
			frame:Fire("OnEvent", "GAME_PAD_CONNECTED")
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\PadPlayStation", editor.Art.texture)
			assert.equal("Options closes this window. Using the cursor? Click a button on the picture.", editor.Prompt.Text:GetText())
		end)

		it("shows what a pressed button does in the strip, ringing it on the drawing", function()
			open()
			press("PAD1")
			assert.is_true(strip:IsShown())
			assert.is_false(editor.Prompt:IsShown())
			assert.equal("A", strip.Key:GetText())
			assert.equal("Base layer", strip.Layer:GetText())
			assert.equal("name:JUMP", strip.Name:GetText())
			assert.equal("Key binding command", strip.Place:GetText())
			assert.is_true(strip.Icon:IsShown()) -- Jump wears LeanPad's own face
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\IconJump", strip.Icon.texture)
			assert.is_true(strip.Clear.enabled)
			assert.equal("|cff66788aOther layers|r   " .. LT_RAW .. " spell:1953   text:PADRTRIGGER name:MULTIACTIONBAR2BUTTON7   "
				.. LT_RAW .. " + text:PADRTRIGGER name:MULTIACTIONBAR3BUTTON7", strip.Others:GetText())
			local x, y = ns.KeyGeometry(ns.PADS.xbox, "PAD1")
			assert.is_true(editor.Ring:IsShown())
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\Ring", editor.Ring.texture)
			assert.same({ "CENTER", editor, "TOPLEFT", 460 + x, -(298 - y) }, editor.Ring.point)
			assert.equal(ns.Font(13, ns.COLORS.accent), callout("PAD1").text.font)
			assert.same({ ns.COLORS.accent[1], ns.COLORS.accent[2], ns.COLORS.accent[3], 1 }, callout("PAD1").lines[1].color)
			press("PADDUP")
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\RingSquare", editor.Ring.texture)
			assert.equal("|cff66788aEmpty slot|r", strip.Name:GetText())
			assert.equal("Action Bar 1, slot 5", strip.Place:GetText())
			press("PADDRIGHT") -- Target nearest enemy has a face though it sits on no bar
			assert.is_true(strip.Icon:IsShown())
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\IconTargetEnemy", strip.Icon.texture)
			assert.equal("name:TARGETNEARESTENEMY", strip.Name:GetText())
		end)

		it("reads the layer from the held modifiers and shows the slot's spell", function()
			open()
			w.held.shift = true
			press("PADLTRIGGER") -- the modifier alone only switches layer
			assert.is_false(strip:IsShown())
			press("PAD1")
			assert.is_true(tab(2).Underline:IsShown())
			assert.equal("spell:1953", strip.Name:GetText())
			assert.equal("Action Bar 2, slot 1", strip.Place:GetText())
			assert.equal(135808, strip.Icon.texture)
			assert.is_true(strip.Icon:IsShown())
		end)

		it("follows held modifiers while open", function()
			open()
			w.held.ctrl = true
			frame:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.is_true(tab(3).Underline:IsShown())
			w.held.ctrl = false
			frame:Fire("OnEvent", "MODIFIER_STATE_CHANGED")
			assert.is_true(tab(1).Underline:IsShown()) -- letting go returns to Base
		end)

		it("explains the cursor's buttons", function()
			open()
			press("PAD1")
			assert.equal("Also the cursor's left-click.", strip.Note:GetText())
			press("PAD2")
			assert.equal("Also the cursor's right-click.", strip.Note:GetText())
			press("PADRSTICK")
			assert.equal("Keeps the gamepad cursor reachable.", strip.Note:GetText())
			press("PAD3")
			assert.equal("", strip.Note:GetText())
		end)

		it("picks which form's Action Bar 1 page Base edits, back to the page in play once closed", function()
			w.forms = { { spell = 5487, icon = 1 }, { spell = 768, icon = 2 } }
			ns.db.formPages = { [7] = { spell = 768 } }
			w.actions[73] = { kind = "spell", id = 99, texture = 7373 }
			open()
			local page = editor.Toolbar.Page
			assert.is_true(page:IsShown())
			assert.equal("Base: Normal", page.Label:GetText())
			page:Fire("OnClick")
			assert.same({ "Base buttons change with your form; the other layers stay the same in every form." }, w.menu.root.titles)
			assert.same({ "Normal", "spell:768" }, labels(w.menu.root))
			wow.entry(w.menu.root, "spell:768").callback()
			assert.equal("Base: spell:768", page.Label:GetText())
			press("PAD3")
			assert.equal("spell:99", strip.Name:GetText())
			assert.equal("Action Bar 1, slot 1, spell:768", strip.Place:GetText())
			ns.ToggleController()
			assert.equal(1, ns.MainBarPage())
		end)

		it("hides the page picker for a class without forms, and says how to add one", function()
			open()
			assert.is_false(editor.Toolbar.Page:IsShown())
			editor.Toolbar.Page:Fire("OnClick")
			assert.equal("Shift into a form once to add it here.", w.menu.root.titles[2])
		end)

		it("warns that a button on a turned-off bar does nothing", function()
			open()
			w.held.shift = true
			w.barsShown[1] = false
			press("PAD1")
			assert.equal("|cffff5050Action Bar 2 is turned off, so this button does nothing.|r Turn it on in Options > Gameplay > Action Bars.", strip.Note:GetText())
		end)

		it("shows a layer button as one, with nothing to change, clear or drop on it", function()
			open()
			w.bindings.PADLTRIGGER = "JUMP" -- a stale binding never shows: layer buttons hold no action
			editor.Hits.PADLTRIGGER:Fire("OnClick")
			assert.equal("Opens the LT layer", strip.Name:GetText())
			assert.equal("Layer button: hold it to use that layer. It fires nothing itself.", strip.Place:GetText())
			assert.is_false(strip.Icon:IsShown())
			assert.is_false(strip.Change:IsShown())
			assert.is_false(strip.Clear:IsShown())
			assert.is_false(strip.Hint:IsShown())
			assert.equal("", strip.Others:GetText())
			assert.equal("Opens the LT layer " .. LT, callout("PADLTRIGGER").text:GetText())
			w.cursor = "spell"
			strip:Fire("OnReceiveDrag")
			assert.same({}, w.placed)
			assert.equal("LeanPad: LT is a layer button and holds no action.", w.printed[#w.printed])
			press("PAD1")
			assert.is_true(strip.Change:IsShown())
			assert.is_true(strip.Hint:IsShown())
		end)

		it("says so when a button is unbound, and can't clear it", function()
			open()
			press("PADPADDLE1")
			assert.equal("|cff66788aNot bound|r", strip.Name:GetText())
			assert.matches("drop a spell", strip.Place:GetText())
			assert.is_false(strip.Clear.enabled)
			assert.is_false(editor.Ring:IsShown()) -- paddles aren't on the drawing
		end)

		it("changes, clears, and takes dropped spells for the picked button", function()
			open()
			w.held.shift = true
			press("PAD1")
			button("Change action..."):Fire("OnClick")
			assert.equal("text:SHIFT-PAD1", w.menu.root.title)
			w.cursor = "spell"
			strip:Fire("OnReceiveDrag")
			strip:Fire("OnMouseUp")
			assert.same({ 61, 61 }, w.placed)
			w.cursor = nil
			strip:Fire("OnMouseUp")
			assert.same({ 61, 61 }, w.placed)
			button("Clear"):Fire("OnClick")
			assert.is_nil(w.bindings["SHIFT-PAD1"])
		end)

		it("lets cursor users hover, click and drop on the drawing", function()
			open()
			local y = editor.Hits.PAD4
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\Ring", y:GetHighlightTexture().texture)
			assert.same({ ns.COLORS.accent[1], ns.COLORS.accent[2], ns.COLORS.accent[3], 0.6 }, y:GetHighlightTexture().vertexColor)
			assert.equal("Interface\\AddOns\\LeanPad\\Art\\RingSquare", editor.Hits.PADDUP:GetHighlightTexture().texture)
			y:Fire("OnClick")
			assert.equal("Y", strip.Key:GetText())
			w.held.shift = true
			w.cursor = "spell"
			editor.Hits.PAD1:Fire("OnReceiveDrag")
			assert.equal("A", strip.Key:GetText())
			assert.same({ 61 }, w.placed)
		end)

		it("takes an action out of its bar slot when dragged off the drawing or the strip", function()
			open()
			w.held.shift = true
			editor.Hits.PAD1:Fire("OnDragStart")
			assert.equal("A", strip.Key:GetText())
			assert.same({ { "action", 61 } }, w.pickups)
			strip:Fire("OnDragStart")
			assert.same({ { "action", 61 }, { "action", 61 } }, w.pickups)
			w.actions[61] = nil
			strip:Fire("OnDragStart") -- an empty slot has nothing to take
			assert.equal(2, #w.pickups)
		end)

		it("closes on the pad's Menu button and when combat starts, forgetting the pick", function()
			open()
			press("PAD1")
			press("PADFORWARD")
			assert.is_false(frame:IsShown())
			ns.ToggleController()
			assert.is_false(strip:IsShown())
			frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
			assert.is_false(frame:IsShown())
		end)

		it("flashes Saved in the footer for two seconds once a change is written", function()
			ns.Saved() -- nothing to flash on before the window exists
			open()
			press("PAD1")
			button("Clear"):Fire("OnClick")
			assert.is_true(editor.Saved:IsShown())
			assert.is_false(editor.Status:IsShown())
			assert.equal("|A:common-icon-checkmark:12:12|a Saved to your account's key bindings", editor.Saved:GetText())
			assert.equal(2, w.timers[1].seconds)
			wow.tick()
			assert.is_false(editor.Saved:IsShown())
			assert.is_true(editor.Status:IsShown())
			-- A change made in combat flashes when it is actually written.
			w.combat = true
			button("Change..."):Fire("OnClick")
			wow.entry(w.menu.root.entries[1], "LB").callback()
			assert.is_false(editor.Saved:IsShown())
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_true(editor.Saved:IsShown())
			-- On the settings page the flash is plain Saved.
			button(SETTINGS):Fire("OnClick")
			ns.Saved()
			assert.equal("|A:common-icon-checkmark:12:12|a Saved", frame.Options.Saved:GetText())
			assert.is_false(frame.Options.Status:IsShown())
		end)

		it("refreshes the strip when bindings change", function()
			open()
			press("PAD1")
			w.bindings.PAD1 = "SITORSTAND"
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal("name:SITORSTAND", strip.Name:GetText())
		end)

		it("says which binding set changes save to", function()
			open()
			assert.equal("Changes save to your account's key bindings", editor.Status:GetText())
			w.bindingSet = Enum.BindingSet.Character
			frame:Fire("OnEvent", "UPDATE_BINDINGS")
			assert.equal("Changes save to this character's key bindings", editor.Status:GetText())
		end)

		it("footer opens the setup dialog, Blizzard's key bindings and the settings page", function()
			open()
			button("Reset to default layout..."):Fire("OnClick")
			assert.same({ "LEANPAD_SETUP" }, w.popups)
			button(KEY_BINDINGS):Fire("OnClick")
			assert.same({ Settings.KEYBINDINGS_CATEGORY_ID }, w.opened)
			button(SETTINGS):Fire("OnClick")
			assert.is_false(editor:IsShown())
			assert.is_true(frame.Options:IsShown())
			press("PAD1") -- the settings page takes no picks
			assert.is_false(strip:IsShown())
			press("PADFORWARD")
			assert.is_false(frame:IsShown())
			ns.ToggleController() -- reopens on the editor
			assert.is_true(editor:IsShown())
			assert.is_false(frame.Options:IsShown())
		end)

		it("closes from the title bar's X and opens straight to settings for /lp settings", function()
			ns.OpenOptions()
			frame = LeanPadControllerFrame
			assert.is_true(frame.Options:IsShown())
			assert.is_false(frame.Editor:IsShown())
			local close = find("Button", function(widget) return widget.parent == frame and widget.scripts.OnClick and not widget.template end)
			close:Fire("OnClick")
			assert.is_false(frame:IsShown())
			ns.OpenOptions()
			assert.is_true(frame:IsShown())
			ns.ToggleController()
			assert.is_false(frame:IsShown())
		end)
	end)
	describe("form pages", function()
		local watcher
		local function shift(form, bonus, stealthed)
			w.form, w.bar.bonus, w.stealthed = form, bonus, stealthed
			watcher:Fire("OnEvent", "UPDATE_BONUS_ACTIONBAR")
		end

		before_each(function()
			w.forms = { { spell = 5487, icon = 1 }, { spell = 768, icon = 2 }, { spell = 783, icon = 3 } }
			for _, widget in ipairs(w.widgets) do
				if widget.events.UPDATE_BONUS_ACTIONBAR and widget.events.PLAYER_ENTERING_WORLD then watcher = widget end
			end
		end)

		it("learns each form's Action Bar 1 page as the player shifts, and names pages by it", function()
			shift(0, nil) -- caster
			shift(0, 7) -- a bonus bar with no form to name it by
			shift(3, nil) -- Travel Form without a page of its own
			w.bar.page = 2
			shift(1, 9) -- a page picked by hand, not the form's
			assert.is_nil(ns.db.formPages)
			w.bar.page = 1
			shift(2, 7)
			shift(2, 8, true) -- Prowl
			shift(1, 9)
			assert.same({ [7] = { spell = 768 }, [8] = { spell = 768, stealth = true }, [9] = { spell = 5487 } }, ns.db.formPages)
			assert.equal("Normal", ns.PageName(1))
			assert.equal("spell:768 (stealth)", ns.PageName(8))
			assert.equal("Page 12", ns.PageName(12))
			assert.same({ { 1, "Normal" }, { 7, "spell:768" }, { 8, "spell:768 (stealth)" }, { 9, "spell:5487" } }, ns.PageOptions())
			assert.equal("Action Bar 1, slot 5, spell:5487", ns.ActionPlace("ACTIONBUTTON5"))
		end)
	end)

	describe("bar addons", function()
		after_each(function() _G.ElvUI_Bar1 = nil end)

		it("are found by ElvUI's own bars or by name", function()
			assert.is_nil(ns.BarAddon())
			w.addons.Dominos = true
			assert.equal("Dominos", ns.BarAddon())
			_G.ElvUI_Bar1 = {}
			assert.equal("ElvUI", ns.BarAddon())
		end)

		it("are named once a session, with ElvUI's bar numbers for the layers", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(w.printed[1])
			ns, w = wow.boot(nil)
			_G.ElvUI_Bar1 = {}
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.equal("LeanPad: " .. ns.BarAddonNote("ElvUI"), w.printed[#w.printed])
			assert.matches("its Bars 6, 5 and 3", ns.BarAddonNote("ElvUI"))
			assert.matches("^Bartender4 runs your action bars", ns.BarAddonNote("Bartender4"))
		end)

		it("make Blizzard's turned-off bars no reason to warn", function()
			w.barsShown[1] = false
			assert.equal(2, ns.BarOff("MULTIACTIONBAR1BUTTON1"))
			w.addons.Bartender4 = true
			assert.is_nil(ns.BarOff("MULTIACTIONBAR1BUTTON1"))
		end)
	end)
end)
