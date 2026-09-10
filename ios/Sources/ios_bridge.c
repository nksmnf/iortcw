/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/
// ios_bridge.c -- engine side of the launcher bridge.

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/sys/sys_local.h"
#include "ios_bridge.h"

#include "../../SP/code/zlib-1.2.11/unzip.h"

#include <stdio.h>
#include <unistd.h>

/*
==============
IOSBridge_ScanData

What the player actually has, read from the pk3 central directories.

"All five files are present" is a weak thing to tell someone who has just spent
ten minutes copying 637MB: it does not distinguish the real data from five
files of the right names. Counting the maps does, and it is nearly free -- a zip
directory is a few hundred kilobytes at the end of the file, so this never
touches the 300MB of content in front of it.
==============
*/
static qboolean dataScanned;
static int      dataMaps;
static int      dataFiles;
static double   dataMegabytes;

static void IOSBridge_ScanPak( const char *path )
{
	unzFile uf = unzOpen( path );
	unz_global_info gi;
	int i;

	if ( !uf ) {
		return;
	}

	if ( unzGetGlobalInfo( uf, &gi ) != UNZ_OK ) {
		unzClose( uf );
		return;
	}

	for ( i = 0; i < (int)gi.number_entry; i++ ) {
		char name[256];   // MAX_ZPATH, which files.c keeps to itself
		unz_file_info info;

		if ( unzGetCurrentFileInfo( uf, &info, name, sizeof( name ),
				NULL, 0, NULL, 0 ) != UNZ_OK ) {
			break;
		}

		dataFiles++;
		dataMegabytes += (double)info.uncompressed_size / ( 1024.0 * 1024.0 );

		if ( !Q_stricmpn( name, "maps/", 5 ) ) {
			const char *ext = strrchr( name, '.' );

			if ( ext && !Q_stricmp( ext, ".bsp" ) ) {
				dataMaps++;
			}
		}

		if ( unzGoToNextFile( uf ) != UNZ_OK ) {
			break;
		}
	}

	unzClose( uf );
}

bool IOSBridge_ScanData( bool rescan )
{
	static const char *paks[] = {
		"pak0.pk3", "sp_pak1.pk3", "sp_pak2.pk3", "sp_pak3.pk3", "sp_pak4.pk3"
	};
	const char *dir;
	size_t i;

	if ( dataScanned && !rescan ) {
		return dataMaps > 0;
	}

	dataScanned = qtrue;
	dataMaps = 0;
	dataFiles = 0;
	dataMegabytes = 0.0;

	dir = Sys_IOS_DataPath();

	if ( !dir || !*dir ) {
		return false;
	}

	for ( i = 0; i < ARRAY_LEN( paks ); i++ ) {
		char path[MAX_OSPATH];

		Com_sprintf( path, sizeof( path ), "%s/main/%s", dir, paks[i] );
		IOSBridge_ScanPak( path );
	}

	return dataMaps > 0;
}

int    IOSBridge_DataMaps( void )      { return dataMaps; }
int    IOSBridge_DataFiles( void )     { return dataFiles; }
double IOSBridge_DataMegabytes( void ) { return dataMegabytes; }

const char *IOSBridge_EngineVersion( void )
{
	// PLATFORM_STRING is already OS_STRING "-" ARCH_STRING, so adding the
	// architecture again produced "ios-arm64-arm64".
	return Q3_VERSION " " PLATFORM_STRING;
}

// Starting a mission from the launcher writes 68 settings -- 25 from the
// graphics preset and 43 of the launcher's own -- so 64 was already short, and
// what fell off the end was dropped with a message that goes to a log file
// nobody reads. It was g_missionLoadout, the last one set and the one that
// decides whether the player arrives at that mission carrying anything.
#define MAX_LAUNCHER_SETTINGS 128
#define MAX_LAUNCHER_BINDS    64

typedef struct {
	char name[64];
	char value[128];
} launcherPair_t;

static launcherPair_t launcherSettings[MAX_LAUNCHER_SETTINGS];
static int            numLauncherSettings;

static launcherPair_t launcherBinds[MAX_LAUNCHER_BINDS];
static int            numLauncherBinds;

static qboolean launcherDone;
static qboolean launcherConfigRead;
static char     launcherCommandLine[1024];
static char     launcherStartupCommand[256];
static char     bridgeScratch[MAX_OSPATH];

/*
==============
IOSBridge_DataPath
==============
*/
const char *IOSBridge_DataPath( void )
{
	return Sys_IOS_DataPath();
}

