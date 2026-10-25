local wow = require("spec.wow")

describe("Profiles", function()
	local ns, w

	-- A Beast Mastery hunter with a pad layout: Jump on A, Action Bar 1 slot 1 on X, Action Bar 2 slot 1 on LT+A.
	local function setUp(db, char)
		ns, w = wow.boot(db or { prompted = true, crossbarScale = 0.8, backup = { cvars = {}, bindings = {} }, formPages = { [7] = { spell = 768 } } }, char)
		w.bindings = { PAD1 = "JUMP", PAD3 = "ACTIONBUTTON1", ["SHIFT-PAD1"] = "MULTIACTIONBAR1BUTTON1" }
		w.cvars = { GamePadEmulateShift = "PADLTRIGGER", SoftTargetFriend = "0", GamePadSingleActiveID = "2" }
		w.actions[1] = { kind = "macro", id = 7, text = "Mount up" }
		w.actions[73] = { kind = "spell", id = 5221 } -- Action Bar 1 slot 1 on Cat Form's page
	end

	local function watcher()
		for _, widget in ipairs(w.widgets) do
			if widget.events.PLAYER_LOGOUT then return widget end
		end
	end

	local function printed(text)
		for _, line in ipairs(w.printed) do
			if line == text then return true end
		end
		return false
	end

	-- A list in a fixed order, since slots are put back in table order.
	local function sorted(list)
		table.sort(list, function(a, b) return tostring(type(a) == "table" and a[2] or a) < tostring(type(b) == "table" and b[2] or b) end)
		return list
	end

	before_each(function()
		setUp()
		wow.fire("PLAYER_ENTERING_WORLD")
	end)
	after_each(wow.restore)

	describe("migration", function()
		it("turns the old settings into Default, used by the first character to log in", function()
			local default = ns.db.profiles.Default
			assert.equal("Default", LeanPadCharDB.profile)
			assert.equal(0.8, default.settings.crossbarScale)
			for _, key in ipairs({ "prompted", "backup", "formPages", "profiles" }) do assert.is_nil(default.settings[key], key) end
			assert.same(w.bindings, default.bindings)
			assert.equal("PADLTRIGGER", default.cvars.GamePadEmulateShift)
			assert.equal("0", default.cvars.SoftTargetFriend)
			assert.is_nil(default.cvars.GamePadSingleActiveID) -- the active pad stays out
			assert.same({ [1] = { "macro", "Mount up" }, [61] = { "spell", 1953 }, [73] = { "spell", 5221 } }, default.slots[253])
			assert.is_true(ns.db.prompted)
		end)

		it("keeps no bar slots when there is no spec yet", function()
			setUp()
			w.spec = nil
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.same({}, ns.db.profiles.Default.slots)
		end)
	end)

	describe("login", function()
		local tank = { settings = { crossbarScale = 1.2 }, cvars = { SoftTargetFriend = "1" }, bindings = { PAD1 = "JUMP" }, all = true, slots = { [253] = { [61] = { "spell", 1953 } } } }

		it("puts the character's profile in place, as another character may have changed it", function()
			setUp({ prompted = true, padStyle = "xbox", profiles = { Tank = tank } }, { profile = "Tank", specs = {} })
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.equal(1.2, ns.db.crossbarScale)
			assert.is_nil(ns.db.padStyle)
			assert.is_true(ns.db.prompted)
			assert.same({ PAD1 = "JUMP" }, w.bindings)
			assert.equal("1", w.cvars.SoftTargetFriend)
			assert.same({}, w.placed) -- the slot already holds it
			assert.equal(1.2, LeanPadCrossbar.scale)
		end)

		it("waits for combat to end after a reload in combat", function()
			setUp({ prompted = true, profiles = { Tank = tank } }, { profile = "Tank", specs = {} })
			w.combat = true
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(ns.db.crossbarScale)
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal(1.2, ns.db.crossbarScale)
		end)

		it("lets go of a profile deleted or renamed on another character, and leaves the setup alone", function()
			setUp({ prompted = true, profiles = { Tank = tank } }, { profile = "Gone", specs = {} })
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(LeanPadCharDB.profile)
			assert.equal("JUMP", w.bindings.PAD1)
			assert.equal("ACTIONBUTTON1", w.bindings.PAD3)
		end)

		it("leaves a new character without a profile until it picks one", function()
			setUp({ prompted = true, profiles = { Tank = tank } }, nil)
			wow.fire("PLAYER_ENTERING_WORLD")
			assert.is_nil(LeanPadCharDB.profile)
			assert.same({}, LeanPadCharDB.specs)
			assert.equal("ACTIONBUTTON1", w.bindings.PAD3)
		end)
	end)

	it("saves the profile in use at logout and reload", function()
		ns.db.crossbarScale = 1.1
		w.actions[1] = nil
		watcher():Fire("OnEvent", "PLAYER_LOGOUT")
		assert.equal(1.1, ns.db.profiles.Default.settings.crossbarScale)
		assert.is_false(ns.db.profiles.Default.slots[253][1])
	end)

	describe("managing", function()
		it("makes a profile from the current setup and uses it", function()
			ns.NewProfile("  Tank  ")
			assert.equal("Tank", LeanPadCharDB.profile)
			assert.same(ns.db.profiles.Default, ns.db.profiles.Tank)
			assert.is_true(printed("LeanPad: profile Tank made from your current setup, and in use."))
			assert.same({ "Default", "Tank" }, ns.ProfileNames())
		end)

		it("refuses a blank name or one already taken", function()
			ns.NewProfile("   ")
			ns.NewProfile("Default")
			assert.same({ "Default" }, ns.ProfileNames())
			assert.is_true(printed("LeanPad: there is already a profile named Default."))
		end)

		it("copies the profile in use without switching", function()
			ns.db.crossbarScale = 1.1
			ns.CopyProfile("Healer")
			assert.equal("Default", LeanPadCharDB.profile)
			assert.equal(1.1, ns.db.profiles.Healer.settings.crossbarScale)
			assert.same(ns.db.profiles.Default, ns.db.profiles.Healer)
			assert.are_not.equal(ns.db.profiles.Default, ns.db.profiles.Healer)
			ns.CopyProfile("Default")
			assert.same({ "Default", "Healer" }, ns.ProfileNames())
		end)

		it("renames the profile in use, its spec links along", function()
			ns.LinkSpec(254, "Default")
			ns.LinkSpec(255, "Other")
			ns.RenameProfile("Main")
			assert.same({ "Main" }, ns.ProfileNames())
			assert.equal("Main", LeanPadCharDB.profile)
			assert.same({ [254] = "Main", [255] = "Other" }, LeanPadCharDB.specs)
			ns.RenameProfile("")
			assert.same({ "Main" }, ns.ProfileNames())
		end)

		it("deletes a profile and its links, keeping the setup as it is", function()
			ns.CopyProfile("Healer")
			ns.LinkSpec(254, "Default")
			ns.LinkSpec(255, "Healer")
			ns.DeleteProfile("Healer")
			assert.equal("Default", LeanPadCharDB.profile)
			assert.same({ [254] = "Default" }, LeanPadCharDB.specs)
			ns.DeleteProfile("Default")
			assert.is_nil(LeanPadCharDB.profile)
			assert.same({}, LeanPadCharDB.specs)
			assert.same({}, ns.ProfileNames())
			assert.equal("ACTIONBUTTON1", w.bindings.PAD3)
			assert.is_true(printed("LeanPad: profile Default deleted."))
		end)
	end)

	describe("switching", function()
		before_each(function()
			ns.NewProfile("Healer")
			ns.db.crossbarScale = 1.2
			w.bindings.PAD1 = nil
			w.cvars.SoftTargetFriend = "1"
			w.actions[61] = { kind = "item", id = 5512 }
			w.actions[1] = nil
			w.saved = {}
		end)

		it("saves the profile in use, then puts the other's settings, bindings, CVars and bar slots in place", function()
			ns.SwitchProfile("Default")
			local healer = ns.db.profiles.Healer
			assert.equal(1.2, healer.settings.crossbarScale)
			assert.is_nil(healer.bindings.PAD1)
			assert.equal("1", healer.cvars.SoftTargetFriend)
			assert.same({ [1] = false, [61] = { "item", 5512 }, [73] = { "spell", 5221 } }, healer.slots[253])

			assert.equal("Default", LeanPadCharDB.profile)
			assert.equal(0.8, ns.db.crossbarScale)
			assert.equal("JUMP", w.bindings.PAD1)
			assert.equal("0", w.cvars.SoftTargetFriend)
			assert.same({ 1 }, w.saved)
			assert.same({ 1, 61 }, sorted(w.placed))
			assert.same({ { "macro", 1 }, { "spellID", 1953 } }, sorted(w.pickups))
			assert.is_nil(w.cursor)
			assert.is_true(printed("LeanPad: profile Default in use."))
		end)

		it("empties a slot the profile has empty, and leaves alone what already matches", function()
			ns.SwitchProfile("Default")
			w.actions[1] = { kind = "macro", id = 7, text = "Mount up" }
			w.actions[61] = { kind = "spell", id = 1953 }
			w.placed, w.pickups, w.saved = {}, {}, {}
			ns.SwitchProfile("Healer")
			assert.same({ 61 }, w.placed)
			assert.same({ { "action", 1 }, { "item", 5512 } }, sorted(w.pickups))
			w.placed, w.pickups, w.saved = {}, {}, {}
			ns.SwitchProfile("Healer") -- already in place: nothing to write
			assert.same({}, w.placed)
			assert.same({}, w.saved)
		end)

		it("leaves slots it can't fill as they were, and says so in one line", function()
			ns.db.profiles.Default.slots[253] = {
				[1] = { "macro", "Gone" }, [2] = { "macro", "Focus" }, [61] = { "spell", 999 }, [62] = { "item", 6948 }, [63] = { "summonmount", 1 },
			}
			w.unavailable[999], w.unavailable[6948] = true, true
			ns.SwitchProfile("Default")
			assert.same({ 2 }, w.placed) -- Focus, a character macro, is there
			assert.same({ { "macro", 121 } }, w.pickups)
			assert.is_true(printed("LeanPad: Default has a spell, macro or item this character doesn't have in 4 bar slot(s); they were left as they were."))
		end)

		it("waits for combat to end", function()
			w.combat = true
			ns.SwitchProfile("Default")
			assert.equal("Healer", LeanPadCharDB.profile)
			assert.is_true(printed("LeanPad: will apply when combat ends."))
			w.combat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			assert.equal("Default", LeanPadCharDB.profile)
		end)

		it("says so for a profile that doesn't exist", function()
			ns.SwitchProfile("Nope")
			assert.equal("Healer", LeanPadCharDB.profile)
			assert.is_true(printed("LeanPad: no profile named Nope."))
		end)

		it("redraws the controller window and sizes it to the profile", function()
			ns.db.profiles.Default.settings.windowScale = 1.1
			ns.ToggleController()
			ns.SwitchProfile("Default")
			assert.equal(1.1, LeanPadControllerFrame.scale)
		end)

		it("by /lp profile and a name", function()
			SlashCmdList.LEANPAD("profile Default ")
			assert.equal("Default", LeanPadCharDB.profile)
		end)

		it("saves the layout of a character without a profile for Undo reset first", function()
			ns.DeleteProfile("Healer")
			ns.db.undo = nil
			ns.SwitchProfile("Default")
			assert.equal("Default", LeanPadCharDB.profile)
			assert.equal("ACTIONBUTTON1", ns.db.undo.bindings.PAD3)
			assert.is_nil(ns.db.undo.bindings.PAD1)
		end)
	end)

	describe("spec links", function()
		before_each(function()
			ns.NewProfile("Tank")
			ns.LinkSpec(254, "Default")
			w.spec, w.specID = 2, 254
			w.actions[61] = { kind = "item", id = 5512 }
		end)

		it("switch to the linked profile on spec change, leaving the bars to WoW", function()
			watcher():Fire("OnEvent", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
			assert.equal("Default", LeanPadCharDB.profile)
			assert.same({}, w.placed)
			assert.is_nil(ns.db.profiles.Tank.slots[254])
			assert.is_truthy(ns.db.profiles.Tank.slots[253])
			assert.is_true(printed("LeanPad: profile Default in use."))
		end)

		it("leave the profile alone on a spec with no link, or one linked to the profile in use", function()
			ns.LinkSpec(254, false)
			watcher():Fire("OnEvent", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
			assert.equal("Tank", LeanPadCharDB.profile)
			ns.LinkSpec(254, "Tank")
			watcher():Fire("OnEvent", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
			assert.is_false(printed("LeanPad: profile Tank in use."))
		end)
	end)

	describe("on the settings page", function()
		local dropdown

		local function open()
			ns.OpenOptions()
			for _, widget in ipairs(w.widgets) do
				if widget.parent == LeanPadControllerFrame.Options and rawget(widget, "Label") and widget.Label:GetText():find("^Profile: ") then dropdown = widget end
			end
			dropdown:Fire("OnClick")
			return w.menu.root
		end

		local function labels(description)
			local list = {}
			for _, entry in ipairs(description.entries) do table.insert(list, entry.text or "-") end
			return list
		end

		it("lists the profiles, what can be done with the one in use, and a link per spec", function()
			ns.LinkSpec(253, "Default")
			local root = open()
			assert.equal("Profile: Default", dropdown.Label:GetText())
			assert.same({ "Default", "-", "New from current setup...", "Copy...", "Rename...", "Delete...", "-", "Beast Mastery: Default", "Marksmanship: None", "Survival: None" }, labels(root))
			assert.same({ "Switch profile when you change spec" }, root.titles)
			assert.is_true(root.entries[1].selected())
			local link = wow.entry(root, "Marksmanship: None")
			assert.same({ "None", "Default" }, labels(link))
			assert.is_true(link.entries[1].selected())
			link.entries[2].callback()
			assert.equal("Default", LeanPadCharDB.specs[254])
		end)

		it("names new, copied and renamed profiles in Blizzard's input box", function()
			local root = open()
			wow.entry(root, "New from current setup...").callback()
			assert.equal("input", w.dialog.kind)
			w.dialog.data.callback("Tank")
			assert.equal("Tank", LeanPadCharDB.profile)
			assert.equal("Profile: Tank", dropdown.Label:GetText())
			wow.entry(open(), "Copy...").callback()
			assert.equal("Name the copy of %s.", w.dialog.data.text)
			assert.equal("Tank", w.dialog.data.text_arg1)
			w.dialog.data.callback("Tank 2")
			wow.entry(open(), "Rename...").callback()
			w.dialog.data.callback("Bear")
			assert.same({ "Bear", "Default", "Tank 2" }, ns.ProfileNames())
			assert.equal("Profile: Bear", dropdown.Label:GetText())
		end)

		it("switches, and deletes after asking", function()
			ns.NewProfile("Tank")
			local root = open()
			root.entries[1].callback() -- Default
			assert.equal("Default", LeanPadCharDB.profile)
			assert.equal("Profile: Default", dropdown.Label:GetText())
			wow.entry(open(), "Delete...").callback()
			assert.equal("confirm", w.dialog.kind)
			assert.equal("Default", w.dialog.data.text_arg1)
			w.dialog.data.callback()
			assert.same({ "Tank" }, ns.ProfileNames())
			assert.equal("Profile: None", dropdown.Label:GetText())
			assert.same({ "Tank", "-", "New from current setup...", "-", "Beast Mastery: None", "Marksmanship: None", "Survival: None" }, labels(open()))
		end)
	end)
end)
