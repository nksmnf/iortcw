//  LauncherView.swift -- the launcher UI.
//
//  Three tabs: getting the game data in, graphics, and controls. Play stays
//  disabled until pak0.pk3 is present, which is the one thing that otherwise
//  sends the engine straight into a fatal error on startup.
//
//  Russian throughout, since that is the language the person playing this reads.
//
//  Two things run through the whole file. The colours are the system's, so the
//  launcher follows the iPad's own light or dark setting instead of being
//  painted black regardless; and every screen can be driven from the controller
//  as well as by finger, through the cursor in LauncherPad.swift. Neither takes
//  anything away from the other: the focus ring appears only when a pad is
//  connected, and every control it lands on is still there to be tapped.

import SwiftUI
import UIKit

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @StateObject private var pad = PadInput()
    @State private var scope = PadScope()
    @State private var tab = 0
    @State private var language = Loc.current

    private static let tabCount = 4

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
                case 0: DataView(model: model, pad: pad, scope: scope)
                case 1: CampaignView(model: model, pad: pad, scope: scope)
                case 2: GraphicsView(model: model, pad: pad, scope: scope)
                default: ControlsView(model: model, pad: pad, scope: scope)
                }
            }

            Divider()
            footer
        }
        .background(Theme.background.ignoresSafeArea())
        .padScope(pad, scope)
        // The poll runs only while the launcher is up. It is put over the game
        // and taken down again, and a timer left behind would go on reading the
        // pad that is by then being used to play with.
        .onAppear { pad.start() }
        .onDisappear { pad.stop() }
        .onReceive(pad.strokes) { key in
            guard pad.isActive(scope) else { return }
            switch key {
            case .tabPrev: tab = (tab + LauncherView.tabCount - 1) % LauncherView.tabCount
            case .tabNext: tab = (tab + 1) % LauncherView.tabCount
            // Options starts the game from wherever the cursor happens to be,
            // the way a console menu keeps one button that always means "go".
            case .start: if model.canPlay { model.play() }
            default: break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            // The same eagle as the app icon, so the launcher and the home
            // screen are recognisably one thing. The artwork is red on
            // transparent, which is legible on either theme's ground, so it
            // takes no tint and needs nothing behind it.
            Image("WolfLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54)

            WolfTitle()

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let name = model.controllerName {
                    Label(name, systemImage: "gamecontroller.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                    // Only worth screen space when there is a pad to use it.
                    Text(L("D-pad — выбор, Cross — подтвердить, Circle — назад, L1/R1 — вкладки"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                } else {
                    Label(L("Нет контроллера"), systemImage: "gamecontroller")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            Text(model.canPlay ? L("Готово") : L("Нет игровых файлов"))
                .font(.callout)
                .foregroundStyle(model.canPlay ? Color.green : Theme.accent)

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

            VStack(spacing: 3) {
                Button {
                    model.play()
                } label: {
                    Text(L("ИГРАТЬ"))
                        .font(.system(size: 18, weight: .bold))
                        .tracking(2)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 12)
                        // Black rather than the button style's white: orange is
                        // a light colour in both themes, and white on it is
                        // barely there.
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!model.canPlay)

                if model.controllerName != nil {
                    Text(L("Options — начать игру"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

/// The two title lines, the upper one spaced out to the width of the wordmark
/// below it.
///
/// The spacing is laid out rather than typed in. A tracking value fitted by eye
/// fits one string in one font at one size, and the moment either line changes
/// -- another language, another weight -- it is left short or overhanging. Here
/// the letters of the upper line are separate views with flexible gaps between
/// them, so the stack sizes itself to the wordmark and the gaps take up exactly
/// whatever slack there is. Nothing is measured and nothing is stored: it comes
/// out right for whatever text is put in it.
private struct WolfTitle: View {
    private static let upper = "RETURN TO CASTLE"
    private static let lower = "WOLFENSTEIN"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                let letters = Array(WolfTitle.upper)
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    // A plain space on its own is trailing whitespace as far as
                    // the type setter is concerned and measures nothing, which
                    // would close up the gaps between words.
                    Text(letter == " " ? "\u{00A0}" : String(letter))
                    if index < letters.count - 1 {
                        // minLength 0, so the ideal width of this row is the
                        // text alone and the stack is sized by the wordmark.
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(.system(size: 12, weight: .heavy))
            .fontWidth(.condensed)
            .foregroundStyle(Theme.emblem)
            // Split into letters it would otherwise be read out one at a time.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(WolfTitle.upper))

            Text(WolfTitle.lower)
                .font(.system(size: 32, weight: .black))
                .fontWidth(.condensed)
                .tracking(1)
                .foregroundStyle(Theme.wordmark)
        }
        // Without this the flexible row above would claim the whole header.
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Цвета

/// The launcher's colours, named once.
///
/// The two reds are the game's own and are fixed: the wordmark is deliberately
/// a shade brighter than the emblem, because on black the emblem's red goes
/// muddy at text sizes, and the pair reads as one family rather than a
/// mismatch. Both hold up on a white ground as well, so they do not change with
/// the theme -- a brand colour that moves is not a brand colour.
///
/// Everything else is the system's, so the launcher follows the iPad's light or
/// dark setting. That is the whole reason there is a table here: a hand-picked
/// `Color.white.opacity(0.05)` is invisible the moment the ground turns white.
enum Theme {
    /// What the app icon is drawn in.
    static let emblem = Color(red: 0.70, green: 0.07, blue: 0.11)
    /// The wordmark, a step brighter so it holds up as type.
    static let wordmark = Color(red: 0.88, green: 0.17, blue: 0.14)

    /// The ground the launcher sits on, matching what a grouped Form expects
    /// behind it: pale grey in the light theme, near-black in the dark one.
    static let background = Color(uiColor: .systemGroupedBackground)
    /// Cards that stand off that ground, the same fill the Form gives its own
    /// rows so hand-built panels and Form sections look like one thing.
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    /// Anything drawn over the ground -- tracks, chips, rings. Tied to the text
    /// colour rather than to white, so it inverts with the theme.
    static func fill(_ opacity: Double) -> Color { Color.primary.opacity(opacity) }

    /// The launcher's one accent, and the colour of the pad cursor. Orange in
    /// both themes: it is what the game's own menus highlight with, and it
    /// stays clear of the red marks in the header instead of competing.
    static let accent = Color.orange
    /// Text and glyphs sitting on top of the accent. Orange is light in either
    /// theme, so this is black in either theme.
    static let onAccent = Color.black
}

// MARK: - Данные

private struct DataView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope

    /// Nothing on this page can be pressed -- it is a checklist and two
    /// paragraphs -- so the pad only scrolls it. Drawing a focus ring on a row
    /// that would do nothing when confirmed would be a promise the page cannot
    /// keep.
    @State private var mark = 0
    private static let marks = 3

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // A stack rather than a Group: a Group hands its modifiers
                    // to each child, which would put the same scroll id on two
                    // of them.
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
                    }
                    .id(0)

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
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .id(1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Папка")).font(.caption).foregroundStyle(.secondary)
                        Text(model.dataPath + "/main")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .id(2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Сборка")).font(.caption).foregroundStyle(.secondary)
                        Text("iORTCW для iPadOS " + model.appVersion + " · " + model.buildTime)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(model.engineVersion)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .id(3)
                }
                .padding(24)
            }
            .onReceive(pad.strokes) { key in
                guard pad.isActive(scope) else { return }
                switch key {
                case .up:   mark = max(mark - 1, 0)
                case .down: mark = min(mark + 1, DataView.marks)
                default:    return
                }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(mark, anchor: .top) }
            }
        }
    }
}

// MARK: - Кампания

private struct CampaignView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    @State private var cursor = 0

    /// Three, and these three values: the game's own play.menu sets
    /// g_gameskill to 1, 2 or 3 and offers nothing else.
    private static let skills: [(value: Int, title: String)] = [
        (1, "Не делай мне больно"),
        (2, "Не так уж и плохо"),
        (3, "Смерть во плоти"),
    ]

    /// The order the pad walks, which is the order the rows are drawn in.
    private enum Row: Hashable {
        case skill(Int)
        case mission(String)
    }

    private var rows: [Row] {
        CampaignView.skills.map { Row.skill($0.value) }
            + CampaignMission.all.map { Row.mission($0.id) }
    }

    private func focused(_ row: Row) -> Bool {
        pad.connected && pad.isActive(scope)
            && rows.indices.contains(cursor) && rows[cursor] == row
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(L("Сложность")) {
                    // Written out as rows rather than left as an inline Picker:
                    // the picker's rows are its own and cannot be given a focus
                    // ring, and the pad has to be able to land on each one.
                    ForEach(CampaignView.skills, id: \.value) { skill in
                        Button {
                            model.skill = skill.value
                        } label: {
                            HStack {
                                Text(L(skill.title)).foregroundStyle(Color.primary)
                                Spacer()
                                if model.skill == skill.value {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .id(Row.skill(skill.value))
                        .padFocus(focused(.skill(skill.value)))
                    }
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
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .disabled(!model.canPlay)
                        .id(Row.mission(mission.id))
                        .padFocus(focused(.mission(mission.id)))
                    }
                }

                Section {
                    Text(L("note.campaign"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        let rows = self.rows
        switch key {
        case .up, .down:
            guard !rows.isEmpty else { return }
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), rows.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor], anchor: .center)
            }
        case .confirm:
            guard rows.indices.contains(cursor) else { return }
            switch rows[cursor] {
            case .skill(let value):
                model.skill = value
            case .mission(let id):
                guard model.canPlay,
                      let mission = CampaignMission.all.first(where: { $0.id == id }) else { return }
                model.startMission(mission)
            }
        default:
            break
        }
    }
}

// MARK: - Графика

private struct GraphicsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    @State private var cursor = 0

    private enum Row: CaseIterable, Hashable {
        case preset, fps, hiDPI, fov, brightness
    }

    private var rows: [Row] { Row.allCases }

    private func focused(_ row: Row) -> Bool {
        pad.connected && pad.isActive(scope)
            && rows.indices.contains(cursor) && rows[cursor] == row
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(L("Качество")) {
                    Picker(L("Пресет"), selection: $model.preset) {
                        ForEach(GraphicsPreset.allCases) { p in
                            Text(L(p.title)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .id(Row.preset)
                    .padFocus(focused(.preset))
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
                    .id(Row.fps)
                    .padFocus(focused(.fps))
                    Toggle(L("Полное разрешение"), isOn: $model.hiDPI)
                        .id(Row.hiDPI)
                        .padFocus(focused(.hiDPI))
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
                    .id(Row.fov)
                    .padFocus(focused(.fov))
                    HStack {
                        Text(L("Яркость"))
                        Slider(value: $model.brightness, in: 1.0...2.5, step: 0.1)
                        Text(String(format: "%.1f", model.brightness))
                            .monospacedDigit().frame(width: 46)
                    }
                    .id(Row.brightness)
                    .padFocus(focused(.brightness))
                    Text(L("Аппаратной гаммы на iOS нет, поэтому яркость запекается в текстуры и применяется при следующем запуске."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        switch key {
        case .up, .down:
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), rows.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor], anchor: .center)
            }
        case .left, .right, .confirm:
            guard rows.indices.contains(cursor) else { return }
            act(rows[cursor], key)
        default:
            break
        }
    }

    private func act(_ row: Row, _ key: PadKey) {
        let forward = key != .left
        switch row {
        case .preset:
            padCycle(&model.preset, through: GraphicsPreset.allCases, forward: forward)
        case .fps:
            padCycle(&model.maxFPS, through: [60, 90, 120], forward: forward)
        case .hiDPI:
            switch key {
            case .confirm: model.hiDPI.toggle()
            case .left:    model.hiDPI = false
            default:       model.hiDPI = true
            }
        case .fov:
            guard key != .confirm else { return }
            padStep(&model.fov, by: 5, in: 70...110, up: forward)
        case .brightness:
            guard key != .confirm else { return }
            padStep(&model.brightness, by: 0.1, in: 1.0...2.5, up: forward)
        }
    }
}

// MARK: - Управление

private struct ControlsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    @State private var showBinds = false
    @State private var showTest = false
    @State private var cursor = 0

    /// Declared in the order they are drawn, which is the order the pad walks
    /// them in. `rows` drops the two that are only sometimes on screen.
    private enum Row: CaseIterable, Hashable {
        case moveDigital, yaw, pitch, deadzone, invertLook
        case rumble, adaptive, gyroSens, gyroInvertYaw, gyroInvertPitch, gyroMode
        case touchControls, touchLookSens, touchGyro, touchGyroSens
        case volume, music
        case autoSwitch, viewBob, crosshair
        case perfHud, perfLog, padLog
        case test, binds, reset
    }

    /// What a row does when it is confirmed or pushed sideways. Written as one
    /// table so a row cannot be drawn and driven by two different rules.
    private enum Kind {
        case flag(ReferenceWritableKeyPath<LauncherModel, Bool>)
        case range(ReferenceWritableKeyPath<LauncherModel, Double>, ClosedRange<Double>, Double)
        case choice(ReferenceWritableKeyPath<LauncherModel, Int>, [Int])
        case press(() -> Void)
    }

    private var rows: [Row] {
        Row.allCases.filter { row in
            switch row {
            case .gyroSens, .gyroInvertYaw, .gyroInvertPitch:
                return model.gyroMode != 0
            case .touchGyroSens:
                return model.touchGyro
            default:
                return true
            }
        }
    }

    private func focused(_ row: Row) -> Bool {
        pad.connected && pad.isActive(scope)
            && rows.indices.contains(cursor) && rows[cursor] == row
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(L("Стики")) {
                    Toggle(L("Движение по 8 направлениям"), isOn: $model.moveDigital)
                        .id(Row.moveDigital)
                        .padFocus(focused(.moveDigital))
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
                    .id(Row.yaw)
                    .padFocus(focused(.yaw))
                    HStack {
                        Text(L("Вертикаль"))
                        Slider(value: $model.lookPitchSpeed, in: 40...300, step: 10)
                        Text("\(Int(model.lookPitchSpeed))°/с")
                            .monospacedDigit().frame(width: 64)
                    }
                    .id(Row.pitch)
                    .padFocus(focused(.pitch))
                    HStack {
                        Text(L("Мёртвая зона"))
                        Slider(value: $model.stickDeadzone, in: 0.02...0.35, step: 0.01)
                        Text(String(format: "%.0f%%", model.stickDeadzone * 100))
                            .monospacedDigit().frame(width: 64)
                    }
                    .id(Row.deadzone)
                    .padFocus(focused(.deadzone))
                    Toggle(L("Инверсия вертикали"), isOn: $model.invertLook)
                        .id(Row.invertLook)
                        .padFocus(focused(.invertLook))
                }

                Section("DualSense") {
                    HStack {
                        Text(L("Вибрация"))
                        Slider(value: $model.rumble, in: 0...100, step: 5)
                        Text("\(Int(model.rumble))%").monospacedDigit().frame(width: 54)
                    }
                    .id(Row.rumble)
                    .padFocus(focused(.rumble))
                    Text(L("note.haptics"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(L("Адаптивные триггеры"), isOn: $model.adaptiveTriggers)
                        .id(Row.adaptive)
                        .padFocus(focused(.adaptive))
                    if model.gyroMode != 0 {
                        HStack {
                            Text(L("Чувствительность гироскопа"))
                            Slider(value: $model.gyroSens, in: 0.2...3.0, step: 0.1)
                            Text(String(format: "%.1f", model.gyroSens))
                                .monospacedDigit().frame(width: 46)
                        }
                        .id(Row.gyroSens)
                        .padFocus(focused(.gyroSens))

                        // Which way a gyro should turn the view is not something
                        // the code can work out -- only the person holding it
                        // knows it is going the wrong way -- so it is a switch,
                        // one per axis.
                        Toggle(L("Инверсия гироскопа по горизонтали"), isOn: $model.gyroInvertYaw)
                            .id(Row.gyroInvertYaw)
                            .padFocus(focused(.gyroInvertYaw))
                        Toggle(L("Инверсия гироскопа по вертикали"), isOn: $model.gyroInvertPitch)
                            .id(Row.gyroInvertPitch)
                            .padFocus(focused(.gyroInvertPitch))
                        Text(L("Действует и на гироскоп контроллера, и на гироскоп планшета."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker(L("Гироскоп"), selection: $model.gyroMode) {
                        Text(L("Выкл")).tag(0)
                        Text(L("Всегда")).tag(1)
                        Text(L("В прицеле")).tag(2)
                    }
                    .id(Row.gyroMode)
                    .padFocus(focused(.gyroMode))
                }

                Section(L("Экранные кнопки")) {
                    Picker(L("Показывать"), selection: $model.touchControls) {
                        Text(L("Автоматически")).tag(0)
                        Text(L("Всегда")).tag(1)
                        Text(L("Никогда")).tag(2)
                    }
                    .id(Row.touchControls)
                    .padFocus(focused(.touchControls))
                    Text(L("note.touch"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(L("Чувствительность обзора"))
                        Slider(value: $model.touchLookSens, in: 0.3...3.0, step: 0.1)
                        Text(String(format: "%.1f", model.touchLookSens))
                            .monospacedDigit().frame(width: 46)
                    }
                    .id(Row.touchLookSens)
                    .padFocus(focused(.touchLookSens))
                    Text(L("Насколько поворачивается вид за движение пальца по правой половине экрана."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(L("Гироскоп планшета"), isOn: $model.touchGyro)
                        .id(Row.touchGyro)
                        .padFocus(focused(.touchGyro))
                    if model.touchGyro {
                        HStack {
                            Text(L("Чувствительность гироскопа"))
                            Slider(value: $model.touchGyroSens, in: 0.2...3.0, step: 0.1)
                            Text(String(format: "%.1f", model.touchGyroSens))
                                .monospacedDigit().frame(width: 46)
                        }
                        .id(Row.touchGyroSens)
                        .padFocus(focused(.touchGyroSens))
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
                    .id(Row.volume)
                    .padFocus(focused(.volume))
                    HStack {
                        Text(L("Музыка"))
                        Slider(value: $model.musicVolume, in: 0...1, step: 0.05)
                        Text("\(Int(model.musicVolume * 100))%").monospacedDigit().frame(width: 54)
                    }
                    .id(Row.music)
                    .padFocus(focused(.music))
                }

                Section(L("Игра")) {
                    Toggle(L("Переключаться на подобранное оружие"), isOn: $model.autoSwitch)
                        .id(Row.autoSwitch)
                        .padFocus(focused(.autoSwitch))
                    Toggle(L("Покачивание камеры при ходьбе"), isOn: $model.viewBob)
                        .id(Row.viewBob)
                        .padFocus(focused(.viewBob))
                    HStack {
                        Text(L("Размер прицела"))
                        Slider(value: $model.crosshairSize, in: 16...96, step: 4)
                        Text("\(Int(model.crosshairSize))").monospacedDigit().frame(width: 46)
                    }
                    .id(Row.crosshair)
                    .padFocus(focused(.crosshair))
                }

                Section(L("Диагностика")) {
                    Toggle(L("Панель производительности"), isOn: $model.perfHud)
                        .id(Row.perfHud)
                        .padFocus(focused(.perfHud))
                    Toggle(L("Запись производительности в perf.csv"), isOn: $model.perfLog)
                        .id(Row.perfLog)
                        .padFocus(focused(.perfLog))
                    Toggle(L("Запись событий контроллера в лог"), isOn: $model.padLog)
                        .id(Row.padLog)
                        .padFocus(focused(.padLog))
                    Text(L("note.diag"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L("Раскладка")) {
                    Button(L("Проверка контроллера…")) { showTest = true }
                        .id(Row.test)
                        .padFocus(focused(.test))
                    Button(L("Настроить кнопки…")) { showBinds = true }
                        .id(Row.binds)
                        .padFocus(focused(.binds))
                    Button(L("Сбросить к стандартной"), role: .destructive) {
                        model.applyDefaultBindings()
                    }
                    .id(Row.reset)
                    .padFocus(focused(.reset))
                    Text(L("note.layout"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
        .sheet(isPresented: $showBinds) { BindingsView(model: model, pad: pad) }
        .sheet(isPresented: $showTest) { ControllerTestView(pad: pad) }
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        let rows = self.rows
        switch key {
        case .up, .down:
            guard !rows.isEmpty else { return }
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), rows.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor], anchor: .center)
            }
        case .left, .right, .confirm:
            guard rows.indices.contains(cursor) else { return }
            let row = rows[cursor]
            act(row, key)
            // Switching the gyro on inserts its sensitivity row above this one.
            // Follow the row that was just changed rather than the index, so the
            // cursor does not slide onto the control that appeared under it.
            if let moved = self.rows.firstIndex(of: row) { cursor = moved }
        default:
            break
        }
    }

    private func kind(of row: Row) -> Kind {
        switch row {
        case .moveDigital:   return .flag(\.moveDigital)
        case .yaw:           return .range(\.lookYawSpeed, 60...400, 10)
        case .pitch:         return .range(\.lookPitchSpeed, 40...300, 10)
        case .deadzone:      return .range(\.stickDeadzone, 0.02...0.35, 0.01)
        case .invertLook:    return .flag(\.invertLook)
        case .rumble:        return .range(\.rumble, 0...100, 5)
        case .adaptive:      return .flag(\.adaptiveTriggers)
        case .gyroSens:      return .range(\.gyroSens, 0.2...3.0, 0.1)
        case .gyroInvertYaw:   return .flag(\.gyroInvertYaw)
        case .gyroInvertPitch: return .flag(\.gyroInvertPitch)
        case .gyroMode:      return .choice(\.gyroMode, [0, 1, 2])
        case .touchControls: return .choice(\.touchControls, [0, 1, 2])
        case .touchLookSens: return .range(\.touchLookSens, 0.3...3.0, 0.1)
        case .touchGyro:     return .flag(\.touchGyro)
        case .touchGyroSens: return .range(\.touchGyroSens, 0.2...3.0, 0.1)
        case .volume:        return .range(\.volume, 0...1, 0.05)
        case .music:         return .range(\.musicVolume, 0...1, 0.05)
        case .autoSwitch:    return .flag(\.autoSwitch)
        case .viewBob:       return .flag(\.viewBob)
        case .crosshair:     return .range(\.crosshairSize, 16...96, 4)
        case .perfHud:       return .flag(\.perfHud)
        case .perfLog:       return .flag(\.perfLog)
        case .padLog:        return .flag(\.padLog)
        case .test:          return .press { showTest = true }
        case .binds:         return .press { showBinds = true }
        case .reset:         return .press { model.applyDefaultBindings() }
        }
    }

    private func act(_ row: Row, _ key: PadKey) {
        switch kind(of: row) {
        case .flag(let path):
            // Cross flips it; left and right set it outright, which is what a
            // switch looks like it should do.
            switch key {
            case .confirm: model[keyPath: path].toggle()
            case .left:    model[keyPath: path] = false
            default:       model[keyPath: path] = true
            }
        case .range(let path, let range, let step):
            guard key != .confirm else { return }
            padStep(&model[keyPath: path], by: step, in: range, up: key != .left)
        case .choice(let path, let options):
            padCycle(&model[keyPath: path], through: options, forward: key != .left)
        case .press(let action):
            if key == .confirm { action() }
        }
    }
}

private struct BindingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    @Environment(\.dismiss) private var dismiss
    @State private var scope = PadScope()
    @State private var cursor = 0
    /// Driven by hand rather than by NavigationLink alone, so that Cross can
    /// push the same screen a tap does.
    @State private var path: [PadButton] = []

    private func focused(_ button: PadButton) -> Bool {
        pad.connected && pad.isActive(scope)
            && PadButton.all.indices.contains(cursor) && PadButton.all[cursor].id == button.id
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    ForEach(PadButton.all, id: \.id) { button in
                        NavigationLink(value: button) {
                            HStack {
                                Text(button.title)
                                Spacer()
                                Text(model.binding(for: button).map { L($0.title) } ?? "—")
                                    .foregroundStyle(model.binding(for: button) == nil
                                                     ? Color.secondary : Theme.accent)
                            }
                        }
                        .id(button.id)
                        .padFocus(focused(button))
                    }
                }
                .navigationDestination(for: PadButton.self) { button in
                    ActionPicker(model: model, pad: pad, button: button)
                }
                .navigationTitle(L("Кнопки контроллера"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Готово")) { dismiss() }
                    }
                }
                .onReceive(pad.strokes) { key in handle(key, proxy) }
            }
        }
        .padScope(pad, scope)
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        switch key {
        case .up, .down:
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), PadButton.all.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(PadButton.all[cursor].id, anchor: .center)
            }
        case .confirm:
            guard PadButton.all.indices.contains(cursor) else { return }
            path.append(PadButton.all[cursor])
        case .back:
            dismiss()
        default:
            break
        }
    }
}

private struct ActionPicker: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let button: PadButton
    @Environment(\.dismiss) private var dismiss
    @State private var scope = PadScope()
    @State private var cursor = 0

    /// The rows in the order they are drawn, nil being "unassigned". The list
    /// below walks the same groups in the same order, so an index here always
    /// means the row the player is looking at.
    private var rows: [GameAction?] {
        [nil] + GameAction.groups.flatMap { group in
            GameAction.all.filter { $0.group == group }
        }
    }

    private func focused(_ action: GameAction?) -> Bool {
        guard pad.connected, pad.isActive(scope), rows.indices.contains(cursor) else { return false }
        return rows[cursor]?.id == action?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Button(L("Не назначено"), role: .destructive) {
                        model.assign(nil, to: button)
                        dismiss()
                    }
                    .id("—")
                    .padFocus(focused(nil))
                }
                ForEach(GameAction.groups, id: \.self) { group in
                    Section(L(group)) {
                        ForEach(GameAction.all.filter { $0.group == group }, id: \.id) { action in
                            Button {
                                model.assign(action, to: button)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(L(action.title)).foregroundStyle(.primary)
                                    Spacer()
                                    if model.bindings[button.id] == action.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .id(action.id)
                            .padFocus(focused(action))
                        }
                    }
                }
            }
            .navigationTitle(button.title)
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
        .padScope(pad, scope)
    }

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }
        let rows = self.rows
        switch key {
        case .up, .down:
            cursor = min(max(cursor + (key == .down ? 1 : -1), 0), rows.count - 1)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(rows[cursor]?.id ?? "—", anchor: .center)
            }
        case .confirm:
            guard rows.indices.contains(cursor) else { return }
            model.assign(rows[cursor], to: button)
            dismiss()
        case .back:
            dismiss()
        default:
            break
        }
    }
}
