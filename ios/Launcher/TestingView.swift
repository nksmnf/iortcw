//  TestingView.swift -- the launcher's own test runs.
//
//  Two buttons and a list. That is the whole of the interface on purpose: the
//  runs themselves are elaborate, and every part of them that could have been a
//  setting on this page is instead decided by the run, so that two people who
//  press the same button get the same answer.
//
//  What happens when a button is pressed: the launcher hands over to the engine
//  with `selftest` on the command line, exactly as it hands over for a game. The
//  engine runs the checks, writes selftest.txt, and calls back in to reopen the
//  launcher on this page with the result. So the player presses one thing and
//  reads one thing, and the two or three minutes in between look like the game
//  starting -- which is what they are.
//
//  The rows come from cl_selftest.c and are already written in the launcher's
//  own language; nothing here interprets them, which is deliberate. A page that
//  decides what a failure means is a page that has to be edited every time a
//  check is added.

import SwiftUI

enum TestVerdict {
    case pass, fail, skip
}

struct TestRow: Identifiable {
    let id: Int
    let verdict: TestVerdict
    let group: String
    let name: String
    let detail: String
}

/// The last report, wherever it came from.
@MainActor
final class SelfTestReport: ObservableObject {
    @Published private(set) var rows: [TestRow] = []
    @Published private(set) var passed = 0
    @Published private(set) var failed = 0
    @Published private(set) var skipped = 0

    /// Whether this is a run that happened in this session rather than one read
    /// back off disk. Worth showing: after a run the page reopens by itself, and
    /// a player who cannot tell a fresh report from last week's has no way to
    /// know the button did anything.
    @Published private(set) var fresh = false

    /// Which half of the game the report is about, taken from its own header
    /// rather than from whatever the page happens to have selected. A report
    /// labelled with the wrong game is worse than one with no label: every row
    /// in it is then read against the wrong engine.
    @Published private(set) var multiplayer: Bool?

    private static let bufferSize = 64 * 1024

    func load() {
        var buf = [CChar](repeating: 0, count: SelfTestReport.bufferSize)

        // A run from this session wins over the file. The file is only written
        // when a run finishes, so an interrupted run has rows in memory that
        // exist nowhere else, and they are the interesting ones.
        var n = IOSBridge_SelfTestSnapshot(&buf, Int32(SelfTestReport.bufferSize))
        var live = n > 0

        if n <= 0 {
            n = IOSBridge_SelfTestLoadStored(&buf, Int32(SelfTestReport.bufferSize))
            live = false
        }

        guard n > 0 else {
            rows = []
            passed = 0; failed = 0; skipped = 0
            fresh = false
            return
        }

        parse(String(cString: buf), live: live)
    }

    private func parse(_ text: String, live: Bool) {
        var out: [TestRow] = []
        var p = 0, f = 0, s = 0

        var game: Bool?

        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") {
                if line.contains("multiplayer") { game = true }
                if line.contains("campaign")    { game = false }
                continue
            }

            let parts = line.split(separator: "\t", maxSplits: 3,
                                   omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let verdict: TestVerdict
            switch parts[0] {
            case "PASS": verdict = .pass; p += 1
            case "FAIL": verdict = .fail; f += 1
            default:     verdict = .skip; s += 1
            }

            out.append(TestRow(id: out.count,
                               verdict: verdict,
                               group: String(parts[1]),
                               name: String(parts[2]),
                               detail: parts.count > 3 ? String(parts[3]) : ""))
        }

        rows = out
        passed = p; failed = f; skipped = s
        fresh = live
        multiplayer = game
    }

    /// Group names in the order they first appear, which is the order the run
    /// performed them in. Sorting them would put "Графика" before "Данные" and
    /// lose the one piece of information the order carries: what ran before
    /// what, and therefore what a later failure might be downstream of.
    var groups: [String] {
        var seen: [String] = []
        for row in rows where !seen.contains(row.group) {
            seen.append(row.group)
        }
        return seen
    }

    var isEmpty: Bool { rows.isEmpty }
}

