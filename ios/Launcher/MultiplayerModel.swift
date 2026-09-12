//  MultiplayerModel.swift -- multiplayer settings, for both playing and hosting.
//
//  Kept apart from LauncherModel because @Published cannot live in an extension
//  and LauncherModel is already long. LauncherModel owns one of these and calls
//  its commit() from its own, so everything still lands in one ios_launcher.cfg.
//
//  Only built into the MP application; the SP launcher never shows these tabs.

import Foundation
import Combine

// MARK: - Static tables

/// The game types RTCW multiplayer actually ships. 0-4 exist in the enum
/// (bg_public.h) but the stock maps carry no entities for deathmatch or CTF, so
/// offering them would produce a server nobody can play on.
enum WolfGameType: Int, CaseIterable, Identifiable {
    case objective = 5
    case stopwatch = 6
    case checkpoint = 7
    case captureAndHold = 8

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .objective:      return "Задание"
        case .stopwatch:      return "Секундомер"
        case .checkpoint:     return "Контрольные точки"
        case .captureAndHold: return "Захват и удержание"
        }
    }

    var detail: String {
        switch self {
        case .objective:
            return "Штатный режим RTCW: одна команда выполняет задачу, другая защищает. Так играет почти вся сеть."
        case .stopwatch:
            return "То же задание, но команды меняются местами и соревнуются, кто быстрее."
        case .checkpoint:
            return "Команды удерживают флаги-контрольные точки на карте."
        case .captureAndHold:
            return "Очки начисляются за время удержания точек."
        }
    }
}

/// The maps that come with the game. Custom maps work too -- the field accepts
/// any name -- but these are the ones guaranteed to be in the player's pk3s.
struct WolfMap: Identifiable, Hashable {
    let id: String
    let title: String

    static let stock: [WolfMap] = [
        WolfMap(id: "mp_beach",        title: "Omaha Beach"),
        WolfMap(id: "mp_base",         title: "Rocket Base"),
        WolfMap(id: "mp_village",      title: "Village"),
        WolfMap(id: "mp_assault",      title: "Assault"),
        WolfMap(id: "mp_sub",          title: "Submarine Pen"),
        WolfMap(id: "mp_destruction",  title: "Destruction"),
        WolfMap(id: "mp_castle",       title: "Castle Keep"),
        WolfMap(id: "mp_depot",        title: "Depot"),
        WolfMap(id: "mp_ice",          title: "Ice"),
        WolfMap(id: "mp_keep",         title: "The Keep"),
    ]
}

/// How a hosted game is run. This is the "dedicated" cvar, and it decides three
/// things at once, which is why it is one control rather than three:
///
///   0  listen  -- the host plays. There is a renderer, so the iPad shows the
///                 game. No heartbeat is sent, so it is findable on the LAN by
///                 broadcast and nowhere else.
///   1  LAN     -- a real server with no client attached. Nothing is drawn, so
///                 the screen stays dark; still no heartbeat.
///   2  internet-- as above, and registered with the masters every five minutes.
///
/// The heartbeat check is explicit about this: only dedicated 2 reports to a
/// master (MP/code/server/sv_main.c:259). So "play with friends over the
/// internet" and "watch the game on the tablet" cannot both be true.
enum ServerVisibility: Int, CaseIterable, Identifiable {
    case listen = 0
    case lan = 1
    case internet = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .listen:   return "Играю сам"
        case .lan:      return "Локальный"
        case .internet: return "Интернет"
        }
    }

    var detail: String {
        switch self {
        case .listen:
            return "Вы играете на своём же сервере, картинка на планшете. Другие игроки находят вас только в локальной сети."
        case .lan:
            return "Чистый сервер без игрока: планшет ничего не рисует, экран будет тёмным. Виден только в локальной сети."
        case .internet:
            return "Сервер регистрируется на мастер-серверах и виден всем. Картинки нет. Нужен проброс UDP-порта на роутере — через мобильный интернет входящие соединения не проходят."
        }
    }

    /// Does the engine draw anything in this mode?
    var hasRenderer: Bool { self == .listen }

    /// Does it report to the masters?
    var registersWithMasters: Bool { self == .internet }
}

