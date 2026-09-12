/*
===========================================================================
cl_selftest.c -- the port's own test run.

Why this exists
---------------
This port keeps breaking in a particular way: a setting the launcher offers
stops reaching the engine, and nothing says so. The switch still moves, the
value is still written, the game still starts -- and the thing it controls
quietly does nothing. Three of those were found by hand in one afternoon: a
gyro that multiplayer never read, an adaptive-trigger switch nobody looked at,
and seven pad keys that could be bound to a name the engine did not know.

None of them were visible in a log. All of them are trivial to ask about from
inside the running game, which is what this does.

Two runs
--------
`selftest basic` answers everything that can be answered from a standing start,
in a second or so: did the launcher's settings arrive, are the commands it binds
real, are the key names it writes ones the engine knows, is the renderer at the
size it should be, is the game data there.

`selftest full` does that and then plays: loads a map, waits for the game to own
the screen, runs the twenty-one-row stick and gyro table, and measures the frame
rate. Two to three minutes.

What it is not
--------------
Not a unit test framework and not a substitute for playing the game. Every check
here is of the form "the launcher says X, does the engine agree" -- which is the
seam the bugs keep appearing in, and the one place a machine can watch better
than a person.

The rows are in Russian because they are shown in the launcher, whose source
language is Russian; Loc.swift turns them into English when the device asks for
it.
===========================================================================
*/

#include "client.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_IPHONE
// Declared here rather than through ios_bridge.h: this file is in the engine
// tree, which is built on macOS too, where that header is not on the include
// path and the bridge is not compiled at all.
void IOSBridge_SelfTestBegin( const char *title );
void IOSBridge_SelfTestRow( int verdict, const char *group, const char *name,
                            const char *detail );
void IOSBridge_SelfTestEnd( int passed, int failed, int skipped );
void IOSLauncher_ShowSelfTest( void );
#endif

// Reaches into sdl_input.c for the stick table's result. Declared here for the
// same reason as above -- there is no shared private header between the two.
void IN_PadTestResult( int *passed, int *failed, qboolean *running );
const char *IN_PadTestFailureName( int index );

#define ST_MAX_ROWS      192
#define ST_MAX_LISTED    16     // failures named individually before summarising

typedef enum {
	ST_PASS,
	ST_FAIL,
	ST_SKIP
} stVerdict_t;

typedef struct {
	int  verdict;
	char group[40];
	char name[80];
	char detail[160];
} stRow_t;

static stRow_t  stRows[ST_MAX_ROWS];
static int      stNumRows;
static int      stPassed, stFailed, stSkipped;

// --- the full run's state machine -------------------------------------------
typedef enum {
	STG_IDLE,
	STG_LOADING,      // the map is being asked for and loaded
	STG_CLEARING,     // waiting for menus to get out of the way
	STG_SETTLE,       // a moment of quiet before measuring anything
	STG_PADTEST,      // the stick and gyro table is running
	STG_FPS,          // counting frames
	STG_FINISH
} stStage_t;

static stStage_t stStage = STG_IDLE;
static int       stStageSince;     // Sys_Milliseconds when the stage began
static int       stStageFrames;
static int       stDismissals;     // how many times we have tried to clear the UI
static int       stFpsFrames;
static qboolean  stRunning;

/*
===============
ST_Row

Records one answer and prints it. Everything this file learns goes through here,
so the console, the log, the report file and the launcher all see the same rows
in the same order.
===============
*/
static void ST_Row( stVerdict_t verdict, const char *group, const char *name,
                    const char *fmt, ... )
{
	va_list argptr;
	char    detail[160];
	stRow_t *row;

	detail[0] = '\0';
	if ( fmt ) {
		va_start( argptr, fmt );
		Q_vsnprintf( detail, sizeof( detail ), fmt, argptr );
		va_end( argptr );
	}

	switch ( verdict ) {
		case ST_PASS: stPassed++;  break;
		case ST_FAIL: stFailed++;  break;
		default:      stSkipped++; break;
	}

	if ( stNumRows < ST_MAX_ROWS ) {
		row = &stRows[stNumRows++];
		row->verdict = (int)verdict;
		Q_strncpyz( row->group,  group,  sizeof( row->group ) );
		Q_strncpyz( row->name,   name,   sizeof( row->name ) );
		Q_strncpyz( row->detail, detail, sizeof( row->detail ) );
	}

	Com_Printf( "selftest: [%s] %s / %s%s%s\n",
		verdict == ST_PASS ? "PASS" : ( verdict == ST_FAIL ? "FAIL" : "SKIP" ),
		group, name, detail[0] ? " -- " : "", detail );

#if defined(__APPLE__) && TARGET_OS_IPHONE
	IOSBridge_SelfTestRow( (int)verdict, group, name, detail );
#endif
}

