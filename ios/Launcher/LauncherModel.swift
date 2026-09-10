//  LauncherModel.swift -- state behind the launcher UI.
//
//  Talks to the engine only through ios_bridge.h. Nothing here touches the
//  engine's own headers, which do not import into Swift cleanly.

import Foundation
import GameController
import Combine

/// One bindable game action, and the controller button currently on it.
struct GameAction: Identifiable, Hashable {
    let id: String          // the console command, e.g. "+attack"
    let title: String
    let group: String

    static let all: [GameAction] = [
        GameAction(id: "+attack",    title: "Огонь",              group: "Бой"),
        GameAction(id: "+attack2",   title: "Альт. огонь",        group: "Бой"),
        GameAction(id: "+zoom",      title: "Прицел",             group: "Бой"),
        GameAction(id: "zoomin",     title: "Кратность +",        group: "Бой"),
        GameAction(id: "zoomout",    title: "Кратность −",        group: "Бой"),
        GameAction(id: "+reload",    title: "Перезарядка",        group: "Бой"),
        GameAction(id: "weapnext",   title: "Следующее оружие",   group: "Бой"),
        GameAction(id: "weapprev",   title: "Предыдущее оружие",  group: "Бой"),
        GameAction(id: "+quickgren", title: "Быстрая граната",    group: "Бой"),
        GameAction(id: "+moveup",    title: "Прыжок",             group: "Движение"),
        GameAction(id: "+movedown",  title: "Присесть",           group: "Движение"),
        GameAction(id: "+sprint",    title: "Спринт",             group: "Движение"),
        GameAction(id: "+speed",     title: "Шагом",              group: "Движение"),
        GameAction(id: "+leanleft",  title: "Наклон влево",       group: "Движение"),
        GameAction(id: "+leanright", title: "Наклон вправо",      group: "Движение"),
        GameAction(id: "+activate",  title: "Использовать",       group: "Действия"),
        GameAction(id: "+useitem",   title: "Применить предмет",  group: "Действия"),
        GameAction(id: "itemnext",   title: "Следующий предмет",  group: "Действия"),
        GameAction(id: "+kick",      title: "Удар ногой",         group: "Действия"),
        GameAction(id: "notebook",   title: "Журнал",             group: "Действия"),
        // The names default.cfg binds to F5 and F9. "save quick" was neither a
        // command nor an argument the engine knows, so binding it did nothing.
        GameAction(id: "savegame quicksave", title: "Быстрое сохранение", group: "Система"),
        GameAction(id: "loadgame quicksave", title: "Быстрая загрузка",   group: "Система"),
        GameAction(id: "togglemenu", title: "Меню",               group: "Система"),
    ]

    static var groups: [String] { ["Бой", "Движение", "Действия", "Система"] }
}

/// The DualSense inputs a player can bind, named the way the engine names them.
struct PadButton: Identifiable, Hashable {
    let id: String          // engine key name, e.g. "PAD0_A"
    let title: String       // what it is called on the controller itself

    static let all: [PadButton] = [
        PadButton(id: "PAD0_A",               title: "Cross"),
        PadButton(id: "PAD0_B",               title: "Circle"),
        PadButton(id: "PAD0_X",               title: "Square"),
        PadButton(id: "PAD0_Y",               title: "Triangle"),
        PadButton(id: "PAD0_LEFTSHOULDER",    title: "L1"),
        PadButton(id: "PAD0_RIGHTSHOULDER",   title: "R1"),
        PadButton(id: "PAD0_LEFTTRIGGER",     title: "L2 (soft)"),
        PadButton(id: "PAD0_RIGHTTRIGGER",    title: "R2 (soft)"),
        PadButton(id: "PAD0_LEFTTRIGGER_HARD",  title: "L2 (full)"),
        PadButton(id: "PAD0_RIGHTTRIGGER_HARD", title: "R2 (full)"),
        PadButton(id: "PAD0_LEFTSTICK_CLICK",  title: "L3"),
        PadButton(id: "PAD0_RIGHTSTICK_CLICK", title: "R3"),
        PadButton(id: "PAD0_DPAD_UP",         title: "D-pad up"),
        PadButton(id: "PAD0_DPAD_DOWN",       title: "D-pad down"),
        PadButton(id: "PAD0_DPAD_LEFT",       title: "D-pad left"),
        PadButton(id: "PAD0_DPAD_RIGHT",      title: "D-pad right"),
        PadButton(id: "PAD0_BACK",            title: "Create"),
        PadButton(id: "PAD0_START",           title: "Options"),
        PadButton(id: "PAD0_TOUCHPAD",        title: "Touchpad click"),
        PadButton(id: "PAD0_TOUCH_TAP",       title: "Touchpad tap"),
        PadButton(id: "PAD0_TOUCH_SWIPE_LEFT",  title: "Touchpad swipe left"),
        PadButton(id: "PAD0_TOUCH_SWIPE_RIGHT", title: "Touchpad swipe right"),
        PadButton(id: "PAD0_TOUCH_SWIPE_UP",    title: "Touchpad swipe up"),
        PadButton(id: "PAD0_TOUCH_SWIPE_DOWN",  title: "Touchpad swipe down"),
    ]
}

