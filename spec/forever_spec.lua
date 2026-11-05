local wow = require("spec.wow")

describe("Forever", function()
	local ns, w, bars

	local function fireScript(event, ...)
		for _, widget in ipairs(w.widgets) do
			if widget.events[event] and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, event, ...) end
		end
	end

	before_each(function()
		ns, w = wow.bootForever({}, nil)
		bars = GamepadMainActionBarFrame.PageUnit.actionBars
	end)
	after_each(wow.restore)

	it("declares Forever's interface and loads its file only there", function()
		assert.equal("120105, 16001", wow.tocHeader("Interface"))
		local line
		for toc in io.lines("LeanPad/LeanPad.toc") do
			if toc:find("^Forever%.lua") then line = toc:gsub("%s+$", "") end
		end
		assert.equal("Forever.lua [AllowLoadGameType forever, camelot]", line)
	end)

	it("does nothing on a client without the Gamepad UI, even if the client loads the file", function()
		ns, w = wow.boot({}, nil)
		assert.is_false(ns.UsesGamepadUI())
		assert.equal("PAD1", (ns.ModifierKeys().PAD1 and "x") or "PAD1")
		assert.equal("", ns.BindingAction("PAD1"))
	end)

	it("runs as retail while the Gamepad UI is off", function()
		w.gamepadUI = false
		w.bindings.PAD1 = "JUMP"
		assert.is_false(ns.UsesGamepadUI())
		assert.equal("JUMP", ns.BindingAction("PAD1"))
		assert.equal("Base", ns.Layers()[1].label)
		assert.same({}, ns.ModifierKeys())
	end)

	describe("layers", function()
		it("are Blizzard's four bars, named for the buttons that open them", function()
			local layers = ns.Layers()
			assert.same({ "", "LEFT-", "RIGHT-", "BOTH-" }, { layers[1].prefix, layers[2].prefix, layers[3].prefix, layers[4].prefix })
			assert.equal("Base", layers[1].label)
			assert.equal("text:PADLTRIGGER", layers[2].label)
			assert.equal("text:PADLTRIGGER + text:PADRTRIGGER", layers[4].label)
		end)

		it("still have names when a layer button is unbound", function()
			w.context.PADLTRIGGER = nil
			assert.equal("Left", ns.Layers()[2].label)
		end)

		it("follow Blizzard's modifiers, not Shift and Ctrl", function()
			assert.equal("", ns.HeldPrefix())
			w.modifiers.left = true
			assert.equal("LEFT-", ns.HeldPrefix())
			w.modifiers.right = true
			assert.equal("BOTH-", ns.HeldPrefix())
			w.modifiers.left = false
			assert.equal("RIGHT-", ns.HeldPrefix())
		end)

		it("mark the buttons that open them", function()
			assert.same({ PADLTRIGGER = "LEFT-", PADRTRIGGER = "RIGHT-" }, ns.ModifierKeys())
			assert.same({ { "PADLTRIGGER", "Left layer" }, { "PADRTRIGGER", "Right layer" } }, ns.LayerKeyNames())
		end)

		it("skip an unbound button in the toolbar", function()
			w.context.PADLTRIGGER = nil
			assert.same({ { "PADRTRIGGER", "Right layer" } }, ns.LayerKeyNames())
		end)

		it("change their button in Blizzard's binding context", function()
			ns.SetLayerButton("GAMEPADLEFTMOD", "PADLSHOULDER")
			assert.equal("GAMEPADLEFTMOD", w.context.PADLSHOULDER)
			assert.is_nil(w.context.PADLTRIGGER)
			assert.equal("GAMEPADLEFTMOD", ns.db.contextDefaults.PADLTRIGGER)
			assert.equal("PADLSHOULDER", ns.LayerButtonKey("GAMEPADLEFTMOD"))
			assert.equal(1, #w.saved)
		end)

		it("can lose their button", function()
			ns.SetLayerButton("GAMEPADLEFTMOD", "none")
			assert.is_nil(w.context.PADLTRIGGER)
			assert.equal("none", ns.LayerButtonKey("GAMEPADLEFTMOD"))
		end)

		it("offer the two layers in the Change menu and on the settings page", function()
			assert.equal("GAMEPADLEFTMOD", ns.LayerButtons()[1][1])
			MenuUtil.CreateContextMenu(nil, ns.LayerMenu)
			local left = wow.entry(w.menu.root, "Left layer")
			assert.is_truthy(left)
			assert.is_truthy(wow.entry(w.menu.root, "Right layer"))
			wow.entry(left, "text:PADLSHOULDER")
		end)
	end)

	it("uses Blizzard's jump icon, which only Forever has", function()
		assert.same({ atlas = "gamepad-ability-icon-jump" }, ns.CommandIcon("JUMP"))
		assert.same({ texture = "Interface\\Cursor\\Interact" }, ns.CommandIcon("INTERACTTARGET"))
	end)

	describe("what a button does", function()
		it("is a slot on the layer's bar, for the D-pad and face buttons", function()
			assert.equal("GAMEPADBAR:topBar:1", ns.BindingAction("PADDLEFT"))
			assert.equal("GAMEPADBAR:leftBar:8", ns.BindingAction("LEFT-PAD1"))
			assert.equal("GAMEPADBAR:rightBar:5", ns.BindingAction("RIGHT-PAD3"))
			assert.equal("GAMEPADBAR:bottomBar:2", ns.BindingAction("BOTH-PADDUP"))
		end)

		it("is Blizzard's own action on Base's face buttons", function()
			assert.equal("JUMP", ns.BindingAction("PAD1"))
			assert.equal("LEANPAD_BACK", ns.BindingAction("PAD2"))
			assert.equal("INTERACTTARGET", ns.BindingAction("PAD3"))
			assert.equal("LEANPAD_INSPECT", ns.BindingAction("PAD4"))
			assert.equal("Back", ns.ActionInfo("PAD2"))
		end)

		it("is nothing on a layer for a key off the bars", function()
			assert.equal("", ns.BindingAction("LEFT-PADLSTICK"))
		end)

		it("prefers Blizzard's context binding, then the plain one", function()
			w.bindings.PADRSTICK, w.bindings.PADBACK = "JUMP", "OPENALLBAGS"
			assert.equal("TOGGLEPINGSYSTEM", ns.BindingAction("PADRSTICK"))
			assert.equal("OPENALLBAGS", ns.BindingAction("PADBACK"))
		end)
	end)

	describe("slots", function()
		it("come from the bar position and the page, skipping the reserved half", function()
			assert.equal(200, ns.SlotForCommand("GAMEPADBAR:topBar:1"))
			assert.equal(204, ns.SlotForCommand("GAMEPADBAR:leftBar:1"))
			w.gamepadPage = 2
			assert.equal(228, ns.SlotForCommand("GAMEPADBAR:topBar:1"))
		end)

		it("follow the page the editor is viewing", function()
			assert.equal(1, ns.MainBarPage())
			w.gamepadPage = 3
			assert.equal(3, ns.MainBarPage())
		end)

		it("come from the override bar while a stance or possess bar replaces one", function()
			bars.stanceBar.overriding = bars.topBar
			assert.equal(921, ns.SlotForCommand("GAMEPADBAR:topBar:1"))
			assert.equal(bars.stanceBar.buttons[1], ns.ButtonForCommand("GAMEPADBAR:topBar:1"))
		end)

		it("fall back to the button on Blizzard's special page", function()
			w.gamepadPage = 4
			bars.topBar.buttons[1].action = 777
			assert.equal(777, ns.SlotForCommand("GAMEPADBAR:topBar:1"))
		end)

		it("leave other commands to LeanPad's own lookup", function()
			assert.equal(61, ns.SlotForCommand("MULTIACTIONBAR1BUTTON1"))
			assert.equal(MultiBarBottomLeftButton1, ns.ButtonForCommand("MULTIACTIONBAR1BUTTON1"))
			assert.is_nil(ns.SlotForCommand("JUMP"))
		end)
	end)

	describe("the editor", function()
		it("says where an action lives", function()
			assert.equal("Gamepad bar, page 1", ns.ActionPlace("GAMEPADBAR:topBar:1"))
			assert.equal("Kept by Blizzard's Gamepad UI", ns.ActionPlace("JUMP"))
			assert.equal("Key binding command", ns.ActionPlace("OPENALLBAGS"))
		end)

		it("offers Blizzard's three pages", function()
			assert.same({ { 1, "Page 1" }, { 2, "Page 2" }, { 3, "Page 3" } }, ns.PageOptions())
		end)

		it("names a button by its layer", function()
			assert.equal("text:PADLTRIGGER + text:PAD1", ns.BindingTitle("LEFT-PAD1"))
			assert.equal("text:PAD1", ns.BindingTitle("PAD1"))
		end)

		it("offers only spells and macros for a bar position", function()
			assert.is_true(ns.SlotOnly("LEFT-PAD1"))
			assert.is_true(ns.SlotOnly("PADDUP"))
			assert.is_false(ns.SlotOnly("PADBACK"))
			MenuUtil.CreateContextMenu(nil, function(_, root) ns.BuildAssignMenu(root, "LEFT-PAD1") end)
			assert.is_truthy(wow.entry(w.menu.root, "Spells"))
			assert.is_nil(wow.entry(w.menu.root, "Commands"))
		end)

		it("binds a command to a key off the bars, taking it out of Blizzard's context", function()
			ns.Assign("PADRSTICK", "OPENALLBAGS")
			assert.is_nil(w.context.PADRSTICK)
			assert.equal("OPENALLBAGS", w.bindings.PADRSTICK)
			assert.equal("TOGGLEPINGSYSTEM", ns.db.contextDefaults.PADRSTICK)
			assert.equal(1, #w.saved)
		end)

		it("keeps the first default a key had", function()
			ns.Assign("PADRSTICK", "OPENALLBAGS")
			ns.Assign("PADRSTICK", "JUMP")
			assert.equal("TOGGLEPINGSYSTEM", ns.db.contextDefaults.PADRSTICK)
		end)

		it("clears a bar position by emptying its slot", function()
			w.actions[200] = { texture = 1, kind = "spell", id = 1 }
			ns.Assign("PADDLEFT", nil)
			assert.equal("GAMEPADACTIONBUTTON1", w.context.PADDLEFT)
			assert.same({ "action", 200 }, w.pickups[#w.pickups])
		end)

		it("leaves an empty slot alone", function()
			local before = #w.pickups
			ns.Assign("PADDLEFT", nil)
			assert.equal(before, #w.pickups)
		end)

		it("explains Blizzard's reserved buttons and layer keys off the bars", function()
			ns.Assign("PAD1", nil)
			assert.is_truthy(w.printed[#w.printed]:find("keeps this button"))
			ns.Assign("LEFT-PADLSTICK", nil)
			assert.is_truthy(w.printed[#w.printed]:find("only the D%-pad"))
		end)

		it("finds a bar position's slot, and refuses a button that has none", function()
			assert.equal(204, ns.EnsureSlot("LEFT-PADDLEFT"))
			assert.is_nil(ns.EnsureSlot("PAD1"))
			assert.is_truthy(w.printed[#w.printed]:find("holds no spell"))
		end)
	end)

	describe("setup", function()
		it("asks nothing, since Blizzard's defaults already work", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.same({}, w.popups)
		end)

		it("resets only what LeanPad changed", function()
			ns.Assign("PADRSTICK", "OPENALLBAGS")
			ns.SetLayerButton("GAMEPADLEFTMOD", "none")
			ns.ShowReset()
			assert.same({ "LEANPAD_RESET_GAMEPAD" }, w.popups)
			StaticPopupDialogs.LEANPAD_RESET_GAMEPAD.OnAccept()
			assert.equal("TOGGLEPINGSYSTEM", w.context.PADRSTICK)
			assert.equal("GAMEPADLEFTMOD", w.context.PADLTRIGGER)
			assert.is_nil(w.bindings.PADRSTICK)
			assert.is_nil(ns.db.contextDefaults)
		end)

		it("clears a key that had no Blizzard binding", function()
			ns.Assign("PADBACK", "OPENALLBAGS")
			assert.equal("", ns.db.contextDefaults.PADBACK)
			ns.Apply()
			assert.is_nil(w.context.PADBACK)
			assert.is_nil(w.bindings.PADBACK)
		end)

		it("resets nothing when LeanPad changed nothing", function()
			ns.Apply()
			assert.is_truthy(w.printed[#w.printed]:find("gamepad buttons are back"))
		end)

		it("never claims pad keys from Blizzard's bars", function()
			w.bindingList = { { "MULTIACTIONBAR1BUTTON1", "BINDING_HEADER_MULTIACTIONBAR", "PADDUP" } }
			fireScript("UPDATE_BINDINGS")
			assert.same({}, w.overrides)
		end)
	end)

	describe("profiles", function()
		it("make the Default profile at login", function()
			w.actions[200] = { texture = 1, kind = "spell", id = 7 }
			wow.fire("PLAYER_ENTERING_WORLD")
			local default = ns.db.profiles.Default
			assert.equal("GAMEPADLEFTMOD", default.bindings["CONTEXT:PADLTRIGGER"])
			assert.same({ "spell", 7 }, default.slots[253][200])
			assert.equal("Default", ns.char.profile)
		end)

		it("save and restore context bindings beside the plain ones", function()
			local saved = ns.Snapshot()
			assert.equal("GAMEPADLEFTMOD", saved.bindings["CONTEXT:PADLTRIGGER"])
			w.context.PADLTRIGGER = nil
			ns.PutBack(saved)
			assert.equal("GAMEPADLEFTMOD", w.context.PADLTRIGGER)
		end)

		it("write plain keys as plain bindings", function()
			ns.BindKey("PADBACK", "JUMP")
			assert.equal("JUMP", w.bindings.PADBACK)
			assert.is_nil(w.context.PADBACK)
		end)

		it("never clear Blizzard's context bindings, even for a profile that lists none", function()
			ns.BindKey("CONTEXT:PADRSTICK", "")
			assert.equal("TOGGLEPINGSYSTEM", w.context.PADRSTICK)
			local saved = ns.Snapshot()
			for key in pairs(saved.bindings) do
				if key:find("^CONTEXT:") then saved.bindings[key] = nil end
			end
			ns.PutBack(saved)
			assert.equal("GAMEPADACTIONBUTTON8", w.context.PAD1)
		end)

		it("cover every slot of the three pages, none reserved", function()
			local slots = {}
			ns.ExtraProfileSlots(slots)
			local count, lowest = 0, math.huge
			for slot in pairs(slots) do
				count, lowest = count + 1, math.min(lowest, slot)
			end
			assert.equal(84, count)
			assert.equal(200, lowest)
		end)
	end)

	describe("play styles", function()
		it("know which of Forever's specs cast from range", function()
			w.specID = 1482 -- Mage
			assert.equal("ranged", ns.SpecStyle())
			w.specID = 1491 -- Warrior
			assert.equal("melee", ns.SpecStyle())
		end)

		it("write soft targeting as temporary CVars, which outrank saved ones", function()
			ns.WritePadCVar("SoftTargetEnemyArc", "2")
			assert.equal("2", w.tempCVars.SoftTargetEnemyArc)
			assert.is_nil(w.cvars.SoftTargetEnemyArc)
		end)

		it("write everything else as usual", function()
			ns.WritePadCVar("GamePadFaceMovementMaxAngleCombat", "115")
			assert.equal("115", w.cvars.GamePadFaceMovementMaxAngleCombat)
		end)
	end)

	describe("asking to turn the Gamepad UI off", function()
		local function prompt()
			for _, widget in ipairs(w.widgets) do
				if widget.scripts.OnGamePadButtonDown and widget.events.PLAYER_REGEN_DISABLED then return widget end
			end
		end

		-- The prompt's two buttons, turn off then keep, found by their labels' words.
		local function promptButton(label)
			for _, widget in ipairs(w.widgets) do
				if widget.parent == prompt() and widget.kind == "Button" and widget.text == label then return widget end
			end
		end

		it("asks at login in LeanPad's own window, not one of Blizzard's that would taint the Gamepad UI", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_true(prompt():IsShown())
			assert.same({}, w.popups)
		end)

		it("doesn't ask with the Gamepad UI off", function()
			w.gamepadUI = false
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(prompt())
		end)

		it("waits for the end of combat", function()
			w.combat = true
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(prompt())
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.is_true(prompt():IsShown())
		end)

		it("gets out of the way when combat starts", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			fireScript("PLAYER_REGEN_DISABLED")
			assert.is_false(prompt():IsShown())
		end)

		it("never writes the setting, which the client blocks from addons", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			prompt():Fire("OnGamePadButtonDown", "PAD1")
			assert.is_nil(w.cvars.InputDeviceInterfaceStyle)
		end)

		it("says where the setting is on A, and offers LeanPad's layout once it goes off", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			prompt():Fire("OnGamePadButtonDown", "PAD1")
			assert.is_false(prompt().propagate)
			assert.is_false(prompt():IsShown())
			assert.is_truthy(w.printed[#w.printed]:find("untick Enable Gamepad UI", 1, true))
			assert.same({}, w.popups)
			w.gamepadUI = false
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.equal("LEANPAD_SETUP", w.popups[1])
		end)

		it("offers the layout only once", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			prompt():Fire("OnGamePadButtonDown", "PAD1")
			w.gamepadUI = false
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.equal(1, #w.popups)
		end)

		it("doesn't ask again while the player goes to the setting", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			prompt():Fire("OnGamePadButtonDown", "PAD1")
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.is_false(prompt():IsShown())
		end)

		it("offers no layout when the Gamepad UI goes off unasked", function()
			w.gamepadUI = false
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.same({}, w.popups)
		end)

		it("works from the mouse too", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			promptButton("Got it"):Fire("OnClick")
			assert.is_false(prompt():IsShown())
		end)

		it("keeps it on with B, and doesn't ask again", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			local shown = prompt()
			shown:Fire("OnGamePadButtonDown", "PAD2")
			assert.is_false(shown:IsShown())
			assert.is_true(ns.db.gamepadUIKept)
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.is_false(shown:IsShown())
		end)

		it("keeps the answer out of profiles", function()
			ns.db.gamepadUIKept = true
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(ns.db.profiles.Default.settings.gamepadUIKept)
		end)

		it("leaves other buttons to their bindings", function()
			wow.fire("PLAYER_ENTERING_WORLD")
			prompt():Fire("OnGamePadButtonDown", "PADDUP")
			assert.is_true(prompt().propagate)
			assert.is_true(prompt():IsShown())
		end)

		it("asks when the Gamepad UI is turned on later", function()
			w.gamepadUI = false
			wow.fire("PLAYER_ENTERING_WORLD")
			w.gamepadUI = true
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.is_true(prompt():IsShown())
		end)
	end)

	describe("menus", function()
		local owner

		-- The shown row for an entry's text, from the menu LeanPad drew.
		local function row(text)
			for _, widget in ipairs(w.widgets) do
				local entry = rawget(widget, "entry")
				if entry and entry.text == text and widget:IsShown() then return widget end
			end
		end

		before_each(function()
			owner = CreateFrame("Button")
			MenuUtil.CreateContextMenu = function() error("Blizzard's menu would taint its gamepad navigation") end
		end)

		it("never open Blizzard's menu while the Gamepad UI is on", function()
			assert.has_no.errors(function()
				ns.ContextMenu(owner, function(_, root) root:CreateButton("Bags", function() end) end)
			end)
			assert.is_true(LeanPadMenu:IsShown())
		end)

		it("stay Blizzard's while the Gamepad UI is off", function()
			w.gamepadUI = false
			assert.has_error(function() ns.ContextMenu(owner, function() end) end)
		end)

		it("run a button and close", function()
			local clicked
			ns.ContextMenu(owner, function(_, root) root:CreateButton("Bags", function() clicked = true end) end)
			row("Bags").scripts.OnClick(row("Bags"))
			assert.is_true(clicked)
			assert.is_false(LeanPadMenu:IsShown())
		end)

		it("show titles and dividers that do nothing", function()
			ns.ContextMenu(owner, function(_, root)
				root:CreateTitle("Heading")
				root:CreateDivider()
			end)
			row("Heading").scripts.OnClick(row("Heading"))
			assert.is_true(LeanPadMenu:IsShown())
			row("Heading").scripts.OnEnter(row("Heading"))
			assert.is_false(row("Heading").Hover:IsShown())
		end)

		it("tick the current radio and pass its value on", function()
			local picked
			ns.ContextMenu(owner, function(_, root)
				ns.Radios(root, { { 1, "One" }, { 2, "Two" } }, function() return 2 end, function(value) picked = value end)
			end)
			assert.is_false(row("One").Check:IsShown())
			assert.is_true(row("Two").Check:IsShown())
			row("One").scripts.OnClick(row("One"))
			assert.equal(1, picked)
		end)

		it("open a submenu on hover, and close it for another row", function()
			ns.ContextMenu(owner, function(_, root)
				local spells = root:CreateButton("Spells")
				spells:SetScrollMode(400)
				spells:CreateButton("Blink", function() end)
				root:CreateButton("Bags", function() end)
			end)
			local spells = row("Spells")
			assert.is_nil(row("Blink"))
			spells.scripts.OnEnter(spells)
			assert.is_true(spells.Hover:IsShown())
			assert.is_true(spells.Arrow:IsShown())
			assert.is_truthy(row("Blink"))
			local submenu = row("Blink").parent.parent.parent
			assert.is_true(submenu:IsShown())
			row("Bags").scripts.OnEnter(row("Bags"))
			assert.is_false(submenu:IsShown())
			spells.scripts.OnLeave(spells)
			assert.is_false(spells.Hover:IsShown())
		end)

		it("hide rows left over from a longer menu", function()
			ns.ContextMenu(owner, function(_, root)
				root:CreateButton("One", function() end)
				root:CreateButton("Two", function() end)
			end)
			ns.ContextMenu(owner, function(_, root) root:CreateButton("Three", function() end) end)
			assert.is_truthy(row("Three"))
			assert.is_nil(row("Two"))
		end)

		it("cap their height and scroll within their range", function()
			ns.ContextMenu(owner, function(_, root)
				for index = 1, 40 do root:CreateButton("Row" .. index, function() end) end
			end)
			local scroll = row("Row1").parent.parent
			scroll.scrollRange = 48
			scroll.scripts.OnMouseWheel(scroll, -1)
			assert.equal(24, scroll.verticalScroll)
			scroll.scripts.OnMouseWheel(scroll, -5)
			assert.equal(48, scroll.verticalScroll)
			scroll.scripts.OnMouseWheel(scroll, 5)
			assert.equal(0, scroll.verticalScroll)
		end)

		it("close on a click elsewhere, Escape and combat", function()
			ns.ContextMenu(owner, function() end)
			LeanPadMenu.scripts.OnClick(LeanPadMenu)
			assert.is_false(LeanPadMenu:IsShown())
			ns.ContextMenu(owner, function() end)
			LeanPadMenu.scripts.OnEvent(LeanPadMenu)
			assert.is_false(LeanPadMenu:IsShown())
			assert.is_true(LeanPadMenu.events.PLAYER_REGEN_DISABLED)
			local listed
			for _, name in ipairs(UISpecialFrames) do listed = listed or name == "LeanPadMenu" end
			assert.is_true(listed)
		end)
	end)

	describe("the crossbar", function()
		before_each(function() wow.fire("PLAYER_ENTERING_WORLD") end)

		it("fades the bars it mirrors and leaves the rest", function()
			for _, name in ipairs({ "topBar", "leftBar", "rightBar", "bottomBar", "possessBar", "stanceBar" }) do
				assert.equal(0, bars[name].alpha)
			end
		end)

		it("gives them back when it is turned off", function()
			ns.db.crossbar = false
			ns.SetCrossbarShown(false)
			assert.equal(1, bars.topBar.alpha)
		end)

		it("gives them back when the Gamepad UI goes off", function()
			w.gamepadUI = false
			fireScript("CVAR_UPDATE", "InputDeviceInterfaceStyle")
			wow.nextFrame()
			assert.equal(1, bars.topBar.alpha)
		end)

		it("ignores other CVars", function()
			w.gamepadUI = false
			fireScript("CVAR_UPDATE", "GamePadEnable")
			wow.nextFrame()
			assert.equal(0, bars.topBar.alpha)
		end)

		it("mirrors a layer's slot on its set", function()
			w.actions[204] = { texture = 42, kind = "spell", id = 1, usable = true }
			w.modifiers.left = true
			ns.RefreshCrossbar()
			local shown
			for _, widget in ipairs(w.widgets) do
				shown = shown or (rawget(widget, "buttons") and widget.buttons.PADDLEFT)
			end
			assert.equal(204, shown.slot)
			assert.equal(42, shown.Icon.texture)
		end)

		describe("empty buttons", function()
			local function shownSockets()
				local cluster, shown = nil, {}
				for _, widget in ipairs(w.widgets) do
					cluster = cluster or (rawget(widget, "buttons") and widget)
				end
				for key, button in pairs(cluster.buttons) do
					if button:IsShown() then table.insert(shown, key) end
				end
				table.sort(shown)
				return shown
			end
			local CROSS = { "PAD1", "PAD2", "PAD3", "PAD4", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PADDUP" }

			it("show every button in the layout by default on Forever, but the layer buttons", function()
				assert.is_true(ns.ShowEmptySockets())
				ns.RefreshCrossbar()
				assert.same({ "PAD1", "PAD2", "PAD3", "PAD4", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PADDUP",
					"PADLSHOULDER", "PADLSTICK", "PADRSHOULDER", "PADRSTICK" }, shownSockets())
			end)

			it("can be turned off, leaving only what is bound", function()
				ns.SetCrossbarEmpty(false)
				assert.is_false(ns.db.crossbarEmpty)
				assert.same(CROSS, shownSockets()) -- on Blizzard's bars, the cross is all that holds anything
			end)

			it("wait for the crossbar to refresh when it is hidden", function()
				LeanPadCrossbar:Hide()
				assert.has_no.errors(function() ns.SetCrossbarEmpty(false) end)
				assert.is_false(ns.ShowEmptySockets())
			end)

			it("stay off on retail unless asked for", function()
				ns, w = wow.boot({}, nil)
				assert.is_false(ns.ShowEmptySockets())
				ns.db.crossbarEmpty = true
				assert.is_true(ns.ShowEmptySockets())
			end)

			it("never include a stick click holding only a command", function()
				w.gamepadUI = false
				ns.db.crossbarEmpty = false
				w.bindings.PADRSTICK, w.bindings.PADLSTICK = "INTERACTTARGET", "ACTIONBUTTON1"
				ns.RefreshCrossbar()
				assert.same({ "PADLSTICK" }, shownSockets())
			end)
		end)

		it("hooks Blizzard's modifiers and paging instead of joining their callback lists", function()
			local hooked = {}
			for _, entry in ipairs(w.hooks) do hooked[entry.method] = entry.hook end
			assert.is_function(hooked.OnCrossBarModifierChanged)
			assert.is_function(hooked.SetCurrentPage)
		end)

		it("refreshes the crossbar and the open editor when a layer opens", function()
			ns.ToggleController()
			assert.is_true(LeanPadControllerFrame:IsShown())
			w.actions[204] = { texture = 42, kind = "spell", id = 1, usable = true }
			w.modifiers.left = true
			w.hooks[1].hook()
			local found
			for _, widget in ipairs(w.widgets) do
				if rawget(widget, "buttons") then found = found or widget.buttons.PADDLEFT end
			end
			assert.equal(204, found.slot)
		end)

		it("refreshes nothing before anything is open", function()
			LeanPadCrossbar:Hide()
			assert.has_no.errors(function() w.hooks[1].hook() end)
		end)
	end)
end)
