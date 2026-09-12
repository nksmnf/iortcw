//  MultiplayerView.swift -- the tabs that only exist in the MP application.
//
//  Three screens: find a game, set up how you play, and run a server of your
//  own. They reuse the launcher's own Panel/Field/SliderRow vocabulary so this
//  half of the app looks like the other half rather than like a settings dump.
//
//  Pad navigation is deliberately not wired into these the way it is into the
//  campaign and graphics tabs. The server list is a live, reordering list and
//  the cursor model those tabs use is built around a fixed set of rows; the
//  tabs themselves are still reachable with L1/R1, and everything here works by
//  touch. It is the one place the two halves are not yet equal.

import SwiftUI

// MARK: - Серверы

struct ServersView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var mp: MultiplayerModel
    @StateObject private var browser = ServerBrowser()

    @State private var manualAddress = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Panel(L("Поиск игры")) {
                    HStack(spacing: Space.l) {
                        Button {
                            browser.refresh()
                        } label: {
                            Label(browser.isScanning ? L("Идёт опрос…") : L("Обновить список"),
                                  systemImage: "arrow.clockwise")
                        }
                        .disabled(browser.isScanning)

                        if browser.isScanning {
                            ProgressView()
                        }

                        Spacer()

                        Toggle(L("Только с игроками"), isOn: $browser.hideEmpty)
                            .fixedSize()
                    }

                    if !browser.status.isEmpty {
                        Text(browser.status)
                            .font(TypeScale.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !browser.servers.isEmpty {
                        Text(browser.summary)
                            .font(TypeScale.status)
                    }

                    Note(L("Список собирается напрямую с трёх живых мастер-серверов. Боты не считаются за игроков: на большинстве серверов их два-три десятка, и без этого пустой сервер выглядит полным."))
                }

                if !browser.visibleServers.isEmpty {
                    Panel(L("Найденные серверы")) {
                        ForEach(browser.visibleServers) { server in
                            ServerRow(server: server) {
                                model.connect(to: server.address)
                            }
                            if server.id != browser.visibleServers.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                Panel(L("Подключиться по адресу")) {
                    Field(note: L("Если вы знаете адрес сервера, его не обязательно искать в списке. Формат: 192.168.1.10:27960")) {
                        HStack(spacing: Space.l) {
                            TextField("1.2.3.4:27960", text: $manualAddress)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            Button(L("Подключиться")) {
                                model.connect(to: manualAddress)
                            }
                            .disabled(manualAddress.isEmpty || !model.canPlay)
                        }
                    }
                }

                if !model.canPlay {
                    Note(L("Игровые файлы ещё не на месте — подключиться не получится. Откройте вкладку «Данные»."))
                }
            }
            .padding(Space.xl)
        }
        .onAppear {
            if browser.servers.isEmpty && !browser.isScanning {
                browser.refresh()
            }
        }
    }
}

/// One server in the list.
private struct ServerRow: View {
    let server: GameServer
    let connect: () -> Void

    var body: some View {
        Button(action: connect) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(server.name.isEmpty ? server.address : server.name)
                        .font(TypeScale.row)
                        .foregroundStyle(server.refusesForeignClients ? .secondary : .primary)
                        .lineLimit(1)

                    HStack(spacing: Space.s) {
                        Text(server.mapName)
                            .font(TypeScale.monoSmall)
                        Text("·")
                        Text(server.family)
                            .font(TypeScale.caption)
                        if !server.mod.isEmpty && server.mod != "baseq3" {
                            Text("·")
                            Text(server.mod)
                                .font(TypeScale.caption)
                                .lineLimit(1)
                        }
                        if server.needsPassword {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                        }
                        if server.refusesForeignClients {
                            Text("·")
                            Text(L("нужен свой клиент"))
                                .font(TypeScale.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: Space.l)

                VStack(alignment: .trailing, spacing: Space.xs) {
                    Text(server.occupancy)
                        .font(TypeScale.row.monospacedDigit())
                        .foregroundStyle(server.isEmpty ? .secondary : .primary)
                    HStack(spacing: Space.xs) {
                        if server.bots > 0 {
                            Text(L("ботов") + " \(server.bots)")
                                .font(TypeScale.caption)
                        }
                        Text("\(server.pingMs) ms")
                            .font(TypeScale.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Настройки мультиплеера

struct MultiplayerSettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var mp: MultiplayerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Panel(L("Игрок")) {
                    Field(note: L("Имя, под которым вас видят на сервере.")) {
                        TextField(L("Имя"), text: $mp.playerName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Panel(L("Сеть")) {
                    Field(note: L("Пропускная способность канала. 25000 подходит для любого современного подключения; снижать имеет смысл только на очень плохой связи.")) {
                        SliderRow(title: L("Скорость (rate)"),
                                  value: Binding(
                                    get: { Double(mp.rate) },
                                    set: { mp.rate = Int($0) }),
                                  range: 5000...45000, step: 1000,
                                  readout: "\(mp.rate)")
                    }

                    SliderRow(title: L("Пакетов в секунду"),
                              value: Binding(
                                get: { Double(mp.maxPackets) },
                                set: { mp.maxPackets = Int($0) }),
                              range: 30...125, step: 5,
                              readout: "\(mp.maxPackets)")

                    Field(note: L("Сколько снимков состояния мира сервер шлёт вам в секунду. Больше значения, чем сервер отдаёт, получить нельзя.")) {
                        SliderRow(title: L("Снимков в секунду"),
                                  value: Binding(
                                    get: { Double(mp.snaps) },
                                    set: { mp.snaps = Int($0) }),
                                  range: 20...40, step: 1,
                                  readout: "\(mp.snaps)")
                    }

                    Field(note: L("Больше половины населённых серверов играют на нестандартных картах. Без докачки на них просто не зайти. Качается по UDP — медленно, но это единственный путь: curl в сборку для iOS не входит.")) {
                        Toggle(L("Докачивать карты с сервера"), isOn: $mp.allowDownload)
                    }
                }

                // No crosshair sliders here any more. They wrote cg_drawCrosshair
                // and cg_crosshairSize, which are one pair of cvars in one
                // generated config -- so multiplayer's copies were applied to
                // the campaign as well, and, being written after the Game tab's,
                // won over it. The size is on the Game tab, shared like every
                // other setting; the shape belongs to each game's own options
                // menu, which is why the launcher seeds it once and then stops
                // mentioning it (see migrate(from:) in LauncherModel).
                Panel(L("Экран боя")) {
                    Toggle(L("Счётчик кадров"), isOn: $mp.drawFPS)
                    Toggle(L("Лагометр"), isOn: $mp.lagometer)
                    Toggle(L("Кровь"), isOn: $mp.blood)
                    Toggle(L("Упрощённые предметы"), isOn: $mp.simpleItems)
                    Field(note: L("Перезаряжать автоматически, когда обойма опустела.")) {
                        Toggle(L("Автоперезарядка"), isOn: $mp.autoReload)
                    }
                }

                // No Diagnostics panel here. There used to be one, with its own
                // copies of the performance switches, and because both panels
                // wrote the same two cvars the one further down the commit won:
                // the panel on the Game tab could not turn the strip on at all.
                // One setting, one switch, one place.
                Note(L("Графика, прицел, чувствительность стиков, гироскоп, раскладка геймпада и диагностика — на вкладках «Графика», «Управление» и «Игра»: они общие с одиночной игрой."))
            }
            .padding(Space.xl)
        }
        .onDisappear { mp.save() }
    }
}

// MARK: - Свой сервер

struct HostView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var mp: MultiplayerModel

    @State private var showRotation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Panel(L("Сервер")) {
                    Field(note: L("Как сервер называется в списке.")) {
                        TextField(L("Название"), text: $mp.hostName)
                            .textFieldStyle(.roundedBorder)
                    }

                    Field(note: L(mp.visibility.detail)) {
                        ChoiceRow(title: L("Режим"), selection: $mp.visibility, focused: false) {
                            ForEach(ServerVisibility.allCases) { v in
                                Text(L(v.title)).tag(v)
                            }
                        }
                    }

                    if !mp.visibility.hasRenderer {
                        Note(L("В этом режиме движок ничего не рисует: экран планшета останется тёмным, пока сервер работает. Это нормально — сервер живёт в фоне."))
                    }

                    Field(note: L("Приложение продолжает работать, когда вы его свернули или погасили экран. Держите планшет на зарядке: процессор не засыпает, и батарея садится заметно быстрее.")) {
                        Toggle(L("Работать при скрытом приложении"), isOn: $mp.keepAwake)
                    }
                }

                Panel(L("Игра")) {
                    Field(note: L(mp.gameType.detail)) {
                        ChoiceRow(title: L("Режим игры"), selection: $mp.gameType, focused: false) {
                            ForEach(WolfGameType.allCases) { g in
                                Text(L(g.title)).tag(g)
                            }
                        }
                    }

                    Field(note: L("Карты по очереди. Первая запускается сразу.")) {
                        Button {
                            showRotation = true
                        } label: {
                            HStack {
                                Text(L("Ротация карт"))
                                Spacer()
                                Text(mp.mapRotation.isEmpty
                                     ? L("не задана")
                                     : "\(mp.mapRotation.count) " + L("карт"))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    SliderRow(title: L("Слотов"),
                              value: Binding(
                                get: { Double(mp.maxClients) },
                                set: { mp.maxClients = Int($0) }),
                              range: 2...32, step: 1,
                              readout: "\(mp.maxClients)")

                    Field(note: L("0 — без ограничения по времени.")) {
                        SliderRow(title: L("Лимит времени, мин"),
                                  value: Binding(
                                    get: { Double(mp.timeLimit) },
                                    set: { mp.timeLimit = Int($0) }),
                                  range: 0...60, step: 1,
                                  readout: mp.timeLimit == 0 ? L("нет") : "\(mp.timeLimit)")
                    }

                    Toggle(L("Огонь по своим"), isOn: $mp.friendlyFire)
                    Toggle(L("Уравнивать команды"), isOn: $mp.forceBalance)

                    Field(note: L("Разминка перед началом раунда.")) {
                        Toggle(L("Разминка"), isOn: $mp.doWarmup)
                    }

                    if mp.doWarmup {
                        SliderRow(title: L("Длительность разминки, с"),
                                  value: Binding(
                                    get: { Double(mp.warmupTime) },
                                    set: { mp.warmupTime = Int($0) }),
                                  range: 5...60, step: 5,
                                  readout: "\(mp.warmupTime)")
                    }

                    Field(note: L("0 — обычные бесконечные респауны.")) {
                        SliderRow(title: L("Жизней на раунд"),
                                  value: Binding(
                                    get: { Double(mp.maxLives) },
                                    set: { mp.maxLives = Int($0) }),
                                  range: 0...10, step: 1,
                                  readout: mp.maxLives == 0 ? L("без лимита") : "\(mp.maxLives)")
                    }
                }

                Panel(L("Доступ")) {
                    Field(note: L("Порт UDP. Если поднимаете несколько серверов или он уже занят — смените.")) {
                        SliderRow(title: L("Порт"),
                                  value: Binding(
                                    get: { Double(mp.netPort) },
                                    set: { mp.netPort = Int($0) }),
                                  range: 27950...27999, step: 1,
                                  readout: "\(mp.netPort)")
                    }

                    Field(note: L("Пусто — сервер открыт для всех.")) {
                        SecureField(L("Пароль на вход"), text: $mp.serverPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    Field(note: L("Пароль удалённого управления. Пустой — rcon выключен, и это правильное состояние, если вы им не пользуетесь.")) {
                        SecureField(L("Пароль rcon"), text: $mp.rconPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    Field(note: L("Сообщение, которое видят подключившиеся.")) {
                        TextField(L("Приветствие"), text: $mp.motd)
                            .textFieldStyle(.roundedBorder)
                    }

                    if mp.visibility.registersWithMasters {
                        Field(note: L("Сервер сообщает о себе мастер-серверам каждые пять минут. Без этого в общий список он не попадёт.")) {
                            Toggle(L("Регистрировать на мастер-серверах"), isOn: $mp.registerWithMasters)
                        }
                    }
                }

                Panel(L("Тонкая настройка")) {
                    Field(note: L("Требовать от клиентов те же файлы, что на сервере. Выключение открывает дорогу чит-пакам.")) {
                        Toggle(L("Проверка файлов (sv_pure)"), isOn: $mp.pureServer)
                    }

                    Toggle(L("Защита от флуда"), isOn: $mp.floodProtect)

                    SliderRow(title: L("Потолок скорости клиента"),
                              value: Binding(
                                get: { Double(mp.serverMaxRate) },
                                set: { mp.serverMaxRate = Int($0) }),
                              range: 5000...45000, step: 1000,
                              readout: "\(mp.serverMaxRate)")

                    Field(note: L("0 — не ограничивать. Отсекает игроков с пингом выше или ниже порога.")) {
                        SliderRow(title: L("Максимальный пинг"),
                                  value: Binding(
                                    get: { Double(mp.maxPing) },
                                    set: { mp.maxPing = Int($0) }),
                                  range: 0...500, step: 10,
                                  readout: mp.maxPing == 0 ? L("нет") : "\(mp.maxPing)")
                    }

                    SliderRow(title: L("Лимит жалоб"),
                              value: Binding(
                                get: { Double(mp.complaintLimit) },
                                set: { mp.complaintLimit = Int($0) }),
                              range: 0...10, step: 1,
                              readout: "\(mp.complaintLimit)")
                }

                Button {
                    model.startHosting()
                } label: {
                    Label(L("Запустить сервер"), systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canPlay)

                if !model.canPlay {
                    Note(L("Игровые файлы ещё не на месте. Откройте вкладку «Данные»."))
                }
            }
            .padding(Space.xl)
        }
        .sheet(isPresented: $showRotation) {
            RotationEditor(mp: mp)
        }
        .onDisappear { mp.save() }
    }
}

/// Picking which maps the server runs, and in what order.
private struct RotationEditor: View {
    @ObservedObject var mp: MultiplayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L("В ротации")) {
                    ForEach(mp.mapRotation, id: \.self) { map in
                        HStack {
                            Text(title(for: map))
                            Spacer()
                            Text(map)
                                .font(TypeScale.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { mp.mapRotation.remove(atOffsets: $0) }
                    .onMove { mp.mapRotation.move(fromOffsets: $0, toOffset: $1) }

                    if mp.mapRotation.isEmpty {
                        Text(L("Пусто — сервер запустится на первой карте из списка ниже."))
                            .font(TypeScale.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L("Карты игры")) {
                    ForEach(WolfMap.stock) { map in
                        Button {
                            if !mp.mapRotation.contains(map.id) {
                                mp.mapRotation.append(map.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(map.title)
                                    Text(map.id)
                                        .font(TypeScale.monoSmall)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if mp.mapRotation.contains(map.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L("Ротация карт"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Готово")) {
                        mp.startMap = mp.mapRotation.first ?? mp.startMap
                        mp.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func title(for id: String) -> String {
        WolfMap.stock.first { $0.id == id }?.title ?? id
    }
}