// MARK: - Model

@MainActor
final class MultiplayerModel: ObservableObject {
    // --- client ------------------------------------------------------------
    @Published var playerName: String = "iPad Player"
    @Published var rate: Int = 25000
    @Published var maxPackets: Int = 60
    @Published var snaps: Int = 40
    @Published var autoReload: Bool = true
    @Published var drawFPS: Bool = false
    @Published var lagometer: Bool = false
    @Published var blood: Bool = true
    @Published var simpleItems: Bool = false
    @Published var teamChatHeight: Int = 8
    @Published var allowDownload: Bool = true

    // --- hosting -----------------------------------------------------------
    @Published var hostName: String = "iORTCW iPad"
    @Published var visibility: ServerVisibility = .listen
    @Published var maxClients: Int = 12
    @Published var gameType: WolfGameType = .objective
    @Published var startMap: String = "mp_beach"
    @Published var mapRotation: [String] = ["mp_beach", "mp_base", "mp_village"]
    @Published var timeLimit: Int = 20
    @Published var friendlyFire: Bool = true
    @Published var doWarmup: Bool = true
    @Published var warmupTime: Int = 20
    @Published var forceBalance: Bool = true
    @Published var maxLives: Int = 0
    @Published var pureServer: Bool = true
    @Published var floodProtect: Bool = true
    @Published var netPort: Int = 27960
    @Published var serverPassword: String = ""
    @Published var rconPassword: String = ""
    @Published var motd: String = ""
    @Published var complaintLimit: Int = 3
    @Published var serverMaxRate: Int = 25000
    @Published var minPing: Int = 0
    @Published var maxPing: Int = 0
    @Published var keepAwake: Bool = true
    @Published var registerWithMasters: Bool = true

    /// The masters a hosted server reports to. Same three the browser asks, and
    /// for the same reason: those are the ones that answer.
    static let masterServers = [
        "wolfmaster.idsoftware.com",
        "master.iortcw.org",
        "dpmaster.deathmask.net",
    ]

    init() {
        load()
    }

    // MARK: Persistence
    //
    // Hosting settings live in UserDefaults rather than in cvars. Most of them
    // are only meaningful while a server is running, and several (net_port,
    // dedicated) are CVAR_INIT or CVAR_LATCH, so reading them back out of the
    // engine after the fact would give the launcher stale or empty values.

