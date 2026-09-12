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
        GameAction(id: "weapalt",    title: "Режим оружия",       group: "Бой"),
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
        // Multiplayer's own commands. The campaign does not register these and
        // the campaign's notebook is not registered in multiplayer -- one
        // binding list, two games, and a binding the running game has never
        // heard of simply does nothing.
        GameAction(id: "+dropweapon", title: "Бросить оружие",    group: "Мультиплеер"),
        GameAction(id: "help",        title: "Помощь (MP)",       group: "Мультиплеер"),
        GameAction(id: "+scores",     title: "Таблица очков",     group: "Мультиплеер"),
        GameAction(id: "messagemode", title: "Написать всем",     group: "Мультиплеер"),
        GameAction(id: "messagemode2", title: "Написать команде", group: "Мультиплеер"),
        // The names default.cfg binds to F5 and F9. "save quick" was neither a
        // command nor an argument the engine knows, so binding it did nothing.
        GameAction(id: "savegame quicksave", title: "Быстрое сохранение", group: "Система"),
        GameAction(id: "loadgame quicksave", title: "Быстрая загрузка",   group: "Система"),
        GameAction(id: "togglemenu", title: "Меню",               group: "Система"),
    ]

    static var groups: [String] { ["Бой", "Движение", "Действия", "Мультиплеер", "Система"] }
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
            // Without this the pixel format comes back with no stencil at
            // all, and cg_shadows 2 -- what "Максимум" asks for -- draws
            // nothing: tr_shadows.c bails when stencilBits < 4, and
            // cg_players.c only draws the cheap blob at exactly 1. So the
            // top preset was the one setting with no character shadows of
            // any kind, worse than the preset below it. The device reports
            // GL_OES_stencil8, so eight bits is there for the asking.
            "r_stencilbits": "8",
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

/// A campaign the launcher can start: the retail one, or one of the fan
/// campaigns from the Russian anthology installed beside it.
///
/// Those are pure data -- maps, AAS, scripts, menus, text, sound -- and this
/// engine plays them unmodified, each out of a folder of its own with fs_game
/// pointed at it. The bridge owns the list of folders, because the importer has
/// to know it too; what lives here is what only the launcher cares about: what
/// to call a campaign and which maps it contains, in which order.
///
/// The order is not guesswork. It is the chain of `changelevel` commands in the
/// campaign's own .ai scripts -- how RTCW actually moves the player from one
/// map to the next -- read out of each pk3. Maps outside that chain are left
/// out on purpose: they are duplicates of retail levels the campaign ships
/// unchanged, or test maps its author never wired up, and neither is part of
/// the story it tells.
///
/// Mission names are the map names, with the campaign's own title where it
/// gives one in its briefing. Inventing Russian names for a hundred maps whose
/// authors never named them would put words in their mouths, and the player
/// picking a mission out of the grid is served by the name the game itself
/// uses.
struct Campaign: Identifiable, Hashable {
    let id: String              // fs_game folder; empty is the retail campaign
    let title: String
    let maps: [String]
    let names: [String: String] // map -> the campaign's own name for it

    var isRetail: Bool { id.isEmpty }
    var startMap: String { maps.first ?? "" }

    var missions: [CampaignMission] {
        guard !isRetail else { return CampaignMission.all }

        // Translated here rather than at the tile: the number is part of the
        // title the retail campaign already carries, so a tile that put one in
        // front of what it was given would number those twice. Read on every
        // redraw, which is what a language switch causes.
        return maps.enumerated().map { index, map in
            let name = names[map].map { Loc.s($0) } ?? map
            return CampaignMission(id: map, title: "\(index + 1). \(name)")
        }
    }

    static let retail = Campaign(id: "", title: "Оригинальная кампания",
                                 maps: CampaignMission.all.map(\.id), names: [:])

    /// The ten campaigns of the anthology, every one of them verified to load
    /// on this engine. Ordered the way the anthology's own installer lists
    /// them: the full-length ones first, the demo last.
    static let extras: [Campaign] = [
        Campaign(id: "time_gate", title: "Врата времени",
                 maps: ["cutscene1", "tomb2", "tomb3", "tomb4", "vil01", "vil02",
                        "berg", "bergwerk", "ber", "labor1", "labor1a", "labor2",
                        "labor3", "fin"],
                 names: [:]),

        Campaign(id: "stalingrad", title: "Сталинград",
                 maps: ["cutscene1", "demo1", "demo2", "demo3", "cine8", "demo4",
                        "demo5", "cine9", "demo6", "demo7", "demo8", "demo9",
                        "demo55a", "demo10", "cine5"],
                 names: [:]),

        Campaign(id: "saboteur", title: "Диверсант",
                 maps: ["normandy", "seabase", "techicalbunker", "support",
                        "UnderBase", "UnderBase2", "SecretWeapon",
                        "SecretWeapon2", "Endmission"],
                 names: ["normandy": "Прибрежная полоса",
                         "seabase": "Морская крепость",
                         "techicalbunker": "Техническая часть базы",
                         "support": "Инженерный бункер"]),

        Campaign(id: "ghosts_of_war", title: "Призраки войны",
                 maps: ["cutscene1", "roadtobase2", "darkforest", "darkcastle",
                        "darkchurch", "darkcrypt1", "darkcrypt2", "statement",
                        "darkend"],
                 names: [:]),

        Campaign(id: "red_alert", title: "Красная тревога",
                 maps: ["cutscene1", "50a", "50b", "50b_1", "50c", "505", "50d",
                        "50e", "506", "50e_1", "50f", "50j"],
                 names: [:]),

        Campaign(id: "special_forces", title: "Спецназ",
                 maps: ["cutscene1", "30s", "30", "30a", "30b", "30c", "30d",
                        "30f", "30j"],
                 names: [:]),

        Campaign(id: "project_51", title: "Проект 51",
                 maps: ["cutscene1", "pro2", "pro3", "pro4", "pro5", "pro6",
                        "pro7", "pro8", "pro9", "pro10", "pro11", "pro12"],
                 names: [:]),

        Campaign(id: "pharaohs_curse", title: "Проклятие фараона",
                 maps: ["intro_grobnica", "level1", "level2", "level3", "level4",
                        "level5"],
                 names: [:]),

        // The one campaign whose .ai scripts name no successor: it moves the
        // player on from trigger entities inside the maps instead. Listed in
        // the order its own pk3 numbers them.
        Campaign(id: "the_rate_is_more_than_life", title: "Ставка больше, чем жизнь",
                 maps: ["dd", "2222", "77", "map4_1", "map5"],
                 names: [:]),

        Campaign(id: "project_x", title: "Проект X (демо)",
                 maps: ["piramid", "tomb1"],
                 names: [:]),
    ]