/// Graphics presets.
///
/// The M5 is enormously faster than anything RTCW was built for -- it is a 2001
/// game running a fixed-function pipeline -- so "maximum" is the sensible
/// default and the lower presets exist for battery life rather than for
/// playability. The only genuinely expensive setting at this resolution is
/// stencil shadows.
enum GraphicsPreset: Int, CaseIterable, Identifiable {
    case maximum = 0
    case balanced = 1
    case battery = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .maximum:  return "Максимум"
        case .balanced: return "Баланс"
        case .battery:  return "Экономия"
        }
    }

    var detail: String {
        switch self {
        case .maximum:
            return "Полное разрешение, анизотропная фильтрация, динамический свет и тени."
        case .balanced:
            return "То же, но без стенсильных теней — самой дорогой настройки на таком разрешении."
        case .battery:
            return "Половинное разрешение и упрощённые эффекты. Заметно дольше от батареи."
        }
    }

    /// cvar name -> value. Applied on top of the game's own defaults.
    var cvars: [String: String] {
        var v: [String: String] = [
            // Textures. picmip 0 is full detail; the pk3s are small by modern
            // standards and there is no reason to downscale them here.
            "r_picmip": "0",
            "r_picmip2": "0",
            "r_texturebits": "32",
            "r_colorbits": "32",
            "r_depthbits": "24",
            "r_textureMode": "GL_LINEAR_MIPMAP_LINEAR",
            "r_detailtextures": "1",
            // No S3TC on Apple hardware, and the ES path does not implement the
            // alternatives, so compression stays off.
            "r_ext_compressed_textures": "0",
            "r_ext_texture_filter_anisotropic": "1",
            "r_ext_max_anisotropy": "16",

            // Geometry. Lower subdivisions means finer curves -- and a lot more
            // of them. 1 is the finest the engine allows and multiplies the
            // triangles on every arch, rail and stairwell in the game for a
            // difference nobody can see at arm's length on a tablet; 2 is
            // already past the point of diminishing returns.
            "r_subdivisions": "2",
            "r_lodbias": "0",
            // 999 switches curve level of detail off outright, so a curved
            // surface across the map costs what it costs up close. 250 is the
            // engine's own default and keeps the detail where it is looked at.
            "r_lodCurveError": "250",

            // World
            "r_fastsky": "0",
            "r_drawSun": "1",
            "r_flares": "1",
            "r_dynamiclight": "1",
            "r_drawentities": "1",

            // Bloom does a full-screen copy per frame through the ES1 path,
            // which at 2752x2064 costs far more than it is worth.
            "r_bloom": "0",

            "cg_shadows": "2",       // stencil shadow volumes
            "cg_brassTime": "2500",
            "cg_gibs": "1",
            "cg_wolfparticles": "1",
            "cg_coronas": "1",
            "cg_marktime": "20000",
        ]

        switch self {
        case .maximum:
            break
        case .balanced:
            v["cg_shadows"] = "1"    // blob shadows
            v["r_ext_max_anisotropy"] = "8"
        case .battery:
            v["cg_shadows"] = "0"
            v["r_ext_max_anisotropy"] = "2"
            v["r_subdivisions"] = "4"
            v["r_lodCurveError"] = "250"
            v["r_dynamiclight"] = "0"
            v["cg_wolfparticles"] = "0"
            v["cg_brassTime"] = "0"
            v["cg_marktime"] = "5000"
        }

        return v
    }
}

/// The campaign in order, so a mission can be started without going through
/// RTCW's own menus -- which are cursor-driven and awkward on a touchscreen.
struct CampaignMission: Identifiable, Hashable {
    let id: String      // map name
    let title: String