/*
===============
ST_CommandExists

There is no Cmd_Exists in this engine, only an enumerator, so the enumerator is
what we use. Cheap enough at a few hundred commands, and asked a few dozen times.
===============
*/
static const char *stWanted;
static qboolean    stFound;

static void ST_CommandProbe( const char *s )
{
	if ( !stFound && !Q_stricmp( s, stWanted ) ) {
		stFound = qtrue;
	}
}

static qboolean ST_CommandExists( const char *name )
{
	stWanted = name;
	stFound  = qfalse;
	Cmd_CommandCompletion( ST_CommandProbe );
	return stFound;
}

/*
===============
ST_CheckCommands

The commands the launcher and the on-screen controls cannot work without.

`sendkey` is the one worth spelling out: the touch overlay presses a binding by
running it, and multiplayer did not have it at all, so every overlay button that
was a binding rather than a stick did nothing. It looked exactly like a dead
touch area.
===============
*/
static void ST_CheckCommands( void )
{
	static const char *needed[] = {
		"bind", "unbind", "exec", "sendkey", "padtest", "selftest",
		"+attack", "+forward", "+moveleft", "+speed", "+activate"
	};
	int i;
	int missing = 0;

	for ( i = 0; i < (int)ARRAY_LEN( needed ); i++ ) {
		if ( !ST_CommandExists( needed[i] ) ) {
			ST_Row( ST_FAIL, "Команды", needed[i], "команда не зарегистрирована" );
			missing++;
		}
	}

	if ( !missing ) {
		ST_Row( ST_PASS, "Команды", "обязательные команды",
			"все %d на месте", (int)ARRAY_LEN( needed ) );
	}
}

/*
===============
ST_CheckPadKeyNames

Every extended pad key the touch overlay and the launcher can name. A key whose
name the engine does not know cannot be bound: `bind` looks the name up, fails
to find it, and says nothing the player will ever see.
===============
*/
static void ST_CheckPadKeyNames( void )
{
	// Exactly the twenty-four the launcher's pad page can offer, spelled the way
	// it spells them. The list is deliberately the launcher's rather than the
	// engine's: the question is not "what keys exist" but "can everything the
	// player is shown actually be bound", and a name only the engine knows is
	// nobody's problem.
	static const char *names[] = {
		"PAD0_A", "PAD0_B", "PAD0_X", "PAD0_Y",
		"PAD0_LEFTSHOULDER", "PAD0_RIGHTSHOULDER",
		"PAD0_LEFTTRIGGER", "PAD0_RIGHTTRIGGER",
		"PAD0_LEFTTRIGGER_HARD", "PAD0_RIGHTTRIGGER_HARD",
		"PAD0_TOUCHPAD", "PAD0_TOUCH_TAP",
		"PAD0_TOUCH_SWIPE_UP", "PAD0_TOUCH_SWIPE_DOWN",
		"PAD0_TOUCH_SWIPE_LEFT", "PAD0_TOUCH_SWIPE_RIGHT",
		"PAD0_DPAD_UP", "PAD0_DPAD_DOWN", "PAD0_DPAD_LEFT", "PAD0_DPAD_RIGHT",
		"PAD0_START", "PAD0_BACK",
		"PAD0_LEFTSTICK_CLICK", "PAD0_RIGHTSTICK_CLICK"
	};
	int i;
	int missing = 0;

	for ( i = 0; i < (int)ARRAY_LEN( names ); i++ ) {
		if ( Key_StringToKeynum( (char *)names[i] ) == -1 ) {
			ST_Row( ST_FAIL, "Управление", names[i], "движок не знает такого имени клавиши" );
			missing++;
		}
	}

	if ( !missing ) {
		ST_Row( ST_PASS, "Управление", "имена клавиш геймпада",
			"все %d распознаны", (int)ARRAY_LEN( names ) );
	}
}