    static let all: [Campaign] = [retail] + extras
}

/// Which of the two sets of game data something belongs to.
///
/// The raw values are the engine side's IOS_DATA_SET_*, and they are written
/// out here rather than imported from the bridge: a bare C enum and a typedef'd
/// one arrive in Swift as two different kinds of thing, and the launcher should
/// not have to be edited because the header changed its mind about which it is.
enum DataSetKind: Int32, CaseIterable, Identifiable {
    case campaign = 0
    case multiplayer = 1

    var id: Int32 { rawValue }
}

/// One file a set expects, and whether it is on the device.
struct DataFileState: Identifiable, Hashable {
    let name: String
    let present: Bool
    /// The set cannot be played without it. pak0.pk3 is the case that matters:
    /// its absence is a fatal error inside FS_Startup rather than a level the
    /// player never reaches.
    let required: Bool

    var id: String { name }
}

/// A whole set: the files it wants, and what the ones that are there add up to.
///
/// The numbers are read from the pk3 directories rather than worked out from
/// the filenames, so they describe what the engine will actually find.
struct DataSetState: Identifiable, Hashable {
    let kind: DataSetKind
    let files: [DataFileState]
    let maps: Int
    let entries: Int
    let megabytes: Double
    /// The files the engine cannot start without are all there.
    let isPlayable: Bool
    /// What the player has is what they should have: the complete set at the
    /// last official patch level, nothing missing and nothing wearing an id
    /// pak's name. Stricter than `isPlayable`, which asks only whether it runs.
    let isRecommended: Bool

    var id: Int32 { kind.rawValue }

    /// Everything the set lists is present -- stricter than `isPlayable`, which
    /// asks only for the files without which there is nothing to start.
    var isComplete: Bool { !files.isEmpty && files.allSatisfy(\.present) }
}

@MainActor
final class LauncherModel: ObservableObject {
    // Game data
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
    // Per-axis overrides for the figure above. Zero is not a sensitivity here,
    // it is the absence of one: the engine reads it as "this axis has nothing
    // of its own, use the common number" (IN_AxisSens). So zero must never be
    // something a slider can be dragged to -- see `gyroSplitAxes`.
    @Published var gyroYawSens: Double = 0
    @Published var gyroPitchSens: Double = 0
    // Whether a sensor hands its axes over the way the documentation says is
    // not something any code here can find out: a driver that has one mirrored
    // looks exactly like one that does not until somebody turns and watches the
    // view go the other way. So the player decides. These two are the
    // controller's alone now: the iPad's sensor is read through a different
    // path and carries its own pair, `touchGyroInvert*`.
    @Published var gyroInvertYaw: Bool = false
    @Published var gyroInvertPitch: Bool = false
    // Where the horizontal half of the gyro comes from: 0 the pad turning flat,
    // 1 the pad tipping left and right, 2 the two added together. Roll is the
    // default because it is the wrists that do it, and the wrists are steadier
    // than the arm the flat turn comes from.
    @Published var gyroYawSource: Int = 1
    @Published var rumble: Double = 100
    // A kick when a shot lands on someone, which is a different thing from the
    // vibration for damage taken and is switched separately: one is information
    // the player needs, the other is the weapon having weight.
    @Published var rumbleImpact: Bool = true
    // How hard that kick is, as a multiplier on it and on nothing else: the
    // vibration for damage taken keeps its own strength. A player who wants to
    // feel their shots land without being shaken by them turns this down rather
    // than turning the motors down, which would take the damage warning with it.
    @Published var rumbleImpactScale: Double = 1.0
    @Published var adaptiveTriggers: Bool = true
    @Published var triggerHard: Double = 0.75
    @Published var touchControls: Int = 0   // automatic: follows the hand, see ios_touch.m
    @Published var touchLookSens: Double = 1.0
    @Published var touchLookYawSens: Double = 0
    @Published var touchLookPitchSens: Double = 0
    // Three states, not two: 0 off, 1 only while no controller is connected --
    // which is all it ever used to do, and what a config already carrying
    // `in_touchGyro 1` still means -- and 2 always, adding to the controller's
    // gyro instead of standing in for it. It was carried here as a Bool for a
    // while after the engine grew the third state, and that quietly turned a
    // player's 2 back into a 1 the first time the launcher saved anything.
    @Published var touchGyro: Int = 0
    @Published var touchGyroSens: Double = 1.0
    @Published var touchGyroYawSens: Double = 0
    @Published var touchGyroPitchSens: Double = 0
    @Published var touchGyroInvertYaw: Bool = false
    @Published var touchGyroInvertPitch: Bool = false
    @Published var moveExpo: Double = 0.15

    // Sound
    @Published var volume: Double = 0.8
    @Published var musicVolume: Double = 0.5

    // Game
    //
    // cg_autoswitch is a mode rather than a flag: 0 never, 1 always, 2 when the
    // weapon is new to the arsenal, 3 when it sits in a better bank, 4 either,
    // 5 both. 2 is the game's own default and what the campaign is built
    // around; the launcher used to write 1, Quake III's rule, which hands the
    // player a duplicate of a gun they already carry.
    @Published var autoSwitch: Int = 2
    @Published var autoActivate: Bool = true
    @Published var emptySwitch: Bool = false
    @Published var viewBob: Bool = true
    @Published var crosshairSize: Double = 48