    private func load() {
        let d = UserDefaults.standard

        playerName   = d.string(forKey: "mp.name") ?? playerName
        rate         = d.object(forKey: "mp.rate") as? Int ?? rate
        maxPackets   = d.object(forKey: "mp.maxpackets") as? Int ?? maxPackets
        snaps        = d.object(forKey: "mp.snaps") as? Int ?? snaps
        autoReload   = d.object(forKey: "mp.autoreload") as? Bool ?? autoReload
        drawFPS      = d.object(forKey: "mp.drawfps") as? Bool ?? drawFPS
        lagometer    = d.object(forKey: "mp.lagometer") as? Bool ?? lagometer
        blood        = d.object(forKey: "mp.blood") as? Bool ?? blood
        simpleItems  = d.object(forKey: "mp.simpleitems") as? Bool ?? simpleItems
        allowDownload = d.object(forKey: "mp.download") as? Bool ?? allowDownload

        hostName     = d.string(forKey: "mp.host.name") ?? hostName
        if let v = d.object(forKey: "mp.host.visibility") as? Int,
           let parsed = ServerVisibility(rawValue: v) { visibility = parsed }
        maxClients   = d.object(forKey: "mp.host.maxclients") as? Int ?? maxClients
        if let g = d.object(forKey: "mp.host.gametype") as? Int,
           let parsed = WolfGameType(rawValue: g) { gameType = parsed }
        startMap     = d.string(forKey: "mp.host.map") ?? startMap
        mapRotation  = d.stringArray(forKey: "mp.host.rotation") ?? mapRotation
        timeLimit    = d.object(forKey: "mp.host.timelimit") as? Int ?? timeLimit
        friendlyFire = d.object(forKey: "mp.host.ff") as? Bool ?? friendlyFire
        doWarmup     = d.object(forKey: "mp.host.dowarmup") as? Bool ?? doWarmup
        warmupTime   = d.object(forKey: "mp.host.warmup") as? Int ?? warmupTime
        forceBalance = d.object(forKey: "mp.host.balance") as? Bool ?? forceBalance
        maxLives     = d.object(forKey: "mp.host.maxlives") as? Int ?? maxLives
        pureServer   = d.object(forKey: "mp.host.pure") as? Bool ?? pureServer
        floodProtect = d.object(forKey: "mp.host.flood") as? Bool ?? floodProtect
        netPort      = d.object(forKey: "mp.host.port") as? Int ?? netPort
        serverPassword = d.string(forKey: "mp.host.password") ?? serverPassword
        rconPassword = d.string(forKey: "mp.host.rcon") ?? rconPassword
        motd         = d.string(forKey: "mp.host.motd") ?? motd
        complaintLimit = d.object(forKey: "mp.host.complaint") as? Int ?? complaintLimit
        serverMaxRate = d.object(forKey: "mp.host.maxrate") as? Int ?? serverMaxRate
        minPing      = d.object(forKey: "mp.host.minping") as? Int ?? minPing
        maxPing      = d.object(forKey: "mp.host.maxping") as? Int ?? maxPing
        keepAwake    = d.object(forKey: "mp.host.keepawake") as? Bool ?? keepAwake
        registerWithMasters = d.object(forKey: "mp.host.masters") as? Bool ?? registerWithMasters
    }

    func save() {
        let d = UserDefaults.standard

        d.set(playerName, forKey: "mp.name")
        d.set(rate, forKey: "mp.rate")
        d.set(maxPackets, forKey: "mp.maxpackets")
        d.set(snaps, forKey: "mp.snaps")
        d.set(autoReload, forKey: "mp.autoreload")
        d.set(drawFPS, forKey: "mp.drawfps")
        d.set(lagometer, forKey: "mp.lagometer")
        d.set(blood, forKey: "mp.blood")
        d.set(simpleItems, forKey: "mp.simpleitems")
        d.set(allowDownload, forKey: "mp.download")

        d.set(hostName, forKey: "mp.host.name")
        d.set(visibility.rawValue, forKey: "mp.host.visibility")
        d.set(maxClients, forKey: "mp.host.maxclients")
        d.set(gameType.rawValue, forKey: "mp.host.gametype")
        d.set(startMap, forKey: "mp.host.map")
        d.set(mapRotation, forKey: "mp.host.rotation")
        d.set(timeLimit, forKey: "mp.host.timelimit")
        d.set(friendlyFire, forKey: "mp.host.ff")
        d.set(doWarmup, forKey: "mp.host.dowarmup")
        d.set(warmupTime, forKey: "mp.host.warmup")
        d.set(forceBalance, forKey: "mp.host.balance")
        d.set(maxLives, forKey: "mp.host.maxlives")
        d.set(pureServer, forKey: "mp.host.pure")
        d.set(floodProtect, forKey: "mp.host.flood")
        d.set(netPort, forKey: "mp.host.port")
        d.set(serverPassword, forKey: "mp.host.password")
        d.set(rconPassword, forKey: "mp.host.rcon")
        d.set(motd, forKey: "mp.host.motd")
        d.set(complaintLimit, forKey: "mp.host.complaint")
        d.set(serverMaxRate, forKey: "mp.host.maxrate")
        d.set(minPing, forKey: "mp.host.minping")
        d.set(maxPing, forKey: "mp.host.maxping")
        d.set(keepAwake, forKey: "mp.host.keepawake")
        d.set(registerWithMasters, forKey: "mp.host.masters")
    }

