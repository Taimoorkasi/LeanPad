# Changelog

All notable changes to LeanPad are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- *Auto-run* and *Toggle gamepad cursor* show their icons in the editor again, instead of a blank button.

## [0.7.0] - 2026-11-08

Everything since 0.6.0, the 0.7.0-beta.1 changes for WoW: Forever included.

### Added

- **Talk to NPCs and do quests from the pad, in LeanPad's own window.** It stands in for Blizzard's gossip and quest windows: the NPC beside their words in 3D, talking, or as a round portrait, the quest's title in Blizzard's quest lettering, and the words in a column short enough to read at a glance, writing themselves in. A confirms, B backs out, the D-pad chooses and the bumpers scroll long text; the first A shows text still writing in. Rewards show as tiles in their quality's colour, every kind of them: items, currency choices, currencies, spells not known yet, gold, XP, honor and renown. Choosing one shows its tooltip and how it compares with what you wear, and a quest with several won't complete until you pick one. PvP quests and quests that cost gold take a second press of A. Escape and the Menu button end the conversation. In combat, new conversations open in Blizzard's windows, so the pad stays on your abilities. Quests from items, areas and the adventure map, and NPCs with frames of their own, still use Blizzard's. On by default on Forever and off on retail.
- **Pop-ups from the pad.** The buttons showing on Blizzard's pop-ups, the dungeon queue pop and ready checks go to A, B, X and Y from left to right, named under the pop-up, such as Release Spirit and Recap when you die. The presses count as your own clicks, so entering a dungeon works. Pop-ups that show in combat wait for the cursor.
- **Settings in two tabs, Controls and Dialogue**, and every setting says what it does when you hover the (i) after its name. *Dialogue* sets the window on or off, its place (any of nine, from top left to bottom right), its size and text size, the 3D NPC, the writing-in, an optional camera zoom on the NPC, and pop-ups. *Show or hide* previews the window in place, following changes as you make them.
- **WoW: Forever support.** With Forever's Gamepad UI on, LeanPad's crossbar and editor work on Blizzard's gamepad bars and keep its menus, radials and targeting: Base, LT, RT and LT+RT are its top, left, right and bottom bars, across its three pages. With the Gamepad UI off, LeanPad works as it does on retail. If the Gamepad UI is on when you log in, LeanPad suggests turning it off, since LeanPad does more without it, says where the setting is, and offers its layout setup once you have.
- **Show empty buttons.** A crossbar setting that draws every button in the layout as a faint socket before anything is bound, as Blizzard's Show Empty Action Bars does. On by default on Forever and off on retail.

### Changed

- **Stick clicks on the crossbar** show only when they hold a bar action, not a command such as Interact.
- **Crossbar proportions.** The D-pad and face diamonds are wider than tall, and the stacked sockets between them are spaced so their glyphs clear the button above. Buttons you've dragged stay where you put them.
- **Clearer Jump and Interact icons.** Interact uses the game's own interact cursor, Jump is a new drawing, and on Forever Jump uses Blizzard's gamepad icon.
- **Auto play style on Forever** treats Mage, Hunter, Priest and Warlock as ranged. Each class there has one spec, so choose a tank or healer style by hand.
- **GitHub's source archives** no longer include the design notes.

### Fixed

- In Edit Mode, the unlocked crossbar no longer blocks clicks on the frames under its empty space. Only the strip with its hint and *Reset layout* takes the mouse.
- *Toggle gamepad cursor* no longer raises an error on every press when a start spot is set. The game now refuses to move the cursor from a key binding, so the cursor comes up where it was instead.

## [0.7.0-beta.1] - 2026-11-05

### Added

