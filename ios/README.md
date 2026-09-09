# iORTCW for iPadOS

Return to Castle Wolfenstein — the single-player campaign — on iPadOS, with full
DualSense support.

Built and verified against Xcode 26.6 / iOS SDK 26.5, targeting an iPad Pro 13"
(M5). Multiplayer is out of scope; only the `SP/` tree is used.

---

## Building

You need Xcode (not just the Command Line Tools). If `xcode-select` points at
the CLT, the scripts set `DEVELOPER_DIR` for you.

```sh
# An .ipa for AltStore
ios/scripts/build-ipa.sh            # -> build/ipa/iORTCW.ipa

# An Xcode project, to build and run from the IDE
ios/scripts/gen-xcode.sh device     # -> build/ios/iortcw_sp.xcodeproj
ios/scripts/gen-xcode.sh simulator  # -> build/ios-sim/iortcw_sp.xcodeproj

# Build, install and launch on the simulator, with game data linked in
IORTCW_DATA_DIR=/path/to/rtcw/Main ios/scripts/sim-run.sh
```

The `.ipa` is deliberately unsigned — AltStore re-signs it with your own
certificate on install. To run from Xcode instead, open the project, select the
`iORTCW` target and set your signing team.

## Installing

1. Send `iORTCW.ipa` to the iPad and open it with AltStore (or use AltServer).
2. Launch it once. The launcher will report that the game data is missing.
3. In **Files → On My iPad → iORTCW → main**, copy in from your RTCW
   installation:
   `pak0.pk3`, `sp_pak1.pk3`, `sp_pak2.pk3`, `sp_pak3.pk3`, `sp_pak4.pk3`.
   The launcher ticks them off as they arrive; no relaunch needed.
4. Pair a DualSense over Bluetooth (Settings → Bluetooth, hold Create + PS until
   the light bar flashes) and set your bindings in the launcher.

Re-signing every 7 days is an *update*, not a reinstall, so the game data and
your saves survive it — as long as the bundle identifier stays the same, which
is why `IORTCW_BUNDLE_ID` is pinned rather than generated.

## DualSense

| Feature | How |
|---|---|
| Buttons, sticks, analogue triggers | SDL's MFi backend |
| Second trigger stage | A deeper threshold on its own bindable keys, so half-pull can aim and full-pull fire |
| Touchpad | Tap, click and four swipe directions, all bindable; optional drag-to-look |
| Gyro aiming | Added on top of the right stick — stick for the big turn, gyro for fine aim. Off, always on, or only while scoped |
| Vibration | Per-weapon recoil, damage, explosions |
| Light bar | Tracks health, green through red |
| Adaptive triggers | Per-weapon resistance profiles |

Adaptive triggers go through `GameController.framework` directly
(`ios/Sources/ios_dualsense.m`) because SDL has no API for them. That coexists
with SDL: SDL only reads those `GCController` objects, this only writes trigger
state.

## Without a controller

On-screen controls appear whenever no controller is connected (`in_touchControls`
0 automatic / 1 always / 2 never). Left half is a floating movement stick, right
half is look, with fire/jump/use/crouch/reload/next-weapon bottom right.

Two gestures work whether or not the controls are shown, and they are the only
way into the menu and console on a sideloaded build with no debugger attached:

- **three-finger tap** — Escape
- **four-finger tap** — console

## How it is put together

`SP/Makefile` remains the authority for the macOS build. This directory adds
what the Makefile cannot express: a single statically linked binary, an app
bundle, Swift, and an Xcode project.

- **Source lists are not duplicated.** `cmake/extract_sources.py` asks the
  Makefile what it would build and maps the object list back to sources
  (`cmake/sources.generated.cmake`). It fails loudly on anything it cannot
  resolve rather than guessing. Re-run it after adding or removing source files;
  `--check` verifies the committed copy is current.

- **Game modules are linked in, not dlopen'd.** iOS refuses to load code from
  outside the signed bundle and arm64 has no QVM compiler, so `qagame`, `cgame`
  and `ui` are compiled with `-fvisibility=hidden -fno-common`, have their entry
  points renamed, and are collapsed with `ld -r` so each exposes exactly two
  symbols. See `cmake/StaticVM.cmake`. Setting `vm_static 0` falls back to the
  normal dll/QVM search, and the QVM build still works
  (`make BUILD_GAME_QVM=1`) if it is ever needed.

- **Renderer is OpenGL ES 1.1**, reusing the `USE_OPENGLES` path already in
  `SP/code/renderer`. ES 1.1 is deprecated on iOS but very much alive: the
  engine reports `OpenGL ES-CM 1.1 APPLE` on iOS 26.5, with framebuffer objects,
  stencil8 (needed for RTCW's shadow volumes) and limited NPOT all present.

- **Rendering is at native resolution.** `r_mode` is ignored on iOS: it is
  `CVAR_LATCH` and `default.cfg` inside `pak0.pk3` sets it to 3 before the
  renderer registers the cvar, so the config always won and the game came up as
  a 640×480 window in the corner. `r_hidpi 0` halves the resolution for battery.

## Files

```
ios/
├── CMakeLists.txt          the build; macOS-capable too, as a test bed
├── cmake/
│   ├── extract_sources.py  derives source lists from SP/Makefile
│   ├── StaticVM.cmake      the ld -r machinery for the game modules
│   └── sources.generated.cmake
├── Sources/
│   ├── sys_ios.m           platform layer (replaces the Carbon-based sys_osx.m)
│   ├── ios_touch.m         on-screen controls
│   ├── ios_dualsense.m     adaptive triggers
│   └── ios_bridge.{h,c}    the surface the Swift launcher may touch
├── Launcher/               SwiftUI launcher
├── Resources/Info.plist.in
└── scripts/
```

## Notes and limitations

- **The simulator shows the game letterboxed** and hides the right-hand
  on-screen controls. That is the simulator keeping its frame in portrait while
  the app draws landscape; a device honours the landscape-only Info.plist.
- **`IORTCWSkipLauncher`** (a `UserDefaults` bool) starts straight into the game
  for players who have already set everything up.
- **`qconsole.log`** — set `logfile 2`. It lands in Documents, so it is readable
  in Files.app, which on a sideloaded build is the only window into the engine.
- Multiplayer is not built: `USE_CURL=0`, and `+set net_enabled 0` is passed so
  iOS never raises the Local Network permission prompt for a single-player game.
