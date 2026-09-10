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
            return "Полное разрешение, анизотропная фильтрация, динамический свет и тени. M5 тянет это с запасом."
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

            // Geometry. Lower subdivisions means finer curves.
            "r_subdivisions": "1",
            "r_lodbias": "0",
            "r_lodCurveError": "999",

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
    @Published var touchControls: Int = 1   // shown always; the pad does not replace touch
    @Published var invertLook: Bool = false
    @Published var moveDigital: Bool = true
    @Published var skill: Int = 2          // g_gameskill: 1 easy .. 4 death incarnate

    // Bindings, keyed by engine key name
    @Published var bindings: [String: String] = [:]

    @Published var controllerName: String? = nil

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

        dataMask = Int(IOSBridge_GameDataMask())
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
        IOSBridge_SetCvar("in_moveExpo", "0.15")
        IOSBridge_SetCvar("joy_threshold", String(format: "%.2f", stickDeadzone))
        IOSBridge_SetCvar("in_invertLook", invertLook ? "1" : "0")
        IOSBridge_SetCvar("in_gyro", "\(gyroMode)")
        IOSBridge_SetCvar("in_gyroSens", String(format: "%.2f", gyroSens))
        IOSBridge_SetCvar("in_rumble", String(format: "%.0f", rumble))
        IOSBridge_SetCvar("in_adaptiveTriggers", adaptiveTriggers ? "1" : "0")
        IOSBridge_SetCvar("in_triggerHard", String(format: "%.2f", triggerHard))
        IOSBridge_SetCvar("in_touchControls", "\(touchControls)")
        IOSBridge_SetCvar("in_joystick", "1")

        // Framerate-independent movement. Q3-lineage physics is tied to the
        // frame rate (the classic 125fps jump), and RTCW's default com_maxfps of
        // 76 exists to dodge that. Since this is single player, fixing pmove is
        // the cleaner answer and it makes 120Hz safe.
        IOSBridge_SetCvar("pmove_fixed", "1")
        IOSBridge_SetCvar("pmove_msec", "8")

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
        IOSBridge_SetStartupCommand("spmap \(mission.id)")
        IOSBridge_LauncherFinished()
    }
}
