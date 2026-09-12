import Foundation
import SwiftUI

/// Russian and English for the launcher.
///
/// The Russian text is the key, so a string that has no translation yet still
/// shows something sensible rather than a placeholder, and adding a string
/// costs nothing until someone gets round to translating it.
///
/// The choice is the player's, not the system's: someone running an English
/// iPad may still want the Russian, and the other way round.
enum Loc {
    private static let key = "IORTCWLanguage"

    enum Language: String, CaseIterable, Identifiable {
        case russian = "ru"
        case english = "en"

        var id: String { rawValue }
        var title: String { self == .russian ? "Русский" : "English" }
    }

    static var current: Language = {
        if let stored = UserDefaults.standard.string(forKey: key),
           let language = Language(rawValue: stored) {
            return stored == "en" ? .english : .russian
        }

        // Follow the device the first time, then remember what was chosen.
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? .russian : .english
    }()

    static func select(_ language: Language) {
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }

    /// Takes either the Russian text itself -- which is the key for short
    /// labels -- or one of the note.* keys used for the longer paragraphs,
    /// where a key in the layout reads better than a paragraph would.
    static func s(_ key: String) -> String {
        if let note = notes[key] {
            return current == .english ? note.en : note.ru
        }

        guard current == .english else { return key }
        return table[key] ?? key
    }

