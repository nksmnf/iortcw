# Сеть RTCW сегодня: мастер-серверы, живые цифры и свой сервер

Документ отвечает на три вопроса: какие мастер-серверы Return to Castle
Wolfenstein ещё живы, сколько людей и серверов реально в сети, и как поднять
собственный выделенный сервер на движке из этого репозитория.

Все цифры в разделе 3 получены прямыми UDP-запросами к мастерам и к каждому
найденному серверу — не из чужих трекеров. Скрипты для повторения замера лежат
в приложении (раздел 6), их можно запустить в любой момент и получить свежий
срез.

Ссылки на код даны относительно корня репозитория; если не указано иное, речь
про дерево `MP/` — мультиплеер живёт там.

---

## 1. Коротко

**Мастер-серверы живы, их три.** Официальный `wolfmaster.idsoftware.com` не
умер: он резолвится в 20.25.21.175 и отвечает на запросы — именно он держит
самый полный список. Рядом работают `dpmaster.deathmask.net` и
`master.iortcw.org`.

**Сеть маленькая, но не мёртвая.** На момент замеров (11 сентября 2026, 18:00–18:15 UTC)
мастера отдавали 41–44 адреса, из них **25 серверов реально ответили**, на них
**44–52 живых человека** и **~415 ботов**. Людьми заняты 9–13 серверов из 25,
остальные крутят Omni-Bot в пустую.

**iortcw — самый заметный движок в этой сети.** 9 из 25 живых серверов работают
на iortcw, и самый населённый сервер сети (24 человека, `The Boring Server`) —
тоже iortcw 1.51c. Остальные делятся поровну между ванильной 1.4/1.41 и
соревновательной веткой 1.0/1.1.

**Свой сервер поднимается одной командой сборки и одним конфигом.** Нужны
`iowolfded`, файлы игры из `main/` и `dedicated 2` — без последнего сервер в
мастере не появится (`MP/code/server/sv_main.c:259`).

**Главная ловушка:** протокол 61 (родной для iortcw) в мастерах **пуст** —
ноль серверов. Все публичные серверы регистрируются под протоколом 60, потому
что iortcw по умолчанию работает в legacy-режиме. Подробности в разделе 5.1.

---

## 2. Мастер-серверы

### 2.1 Что зашито в код

Движок хранит до пяти адресов мастеров — `MAX_MASTER_SERVERS` равен 5
(`MP/code/qcommon/q_shared.h:106`). Первые два прописаны в коде, остальные три
пустые и настраиваются игроком:

```c
// MP/code/server/sv_init.c:905
sv_master[0] = Cvar_Get("sv_master1", MASTER_SERVER_NAME, 0);
sv_master[1] = Cvar_Get("sv_master2", "master.iortcw.org", 0);
for (index = 2; index < MAX_MASTER_SERVERS; index++)
        sv_master[index] = Cvar_Get(va("sv_master%d", index + 1), "", CVAR_ARCHIVE);
```

`MASTER_SERVER_NAME` — официальный мастер id Software
(`MP/code/qcommon/qcommon.h:304`):

```c
#ifndef MASTER_SERVER_NAME
#define MASTER_SERVER_NAME		"wolfmaster.idsoftware.com"	// Official master server
//#define MASTER_SERVER_NAME		"dpmaster.deathmask.net"
#endif
```

Стандартный порт мастера — 27950, `PORT_MASTER` в
`MP/code/qcommon/qcommon.h:337`. Если в `sv_master*` порт не указан, движок
подставляет его сам (`MP/code/server/sv_main.c:298`).

В дереве `SP/` мастера другие и **мертвы**: `master.gmistudios.com` и
`update.gmistudios.com` (`SP/code/qcommon/qcommon.h:293` и `:289`) сегодня даже не
резолвятся. Для одиночной кампании это неважно — сетевой игры там нет. Обратите
внимание, что в `SP/code/server/sv_init.c:1044` строки с мастерами закомментированы
целиком, а `sv_master1..5` по умолчанию пустые.

Сервер обновлений `wolfmotd.idsoftware.com` (`MP/code/qcommon/qcommon.h:300`)
тоже не резолвится — авто-обновление и MOTD от id больше не работают.

### 2.2 Что живо на самом деле

Проверка 11 сентября 2026, 18:00 UTC (UDP-запрос `getservers` на порт 27950):

