//  LauncherView.swift -- the launcher UI.
//
//  Three tabs: getting the game data in, graphics, and controls. Play stays
//  disabled until pak0.pk3 is present, which is the one thing that otherwise
//  sends the engine straight into a fatal error on startup.
//
//  Russian throughout, since that is the language the person playing this reads.

import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @State private var tab = 0
    @State private var language = Loc.current

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $tab) {
                Text(L("Данные")).tag(0)
                Text(L("Кампания")).tag(1)
                Text(L("Графика")).tag(2)
                Text(L("Управление")).tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch tab {
                case 0: DataView(model: model)
                case 1: CampaignView(model: model)
                case 2: GraphicsView(model: model)
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
        HStack(spacing: 14) {
            // The same eagle as the app icon, so the launcher and the home
            // screen are recognisably one thing.
            Image("WolfLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 1) {
                Text("RETURN TO CASTLE")
                    .font(.system(size: 12, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(5)
                    .foregroundStyle(Theme.emblem)
                Text("WOLFENSTEIN")
                    .font(.system(size: 32, weight: .black))
                    .fontWidth(.condensed)
                    .tracking(1)
                    .foregroundStyle(Theme.wordmark)
            }
            Spacer()
            if let name = model.controllerName {
                Label(name, systemImage: "gamecontroller.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Label(L("Нет контроллера"), systemImage: "gamecontroller")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            Text(model.canPlay ? L("Готово") : L("Нет игровых файлов"))
                .font(.callout)
                .foregroundStyle(model.canPlay ? Color.green : Color.orange)

            Spacer()

            // Every string goes through L(), which reads Loc.current, so
            // changing this redraws the whole launcher in the other language.
            Picker("", selection: $language) {
                ForEach(Loc.Language.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .onChange(of: language) { chosen in Loc.select(chosen) }

            Spacer()
            Button {
                model.play()
            } label: {
                Text(L("ИГРАТЬ"))
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

// MARK: - Данные

/// The two reds, named once.
///
/// The wordmark is deliberately a shade brighter than the emblem: on black the
/// emblem's red goes muddy at text sizes, and the pair reads as one family
/// rather than a mismatch.
enum Theme {
    /// What the app icon is drawn in.
    static let emblem = Color(red: 0.70, green: 0.07, blue: 0.11)
    /// The wordmark, a step brighter so it holds up as type.
    static let wordmark = Color(red: 0.88, green: 0.17, blue: 0.14)
}

private struct DataView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.hasAllData {
                    Label(L("Все игровые файлы найдены."), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)

                    if model.dataMaps > 0 {
                        // Counted from the pk3 directories. Five files of the
                        // right names prove nothing; 35 maps do.
                        Text("\(model.dataMaps) карт · \(model.dataFiles) файлов · "
                             + String(format: "%.0f МБ распакованных данных", model.dataMegabytes))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Скопируйте данные Return to Castle Wolfenstein"))
                            .font(.headline)
                        Text(L("note.data"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(LauncherModel.dataFiles.enumerated()), id: \.offset) { idx, name in
                        let present = model.dataMask & (1 << idx) != 0
                        HStack {
                            Image(systemName: present ? "checkmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(present ? Color.green : Color.secondary)
                            Text(name)
                                .font(.system(.callout, design: .monospaced))
                            Spacer()
                            if idx == 0 && !present {
                                Text(L("обязателен"))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Папка")).font(.caption).foregroundStyle(.secondary)
                    Text(model.dataPath + "/main")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Сборка")).font(.caption).foregroundStyle(.secondary)
                    Text("iORTCW для iPadOS " + model.appVersion + " · " + model.buildTime)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(model.engineVersion)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Кампания

private struct CampaignView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Form {
            Section(L("Сложность")) {
                // Three, and these three values: the game's own play.menu sets
                // g_gameskill to 1, 2 or 3 and offers nothing else.
                Picker(L("Сложность"), selection: $model.skill) {
                    Text(L("Не делай мне больно")).tag(1)
                    Text(L("Не так уж и плохо")).tag(2)
                    Text(L("Смерть во плоти")).tag(3)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section(L("Миссии")) {
                ForEach(CampaignMission.all) { mission in
                    Button {
                        model.startMission(mission)
                    } label: {
                        HStack {
                            Text(L(mission.title))
                                .foregroundStyle(model.canPlay ? Color.primary : Color.secondary)
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .disabled(!model.canPlay)
                }
            }

            Section {
                Text(L("note.campaign"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Графика

private struct GraphicsView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Form {
            Section(L("Качество")) {
                Picker(L("Пресет"), selection: $model.preset) {
                    ForEach(GraphicsPreset.allCases) { p in
                        Text(L(p.title)).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Text(L(model.preset.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Экран")) {
                Picker(L("Кадры/с"), selection: $model.maxFPS) {
                    Text("60").tag(60)
                    Text("90").tag(90)
                    Text("120").tag(120)
                }
                .pickerStyle(.segmented)
                Toggle(L("Полное разрешение"), isOn: $model.hiDPI)
                Text(model.hiDPI
                     ? "Рендер в родных 2752×2064."
                     : "Половинное разрешение: мягче картинка, дольше батарея.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Изображение")) {
                HStack {
                    Text(L("Поле зрения"))
                    Slider(value: $model.fov, in: 70...110, step: 5)
                    Text("\(Int(model.fov))°").monospacedDigit().frame(width: 46)
                }
                HStack {
                    Text(L("Яркость"))
                    Slider(value: $model.brightness, in: 1.0...2.5, step: 0.1)
                    Text(String(format: "%.1f", model.brightness))
                        .monospacedDigit().frame(width: 46)
                }
                Text(L("Аппаратной гаммы на iOS нет, поэтому яркость запекается в текстуры и применяется при следующем запуске."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Управление

private struct ControlsView: View {
    @ObservedObject var model: LauncherModel
    @State private var showBinds = false
    @State private var showTest = false

    var body: some View {
        Form {
            Section(L("Стики")) {
                Toggle(L("Движение по 8 направлениям"), isOn: $model.moveDigital)
                Text(model.moveDigital
                     ? "Левый стик работает как WASD: северо-восток — это вперёд и вправо. Предсказуемо и без сноса."
                     : "Плавное аналоговое движение.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(L("Скорость поворота"))
                    Slider(value: $model.lookYawSpeed, in: 60...400, step: 10)
                    Text("\(Int(model.lookYawSpeed))°/с")
                        .monospacedDigit().frame(width: 64)
                }
                HStack {
                    Text(L("Вертикаль"))
                    Slider(value: $model.lookPitchSpeed, in: 40...300, step: 10)
                    Text("\(Int(model.lookPitchSpeed))°/с")
                        .monospacedDigit().frame(width: 64)
                }
                HStack {
                    Text(L("Мёртвая зона"))
                    Slider(value: $model.stickDeadzone, in: 0.02...0.35, step: 0.01)
                    Text(String(format: "%.0f%%", model.stickDeadzone * 100))
                        .monospacedDigit().frame(width: 64)
                }
                Toggle(L("Инверсия вертикали"), isOn: $model.invertLook)
            }

            Section("DualSense") {
                HStack {
                    Text(L("Вибрация"))
                    Slider(value: $model.rumble, in: 0...100, step: 5)
                    Text("\(Int(model.rumble))%").monospacedDigit().frame(width: 54)
                }
                Text(L("note.haptics"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L("Адаптивные триггеры"), isOn: $model.adaptiveTriggers)
                if model.gyroMode != 0 {
                    HStack {
                        Text(L("Чувствительность гироскопа"))
                        Slider(value: $model.gyroSens, in: 0.2...3.0, step: 0.1)
                        Text(String(format: "%.1f", model.gyroSens))
                            .monospacedDigit().frame(width: 46)
                    }
                }
                Picker(L("Гироскоп"), selection: $model.gyroMode) {
                    Text(L("Выкл")).tag(0)
                    Text(L("Всегда")).tag(1)
                    Text(L("В прицеле")).tag(2)
                }
            }

            Section(L("Экранные кнопки")) {
                Picker(L("Показывать"), selection: $model.touchControls) {
                    Text(L("Автоматически")).tag(0)
                    Text(L("Всегда")).tag(1)
                    Text(L("Никогда")).tag(2)
                }
                Text(L("note.touch"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(L("Чувствительность обзора"))
                    Slider(value: $model.touchLookSens, in: 0.3...3.0, step: 0.1)
                    Text(String(format: "%.1f", model.touchLookSens))
                        .monospacedDigit().frame(width: 46)
                }
                Text(L("Насколько поворачивается вид за движение пальца по правой половине экрана."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L("Гироскоп планшета"), isOn: $model.touchGyro)
                if model.touchGyro {
                    HStack {
                        Text(L("Чувствительность гироскопа"))
                        Slider(value: $model.touchGyroSens, in: 0.2...3.0, step: 0.1)
                        Text(String(format: "%.1f", model.touchGyroSens))
                            .monospacedDigit().frame(width: 46)
                    }
                }
                Text(L("note.gyro"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("note.menu"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Звук")) {
                HStack {
                    Text(L("Громкость"))
                    Slider(value: $model.volume, in: 0...1, step: 0.05)
                    Text("\(Int(model.volume * 100))%").monospacedDigit().frame(width: 54)
                }
                HStack {
                    Text(L("Музыка"))
                    Slider(value: $model.musicVolume, in: 0...1, step: 0.05)
                    Text("\(Int(model.musicVolume * 100))%").monospacedDigit().frame(width: 54)
                }
            }

            Section(L("Игра")) {
                Toggle(L("Переключаться на подобранное оружие"), isOn: $model.autoSwitch)
                Toggle(L("Покачивание камеры при ходьбе"), isOn: $model.viewBob)
                HStack {
                    Text(L("Размер прицела"))
                    Slider(value: $model.crosshairSize, in: 16...96, step: 4)
                    Text("\(Int(model.crosshairSize))").monospacedDigit().frame(width: 46)
                }
            }

            Section(L("Диагностика")) {
                Toggle(L("Панель производительности"), isOn: $model.perfHud)
                Toggle(L("Запись производительности в perf.csv"), isOn: $model.perfLog)
                Toggle(L("Запись событий контроллера в лог"), isOn: $model.padLog)
                Text(L("note.diag"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Раскладка")) {
                Button(L("Проверка контроллера…")) { showTest = true }
                Button(L("Настроить кнопки…")) { showBinds = true }
                Button(L("Сбросить к стандартной"), role: .destructive) {
                    model.applyDefaultBindings()
                }
                Text(L("note.layout"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showBinds) { BindingsView(model: model) }
        .sheet(isPresented: $showTest) { ControllerTestView() }
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
                            Text(model.binding(for: pad).map { L($0.title) } ?? "—")
                                .foregroundStyle(model.binding(for: pad) == nil
                                                 ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            .navigationTitle(L("Кнопки контроллера"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово")) { dismiss() }
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
                Button(L("Не назначено"), role: .destructive) {
                    model.assign(nil, to: pad)
                    dismiss()
                }
            }
            ForEach(GameAction.groups, id: \.self) { group in
                Section(L(group)) {
                    ForEach(GameAction.all.filter { $0.group == group }, id: \.id) { action in
                        Button {
                            model.assign(action, to: pad)
                            dismiss()
                        } label: {
                            HStack {
                                Text(L(action.title)).foregroundStyle(.primary)
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
