# LeanPad

Lean controller play on World of Warcraft's own gamepad layer, for retail and WoW: Forever.

**On WoW: Forever?** Turn off Blizzard's Gamepad UI for the full experience. [See what changes](#wow-forever).

WoW already has a full gamepad layer built in: controller buttons are ordinary key bindings, the triggers can act as Shift and Ctrl, and there is a native gamepad cursor and soft targeting. LeanPad configures that layer for you instead of rebuilding it. Your actions stay on Blizzard's own action bars, so Blizzard draws the cooldowns, glows and range, and your layout keeps working if you turn the addon off.

## New in 0.7.0

- **Talk to NPCs and do quests from the pad.** LeanPad's own dialogue window, made for reading: the NPC in 3D beside their words, which write themselves in, rewards as tiles in their quality's colour, and A, B and the D-pad to answer. Put it in any of nine places on screen, at the size and text size you like.
- **Pop-ups from the pad.** A, B, X and Y press the buttons of Blizzard's pop-ups, the dungeon queue pop and ready checks, named under each one, such as Release Spirit and Recap when you die.
- **Settings in two tabs**, *Controls* and *Dialogue*, and an (i) on every setting that says what it does, with a live preview of the dialogue window.
- **WoW: Forever support**, plus fixes: Edit Mode can reach the frames under the crossbar again, and the cursor toggle no longer errors.

![LeanPad's dialogue window: an NPC in 3D beside their words](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/dialogue-npc.png)

![LeanPad's dialogue window offering a quest](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/dialogue-quest.png)

![A pop-up with LeanPad's A and B prompts](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/popup.png)

## Easy binding setup

Press a button on your pad and see what it does on every layer. Pick a spell or macro straight from your spellbook and LeanPad puts it on the button for you.

![The LeanPad controller editor](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/easy-binding-setup.png)

![The LeanPad editor's Change action menu listing Guardian spells](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/easy-binding-mapping.png)

## Easy to understand settings

Layer buttons, which pad to use, Xbox or PlayStation labels, the cursor, the crossbar and soft targeting on the *Controls* tab, and the dialogue window and pop-ups on the *Dialogue* tab, all next to the editor. Hover the (i) after any setting to see what it does.

![The LeanPad settings page on its Controls tab](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/easy-to-understand-settings.png)

![The Dialogue tab of LeanPad's settings](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/settings-dialogue.png)

## Crossbar layouts

Seven styles, picked from *View* on the settings page. The square grid sits under your character and swaps as you hold a layer button; square rows show every layer at once, one row each, the held one in front.

![The square grid crossbar under the character](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/layout-square-grid.png)

![The square rows crossbar, one row per layer](https://raw.githubusercontent.com/tamuir/LeanPad/main/docs/images/layout-square-one-per-layer.png)

## Features

- **One-click setup.** Turns on the gamepad, makes the triggers your layer buttons, sets the cursor clicks and gamepad soft targeting, and binds the controller to Action Bars 1 to 4. An existing controller layout is kept unless you choose otherwise, and *Undo setup* puts everything back.
- **Three crossbar layers.** Hold LT, RT or both to reach a full D-pad and face-button set on its own action bar. Layer buttons only switch layers, as in FFXIV.
- **Controller editor.** A drawing of your PlayStation or Xbox pad with every button labelled. Press a button to see and change what it does.
- **Crossbar HUD.** Your controller actions in controller-shaped clusters with cooldowns and charges. Drag, size and snap the whole bar, each set or each button.
- **Show empty buttons.** Optionally draws every button in the layout as a faint socket before anything is bound. On by default on Forever.
- **Dialogue window.** Talk to NPCs and do quests from the pad: A confirms, B backs out, the D-pad chooses a quest, a line or a reward, whose tooltip shows as you pick it, and the bumpers scroll long text. In combat, new conversations open in Blizzard's windows. On by default on Forever; turn it on for retail on the *Dialogue* tab.
- **Pop-ups from the pad.** A, B, X and Y press a pop-up's buttons, left to right, the dungeon queue and ready checks included. They count as your own clicks, so entering a dungeon works.
- **Play styles.** Tank, Melee, Ranged, Healer, or Auto by spec, so your character moves the way your role needs in combat.
- **Combat-safe.** Bindings and settings are only written out of combat, and nothing runs while you are idle.

![LeanPad's command icons](https://raw.githubusercontent.com/tamuir/LeanPad/main/tools/preview/Icons.png)

## Getting started

Install, log in, and accept the setup prompt. Then type `/lp` to open the editor, or `/lp settings` for the settings page. LeanPad is also in the minimap's addon compartment. On retail, turn on the dialogue window and pop-ups on the settings' *Dialogue* tab.

Using ConsolePort? Turn it off first: both addons manage the gamepad bindings and settings.

## WoW: Forever

Forever has its own controller interface, Blizzard's Gamepad UI, which replaces the action bars and takes over the controller's buttons. LeanPad works with it on or off, but you only get all of LeanPad with it off.

To turn it off, untick *Enable Gamepad UI* in *Options > Gameplay > Gamepad (Alpha)*. The game doesn't let addons change this setting, so LeanPad reminds you when you log in, then offers its layout setup once it's off.

| | Gamepad UI off | Gamepad UI on |
| --- | --- | --- |
| Spells on A, B, X and Y on the Base layer | Yes | No, Blizzard keeps those four |
| Spells on the bumpers, stick clicks, View and Menu | Yes | No, commands only |
| Commands such as map or bags on the LT and RT layers | Yes | No, spells and macros only |
| Clicking the crossbar with the mouse | Every view | The Base layer only in views that swap as you hold a layer button |
| Answering quests with the pad | LeanPad's dialogue window | Blizzard's own |
| Blizzard's radial menus, controller menu navigation and group targeting | No, use the cursor for windows | Yes |

Your settings and profiles on Forever are separate from retail's.

## Reporting a problem

Found a bug? Report it at https://github.com/tamuir/LeanPad/issues. The form asks for your LeanPad version, controller, bar addon and any Lua error, so it can be tracked down quickly. Reports left in the comments here are easy to miss.

Source and changelog: https://github.com/tamuir/LeanPad