| Мастер | IP | Отвечает | Серверов в списке | В коде |
|---|---|---|---|---|
| `wolfmaster.idsoftware.com` | 20.25.21.175 | да | **25–26** (самый полный) | `sv_master1` по умолчанию |
| `dpmaster.deathmask.net` | 107.161.23.68 | да | 22–23 | закомментирован |
| `master.iortcw.org` | 104.194.9.163 | да | 6 | `sv_master2` по умолчанию |
| `master.rtcw.eu` | 188.114.97.0 | нет | — | — |
| `master.wolffiles.de` | 138.201.136.212 | нет | — | — |
| `master.rtcwmp.com` | 5.252.102.102 | нет (на 27950 молчит) | — | — |
| `master.gmistudios.com` | не резолвится | — | — | `SP/`, мёртв |
| `wolfmotd.idsoftware.com` | не резолвится | — | — | сервер обновлений, мёртв |

Проверялись также мастера соседних игр (`master.quake3arena.com`,
`master.ioquake3.org`, `dpmaster.tchr.no`, `master0.excessiveplus.net`,
`master.maverickservers.com`) — они живы, но RTCW-серверов не отдают.

Три живых мастера **частично пересекаются, но ни один не полон**. Объединение
трёх списков даёт 41–44 уникальных адреса против 25–26 у лучшего из них.

> **Практический вывод для игрока.** По умолчанию клиент опрашивает только
> `sv_master1` и `sv_master2`. Добавьте третьим `dpmaster.deathmask.net` — в
> консоли или в `wolfconfig_mp.cfg`:
>
> ```
> seta sv_master3 "dpmaster.deathmask.net"
> ```
>
> В меню это отдельные источники «Internet1…Internet5» — UI берёт их из
> `sv_master1..5` по номеру вкладки (`MP/code/ui/ui_main.c:3170`).

### 2.3 Как устроен опрос

Мастер — это простой UDP-сервис на out-of-band пакетах Quake 3: четыре байта
`0xFF 0xFF 0xFF 0xFF`, дальше текстовая команда.

**Клиент → мастер.** Команда зависит от `com_gamename`
(`MP/code/client/cl_main.c:4854`):

```c
else if ( !Q_stricmp( com_gamename->string, LEGACY_MASTER_GAMENAME ) )
        Com_sprintf(command, sizeof(command), "getservers %s", Cmd_Argv(2));
else
        Com_sprintf(command, si zeof(command), "getservers %s %s", com_gamename->string, Cmd_Argv(2));
```

`LEGACY_MASTER_GAMENAME` — это `"wolfmp"` (`MP/code/qcommon/q_shared.h:87`), и
оно же значение `com_gamename` по умолчанию (`GAMENAME_FOR_MASTER`,
`MP/code/qcommon/q_shared.h:75`). То есть штатный клиент RTCW всегда шлёт
**короткую, legacy-форму** `getservers <протокол>` — без имени игры.

Это важно: `wolfmaster.idsoftware.com` понимает **только** короткую форму. На
`getservers wolfmp 60` он молчит, на `getservers 60` отвечает списком из 25
адресов. `dpmaster.deathmask.net` и `master.iortcw.org` принимают обе формы.

**Мастер → клиент.** Ответ `getserversResponse`, дальше подряд записи
`\<4 байта IPv4><2 байта порт BE>`, в конце `\EOT`. Для IPv6 — команда
`getserversExt` и записи с префиксом `/` и 16-байтным адресом
(`MP/code/client/cl_main.c:4845`).

**Сервер → мастер.** Каждые 5 минут (`HEARTBEAT_MSEC`,
`MP/code/server/sv_main.c:241`) выделенный сервер шлёт heartbeat. Строка
сообщения опять зависит от `com_gamename` (`MP/code/server/sv_main.c:266`):
при штатном `wolfmp` это `LEGACY_HEARTBEAT_FOR_MASTER`, то есть
`"Wolfenstein-1"` (`MP/code/qcommon/q_shared.h:88`); иначе — `"DarkPlaces"`.
При выключении сервер шлёт `"WolfFlatline-1"` (`MP/code/server/sv_main.c:368`).

DNS-имя мастера резолвится не чаще раза в сутки — `MASTERDNS_MSEC` равен 24
часам (`MP/code/server/sv_main.c:242`). Если мастер переехал, сервер узнает об
этом только после рестарта или изменения `sv_master*`.

**Опрос конкретного сервера.** Мастер адресов не проверяет, поэтому клиент сам
шлёт каждому `getstatus` (ответ `statusResponse` + строки игроков) или `getinfo`
(короткий `infoResponse`). Именно так получены цифры раздела 3.

---

## 3. Сколько народу в сети

### 3.1 Методика

1. Ко всем трём живым мастерам отправлены `getservers` для протоколов
   50, 57, 58, 59, 60, 61 — в обеих формах (с именем игры и без).