    // Diagnostics
    @Published var perfHud: Bool = false
    @Published var perfLog: Bool = false
    @Published var padLog: Bool = false
    @Published var invertLook: Bool = false
    @Published var moveDigital: Bool = true
    @Published var skill: Int = 2          // g_gameskill: 1 easy .. 4 death incarnate

    // MARK: - Кампания

    /// Which campaign the Campaign tab is showing, as its fs_game folder.
    ///
    /// Kept in UserDefaults rather than in ios_launcher.cfg, because it is not
    /// a cvar: fs_game is read by FS_Startup before any config is exec'd, so it
    /// reaches the engine on the command line and nothing would ever read it
    /// back out of the file. Remembered all the same -- a player halfway
    /// through a fan campaign should not land on the retail one every launch.
    @Published var campaignID: String = UserDefaults.standard.string(forKey: "IORTCWCampaign") ?? "" {
        didSet {
            guard campaignID != oldValue else { return }
            UserDefaults.standard.set(campaignID, forKey: "IORTCWCampaign")
        }
    }

    /// Which of the extra campaigns are actually on the device, refreshed by
    /// the same once-a-second poll that watches for the retail paks.
    @Published var installedCampaigns: [String] = []

    /// The campaign in play, falling back to the retail one if what was
    /// remembered has since been deleted off the device.
    var campaign: Campaign {
        guard let found = Campaign.all.first(where: { $0.id == campaignID }),
              found.isRetail || installedCampaigns.contains(found.id) else {
            return .retail
        }

        return found
    }

    /// What the picker offers: the retail campaign always, and every extra one
    /// whose pak is installed and readable.
    var availableCampaigns: [Campaign] {
        [.retail] + Campaign.extras.filter { installedCampaigns.contains($0.id) }
    }

    /// How many maps and how much data an installed campaign holds, straight
    /// from the bridge's scan of its pk3.
    func campaignSummary(_ campaign: Campaign) -> (maps: Int, megabytes: Double)? {
        guard !campaign.isRetail else { return nil }

        for index in 0..<Int(IOSBridge_CampaignModCount())
        where String(cString: IOSBridge_CampaignModDir(Int32(index))) == campaign.id {
            return (Int(IOSBridge_CampaignModMaps(Int32(index))),
                    IOSBridge_CampaignModMegabytes(Int32(index)))
        }

        return nil
    }

    // MARK: - Раздельные оси

    /// Whether a group of sensitivities has its two axes set apart, and the
    /// switch that sets them apart. Three groups have the pair: the
    /// controller's gyro, the iPad's, and looking about with a finger.
    ///
    /// There is no engine key behind these and there must not be one. The
    /// engine already answers the question -- a per-axis key holding zero means
    /// that axis has nothing of its own and falls through to the common figure
    /// (IN_AxisSens) -- so "are they apart" is exactly "is either of them
    /// non-zero", and it reads back out of the config on the next launch
    /// without anything having to be stored to say so. A key of our own would
    /// be a second copy of that answer, free to drift out of step with it.
    ///
    /// Turning the switch on seeds both axes from the common figure rather than
    /// from some default, so what changes at that moment is the screen and not
    /// the way the game feels under the hands. Turning it off cannot do the
    /// same in reverse -- two numbers do not collapse into one without throwing
    /// one of them away -- so it clears the pair, and the common slider comes
    /// back showing, as it always did, the figure that is now in force. Nothing
    /// is hidden either way: whatever slider is on screen is what is applied.
    var gyroSplitAxes: Bool {
        get { splitAxes(gyroYawSens, gyroPitchSens) }
        set { setSplitAxes(newValue, common: \.gyroSens,
                           yaw: \.gyroYawSens, pitch: \.gyroPitchSens) }
    }

    var touchGyroSplitAxes: Bool {
        get { splitAxes(touchGyroYawSens, touchGyroPitchSens) }
        set { setSplitAxes(newValue, common: \.touchGyroSens,
                           yaw: \.touchGyroYawSens, pitch: \.touchGyroPitchSens) }
    }

    var touchLookSplitAxes: Bool {
        get { splitAxes(touchLookYawSens, touchLookPitchSens) }
        set { setSplitAxes(newValue, common: \.touchLookSens,
                           yaw: \.touchLookYawSens, pitch: \.touchLookPitchSens) }
    }

    private func splitAxes(_ yaw: Double, _ pitch: Double) -> Bool {
        yaw > 0 || pitch > 0
    }

    private func setSplitAxes(_ on: Bool,
                              common: ReferenceWritableKeyPath<LauncherModel, Double>,
                              yaw: ReferenceWritableKeyPath<LauncherModel, Double>,
                              pitch: ReferenceWritableKeyPath<LauncherModel, Double>) {
        guard on else {
            self[keyPath: yaw] = 0
            self[keyPath: pitch] = 0
            return
        }

        // Only an axis that has nothing of its own is seeded. Coming back to a
        // group that was already split has to find the numbers that were left
        // there, not the common figure written over them.
        let seed = self[keyPath: common]
        if self[keyPath: yaw] <= 0 { self[keyPath: yaw] = seed }
        if self[keyPath: pitch] <= 0 { self[keyPath: pitch] = seed }
    }

    // Bindings, keyed by engine key name
    @Published var bindings: [String: String] = [:]

    // Diagnostics. On by default for now: the port is new enough that the next
    // fix usually starts with a log, and a log nobody switched on is a log
    // nobody has.
    @Published var diagVerboseLog: Bool = true
    @Published var diagPerfHud: Bool = false
    @Published var diagPerfLog: Bool = true

    @Published var controllerName: String? = nil

    /// Multiplayer settings, hosting included. Built in both applications so the
    /// type is always available; only the MP launcher shows the tabs that use
    /// it, and only its commit() writes any of it out.
    let mp = MultiplayerModel()

    /// One application, both games, so every tab is offered. The name is kept
    /// because the tabs and a few notes read it.
    var isMultiplayer: Bool { true }

