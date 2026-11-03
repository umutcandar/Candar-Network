# iOS TestFlight Startup Crash Fix

Date: 2026-06-20

## Root cause

TestFlight build 37 embedded a project pack exported by Godot 4.6.3 while
the native iOS engine library was Godot 4.5. Godot project packs are not
forward-compatible across this engine boundary, so the app could terminate
during startup before rendering the first screen.

## Fix

- Installed the matching Godot 4.5 stable editor at
  `~/Applications/Godot-4.5.app`.
- Exported a fresh iOS pack with Godot 4.5.
- Smoke-tested that pack with the same Godot 4.5 runtime.
- Embedded the verified pack in version 2.0.10 build 38.
- Verified the archive contains build 38 and an exact copy of the tested pack.
- Added `scripts/build_ios_pack.sh` to block future engine/pack mismatches.

## TestFlight

- Build 37: incompatible pack; do not test or distribute.
- Build 38: engine mismatch fixed, but a black-screen startup was reproduced
  on the physical device. The pack had been exported from a workspace import
  cache previously touched by Godot 4.6.
- Build 39: rebuilt from a clean Godot 4.5-only import cache for physical-device
  verification before upload.