    /// Which quarter of the campaign this mission sits in, used to decide what
    /// the player arrives carrying. Starting a map from here has no savegame
    /// behind it, and single player normally carries weapons forward inside
    /// one, so without this the player spawns with empty hands.
    var chapter: Int {
        guard let index = CampaignMission.all.firstIndex(where: { $0.id == id }) else { return 1 }
        switch index {
        case 0...2:   return 1
        case 3...7:   return 2
        case 8...16:  return 3
        default:      return 4
        }
    }

    static let all: [CampaignMission] = [
        CampaignMission(id: "escape1",   title: "1. Побег"),
        CampaignMission(id: "escape2",   title: "2. Замок Вольфенштайн"),
        CampaignMission(id: "tram",      title: "3. Фуникулёр"),
        CampaignMission(id: "village1",  title: "4. Деревня"),
        CampaignMission(id: "crypt1",    title: "5. Склеп"),
        CampaignMission(id: "crypt2",    title: "6. Гробница"),
        CampaignMission(id: "church",    title: "7. Церковь"),
        CampaignMission(id: "boss1",     title: "8. Хайнрих"),
        CampaignMission(id: "forest",    title: "9. Лес"),
        CampaignMission(id: "dam",       title: "10. Плотина"),
        CampaignMission(id: "village2",  title: "11. Деревня II"),
        CampaignMission(id: "chateau",   title: "12. Шато"),
        CampaignMission(id: "dark",      title: "13. Тёмная база"),
        CampaignMission(id: "trainyard", title: "14. Депо"),
        CampaignMission(id: "sfm",       title: "15. Секретный завод"),
        CampaignMission(id: "factory",   title: "16. Завод"),
        CampaignMission(id: "swf",       title: "17. Оружейный цех"),
        CampaignMission(id: "assault",   title: "18. Штурм"),
        CampaignMission(id: "xlabs",     title: "19. X-Лаборатории"),
        CampaignMission(id: "dig",       title: "20. Раскопки"),
        CampaignMission(id: "norway",    title: "21. Норвегия"),
        CampaignMission(id: "rocket",    title: "22. Ракетная база"),
        CampaignMission(id: "baseout",   title: "23. Побег с базы"),
        CampaignMission(id: "castle",    title: "24. Замок"),
        CampaignMission(id: "boss2",     title: "25. Пробуждение"),
        CampaignMission(id: "end",       title: "26. Финал"),
    ]
}

@MainActor
final class LauncherModel: ObservableObject {
    // Game data
    @Published var dataMask: Int = 0
    @Published var dataPath: String = ""

    // Graphics
    @Published var preset: GraphicsPreset = .maximum
    @Published var maxFPS: Int = 120
    @Published var hiDPI: Bool = true
    @Published var fov: Double = 90
    @Published var brightness: Double = 1.3

    // Controls
    @Published var sensitivity: Double = 5
    @Published var lookYawSpeed: Double = 220
    @Published var lookPitchSpeed: Double = 190
    @Published var stickExpo: Double = 0.35
    @Published var stickDeadzone: Double = 0.12
    @Published var gyroMode: Int = 0
    @Published var gyroSens: Double = 1.0
    @Published var rumble: Double = 100
    @Published var adaptiveTriggers: Bool = true
    @Published var triggerHard: Double = 0.75
    @Published var touchControls: Int = 0   // automatic: follows the hand, see ios_touch.m
    @Published var touchLookSens: Double = 1.0
    @Published var touchGyro: Bool = false
    @Published var touchGyroSens: Double = 1.0
    @Published var moveExpo: Double = 0.15

    // Sound
    @Published var volume: Double = 0.8
    @Published var musicVolume: Double = 0.5

    // Game
    @Published var autoSwitch: Bool = true
    @Published var viewBob: Bool = true
    @Published var crosshairSize: Double = 48

    // Diagnostics
    @Published var perfHud: Bool = false
    @Published var perfLog: Bool = false
    @Published var padLog: Bool = false
    @Published var invertLook: Bool = false
    @Published var moveDigital: Bool = true
    @Published var skill: Int = 2          // g_gameskill: 1 easy .. 4 death incarnate

    // Bindings, keyed by engine key name
    @Published var bindings: [String: String] = [:]

    @Published var controllerName: String? = nil

    // What is actually in the pk3s, read from their directories rather than
    // taken on faith from five filenames being present.
    @Published var dataMaps: Int = 0
    @Published var dataFiles: Int = 0
    @Published var dataMegabytes: Double = 0