/*
===============
ST_CheckGyroWiring

The gyro's two axes have to fit in the array they are written into, and the view
code has to be the copy that reads them. The first is arithmetic. The second
cannot be seen from here at all -- only the full run's table can answer it -- so
this says so rather than implying an answer it does not have.
===============
*/
static void ST_CheckGyroWiring( qboolean full )
{
	if ( AXIS_GYRO_PITCH < MAX_JOYSTICK_AXIS && AXIS_GYRO_YAW < MAX_JOYSTICK_AXIS ) {
		ST_Row( ST_PASS, "Управление", "оси гироскопа",
			"%d и %d при размере массива %d",
			AXIS_GYRO_PITCH, AXIS_GYRO_YAW, MAX_JOYSTICK_AXIS );
	} else {
		ST_Row( ST_FAIL, "Управление", "оси гироскопа",
			"индексы %d/%d не помещаются в %d",
			AXIS_GYRO_PITCH, AXIS_GYRO_YAW, MAX_JOYSTICK_AXIS );
	}

	if ( !full ) {
		ST_Row( ST_SKIP, "Управление", "гироскоп поворачивает обзор",
			"проверяется только в полном прогоне" );
	}
}

/*
===============
ST_CheckLauncherSettings

The launcher's own file, read back and compared against what the engine ended up
with. This is the check the others are worth the least without: it needs no list
of cvars kept in step by hand, because the file is the list, and it catches both
halves of the fault -- a setting written to a cvar nobody registered, and a
setting registered but then overwritten by a config exec'd afterwards.
===============
*/
static void ST_CheckLauncherSettings( void )
{
	union { char *c; void *v; } f;
	char        *text;
	const char  *token;
	char         name[MAX_CVAR_VALUE_STRING];
	char         want[MAX_CVAR_VALUE_STRING];
	const char  *have;
	int          len;
	int          checked = 0, wrong = 0, absent = 0, listed = 0;

	len = FS_ReadFile( "ios_launcher.cfg", &f.v );
	if ( len <= 0 || !f.c ) {
		ST_Row( ST_SKIP, "Настройки", "файл лаунчера",
			"ios_launcher.cfg не найден -- лаунчер ещё ничего не сохранял" );
		return;
	}

	text = f.c;
	COM_BeginParseSession( "ios_launcher.cfg" );

	while ( 1 ) {
		token = COM_ParseExt( &text, qtrue );
		if ( !token[0] ) {
			break;
		}

		if ( !Q_stricmp( token, "seta" ) || !Q_stricmp( token, "set" ) ) {
			Q_strncpyz( name, COM_ParseExt( &text, qfalse ), sizeof( name ) );
			Q_strncpyz( want, COM_ParseExt( &text, qfalse ), sizeof( want ) );

			if ( !name[0] ) {
				continue;
			}
			checked++;

			if ( Cvar_Flags( name ) == CVAR_NONEXISTENT ) {
				absent++;
				if ( listed < ST_MAX_LISTED ) {
					ST_Row( ST_FAIL, "Настройки", name,
						"лаунчер пишет \"%s\", но такого cvar'а в этой игре нет", want );
					listed++;
				}
				continue;
			}

			// Whether the value arrived is only a question where the engine
			// execs this file at all, which is the device and nowhere else --
			// Com_ExecuteCfg's exec of it sits inside TARGET_OS_IPHONE. On a
			// desktop test build the file is written and never read, so a
			// mismatch means nothing, and reporting it as a fault buries the
			// rows that do mean something.
#if defined(__APPLE__) && TARGET_OS_IPHONE
			have = Cvar_VariableString( name );
			if ( Q_stricmp( have, want ) ) {
				wrong++;
				if ( listed < ST_MAX_LISTED ) {
					ST_Row( ST_FAIL, "Настройки", name,
						"лаунчер поставил \"%s\", в игре \"%s\"", want, have );
					listed++;
				}
			}
#else
			(void)have;
#endif
			continue;
		}

	}

	FS_FreeFile( f.v );

#if defined(__APPLE__) && TARGET_OS_IPHONE
	if ( !absent && !wrong ) {
		ST_Row( ST_PASS, "Настройки", "настройки лаунчера",
			"все %d применены", checked );
	} else {
		ST_Row( ST_FAIL, "Настройки", "настройки лаунчера",
			"из %d: %d не существует, %d перезаписано", checked, absent, wrong );
	}
#else
	(void)wrong;
	if ( absent ) {
		ST_Row( ST_FAIL, "Настройки", "настройки лаунчера",
			"из %d: %d пишется в cvar, которого нет", checked, absent );
	} else {
		ST_Row( ST_PASS, "Настройки", "настройки лаунчера",
			"все %d записываются в существующие cvar'ы", checked );
	}
	ST_Row( ST_SKIP, "Настройки", "значения настроек",
		"эта сборка не исполняет ios_launcher.cfg -- сверять значения не с чем" );
#endif

}

