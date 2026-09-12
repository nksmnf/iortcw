# iORTCW for iPadOS

Return to Castle Wolfenstein — the single-player campaign — on iPadOS, with full
DualSense support.

Built and verified against Xcode 26.6 / iOS SDK 26.5, targeting an iPad Pro 13"
(M5).

Multiplayer is a second application built from the same directory: see
**Multiplayer** below. The two are separate apps with separate bundle
identifiers, because `SP/` and `MP/` are separate copies of the engine that
share no symbols and cannot be linked into one binary.

---

## Building

You need Xcode (not just the Command Line Tools). If `xcode-select` points at
the CLT, the scripts set `DEVELOPER_DIR` for you.

Every script takes `IORTCW_TREE=MP` to build the multiplayer application
instead; each tree has its own build directory, so the two never collide.

```sh
# Build signed and install straight onto the paired iPad
ios/scripts/install-device.sh

# An .ipa for AltStore
ios/scripts/build-ipa.sh            # -> build/ipa/iORTCW.ipa
IORTCW_TREE=MP ios/scripts/build-ipa.sh   # -> build/ipa-mp/iORTCW-MP.ipa

# An Xcode project, to build and run from the IDE
ios/scripts/gen-xcode.sh device     # -> build/ios/iortcw_sp.xcodeproj
ios/scripts/gen-xcode.sh simulator  # -> build/ios-sim/iortcw_sp.xcodeproj

# Build, install and launch on the simulator, with game data linked in
IORTCW_DATA_DIR=/path/to/rtcw/Main ios/scripts/sim-run.sh
```

Two ways onto the device, and the first is the short one.

`install-device.sh` signs with the developer account already set up on this Mac
— it finds the team from the provisioning profile for the bundle identifier —
and hands the app to the iPad over the CoreDevice tunnel. Nothing to move, and
no 7-day re-sign to remember. It needs the iPad paired and trusted, which is to
say showing up in `xcrun devicectl list devices`.

The `.ipa` is the other way, and it is deliberately unsigned — AltStore re-signs
it with your own certificate on install. Use it when the Mac that builds is not
the Mac the iPad is paired with.

Either way it is an *update*: the app container survives, so the game data and
the savegames stay put. That holds only while the bundle identifier does, which
is why `IORTCW_BUNDLE_ID` is pinned rather than generated.

## Installing

1. `ios/scripts/install-device.sh`, or send `iORTCW.ipa` to the iPad and open it
   with AltStore (or use AltServer).
2. Launch it once. The launcher will report that the game data is missing.
3. In **Files → On My iPad → iORTCW → main**, copy in from your RTCW
   installation:
   `pak0.pk3`, `sp_pak1.pk3`, `sp_pak2.pk3`, `sp_pak3.pk3`, `sp_pak4.pk3`.
   The launcher ticks them off as they arrive; no relaunch needed.
4. Pair a DualSense over Bluetooth (Settings → Bluetooth, hold Create + PS until
   the light bar flashes) and set your bindings in the launcher.

AltStore's re-sign every 7 days is an *update* too, not a reinstall, so nothing
copied in is lost to it either.

### Extra campaigns and the Russian localisation

Two optional things can be dropped in the same way, at the top level of the
`iORTCW` folder — the launcher files them where they belong on the next start:

- **Fan campaigns.** Ten of them, pure data, each one pak. Dropping
  `time_gate.pk3` creates `time_gate/` and moves it there, and the campaign
  appears in the picker on the Campaign tab. Русская документация:
  [docs/RU/CAMPAIGNS.md](../docs/RU/CAMPAIGNS.md).
- **The Russian localisation**, as shipped with the Russian anthology of the
  game: text, menus and the dubbed campaign dialogue. The launcher's language
  switch then moves the game with it, parking the paks as `*.pk3.off` for
  English. Details, including what does and does not survive a pure server:
  [docs/RU/RUSSIAN.md](../docs/RU/RUSSIAN.md).

Each campaign keeps its own savegames and its own console log; the last two
runs of each are kept under `iORTCW/logs/`.

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

On-screen controls appear unless a controller is being used (`in_touchControls`
0 automatic / 1 always / 2 never). Left half is a floating movement stick, right
half is look, with fire/jump/use/crouch/reload/next-weapon bottom right and a
MENU button top right. They hide themselves whenever the game is not what is on
screen: a menu, a loading screen, the mission briefing, a cutscene.

"Automatic" waits for the pad to actually be used rather than merely reported.
iOS reports a gamepad with nothing attached -- the simulator always does -- and
hiding the controls on that leaves a tablet with no way to play at all.

Two gestures work whether or not the controls are shown:

- **three-finger tap** — Escape, the same as the MENU button
- **four-finger tap** — console

The overlay owns every touch and drives the game's own cursor to the finger.
Letting SDL synthesise mouse events from touches, which is the obvious way and
what this did at first, does not work: the engine runs the mouse in relative
mode for aiming, and in that mode a synthesised event arrives pinned to the
centre of the window with a zero delta, so the cursor never moves and a tap
activates whatever it was already over.

`in_debugTouch 1` logs every touch and the state it arrived in. There is no
console on a tablet, and that log is what found the above.

## Multiplayer

`IORTCW_TREE=MP` builds **iORTCW MP** (`com.iortcw.mp`) from the `MP/` tree. It
needs `pak0.pk3` and `mp_pak0.pk3` … `mp_pak5.pk3`; the campaign paks are not
used and the multiplayer ones did not ship on the disc, so a copy that plays the
campaign perfectly can still be missing every file this build wants.

