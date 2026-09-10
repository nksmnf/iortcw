//  LauncherPad.swift -- driving the launcher from the controller.
//
//  SwiftUI has a focus system, but on iOS it moves for the keyboard only: the
//  d-pad reaches .focusable() views on tvOS and not here, so a launcher that
//  relied on it would simply be dead in the hand. This keeps a cursor of its
//  own instead -- one index per screen -- and reads the pad the way
//  ControllerTestView does, by polling GameController on a timer rather than by
//  installing handlers, which iPadOS has already been caught calling twice for
//  a single press.
//
//  Nothing here is taken away from the finger: the cursor draws itself only
//  while a pad is connected, and every row it acts on is a control that is
//  still there to be tapped.

import Combine
import GameController
import SwiftUI

/// What a press means to the launcher, rather than which button it was. The
/// mapping from one to the other lives in `sample()` and nowhere else.
enum PadKey: CaseIterable {
    case up, down, left, right
    case confirm, back
    case tabPrev, tabNext
    case start

    /// Directions repeat while held -- the campaign is 26 missions long, and
    /// stepping through it one press at a time is not something to ask of
    /// anyone. Confirm and back deliberately do not repeat: a menu that fires
    /// twice because a thumb lingered is worse than one that fires late.
    var repeats: Bool {
        switch self {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }
}

/// Which screen the pad is talking to.
///
/// Sheets and pushed views sit on top of the launcher rather than replacing it,
/// so several screens are alive at once and every one of them hears every
/// stroke. Each claims a scope while it is on screen and acts only while it is
/// the last one claimed -- which is the one the player can actually see.
struct PadScope: Hashable {
    private let id = UUID()
    init() {}
}

@MainActor
final class PadInput: ObservableObject {
    /// The drawn cursor follows this: with no pad connected the launcher looks
    /// exactly as it did before, with no ring on anything.
    @Published private(set) var connected = false

    /// A subject rather than an @Published value: a published value is replayed
    /// to whoever subscribes next, and a sheet opened with Cross would then be
    /// handed that same Cross the instant it appeared, activating its first row.
    let strokes = PassthroughSubject<PadKey, Never>()

    @Published private var scopes: [PadScope] = []

    private var timer: Timer?
    private var held: [PadKey: (start: TimeInterval, last: TimeInterval)] = [:]

    /// Long enough that a deliberate single press never repeats, short enough
    /// that holding a direction feels like scrolling rather than waiting.
    private let repeatDelay: TimeInterval = 0.38
    private let repeatRate: TimeInterval = 0.09

    func start() {
        guard timer == nil else { return }
        // 60 Hz. A tap on a pad lasts around 50 ms, so this cannot miss one.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    /// Called when the launcher goes away. The game carries on underneath it,
    /// and a timer left running would keep reading the pad that is by then
    /// being used to play with.
    func stop() {
        timer?.invalidate()
        timer = nil
        held.removeAll()
        connected = false
    }

    deinit { timer?.invalidate() }

    func claim(_ scope: PadScope) {
        scopes.removeAll { $0 == scope }
        scopes.append(scope)
    }

    func release(_ scope: PadScope) {
        scopes.removeAll { $0 == scope }
    }

    /// True for the frontmost screen only, so one stroke is acted on once.
    func isActive(_ scope: PadScope) -> Bool { scopes.last == scope }

    private func sample() {
        guard let gamepad = GCController.controllers().first?.extendedGamepad else {
            if connected { connected = false }
            held.removeAll()
            return
        }
        if !connected { connected = true }

        var down: Set<PadKey> = []
        // The left stick moves the cursor as well as the d-pad does, because
        // that is where the thumb already is when the game is being started.
        if gamepad.dpad.up.isPressed || stick(gamepad.leftThumbstick.yAxis.value, .up) {
            down.insert(.up)
        }
        if gamepad.dpad.down.isPressed || stick(-gamepad.leftThumbstick.yAxis.value, .down) {
            down.insert(.down)
        }
        if gamepad.dpad.left.isPressed || stick(-gamepad.leftThumbstick.xAxis.value, .left) {
            down.insert(.left)
        }
        if gamepad.dpad.right.isPressed || stick(gamepad.leftThumbstick.xAxis.value, .right) {
            down.insert(.right)
        }
        if gamepad.buttonA.isPressed { down.insert(.confirm) }
        if gamepad.buttonB.isPressed { down.insert(.back) }
        if gamepad.leftShoulder.isPressed { down.insert(.tabPrev) }
        if gamepad.rightShoulder.isPressed { down.insert(.tabNext) }
        if gamepad.buttonMenu.isPressed { down.insert(.start) }

        let now = Date().timeIntervalSinceReferenceDate
        for key in PadKey.allCases {
            guard down.contains(key) else {
                held[key] = nil
                continue
            }
            guard let state = held[key] else {
                held[key] = (start: now, last: now)
                strokes.send(key)
                continue
            }
            guard key.repeats,
                  now - state.start >= repeatDelay,
                  now - state.last >= repeatRate else { continue }
            held[key] = (start: state.start, last: now)
            strokes.send(key)
        }
    }

    /// A stick counts as a direction past 0.6 and stops counting below 0.35, so
    /// a thumb resting near the edge does not chatter between the two.
    private func stick(_ value: Float, _ key: PadKey) -> Bool {
        value > (held[key] == nil ? 0.6 : 0.35)
    }
}

extension View {
    /// Marks this screen as the one the pad drives while it is on screen.
    func padScope(_ pad: PadInput, _ scope: PadScope) -> some View {
        onAppear { pad.claim(scope) }
            .onDisappear { pad.release(scope) }
    }

    /// The cursor itself.
    ///
    /// It has to be obvious at arm's length -- a pad is used from further away
    /// than a finger is -- so it is a filled plate and not a hairline. The
    /// negative padding lets it sit outside the row's own text without changing
    /// the layout of anything, which keeps the touch version pixel-identical.
    func padFocus(_ focused: Bool) -> some View {
        background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                )
                .padding(.horizontal, -8)
                .padding(.vertical, -5)
                .opacity(focused ? 1 : 0)
                // It is decoration and nothing else: a filled shape would
                // otherwise take the taps that land in the margin it adds.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Move a slider one step, without letting the rounding walk the value off the
/// steps the slider itself is snapped to.
func padStep(_ value: inout Double, by step: Double, in range: ClosedRange<Double>, up: Bool) {
    let moved = value + (up ? step : -step)
    let snapped = (moved / step).rounded() * step
    value = min(max(snapped, range.lowerBound), range.upperBound)
}

/// Step through a fixed set of choices, wrapping at the ends: with three
/// options there is no distance to cover, and wrapping means neither direction
/// ever dead-ends.
func padCycle<T: Equatable>(_ value: inout T, through options: [T], forward: Bool) {
    guard !options.isEmpty else { return }
    guard let index = options.firstIndex(of: value) else {
        value = options[0]
        return
    }
    let step = forward ? 1 : options.count - 1
    value = options[(index + step) % options.count]
}