/*
==============
IOSBridge_HasGameData
==============
*/
bool IOSBridge_HasGameData( void )
{
	return Sys_IOS_HasGameData() ? true : false;
}

/*
==============
IOSBridge_GameDataMask

Bit per expected pk3, so the launcher can show a checklist rather than a single
yes/no -- the common failure is copying some of the files but not all.
==============
*/
int IOSBridge_GameDataMask( void )
{
	static const char *files[] = {
		"pak0.pk3", "sp_pak1.pk3", "sp_pak2.pk3", "sp_pak3.pk3", "sp_pak4.pk3"
	};
	int mask = 0;
	int i;

	for ( i = 0; i < (int)ARRAY_LEN( files ); i++ ) {
		char path[MAX_OSPATH];

		Com_sprintf( path, sizeof( path ), "%s/main/%s",
			Sys_IOS_DataPath(), files[i] );

		if ( access( path, R_OK ) == 0 ) {
			mask |= ( 1 << i );
		}
	}

	return mask;
}

/*
==============
IOSBridge_ImportLooseData
==============
*/
int IOSBridge_ImportLooseData( void )
{
	return Sys_IOS_ImportLooseData();
}

/*
==============
IOSBridge_ReadConfig

Load Documents/main/ios_launcher.cfg back into the tables above.

The launcher runs from main() before Com_Init, so there is no cvar system to ask
yet and IOSBridge_GetCvar had nothing to answer with: every setting came back
empty. The launcher read that as "never configured", showed its built-in
defaults, and then -- because pressing Play writes the whole set out again --
committed those defaults over what the player had actually chosen. Settings did
not merely fail to appear on a cold start, they were destroyed by it.

Reading our own generated config back fixes that at the source: it is the same
data the engine is about to exec, so the launcher opens on the state the game is
about to start in, and rewriting it is a no-op instead of a reset.

Only our own file is read. wolfconfig.cfg holds several hundred archived cvars
and is exec'd first, so everything it says about a setting the launcher owns is
overridden a moment later by this file -- showing its values would mean showing
the player something the engine is about to discard.

stdio and COM_ParseExt rather than the filesystem layer, for the same reason
IOSBridge_WriteConfig uses stdio: FS_Startup has not run. The tokeniser is pure
code and safe this early.
==============
*/
static void IOSBridge_ReadConfig( void )
{
	char path[MAX_OSPATH];
	FILE *f;
	long length;
	char *buffer, *text;

	if ( launcherConfigRead ) {
		return;
	}

	// Set before parsing, not after: the loop below goes through
	// IOSBridge_SetCvar, which calls straight back in here.
	launcherConfigRead = qtrue;

	// With the engine up, its own cvars are the fresher source and the tables
	// have already been filled by the cold start that preceded it.
	if ( com_fullyInitialized ) {
		return;
	}

	Com_sprintf( path, sizeof( path ), "%s/main/ios_launcher.cfg",
		Sys_IOS_DataPath() );

	f = fopen( path, "rb" );
	if ( !f ) {
		return;		// first run: nothing to restore, defaults are correct
	}

	fseek( f, 0, SEEK_END );
	length = ftell( f );
	fseek( f, 0, SEEK_SET );

	// A config this size is not one of ours, and reading it would only find
	// nonsense to feed to the launcher.
	if ( length <= 0 || length > 256 * 1024 ) {
		fclose( f );
		return;
	}

	buffer = malloc( length + 2 );
	if ( !buffer ) {
		fclose( f );
		return;
	}

	length = (long)fread( buffer, 1, length, f );
	fclose( f );

	// SkipRestOfLine walks past the terminator when the last line has no
	// newline of its own, and the next COM_ParseExt then reads off the end of
	// the buffer. One appended newline is cheaper than not trusting it.
	buffer[length] = '\n';
	buffer[length + 1] = '\0';

	COM_BeginParseSession( "ios_launcher.cfg" );
	text = buffer;

	while ( text ) {
		char name[64];
		char *token = COM_ParseExt( &text, qtrue );
		qboolean isBind;

		if ( !token[0] ) {
			break;		// end of file
		}

		isBind = !Q_stricmp( token, "bind" );

		// Anything else on a line is skipped rather than guessed at: the file
		// is generated, but it sits in Documents where anyone can edit it.
		if ( isBind || !Q_stricmp( token, "seta" ) ) {
			// COM_ParseExt hands back a pointer to its own buffer, so the name
			// has to be copied before the value is parsed over the top of it.
			Q_strncpyz( name, COM_ParseExt( &text, qfalse ), sizeof( name ) );
			token = COM_ParseExt( &text, qfalse );

			if ( name[0] ) {
				if ( isBind ) {
					IOSBridge_SetBinding( name, token );
				} else {
					IOSBridge_SetCvar( name, token );
				}
			}
		}

		if ( text ) {
			SkipRestOfLine( &text );
		}
	}

	free( buffer );

	Com_Printf( "Launcher: restored %d settings and %d binds from ios_launcher.cfg\n",
		numLauncherSettings, numLauncherBinds );
}