The launcher grows three tabs, and drops the Campaign one:

| Tab | What it does |
|---|---|
| **Серверы** | Queries the three live masters directly and lists what answers: name, map, humans/slots, ping, engine family and mod. Tap a row to join, or type an address. |
| **Мультиплеер** | Player name, network rates, crosshair, HUD, map downloads. |
| **Свой сервер** | Runs a server from the tablet: game type, map rotation, slots, limits, passwords, rcon, port, and how visible it is. |

Graphics and Controls are shared with the campaign build, so stick feel, gyro
and the DualSense layout carry over.

### Finding servers

The browser speaks the Quake 3 out-of-band protocol itself
(`ios/Launcher/ServerBrowser.swift`) rather than going through the engine,
because the launcher runs before `Com_Init` and there is no engine yet. Two
things about the masters are worth knowing, both of them measured rather than
assumed (`docs/RU/server.md`):

- `wolfmaster.idsoftware.com` — the official master, still alive — answers only
  the short `getservers <protocol>` form. Send it a game name and it says
  nothing at all.
- Protocol 61, iortcw's own, is **empty on every master**. Every public server,
  iortcw ones included, registers as 60, because `com_legacyprotocol` defaults
  to 60. Asking only for 61 finds nothing and looks like a bug.

Bots are counted separately from players: a bot always reports a ping of zero,
and without that split most of the network looks full when nobody is playing.

### Hosting, and the background problem

iOS suspends an ordinary app seconds after it leaves the screen, and a suspended
process stops reading its socket — every client times out and the master stops
hearing the heartbeat. There is no background mode for "keep listening on a
socket"; the list is fixed and a game server is not on it.

So hosting starts an audio graph that renders silence
(`ios/Sources/ios_keepalive.m`), which is a real, documented background mode.
Three things follow from that, and they are in the file as well:

- App Review would reject it, because the app is not an audio app. This build is
  sideloaded through AltStore, where there is no review — but anyone taking it
  further needs to know.
- It costs battery. The CPU never sleeps and the server keeps simulating. Host
  from a tablet that is plugged in.
- The session mixes with others, so it never silences the user's music.

The **Режим** control is the `dedicated` cvar, and it decides more than
visibility:

| Mode | `dedicated` | Picture on the tablet | In the master list |
|---|---|---|---|
| Играю сам | 0 | yes — you play on it | no (LAN broadcast only) |
| Локальный | 1 | no, the screen stays dark | no |
| Интернет | 2 | no | yes, heartbeat every 5 min |

Only `dedicated 2` reports to a master (`MP/code/server/sv_main.c:259`), and
only mode 0 draws anything. "Play on it" and "visible on the internet" are
therefore mutually exclusive. Hosting publicly also needs a UDP port forward:
incoming connections never arrive over mobile data, which is behind CGNAT.

### What is not there yet

- **Pad navigation inside the three new tabs.** L1/R1 still move between tabs,
  and everything works by touch, but the cursor model the campaign and graphics
  tabs use is built around a fixed set of rows and the server list is neither
  fixed nor static.
- **HTTP map downloads.** `USE_CURL=0` for iOS, so downloads fall back to the
  engine's UDP path: slower, but it works, and over half the populated servers
  run custom maps that cannot be joined without it.
- **Per-weapon haptics.** `cg_haptics.c` is a campaign file; the MP game modules
  do not drive the DualSense's adaptive triggers or light bar. Buttons, sticks,
  gyro and rumble all work — they are engine-side.
- **IPv6-only networks.** The masters have no AAAA records and hand back literal
  IPv4 addresses, which DNS64 cannot translate. On a 464XLAT carrier (most of
  them) this never comes up.

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

- **The simulator renders in software** (`GL_RENDERER: Apple Software Renderer`)
  and is nowhere near playable speed at 2752x2064 -- roughly a frame a second,
  which reads as a hang. `+set r_hidpi 0` quarters the pixel count and makes it
  usable for testing flow and input. It says nothing about the device, where
  ES 1.1 runs on the GPU.
- **The simulator shows the game letterboxed** when its own frame is portrait.
  The app itself stays landscape; a device honours the landscape-only Info.plist.
- **A game module linked into the engine keeps its globals across a level
  change**, where a bytecode or freshly loaded one would not. Anything written
  as "allocate once, the pointer starts null" is therefore a dangling pointer
  after the first map. Two were found this way and fixed at the source
  (`botstates` in the game, the portal fog flag in cgame); a third of the same
  shape would look like a crash on level change or on loading a savegame.
- **Savegame names are filled in** from the map (escape1_1, escape1_2). The save
  menu refuses an empty name and there is no keyboard to type one with.
- **`IORTCWSkipLauncher`** (a `UserDefaults` bool) starts straight into the game
  for players who have already set everything up.
- **`qconsole.log`** — set `logfile 2`. It lands in Documents, so it is readable
  in Files.app, which on a sideloaded build is the only window into the engine.
- **The campaign build passes `+set net_enabled 0`**, so iOS never raises the
  Local Network permission prompt for a game with no network. The multiplayer
  build passes `1` (IPv4 only, which is all the masters speak) and declares
  `NSLocalNetworkUsageDescription`; without that key the engine's broadcast and
  IPv6 multicast scan are dropped silently and the LAN list is simply always
  empty.