/*
===============
ST_CheckBindings

Every key the launcher has bound: is the name one the engine knows, and is the
thing bound to it something that can actually be run.

Asked twice, because the honest answer changes. Cold, at the main menu, the game
modules are not loaded and the commands they register -- weapnext, zoomin,
notebook and the rest of what a player actually binds -- do not exist yet, so a
missing one says nothing. With a map up they all exist, and a missing one is
exactly the fault this file was written for: multiplayer does not register the
campaign's notebook, and a key bound to it there does nothing at all.
===============
*/
static void ST_CheckBindings( qboolean modulesUp )
{
	union { char *c; void *v; } f;
	char        *text;
	const char  *token;
	char         key[MAX_CVAR_VALUE_STRING];
	char         action[MAX_CVAR_VALUE_STRING];
	int          len;
	int          binds = 0, badKeys = 0, badActions = 0, listed = 0;

	len = FS_ReadFile( "ios_launcher.cfg", &f.v );
	if ( len <= 0 || !f.c ) {
		return;		// the settings check has already said so
	}

	text = f.c;
	COM_BeginParseSession( "ios_launcher.cfg" );

	while ( 1 ) {
		token = COM_ParseExt( &text, qtrue );
		if ( !token[0] ) {
			break;
		}

		if ( Q_stricmp( token, "bind" ) ) {
			continue;
		}

		Q_strncpyz( key,    COM_ParseExt( &text, qfalse ), sizeof( key ) );
		Q_strncpyz( action, COM_ParseExt( &text, qfalse ), sizeof( action ) );

		if ( !key[0] ) {
			continue;
		}
		binds++;

		if ( Key_StringToKeynum( key ) == -1 ) {
			badKeys++;
			if ( listed < ST_MAX_LISTED ) {
				ST_Row( ST_FAIL, "Привязки", key,
					"привязана \"%s\", но такой клавиши движок не знает", action );
				listed++;
			}
			continue;
		}

		if ( !action[0] ) {
			continue;
		}

		{
			// Only the first word: a binding may be several commands, and may
			// legitimately start with a cvar rather than a command.
			char  first[80];
			char *space;

			Q_strncpyz( first, action, sizeof( first ) );
			space = strchr( first, ' ' );
			if ( space ) {
				*space = '\0';
			}

			if ( !ST_CommandExists( first ) &&
			     Cvar_Flags( first ) == CVAR_NONEXISTENT ) {
				badActions++;
				if ( modulesUp && listed < ST_MAX_LISTED ) {
					ST_Row( ST_FAIL, "Привязки", key,
						"назначено \"%s\", но такой команды в этой игре нет", first );
					listed++;
				}
			}
		}
	}

	FS_FreeFile( f.v );

	if ( !binds ) {
		return;
	}

	if ( badKeys ) {
		ST_Row( ST_FAIL, "Привязки", "имена клавиш",
			"из %d: %d с клавишей, которой движок не знает", binds, badKeys );
	} else {
		ST_Row( ST_PASS, "Привязки", "имена клавиш",
			"все %d клавиши движок знает", binds );
	}

	if ( !modulesUp ) {
		ST_Row( ST_SKIP, "Привязки", "команды привязок",
			"проверяются в полном прогоне: без загруженной карты команд игровых модулей ещё нет" );
		return;
	}

	if ( badActions ) {
		ST_Row( ST_FAIL, "Привязки", "команды привязок",
			"из %d: %d назначено на то, чего в этой игре нет", binds, badActions );
	} else {
		ST_Row( ST_PASS, "Привязки", "команды привязок", "все %d рабочие", binds );
	}
}

