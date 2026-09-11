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
        "Покачивание камеры при ходьбе": "View bob while walking",
        "Размер прицела": "Crosshair size",
        "Диагностика": "Diagnostics",
        "Панель производительности": "Performance readout",
        "Запись производительности в perf.csv": "Log performance to perf.csv",
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