/*
==============
IOSBridge_SetCvar

Recorded for the generated config, and applied live too when the engine is
already up (the launcher can be reopened mid-game).
==============
*/
void IOSBridge_SetCvar( const char *name, const char *value )
{
	int i;

	IOSBridge_ReadConfig();

	if ( !name || !value ) {
		return;
	}

	for ( i = 0; i < numLauncherSettings; i++ ) {
		if ( !Q_stricmp( launcherSettings[i].name, name ) ) {
			break;
		}
	}

	if ( i == numLauncherSettings ) {
		if ( numLauncherSettings >= MAX_LAUNCHER_SETTINGS ) {
			Com_Printf( "Launcher: too many settings, dropping %s\n", name );
			return;
		}
		numLauncherSettings++;
		Q_strncpyz( launcherSettings[i].name, name, sizeof( launcherSettings[i].name ) );
	}

	Q_strncpyz( launcherSettings[i].value, value, sizeof( launcherSettings[i].value ) );

	if ( com_fullyInitialized ) {
		Cvar_Set( name, value );
	}
}

/*
==============
IOSBridge_ForgetCvar

Stop writing a setting, leaving whatever value it has to the engine.

This is what makes a default a default rather than an order. The launcher seeds
a handful of settings it has no control for -- the crosshair shape is one -- and
anything left in the generated config is re-applied on every single launch,
after wolfconfig.cfg, so it would silently undo the player's choice every time
they picked something else in the game's own menus. Dropping the setting once it
has been seeded hands it back: the engine archives it like any other cvar and
the launcher never mentions it again.
==============
*/
void IOSBridge_ForgetCvar( const char *name )
{
	int i;

	IOSBridge_ReadConfig();

	if ( !name ) {
		return;
	}

	for ( i = 0; i < numLauncherSettings; i++ ) {
		if ( !Q_stricmp( launcherSettings[i].name, name ) ) {
			// Closing the gap rather than swapping the last entry into it keeps
			// the generated config in a stable order, which matters only to
			// whoever ends up reading it in Files.app -- but that is the point
			// of a text config.
			memmove( &launcherSettings[i], &launcherSettings[i + 1],
				( numLauncherSettings - i - 1 ) * sizeof( launcherSettings[0] ) );
			numLauncherSettings--;
			return;
		}
	}
}

/*
==============
IOSBridge_GetCvar
==============
*/
const char *IOSBridge_GetCvar( const char *name )
{
	int i;

	IOSBridge_ReadConfig();

	if ( !name ) {
		return "";
	}

	// The launcher's own pending value wins over the engine's, so the UI shows
	// what the user just chose rather than what is still live.
	for ( i = 0; i < numLauncherSettings; i++ ) {
		if ( !Q_stricmp( launcherSettings[i].name, name ) ) {
			return launcherSettings[i].value;
		}
	}

	if ( com_fullyInitialized ) {
		Q_strncpyz( bridgeScratch, Cvar_VariableString( name ), sizeof( bridgeScratch ) );
		return bridgeScratch;
	}

	return "";
}

/*
==============
IOSBridge_SetBinding
==============
*/
void IOSBridge_SetBinding( const char *keyName, const char *action )
{
	int i;

	IOSBridge_ReadConfig();

	if ( !keyName || !action ) {
		return;
	}

	for ( i = 0; i < numLauncherBinds; i++ ) {
		if ( !Q_stricmp( launcherBinds[i].name, keyName ) ) {
			break;
		}
	}

	if ( i == numLauncherBinds ) {
		if ( numLauncherBinds >= MAX_LAUNCHER_BINDS ) {
			Com_Printf( "Launcher: too many binds, dropping %s\n", keyName );
			return;
		}
		numLauncherBinds++;
		Q_strncpyz( launcherBinds[i].name, keyName, sizeof( launcherBinds[i].name ) );
	}

	Q_strncpyz( launcherBinds[i].value, action, sizeof( launcherBinds[i].value ) );

	if ( com_fullyInitialized ) {
		int keynum = Key_StringToKeynum( (char *)keyName );

		if ( keynum >= 0 ) {
			Key_SetBinding( keynum, action );
		}
	}
}

