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
        GameAction(id: "+attack",     title: "Fire",            group: "Combat"),
        GameAction(id: "+zoom",       title: "Aim / scope",     group: "Combat"),
        GameAction(id: "+reload",     title: "Reload",          group: "Combat"),
        GameAction(id: "weapnext",    title: "Next weapon",     group: "Combat"),
        GameAction(id: "weapprev",    title: "Previous weapon", group: "Combat"),
        GameAction(id: "+movedown",   title: "Crouch",          group: "Movement"),
        GameAction(id: "+moveup",     title: "Jump",            group: "Movement"),
        GameAction(id: "+speed",      title: "Walk / run",      group: "Movement"),
        GameAction(id: "+leanleft",   title: "Lean left",       group: "Movement"),
        GameAction(id: "+leanright",  title: "Lean right",      group: "Movement"),
        GameAction(id: "+useitem",    title: "Use / activate",  group: "Actions"),
        GameAction(id: "+kick",       title: "Kick",            group: "Actions"),
        GameAction(id: "itemnext",    title: "Next item",       group: "Actions"),
        GameAction(id: "notebook",    title: "Notebook",        group: "Actions"),
        GameAction(id: "save quick",  title: "Quick save",      group: "System"),
        GameAction(id: "load quick",  title: "Quick load",      group: "System"),
        GameAction(id: "togglemenu",  title: "Menu",            group: "System"),
    ]

    static var groups: [String] { ["Combat", "Movement", "Actions", "System"] }
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

@MainActor
final class LauncherModel: ObservableObject {
    // Game data
    @Published var dataMask: Int = 0
    @Published var dataPath: String = ""

    // Graphics
    @Published var maxFPS: Int = 120
    @Published var hiDPI: Bool = true
    @Published var fov: Double = 90
    @Published var brightness: Double = 1.3

    // Controls
    @Published var sensitivity: Double = 5
    @Published var gyroMode: Int = 0
    @Published var gyroSens: Double = 1.0
    @Published var rumble: Double = 100
    @Published var adaptiveTriggers: Bool = true
    @Published var triggerHard: Double = 0.75
    @Published var touchControls: Int = 0
    @Published var invertLook: Bool = false

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

    func refreshData() {
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
            "PAD0_RIGHTTRIGGER":      "+attack",
            "PAD0_LEFTTRIGGER":       "+zoom",
            "PAD0_A":                 "+moveup",
            "PAD0_B":                 "+movedown",
            "PAD0_X":                 "+useitem",
            "PAD0_Y":                 "+reload",
            "PAD0_RIGHTSHOULDER":     "weapnext",
            "PAD0_LEFTSHOULDER":      "weapprev",
            "PAD0_LEFTSTICK_CLICK":   "+speed",
            "PAD0_RIGHTSTICK_CLICK":  "+kick",
            "PAD0_DPAD_UP":           "itemnext",
            "PAD0_DPAD_DOWN":         "notebook",
            "PAD0_DPAD_LEFT":         "+leanleft",
            "PAD0_DPAD_RIGHT":        "+leanright",
            "PAD0_START":             "togglemenu",
            "PAD0_BACK":              "save quick",
            "PAD0_TOUCHPAD":          "load quick",
            "PAD0_TOUCH_SWIPE_LEFT":  "weapprev",
            "PAD0_TOUCH_SWIPE_RIGHT": "weapnext",
        ]
    }

    private func loadDefaults() {
        applyDefaultBindings()

        // Anything already set (a previous run) overrides the defaults.
        for pad in PadButton.all {
            let current = String(cString: IOSBridge_GetBinding(pad.id))
            if !current.isEmpty {
                bindings[pad.id] = current
            }
        }
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
        IOSBridge_SetCvar("com_maxfps", "\(maxFPS)")
        IOSBridge_SetCvar("r_hidpi", hiDPI ? "1" : "0")
        IOSBridge_SetCvar("cg_fov", String(format: "%.0f", fov))
        IOSBridge_SetCvar("r_gamma", String(format: "%.2f", brightness))

        IOSBridge_SetCvar("sensitivity", String(format: "%.2f", sensitivity))
        IOSBridge_SetCvar("m_pitch", invertLook ? "-0.022" : "0.022")
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
        IOSBridge_LauncherFinished()
    }
}