/*
===============
ST_CheckRenderer

The size the game is actually drawing at. This has its own row because the
failure it looks for is one a player reports as something else entirely: when
the renderer falls back to 640x480 on a tablet the picture shrinks into a
corner, and what gets reported is that the touch controls have stopped hitting
anything.
===============
*/
static void ST_CheckRenderer( void )
{
	int w = cls.glconfig.vidWidth;
	int h = cls.glconfig.vidHeight;

	if ( w <= 0 || h <= 0 ) {
		ST_Row( ST_FAIL, "Графика", "разрешение", "рендерер не поднят" );
		return;
	}

#if defined(__APPLE__) && TARGET_OS_IPHONE
	// A tablet has no 640x480 mode to be legitimately in. Anything that small
	// is the fallback, which is the bug.
	if ( w < 1024 ) {
		ST_Row( ST_FAIL, "Графика", "разрешение",
			"%d x %d -- похоже на откат к минимальному режиму", w, h );
	} else {
		ST_Row( ST_PASS, "Графика", "разрешение", "%d x %d", w, h );
	}
#else
	ST_Row( ST_PASS, "Графика", "разрешение", "%d x %d", w, h );
#endif

	if ( Cvar_Flags( "r_hidpi" ) == CVAR_NONEXISTENT ) {
		ST_Row( ST_FAIL, "Графика", "r_hidpi",
			"cvar не зарегистрирован -- сборка не знает про экран Retina" );
	} else {
		ST_Row( ST_PASS, "Графика", "r_hidpi", "%s", Cvar_VariableString( "r_hidpi" ) );
	}
}

/*
===============
ST_CheckGameData

Which paks the file system actually opened. Named rather than counted, because
"twelve paks" is true of a set that is missing the one the server wants.
===============
*/
static void ST_CheckGameData( void )
{
	const char *paks = FS_LoadedPakNames();
#ifdef IORTCW_MP_BUILD
	static const char *wanted[] = { "mp_pak0", "mp_bin" };
	const char *game = "Мультиплеер";
#else
	static const char *wanted[] = { "pak0", "sp_pak1" };
	const char *game = "Кампания";
#endif
	int i;
	int missing = 0;

	if ( !paks || !paks[0] ) {
		ST_Row( ST_FAIL, "Данные", game, "не загружено ни одного pk3" );
		return;
	}

	for ( i = 0; i < (int)ARRAY_LEN( wanted ); i++ ) {
		if ( !strstr( paks, wanted[i] ) ) {
			ST_Row( ST_FAIL, "Данные", wanted[i], "pk3 не загружен" );
			missing++;
		}
	}

	if ( !missing ) {
		ST_Row( ST_PASS, "Данные", game, "обязательные pk3 на месте" );
	}
}