    // What is actually in the pk3s, read from their directories rather than
    // taken on faith from the filenames being present. Both sets, in the order
    // DataSetKind lists them.
    @Published private(set) var dataSets: [DataSetState] = []

    func dataSet(_ kind: DataSetKind) -> DataSetState? {
        dataSets.first { $0.kind == kind }
    }

    /// "0.4.0" -- the port's version, not the engine's.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// The build number, which only ever goes up. It replaced the build time in
    /// this readout: a timestamp says when a binary was made and nothing about
    /// which one it is, and the one a player reads out when something is wrong
    /// has to be a number two people can compare.
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// The commit the build came from, short form, with "-dirty" on it when the
    /// tree had uncommitted work in it. Missing when git was not there to ask,
    /// and then nothing is shown rather than a placeholder that looks like a
    /// hash.
    var buildCommit: String? {
        guard let hash = Bundle.main.infoDictionary?["IORTCWGitHash"] as? String,
              !hash.isEmpty else { return nil }
        return hash
    }

    /// "iortcw 1.51d-SP ios-arm64", the engine's own version string.
    var engineVersion: String { String(cString: IOSBridge_EngineVersion()) }

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// The launcher used to carry the campaign's five filenames as a list of
    /// its own, and to work out from a bitmask over them whether the set was
    /// complete. The bridge owns both lists now -- it is the side that knows
    /// which files an engine build refuses to start without -- and each section
    /// of the Data tab asks its own set. What is left here is the one question
    /// the rest of the launcher asks: can the game be started at all.
    ///
    /// The campaign set answers it, not IOSBridge_HasGameData(). That one only
    /// opens main/pak0.pk3, which is enough for the engine to boot and not
    /// enough for there to be a campaign -- FS_CheckSPPaks raises a fatal error
    /// unless sp_pak1 through sp_pak4 are all there, so offering Play with pak0
    /// alone offers a crash on startup. The Data tab already refuses to call
    /// that set complete; the footer and the Play block now agree with it.
    /// The fallback keeps the old answer for the moment before the first scan.
    var canPlay: Bool { canPlayCampaign }

    /// The campaign needs pak0 and sp_pak1..4; multiplayer needs pak0 and
    /// mp_pak0..5. A player may well have one set and not the other, and the
    /// two buttons in the footer light up independently because of it.
    var canPlayCampaign: Bool {
        dataSet(.campaign)?.isPlayable ?? IOSBridge_HasGameData()
    }

    var canPlayMultiplayer: Bool {
        dataSet(.multiplayer)?.isPlayable ?? false
    }

    /// The set this application is actually about. The campaign build needs
    /// sp_pak1..4 and does not care about the multiplayer paks; the multiplayer
    /// build is the other way round, and judging it by the campaign's files
    /// would grey out Play on a copy that can join every server on the network.
    var primarySet: DataSetKind { .campaign }

    init() {
        dataPath = String(cString: IOSBridge_DataPath())
        refreshData()
        loadDefaults()
        observeControllers()

        // The game's language follows the launcher's, including across a
        // restart: the paks may have been copied in since the last run, or the
        // language chosen on a launch where they were not there yet. Costs a
        // pair of stats when nothing has to move.
        applyLanguage(Loc.current, writeConfig: false)

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

        // Forced on every pass, because forcing it is what this poll is for:
        // the files are being copied in with this screen open and the lists
        // have to tick over as they land, rather than making the player relaunch
        // for them. The bridge is built to be polled -- a forced rescan reopens
        // only the pk3s whose size or timestamp moved, so a pass over an
        // unchanged folder costs a stat per file. The scan also covers the
        // multiplayer set, which the old campaign-only mask never saw.
        _ = IOSBridge_ScanData(true)

        // Assigned only when something differs. This runs once a second, and a
        // published value handed identical contents still redraws the tab.
        let fresh = DataSetKind.allCases.map { snapshot(of: $0) }
        if fresh != dataSets {
            dataSets = fresh
        }

        // Same treatment for the extra campaigns: their folders are watched by
        // this poll, so a campaign copied in with the launcher open turns up in
        // the picker without a relaunch.
        var present: [String] = []
        for index in 0..<Int(IOSBridge_CampaignModCount())
        where IOSBridge_CampaignModInstalled(Int32(index)) {
            present.append(String(cString: IOSBridge_CampaignModDir(Int32(index))))
        }

        if present != installedCampaigns {
            installedCampaigns = present
        }
    }

