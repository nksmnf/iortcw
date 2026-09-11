//  ControllerTestView.swift -- live view of what the controller is sending.
//
//  This exists because "the sticks do the same thing" is impossible to diagnose
//  from a description. Reading the hardware directly through GameController --
//  not through the engine -- separates two questions that otherwise look
//  identical: is the controller reporting what we think, and is the engine doing
//  the right thing with it.

import SwiftUI
import GameController

@MainActor
final class ControllerProbe: ObservableObject {
    @Published var connected = false
    @Published var name = "—"
    @Published var leftX: Float = 0
    @Published var leftY: Float = 0
    @Published var rightX: Float = 0
    @Published var rightY: Float = 0
    @Published var leftTrigger: Float = 0
    @Published var rightTrigger: Float = 0
    @Published var pressed: Set<String> = []
    @Published var hasGyro = false
    @Published var hasAdaptiveTriggers = false
    @Published var hasHaptics = false

    /// How long Circle has been held, as 0...1 of `holdToClose`.
    ///
    /// This screen is the one place where a tap on Circle must not close
    /// anything: Circle is one of the buttons being tested, and a page that
    /// leaves the moment it is pressed can never show it working. Holding it is
    /// the way out instead, and the bar filling up says so without words.
    @Published var backHold: Double = 0

    static let holdToClose: TimeInterval = 0.7

    private var backSince: TimeInterval?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    deinit { timer?.invalidate() }

    private func sample() {
        guard let pad = GCController.controllers().first?.extendedGamepad else {
            connected = false
            name = "—"
            pressed = []
            leftX = 0; leftY = 0; rightX = 0; rightY = 0
            leftTrigger = 0; rightTrigger = 0
            backSince = nil
            backHold = 0
            return
        }

        connected = true
        name = pad.controller?.vendorName ?? "Контроллер"

        leftX = pad.leftThumbstick.xAxis.value
        leftY = pad.leftThumbstick.yAxis.value
        rightX = pad.rightThumbstick.xAxis.value
        rightY = pad.rightThumbstick.yAxis.value
        leftTrigger = pad.leftTrigger.value
        rightTrigger = pad.rightTrigger.value

        var down: Set<String> = []
        func check(_ button: GCControllerButtonInput?, _ label: String) {
            if button?.isPressed == true { down.insert(label) }
        }
        check(pad.buttonA, "Cross")
        check(pad.buttonB, "Circle")
        check(pad.buttonX, "Square")
        check(pad.buttonY, "Triangle")
        check(pad.leftShoulder, "L1")
        check(pad.rightShoulder, "R1")
        check(pad.leftTrigger, "L2")
        check(pad.rightTrigger, "R2")
        check(pad.leftThumbstickButton, "L3")
        check(pad.rightThumbstickButton, "R3")
        check(pad.buttonMenu, "Options")
        check(pad.buttonOptions, "Create")
        check(pad.dpad.up, "D-Up")
        check(pad.dpad.down, "D-Down")
        check(pad.dpad.left, "D-Left")
        check(pad.dpad.right, "D-Right")
        if #available(iOS 14.5, *), let ds = pad as? GCDualSenseGamepad {
            check(ds.touchpadButton, "Тачпад")
            hasAdaptiveTriggers = true
        }
        pressed = down

        if pad.buttonB.isPressed {
            let now = Date().timeIntervalSinceReferenceDate
            let since = backSince ?? now
            backSince = since
            backHold = min(1, (now - since) / ControllerProbe.holdToClose)
        } else {
            backSince = nil
            backHold = 0
        }

        hasGyro = pad.controller?.motion != nil
        hasHaptics = pad.controller?.haptics != nil
    }
}

struct ControllerTestView: View {
    @ObservedObject var pad: PadInput
    @StateObject private var probe = ControllerProbe()
    @Environment(\.dismiss) private var dismiss
    @State private var scope = PadScope()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    status