/*
===============
ST_CheckNetwork

Multiplayer only, and only the parts a run can ask about without going near the
network: that there is somewhere to ask for servers, and that the browser's own
limits are not set to something that hides every server there is.
===============
*/
static void ST_CheckNetwork( void )
{
#ifdef IORTCW_MP_BUILD
	int         masters = 0;
	int         i;
	const char *v;

	for ( i = 1; i <= 5; i++ ) {
		v = Cvar_VariableString( va( "sv_master%d", i ) );
		if ( v && v[0] ) {
			masters++;
		}
	}

	if ( masters ) {
		ST_Row( ST_PASS, "Сеть", "мастер-серверы", "настроено: %d", masters );
	} else {
		ST_Row( ST_FAIL, "Сеть", "мастер-серверы",
			"ни одного -- список серверов будет пустым" );
	}

	if ( Cvar_VariableIntegerValue( "cl_maxPing" ) < 200 ) {
		ST_Row( ST_FAIL, "Сеть", "cl_maxPing",
			"%s -- при таком пределе большинство серверов не покажется",
			Cvar_VariableString( "cl_maxPing" ) );
	} else {
		ST_Row( ST_PASS, "Сеть", "cl_maxPing", "%s",
			Cvar_VariableString( "cl_maxPing" ) );
	}
#else
	ST_Row( ST_SKIP, "Сеть", "мастер-серверы", "только в мультиплеере" );
#endif
}

/*
===============
ST_WriteReport

The whole run, on disk, where it survives the app being closed. Tab separated
and one row to a line, so it can be read by eye and by machine without either
having to guess.
===============
*/
static void ST_WriteReport( void )
{
	fileHandle_t f;
	char         line[400];
	int          i;

	f = FS_FOpenFileWrite( "selftest.txt" );
	if ( !f ) {
		Com_Printf( "selftest: не удалось записать selftest.txt\n" );
		return;
	}

	Com_sprintf( line, sizeof( line ),
		"# iORTCW selftest\n# %s\n# %s\n# passed %d\tfailed %d\tskipped %d\n",
#ifdef IORTCW_MP_BUILD
		"multiplayer",
#else
		"campaign",
#endif
		Cvar_VariableString( "version" ),
		stPassed, stFailed, stSkipped );
	FS_Write( line, strlen( line ), f );

	for ( i = 0; i < stNumRows; i++ ) {
		Com_sprintf( line, sizeof( line ), "%s\t%s\t%s\t%s\n",
			stRows[i].verdict == ST_PASS ? "PASS" :
			( stRows[i].verdict == ST_FAIL ? "FAIL" : "SKIP" ),
			stRows[i].group, stRows[i].name, stRows[i].detail );
		FS_Write( line, strlen( line ), f );
	}

	FS_FCloseFile( f );
	Com_Printf( "selftest: отчёт записан в selftest.txt\n" );
}

/*
===============
ST_Finish
===============
*/
static void ST_Finish( void )
{
	stStage   = STG_IDLE;
	stRunning = qfalse;

	Com_Printf( "selftest: %d прошло, %d не прошло, %d пропущено\n",
		stPassed, stFailed, stSkipped );

	ST_WriteReport();

#if defined(__APPLE__) && TARGET_OS_IPHONE
	IOSBridge_SelfTestEnd( stPassed, stFailed, stSkipped );
	// Back to the launcher with the answer, rather than leaving the player in a
	// test map wondering whether anything happened.
	IOSLauncher_ShowSelfTest();
#endif
}

/*
===============
ST_RunBasic

Everything that can be answered without playing.
===============
*/
static void ST_RunBasic( qboolean full )
{
	ST_CheckLauncherSettings();

	// Skipped here when a full run is about to load a map: the same rows are
	// asked again with the game modules in, and reporting them twice -- once
	// unanswerable, once answered -- reads as two different results.
	if ( !full ) {
		ST_CheckBindings( cls.cgameStarted );
	}

	ST_CheckCommands();
	ST_CheckPadKeyNames();
	ST_CheckGyroWiring( full );
	ST_CheckRenderer();
	ST_CheckGameData();
	ST_CheckNetwork();
}