- **WoW: Forever support.** With Forever's Gamepad UI on, LeanPad's crossbar and editor work on Blizzard's gamepad bars and keep its menus, radials and targeting: Base, LT, RT and LT+RT are its top, left, right and bottom bars, across its three pages. With the Gamepad UI off, LeanPad works as it does on retail. If the Gamepad UI is on when you log in, LeanPad suggests turning it off, since LeanPad does more without it, says where the setting is, and offers its layout setup once you have.
- **Answer quests with the pad.** While a quest or NPC window is open, A confirms, B backs out and the D-pad chooses a quest, a gossip line or a reward, with the buttons named under the window in place of Blizzard's own. Choosing a reward highlights it and shows its tooltip, as hovering with the mouse does. On by default on Forever and off on retail, under *Quests* on the settings page. It steps aside for a cursor you bring up, in combat, and for Blizzard's Gamepad UI, which does this itself.
- **Show empty buttons.** A new crossbar setting draws every button in the layout as a faint socket before anything is bound, as Blizzard's Show Empty Action Bars does. On by default on Forever and off on retail.

### Changed

- **Stick clicks on the crossbar** now show only when they hold a bar action, not a command such as Interact.
- **Crossbar proportions.** The D-pad and face diamonds are wider than tall, and the stacked sockets between them are spaced so their glyphs clear the button above. Buttons you've dragged stay where you put them.
- **Clearer Jump and Interact icons.** Interact uses the game's own interact cursor, Jump is a new drawing, and on Forever Jump uses Blizzard's gamepad icon.
- **Auto play style on Forever** treats Mage, Hunter, Priest and Warlock as ranged. Each class there has one spec, so choose a tank or healer style by hand.
- **GitHub's source archives** no longer include the design notes.

## [0.6.0] - 2026-10-26

### Added

- **Five new crossbar styles**, picked from *View* on the settings page. *One row*: LB and the D-pad under the left thumb, the face buttons and RB under the right, in a single action-bar row. *One row, faint*: the same row, faint until you hold a layer button. *Square grid*: square tiles in two rows of five under the character, each column one direction (left, up, right, down, with X, Y, B, A under them), the bumpers beside them. *Square rows*: a tight square row per layer, Base on top. *Stacked rows*: a round row per layer, Base at the bottom. In the row styles the layer you hold comes to the front and the rest fade back. Each style keeps its own dragged layout, and *Reset layout* resets only the style shown.
- **Click the crossbar to cast.** With *Mouse* on in the crossbar settings, clicking a socket casts what it holds, in combat too, as a click on an action bar does. Holding a layer button while clicking fires that layer, as the pad does, and Action Bar 1 follows forms and stances. Drag-and-drop and tooltips work as before.
- **Profiles.** A profile is your whole controller setup under a name: LeanPad's settings and crossbar layout, the controller bindings on every layer, the controller CVars and what the bar slots your pad fires hold. Make one from your current setup, copy, rename or delete it, and switch from the *Profile* menu at the top of the settings page or with `/lp profile <name>`. Link each spec to a profile, say Guardian to Tank and Feral to DPS, and LeanPad switches when you change spec, once combat ends. Profiles are shared by all your characters; each character remembers its own and its spec links. Your current setup becomes the *Default* profile, nothing lost. The profile in use saves itself when you switch away and when you log out or reload. Bar slots are kept per spec, so one profile serves every class that uses it; a spell, macro or item the character doesn't have leaves its slot as it was, and LeanPad says so in one line.

### Fixed

- **Pad buttons on Action Bars 2-8 work alongside ElvUI and other bar addons.** These addons send bar keys to their own buttons, so a pad button bound to a bar they had turned off, such as ElvUI's Bar 13 for Action Bar 6, gave a vibration and cast nothing, while the crossbar showed the spell. LeanPad now gives those pad keys their Blizzard binding back, so a press always fires the slot the crossbar shows. Action Bar 1 stays with the bar addon, which pages it for forms and stances. Without a bar addon nothing changes.
- The editor's *Base* form menu fits under its picker instead of running out of the window over the layer buttons, and settings dropdowns keep long choices inside their box.
- A pad button on Blizzard's mouse-button commands reads *Left-click: select, camera* or *Right-click: interact, turn* in the editor, not CAMERAORSELECTORMOVE or TURNORACTION.

## [0.5.0] - 2026-10-24

### Added