    /// One pass over a set, straight from the bridge.
    private func snapshot(of kind: DataSetKind) -> DataSetState {
        let set = kind.rawValue
        var files: [DataFileState] = []
        for index in 0..<IOSBridge_SetFileCount(set) {
            // A name that came back empty would be a bridge that disagrees with
            // its own count; skip it rather than putting a blank row on screen.
            guard let name = IOSBridge_SetFileName(set, index) else { continue }
            files.append(DataFileState(name: String(cString: name),
                                       present: IOSBridge_SetFilePresent(set, index),
                                       required: IOSBridge_SetFileRequired(set, index)))
        }

        return DataSetState(kind: kind,
                            files: files,
                            maps: Int(IOSBridge_SetMaps(set)),
                            entries: Int(IOSBridge_SetFiles(set)),
                            megabytes: IOSBridge_SetMegabytes(set),
                            isPlayable: IOSBridge_SetIsPlayable(set),
                            isRecommended: IOSBridge_SetIsRecommended(set))
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
            // Triggers do the shooting. Above them the shoulders move the
            // player, and the face buttons change the weapon -- the opposite
            // way round from the usual console layout, and on purpose.
            //
            // Of the two shoulders R1 is the one under the stronger finger,
            // the one already lying over the fire trigger, and it goes to jump.
            // Jump is the timed action of the pair: it has to land on an exact
            // moment -- a gap, a ledge, a grenade at the feet -- and a jump a
            // beat late is a jump that did not happen. Crouch is held rather
            // than aimed. It goes down before the shooting starts and stays
            // down, which is what a finger resting on L1 does well, and the
            // right hand is left free to keep firing while it is held. This is
            // the way round it was played on the device; the first pass had the
            // two swapped, on the reasoning that crouch belongs under the
            // trigger finger, and that turned out to be the wrong half of the
            // pair to spend the good finger on.
            //
            // Changing weapon is the opposite kind of act -- it happens between
            // fights, not during one -- so it goes to the face buttons, where
            // the thumb has time to leave the stick for it.
            "PAD0_RIGHTTRIGGER":      "+attack",
            "PAD0_LEFTTRIGGER":       "+zoom",
            "PAD0_RIGHTSHOULDER":     "+moveup",     // R1 -- jump, over the trigger
            "PAD0_LEFTSHOULDER":      "+movedown",   // L1 -- crouch, over the aim

            "PAD0_A":                 "weapprev",    // Cross  -- previous weapon
            "PAD0_B":                 "weapnext",    // Circle -- next weapon
            "PAD0_X":                 "+reload",     // Square -- reload
            "PAD0_Y":                 "+activate",   // Triangle -- use/open

            // Sprint is held down for as long as the player is running, and
            // clicking the stick that is being shoved into a corner at the same
            // time is both awkward and easy to set off by accident. So it sits
            // on the aiming stick, and the kick -- one deliberate tap, never
            // held -- takes the movement stick.
            "PAD0_LEFTSTICK_CLICK":   "+kick",
            "PAD0_RIGHTSTICK_CLICK":  "+sprint",

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

    /// Bumped when a shipped default changes in a way that has to reach players
    /// who already have a config. Their stored value wins over a default, as it
    /// should -- so without this a retune would only ever be seen on a fresh
    /// install.
    ///
    /// It used to work by ignoring a stale config wholesale. That cost the
    /// player every unrelated setting they had -- brightness, volume, field of
    /// view, difficulty -- for the sake of one retuned number, and because
    /// `in_tuningVersion` could not be read back before the engine was up it
    /// fired on every single launch instead of once. Each bump now names the
    /// one-off fix it needs and touches nothing else; see `migrate(from:)`.
    private static let tuningVersion = 6

    /// gfx/2d/crosshairi: four detached ticks around an open centre with a dot
    /// in it. cg_drawCrosshair indexes gfx/2d/crosshair'a'+n (cg_main.c), and of
    /// the ten shipped shapes this is the only one that is a cross with a centre
    /// dot; the alternatives are either a solid plus that hides what is behind
    /// it, or a faint disc that covers a good part of the screen once
    /// cg_crosshairSize is turned up for a tablet.
    private static let defaultCrosshair = 8

    /// Whether the crosshair shape still has to be handed to the player. See
    /// `migrate(from:)` for why it is written once rather than every launch.
    private var seedsCrosshair = false

    private func loadDefaults() {
        applyDefaultBindings()

        let stored = Int(cvar("in_tuningVersion") ?? "") ?? 0

        // Anything already set (a previous run) overrides the defaults.
        //
        // From version 3 the config lists every button the launcher knows,
        // cleared ones included as an empty bind, so an empty value means the
        // player took that button off -- moved its action elsewhere, most
        // likely -- and the default must not walk back in behind them. An older
        // config only lists what was bound, and there an empty value is
        // genuinely "no idea", so the default is the better answer.
        for pad in PadButton.all {
            let current = String(cString: IOSBridge_GetBinding(pad.id))
            if !current.isEmpty {
                bindings[pad.id] = current
            } else if stored >= 3 {
                bindings.removeValue(forKey: pad.id)
            }
        }

        // Settings used to be write-only: every launch wrote these defaults over
        // whatever the player had chosen, so nothing they changed here survived.
        // They are read back from the config the engine is about to exec, which
        // ios_bridge.c now parses when the engine is not up yet -- before that
        // every value below came back empty and fell through to its default.
        sensitivity      = cvarValue("sensitivity", sensitivity)
        lookYawSpeed     = cvarValue("in_lookYawSpeed", lookYawSpeed)
        lookPitchSpeed   = cvarValue("in_lookPitchSpeed", lookPitchSpeed)
        stickExpo        = cvarValue("in_stickExpo", stickExpo)
        stickDeadzone    = cvarValue("joy_threshold", stickDeadzone)
        gyroSens         = cvarValue("in_gyroSens", gyroSens)
        gyroYawSens      = cvarValue("in_gyroYawSens", gyroYawSens)
        gyroPitchSens    = cvarValue("in_gyroPitchSens", gyroPitchSens)
        rumble           = cvarValue("in_rumble", rumble)
        triggerHard      = cvarValue("in_triggerHard", triggerHard)
        fov              = cvarValue("cg_fov", fov)
        brightness       = cvarValue("r_gamma", brightness)

        gyroMode         = Int(cvarValue("in_gyro", Double(gyroMode)))
        gyroYawSource    = Int(cvarValue("in_gyroYawSource", Double(gyroYawSource)))
        touchControls    = Int(cvarValue("in_touchControls", Double(touchControls)))
        // Three states since the iPad's gyro stopped standing down for the
        // controller's. Read as a number, or a config saying 2 comes back as a
        // 1 and the next save writes the player's choice away.
        touchGyro        = Int(cvarValue("in_touchGyro", Double(touchGyro)))
        maxFPS           = Int(cvarValue("com_maxfps", Double(maxFPS)))
        skill            = Int(cvarValue("g_gameskill", Double(skill)))

        touchLookSens    = cvarValue("in_touchLookSens", touchLookSens)
        touchLookYawSens = cvarValue("in_touchLookYawSens", touchLookYawSens)
        touchLookPitchSens = cvarValue("in_touchLookPitchSens", touchLookPitchSens)
        touchGyroSens    = cvarValue("in_touchGyroSens", touchGyroSens)
        touchGyroYawSens = cvarValue("in_touchGyroYawSens", touchGyroYawSens)
        touchGyroPitchSens = cvarValue("in_touchGyroPitchSens", touchGyroPitchSens)
        moveExpo         = cvarValue("in_moveExpo", moveExpo)
        volume           = cvarValue("s_volume", volume)
        musicVolume      = cvarValue("s_musicvolume", musicVolume)
        crosshairSize    = cvarValue("cg_crosshairSize", crosshairSize)

        autoSwitch       = Int(cvarValue("cg_autoswitch", Double(autoSwitch)))
        autoActivate     = cvarValue("cg_autoactivate", autoActivate ? 1 : 0) != 0
        emptySwitch      = cvarValue("cg_emptyswitch", emptySwitch ? 1 : 0) != 0
        viewBob          = cvarValue("cg_bobup", viewBob ? 1 : 0) != 0
        perfHud          = cvarValue("r_perfHud", perfHud ? 1 : 0) != 0
        perfLog          = cvarValue("r_perfLog", perfLog ? 1 : 0) != 0
        padLog           = cvarValue("in_debugPad", padLog ? 1 : 0) != 0

        invertLook       = cvarValue("in_invertLook", invertLook ? 1 : 0) != 0
        gyroInvertYaw    = cvarValue("in_gyroInvertYaw", gyroInvertYaw ? 1 : 0) != 0
        gyroInvertPitch  = cvarValue("in_gyroInvertPitch", gyroInvertPitch ? 1 : 0) != 0
        touchGyroInvertYaw   = cvarValue("in_touchGyroInvertYaw", touchGyroInvertYaw ? 1 : 0) != 0
        touchGyroInvertPitch = cvarValue("in_touchGyroInvertPitch", touchGyroInvertPitch ? 1 : 0) != 0
        moveDigital      = cvarValue("in_moveDigital", moveDigital ? 1 : 0) != 0
        adaptiveTriggers = cvarValue("in_adaptiveTriggers", adaptiveTriggers ? 1 : 0) != 0
        rumbleImpact     = cvarValue("cg_rumbleImpact", rumbleImpact ? 1 : 0) != 0
        rumbleImpactScale = cvarValue("cg_rumbleImpactScale", rumbleImpactScale)
        hiDPI            = cvarValue("r_hidpi", hiDPI ? 1 : 0) != 0

        diagVerboseLog   = cvarValue("developer", diagVerboseLog ? 1 : 0) != 0
        diagPerfHud      = cvarValue("r_perfHud", diagPerfHud ? 1 : 0) != 0
        diagPerfLog      = cvarValue("r_perfLog", diagPerfLog ? 1 : 0) != 0

        migrate(from: stored)
    }

    /// One-off fixes for a config written by an older build, applied on the
    /// launch that first sees it.
    ///
    /// Deliberately surgical. A migration overrides a stored value only when
    /// that value is the default the older build shipped: if the player has
    /// chosen something of their own it stays, because a change of mind on our
    /// side is not a reason to overrule them. Nothing here may write a default
    /// over a setting it does not name.
    private func migrate(from stored: Int) {
        // 3: kick and sprint changed places on the stick clicks. Anyone who has
        // played before is carrying the old pair, and a stored binding wins over
        // a default, so without this the new layout would never arrive.
        if stored < 3,
           bindings["PAD0_LEFTSTICK_CLICK"] == "+sprint",
           bindings["PAD0_RIGHTSTICK_CLICK"] == "+kick" {
            bindings["PAD0_LEFTSTICK_CLICK"] = "+kick"
            bindings["PAD0_RIGHTSTICK_CLICK"] = "+sprint"
        }

        // 4: the shoulders took over movement and the face buttons took over
        // weapons, for the reasons written out in applyDefaultBindings(). Moved
        // only for a player still carrying exactly the old four: anyone who put
        // something else on any of them arranged it that way on purpose, and a
        // change of mind here is not a reason to overrule it. It touches no
        // button the bump above does, so a config still on version 2 takes both
        // in turn and gets the same layout a fresh install would.
        if stored < 4,
           bindings["PAD0_RIGHTSHOULDER"] == "weapnext",
           bindings["PAD0_LEFTSHOULDER"] == "weapprev",
           bindings["PAD0_A"] == "+moveup",
           bindings["PAD0_B"] == "+movedown" {
            bindings["PAD0_RIGHTSHOULDER"] = "+movedown"
            bindings["PAD0_LEFTSHOULDER"] = "+moveup"
            bindings["PAD0_A"] = "weapprev"
            bindings["PAD0_B"] = "weapnext"
        }

        // 5: jump and crouch changed places on the shoulders, after the pair
        // was played on the device the way version 4 shipped it. Only for a
        // player carrying exactly that pair -- anyone who put something else on
        // either shoulder chose it, and this is a change of our mind, not
        // theirs. A config older than 4 takes the bump above first, which leaves
        // it holding exactly the pair this one looks for, so it arrives at the
        // same layout a fresh install would.
        if stored < 5,
           bindings["PAD0_RIGHTSHOULDER"] == "+movedown",
           bindings["PAD0_LEFTSHOULDER"] == "+moveup" {
            bindings["PAD0_RIGHTSHOULDER"] = "+moveup"
            bindings["PAD0_LEFTSHOULDER"] = "+movedown"
        }

        // 6: the weapon switch was a checkbox, and "on" wrote cg_autoswitch 1
        // -- "always", which is Quake III's rule and not Wolfenstein's. Walking
        // over a rifle already in the arsenal took the gun out of the player's
        // hands for a duplicate, which is what a mission started from the
        // launcher, with a loadout, does constantly. 2 switches only for a
        // weapon that is genuinely new. Moved only for a config still holding
        // exactly what the old checkbox wrote: 0 was a deliberate "off", and
        // anything else was chosen in the control that replaced it.
        if stored < 6, autoSwitch == 1 {
            autoSwitch = 2
        }

        // The crosshair shape is seeded, not owned. There is no crosshair
        // control in the launcher, so leaving cg_drawCrosshair in the generated
        // config would re-apply it after wolfconfig.cfg on every launch and
        // quietly undo anything the player picked in the game's own options --
        // the very thing this pass exists to stop. It is written on the launch
        // that migrates the config, and dropped from the set afterwards: the
        // engine archives it within the frame (Com_Frame calls
        // Com_WriteConfiguration) and it is the player's from then on.
        //
        // The bound is the version this seeding was introduced at, not the
        // current one. Written as `stored < tuningVersion` it would fire again
        // on every later bump, and a player who is only being handed a new
        // button layout would silently lose the crosshair they had chosen in
        // the game's own options -- the exact overruling this pass exists to
        // stop.
        seedsCrosshair = stored < 3
        if !seedsCrosshair {
            IOSBridge_ForgetCvar("cg_drawCrosshair")
        }
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
    func commit(missionLoadout: Int = 0) {
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
        IOSBridge_SetCvar("in_touchLookYawSens", String(format: "%.2f", touchLookYawSens))
        IOSBridge_SetCvar("in_touchLookPitchSens", String(format: "%.2f", touchLookPitchSens))
        IOSBridge_SetCvar("in_touchGyro", "\(touchGyro)")
        IOSBridge_SetCvar("in_touchGyroSens", String(format: "%.2f", touchGyroSens))
        IOSBridge_SetCvar("in_touchGyroYawSens", String(format: "%.2f", touchGyroYawSens))
        IOSBridge_SetCvar("in_touchGyroPitchSens", String(format: "%.2f", touchGyroPitchSens))
        IOSBridge_SetCvar("in_touchGyroInvertYaw", touchGyroInvertYaw ? "1" : "0")
        IOSBridge_SetCvar("in_touchGyroInvertPitch", touchGyroInvertPitch ? "1" : "0")

        IOSBridge_SetCvar("s_volume", String(format: "%.2f", volume))
        IOSBridge_SetCvar("s_musicvolume", String(format: "%.2f", musicVolume))

        IOSBridge_SetCvar("cg_autoswitch", "\(autoSwitch)")
        IOSBridge_SetCvar("cg_autoactivate", autoActivate ? "1" : "0")
        IOSBridge_SetCvar("cg_emptyswitch", emptySwitch ? "1" : "0")
        IOSBridge_SetCvar("cg_bobup", viewBob ? "0.005" : "0")
        IOSBridge_SetCvar("cg_bobpitch", viewBob ? "0.002" : "0")
        IOSBridge_SetCvar("cg_bobroll", viewBob ? "0.002" : "0")
        IOSBridge_SetCvar("cg_crosshairSize", String(format: "%.0f", crosshairSize))

        // Shape, once, and only when it is still owed. See migrate(from:).
        if seedsCrosshair {
            IOSBridge_SetCvar("cg_drawCrosshair", "\(LauncherModel.defaultCrosshair)")
        }

        IOSBridge_SetCvar("r_perfHud", perfHud ? "1" : "0")
        IOSBridge_SetCvar("r_perfLog", perfLog ? "1" : "0")
        IOSBridge_SetCvar("in_debugPad", padLog ? "1" : "0")
        IOSBridge_SetCvar("joy_threshold", String(format: "%.2f", stickDeadzone))
        IOSBridge_SetCvar("in_invertLook", invertLook ? "1" : "0")
        IOSBridge_SetCvar("in_gyro", "\(gyroMode)")
        IOSBridge_SetCvar("in_gyroSens", String(format: "%.2f", gyroSens))
        IOSBridge_SetCvar("in_gyroYawSens", String(format: "%.2f", gyroYawSens))
        IOSBridge_SetCvar("in_gyroPitchSens", String(format: "%.2f", gyroPitchSens))
        IOSBridge_SetCvar("in_gyroYawSource", "\(gyroYawSource)")
        IOSBridge_SetCvar("in_gyroInvertYaw", gyroInvertYaw ? "1" : "0")
        IOSBridge_SetCvar("in_gyroInvertPitch", gyroInvertPitch ? "1" : "0")
        IOSBridge_SetCvar("in_rumble", String(format: "%.0f", rumble))
        IOSBridge_SetCvar("cg_rumbleImpact", rumbleImpact ? "1" : "0")
        IOSBridge_SetCvar("cg_rumbleImpactScale", String(format: "%.2f", rumbleImpactScale))
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

        // Every button the launcher knows, not only the bound ones. A button the
        // player has cleared has to be written as an empty bind: leave it out
        // and the config says nothing about it, so the next launch fills it back
        // in from the defaults -- and whatever wolfconfig.cfg still has on that
        // key survives, which is exactly what this file is exec'd last to stop.
        for pad in PadButton.all {
            IOSBridge_SetBinding(pad.id, bindings[pad.id] ?? "")
        }

        // Difficulty and the mission loadout have to reach the table before the
        // config is written. On a cold start the launcher runs before Com_Init,
        // so IOSBridge_SetCvar can only stash the pair -- there is no engine to
        // set it on -- and anything stashed after WriteConfig lands in neither
        // the file nor the engine and is simply lost. Both of these were set
        // after the write, so the difficulty chosen here never took effect and a
        // mission started from the launcher was played with no loadout at all.
        //
        // The loadout is written on every commit, zero unless a mission is being
        // started, so a chapter left in the file by a previous session cannot
        // hand the player the wrong weapons on the next cold start.
        IOSBridge_SetCvar("g_gameskill", "\(skill)")
        IOSBridge_SetCvar("g_missionLoadout", "\(missionLoadout)")

        // Before the write, for the reason spelled out above: a pair stashed
        // after it reaches neither the file nor the engine.
        //
        // The multiplayer settings are written on every commit, including a
        // campaign launch. They are harmless there -- the campaign engine reads
        // none of them -- and writing them unconditionally means the file is
        // the same whichever button was pressed.
        mp.commitClient()

        // Both games keep the statically linked modules. Loading them from the
        // pk3s is not an option on this platform and never was: RTCW shipped
        // its multiplayer modules as x86 libraries, not as QVM bytecode, so
        // there is nothing here an arm64 device could run. Pure servers are
        // satisfied a different way -- VM_Create names the pak the module
        // corresponds to, which is what they actually ask for.
        IOSBridge_SetCvar("vm_static", "1")

        // Diagnostics.
        //
        // logfile 2 flushes every line, which is what makes a log survive a
        // crash -- on a sideloaded build with no debugger that is the only
        // account of what happened. developer 1 adds the engine's own running
        // commentary, including why a server was dropped from the browser.
        IOSBridge_SetCvar("developer", diagVerboseLog ? "1" : "0")
        IOSBridge_SetCvar("logfile", "2")
        IOSBridge_SetCvar("r_perfHud", diagPerfHud ? "1" : "0")
        IOSBridge_SetCvar("r_perfLog", diagPerfLog ? "1" : "0")

        IOSBridge_WriteConfig()
    }

    func play() {
        IOSDispatch_SetGame(Int32(IORTCW_GAME_CAMPAIGN))
        commit()
        beginSession()
        IOSBridge_SetStartupCommand("")
        IOSBridge_LauncherFinished()
    }

    /// Multiplayer, from the footer button: the game's own menus, nothing
    /// joined yet.
    ///
    /// Goes through commit() like the campaign does, so graphics, stick feel and
    /// the pad layout are applied to multiplayer too -- they are one set of
    /// settings for one application.
    func playMultiplayer() {
        IOSDispatch_SetGame(Int32(IORTCW_GAME_MULTIPLAYER))
        commit()
        mp.save()
        IOSBridge_SetExtraArgs("")
        IOSBridge_SetStartupCommand("")
        IOSBridge_LauncherFinished()
    }

    /// Join a server picked in the browser, or typed in by hand.
    func connect(to address: String) {
        IOSDispatch_SetGame(Int32(IORTCW_GAME_MULTIPLAYER))
        commit()
        mp.save()
        IOSBridge_SetExtraArgs("")
        IOSBridge_SetStartupCommand("connect \(address)")
        IOSBridge_LauncherFinished()
    }

    /// Start hosting. The server settings themselves are the multiplayer
    /// model's; this adds the shared ones and the command line.
    func startHosting() {
        IOSDispatch_SetGame(Int32(IORTCW_GAME_MULTIPLAYER))
        commit()
        mp.applyHosting()
        IOSBridge_LauncherFinished()
    }

    /// Hand over to the engine to run the self-test rather than to play.
    ///
    /// Goes through commit() like every other way out of the launcher, and that
    /// is the point rather than a side effect: the run's first and most useful
    /// check reads ios_launcher.cfg back and asks the engine whether it agrees
    /// with it, so the file has to be the one this launcher just wrote.
    func runSelfTest(full: Bool, multiplayer: Bool) {
        IOSDispatch_SetGame(Int32(multiplayer ? IORTCW_GAME_MULTIPLAYER
                                              : IORTCW_GAME_CAMPAIGN))
        commit()
        if multiplayer {
            mp.save()
            mp.commitClient()
        }
        IOSBridge_SetExtraArgs("")
        IOSBridge_SetStartupCommand(full ? "selftest full" : "selftest")
        IOSBridge_LauncherFinished()
    }

    /// Start a mission directly, skipping the game's own menus.
    func startMission(_ mission: CampaignMission) {
        // The mission loadout is the retail campaign's own table of what the
        // player should be carrying by that chapter. A fan campaign has its
        // own progression and its maps hand out their own weapons, so it gets
        // none: guessing a chapter number for someone else's level would arm
        // the player with whatever the retail game hands out at that point.
        commit(missionLoadout: campaign.isRetail ? mission.chapter : 0)
        beginSession()
        IOSBridge_SetStartupCommand("spmap \(mission.id)")
        IOSBridge_LauncherFinished()
    }

    /// Start the selected campaign from its first map.
    func startCampaign() {
        guard let first = campaign.missions.first else {
            play()
            return
        }

        startMission(first)
    }

    /// Everything that has to happen between "the player pressed start" and the
    /// engine coming up: point it at the right game folder, and keep the last
    /// run's log before this one truncates it.
    private func beginSession() {
        let tag = campaign.isRetail ? "main" : campaign.id

        // fs_game is read by FS_Startup, long before the first exec, so the
        // command line is the only way in. The multiplayer build uses the same
        // slot for its dedicated-server arguments and has no campaign picker,
        // so it is left alone there.
        if !isMultiplayer {
            IOSBridge_SetExtraArgs(campaign.isRetail ? "" : "+set fs_game \(campaign.id)")
        }

        IOSBridge_RotateLog(tag)
    }

    /// Follow the launcher's language with the game's own.
    ///
    /// The anthology's Russian paks override the retail text, menus, fonts and
    /// -- for the campaign -- the dubbed dialogue, and their names put them
    /// last in the search order, where nothing can outrank them. So switching
    /// the launcher to English has to take the files themselves out of the
    /// path; the bridge does that by renaming them, which costs nothing even
    /// for the 163MB of sound.
    ///
    /// Multiplayer also gets cl_language, and that one deserves a note: the
    /// anthology ships its in-game Russian strings in the *French* slot of
    /// scripts/translation.cfg, because a stock 1.41 client has no Russian slot
    /// to put them in. So "French" here means Russian, and it is the only way
    /// those strings reach the screen -- including on pure servers, where the
    /// Russian pak itself is outranked by the server's own paks but a .cfg on
    /// disk is still read.
    func applyLanguage(_ language: Loc.Language, writeConfig: Bool = true) {
        let russian = language == .russian

        if IOSBridge_RussianPaksPresent() {
            _ = IOSBridge_SetRussianPaks(russian)
        }

        if isMultiplayer {
            IOSBridge_SetCvar("cl_language", russian ? "1" : "0")

            // Not from init: the settings have only just been read back and
            // writing them out again before the player has touched anything
            // would be a round trip for nothing. Play and every other commit
            // writes the file anyway.
            if writeConfig {
                IOSBridge_WriteConfig()
            }
        }

        refreshData()
    }

    /// Are the Russian game files installed at all? The language switch says so
    /// when they are not, rather than silently doing nothing.
    var hasRussianPaks: Bool { IOSBridge_RussianPaksPresent() }
}