/*
===============
CL_SelfTestFrame

Ticked once a frame while a full run is in progress. Written as a state machine
rather than a loop with waits in it for the reason every other scripted run in
this port learned the hard way: a pending `wait` freezes the command buffer, and
the digital movement path the stick table measures runs through that buffer.
===============
*/
void CL_SelfTestFrame( void )
{
	int      elapsed;
	int      passed, failed;
	qboolean padRunning;

	if ( stStage == STG_IDLE ) {
		return;
	}

	stStageFrames++;
	elapsed = Sys_Milliseconds() - stStageSince;

	switch ( stStage ) {
		case STG_LOADING:
			// Give the map a generous window. An iPad loading mp_beach off a
			// cold file system is slower than anything a desktop does.
			if ( Cvar_VariableIntegerValue( "sv_running" ) && elapsed > 3000 ) {
				stStage       = STG_CLEARING;
				stStageSince  = Sys_Milliseconds();
				stStageFrames = 0;
				stDismissals  = 0;
#ifdef IORTCW_MP_BUILD
				// Multiplayer drops into the limbo screen, which holds the UI
				// until a side is picked. Nothing below can start until it is.
				Cbuf_AddText( "team r\n" );
#endif
			} else if ( elapsed > 120000 ) {
				ST_Row( ST_FAIL, "Игра", "загрузка карты",
					"карта не загрузилась за две минуты" );
				stStage = STG_FINISH;
			}
			break;

		case STG_CLEARING:
			// CA_ACTIVE and not merely "no menu": CL_UIActive() deliberately
			// counts a cinematic as the game owning the screen, which is right
			// for what it is used for and wrong here. Several multiplayer maps
			// open on a ROQ intro, and during one the view does not turn, so a
			// table measured over it fails three quarters of its rows and reads
			// as the sticks being dead.
			if ( clc.state == CA_ACTIVE && !CL_UIActive() ) {
				// Now that the game modules are in, ask about the bindings
				// again -- this time their commands exist, so a missing one
				// means something.
				ST_CheckBindings( qtrue );

				ST_Row( ST_PASS, "Игра", "загрузка карты",
					"карта загружена, игра владеет экраном" );
				// Put the input layer through a restart of its own before
				// measuring anything.
				//
				// The virtual pad is attached by cvar, but attaching an SDL
				// device is not the same as the engine opening it: the joystick
				// layer opens what is present when it starts, and whether the
				// pad ends up open therefore depends on whether it was attached
				// before or after the restart a map load happens to perform.
				// That ordering came out differently from run to run, and when
				// it came out wrong every axis read zero and three quarters of
				// the table failed for want of a stick that was
				// never opened. So the run stops depending on it and asks for
				// the restart itself, after which the pad is attached, open,
				// and the only device there.
				Cbuf_AddText( "in_restart\n" );

				stStage       = STG_SETTLE;
				stStageSince  = Sys_Milliseconds();
				stStageFrames = 0;
				break;
			}

			// The campaign opens on a briefing that waits to be dismissed. One
			// press every second or so, rather than a stream of them: the menu
			// under it has its own pages, and hammering the button walks
			// through them instead of leaving.
			if ( elapsed > 1500 + stDismissals * 1200 && stDismissals < 8 ) {
				Com_QueueEvent( 0, SE_KEY, K_MOUSE1, qtrue,  0, NULL );
				Com_QueueEvent( 0, SE_KEY, K_MOUSE1, qfalse, 0, NULL );
				stDismissals++;
			}

			if ( elapsed > 90000 ) {
				ST_Row( ST_FAIL, "Игра", "загрузка карты",
					"экран так и не освободился: меню %d, состояние %d",
					Key_GetCatcher(), (int)clc.state );
				stStage = STG_FINISH;
			}
			break;

		case STG_SETTLE:
			// A map load restarts the input layer and the pad has just been
			// attached on top of that. Measuring a turn rate while either is
			// still settling reads as a fault that is not there.
			if ( elapsed > 4000 ) {
				stStage       = STG_PADTEST;
				stStageSince  = Sys_Milliseconds();
				stStageFrames = 0;
				Cbuf_AddText( "padtest\n" );
			}
			break;

		case STG_PADTEST:
			IN_PadTestResult( &passed, &failed, &padRunning );

			// The table needs a frame or two to start before its absence means
			// it has finished.
			if ( elapsed < 2000 ) {
				break;
			}

			if ( !padRunning ) {
				if ( passed + failed == 0 ) {
					ST_Row( ST_FAIL, "Управление", "таблица стиков и гироскопа",
						"прогон не состоялся" );
				} else if ( failed ) {
					int         i;
					const char *name;

					// Named rather than counted. Which row failed is the whole
					// of the diagnosis -- a movement row and a look row failing
					// are two different faults that feel identical -- and the
					// console this used to point at does not survive the game
					// restart a map load performs.
					for ( i = 0; ( name = IN_PadTestFailureName( i ) ) != NULL; i++ ) {
						ST_Row( ST_FAIL, "Управление", name, "строка не прошла" );
					}

					ST_Row( ST_FAIL, "Управление", "таблица стиков и гироскопа",
						"%d из %d строк не прошли", failed, passed + failed );
				} else {
					ST_Row( ST_PASS, "Управление", "таблица стиков и гироскопа",
						"все %d строк прошли, включая гироскоп", passed );
				}

				stStage       = STG_FPS;
				stStageSince  = Sys_Milliseconds();
				stStageFrames = 0;
				stFpsFrames   = 0;
			} else if ( elapsed > 120000 ) {
				ST_Row( ST_FAIL, "Управление", "таблица стиков и гироскопа",
					"прогон не завершился за две минуты" );
				stStage = STG_FPS;
				stStageSince = Sys_Milliseconds();
				stFpsFrames  = 0;
			}
			break;

		case STG_FPS:
			stFpsFrames++;
			if ( elapsed >= 4000 ) {
				float fps = stFpsFrames * 1000.0f / (float)elapsed;

				// Not a pass or fail anybody should argue with -- it is a
				// number to keep, and the threshold is only there so a run that
				// crawls says so out loud.
				if ( fps >= 30.0f ) {
					ST_Row( ST_PASS, "Графика", "частота кадров",
						"%.0f кадров/с на карте", fps );
				} else {
					ST_Row( ST_FAIL, "Графика", "частота кадров",
						"%.0f кадров/с -- играть будет тяжело", fps );
				}
				stStage = STG_FINISH;
			}
			break;

		default:
			stStage = STG_FINISH;
			break;
	}

	if ( stStage == STG_FINISH ) {
		ST_Finish();
	}
}