    /// "0.2.0 (20260910)" -- the port's version, not the engine's.
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// When this binary was built, taken from the executable itself so it can
    /// never disagree with what is actually running.
    var buildTime: String {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return "—" }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    /// "iortcw 1.51d-SP ios-arm64", the engine's own version string.
    var engineVersion: String { String(cString: IOSBridge_EngineVersion()) }

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    static let dataFiles = ["pak0.pk3", "sp_pak1.pk3", "sp_pak2.pk3",
                            "sp_pak3.pk3", "sp_pak4.pk3"]

    var hasAllData: Bool { dataMask == (1 << LauncherModel.dataFiles.count) - 1 }
    var canPlay: Bool { IOSBridge_HasGameData() }

    init() {
        dataPath = String(cString: IOSBridge_DataPath())
        refreshData()
        loadDefaults()
        observeControllers()

        // The whole point of polling: the user copies files in through Files.app
        // with this screen open, and the checklist should tick over as they land
        // rather than making them relaunch.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshData() }
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    @Published var importedCount: Int = 0

    func refreshData() {
        // Sweep anything dropped at the top level into main/ first. Finder will
        // not drop into a subfolder over file sharing, so from a Mac this is the
        // only way the data ever gets where the engine looks for it. Files still
        // being written are skipped and picked up on a later pass.
        let moved = Int(IOSBridge_ImportLooseData())
        if moved > 0 {
            importedCount += moved
        }

        let previous = dataMask
        dataMask = Int(IOSBridge_GameDataMask())

        // Only when the set of files changed, and only once it is complete:
        // reading five zip directories is cheap but not free, and this runs
        // every second while the launcher is open.
        if hasAllData && (dataMaps == 0 || dataMask != previous) {
            if IOSBridge_ScanData(dataMask != previous) {
                dataMaps = Int(IOSBridge_DataMaps())
                dataFiles = Int(IOSBridge_DataFiles())
                dataMegabytes = IOSBridge_DataMegabytes()
            }
        }
    }

    private func observeControllers() {
        let update: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.controllerName = GCController.controllers().first?.vendorName
            }
        }
        controllerName = GCController.controllers().first?.vendorName
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main, using: update))
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main, using: update))
    }

    /// A layout that suits a controller, rather than the keyboard defaults the
    /// game ships with. Applied on first run and by the Reset button.
    func applyDefaultBindings() {
        bindings = [
            // Triggers do the shooting, shoulders change weapon -- the layout
            // every console shooter uses, so it needs no learning.
            "PAD0_RIGHTTRIGGER":      "+attack",
            "PAD0_LEFTTRIGGER":       "+zoom",
            "PAD0_RIGHTSHOULDER":     "weapnext",
            "PAD0_LEFTSHOULDER":      "weapprev",

            "PAD0_A":                 "+moveup",     // Cross  -- jump
            "PAD0_B":                 "+movedown",   // Circle -- crouch
            "PAD0_X":                 "+reload",     // Square -- reload
            "PAD0_Y":                 "+activate",   // Triangle -- use/open

            "PAD0_LEFTSTICK_CLICK":   "+sprint",
            "PAD0_RIGHTSTICK_CLICK":  "+kick",

            "PAD0_START":             "togglemenu",
            "PAD0_BACK":              "notebook",
            "PAD0_TOUCHPAD":          "+useitem",

            // The touchpad handles what a pad has no buttons left for. Up and
            // down are the scope's magnification, which the sniper rifle,
            // snooper and binoculars all use and which is otherwise only on the
            // mouse wheel.
            "PAD0_TOUCH_SWIPE_LEFT":  "weapprev",
            "PAD0_TOUCH_SWIPE_RIGHT": "weapnext",
            "PAD0_TOUCH_SWIPE_UP":    "zoomin",
            "PAD0_TOUCH_SWIPE_DOWN":  "zoomout",
            "PAD0_TOUCH_TAP":         "itemnext",

            // The D-pad is deliberately absent: it walks, like the arrow keys.
            //
            // So are the second stages of the triggers. They fire on a full pull
            // in addition to the soft stage, so anything bound here also happens
            // whenever the player shoots or aims hard. They are in the binding
            // editor for anyone who wants to build a two-stage layout on
            // purpose.
        ]
    }

    /// Bumped when the shipped control feel changes. A settings file written by
    /// an older build is ignored once, so a retune actually reaches the player
    /// instead of being overwritten by their stored copy of the old numbers.
    private static let tuningVersion = 2

    private func loadDefaults() {
        applyDefaultBindings()

        // Anything already set (a previous run) overrides the defaults.
        for pad in PadButton.all {
            let current = String(cString: IOSBridge_GetBinding(pad.id))
            if !current.isEmpty {
                bindings[pad.id] = current
            }
        }

        // Settings used to be write-only: every launch wrote these defaults over
        // whatever the player had chosen, so nothing they changed here survived.
        let stored = Int(cvar("in_tuningVersion") ?? "") ?? 0
        guard stored >= LauncherModel.tuningVersion else { return }

        sensitivity      = cvarValue("sensitivity", sensitivity)
        lookYawSpeed     = cvarValue("in_lookYawSpeed", lookYawSpeed)
        lookPitchSpeed   = cvarValue("in_lookPitchSpeed", lookPitchSpeed)
        stickExpo        = cvarValue("in_stickExpo", stickExpo)
        stickDeadzone    = cvarValue("joy_threshold", stickDeadzone)
        gyroSens         = cvarValue("in_gyroSens", gyroSens)
        rumble           = cvarValue("in_rumble", rumble)
        triggerHard      = cvarValue("in_triggerHard", triggerHard)
        fov              = cvarValue("cg_fov", fov)
        brightness       = cvarValue("r_gamma", brightness)

        gyroMode         = Int(cvarValue("in_gyro", Double(gyroMode)))
        touchControls    = Int(cvarValue("in_touchControls", Double(touchControls)))
        maxFPS           = Int(cvarValue("com_maxfps", Double(maxFPS)))
        skill            = Int(cvarValue("g_gameskill", Double(skill)))

        touchLookSens    = cvarValue("in_touchLookSens", touchLookSens)
        touchGyroSens    = cvarValue("in_touchGyroSens", touchGyroSens)
        moveExpo         = cvarValue("in_moveExpo", moveExpo)
        volume           = cvarValue("s_volume", volume)
        musicVolume      = cvarValue("s_musicvolume", musicVolume)
        crosshairSize    = cvarValue("cg_crosshairSize", crosshairSize)

        touchGyro        = cvarValue("in_touchGyro", touchGyro ? 1 : 0) != 0
        autoSwitch       = cvarValue("cg_autoswitch", autoSwitch ? 1 : 0) != 0
        viewBob          = cvarValue("cg_bobup", viewBob ? 1 : 0) != 0
        perfHud          = cvarValue("r_perfHud", perfHud ? 1 : 0) != 0
        perfLog          = cvarValue("r_perfLog", perfLog ? 1 : 0) != 0
        padLog           = cvarValue("in_debugPad", padLog ? 1 : 0) != 0

        invertLook       = cvarValue("in_invertLook", invertLook ? 1 : 0) != 0
        moveDigital      = cvarValue("in_moveDigital", moveDigital ? 1 : 0) != 0
        adaptiveTriggers = cvarValue("in_adaptiveTriggers", adaptiveTriggers ? 1 : 0) != 0
        hiDPI            = cvarValue("r_hidpi", hiDPI ? 1 : 0) != 0
    }

    private func cvar(_ name: String) -> String? {
        let value = String(cString: IOSBridge_GetCvar(name))
        return value.isEmpty ? nil : value
    }

    private func cvarValue(_ name: String, _ fallback: Double) -> Double {
        guard let text = cvar(name), let value = Double(text) else { return fallback }
        return value
    }

    func binding(for pad: PadButton) -> GameAction? {
        guard let cmd = bindings[pad.id] else { return nil }
        return GameAction.all.first { $0.id == cmd }
    }

    func assign(_ action: GameAction?, to pad: PadButton) {
        if let action {
            // One action per button: clear it from wherever it was.
            for (key, value) in bindings where value == action.id && key != pad.id {
                bindings.removeValue(forKey: key)
            }
            bindings[pad.id] = action.id
        } else {
            bindings.removeValue(forKey: pad.id)
        }
    }

    /// Push everything to the engine and write the config it will exec.
    func commit() {
        for (name, value) in preset.cvars {
            IOSBridge_SetCvar(name, value)
        }

        IOSBridge_SetCvar("com_maxfps", "\(maxFPS)")
        IOSBridge_SetCvar("r_hidpi", hiDPI ? "1" : "0")

        // -2 is "whatever the screen is", which is the only honest answer on a
        // device with one fixed panel. default.cfg inside pak0 sets r_mode 3 --
        // 640x480 in the mode table -- and that is what the game's own System
        // menu was reporting.
        IOSBridge_SetCvar("r_mode", "-2")
        IOSBridge_SetCvar("cg_fov", String(format: "%.0f", fov))
        IOSBridge_SetCvar("r_gamma", String(format: "%.2f", brightness))

        IOSBridge_SetCvar("sensitivity", String(format: "%.2f", sensitivity))

        // Stick feel. Turn rates are in degrees per second rather than an
        // opaque multiplier, and the movement stick keeps a flatter curve than
        // the look stick -- aiming wants a soft centre, walking does not.
        IOSBridge_SetCvar("in_gamepadDirect", "1")
        IOSBridge_SetCvar("in_moveDigital", moveDigital ? "1" : "0")
        IOSBridge_SetCvar("in_dpadMove", "1")
        IOSBridge_SetCvar("in_lookYawSpeed", String(format: "%.0f", lookYawSpeed))
        IOSBridge_SetCvar("in_lookPitchSpeed", String(format: "%.0f", lookPitchSpeed))
        IOSBridge_SetCvar("in_stickExpo", String(format: "%.2f", stickExpo))
        IOSBridge_SetCvar("in_moveExpo", String(format: "%.2f", moveExpo))
        IOSBridge_SetCvar("in_touchLookSens", String(format: "%.2f", touchLookSens))
        IOSBridge_SetCvar("in_touchGyro", touchGyro ? "1" : "0")
        IOSBridge_SetCvar("in_touchGyroSens", String(format: "%.2f", touchGyroSens))

        IOSBridge_SetCvar("s_volume", String(format: "%.2f", volume))
        IOSBridge_SetCvar("s_musicvolume", String(format: "%.2f", musicVolume))

        IOSBridge_SetCvar("cg_autoswitch", autoSwitch ? "1" : "0")
        IOSBridge_SetCvar("cg_bobup", viewBob ? "0.005" : "0")
        IOSBridge_SetCvar("cg_bobpitch", viewBob ? "0.002" : "0")
        IOSBridge_SetCvar("cg_bobroll", viewBob ? "0.002" : "0")
        IOSBridge_SetCvar("cg_crosshairSize", String(format: "%.0f", crosshairSize))

        IOSBridge_SetCvar("r_perfHud", perfHud ? "1" : "0")
        IOSBridge_SetCvar("r_perfLog", perfLog ? "1" : "0")
        IOSBridge_SetCvar("in_debugPad", padLog ? "1" : "0")
        IOSBridge_SetCvar("joy_threshold", String(format: "%.2f", stickDeadzone))
        IOSBridge_SetCvar("in_invertLook", invertLook ? "1" : "0")
        IOSBridge_SetCvar("in_gyro", "\(gyroMode)")
        IOSBridge_SetCvar("in_gyroSens", String(format: "%.2f", gyroSens))
        IOSBridge_SetCvar("in_rumble", String(format: "%.0f", rumble))
        IOSBridge_SetCvar("in_adaptiveTriggers", adaptiveTriggers ? "1" : "0")
        IOSBridge_SetCvar("in_triggerHard", String(format: "%.2f", triggerHard))
        IOSBridge_SetCvar("in_touchControls", "\(touchControls)")
        IOSBridge_SetCvar("in_joystick", "1")

        // pmove_fixed is deliberately left alone.
        //
        // It makes movement frame-rate independent, which is tempting at 120Hz,
        // but g_active.c applies it to every client -- there is no per-client
        // switch in this tree, pers.pmoveFixed is read and never set. So turning
        // it on also runs every AI cast's physics in 8ms steps instead of the
        // stock single step per think, which is a change to how the game's
        // characters move that the original never had. Not a trade worth making
        // for a single-player nicety.
        IOSBridge_SetCvar("pmove_fixed", "0")

        IOSBridge_SetCvar("in_tuningVersion", "\(LauncherModel.tuningVersion)")

        // Give the engine room; the default 256MB hunk is tight for the larger
        // campaign maps and an iPad has plenty.
        IOSBridge_SetCvar("com_hunkMegs", "512")

        for (key, action) in bindings {
            IOSBridge_SetBinding(key, action)
        }

        IOSBridge_WriteConfig()
    }

    func play() {
        commit()
        IOSBridge_SetStartupCommand("")
        IOSBridge_LauncherFinished()
    }

    /// Start a mission directly, skipping the game's own menus.
    func startMission(_ mission: CampaignMission) {
        commit()
        IOSBridge_SetCvar("g_gameskill", "\(skill)")
        IOSBridge_SetCvar("g_missionLoadout", "\(mission.chapter)")
        IOSBridge_SetStartupCommand("spmap \(mission.id)")
        IOSBridge_LauncherFinished()
    }
}