    private static let table: [String: String] = [
        // Tabs and chrome
        "Данные": "Data",
        "Кампания": "Campaign",
        "Играть": "Play",
        "Графика": "Graphics",
        "Управление": "Controls",
        "Нет контроллера": "No controller",
        "Готово": "Ready",
        "Нет игровых файлов": "Game data missing",
        // The line under the footer's status: what is going to load, or where
        // to go when there is nothing to load.
        "%ld карт · %.0f МБ": "%ld maps · %.0f MB",
        "Откройте вкладку «Данные»": "Open the Data tab",
        "Не хватает файлов: %ld": "%ld files missing",
        "Язык": "Language",

        // Data
        "Установка": "Installation",
        "Игровые файлы кампании": "Campaign game files",
        "Игровые файлы мультиплеера": "Multiplayer game files",
        "Все игровые файлы найдены.": "All game files found.",
        "Набор неполный, но играть можно.": "Incomplete, but playable.",
        "Набор неполный.": "The set is incomplete.",
        "Полный официальный набор": "Complete official set",
        "%ld карт · %ld файлов · %.0f МБ распакованных данных":
            "%ld maps · %ld files · %.0f MB uncompressed",
        "iORTCW для iPadOS": "iORTCW for iPadOS",
        "Скопируйте данные Return to Castle Wolfenstein":
            "Copy in your Return to Castle Wolfenstein data",
        "обязателен": "required",
        "Папка": "Folder",
        "Сборка": "Build",

        // Campaign
        "Сложность": "Difficulty",
        "Не делай мне больно": "Don't hurt me",
        "Не так уж и плохо": "Bring 'em on",
        "Смерть во плоти": "Death incarnate",
        "Миссии": "Missions",
        "карт": "maps",
        "МБ": "MB",

        // The campaigns. The retail one, and the ten fan campaigns of the
        // Russian anthology -- their English names are the ones their authors
        // released them under, not translations of the Russian.
        "Оригинальная кампания": "Original campaign",
        "Врата времени": "Time Gate",
        "Сталинград": "Stalingrad",
        "Диверсант": "Saboteur",
        "Призраки войны": "Ghosts of War",
        "Красная тревога": "Red Alert",
        "Спецназ": "Special Forces",
        "Проект 51": "Project 51",
        "Проклятие фараона": "Pharaoh's Curse",
        "Ставка больше, чем жизнь": "The Rate Is More Than Life",
        "Проект X (демо)": "Project X (demo)",

        // Mission names a campaign gives its own maps.
        "Прибрежная полоса": "The coastal strip",
        "Морская крепость": "Sea fortress",
        "Техническая часть базы": "Base technical section",
        "Инженерный бункер": "Engineering bunker",

        // Graphics
        "Качество": "Quality",
        "Пресет": "Preset",
        "Экран": "Display",
        "Кадры/с": "Frame rate",
        "Полное разрешение": "Full resolution",
        "Рендер в родных 2752×2064.": "Rendered at the panel's own 2752×2064.",
        "Половинное разрешение: мягче картинка, дольше батарея.":
            "Half resolution: softer image, longer battery.",
        "Изображение": "Image",
        "Поле зрения": "Field of view",
        "Яркость": "Brightness",
        "Аппаратной гаммы на iOS нет, поэтому яркость запекается в текстуры и применяется при следующем запуске.":
            "iOS has no hardware gamma, so brightness is baked into the textures and takes effect on the next start.",
        "Максимум": "Maximum",
        "Баланс": "Balanced",
        "Экономия": "Battery",
        "Полное разрешение, анизотропная фильтрация, динамический свет и тени.":
            "Full resolution, anisotropic filtering, dynamic lights and shadows.",
        "То же, но без стенсильных теней — самой дорогой настройки на таком разрешении.":
            "The same without stencil shadows, which cost the most at this resolution.",
        "Половинное разрешение и упрощённые эффекты. Заметно дольше от батареи.":
            "Half resolution and simpler effects. Noticeably longer on battery.",

        // Controls
        "Стики": "Sticks",
        "Движение по 8 направлениям": "Eight-way movement",
        "Левый стик работает как WASD: северо-восток — это вперёд и вправо. Предсказуемо и без сноса.":
            "The left stick behaves like WASD: north-east is forward and right. Predictable, and it does not drift.",
        "Плавное аналоговое движение.": "Smooth analogue movement.",
        "Скорость поворота": "Turn speed",
        "Вертикаль": "Vertical",
        "Мёртвая зона": "Dead zone",
        "Инверсия вертикали": "Invert vertical",
        "Вибрация": "Vibration",
        "Отдача при попадании": "Impact feedback on hits",
        "Сила отдачи": "Impact strength",
        // Degrees per second. The unit letter is a word, so it is translated
        // like one -- it was being built into the readout in code and stayed
        // Cyrillic on an English launcher.
        "%ld°/с": "%ld°/s",
        "Адаптивные триггеры": "Adaptive triggers",
        "Чувствительность гироскопа": "Gyro sensitivity",
        "Гироскоп": "Gyro",
        "Инверсия гироскопа по горизонтали": "Invert gyro horizontally",
        "Инверсия гироскопа по вертикали": "Invert gyro vertically",
        "Горизонталь гироскопа": "Gyro horizontal from",
        "Раздельно по осям": "Separate axes",
        "Чувствительность по горизонтали": "Horizontal sensitivity",
        "Чувствительность по вертикали": "Vertical sensitivity",
        "Разворот": "Yaw",
        "Крен": "Roll",
        "Оба": "Both",
        "Только гироскоп контроллера — у планшета свои переключатели.":
            "The controller's gyro only -- the iPad has switches of its own.",
        "Выкл": "Off",
        "Всегда": "Always",
        "В прицеле": "While aiming",
        "Экранные кнопки": "On-screen controls",
        "Показывать": "Show",
        "Автоматически": "Automatic",
        "Никогда": "Never",
        "Чувствительность обзора": "Look sensitivity",
        "Насколько поворачивается вид за движение пальца по правой половине экрана.":
            "How far the view turns for a given finger movement on the right half of the screen.",
        "Гироскоп планшета": "iPad gyro",
        "Обзор пальцем": "Finger look",
        "Режим": "Mode",
        "Без контроллера": "Without a controller",
        "Инверсия по горизонтали": "Invert horizontally",
        "Инверсия по вертикали": "Invert vertically",
        "Звук": "Sound",
        "Громкость": "Volume",
        "Музыка": "Music",
        "Игра": "Game",
        "Переключаться на подобранное оружие": "Switch to picked-up weapons",
        "Только новое": "Only new",
        "Новое или лучше": "New or better",
        "Подбирать предметы на ходу": "Pick things up by walking over them",
        "Менять оружие, когда кончились патроны": "Switch weapon when out of ammo",
        "Покачивание камеры при ходьбе": "View bob while walking",
        "Размер прицела": "Crosshair size",
        "Диагностика": "Diagnostics",
        "Панель производительности": "Performance readout",
        "Запись производительности в perf.csv": "Log performance to perf.csv",
        "Подробный лог движка": "Verbose engine log",
        "Запись событий контроллера в лог": "Log controller events",
        "Раскладка": "Layout",
        "Проверка контроллера…": "Controller test…",
        "Настроить кнопки…": "Assign buttons…",
        "Сбросить к стандартной": "Reset to default",
        "Кнопки контроллера": "Controller buttons",
        "Не назначено": "Unassigned",

        // Pad navigation. The button names are the ones printed on a DualSense,
        // so they stay as they are in both languages.
        "Options — начать игру": "Options starts the game",
        "Держите Circle, чтобы закрыть": "Hold Circle to close",

        // Actions
        "Огонь": "Fire",
        "Бой": "Combat",
        "Альт. огонь": "Alt fire",
        "Прицел": "Aim",
        "Кратность +": "Zoom in",
        "Кратность −": "Zoom out",
        "Перезарядка": "Reload",
        "Следующее оружие": "Next weapon",
        "Предыдущее оружие": "Previous weapon",
        "Быстрая граната": "Quick grenade",
        "Режим оружия": "Weapon mode",
        "Прыжок": "Jump",
        "Движение": "Movement",
        "Присесть": "Crouch",
        "Спринт": "Sprint",
        "Шагом": "Walk",
        "Наклон влево": "Lean left",
        "Наклон вправо": "Lean right",
        "Использовать": "Use",
        "Действия": "Actions",
        "Применить предмет": "Use item",
        "Следующий предмет": "Next item",
        "Удар ногой": "Kick",
        "Журнал": "Notebook",
        "Быстрое сохранение": "Quick save",
        "Система": "System",
        "Быстрая загрузка": "Quick load",
        "Меню": "Menu",

        // Missions
        "1. Побег": "1. Escape",
        "2. Замок Вольфенштайн": "2. Castle Wolfenstein",
        "3. Фуникулёр": "3. Tram",
        "4. Деревня": "4. Village",
        "5. Склеп": "5. Crypt",
        "6. Гробница": "6. Tomb",
        "7. Церковь": "7. Church",
        "8. Хайнрих": "8. Heinrich",
        "9. Лес": "9. Forest",
        "10. Плотина": "10. Dam",
        "11. Деревня II": "11. Village II",
        "12. Шато": "12. Chateau",
        "13. Тёмная база": "13. Dark base",
        "14. Депо": "14. Trainyard",
        "15. Секретный завод": "15. Secret facility",
        "16. Завод": "16. Factory",
        "17. Оружейный цех": "17. Weapons plant",
        "18. Штурм": "18. Assault",
        "19. X-Лаборатории": "19. X-Labs",
        "20. Раскопки": "20. Dig",
        "21. Норвегия": "21. Norway",
        "22. Ракетная база": "22. Rocket base",
        "23. Побег с базы": "23. Base escape",
        "24. Замок": "24. Castle",
        "25. Пробуждение": "25. Awakening",
        "26. Финал": "26. End",



        "Мультиплеер": "Multiplayer",
        "Бросить оружие": "Drop weapon",
        "Помощь (MP)": "Help (MP)",
        "Таблица очков": "Scoreboard",
        "Написать всем": "Say to all",
        "Написать команде": "Say to team",
        // --- проверка ---
        "Проверка": "Testing",
        "Что проверять": "What to test",
        "Прогон": "Run",
        "Основная проверка": "Basic run",
        "Полная проверка": "Full run",
        "Последний отчёт": "Last report",
        "прошло": "passed",
        "не прошло": "failed",
        "пропущено": "skipped",
        "с прошлого запуска": "from an earlier session",
        "Две половины игры — это два независимых движка в одном приложении, и проверяются они порознь. Настройки у них общие, поэтому расхождение между ними чаще всего и оказывается ошибкой.": "The two halves of the game are two independent engines in one application, and they are tested separately. Their settings are shared, which is why a disagreement between them is usually the bug.",
        "Файлы этой половины игры не найдены — проверять нечего.": "The files for this half of the game are missing -- there is nothing to test.",
        "Около десяти секунд. Спрашивает движок, дошли ли до него настройки лаунчера, существуют ли команды, которые он назначает на клавиши, знает ли он имена этих клавиш, то ли разрешение на экране и на месте ли файлы игры.": "About ten seconds. Asks the engine whether the launcher's settings reached it, whether the commands it binds to keys exist, whether it knows the names of those keys, whether the screen is at the right size and whether the game files are there.",
        "Две-три минуты. Всё то же самое, а затем игра сама загрузит карту, прогонит таблицу стиков и гироскопа из двадцати одной строки и замерит частоту кадров. Экран будет жить своей жизнью — так и должно быть.": "Two to three minutes. All of the above, and then the game loads a map by itself, runs the twenty-one row stick and gyro table and measures the frame rate. The screen will move on its own; that is what it is supposed to do.",
        "Игра запустится, прогон пройдёт сам, лаунчер вернётся сюда с результатом. Отчёт остаётся в Documents/main/selftest.txt.": "The game starts, the run performs itself, and the launcher comes back here with the result. The report is kept in Documents/main/selftest.txt.",
        "Прогонов ещё не было. Начните с основной проверки — она быстрая и отвечает на большинство вопросов.": "No run yet. Start with the basic one: it is quick and answers most of the questions.",
        "Настройки": "Settings",
        "Команды": "Commands",
        "Привязки": "Bindings",
        "настройки лаунчера": "launcher settings",
        "привязки клавиш": "key bindings",
        "обязательные команды": "required commands",
        "имена клавиш геймпада": "gamepad key names",
        "оси гироскопа": "gyro axes",
        "гироскоп поворачивает обзор": "gyro turns the view",
        "файл лаунчера": "launcher file",
        "разрешение": "resolution",
        "частота кадров": "frame rate",
        "мастер-серверы": "master servers",
        "загрузка карты": "map load",
        "таблица стиков и гироскопа": "stick and gyro table",
        // --- консоль сервера ---
        "Работает": "Running",
        "Запускается…": "Starting\u{2026}",
        "порт": "port",
        "Ждём вывод сервера…": "Waiting for server output\u{2026}",
        "Команда консоли": "Console command",
        "Выполнить": "Run",
        "Кто на сервере": "Who is on",
        "Следующая карта": "Next map",
        "Перезапустить карту": "Restart map",
        "Остановить": "Stop",
        // --- Мультиплеер: вкладки и экраны ---
        // "Мультиплеер" itself is up with the campaign's action names, which is
        // where it was first needed.
        "Серверы": "Servers",
        "Свой сервер": "Host",

        // Поиск игры
        "Поиск игры": "Find a game",
        "Обновить список": "Refresh list",
        "Идёт опрос…": "Scanning\u{2026}",
        "Только с игроками": "Occupied only",
        "Найденные серверы": "Servers found",
        "Подключиться": "Connect",
        "Подключиться по адресу": "Connect by address",
        "ботов": "bots",
        "нужен свой клиент": "needs its own client",
        "Список собирается напрямую с трёх живых мастер-серверов. Боты не считаются за игроков: на большинстве серверов их два-три десятка, и без этого пустой сервер выглядит полным.":
            "The list is gathered straight from the three masters that still answer. Bots are not counted as players: most servers run twenty or thirty, and without that an empty server looks full.",
        "Если вы знаете адрес сервера, его не обязательно искать в списке. Формат: 192.168.1.10:27960":
            "If you know the address you do not need the list. Format: 192.168.1.10:27960",
        "Игровые файлы ещё не на месте — подключиться не получится. Откройте вкладку «Данные».":
            "The game data is not in place yet, so joining will not work. See the Data tab.",
        "Игровые файлы ещё не на месте. Откройте вкладку «Данные».":
            "The game data is not in place yet. See the Data tab.",

        // Настройки клиента
        "Игрок": "Player",
        "Имя": "Name",
        "Имя, под которым вас видят на сервере.": "The name other players see.",
        "Сеть": "Network",
        "Скорость (rate)": "Rate",
        "Пакетов в секунду": "Packets per second",
        "Снимков в секунду": "Snapshots per second",
        "Докачивать карты с сервера": "Download maps from the server",
        "Экран боя": "Heads-up display",
        "Счётчик кадров": "Frame counter",
        "Лагометр": "Lagometer",
        "Кровь": "Blood",
        "Упрощённые предметы": "Simple items",
        "Автоперезарядка": "Auto-reload",
        "нет": "off",
        "Пропускная способность канала. 25000 подходит для любого современного подключения; снижать имеет смысл только на очень плохой связи.":
            "Channel bandwidth. 25000 suits any modern connection; lowering it only helps on a genuinely bad line.",
        "Сколько снимков состояния мира сервер шлёт вам в секунду. Больше значения, чем сервер отдаёт, получить нельзя.":
            "How many world snapshots the server sends you per second. You cannot receive more than it sends.",
        "Больше половины населённых серверов играют на нестандартных картах. Без докачки на них просто не зайти. Качается по UDP — медленно, но это единственный путь: curl в сборку для iOS не входит.":
            "Over half the populated servers run custom maps, and without downloads you simply cannot join them. It goes over UDP -- slow, but it is the only route: curl is not built for iOS.",
        "Перезаряжать автоматически, когда обойма опустела.": "Reload automatically when the magazine runs dry.",
        "Графика, прицел, чувствительность стиков, гироскоп, раскладка геймпада и диагностика — на вкладках «Графика», «Управление» и «Игра»: они общие с одиночной игрой.":
            "Graphics, the crosshair, stick feel, gyro, the pad layout and diagnostics are on the Graphics, Controls and Game tabs: they are shared with the campaign.",

        // Хостинг
        "Сервер": "Server",
        "Название": "Title",
        "Как сервер называется в списке.": "How the server is named in the list.",
        "Играю сам": "I play",
        "Локальный": "LAN",
        "Интернет": "Internet",
        "Работать при скрытом приложении": "Keep running when hidden",
        "Режим игры": "Game type",
        "Задание": "Objective",
        "Секундомер": "Stopwatch",
        "Контрольные точки": "Checkpoint",
        "Захват и удержание": "Capture and hold",
        "Ротация карт": "Map rotation",
        "Карты игры": "Stock maps",
        "В ротации": "In rotation",
        "не задана": "not set",
        "Слотов": "Slots",
        "Лимит времени, мин": "Time limit, min",
        "Огонь по своим": "Friendly fire",
        "Уравнивать команды": "Force team balance",
        "Разминка": "Warmup",
        "Длительность разминки, с": "Warmup length, s",
        "Жизней на раунд": "Lives per round",
        "без лимита": "unlimited",
        "Доступ": "Access",
        "Порт": "Port",
        "Пароль на вход": "Join password",
        "Пароль rcon": "rcon password",
        "Приветствие": "Message of the day",
        "Регистрировать на мастер-серверах": "Register with the masters",
        "Тонкая настройка": "Fine tuning",
        "Проверка файлов (sv_pure)": "File check (sv_pure)",
        "Защита от флуда": "Flood protection",
        "Потолок скорости клиента": "Client rate ceiling",
        "Максимальный пинг": "Maximum ping",
        "Лимит жалоб": "Complaint limit",
        "Запустить сервер": "Start server",
        "Карты по очереди. Первая запускается сразу.": "Maps in order. The first one starts immediately.",
        "0 — без ограничения по времени.": "0 means no time limit.",
        "0 — обычные бесконечные респауны.": "0 is the usual unlimited respawns.",
        "0 — не ограничивать. Отсекает игроков с пингом выше или ниже порога.":
            "0 means no limit. Rejects players whose ping is outside the threshold.",
        "Разминка перед началом раунда.": "A warmup period before the round begins.",
        "Порт UDP. Если поднимаете несколько серверов или он уже занят — смените.":
            "The UDP port. Change it if you run more than one server or it is already taken.",
        "Пусто — сервер открыт для всех.": "Empty means the server is open to everyone.",
        "Пароль удалённого управления. Пустой — rcon выключен, и это правильное состояние, если вы им не пользуетесь.":
            "The remote-control password. Empty disables rcon, which is the right state if you do not use it.",
        "Сообщение, которое видят подключившиеся.": "Shown to players as they join.",
        "Сервер сообщает о себе мастер-серверам каждые пять минут. Без этого в общий список он не попадёт.":
            "The server reports to the masters every five minutes. Without it, it never reaches the public list.",
        "Требовать от клиентов те же файлы, что на сервере. Выключение открывает дорогу чит-пакам.":
            "Require clients to load the same files as the server. Turning it off opens the door to cheat paks.",
        "Приложение продолжает работать, когда вы его свернули или погасили экран. Держите планшет на зарядке: процессор не засыпает, и батарея садится заметно быстрее.":
            "The app keeps running when you put it away or the screen goes off. Keep the tablet plugged in: the CPU never sleeps and the battery drains noticeably faster.",
        "В этом режиме движок ничего не рисует: экран планшета останется тёмным, пока сервер работает. Это нормально — сервер живёт в фоне.":
            "In this mode the engine draws nothing: the tablet stays dark while the server runs. That is expected -- the server lives in the background.",
        "Пусто — сервер запустится на первой карте из списка ниже.":
            "Empty means the server starts on the first map from the list below.",
        "Вы играете на своём же сервере, картинка на планшете. Другие игроки находят вас только в локальной сети.":
            "You play on your own server and the tablet shows the game. Others can only find you on the local network.",
        "Чистый сервер без игрока: планшет ничего не рисует, экран будет тёмным. Виден только в локальной сети.":
            "A plain server with no player attached: nothing is drawn and the screen stays dark. Visible on the local network only.",
        "Сервер регистрируется на мастер-серверах и виден всем. Картинки нет. Нужен проброс UDP-порта на роутере — через мобильный интернет входящие соединения не проходят.":
            "The server registers with the masters and is visible to everyone. Nothing is drawn. You need a UDP port forward on your router -- incoming connections never arrive over mobile data.",
        "Штатный режим RTCW: одна команда выполняет задачу, другая защищает. Так играет почти вся сеть.":
            "The standard RTCW mode: one team completes an objective, the other defends. Nearly the whole network plays this.",
        "То же задание, но команды меняются местами и соревнуются, кто быстрее.":
            "The same objective, but the teams swap and race each other's time.",
        "Команды удерживают флаги-контрольные точки на карте.":
            "Teams hold flag checkpoints across the map.",
        "Очки начисляются за время удержания точек.":
            "Points accrue for time spent holding the points.",

    ]

