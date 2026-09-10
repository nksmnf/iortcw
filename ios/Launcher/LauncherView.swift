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

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $tab) {
                Text("Данные").tag(0)
                Text("Кампания").tag(1)
                Text("Графика").tag(2)
                Text("Управление").tag(3)
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
                Label("Нет контроллера", systemImage: "gamecontroller")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            Text(model.canPlay ? "Готово" : "Нет игровых файлов")
                .font(.callout)
                .foregroundStyle(model.canPlay ? Color.green : Color.orange)
            Spacer()
            Button {
                model.play()
            } label: {
                Text("ИГРАТЬ")
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

private struct DataView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.hasAllData {
                    Label("Все игровые файлы найдены.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Скопируйте данные Return to Castle Wolfenstein")
                            .font(.headline)
                        Text("""
                             Нужны файлы .pk3 из вашей копии игры — они лежат в \
                             папке Main установленной RTCW (GOG или Steam).

                             С Mac: подключите iPad, откройте его в Finder, \
                             вкладка «Файлы», и перетащите файлы .pk3 (или всю \
                             папку Main) на iORTCW. Finder кладёт их только в \
                             корень — это нормально, приложение само перенесёт \
                             их в main/.

                             На самом iPad: Файлы → На iPad → iORTCW.

                             Список обновляется по мере копирования. Большие \
                             файлы появляются только когда докопируются, так что \
                             пауза на pak0.pk3 — это нормально.
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
                                .foregroundStyle(present ? Color.green : Color.secondary)
                            Text(name)
                                .font(.system(.callout, design: .monospaced))
                            Spacer()
                            if idx == 0 && !present {
                                Text("обязателен")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Папка").font(.caption).foregroundStyle(.secondary)
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

// MARK: - Кампания

private struct CampaignView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Form {
            Section("Сложность") {
                Picker("Сложность", selection: $model.skill) {
                    Text("Не делай мне больно").tag(1)
                    Text("Не так уж и плохо").tag(2)
                    Text("Схватка").tag(3)
                    Text("Смерть во плоти").tag(4)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Миссии") {
                ForEach(CampaignMission.all) { mission in
                    Button {
                        model.startMission(mission)
                    } label: {
                        HStack {
                            Text(mission.title)
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
                Text("""
                     Запуск отсюда идёт мимо меню игры. Меню RTCW рассчитано на                      мышь, и на планшете попасть в его пункты неудобно — так что                      это самый прямой путь к игре.

                     Сохранения работают как обычно: быстрое сохранение и                      загрузка есть в раскладке контроллера.
                     """)
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
            Section("Качество") {
                Picker("Пресет", selection: $model.preset) {
                    ForEach(GraphicsPreset.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.preset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Экран") {
                Picker("Кадры/с", selection: $model.maxFPS) {
                    Text("60").tag(60)
                    Text("90").tag(90)
                    Text("120").tag(120)
                }
                .pickerStyle(.segmented)
                Toggle("Полное разрешение", isOn: $model.hiDPI)
                Text(model.hiDPI
                     ? "Рендер в родных 2752×2064."
                     : "Половинное разрешение: мягче картинка, дольше батарея.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Изображение") {
                HStack {
                    Text("Поле зрения")
                    Slider(value: $model.fov, in: 70...110, step: 5)
                    Text("\(Int(model.fov))°").monospacedDigit().frame(width: 46)
                }
                HStack {
                    Text("Яркость")
                    Slider(value: $model.brightness, in: 1.0...2.5, step: 0.1)
                    Text(String(format: "%.1f", model.brightness))
                        .monospacedDigit().frame(width: 46)
                }
                Text("Аппаратной гаммы на iOS нет, поэтому яркость запекается в текстуры и применяется при следующем запуске.")
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
            Section("Стики") {
                Toggle("Движение по 8 направлениям", isOn: $model.moveDigital)
                Text(model.moveDigital
                     ? "Левый стик работает как WASD: северо-восток — это вперёд и вправо. Предсказуемо и без сноса."
                     : "Плавное аналоговое движение.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Скорость поворота")
                    Slider(value: $model.lookYawSpeed, in: 60...400, step: 10)
                    Text("\(Int(model.lookYawSpeed))°/с")
                        .monospacedDigit().frame(width: 64)
                }
                HStack {
                    Text("Вертикаль")
                    Slider(value: $model.lookPitchSpeed, in: 40...300, step: 10)
                    Text("\(Int(model.lookPitchSpeed))°/с")
                        .monospacedDigit().frame(width: 64)
                }
                HStack {
                    Text("Мёртвая зона")
                    Slider(value: $model.stickDeadzone, in: 0.02...0.35, step: 0.01)
                    Text(String(format: "%.0f%%", model.stickDeadzone * 100))
                        .monospacedDigit().frame(width: 64)
                }
                Toggle("Инверсия вертикали", isOn: $model.invertLook)
            }

            Section("DualSense") {
                HStack {
                    Text("Вибрация")
                    Slider(value: $model.rumble, in: 0...100, step: 5)
                    Text("\(Int(model.rumble))%").monospacedDigit().frame(width: 54)
                }
                Text("""
                     Вибрация только при получении урона, и её длительность \
                     показывает, сколько сняли: царапина — короткий тик, \
                     тяжёлое попадание тянется заметно дольше. При стрельбе \
                     контроллер молчит — иначе он гудит постоянно и не сообщает \
                     ничего нового.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Адаптивные триггеры", isOn: $model.adaptiveTriggers)
                Picker("Гироскоп", selection: $model.gyroMode) {
                    Text("Выкл").tag(0)
                    Text("Всегда").tag(1)
                    Text("В прицеле").tag(2)
                }
            }

            Section("Экранные кнопки") {
                Picker("Показывать", selection: $model.touchControls) {
                    Text("Без контроллера").tag(0)
                    Text("Всегда").tag(1)
                    Text("Никогда").tag(2)
                }
                Text("""
                     Кнопка MENU в углу открывает меню игры — там сохранение, \
                     загрузка и выход. Три пальца делают то же самое, четыре — \
                     консоль; и то и другое работает всегда. Тап пропускает \
                     заставку.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Раскладка") {
                Button("Проверка контроллера…") { showTest = true }
                Button("Настроить кнопки…") { showBinds = true }
                Button("Сбросить к стандартной", role: .destructive) {
                    model.applyDefaultBindings()
                }
                Text("""
                     По умолчанию: R2 — огонь, L2 — прицел, R1/L1 — смена оружия, \
                     Квадрат — перезарядка, Треугольник — использовать, Крест — \
                     прыжок, Круг — присесть, L3 — спринт, R3 — удар ногой. \
                     Крестовина ходит, как стрелки на клавиатуре. Свайпы по \
                     тачпаду: вверх-вниз — кратность прицела, влево-вправо — \
                     оружие, тап — предмет.
                     """)
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
                            Text(model.binding(for: pad)?.title ?? "—")
                                .foregroundStyle(model.binding(for: pad) == nil
                                                 ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            .navigationTitle("Кнопки контроллера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
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
                Button("Не назначено", role: .destructive) {
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
