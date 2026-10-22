# LeanPad

A lean controller addon for retail World of Warcraft (Midnight, 12.1.5).

WoW already has a full gamepad layer built in: controller buttons are ordinary key bindings, the triggers can act as Shift and Ctrl, and there is a native gamepad cursor and soft targeting. LeanPad configures that layer for you instead of rebuilding it. You get a one-click setup, a crossbar-style layout across three trigger layers, a visual controller editor and a crossbar HUD. It has no libraries, no textures of its own and no code running while you are idle.

Your actions stay on Blizzard's own action bars, so Blizzard draws the cooldowns, glows and range, and the layout keeps working if you disable the addon.

## Features

- **One-click setup.** Turns on the gamepad, makes LT and RT act as Shift and Ctrl, sets the cursor clicks and gamepad soft targeting, and binds the controller to Action Bars 1-4. If you already have a controller layout, LeanPad keeps it by default.
- **Undo.** Setup saves your previous CVars and bindings first. `/lp restore` puts them back.
- **Three crossbar layers.** LT, RT and LT+RT each map the D-pad and face buttons onto 8 slots of their own action bar.
- **Controller editor.** `/lp` opens a drawing of your controller (Xbox or PlayStation layout, detected from the pad) with one tab per trigger layer. Click a button to bind any Blizzard command to it, drag spells onto it, or press a button on the pad to find it.
- **Crossbar HUD.** Shows your controller actions in controller-shaped clusters, with cooldowns, charges, usability and press feedback. It can show only the held layer or all layers at once.
- **Settings panel.** Every option lives in Blizzard's own Settings panel under *AddOns > LeanPad*.
- **Combat-safe.** Bindings and CVars are only written out of combat. A request made in combat runs once combat ends.

## Requirements

- World of Warcraft retail, interface 120105 (12.1.5)
- A controller that WoW's built-in gamepad support recognises

## Installation

1. Download the latest release, or clone this repository.
2. Copy the `LeanPad` folder (the one containing `LeanPad.toc`) into `World of Warcraft\_retail_\Interface\AddOns\`.
3. Start the game, or type `/reload` if it is already running.

On your first login, LeanPad asks whether to set up the controller. You can run setup again any time from the Settings panel.

> **Using ConsolePort?** Disable it before using LeanPad. Both addons manage the gamepad bindings and CVars, and they will overwrite each other.

## Usage

| Command | What it does |
| --- | --- |
| `/lp` | Open or close the controller editor |
| `/lp settings` | Open LeanPad's Settings panel |
| `/lp restore` | Restore the controller settings and bindings from before setup |
| `/lp perf` | Print LeanPad's CPU cost from the in-game addon profiler |

LeanPad also adds a **Toggle gamepad cursor** binding under *Key Bindings > AddOns > LeanPad*.

### Default layout

Button names use Xbox labels.

| Button | Action |
| --- | --- |
| A | Jump |
| B | Interact with target |
| X, Y | Action Bar 1, slots 1-2 |
| LB, RB | Action Bar 1, slots 3-4 |
| D-pad up, down | Action Bar 1, slots 5-6 |
| D-pad left, right | Previous enemy, nearest enemy |
| Left stick click | Auto-run |
| Right stick click | Action Bar 1, slot 7 |
| View | Open bags (LT+View: world map, RT+View: character) |
| Menu | Game menu (LT+Menu: spellbook) |

| Hold | Uses | D-pad up, right, down, left | Y, B, A, X |
| --- | --- | --- | --- |
| LT | Action Bar 2 | slots 1-4 | slots 5-8 |
| RT | Action Bar 3 | slots 1-4 | slots 5-8 |
| LT+RT | Action Bar 4 | slots 1-4 | slots 5-8 |

When the gamepad cursor is on, A left-clicks and B right-clicks.

To see a layer on screen, turn on Action Bars 2-4 in *Settings > Action Bars* and place them in Edit Mode, or use LeanPad's crossbar HUD.

## Development

```sh
docker build -t leanpad-test spec
docker run --rm -v "${PWD}:/src" leanpad-test
```

The tests run [busted](https://lunarmodules.github.io/busted/) on Lua 5.1, the version the WoW client embeds. The run fails if line coverage of `LeanPad/` drops below 100%. `spec/wow.lua` fakes the WoW API, so every new API the addon calls needs a stub there.

For live testing, link the `LeanPad` folder into your `AddOns` folder and use `/reload` after each edit. On Windows:

```powershell
New-Item -ItemType Junction -Path "<WoW>\_retail_\Interface\AddOns\LeanPad" -Target "<repo>\LeanPad"
```

Ground rules for changes:

- Check every API against the `live` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source).
- Only write CVars and bindings out of combat, from code the player triggered.
- Never compare or do arithmetic on combat values; in Midnight they may be secret.
- No `OnUpdate` while idle, no embedded libraries and no textures.
- Use `hooksecurefunc` only, and never change attributes on Blizzard's secure frames.
- LeanPad is written from scratch on WoW's native gamepad API. Do not copy code, presets or layouts from other controller addons.

The reasoning behind the design is in [docs/WoW controller addon design.md](docs/WoW%20controller%20addon%20design.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

LeanPad is licensed under the GNU General Public License, version 2 or (at your option) any later version. The full text is in [LICENSE](LICENSE).