    /// The paragraphs, both languages together.
    private static let notes: [String: (ru: String, en: String)] = [
        "note.data": (
            ru: """
                Нужны файлы .pk3 из вашей копии игры — они лежат в папке Main \
                установленной RTCW (GOG или Steam).

                С Mac: подключите iPad, откройте его в Finder, вкладка «Файлы», \
                и перетащите файлы .pk3 (или всю папку Main) на iORTCW. Finder \
                кладёт их только в корень — это нормально, приложение само \
                перенесёт их в main/.

                На самом iPad: Файлы → На iPad → iORTCW.

                Список обновляется по мере копирования. Большие файлы идут \
                несколько минут.
                """,
            en: """
                The .pk3 files from your own copy of the game, out of the Main \
                folder of an installed RTCW (GOG or Steam).

                From a Mac: connect the iPad, open it in Finder, go to Files \
                and drag the .pk3 files (or the whole Main folder) onto iORTCW. \
                Finder will only drop them at the top level, which is fine -- \
                the app moves them into main/ itself.

                On the iPad: Files -> On My iPad -> iORTCW.

                The list updates as they copy. The large ones take a few minutes.
                """),

        "note.mpdata.mp": (
            ru: """
                Это мультиплеерная сборка: нужны pak0.pk3 и mp_pak0..mp_pak5. \
                Паки mp_pakmaps* необязательны — это официальные бонусные карты, \
                без них можно играть, но не на всех серверах.
                """,
            en: """
                This is the multiplayer build: it needs pak0.pk3 and \
                mp_pak0..mp_pak5. The mp_pakmaps* paks are optional -- official \
                bonus maps, playable without them but not on every server.
                """),

        "note.mpdata": (
            ru: """
                Мультиплеер в этой сборке не поддерживается: собран только \
                одиночный код. Файлы показаны, чтобы было видно, что лежит на \
                диске.
                """,
            en: """
                Multiplayer is not supported in this build -- only the single \
                player code is compiled. The files are listed so that it is \
                clear what is on the device.
                """),

        "note.campaign": (
            ru: """
                Запуск отсюда идёт мимо меню игры: оно рассчитано на мышь, и \
                попадать в его пункты пальцем неудобно.

                Миссия начинается с набором снаряжения, который к этому месту \
                кампании уже был бы у игрока — иначе выход был бы с пустыми \
                руками.
                """,
            en: """
                Starting here goes past the game's own menus: they were built \
                for a mouse, and hitting their entries with a finger is awkward.

                The mission begins with the kit the player would already have \
                by that point in the campaign -- otherwise they would arrive \
                empty handed.
                """),

        "note.touch": (
            ru: """
                Автоматически: показаны, пока не используется контроллер; \
                возвращаются при касании экрана и уходят через пять секунд без \
                него.
                """,
            en: """
                Automatic: shown until a controller is in use; back on a touch, \
                and gone again five seconds after the screen is left alone.
                """),

        "note.gyroyaw": (
            ru: """
                Разворот — это поворот пада плашмя, как руля, лежащего на \
                столе. Крен — наклон вправо-влево вокруг оси, идущей через \
                кнопку PS. Крен обычно точнее: его делают запястья, а разворот \
                идёт от всей руки. «Оба» складывает их и работает при любом \
                хвате.
                """,
            en: """
                Yaw is the pad turning flat, like a wheel lying on a table. \
                Roll is tipping it left and right, around the line through the \
                PS button. Roll is usually the finer of the two: the wrists do \
                it, where yaw comes from the whole arm. Both adds them \
                together and works whichever way the pad is held.
                """),

        "note.gyro": (
            ru: """
                Доводка прицела наклоном планшета, поверх пальца. «Без \
                контроллера» — прежнее поведение: с подключённым падом работает \
                его гироскоп, а этот молчит. «Всегда» держит включёнными оба, и \
                их вклад складывается.
                """,
            en: """
                Fine aim by tilting the iPad, on top of the finger. "Without a \
                controller" is what it always did: with a pad connected its gyro \
                takes over and this one stays quiet. "Always" keeps both running \
                and adds what each of them asks for.
                """),

        "note.pickup": (
            ru: """
                Оружие с земли подбирается в любом случае — выбор лишь в том, \
                брать ли его сразу в руки. «Только новое» — правило самой \
                игры: в руках остаётся то, чем вы стреляли, пока не попадётся \
                то, чего у вас ещё нет. «Всегда» — правило Quake III: любой \
                подобранный ствол, даже второй такой же, вытесняет текущий, и \
                с набором оружия от лаунчера это происходит на каждом шагу.
                """,
            en: """
                A weapon on the ground is picked up either way; this only \
                decides whether it goes straight into your hands. "Only new" is \
                the game's own rule: what you were firing stays up until \
                something you do not already carry turns up. "Always" is Quake \
                III's -- any gun picked up, a duplicate included, takes over, \
                which with the launcher's loadout happens constantly.
                """),

        "note.perfHud": (
            ru: """
                Полоска поверх игры: кадры в секунду, время кадра, частота \
                экрана, процессор, память и счётчики рендера.
                """,
            en: """
                A strip over the game: frames per second, frame time, screen \
                refresh, CPU, memory and the renderer's counters.
                """),

        "note.perfLog": (
            ru: """
                Те же замеры в main/perf.csv, по строке на полсекунды — по ним \
                видно, где именно просело.
                """,
            en: """
                The same measurements in main/perf.csv, a row every half \
                second, which is what shows where it actually dropped.
                """),

        "note.verboseLog": (
            ru: """
                Собственный рассказ движка в main/rtcwconsole.log — включая то, \
                почему сервер выпал из списка. Пишется построчно, поэтому \
                переживает вылет.
                """,
            en: """
                The engine's own running commentary in main/rtcwconsole.log, \
                including why a server was dropped from the browser. Written \
                line by line, so it survives a crash.
                """),

        "note.diag": (
            ru: """
                Файлы лежат в папке main и доступны через приложение Файлы. \
                Запись стоит включать только когда нужно разобраться с \
                проблемой — она идёт постоянно.
                """,
            en: """
                The files live in the main folder and are reachable through \
                Files. Worth turning on only to look into a problem: it writes \
                constantly.
                """),

        "note.haptics": (
            ru: """
                Вибрация только при получении урона, и её длительность \
                показывает, сколько сняли: царапина — короткий тик, тяжёлое \
                попадание тянется заметно дольше. При стрельбе контроллер \
                молчит — иначе он гудит постоянно и не сообщает ничего нового.
                """,
            en: """
                The controller vibrates only when you are hit, and the length \
                says how hard: a graze is a short tick, a heavy hit lasts \
                noticeably longer. It stays quiet while firing -- otherwise it \
                hums continuously and tells you nothing new.
                """),

        "note.impactscale": (
            ru: """
                Насколько сильным делать этот толчок. Множитель действует \
                только на попадания по врагу — вибрация от полученного урона \
                остаётся какой была, поэтому предупреждение о том, что бьют \
                вас, не глохнет вместе с отдачей.
                """,
            en: """
                How hard that kick should be. The multiplier applies to hits on \
                an enemy only -- the vibration for damage taken keeps its own \
                strength, so turning the recoil down does not quieten the \
                warning that something is hitting you.
                """),
        "note.impact": (
            ru: """
                Короткий толчок, когда попадание приходится по врагу. Это \
                отдельная вещь от вибрации при получении урона: та сообщает, \
                что происходит с игроком, а эта даёт оружию отдачу, чтобы удар \
                чувствовался, а не только звучал.
                """,
            en: """
                A short kick when a shot lands on an enemy. It is a separate \
                thing from the vibration for damage taken: that one tells the \
                player what is happening to them, this one gives the weapon \
                something to push back with, so a hit is felt and not only \
                heard.
                """),

        "note.menu": (
            ru: """
                Кнопка MENU в углу открывает меню игры — там сохранение, \
                загрузка и выход. Три пальца делают то же самое, четыре — \
                консоль; и то и другое работает всегда. Тап пропускает заставку.
                """,
            en: """
                The MENU button in the corner opens the game's menu, where \
                saving, loading and quitting are. Three fingers do the same and \
                four open the console; both work at any time. A tap skips a \
                cutscene.
                """),

        "note.layout": (
            ru: """
                По умолчанию: R2 — огонь, L2 — прицел, R1 — прыжок, L1 — \
                присесть, Круг — следующее оружие, Крест — предыдущее, Квадрат — \
                перезарядка, Треугольник — использовать, L3 — удар ногой, R3 — \
                спринт. Крестовина ходит, как стрелки на клавиатуре. Свайпы по \
                тачпаду: вверх-вниз — кратность прицела, влево-вправо — оружие, \
                тап — предмет.
                """,
            en: """
                By default: R2 fire, L2 aim, R1 jump, L1 crouch, Circle next \
                weapon, Cross previous weapon, Square reload, Triangle use, L3 \
                kick, R3 sprint. The D-pad walks, like the arrow keys. Touchpad \
                swipes: up and down change scope magnification, left and right \
                change weapon, a tap selects the next item.
                """),
    ]
}

/// Short name, because it appears on nearly every line of the interface.
func L(_ key: String) -> String { Loc.s(key) }