    // MARK: Applying

    /// Client-side settings. Written on every launch, whether playing or hosting
    /// -- a listen server's operator is also a player.
    func commitClient() {
        IOSBridge_SetCvar("name", playerName.isEmpty ? "iPad Player" : playerName)
        IOSBridge_SetCvar("rate", "\(rate)")
        IOSBridge_SetCvar("cl_maxpackets", "\(maxPackets)")
        IOSBridge_SetCvar("snaps", "\(snaps)")
        IOSBridge_SetCvar("cg_autoReload", autoReload ? "1" : "0")
        IOSBridge_SetCvar("cg_drawFPS", drawFPS ? "1" : "0")
        IOSBridge_SetCvar("cg_lagometer", lagometer ? "1" : "0")
        IOSBridge_SetCvar("cg_showblood", blood ? "1" : "0")
        IOSBridge_SetCvar("cg_simpleItems", simpleItems ? "1" : "0")
        IOSBridge_SetCvar("cg_teamChatHeight", "\(teamChatHeight)")

        // Downloads matter more here than they look: over half the populated
        // servers run custom maps, and without this a player simply cannot join
        // them. curl is not built for iOS, so this is the engine's own UDP
        // path -- slower, but it is the difference between joining and not.
        IOSBridge_SetCvar("cl_allowDownload", allowDownload ? "1" : "0")

        // net_enabled is deliberately NOT set here, although multiplayer does
        // need it on. It is read before any config is exec'd, so a value put in
        // the launcher's file can never take effect -- the command line is the
        // only place that can carry it, and ios_bridge.c sets it there from
        // which game is being started. Written here as well it was a line in
        // the config that disagreed with the running engine for the rest of the
        // session, which is precisely what the settings check reports as a
        // fault, and it would have been right to.

        // The game's own server browser, set so that it shows what is out there.
        //
        // Its defaults are not the problem -- these are what a player ends up
        // with after touching the filter screen once, and several of them are
        // traps. PunkBuster is the worst: the server never sends that key at
        // all, so "show only PunkBuster servers" hides every server in the
        // world. The gametype filter is nearly as bad, because a server running
        // anything the menu does not list is simply invisible.
        IOSBridge_SetCvar("ui_joinGametype", "0")        // All
        IOSBridge_SetCvar("ui_browserShowEmpty", "1")
        IOSBridge_SetCvar("ui_browserShowFull", "1")
        IOSBridge_SetCvar("ui_browserShowFriendlyFire", "0")
        IOSBridge_SetCvar("ui_browserShowMaxlives", "1")
        IOSBridge_SetCvar("ui_browserShowTourney", "1")
        IOSBridge_SetCvar("ui_browserShowPunkBuster", "0")
        IOSBridge_SetCvar("ui_browserShowAntilag", "0")

        // A server is pinged once and never again, so a lost packet or a slow
        // route means it stays invisible until the next full refresh. 800ms is
        // tight for a transatlantic server on a tablet's wifi.
        IOSBridge_SetCvar("cl_maxPing", "2000")
    }

