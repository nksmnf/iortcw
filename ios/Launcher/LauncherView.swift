//  LauncherView.swift -- the launcher UI.
//
//  Three tabs: getting the game data in, graphics, and controls (including the
//  bind editor). The Play button is disabled until pak0.pk3 is present, which is
//  the one thing that will otherwise send the engine straight into a fatal
//  error on startup.

import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $tab) {
                Text("Game Data").tag(0)
                Text("Graphics").tag(1)
                Text("Controls").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch tab {
                case 0: DataView(model: model)
                case 1: GraphicsView(model: model)
                default: ControlsView(model: model)
                }
            }

            Divider()
            footer
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RETURN TO CASTLE")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(.orange.opacity(0.85))
                Text("Wolfenstein")
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let name = model.controllerName {
                Label(name, systemImage: "gamecontroller.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Label("No controller", systemImage: "gamecontroller")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            Text(model.canPlay ? "Ready" : "Waiting for game data")
                .font(.callout)
                .foregroundStyle(model.canPlay ? .green : .orange)
            Spacer()
            Button {
                model.play()
            } label: {
                Text("PLAY")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(2)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!model.canPlay)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Game data

private struct DataView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.hasAllData {
                    Label("All game files found.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Copy your Return to Castle Wolfenstein data")
                            .font(.headline)
                        Text("""
                             Open Files, go to On My iPad → iORTCW → main, and \
                             copy the .pk3 files from your RTCW installation \
                             into it. They are found in the Main folder of a \
                             GOG or Steam copy.

                             This list updates on its own as the files arrive — \
                             you do not need to restart.
                             """)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(LauncherModel.dataFiles.enumerated()), id: \.offset) { idx, name in
                        let present = model.dataMask & (1 << idx) != 0
                        HStack {
                            Image(systemName: present ? "checkmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(present ? .green : .secondary)
                            Text(name)
                                .font(.system(.callout, design: .monospaced))
                            Spacer()
                            if idx == 0 && !present {
                                Text("required")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder").font(.caption).foregroundStyle(.secondary)
                    Text(model.dataPath + "/main")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Graphics

private struct GraphicsView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Form {
            Section("Display") {
                Picker("Frame rate", selection: $model.maxFPS) {
                    Text("60 fps").tag(60)
                    Text("90 fps").tag(90)
                    Text("120 fps (ProMotion)").tag(120)
                }
                Toggle("Full resolution", isOn: $model.hiDPI)
                Text(model.hiDPI
                     ? "Renders at the panel's native 2752×2064."
                     : "Renders at half resolution. Sharper battery life, softer picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Picture") {
                HStack {
                    Text("Field of view")
                    Slider(value: $model.fov, in: 70...110, step: 5)
                    Text("\(Int(model.fov))°").monospacedDigit().frame(width: 46)
                }
                HStack {
                    Text("Brightness")
                    Slider(value: $model.brightness, in: 1.0...2.5, step: 0.1)
                    Text(String(format: "%.1f", model.brightness))
                        .monospacedDigit().frame(width: 46)
                }
                Text("iOS has no hardware gamma, so brightness is baked into textures and only takes effect on the next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Controls

private struct ControlsView: View {
    @ObservedObject var model: LauncherModel
    @State private var showBinds = false

    var body: some View {
        Form {
            Section("Aiming") {
                HStack {
                    Text("Sensitivity")
                    Slider(value: $model.sensitivity, in: 1...20, step: 0.5)
                    Text(String(format: "%.1f", model.sensitivity))
                        .monospacedDigit().frame(width: 46)
                }
                Toggle("Invert vertical look", isOn: $model.invertLook)
            }

            Section("Gyro aiming") {
                Picker("Gyro", selection: $model.gyroMode) {
                    Text("Off").tag(0)
                    Text("Always on").tag(1)
                    Text("Only while aiming").tag(2)
                }
                if model.gyroMode != 0 {
                    HStack {
                        Text("Gyro sensitivity")
                        Slider(value: $model.gyroSens, in: 0.2...4.0, step: 0.1)
                        Text(String(format: "%.1f", model.gyroSens))
                            .monospacedDigit().frame(width: 46)
                    }
                    Text("Tilting the controller adds to the right stick rather than replacing it — stick for the big turn, gyro for the fine aim.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("DualSense") {
                HStack {
                    Text("Vibration")
                    Slider(value: $model.rumble, in: 0...100, step: 5)
                    Text("\(Int(model.rumble))%").monospacedDigit().frame(width: 52)
                }
                Toggle("Adaptive triggers", isOn: $model.adaptiveTriggers)
                Text("Each weapon gets its own trigger resistance — a light break on the Luger, a heavy one on the Mauser, a rattle on automatics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Full-pull point")
                    Slider(value: $model.triggerHard, in: 0.4...0.95, step: 0.05)
                    Text(String(format: "%.0f%%", model.triggerHard * 100))
                        .monospacedDigit().frame(width: 52)
                }
            }

            Section("On-screen controls") {
                Picker("Show", selection: $model.touchControls) {
                    Text("Only without a controller").tag(0)
                    Text("Always").tag(1)
                    Text("Never").tag(2)
                }
                Text("Three-finger tap is Escape and four-finger tap opens the console, whether or not the controls are shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bindings") {
                Button("Edit controller bindings…") { showBinds = true }
                Button("Reset to defaults", role: .destructive) {
                    model.applyDefaultBindings()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showBinds) {
            BindingsView(model: model)
        }
    }
}

private struct BindingsView: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PadButton.all, id: \.id) { pad in
                    NavigationLink {
                        ActionPicker(model: model, pad: pad)
                    } label: {
                        HStack {
                            Text(pad.title)
                            Spacer()
                            // Both branches must be the same ShapeStyle type;
                            // mixing .secondary (hierarchical) with .orange
                            // (Color) breaks inference for the whole ForEach.
                            Text(model.binding(for: pad)?.title ?? "—")
                                .foregroundStyle(model.binding(for: pad) == nil
                                                 ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            .navigationTitle("Controller bindings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ActionPicker: View {
    @ObservedObject var model: LauncherModel
    let pad: PadButton
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button("Unbound", role: .destructive) {
                    model.assign(nil, to: pad)
                    dismiss()
                }
            }
            ForEach(GameAction.groups, id: \.self) { group in
                Section(group) {
                    ForEach(GameAction.all.filter { $0.group == group }, id: \.id) { action in
                        Button {
                            model.assign(action, to: pad)
                            dismiss()
                        } label: {
                            HStack {
                                Text(action.title).foregroundStyle(.primary)
                                Spacer()
                                if model.bindings[pad.id] == action.id {
                                    Image(systemName: "checkmark").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(pad.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