/*
===============
CL_SelfTest_f
===============
*/
static void CL_SelfTest_f( void )
{
	qboolean full = ( Cmd_Argc() > 1 && !Q_stricmp( Cmd_Argv( 1 ), "full" ) );

	if ( stRunning ) {
		Com_Printf( "selftest: прогон уже идёт\n" );
		return;
	}

	stNumRows = 0;
	stPassed = stFailed = stSkipped = 0;
	stRunning = qtrue;

#if defined(__APPLE__) && TARGET_OS_IPHONE
	IOSBridge_SelfTestBegin( full ? "Полный прогон" : "Основной прогон" );
#endif

	Com_Printf( "\nselftest: %s\n", full ? "полный прогон" : "основной прогон" );

	ST_RunBasic( full );

	if ( !full ) {
		ST_Finish();
		return;
	}

	// The map the full run plays on. Deliberately one of the stock ones, so a
	// run means the same thing on every copy of the game.
	stStage       = STG_LOADING;
	stStageSince  = Sys_Milliseconds();
	stStageFrames = 0;

	// Before the map, and it has to be before the map. Attaching a virtual SDL
	// device does not make the engine open it -- the joystick layer opens what
	// is there when it starts -- and the thing that starts it again is the
	// input restart a map load performs. Attached afterwards the device sits in
	// the list unopened, every axis reads zero, and three quarters of the table
	// fails for want of a stick.
	Cvar_Set( "in_padEmulate", "1" );

#ifdef IORTCW_MP_BUILD
	Cbuf_AddText( "devmap mp_beach\n" );
#else
	Cbuf_AddText( "spdevmap escape1\n" );
#endif
}

/*
===============
CL_SelfTest_Init

Called from the input layer's own start-up, which is the one place both trees
share a file -- SP and MP have diverged everywhere else, and a registration put
in either tree's cl_main.c would have to be kept in step by hand.
===============
*/
void CL_SelfTest_Init( void )
{
	static qboolean registered;

	if ( registered ) {
		// IN_Init runs again on every vid_restart.
		return;
	}
	registered = qtrue;

	Cmd_AddCommand( "selftest", CL_SelfTest_f );
}