- **Proc glows on the crossbar.** When a proc lights a spell, its socket lights a round gold glow that pops in and breathes, with a spark running round it: the round take on Blizzard's square spell alert, macros included.
- *Toggle gamepad cursor* and *Interact with target* head the editor's Commands menu, instead of sitting deep in Blizzard's categories.
- **Cursor start spot.** *Settings > Cursor* takes an x, y offset from the screen's centre, in UI units as frames are placed, and *Toggle gamepad cursor* puts the cursor there each time it turns it on. *Pick...* sets it on screen: lines cross at the centre, a ring marks the spot set now, and a click sets the new one. Left blank, the cursor stays where it was.
- **Window size** beside the settings page title, 80% to 125%, sizes LeanPad's window on top of the UI scale that ElvUI and others set.
- **Cursor warning.** When the cursor clicks are on buttons but nothing brings the cursor up (no button on *Toggle gamepad cursor* and *Show it when a window opens* off), the editor and the settings page say so, since the clicks then do nothing.

### Changed

- The settings page reads in a clear hierarchy: section headings in small amber capitals over a hairline, grey labels, white values and smaller notes, with even spacing between sections. Reset layout, Undo reset and Undo setup move to the footer beside Key Bindings and explain themselves on hover.

## [0.4.0] - 2026-10-24

### Added

- **Form pages in the editor.** Action Bar 1 has its own page for each form or stance, such as Cat Form, Bear Form or Prowl, and Base edits the one in play. A *Base* picker by the controller name shows which, and lets you set up another form's buttons without shifting into it. LeanPad learns each form's page the first time you shift into it.
- **Bar addons named.** With ElvUI, Bartender4 or Dominos running the action bars, LeanPad says so at login and on the settings page; for ElvUI it names the bars each layer uses (Bars 1, 6, 5 and 3). The turned-off-bar warning stays quiet then, since Blizzard's Show Action Bar options don't apply.

### Fixed

- Action Bar 1 follows your form, stance, vehicle or override bar in the editor and on the crossbar, so a spell placed in Cat Form lands on Cat Form's page. LeanPad now reads the page from the game, not from Blizzard's bar button, which stays on a stale page when a bar addon such as ElvUI runs the bars.

## [0.3.0] - 2026-10-24

### Added

- **Warning for turned-off action bars.** Controller buttons bound to an Action Bar that is turned off in *Options > Gameplay > Action Bars* fire nothing. LeanPad now says so in chat at login and whenever a bar is turned off, and the editor marks the button, with where to turn the bar back on.
- **Drag spells off** the crossbar (with its mouse on) and the editor, as off Blizzard's bars: the slot empties and the spell rides the cursor, to drop on another slot or let go of to remove it.
- Crossbar sockets blink on every press of their pad button, whatever it does: a spell, one on cooldown, an empty slot or a command such as Jump. Mashing a button blinks it each time.
- Crossbar icons turn red while your target is out of their range.
- **Undo reset**, on the settings page, in *AddOns > LeanPad* and as `/lp undo`: brings back the layout the last reset replaced. *Undo setup* still returns to how things were before LeanPad.

### Changed

- Reset to default layout starts over: it clears every controller binding, on any modifier, before binding LeanPad's layout, so no old chord fires alongside it. Keyboard and mouse bindings are left alone. Everything it clears is saved first.

## [0.2.0] - 2026-10-22

### Added

- **Settings page** inside the editor, from its Settings button, `/lp settings` or Blizzard's *AddOns > LeanPad*: gamepad on or off, which pad to use when several are connected, Xbox or PlayStation labels whatever the pad reports, the three layer buttons, play style, soft targeting, the crossbar's view, size, opacity, position and mouse, and the native cursor's clicks, speed, auto-show, stick hiding and touchpad. Every change flashes *Saved* in the footer once it is written, including changes queued until combat ends.
- **Spells and macros in Change action.** The menu opens with your spellbook, by tab for your spec with icons, and your macros. Pick one and it lands on the button: into the bar slot the button already fires, or into the first free slot of that layer's own bar, which the button is bound to on the spot. Bar slots and Blizzard's other commands keep their lists beneath.
- **Play styles**: Tank, Melee, Ranged, Healer, or Auto by spec. A style sets how the body answers the stick in combat (tanks never show their back, melee and ranged strafe but spin to run, healers run free) and whom soft targeting looks for. Off until chosen.
- **Crossbar layout editing.** Unlock the crossbar from the settings page or Blizzard's Edit Mode, then drag the whole bar, any one set or any single button, and scroll over a set to size it. Drops snap to a grid and line up with neighbours; Shift drops freely; *Reset layout* puts everything back. Positions and sizes are saved.
- **Crossbar mouse mode**, off by default: drop a spell from the spellbook or talents onto a socket to put it in that button's bar slot, and hover a socket for its tooltip.
- **Command icons** in LeanPad's own style for targeting (with next, previous and party-number badges), interact, jump, auto-run, the cursor toggle, bags, game menu, map, spellbook and character pane; Blizzard's micro-menu atlases for the other panels. They show on the crossbar and in the editor.
- LeanPad has a logo, shown in the addon list and the minimap's addon compartment, where LeanPad is now listed; `/leanpad` works as well as `/lp`.