/*
==============
IOSBridge_GetBinding
==============
*/
const char *IOSBridge_GetBinding( const char *keyName )
{
	int i;

	IOSBridge_ReadConfig();

	if ( !keyName ) {
		return "";
	}

	for ( i = 0; i < numLauncherBinds; i++ ) {
		if ( !Q_stricmp( launcherBinds[i].name, keyName ) ) {
			return launcherBinds[i].value;
		}
	}

	if ( com_fullyInitialized ) {
		int keynum = Key_StringToKeynum( (char *)keyName );

		if ( keynum >= 0 ) {
			char *bind = Key_GetBinding( keynum );
			return bind ? bind : "";
		}
	}

	return "";
}

/*
==============
IOSBridge_WriteConfig

Writes Documents/main/ios_launcher.cfg. The engine execs it after default.cfg
and wolfconfig.cfg, so it is the last word on anything it mentions.

Written with stdio rather than the filesystem layer because the launcher runs
before FS_Startup.
==============
*/
void IOSBridge_WriteConfig( void )
{
	char path[MAX_OSPATH];
	FILE *f;
	int i;

	// Never overwrite the stored config with a set that has not been seeded
	// from it: everything it does not mention is lost the moment this runs.
	IOSBridge_ReadConfig();

	Com_sprintf( path, sizeof( path ), "%s/main/ios_launcher.cfg",
		Sys_IOS_DataPath() );

	f = fopen( path, "w" );
	if ( !f ) {
		Com_Printf( "Launcher: cannot write %s\n", path );
		return;
	}

	fprintf( f, "// Generated by the iORTCW launcher -- do not edit.\n" );
	fprintf( f, "// Exec'd after wolfconfig.cfg, so these settings win.\n\n" );

	for ( i = 0; i < numLauncherSettings; i++ ) {
		fprintf( f, "seta %s \"%s\"\n", launcherSettings[i].name, launcherSettings[i].value );
	}

	if ( numLauncherBinds ) {
		fprintf( f, "\n" );
		for ( i = 0; i < numLauncherBinds; i++ ) {
			fprintf( f, "bind %s \"%s\"\n", launcherBinds[i].name, launcherBinds[i].value );
		}
	}

	fclose( f );

	Com_Printf( "Launcher: wrote %d settings and %d binds to ios_launcher.cfg\n",
		numLauncherSettings, numLauncherBinds );
}

/*
==============
IOSBridge_SetStartupCommand
==============
*/
void IOSBridge_SetStartupCommand( const char *command )
{
	Q_strncpyz( launcherStartupCommand, command ? command : "",
		sizeof( launcherStartupCommand ) );
}

/*
==============
IOSBridge_BuildCommandLine

Arguments that cannot go in the config because they are read too early:
com_hunkMegs is consumed by Com_InitHunkMemory before any exec, and net_enabled
has to be off from the start or iOS raises the Local Network permission prompt
for a single-player game.
==============
*/
const char *IOSBridge_BuildCommandLine( void )
{
	const char *hunk = IOSBridge_GetCvar( "com_hunkMegs" );

	// logfile 2 is on by default and flushes each line. On a sideloaded build
	// with no debugger attached, Documents/main/rtcwconsole.log is the only way
	// to see what the engine did, and it is readable from Files.app.
	Com_sprintf( launcherCommandLine, sizeof( launcherCommandLine ),
		"+set com_hunkMegs %s +set net_enabled 0 +set logfile 2",
		( hunk && hunk[0] ) ? hunk : "512" );

	// Appended last so it runs after everything else is configured.
	if ( launcherStartupCommand[0] ) {
		Q_strcat( launcherCommandLine, sizeof( launcherCommandLine ), " +" );
		Q_strcat( launcherCommandLine, sizeof( launcherCommandLine ),
			launcherStartupCommand );
	}

	return launcherCommandLine;
}

/*
==============
IOSBridge_LauncherFinished
==============
*/
void IOSBridge_LauncherFinished( void )
{
	launcherDone = qtrue;
}

/*
==============
Sys_IOS_LauncherIsFinished

Read by the runloop pump on the C side.
==============
*/
bool Sys_IOS_LauncherIsFinished( void )
{
	return launcherDone ? true : false;
}

/*
==============
Sys_IOS_LauncherReset
==============
*/
void Sys_IOS_LauncherReset( void )
{
	launcherDone = qfalse;
}