struct TestingView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var pad: PadInput
    let scope: PadScope
    let onFooter: () -> Void

    @StateObject private var report = SelfTestReport()
    @State private var cursor = 0
    @State private var multiplayer = false

    private enum Row: CaseIterable, Hashable {
        case game, basic, full
    }

    private var rows: [Row] { Row.allCases }

    private func focused(_ row: Row) -> Bool {
        pad.connected && pad.isActive(scope)
            && rows.indices.contains(cursor) && rows[cursor] == row
    }

    private var canRun: Bool {
        multiplayer ? model.canPlayMultiplayer : model.canPlayCampaign
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: Space.xxl) {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        whatPanel
                        runPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Space.xl) {
                        resultPanel
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.xl)
            }
            .onReceive(pad.strokes) { key in handle(key, proxy) }
        }
        .onAppear {
            report.load()

            // The report's own game wins, so the page that has just come back
            // from a run is set to the half the run was about. Failing that,
            // whichever half is installed -- campaign first, because that is
            // what most copies have.
            multiplayer = report.multiplayer
                ?? (!model.canPlayCampaign && model.canPlayMultiplayer)
        }
    }

    // MARK: - что проверяем

    private var whatPanel: some View {
        Panel(L("Что проверять")) {
            Field(note: L("Две половины игры — это два независимых движка в одном приложении, и проверяются они порознь. Настройки у них общие, поэтому расхождение между ними чаще всего и оказывается ошибкой.")) {
                Picker("", selection: $multiplayer) {
                    Text(L("Кампания")).tag(false)
                    Text(L("Мультиплеер")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .id(Row.game)
                .padFocusRing(focused(.game), radius: controlRadius)
            }

            if !canRun {
                Text(L("Файлы этой половины игры не найдены — проверять нечего."))
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - прогон

    private var runPanel: some View {
        Panel(L("Прогон")) {
            VStack(alignment: .leading, spacing: Space.l) {
                runButton(
                    title: L("Основная проверка"),
                    subtitle: L("Около десяти секунд. Спрашивает движок, дошли ли до него настройки лаунчера, существуют ли команды, которые он назначает на клавиши, знает ли он имена этих клавиш, то ли разрешение на экране и на месте ли файлы игры."),
                    row: .basic,
                    prominent: true
                ) {
                    model.runSelfTest(full: false, multiplayer: multiplayer)
                }

                runButton(
                    title: L("Полная проверка"),
                    subtitle: L("Две-три минуты. Всё то же самое, а затем игра сама загрузит карту, прогонит таблицу стиков и гироскопа из двадцати одной строки и замерит частоту кадров. Экран будет жить своей жизнью — так и должно быть."),
                    row: .full,
                    prominent: false
                ) {
                    model.runSelfTest(full: true, multiplayer: multiplayer)
                }

                Text(L("Игра запустится, прогон пройдёт сам, лаунчер вернётся сюда с результатом. Отчёт остаётся в Documents/main/selftest.txt."))
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runButton(title: String, subtitle: String, row: Row,
                           prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title)
                    .font(TypeScale.row.weight(.semibold))
                    .foregroundStyle(canRun
                        ? (prominent ? Theme.onAccent : Color.primary)
                        : Color.secondary)
                Text(subtitle)
                    .font(TypeScale.caption)
                    .foregroundStyle(canRun
                        ? (prominent ? Theme.onAccent.opacity(0.75) : Color.secondary)
                        : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            .background(
                RoundedRectangle(cornerRadius: controlRadius, style: .continuous)
                    .fill(canRun
                        ? (prominent ? Theme.accent : Theme.fill(0.08))
                        : Theme.fill(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
        .id(row)
        .padFocusRing(focused(row), radius: controlRadius)
    }

    // MARK: - результат

    private var resultPanel: some View {
        Panel(L("Последний отчёт")) {
            if report.isEmpty {
                Text(L("Прогонов ещё не было. Начните с основной проверки — она быстрая и отвечает на большинство вопросов."))
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Space.l) {
                    summary

                    ForEach(report.groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(L(group))
                                .font(TypeScale.label)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)

                            ForEach(report.rows.filter { $0.group == group }) { row in
                                resultRow(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: Space.l) {
            count(report.passed, L("прошло"), Theme.ok)
            count(report.failed, L("не прошло"),
                  report.failed > 0 ? Color.red : Color.secondary)
            count(report.skipped, L("пропущено"), Color.secondary)

            Spacer(minLength: 0)

            if let mp = report.multiplayer {
                Text(mp ? L("Мультиплеер") : L("Кампания"))
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
            }

            if !report.fresh {
                Text(L("с прошлого запуска"))
                    .font(TypeScale.caption)
                    .foregroundStyle(Theme.hint)
            }
        }
    }

    private func count(_ n: Int, _ label: String, _ colour: Color) -> some View {
        HStack(spacing: Space.xs) {
            Text("\(n)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(colour)
            Text(label)
                .font(TypeScale.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ row: TestRow) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: mark(row.verdict))
                .foregroundStyle(colour(row.verdict))
                .font(.callout)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(L(row.name))
                    .font(TypeScale.body)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(TypeScale.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func mark(_ v: TestVerdict) -> String {
        switch v {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .skip: return "minus.circle"
        }
    }

    private func colour(_ v: TestVerdict) -> Color {
        switch v {
        case .pass: return Theme.ok
        case .fail: return .red
        case .skip: return Theme.hint
        }
    }

    // MARK: - пад

    private func handle(_ key: PadKey, _ proxy: ScrollViewProxy) {
        guard pad.isActive(scope) else { return }

        switch key {
        case .up, .down:
            let next = cursor + (key == .down ? 1 : -1)
            guard next < rows.count else { onFooter(); return }
            cursor = max(next, 0)
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
        switch row {
        case .game:
            switch key {
            case .left:  multiplayer = false
            case .right: multiplayer = true
            default:     multiplayer.toggle()
            }
        case .basic:
            // Only the confirm button starts a run. Left and right walk a page
            // everywhere else in the launcher, and a thumb that slipped should
            // not cost two minutes.
            guard key == .confirm, canRun else { return }
            model.runSelfTest(full: false, multiplayer: multiplayer)
        case .full:
            guard key == .confirm, canRun else { return }
            model.runSelfTest(full: true, multiplayer: multiplayer)
        }
    }
}