### Changed

- **Redesigned controller editor** (`/lp`). The controller sits fixed in the middle with every bound button labelled beside it and a leader curving to the button, one layer per tab. Press a button, holding a layer button first for its layer, and the strip below shows the spell on its slot, where it lives and the same button on the other layers, with Change action, Clear and spell drop. Cursor users can hover and click the drawing. The Menu button closes it.
- The editor has its own flat look: slate panels, one amber accent and Arial Narrow, drawn with colour textures only. The controller drawings are redrawn in steel on slate to match, and ship in `LeanPad/Art/`, generated by `tools/draw-pads.js`.
- **Layer buttons only open layers**, as in FFXIV and WoW: Forever. Making a button a layer button clears its own bindings on every layer; the editor offers nothing to change or drop on it, and the crossbar shows no socket for it.
- The crossbar's view is one setting: off, one set that swaps with the held layer, or all layers at once. The sockets between the two diamonds sit on the diamonds' centre line with even gaps; the cursor toggle and auto-run get no socket.
- Blizzard's Settings panel now holds only the entry points: open the editor, open the settings page, set up, undo, Action Bars and Key Bindings.
- Editor copy follows the pad: PlayStation users read L2, R2 and Options, not LT, RT and Menu.
- The default layout puts *Toggle gamepad cursor* on the right stick click (R3), instead of Action Bar 1 slot 7. Existing layouts are not changed; use *Reset to default layout* to pick it up.

### Fixed

- *Default layout* clears the triggers' own bindings, so tapping LT or RT no longer fires a leftover action from a previous layout.
- Crossbar press feedback no longer disappears while a button is held, when the bar refreshes mid-press.
- A spell picked for, or dropped on, a button with no bar slot now finds a free slot. Keyboard keys on a slot, such as 1 to = on Action Bar 1, no longer make the bar look full; only another pad button takes a slot.

## [0.1.0] - 2026-10-22

First public release.

### Added

- One-click controller setup: turns on the gamepad, makes LT and RT emulate Shift and Ctrl, moves the cursor clicks to A and B, enables gamepad soft targeting, and binds the controller to Action Bars 1-4 across three trigger layers (LT, RT, LT+RT).
- An existing controller layout is kept by default; setup asks before replacing it.
- `/lp restore` and an *Undo setup* button that restore the CVars and bindings from before setup.
- Visual controller editor (`/lp`) with Xbox and PlayStation layouts, one tab per modifier layer, a binding menu covering every Blizzard command, drag-and-drop onto action slots, and button detection.
- Crossbar HUD showing controller actions in controller-shaped clusters, with native cooldowns, charges, usability and press feedback. Unused buttons are hidden. It can show only the held layer or all layers at once.
- Settings panel under *AddOns > LeanPad* for setup, the crossbar, the modifier buttons, the cursor clicks and soft targeting.
- *Toggle gamepad cursor* key binding.
- `/lp perf` readout from the in-game addon profiler.
- In-combat requests to change bindings or CVars are queued until combat ends.

[Unreleased]: https://github.com/Taimoorkasi/LeanPad/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/Taimoorkasi/LeanPad/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Taimoorkasi/LeanPad/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Taimoorkasi/LeanPad/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Taimoorkasi/LeanPad/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Taimoorkasi/LeanPad/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Taimoorkasi/LeanPad/releases/tag/v0.1.0