    /// Server-side settings, applied only when hosting.
    func commitServer() {
        IOSBridge_SetCvar("sv_hostname", hostName.isEmpty ? "iORTCW iPad" : hostName)
        IOSBridge_SetCvar("sv_maxclients", "\(maxClients)")
        IOSBridge_SetCvar("g_gametype", "\(gameType.rawValue)")
        IOSBridge_SetCvar("timelimit", "\(timeLimit)")
        IOSBridge_SetCvar("g_friendlyFire", friendlyFire ? "1" : "0")
        IOSBridge_SetCvar("g_doWarmup", doWarmup ? "1" : "0")
        IOSBridge_SetCvar("g_warmup", "\(warmupTime)")
        IOSBridge_SetCvar("g_teamForceBalance", forceBalance ? "1" : "0")
        IOSBridge_SetCvar("g_maxlives", "\(maxLives)")
        IOSBridge_SetCvar("g_complaintlimit", "\(complaintLimit)")
        IOSBridge_SetCvar("sv_pure", pureServer ? "1" : "0")
        IOSBridge_SetCvar("sv_floodProtect", floodProtect ? "1" : "0")
        IOSBridge_SetCvar("sv_maxRate", "\(serverMaxRate)")
        IOSBridge_SetCvar("sv_minPing", "\(minPing)")
        IOSBridge_SetCvar("sv_maxPing", "\(maxPing)")
        IOSBridge_SetCvar("g_motd", motd)
        IOSBridge_SetCvar("g_password", serverPassword)
        IOSBridge_SetCvar("rconPassword", rconPassword)

        // Masters are only consulted when the server is public anyway, but
        // clearing them makes "LAN only" unambiguous rather than relying on the
        // dedicated check alone.
        for (index, master) in MultiplayerModel.masterServers.enumerated() {
            let shouldRegister = registerWithMasters && visibility.registersWithMasters
            IOSBridge_SetCvar("sv_master\(index + 1)", shouldRegister ? master : "")
        }
    }

    // MARK: Starting

    /// Join a server. The address goes in as a startup command, which the engine
    /// runs once it is up -- the same path the launcher already uses to start a
    /// campaign mission.
    func connect(to address: String) {
        IOSDispatch_SetGame(Int32(IORTCW_GAME_MULTIPLAYER))
        commitClient()
        save()
        IOSBridge_SetExtraArgs("")
        IOSBridge_WriteConfig()
        IOSBridge_SetStartupCommand("connect \(address)")
        IOSBridge_LauncherFinished()
    }

    /// Start hosting.
    ///
    /// dedicated and net_port are both settled before any config is exec'd --
    /// one is CVAR_INIT, the other CVAR_LATCH -- so they go on the command line
    /// rather than into ios_launcher.cfg, where they would simply be ignored.
    /// The server half of starting a host. LauncherModel.startHosting() calls
    /// this after the shared settings have been written.
    func applyHosting() {
        commitServer()

        for (name, value) in rotationCommands() {
            IOSBridge_SetCvar(name, value)
        }

        save()

        IOSBridge_SetExtraArgs(
            "+set dedicated \(visibility.rawValue) +set net_port \(netPort)")
        IOSBridge_WriteConfig()

        // Keeping the process scheduled is what makes hosting survive the app
        // being put away. Only worth it when there is actually a server: a
        // silent audio graph running behind a single-player game is pure drain.
        IOSBridge_SetKeepAwake(keepAwake)

        // A server with no renderer has nothing to show, so the launcher stays
        // up and turns into its console. A listen server does draw, and there
        // the launcher gets out of the way as usual.
        LauncherHost.shared.hostingModel = visibility.hasRenderer ? nil : self

        // vstr d1 rather than "map X": it starts the rotation at its first
        // entry, so nextmap is already primed when the first round ends.
        IOSBridge_SetStartupCommand("vstr d1")
        IOSBridge_LauncherFinished()
    }

    /// Start multiplayer without joining anything, which lands in the game's
    /// own server browser. The footer button uses this.
    func play() {
        IOSDispatch_SetGame(Int32(IORTCW_GAME_MULTIPLAYER))
        commitClient()
        save()
        IOSBridge_SetExtraArgs("")
        IOSBridge_WriteConfig()
        IOSBridge_SetStartupCommand("")
        IOSBridge_LauncherFinished()
    }

    /// The map rotation, as the vstr chain RTCW servers have always used.
    /// Written into the generated config so it survives into the running server.
    func rotationCommands() -> [(String, String)] {
        let maps = mapRotation.isEmpty ? [startMap] : mapRotation
        var out: [(String, String)] = []

        for (i, map) in maps.enumerated() {
            let next = "d\((i + 1) % maps.count + 1)"
            out.append(("d\(i + 1)", "map \(map) ; set nextmap vstr \(next)"))
        }
        return out
    }
}