2. Адреса объединены и дедуплицированы.
3. Каждому адресу отправлен `getstatus`; разобраны infostring и список игроков.
4. **Боты отделены от людей по пингу**: в `statusResponse` строка игрока имеет
   вид `<счёт> <пинг> "<имя>"`, и у бота пинг всегда 0. Без этого фильтра цифра
   «игроков онлайн» завышается в восемь раз.

Скрипт — в разделе 6.

### 3.2 Цифры

Четыре замера 11 сентября 2026, 18:00–18:15 UTC (вечер пятницы в Европе —
не пик, но и не мёртвое время):

| Показатель | Значение |
|---|---|
| Адресов в мастерах (объединение трёх) | 41–44 |
| Серверов реально ответило | **25** |
| Не ответило (мёртвые записи в мастере) | 16–19 |
| **Живых людей** | **44–52** |
| Ботов | 413–419 |
| Серверов, где есть хотя бы один человек | 9–13 |
| Серверов, где играют только боты | 12–16 |

Разброс между последовательными замерами — обычное дело: люди заходят и
выходят, часть серверов теряет пакеты. Порядок величины устойчив: **несколько
десятков человек, около 25 живых серверов**.

Для сравнения: публичный трекер [gs4u.net](https://www.gs4u.net/en/wolfrtcw/) в
тот же момент показывал всего 4 сервера и 6 игроков — он опрашивает свой
устаревший список и сильно недосчитывает сеть. Прямой опрос мастеров даёт
картину в шесть раз полнее.

### 3.3 Кто на чём играет

Разбивка 25 живых серверов по движку (по полю `version` в infostring):

| Ветка | Серверов | Протокол |
|---|---|---|
| **iortcw** (1.5a … 1.51d) | **9** | 60 |
| RTCW 1.4 / 1.41b (ванильный движок id) | 8 | 60 |
| RTCW 1.0 / 1.1c и производные (WolfSE, WolfX, «rtcw 1.x») | 8 | 57 |

Что мастера отдают по протоколам:

| Протокол | Что это | Серверов |
|---|---|---|
| 50 | пре-релизная MP-демка (`PRE_RELEASE_DEMO`, `MP/code/qcommon/qcommon.h:291`) | 3 |
| 57 | ветка RTCW 1.0/1.1 — соревновательная сцена | 17 |
| 59 | RTCW 1.33 | 3 |
| **60** | RTCW 1.4/1.41 **и весь iortcw** | **26** |
| **61** | родной протокол iortcw (`PROTOCOL_VERSION`, `MP/code/qcommon/qcommon.h:288`) | **0** |

Ноль на 61-м — не ошибка замера и не признак того, что iortcw никто не
использует. Объяснение в разделе 5.1.

Самый населённый сервер сети на момент замера:

```
185.128.244.213:27960   The Boring Server    24 человека / 128 слотов
                        iortcw 1.51c-MP linux-x86_64   карта mp_base   gametype 5
```

Он же единственный крупный сервер **без ботов вообще** — 24 из 24 игроков живые.

### 3.4 Моды

По полю `gamename` у живых серверов:

| Мод | Серверов |
|---|---|
| Omni-Bot (`omnibot`, `omnibot69`) | 12 |
| rtcwPub / rtcwPubJ | 6 |
| FFmod | 3 |
| Dark-MoD 5.1 | 1 |
| s4ndmod26 | 1 |
| wolfpro | 1 |

Omni-Bot доминирует: именно он держит те самые 400+ ботов, наполняющих пустые
серверы, чтобы браузер не показывал 0/64.

### 3.5 Карты

Из 25 живых серверов стоковые карты крутят меньше половины — сцена давно живёт
на кастомных:

* стоковые: `mp_beach` (5 серверов — безусловный лидер), `mp_depot` (2),
  `mp_base`, `mp_sub`;
* кастомные: `mp_marketgarden`, `mp_omaha_2`, `hydro_dam_v2`, `wt_mustard`,
  `as_radarbunker`, `te_frostbite`, `te_ufo`, `mk_flooded_town`, `forest_base`,
  `ktg_rush`, `chateau`, `tram`, `infamy`, `denoflions_dual`, `trainyard`.

Практический вывод для админа: без настроенной докачки карт (раздел 4.9) на
кастомном сервере никто не окажется.

---

## 4. Свой сервер

### 4.1 Что понадобится

* Любая машина с Linux (или Windows/macOS) и публичным IPv4.
* Один открытый UDP-порт — по умолчанию **27960** (`PORT_SERVER`,
  `MP/code/qcommon/qcommon.h:339`; `net_port` берёт его как значение по
  умолчанию — `MP/code/qcommon/net_ip.c:1440`).
* Файлы игры из легальной копии RTCW.
* ~20 МБ под движок, ~700 МБ под `main/`.

Требований к железу практически нет: сервер на 32 слота с ботами укладывается в
одно ядро и пару сотен мегабайт RAM.

### 4.2 Сборка `iowolfded`

Выделенный сервер собирается из этого репозитория как отдельная цель. Имя
бинарника — `iowolfded` (`MP/Makefile:133`).

Зависимости для сборки только сервера минимальны — SDL2 серверу не нужен:

```bash
# Debian/Ubuntu
sudo apt install build-essential libcurl4-openssl-dev
```

Сборка (из каталога `MP/`):

```bash
cd MP
make -j"$(nproc)" BUILD_CLIENT=0 BUILD_SERVER=1
```

Готовый бинарник ляжет в `MP/build/release-linux-x86_64/iowolfded.x86_64`
(имя каталога зависит от платформы и архитектуры).

Полезные переключатели сборки (`README.md:81`):

| Переменная | Смысл |
|---|---|
| `BUILD_SERVER=1` | собрать `iowolfded` |
| `BUILD_CLIENT=0` | не собирать клиент (экономит время и зависимости) |
| `BUILD_GAME_SO=1` | собрать серверные игровые библиотеки (`qagame`) |
| `BUILD_GAME_QVM=1` | собрать QVM вместо нативных библиотек |
| `SERVERBIN=имя` | переименовать бинарник |
| `USE_CURL=1` | поддержка HTTP/FTP-докачки (включено по умолчанию, `MP/Makefile:180`) |
| `DEFAULT_BASEDIR=путь` | дополнительный путь поиска `main/` |

Для установки в систему: задайте `COPYDIR` и выполните `make copyfiles`
(`README.md:62`); по умолчанию это `/usr/local/games/wolf`.

### 4.3 Файлы игры

Рядом с бинарником должен лежать каталог `main/` с паками из вашей копии RTCW:

```
wolfserver/
├── iowolfded.x86_64
└── main/
    ├── pak0.pk3
    ├── mp_pak0.pk3
    ├── mp_pak1.pk3
    ├── mp_pak2.pk3
    ├── mp_pak3.pk3
    ├── mp_pak4.pk3
    ├── mp_pak5.pk3
    └── server.cfg
```

Движок проверяет контрольные суммы шести `mp_pak*.pk3` (`NUM_MP_PAKS` равно 6,
`MP/code/qcommon/qcommon.h:666`; таблица сумм — `MP/code/qcommon/files.c:198`) и
ругается в лог, если пак переименован или битый
(`MP/code/qcommon/files.c:3746`). Самый надёжный путь — скопировать **все**
`*.pk3` из `main/` установленной игры.

`mp_bin.pk3` серверу не нужен: проверка бинарных паков обёрнута в
`#ifndef DEDICATED` (`MP/code/qcommon/files.c:207`) — там лежат клиентские
библиотеки `cgame`/`ui`.

Простейший способ достать паки — установить RTCW из Steam/GOG и взять `main/`
оттуда. Распространять паки нельзя, копия должна быть ваша.

### 4.4 Конфиг

`main/server.cfg` — минимальный рабочий вариант для публичного objective-сервера:

```cfg
// ---- идентификация ----
set sv_hostname     "^1RU^7 RTCW Objective ^3| iortcw"
set g_motd          "Добро пожаловать. Правила: не читерим."
set sv_maxclients   "20"          // всего слотов
set sv_privateClients "2"         // из них по паролю
set sv_privatePassword "adminpass"

// ---- публичность ----
set dedicated       "2"           // 2 = интернет, 1 = только LAN
set net_port        "27960"

// ---- режим игры ----
set g_gametype      "5"           // 5 = Wolf Objective
set timelimit       "20"
set g_friendlyFire  "1"
set g_doWarmup      "1"
set g_warmup        "20"
set g_teamForceBalance "1"
set g_complaintlimit "3"
set g_maxlives      "0"

// ---- сеть и защита ----
set sv_pure         "1"
set sv_floodProtect "1"
set sv_maxRate      "25000"
set sv_minPing      "0"
set sv_maxPing      "0"
set sv_timeout      "240"
set sv_reconnectlimit "3"

// ---- докачка карт ----
set sv_allowDownload "1"
sets sv_dlURL       "http://example.org/rtcw"
set sv_dlRate       "1024"

// ---- управление ----
set rconPassword    "смените-это"
set g_log           "games.log"
set g_logsync       "0"
set sv_banFile      "serverbans.dat"

// ---- ротация карт ----
set d1 "map mp_beach ; set nextmap vstr d2"
set d2 "map mp_base ; set nextmap vstr d3"
set d3 "map mp_village ; set nextmap vstr d4"
set d4 "map mp_depot ; set nextmap vstr d1"
vstr d1
```

Значения `g_gametype` (`MP/code/game/bg_public.h:194`):

| Значение | Режим |
|---|---|
| 0 | Free For All |
| 1 | Tournament |
| 2 | Single Player |
| 3 | Team Deathmatch |
| 4 | Capture the Flag |
| **5** | **Wolf Objective** — штатный режим RTCW, значение по умолчанию (`MP/code/game/g_main.c:178`) |
| 6 | Stopwatch |
| 7 | Checkpoint |
| 8 | Capture & Hold |

Обратите внимание на `sets` вместо `set` у `sv_dlURL`: `sets` кладёт значение в
serverinfo, откуда его читает клиент (`README.md:270`). Для `sv_dlURL` это
обязательно — сама переменная объявлена с `CVAR_SERVERINFO`
(`MP/code/server/sv_init.c:903`), но на чужих движках `sets` нужен явно.

Значения по умолчанию для остальных серверных переменных смотрите в
`MP/code/server/sv_init.c:851` и далее, для игровых — в
`MP/code/game/g_main.c:176`.

### 4.5 Запуск

```bash
./iowolfded.x86_64 +set dedicated 2 +set fs_game "" +exec server.cfg
```

Переменная `dedicated` имеет `CVAR_INIT` в серверной сборке
(`MP/code/qcommon/common.c:2795`) — то есть задаётся **только** из командной
строки, менять её потом нельзя. В сборке сервера её значение по умолчанию уже
`2`, но указывать явно — привычка полезная.

Проверка, что всё поднялось:

```
Hitch warning: ... (норма при старте)
Resolving wolfmaster.idsoftware.com (IPv4)
wolfmaster.idsoftware.com resolved to 20.25.21.175:27950
Sending heartbeat to wolfmaster.idsoftware.com (IPv4)
Resolving master.iortcw.org (IPv4)
master.iortcw.org resolved to 104.194.9.163:27950
Sending heartbeat to master.iortcw.org (IPv4)
```

Строки `Sending heartbeat` (`MP/code/server/sv_main.c:312`) — главный признак,
что сервер зарегистрировался.

### 4.6 Регистрация в мастере

Три условия, все обязательны (`MP/code/server/sv_main.c:259`):

```c
// "dedicated 1" is for lan play, "dedicated 2" is for inet public play
if (!com_dedicated || com_dedicated->integer != 2 || !(netenabled & (NET_ENABLEV4 | NET_ENABLEV6)))
        return;		// only dedicated servers send heartbeats
```

1. `dedicated 2` — при `1` сервер работает, но в интернет-браузере его не будет.
2. `net_enabled` с включённым IPv4 и/или IPv6 (по умолчанию так и есть).
3. Непустой `sv_master*`.

Рекомендуемый набор мастеров — все три живых, третьим добавляем deathmask:

```cfg
set sv_master1 "wolfmaster.idsoftware.com"
set sv_master2 "master.iortcw.org"
set sv_master3 "dpmaster.deathmask.net"
```

Первый heartbeat уходит сразу при старте карты
(`MP/code/server/sv_main.c:1194`), дальше каждые 5 минут. В браузере сервер
появляется через минуту-другую.

Порт мастера можно указать явно: `set sv_master3 "dpmaster.deathmask.net:27950"`.

### 4.7 Порты и firewall

| Направление | Порт | Зачем |
|---|---|---|
| входящий UDP | 27960 (`net_port`) | игроки и запросы `getstatus`/`getinfo` от браузеров |
| исходящий UDP | 27950 | heartbeat мастерам |
| входящий TCP | 80/443 (опционально) | ваш HTTP для `sv_dlURL` |

```bash
sudo ufw allow 27960/udp
```

За NAT нужен проброс UDP 27960 **в обе стороны на один и тот же порт**: мастер
запоминает адрес источника heartbeat, и если NAT подменит порт, игроки получат
из мастера неправильный адрес.

Несколько серверов на одной машине — просто разные `net_port` (27960, 27961,
27962…). Если порт занят, движок сам увеличивает его и пробует следующий
(`MP/code/qcommon/net_ip.c:1390`) — при запуске нескольких экземпляров лучше
задавать порт явно, чтобы не гадать.

### 4.8 Проверка, что сервер видно снаружи

Со **стороннего** хоста (не с самого сервера — иначе проверите только loopback):

```bash
# что сервер отвечает вообще
python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
s.sendto(b'\xff\xff\xff\xffgetinfo x', ('ВАШ.IP', 27960))
print(s.recv(65535).decode('latin-1'))
PY
```

```bash
# что мастер вас отдаёт (ищем свой IP в ответе)
python3 - <<'PY'
import socket, struct
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
s.sendto(b'\xff\xff\xff\xffgetservers 60', ('wolfmaster.idsoftware.com', 27950))
d = s.recv(65535); b = d[d.find(b'getserversResponse') + 18:]
j = 0
while j + 7 <= len(b):
    if b[j:j+1] != b'\\':
        j += 1; continue
    c = b[j+1:j+7]
    if c.startswith(b'EOT'): break
    print('%d.%d.%d.%d:%d' % (tuple(c[0:4]) + (struct.unpack('>H', c[4:6])[0],)))
    j += 7
PY
```

Если сервер отвечает напрямую, но мастер его не отдаёт — подождите 5 минут
(интервал heartbeat) и проверьте исходящий UDP 27950.

### 4.9 Докачка карт

Без этого кастомные карты убивают сервер: игрок с недостающим `.pk3` просто не
зайдёт.

**UDP-докачка (работает всегда, но медленно).** `sv_allowDownload 1` и
`sv_dlRate` в кбайт/с (`MP/code/server/sv_init.c:859`, по умолчанию 100). Потолок
— около 1 Мбайт/с на клиента.

**HTTP/FTP-докачка (быстро, рекомендуется).** Разложите свои паки на веб-сервере
и укажите базовый URL. Клиент дописывает к нему `fs_game` и имя файла
(`README.md:277`): при `sv_dlURL` = `http://example.org/rtcw`, `fs_game` = `main`
и недостающем `mp_marketgarden.pk3` он скачает
`http://example.org/rtcw/main/mp_marketgarden.pk3`.

```cfg
set sv_allowDownload "1"
sets sv_dlURL "http://example.org/rtcw"
```

`sv_allowDownload` — битовая маска (`README.md:282`):

| Бит | Смысл |
|---|---|
| 1 | включить докачку |
| 4 | запретить UDP-докачку (только HTTP/FTP) |
| 8 | не просить клиента переподключаться после HTTP/FTP |

Разумный вариант для публичного сервера — `9` (включено + без переподключения),
оставляя UDP как запасной путь.

Движок ставит заголовок `HTTP_REFERER` вида `ioQ3://{IP}:{PORT}` — им можно
ограничить доступ к своему зеркалу через `mod_rewrite`, чтобы чужие серверы не
качали трафик с вашего хоста (`README.md:291`).

### 4.10 Управление работающим сервером

**rcon.** Задайте `rconPassword` и командуйте с клиента:

```
rconpassword вашпароль
rcon status
rcon map mp_beach
rcon kick "Ник"
```

Пустой `rconPassword` полностью отключает rcon
(`MP/code/server/sv_main.c:816`) — это правильное состояние, если вы им не
пользуетесь.

**Именованный канал вместо rcon.** `com_pipefile` создаёт FIFO, в который можно
писать команды прямо с хоста (`MP/code/qcommon/common.c:2932`) — удобнее и
безопаснее rcon, пароль по сети не ходит:

```cfg
set com_pipefile "wolfpipe"
```

```bash
echo "status" > main/wolfpipe
echo "say Сервер перезапустится через 5 минут" > main/wolfpipe
```

На Windows не работает.

**Баны.** Список хранится в `serverbans.dat` (`sv_banFile`,
`MP/code/server/sv_init.c:917`). Команды (`README.md:239`):

```
rcon banaddr 3            # забанить игрока по номеру
rcon banaddr 1.2.3.0/24   # забанить подсеть
rcon exceptaddr 1.2.3.4   # исключение
rcon bandel 2
rcon listbans
rcon rehashbans
```

**Логи.** `g_log` (по умолчанию `games.log`, `MP/code/game/g_main.c:233`);
`g_logsync 1` пишет без буферизации — медленнее, но лог не теряется при падении.

**PunkBuster.** В движке его нет — код вырезан. Античит-инфраструктуры у RTCW
сегодня не существует, защита строится на `sv_pure 1`, банах и присмотре
администратора.

### 4.11 Автозапуск через systemd

`/etc/systemd/system/wolfserver.service`:

```ini
[Unit]
Description=RTCW dedicated server (iortcw)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=wolf
WorkingDirectory=/opt/wolfserver
ExecStart=/opt/wolfserver/iowolfded.x86_64 +set dedicated 2 +set fs_homepath /opt/wolfserver +exec server.cfg
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/wolfserver.log
StandardError=inherit

# базовое ограждение
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/wolfserver /var/log

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now wolfserver
sudo journalctl -u wolfserver -f
```

`fs_homepath` указывает явно, куда писать `games.log`, `serverbans.dat` и
скачанные паки — иначе они уедут в домашний каталог пользователя.

### 4.12 Моды

Мод кладётся в свой каталог рядом с `main/` и включается через `fs_game`:

```bash
./iowolfded.x86_64 +set dedicated 2 +set fs_game osp +exec server.cfg
```

Что ставят на живых серверах сегодня — см. раздел 3.4. Практически безальтернативный
выбор для публичного сервера — **Omni-Bot**: без ботов пустой сервер не
набирает людей, потому что в браузере никто не заходит на 0/32.

Учтите пункт из `README.md:432`: лицензия на исходники игры RTCW запрещает
распространение модов, рассчитанных на несанкционированную id версию игры.

### 4.13 Локальный сервер на macOS

`iowolfded` собирается и под macOS (`make BUILD_CLIENT=0 BUILD_SERVER=1` из
`MP/`), но как постоянный публичный сервер десктоп неудобен — нужен статический адрес и аптайм. Для теста своей сборки
локально достаточно:

```bash
./iowolfded +set dedicated 1 +set net_port 27960 +map mp_beach
```

`dedicated 1` — LAN-режим: сервер не шлёт heartbeat и не светится в интернете,
но виден в локальной сети и доступен по `connect 127.0.0.1:27960`.

---

## 5. Подводные камни

### 5.1 Протокол 60 против 61, и почему список 61-го пуст

У iortcw два протокола одновременно (`MP/code/qcommon/qcommon.h:286`):

```c
#define	PROTOCOL_VERSION	61        // усиленный протокол iortcw
#define PROTOCOL_LEGACY_VERSION	60        // оригинальный RTCW 1.4
```

61-й защищён от UDP-спуфинга, но несовместим с оригинальной 1.4. Чтобы не
отрезать ванильных игроков, iortcw поддерживает оба — и **по умолчанию
представляется мастеру как 60-й** (`MP/code/qcommon/common.c:2862`):

```c
com_legacyprotocol = Cvar_Get("com_legacyprotocol", va("%i", PROTOCOL_LEGACY_VERSION), CVAR_INIT);
if (com_legacyprotocol->integer > 0)
        Cvar_Get("protocol", com_legacyprotocol->string, CVAR_ROM);
```

То же значение уходит в `infoResponse` (`MP/code/server/sv_main.c:682`).

Отсюда и нули в таблице раздела 3.3: **ни один публичный сервер не выключает
legacy-режим**, поэтому все 9 iortcw-серверов сети числятся под протоколом 60.

**Не ставьте `com_legacyprotocol 0`** на публичном сервере. Это включит чистый
61-й, отрежет всех игроков с оригинальной 1.4 — и ваш сервер окажется
единственным в списке протокола 61, где никто не ищет.

### 5.2 `com_legacyversion` и видимость в браузере

Старые браузеры серверов фильтруют по строке версии. Переменная
`com_legacyversion` заставляет сервер представляться как ванильный RTCW 1.41
(`README.md:184`, `MP/code/qcommon/common.c:2849`) — включайте, если сервер не
показывается в сторонних листингах.

### 5.3 `sv_pure`

`sv_pure 1` (по умолчанию, `MP/code/server/sv_init.c:871`) требует, чтобы
клиенты грузили ресурсы только из тех же паков, что у сервера. Выключение
открывает дверь чит-пакам, так что оставляйте единицу, а кастомные паки
раздавайте через `sv_dlURL`.

### 5.4 Мёртвые записи в мастерах

16–19 из 41–44 адресов в мастерах не отвечают — мастера не проверяют серверы и держат
записи после смерти. В браузере это выглядит как зависшие строки без пинга. На
работу вашего сервера не влияет, но объясняет расхождение между «серверов в
списке» и «серверов онлайн».

### 5.5 Заброшенная инфраструктура id

`wolfmotd.idsoftware.com` (обновления и MOTD) и `wolfauthorize.idsoftware.com`
(CD-key, `MP/code/qcommon/qcommon.h:311` — помечен «Decommissioned») не
работают. Проверка ключей в движке отключена, для запуска сервера ничего из
этого не нужно.

---

## 6. Приложение: скрипт замера

Сохраните как `rtcw-scan.py` и запустите — он повторит замеры раздела 3 и
покажет актуальный срез сети. Внешних зависимостей нет.

```python
#!/usr/bin/env python3
"""Опрос мастер-серверов RTCW и подсчёт живых игроков."""
import socket, struct, select, time

MASTERS = ['wolfmaster.idsoftware.com', 'dpmaster.deathmask.net', 'master.iortcw.org']
PROTOCOLS = (50, 57, 58, 59, 60, 61)


def parse_servers(data):
    """Разобрать getserversResponse в список (ip, port)."""
    out = []
    i = data.find(b'getserversResponse')
    if i < 0:
        return out
    b = data[i + 18:]
    j = 0
    while j + 7 <= len(b):
        if b[j:j + 1] != b'\\':
            j += 1
            continue
        c = b[j + 1:j + 7]
        if c.startswith(b'EOT'):
            break
        ip = '%d.%d.%d.%d' % tuple(c[0:4])
        port = struct.unpack('>H', c[4:6])[0]
        if port and ip != '0.0.0.0':
            out.append((ip, port))
        j += 7
    return out


def ask_master(host, cmd, timeout=2.0):
    found = set()
    try:
        addr = socket.getaddrinfo(host, 27950, socket.AF_INET, socket.SOCK_DGRAM)[0][4]
    except socket.gaierror:
        return found
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(b'\xff\xff\xff\xff' + cmd.encode(), addr)
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                found.update(parse_servers(s.recv(65535)))
            except socket.timeout:
                break
    finally:
        s.close()
    return found


def collect():
    """Объединить списки всех мастеров по всем протоколам."""
    servers = set()
    for master in MASTERS:
        for proto in PROTOCOLS:
            # короткая форма — единственная, которую понимает мастер id Software
            servers |= ask_master(master, 'getservers %d' % proto)
            servers |= ask_master(master, 'getservers wolfmp %d' % proto)
    return servers


def poll(servers, timeout=8.0):
    """Опросить каждый сервер через getstatus."""
    socks = {}
    for ip, port in servers:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setblocking(False)
            s.sendto(b'\xff\xff\xff\xffgetstatus x', (ip, port))
            socks[s] = (ip, port)
        except OSError:
            pass
    results = {}
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select(list(socks), [], [], 0.3)
        for s in ready:
            try:
                data, _ = s.recvfrom(65535)
            except OSError:
                continue
            lines = data[4:].decode('latin-1').split('\n')
            if not lines[0].startswith('statusResponse'):
                continue
            fields = (lines[1] if len(lines) > 1 else '').split('\\')[1:]
            info = {fields[i]: fields[i + 1] for i in range(0, len(fields) - 1, 2)}
            results[socks[s]] = (info, [l for l in lines[2:] if l.strip()])
    return results


def humans(players):
    """У бота пинг всегда 0 — так они и отделяются от людей."""
    n = 0
    for line in players:
        parts = line.split(' ')
        if len(parts) > 1 and parts[1].lstrip('-').isdigit() and int(parts[1]) != 0:
            n += 1
    return n


def main():
    servers = collect()
    results = poll(servers)
    total_h = total_b = 0
    rows = []
    for (ip, port), (info, players) in results.items():
        h = humans(players)
        b = len(players) - h
        total_h += h
        total_b += b
        rows.append((h, b, '%s:%d' % (ip, port), info.get('sv_hostname', '?'),
                     info.get('mapname', '?'), info.get('version', '?')))
    for h, b, addr, name, mapname, version in sorted(rows, reverse=True):
        print('%-22s %-34s %-16s людей=%-3d ботов=%-3d  %s'
              % (addr, name[:34], mapname, h, b, version[:40]))
    print('\nв мастерах: %d | ответили: %d | людей: %d | ботов: %d'
          % (len(servers), len(results), total_h, total_b))


if __name__ == '__main__':
    main()
```

---

## 7. Источники

Цифры раздела 3 получены прямым опросом мастеров и серверов 11 сентября 2026
года (18:00–18:15 UTC) скриптом из раздела 6. Внешние ссылки — для контекста:

* [dpmaster.deathmask.net](https://dpmaster.deathmask.net/) — живой мастер, он же
  веб-листинг
* [gs4u.net: RTCW server list](https://www.gs4u.net/en/wolfrtcw/) — сторонний
  трекер (неполный, см. 3.2)
* [wolfenstein4ever.de: RtCW Master list is back](http://wolfenstein4ever.de/index.php/news/return-to-castle-wolfenstein/rtcw-misc/item/1588-rtcw-master-list-is-back)
  — история возвращения официального мастера
* [Steam: RtCW MP — How To play online nowadays](https://steamcommunity.com/sharedfiles/filedetails/?id=166033677)
  — руководство для игроков
* [OldServers: RTCW online](https://oldservers.com.ar/en/rtcw.php) — сообщество,
  держащее кооперативные серверы

Внутри репозитория: `README.md` (переменные и сборка), `HOWTO-Build.txt`
(сборочное окружение), `docs/RU/MP.md` (разбор сетевой архитектуры движка).