                    if probe.connected {
                        sticks
                        triggers
                        buttons
                        capabilities
                        closeHint
                        hint
                    }
                }
                .padding(24)
            }
            .navigationTitle("Проверка контроллера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        // Claimed but never acted on: while this page is up every press belongs
        // to the readout below, and the launcher's cursor underneath must not
        // wander off while the player works through the buttons.
        .padScope(pad, scope)
        .onChange(of: probe.backHold) { held in
            if held >= 1 { dismiss() }
        }
    }

    private var status: some View {
        HStack {
            Image(systemName: probe.connected ? "gamecontroller.fill" : "gamecontroller")
                .foregroundStyle(probe.connected ? Color.green : Color.secondary)
            Text(probe.connected ? probe.name : "Контроллер не подключён")
                .font(.headline)
        }
    }

    private var sticks: some View {
        HStack(spacing: 28) {
            stickView(title: "Левый — движение", x: probe.leftX, y: probe.leftY)
            stickView(title: "Правый — обзор", x: probe.rightX, y: probe.rightY)
        }
    }

    private func stickView(title: String, x: Float, y: Float) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Theme.fill(0.30), lineWidth: 1)
                    .frame(width: 130, height: 130)
                Circle()
                    .stroke(Theme.fill(0.15), lineWidth: 1)
                    .frame(width: 40, height: 40)     // deadzone, roughly
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 18, height: 18)
                    // GameController's Y is up-positive; flip it so the dot
                    // moves the way the thumb does on screen.
                    .offset(x: CGFloat(x) * 56, y: CGFloat(-y) * 56)
            }
            Text(String(format: "x %+.2f   y %+.2f", x, y))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var triggers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Триггеры").font(.caption).foregroundStyle(.secondary)
            triggerBar(label: "L2 — прицел", value: probe.leftTrigger)
            triggerBar(label: "R2 — огонь", value: probe.rightTrigger)
        }
    }

    private func triggerBar(label: String, value: Float) -> some View {
        HStack {
            Text(label).frame(width: 120, alignment: .leading).font(.callout)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill(0.15))
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * CGFloat(value))
                }
            }
            .frame(height: 12)
            Text(String(format: "%.2f", value))
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 44)
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Кнопки").font(.caption).foregroundStyle(.secondary)
            let all = ["Cross", "Circle", "Square", "Triangle", "L1", "R1", "L3", "R3",
                       "D-Up", "D-Down", "D-Left", "D-Right", "Options", "Create", "Тачпад"]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 8) {
                ForEach(all, id: \.self) { name in
                    let on = probe.pressed.contains(name)
                    Text(name)
                        .font(.caption)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(on ? Theme.accent : Theme.fill(0.10),
                                    in: RoundedRectangle(cornerRadius: 6))
                        // Black on orange reads in either theme; the unpressed
                        // chip carries the theme's own text colour.
                        .foregroundStyle(on ? Theme.onAccent : Color.primary)
                }
            }
        }
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Возможности").font(.caption).foregroundStyle(.secondary)
            Label(probe.hasGyro ? "Гироскоп есть" : "Гироскопа нет",
                  systemImage: probe.hasGyro ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(probe.hasGyro ? Color.green : Color.secondary)
            Label(probe.hasHaptics ? "Вибрация есть" : "Вибрации нет",
                  systemImage: probe.hasHaptics ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(probe.hasHaptics ? Color.green : Color.secondary)
            Label(probe.hasAdaptiveTriggers ? "Адаптивные триггеры есть" : "Адаптивных триггеров нет",
                  systemImage: probe.hasAdaptiveTriggers ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(probe.hasAdaptiveTriggers ? Color.green : Color.secondary)
        }
        .font(.callout)
    }

    private var closeHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle")
            Text(L("Держите Circle, чтобы закрыть")).font(.callout)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill(0.15))
                Capsule().fill(Theme.accent)
                    .frame(width: CGFloat(90 * probe.backHold))
            }
            .frame(width: 90, height: 8)
        }
        .foregroundStyle(.secondary)
    }

    private var hint: some View {
        Text("""
             Если точка стика не в центре, когда вы его не трогаете, увеличьте \
             мёртвую зону в настройках управления. Если движение и обзор \
             реагируют на один и тот же стик — пришлите \
             Documents/main/rtcwconsole.log, там видно, что получил движок.
             """)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
