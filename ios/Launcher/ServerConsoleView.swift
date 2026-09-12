//  ServerConsoleView.swift -- what the launcher shows while a server is running.
//
//  A dedicated server draws nothing: the engine never starts the renderer, so
//  handing the screen over to it the way the launcher does for a game would
//  leave a black rectangle and no way back. Instead the launcher stays up and
//  turns into the server's console.
//
//  The output is the engine's own, captured in Sys_Print and read back through
//  the bridge (IOSBridge_LogSnapshot). It arrives because the server's frame
//  loop gives the runloop a turn -- see Sys_IOS_PumpRunLoop; without that this
//  view would be correct and never redraw.

import SwiftUI

@MainActor
final class ServerConsole: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var running = false
    @Published var command = ""

    private var timer: Timer?
    private var lastVersion: UInt32 = 0

    /// 96k is what the bridge keeps; asking for a little more costs nothing and
    /// means the tail is never clipped twice.
    private static let bufferSize = 128 * 1024

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh(force: Bool) {
        running = IOSBridge_ServerRunning()

        let version = IOSBridge_LogVersion()
        guard force || version != lastVersion else { return }
        lastVersion = version

        var buf = [CChar](repeating: 0, count: ServerConsole.bufferSize)
        let n = IOSBridge_LogSnapshot(&buf, Int32(ServerConsole.bufferSize))
        if n > 0 {
            text = String(cString: buf)
        }
    }

    func send(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        IOSBridge_ExecCommand(trimmed)
        command = ""
        // The reply lands in the log a frame or two later; nudge the poll so it
        // does not look like nothing happened.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.refresh(force: true)
        }
    }
}

struct ServerConsoleView: View {
    @ObservedObject var mp: MultiplayerModel
    @StateObject private var console = ServerConsole()

    /// Called when the operator shuts the server down. The launcher cannot come
    /// back afterwards -- the engine is past Com_Init and its game modules are
    /// loaded -- so this quits, which on iOS means the app closes and is
    /// started again from the home screen.
    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            logBody

            Divider()

            controls
        }
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .onAppear { console.start() }
        .onDisappear { console.stop() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(mp.hostName.isEmpty ? L("Сервер") : mp.hostName)
                    .font(TypeScale.section)
                Text(status)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: Space.s) {
                Circle()
                    .fill(console.running ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(console.running ? L("Работает") : L("Запускается…"))
                    .font(TypeScale.status)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
    }

    private var status: String {
        let mode = L(mp.visibility.title)
        return "\(mode) · \(L("порт")) \(mp.netPort) · \(L(mp.gameType.title))"
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(console.text.isEmpty ? L("Ждём вывод сервера…") : console.text)
                    .font(TypeScale.monoSmall)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.l)
                    .id("log")
            }
            // The two-parameter onChange is iOS 17; the deployment target here
            // is 16, so this is the older single-parameter form.
            .onChange(of: console.text) { _ in
                // Follow the tail, the way a terminal does.
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("log", anchor: .bottom)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.l) {
                TextField(L("Команда консоли"), text: $console.command)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(TypeScale.mono)
                    .onSubmit { console.send(console.command) }

                Button(L("Выполнить")) {
                    console.send(console.command)
                }
                .disabled(console.command.isEmpty)
            }

            HStack(spacing: Space.l) {
                ForEach(ServerConsoleView.shortcuts, id: \.command) { item in
                    Button(L(item.title)) {
                        console.send(item.command)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(role: .destructive) {
                    // killserver stops the game but leaves the process running
                    // with no renderer and no way back to the launcher, which
                    // would look like a hang. Quitting is the honest end.
                    IOSBridge_SetKeepAwake(false)
                    console.send("quit")
                } label: {
                    Label(L("Остановить"), systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
    }

    /// The handful of commands an operator reaches for, so they are one tap
    /// rather than typed on a tablet keyboard.
    private static let shortcuts: [(title: String, command: String)] = [
        ("Кто на сервере", "status"),
        ("Следующая карта", "vstr nextmap"),
        ("Перезапустить карту", "map_restart"),
    ]
}
