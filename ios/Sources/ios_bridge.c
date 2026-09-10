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
	return Q3_VERSION " " PLATFORM_STRING "-" ARCH_STRING;
}

#define MAX_LAUNCHER_SETTINGS 64
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
IOSBridge_SetCvar

Recorded for the generated config, and applied live too when the engine is
already up (the launcher can be reopened mid-game).
==============
*/
void IOSBridge_SetCvar( const char *name, const char *value )
{
	int i;

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
IOSBridge_GetCvar
==============
*/
const char *IOSBridge_GetCvar( const char *name )
{
	int i;

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
