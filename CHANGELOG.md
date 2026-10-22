# Changelog

All notable changes to LeanPad are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/OWNER/leanpad/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OWNER/leanpad/releases/tag/v0.1.0
