local wow = require("spec.wow")

describe("Dialogue window", function()
	local ns, w

	-- Every frame listening for the event hears it, Blizzard's own included, as in the client.
	local function fire(event, ...)
		for _, widget in ipairs(w.widgets) do
			if widget.events[event] and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, event, ...) end
		end
	end

	local function window() return rawget(_G, "LeanPadDialogue") end
	local function shown() return window() ~= nil and window():IsShown() end
	local function press(key) window().Input:Fire("OnGamePadButtonDown", key) end
	local function lastCall() return w.questCalls[#w.questCalls] end
	local function confirmText() return window().Confirm:IsShown() and window().Confirm.text or nil end

	-- The rows under the text, in order, and those showing.
	local function rows()
		local found = {}
		for _, widget in ipairs(w.widgets) do
			if widget.kind == "Button" and widget.parent == window() and rawget(widget, "Label") then
				if widget:IsShown() then table.insert(found, widget) end
			end
		end
		return found
	end

	local function labels()
		local found = {}
		for _, row in ipairs(rows()) do table.insert(found, row.Label.text) end
		return found
	end

	-- Events Blizzard's windows were handed, by name.
	local function blizzardGot(event)
		for _, entry in ipairs(w.forwarded) do
			if entry[2] == event then return entry end
		end
	end

	before_each(function()
		ns, w = wow.boot({ questPrompts = true }, nil)
	end)
	after_each(wow.restore)

	describe("taking over Blizzard's windows", function()
		it("is off on retail until turned on, leaving Blizzard's windows their events", function()
			ns, w = wow.boot({}, nil)
			assert.is_false(ns.QuestPromptsEnabled())
			fire("QUEST_DETAIL")
			assert.is_nil(window())
			assert.is_truthy(blizzardGot("QUEST_DETAIL"))
		end)

		it("stops Blizzard's windows hearing the events that open them, and only those", function()
			assert.is_nil(QuestFrame.events.QUEST_DETAIL)
			assert.is_nil(QuestFrame.events.QUEST_GREETING)
			assert.is_nil(CustomGossipFrameManager.events.GOSSIP_SHOW)
			assert.is_true(QuestFrame.events.QUEST_FINISHED)
			assert.is_true(CustomGossipFrameManager.events.GOSSIP_CLOSED)
		end)

		it("gives them back when turned off", function()
			ns.db.questPrompts = false
			ns.ClaimDialogues()
			assert.is_true(QuestFrame.events.QUEST_DETAIL)
			assert.is_true(CustomGossipFrameManager.events.GOSSIP_SHOW)
		end)

		it("stays out of Blizzard's Gamepad UI, which has its own", function()
			ns, w = wow.bootForever({}, nil)
			fire("QUEST_DETAIL")
			assert.is_nil(window())
			assert.is_true(QuestFrame.events.QUEST_DETAIL)
		end)

		it("can be turned off on Forever", function()
			ns, w = wow.bootForever({ questPrompts = false }, nil)
			w.gamepadUI = false
			fire("QUEST_DETAIL")
			assert.is_nil(window())
		end)

		it("leaves a window Blizzard already heard to Blizzard, and answers the next", function()
			ns, w = wow.bootForever({}, nil)
			w.gamepadUI = false
			fire("QUEST_DETAIL")
			assert.is_nil(window())
			fire("QUEST_DETAIL")
			assert.is_true(shown())
		end)

		it("hands back an event it can no longer answer, such as with the Gamepad UI turned on since", function()
			ns.db.questPrompts = false
			fire("GOSSIP_SHOW")
			assert.is_nil(window())
			assert.equal(CustomGossipFrameManager, blizzardGot("GOSSIP_SHOW")[1])
		end)

		it("steps aside for another dialogue addon", function()
			w.addons.DialogueUI = true
			fire("QUEST_DETAIL")
			assert.is_nil(window())
			assert.is_truthy(blizzardGot("QUEST_DETAIL"))
			assert.is_true(QuestFrame.events.QUEST_DETAIL)
		end)
	end)

	describe("pages Blizzard keeps", function()
		local function leftToBlizzard(event, ...)
			fire(event, ...)
			assert.is_false(shown())
			assert.is_truthy(blizzardGot(event))
		end

		it("leave a quest from an item to the tracker's pop-up", function() leftToBlizzard("QUEST_DETAIL", 6948) end)

		it("leave a quest from the adventure map on that map", function()
			w.quest.adventureMap = true
			leftToBlizzard("QUEST_DETAIL")
		end)

		it("leave a quest an area accepts to the tracker's pop-up", function()
			w.quest.autoAccept, w.quest.areaTrigger = true, true
			leftToBlizzard("QUEST_DETAIL")
		end)

		it("leave a gossip with its own look to its own frame", function()
			w.quest.handlers.skoldushall = true
			leftToBlizzard("GOSSIP_SHOW", "skoldushall")
		end)

		it("leave every gossip to a frame that took them all", function()
			CustomGossipFrameManager.baseHandler = true
			leftToBlizzard("GOSSIP_SHOW")
		end)

		it("let Blizzard pick a lone option marked to be picked without asking", function()
			w.quest.gossipOptions = { { name = "Fly", icon = 1, orderIndex = 0, selectOptionWhenOnlyOption = true } }
			leftToBlizzard("GOSSIP_SHOW")
		end)

		it("show that lone option when the NPC insists on talking", function()
			w.quest.gossipOptions = { { name = "Fly", icon = 1, orderIndex = 0, selectOptionWhenOnlyOption = true } }
			w.quest.forceGossip = true
			fire("GOSSIP_SHOW")
			assert.is_true(shown())
		end)
	end)

	describe("in combat", function()
		it("never opens, as Blizzard's windows hear the events again", function()
			w.combat = true
			fire("PLAYER_REGEN_DISABLED")
			assert.is_true(QuestFrame.events.QUEST_DETAIL)
			fire("QUEST_DETAIL")
			assert.is_nil(window())
			assert.is_truthy(blizzardGot("QUEST_DETAIL"))
		end)

		it("keeps an open window for the mouse but gives the pad back", function()
			fire("QUEST_DETAIL")
			w.combat = true
			fire("PLAYER_REGEN_DISABLED")
			assert.is_true(shown())
			assert.is_false(window().Input:IsShown())
			window().Confirm:Fire("OnClick")
			assert.same({ "AcceptQuest" }, lastCall())
		end)

		it("gives way to Blizzard's window for the next page", function()
			fire("QUEST_DETAIL")
			w.combat = true
			fire("PLAYER_REGEN_DISABLED")
			fire("QUEST_COMPLETE")
			assert.is_false(shown())
			assert.is_truthy(blizzardGot("QUEST_COMPLETE"))
		end)

		it("takes the pad and the events back once it ends", function()
			fire("QUEST_DETAIL")
			w.combat = true
			fire("PLAYER_REGEN_DISABLED")
			w.combat = false
			fire("PLAYER_REGEN_ENABLED")
			assert.is_true(window().Input:IsShown())
			assert.is_nil(QuestFrame.events.QUEST_DETAIL)
		end)
	end)

	describe("an NPC's gossip", function()
		before_each(function()
			w.quest.gossipAvailable = { { title = "Boars", questID = 11 } }
			w.quest.gossipActive = { { title = "Wolves", questID = 12, isComplete = true }, { title = "Bears", questID = 13 } }
			w.quest.gossipOptions = { { name = "Train me", icon = 7, orderIndex = 2 }, { name = "Tell me more", icon = 8, overrideIconID = 9, orderIndex = 1 } }
			fire("GOSSIP_SHOW")
		end)

		it("shows the NPC, their words and quests before options in Blizzard's order", function()
			assert.equal("Marshal Dughan", window().Name.text)
			assert.equal("npc", window().Portrait.portrait)
			assert.equal("Well met", window().Body.text)
			assert.equal("", window().Title.text)
			assert.same({ "Boars", "Wolves", "Bears", "Tell me more", "Train me" }, labels())
		end)

		it("marks quests to take, hand in and in progress, and options with their icons", function()
			local shownRows = rows()
			assert.equal("QuestNormal", shownRows[1].Icon.atlas)
			assert.equal("QuestTurnin", shownRows[2].Icon.atlas)
			assert.equal("Quest-In-Progress-Icon-yellow", shownRows[3].Icon.atlas)
			assert.equal(9, shownRows[4].Icon.texture)
			assert.equal(7, shownRows[5].Icon.texture)
		end)

		it("starts on the first line and chooses it on A", function()
			assert.equal("Select", confirmText())
			assert.equal("Choose", window().Hint.text)
			press("PAD1")
			assert.same({ "GossipAvailable", 11 }, lastCall())
			assert.is_false(window().Input.propagate)
		end)

		it("walks the lines with the D-pad, wrapping round", function()
			press("PADDDOWN")
			press("PAD1")
			assert.same({ "GossipActive", 12 }, lastCall())
			press("PADDUP")
			press("PADDUP")
			press("PAD1")
			assert.same({ "GossipOption", 2 }, lastCall())
			assert.is_false(window().Input.propagate)
		end)

		it("says goodbye on B", function()
			press("PAD2")
			assert.same({ "CloseGossip" }, lastCall())
			assert.equal("Goodbye", window().Back.text)
		end)

		it("chooses a line clicked with the mouse", function()
			rows()[5]:Fire("OnClick")
			assert.same({ "GossipOption", 2 }, lastCall())
		end)

		it("leaves other buttons, and every button under a cursor the player brought up, to their bindings", function()
			press("PAD3")
			assert.is_true(window().Input.propagate)
			w.cursorControl = true
			press("PAD1")
			assert.equal(0, #w.questCalls)
			assert.is_true(window().Input.propagate)
		end)

		it("ends the conversation when Escape or Blizzard closes every window", function()
			window():Hide()
			assert.same({ "CloseGossip" }, lastCall())
			fire("GOSSIP_SHOW")
			assert.is_true(shown())
		end)
	end)

	describe("a lone gossip line", function()
		it("leaves the D-pad to its bindings, as there is nothing to choose", function()
			w.quest.gossipOptions = { { name = "Bye", icon = 1, orderIndex = 0 } }
			fire("GOSSIP_SHOW")
			assert.equal("", window().Hint.text)
			press("PADDDOWN")
			assert.is_true(window().Input.propagate)
		end)

		it("offers nothing to select when the NPC only talks", function()
			fire("GOSSIP_SHOW")
			assert.is_nil(confirmText())
			press("PAD1")
			assert.equal(0, #w.questCalls)
		end)
	end)

	describe("a quest giver's greeting", function()
		before_each(function()
			w.quest.available = { "Boars" }
			w.quest.active = { { "Wolves", true } }
			fire("QUEST_GREETING")
		end)

		it("lists quests to take and to hand in", function()
			assert.equal("Hello", window().Body.text)
			assert.same({ "Boars", "Wolves" }, labels())
			assert.equal("QuestTurnin", rows()[2].Icon.atlas)
		end)

		it("opens the one chosen", function()
			press("PAD1")
			assert.same({ "SelectAvailableQuest", 1 }, lastCall())
			press("PADDDOWN")
			press("PAD1")
			assert.same({ "SelectActiveQuest", 1 }, lastCall())
		end)

		it("says goodbye on B", function()
			press("PAD2")
			assert.same({ "CloseQuest" }, lastCall())
		end)
	end)

	describe("a quest offer", function()
		it("shows the quest, its objectives and rewards, with nothing chosen", function()
			w.quest.choices = { { "Sword", 101, 1 } }
			w.quest.rewards = { { "Potion", 102, 3 }, { nil, 103, 1 } }
			w.quest.rewardMoney, w.quest.xp = 500, 1200
			fire("QUEST_DETAIL")
			assert.equal("A Quest", window().Title.text)
			assert.equal("Quest text\n\n|cfff6b73cObjectives|r\nKill ten boars", window().Body.text)
			assert.same({ "Sword", "Potion x3", "..." }, labels())
			assert.equal(101, rows()[1].Icon.texture)
			assert.equal("500c    1200 XP", window().Money.text)
			assert.is_nil(w.tooltip)
		end)

		it("offers a currency among the choices, with its own tooltip", function()
			w.quest.choices = { { "Sword", 101, 1 }, {} }
			w.quest.currencyChoices[2] = { name = "Valorstones", texture = 201, totalRewardAmount = 25 }
			fire("QUEST_DETAIL")
			assert.same({ "Sword", "Valorstones x25" }, labels())
			press("PADDUP")
			assert.same({ "choice", 2 }, w.tooltip.questCurrency)
			assert.is_nil(w.tooltip.compared)
		end)

		it("lists fixed currencies and spells not known yet, and honor and renown with the gold", function()
			w.quest.currencies = { { name = "Resonance Crystals", texture = 202, totalRewardAmount = 100 } }
			w.quest.spells = { { 301, { name = "Portal", texture = 203 } }, { 302, { name = "Known", texture = 204 } }, { 303 } }
			w.quest.knownSpells[302] = true
			w.quest.honor = 50
			w.quest.reputation = { { factionID = 2590, rewardAmount = 250 }, { factionID = 1, rewardAmount = 10 } }
			fire("QUEST_DETAIL")
			assert.same({ "Resonance Crystals x100", "Portal" }, labels())
			assert.equal("50 Honor    Council of Dornogal +250", window().Money.text)
			press("PADDDOWN")
			assert.same({ "reward", 1 }, w.tooltip.questCurrency)
			press("PADDDOWN")
			assert.equal(301, w.tooltip.spell)
		end)

		it("accepts on A and declines on B", function()
			fire("QUEST_DETAIL")
			assert.equal("Accept", confirmText())
			assert.equal("Decline", window().Back.text)
			press("PAD1")
			assert.same({ "AcceptQuest" }, lastCall())
			press("PAD2")
			assert.same({ "CloseQuest" }, lastCall())
		end)

		it("only acknowledges a quest that accepts itself, on either button", function()
			w.quest.autoAccept = true
			fire("QUEST_DETAIL")
			assert.equal("OK", confirmText())
			assert.equal("Goodbye", window().Back.text)
			press("PAD1")
			assert.same({ "AcknowledgeAutoAcceptQuest" }, lastCall())
			press("PAD2")
			assert.equal(2, #w.questCalls)
			assert.same({ "AcknowledgeAutoAcceptQuest" }, lastCall())
		end)

		it("takes a second press to accept a PvP quest", function()
			w.quest.pvp = true
			fire("QUEST_DETAIL")
			assert.equal("Accept (PvP)", confirmText())
			press("PAD1")
			assert.equal(0, #w.questCalls)
			assert.equal("Confirm", confirmText())
			press("PAD1")
			assert.same({ "AcceptQuest" }, lastCall())
		end)

		it("shows a reward's tooltip and comparison as the D-pad reaches it", function()
			w.quest.choices = { { "Sword", 101, 1 }, { "Axe", 104, 1 } }
			fire("QUEST_DETAIL")
			press("PADDUP")
			assert.same({ "choice", 2 }, w.tooltip.questItem)
			assert.equal(rows()[2], w.tooltip.owner)
			assert.is_true(w.tooltip.compared)
			press("PADDDOWN")
			assert.same({ "choice", 1 }, w.tooltip.questItem)
			fire("QUEST_FINISHED")
			assert.is_nil(w.tooltip)
		end)

		it("still lets the D-pad reach a lone reward's tooltip", function()
			w.quest.rewards = { { "Potion", 102, 1 } }
			fire("QUEST_DETAIL")
			press("PADDDOWN")
			assert.same({ "reward", 1 }, w.tooltip.questItem)
			press("PADDDOWN")
			assert.is_true(window().Input.propagate)
		end)

		it("leaves the D-pad to its bindings with no rewards", function()
			fire("QUEST_DETAIL")
			press("PADDUP")
			assert.is_true(window().Input.propagate)
		end)

		it("names no NPC for a quest offered with nobody there", function()
			w.quest.npc = nil
			fire("QUEST_DETAIL")
			assert.equal("", window().Name.text)
			assert.equal("Interface\\QuestFrame\\UI-QuestLog-BookIcon", window().Portrait.texture)
		end)

		it("redraws as item details arrive, and ignores them when closed", function()
			w.quest.rewards = { { nil, 102, 1 } }
			fire("QUEST_DETAIL")
			w.quest.rewards = { { "Potion", 102, 1 } }
			fire("QUEST_ITEM_UPDATE")
			assert.same({ "Potion" }, labels())
			fire("QUEST_FINISHED")
			assert.has_no.errors(function() fire("QUEST_ITEM_UPDATE") end)
		end)

		it("scrolls text taller than the window with the bumpers, and the mouse wheel", function()
			fire("QUEST_DETAIL")
			press("PADRSHOULDER")
			assert.is_true(window().Input.propagate)
			window().Body.stringHeight = 400
			window().Scroll.scrollRange = 100
			fire("QUEST_ITEM_UPDATE")
			assert.equal("Scroll", window().Hint.text)
			press("PADRSHOULDER")
			assert.equal(60, window().Scroll.verticalScroll)
			assert.is_false(window().Input.propagate)
			press("PADRSHOULDER")
			assert.equal(100, window().Scroll.verticalScroll)
			window().Scroll:Fire("OnMouseWheel", 1)
			assert.equal(40, window().Scroll.verticalScroll)
			press("PADLSHOULDER")
			assert.equal(0, window().Scroll.verticalScroll)
		end)

		it("starts each page scrolled to the top", function()
			fire("QUEST_DETAIL")
			window().Scroll.verticalScroll = 80
			fire("QUEST_COMPLETE")
			assert.equal(0, window().Scroll.verticalScroll)
		end)
	end)

	describe("quest progress", function()
		it("lists what's needed and continues on A once the quest can be completed", function()
			w.quest.required = { { "Boar Hide", 105, 10 } }
			w.quest.money = 300
			fire("QUEST_PROGRESS")
			assert.equal("Got them?", window().Body.text)
			assert.same({ "Boar Hide x10" }, labels())
			assert.equal("Costs 300c", window().Money.text)
			assert.equal("Continue", confirmText())
			press("PAD1")
			assert.same({ "CompleteQuest" }, lastCall())
		end)

		it("offers no confirm while it can't, and takes A to do nothing", function()
			w.quest.completable = false
			fire("QUEST_PROGRESS")
			assert.is_nil(confirmText())
			press("PAD1")
			assert.equal(0, #w.questCalls)
			assert.is_false(window().Input.propagate)
		end)
	end)

	describe("handing in a quest", function()
		it("completes on A with no reward to choose, or the only one", function()
			fire("QUEST_COMPLETE")
			assert.equal("Well done", window().Body.text)
			press("PAD1")
			assert.same({ "GetQuestReward", 0 }, lastCall())
			w.quest.choices = { { "Sword", 101, 1 } }
			fire("QUEST_COMPLETE")
			press("PAD1")
			assert.same({ "GetQuestReward", 1 }, lastCall())
		end)

		it("won't complete until one of several rewards is chosen, and takes that one", function()
			w.quest.choices = { { "Sword", 101, 1 }, { "Axe", 104, 1 } }
			w.quest.rewards = { { "Potion", 102, 1 } }
			fire("QUEST_COMPLETE")
			assert.is_nil(confirmText())
			press("PAD1")
			assert.equal(0, #w.questCalls)
			press("PADDUP")
			assert.is_nil(confirmText()) -- the fixed reward, not a choice
			press("PADDUP")
			assert.equal("Complete", confirmText())
			press("PAD1")
			assert.same({ "GetQuestReward", 2 }, lastCall())
		end)

		it("takes a reward clicked with the mouse as chosen, without completing", function()
			w.quest.choices = { { "Sword", 101, 1 }, { "Axe", 104, 1 } }
			fire("QUEST_COMPLETE")
			rows()[1]:Fire("OnClick")
			assert.equal(0, #w.questCalls)
			window().Confirm:Fire("OnClick")
			assert.same({ "GetQuestReward", 1 }, lastCall())
		end)

		it("takes a second press for a quest that costs gold, and shows the cost", function()
			w.quest.money, w.quest.rewardMoney = 300, 50
			fire("QUEST_COMPLETE")
			assert.equal("50c    Costs 300c", window().Money.text)
			assert.equal("Complete (costs gold)", confirmText())
			press("PAD1")
			assert.equal(0, #w.questCalls)
			press("PAD1")
			assert.same({ "GetQuestReward", 0 }, lastCall())
		end)

		it("says goodbye from the Back button too", function()
			fire("QUEST_COMPLETE")
			window().Back:Fire("OnClick")
			assert.same({ "CloseQuest" }, lastCall())
		end)
	end)

	describe("closing", function()
		it("closes with its own conversation", function()
			fire("QUEST_DETAIL")
			fire("QUEST_FINISHED")
			assert.is_false(shown())
			fire("GOSSIP_SHOW")
			fire("GOSSIP_CLOSED")
			assert.is_false(shown())
		end)

		it("survives a gossip closing as the quest it led to opens", function()
			fire("GOSSIP_SHOW")
			fire("QUEST_DETAIL")
			fire("GOSSIP_CLOSED")
			assert.is_true(shown())
			assert.equal("A Quest", window().Title.text)
		end)

		it("survives a quest finishing as its gossip reopens", function()
			fire("QUEST_DETAIL")
			fire("GOSSIP_SHOW")
			fire("QUEST_FINISHED")
			assert.is_true(shown())
		end)

		it("ends a quest when Escape closes it", function()
			fire("QUEST_DETAIL")
			window():Hide()
			assert.same({ "CloseQuest" }, lastCall())
		end)

		it("copes with a close before anything opened", function()
			assert.has_no.errors(function() fire("QUEST_FINISHED") end)
		end)

		it("is one of the windows Escape closes", function()
			fire("QUEST_DETAIL")
			assert.same({ "LeanPadDialogue" }, UISpecialFrames)
		end)
	end)

	describe("the camera", function()
		it("stays put unless turned on", function()
			fire("QUEST_DETAIL")
			assert.equal(15, w.zoom)
		end)

		it("zooms in on the NPC and back out once the talking is done", function()
			ns.db.dialogueCamera = true
			fire("GOSSIP_SHOW")
			assert.equal(4, w.zoom)
			fire("QUEST_DETAIL")
			fire("GOSSIP_CLOSED")
			wow.nextFrame()
			assert.equal(4, w.zoom) -- one conversation, gossip into a quest
			fire("QUEST_FINISHED")
			wow.nextFrame()
			assert.equal(15, w.zoom)
		end)

		it("leaves a camera already that close", function()
			ns.db.dialogueCamera = true
			w.zoom = 3
			fire("QUEST_DETAIL")
			fire("QUEST_FINISHED")
			wow.nextFrame()
			assert.equal(3, w.zoom)
		end)
	end)
end)
