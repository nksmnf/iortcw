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

#include "ios_engine.h"
#include "ios_bridge.h"

#include <dirent.h>
#include <stdio.h>
#include <sys/stat.h>
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

RTCW ships as two independent sets of data and a player may well have one and
not the other, so both are tracked. What a set is made of is decided here and
not in the launcher, because this side already has to know what the engine
refuses to start without.
==============
*/
typedef struct {
	const char *name;
	qboolean required;		// the engine will not start without it
} dataFileDef_t;

typedef struct {
	qboolean present;		// the file is in main/
	qboolean scanned;		// and its central directory was read whole
	off_t size;
	time_t mtime;
	int maps;
	int mpMaps;
	int entries;
	double megabytes;
} dataFileScan_t;

// The campaign. All five are required: SP's FS_CheckSPPaks calls Com_Error
// unless sp_pak1 through sp_pak4 are all present, and pak0.pk3 is checked
// before that. sp_pak4.pk3 came with the Game of the Year edition, which is
// why README.md's older list of four is not enough for this engine.
static const dataFileDef_t campaignFiles[] = {
	{ "pak0.pk3", qtrue },
	{ "sp_pak1.pk3", qtrue },
	{ "sp_pak2.pk3", qtrue },
	{ "sp_pak3.pk3", qtrue },
	{ "sp_pak4.pk3", qtrue }
};

// Multiplayer.
//
// pak0.pk3 is the retail media rather than campaign data -- both halves of the
// game load it -- so it is listed in both sets and, below, read only once.
//
// mp_pak0 through mp_pak5 are required because MP's FS_CheckMPPaks calls
// Com_Error naming the 1.41 point release unless all six are there. Only the
// first three came on the disc (13.11.2001); 3, 4 and 5 arrive with the March,
// May and October 2002 point releases, so a shop-bought copy alone will not do.
//
// mp_bin.pk3 holds the original x86 cgame and ui modules. This build has its
// own and cannot run those anyway, but a pure server references that pak and a
// client without it fails the check -- worth having, not worth refusing to
// start over.
//
// The mp_pakmaps packs are one bonus map each, added between 1.1 (trenchtoast,
// 18.12.2001) and 1.4 (dam and rocket, 02.06.2002). The game starts and plays
// without them; they only decide whether the player can join a server running
// that map. Optional, but part of the complete 1.41 install.
static const dataFileDef_t multiplayerFiles[] = {
	{ "pak0.pk3", qtrue },
	{ "mp_pak0.pk3", qtrue },
	{ "mp_pak1.pk3", qtrue },
	{ "mp_pak2.pk3", qtrue },
	{ "mp_pak3.pk3", qtrue },
	{ "mp_pak4.pk3", qtrue },
	{ "mp_pak5.pk3", qtrue },
	{ "mp_bin.pk3", qfalse },
	{ "mp_pakmaps0.pk3", qfalse },
	{ "mp_pakmaps1.pk3", qfalse },
	{ "mp_pakmaps2.pk3", qfalse },
	{ "mp_pakmaps3.pk3", qfalse },
	{ "mp_pakmaps4.pk3", qfalse },
	{ "mp_pakmaps5.pk3", qfalse },
	{ "mp_pakmaps6.pk3", qfalse }
};

// Name shapes id used for this set's paks: <prefix><number>.pk3. A file that
// fits one of them but is not in the manifest above is one we do not
// understand -- a point release newer than this code, or a renamed pak -- and
// it is why a set can be complete and still not be the recommended one. A mod
// dropped into main/ matches none of these and is left alone, which is the
// point: only files pretending to be id's are questioned.
static const char *campaignShapes[] = { "pak", "sp_pak", NULL };
static const char *multiplayerShapes[] = { "mp_pak", "mp_pakmaps", NULL };

typedef struct {
	const dataFileDef_t *def;
	dataFileScan_t *scan;
	const char **shapes;
	int numFiles;
	qboolean mpMapsOnly;

	int maps;
	int entries;
	double megabytes;
	qboolean playable;		// every required file present and readable
	qboolean complete;		// ... and every optional one too
	qboolean strayPak;		// something id-shaped in main/ that we do not know
} dataSet_t;

static dataFileScan_t campaignScan[ARRAY_LEN( campaignFiles )];
static dataFileScan_t multiplayerScan[ARRAY_LEN( multiplayerFiles )];

static qboolean dataScanned;

static dataSet_t dataSets[IOS_DATA_SET_COUNT] = {
	{ campaignFiles, campaignScan, campaignShapes,
		(int)ARRAY_LEN( campaignFiles ), qfalse,
		0, 0, 0.0, qfalse, qfalse, qfalse },
	{ multiplayerFiles, multiplayerScan, multiplayerShapes,
		(int)ARRAY_LEN( multiplayerFiles ), qtrue,
		0, 0, 0.0, qfalse, qfalse, qfalse }
};

/*
==============
IOSBridge_ScanPak

Counts one pk3 by walking its central directory.
==============
*/
static unsigned IOSBridge_LE16( const unsigned char *p )
{
	return (unsigned)p[0] | ( (unsigned)p[1] << 8 );
}

static unsigned IOSBridge_LE32( const unsigned char *p )
{
	return (unsigned)p[0] | ( (unsigned)p[1] << 8 )
		| ( (unsigned)p[2] << 16 ) | ( (unsigned)p[3] << 24 );
}

static void IOSBridge_ScanPak( const char *path, dataFileScan_t *scan )
{
	// The zip central directory, read with stdio rather than through the
	// engine's unzip.
	//
	// unzOpen allocates with Z_Malloc, and the launcher runs before Com_Init,
	// so in the multiplayer engine -- where Z_Malloc really is the zone
	// allocator -- that dereferences a mainzone that does not exist yet and
	// takes the process down on the first pk3 it looks at. (The campaign engine
	// gets away with it only because its Z_Malloc is a plain malloc.)
	//
	// Everything wanted here is in the central directory: how many entries,
	// what each is called, and how big it is uncompressed. That is a short
	// read, so doing it directly is both the fix and less work than opening
	// the archive properly.
	// 64k of comment plus the record itself, off the stack rather than on it.
	enum { TAIL_MAX = 66000 };
	unsigned char *buf;
	FILE *f = fopen( path, "rb" );
	long size, tailLen, i;
	long eocd = -1;
	unsigned entries, cdOffset;
	unsigned char *cd = NULL;
	unsigned pos;

	if ( !f ) {
		return;
	}

	if ( fseek( f, 0, SEEK_END ) != 0 || ( size = ftell( f ) ) < 22 ) {
		fclose( f );
		return;
	}

	buf = (unsigned char *)malloc( TAIL_MAX );
	if ( !buf ) {
		fclose( f );
		return;
	}

	// The end-of-central-directory record is last, but a trailing comment of up
	// to 64k may follow it, so the search window is that plus the record.
	tailLen = size < (long)TAIL_MAX ? size : (long)TAIL_MAX;
	if ( fseek( f, size - tailLen, SEEK_SET ) != 0
		|| fread( buf, 1, (size_t)tailLen, f ) != (size_t)tailLen ) {
		free( buf );
		fclose( f );
		return;
	}

	for ( i = tailLen - 22; i >= 0; i-- ) {
		if ( IOSBridge_LE32( buf + i ) == 0x06054b50u ) {
			eocd = i;
			break;
		}
	}

	if ( eocd < 0 ) {
		// No end-of-central-directory record yet, which is what a pk3 halfway
		// through being copied looks like. Left unscanned so the next pass
		// tries again rather than believing a count of zero.
		free( buf );
		fclose( f );
		return;
	}

	entries  = IOSBridge_LE16( buf + eocd + 10 );
	cdOffset = IOSBridge_LE32( buf + eocd + 16 );

	if ( !entries || cdOffset >= (unsigned)size ) {
		free( buf );
		fclose( f );
		return;
	}

	{
		long cdLen = (long)IOSBridge_LE32( buf + eocd + 12 );

		if ( cdLen <= 0 || cdOffset + (unsigned)cdLen > (unsigned)size ) {
			free( buf );
			fclose( f );
			return;
		}

		cd = (unsigned char *)malloc( (size_t)cdLen );
		if ( !cd ) {
			free( buf );
			fclose( f );
			return;
		}

		if ( fseek( f, (long)cdOffset, SEEK_SET ) != 0
			|| fread( cd, 1, (size_t)cdLen, f ) != (size_t)cdLen ) {
			free( cd );
			free( buf );
			fclose( f );
			return;
		}

		pos = 0;
		for ( i = 0; i < (long)entries; i++ ) {
			char name[256];   // MAX_ZPATH, which files.c keeps to itself
			unsigned uncompressed, nameLen, extraLen, commentLen, copy;

			if ( pos + 46 > (unsigned)cdLen
				|| IOSBridge_LE32( cd + pos ) != 0x02014b50u ) {
				break;
			}

			uncompressed = IOSBridge_LE32( cd + pos + 24 );
			nameLen      = IOSBridge_LE16( cd + pos + 28 );
			extraLen     = IOSBridge_LE16( cd + pos + 30 );
			commentLen   = IOSBridge_LE16( cd + pos + 32 );

			if ( pos + 46 + nameLen > (unsigned)cdLen ) {
				break;
			}

			copy = nameLen < sizeof( name ) - 1 ? nameLen : sizeof( name ) - 1;
			memcpy( name, cd + pos + 46, copy );
			name[copy] = '\0';

			scan->entries++;
			scan->megabytes += (double)uncompressed / ( 1024.0 * 1024.0 );

			if ( !Q_stricmpn( name, "maps/", 5 ) ) {
				const char *ext = strrchr( name, '.' );

				if ( ext && !Q_stricmp( ext, ".bsp" ) ) {
					scan->maps++;

					// Every multiplayer map id shipped is called mp_something and
					// no campaign map is. pak0.pk3 belongs to both sets and holds
					// 32 campaign maps; counted under "multiplayer" they would
					// promise the player three times the maps they can join a
					// server on.
					if ( !Q_stricmpn( name + 5, "mp_", 3 ) ) {
						scan->mpMaps++;
					}
				}
			}

			pos += 46 + nameLen + extraLen + commentLen;
		}

		free( cd );
	}

	free( buf );
	fclose( f );

	scan->scanned = qtrue;
}

/*
==============
IOSBridge_ReuseScan

pak0.pk3 belongs to both sets, and at 4775 entries it has by far the largest
central directory of the twenty. Reading it once per set would double the only
cost this whole thing has, for an answer that cannot differ.
==============
*/
static const dataFileScan_t *IOSBridge_ReuseScan( const char *name,
		const struct stat *st )
{
	int s, i;

	for ( s = 0; s < IOS_DATA_SET_COUNT; s++ ) {
		const dataSet_t *set = &dataSets[s];

		for ( i = 0; i < set->numFiles; i++ ) {
			const dataFileScan_t *scan = &set->scan[i];

			if ( Q_stricmp( set->def[i].name, name ) ) {
				continue;
			}

			if ( scan->scanned && scan->size == st->st_size
					&& scan->mtime == st->st_mtime ) {
				return scan;
			}
		}
	}

	return NULL;
}

/*
==============
IOSBridge_ScanSet

Re-reads only what has changed since the last pass.

The launcher rescans once a second while the user copies files in, and there
are twenty central directories across the two sets -- over 150MB of multiplayer
data on top of the campaign's 637MB. Opening all of them at that rate would
make the wait it is reporting on measurably worse. Size and mtime decide, so a
file still being written is re-read next pass and a finished one never again.
==============
*/
static void IOSBridge_ScanSet( dataSet_t *set, const char *dir )
{
	int i;

	set->maps = 0;
	set->entries = 0;
	set->megabytes = 0.0;
	set->playable = qtrue;
	set->complete = qtrue;

	for ( i = 0; i < set->numFiles; i++ ) {
		dataFileScan_t *scan = &set->scan[i];
		char path[MAX_OSPATH];
		struct stat st;

		Com_sprintf( path, sizeof( path ), "%s/main/%s", dir, set->def[i].name );

		if ( stat( path, &st ) != 0 ) {
			memset( scan, 0, sizeof( *scan ) );
		} else if ( !scan->scanned || scan->size != st.st_size
				|| scan->mtime != st.st_mtime ) {
			const dataFileScan_t *shared =
				IOSBridge_ReuseScan( set->def[i].name, &st );

			memset( scan, 0, sizeof( *scan ) );

			if ( shared ) {
				*scan = *shared;
			} else {
				scan->size = st.st_size;
				scan->mtime = st.st_mtime;
				IOSBridge_ScanPak( path, scan );
			}

			scan->present = qtrue;
		}

		if ( !scan->scanned ) {
			// A required file that is there but unreadable is worth no more
			// than a missing one, and during a copy that is exactly what it is.
			if ( set->def[i].required ) {
				set->playable = qfalse;
			}
			set->complete = qfalse;
			continue;
		}

		set->maps += set->mpMapsOnly ? scan->mpMaps : scan->maps;
		set->entries += scan->entries;
		set->megabytes += scan->megabytes;
	}
}

/*
==============
IOSBridge_MatchNumbered

<prefix><digits>.pk3, and nothing else. "mp_pakmaps0.pk3" does not match the
prefix "mp_pak" because what follows it has to be a number.
==============
*/
static qboolean IOSBridge_MatchNumbered( const char *name, const char *prefix )
{
	size_t len = strlen( prefix );
	const char *p;

	if ( strlen( name ) <= len || Q_stricmpn( name, prefix, (int)len ) ) {
		return qfalse;
	}

	p = name + len;

	if ( *p < '0' || *p > '9' ) {
		return qfalse;
	}

	while ( *p >= '0' && *p <= '9' ) {
		p++;
	}

	return Q_stricmp( p, ".pk3" ) ? qfalse : qtrue;
}

/*
==============
IOSBridge_IsStrayPak
==============
*/
static qboolean IOSBridge_IsStrayPak( const dataSet_t *set, const char *name )
{
	int i;

	for ( i = 0; set->shapes[i]; i++ ) {
		if ( IOSBridge_MatchNumbered( name, set->shapes[i] ) ) {
			break;
		}
	}

	if ( !set->shapes[i] ) {
		return qfalse;		// not shaped like ours: a mod, or the other set
	}

	for ( i = 0; i < set->numFiles; i++ ) {
		if ( !Q_stricmp( set->def[i].name, name ) ) {
			return qfalse;
		}
	}

	return qtrue;
}

/*
==============
IOSBridge_ScanStrays

One readdir of main/, which holds a couple of dozen entries. Cheap enough to
repeat with every rescan, and it is the only way to answer "and nothing else"
rather than just "nothing missing".
==============
*/
static void IOSBridge_ScanStrays( const char *dir )
{
	char path[MAX_OSPATH];
	DIR *d;
	struct dirent *entry;
	int s;

	for ( s = 0; s < IOS_DATA_SET_COUNT; s++ ) {
		dataSets[s].strayPak = qfalse;
	}

	Com_sprintf( path, sizeof( path ), "%s/main", dir );

	d = opendir( path );
	if ( !d ) {
		return;
	}

	while ( ( entry = readdir( d ) ) != NULL ) {
		for ( s = 0; s < IOS_DATA_SET_COUNT; s++ ) {
			if ( IOSBridge_IsStrayPak( &dataSets[s], entry->d_name ) ) {
				dataSets[s].strayPak = qtrue;
			}
		}
	}

	closedir( d );
}

bool IOSBridge_ScanData( bool rescan )
{
	const char *dir;
	int s;

	if ( dataScanned && !rescan ) {
		return dataSets[IOS_DATA_SET_CAMPAIGN].maps > 0;
	}

	dataScanned = qtrue;

	dir = Sys_IOS_DataPath();

	if ( !dir || !*dir ) {
		return false;
	}

	// Campaign first, so multiplayer's pak0.pk3 finds it already read.
	for ( s = 0; s < IOS_DATA_SET_COUNT; s++ ) {
		IOSBridge_ScanSet( &dataSets[s], dir );
	}

	IOSBridge_ScanStrays( dir );

	return dataSets[IOS_DATA_SET_CAMPAIGN].maps > 0;
}

/*
==============
IOSBridge_DataSet

Every per-set getter goes through here, so a launcher that asks before it has
called IOSBridge_ScanData gets an answer rather than zeroes. The scan is
cached, so after the first one this costs nothing.
==============
*/
static const dataSet_t *IOSBridge_DataSet( int set )
{
	if ( set < 0 || set >= IOS_DATA_SET_COUNT ) {
		return NULL;
	}

	IOSBridge_ScanData( false );

	return &dataSets[set];
}

int IOSBridge_SetFileCount( int set )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	return s ? s->numFiles : 0;
}

const char *IOSBridge_SetFileName( int set, int index )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	if ( !s || index < 0 || index >= s->numFiles ) {
		return "";
	}

	return s->def[index].name;
}

bool IOSBridge_SetFilePresent( int set, int index )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	if ( !s || index < 0 || index >= s->numFiles ) {
		return false;
	}

	return s->scan[index].present ? true : false;
}

bool IOSBridge_SetFileRequired( int set, int index )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	if ( !s || index < 0 || index >= s->numFiles ) {
		return false;
	}

	return s->def[index].required ? true : false;
}

int IOSBridge_SetMaps( int set )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	return s ? s->maps : 0;
}

int IOSBridge_SetFiles( int set )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	return s ? s->entries : 0;
}

double IOSBridge_SetMegabytes( int set )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	return s ? s->megabytes : 0.0;
}

bool IOSBridge_SetIsPlayable( int set )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	return ( s && s->playable ) ? true : false;
}

/*
==============
IOSBridge_SetIsRecommended

"Exactly what you should have", which is a stricter question than "will it
start". Every file of the set is present and readable, optional ones included
-- that is what makes it the complete 1.41-era install rather than merely a
startable one -- and there is nothing beside them wearing an id pak's name that
this code does not recognise.
==============
*/
bool IOSBridge_SetIsRecommended( int set )
{
	const dataSet_t *s = IOSBridge_DataSet( set );

	return ( s && s->complete && !s->strayPak ) ? true : false;
}

// Kept meaning the campaign, because everything from the Play button down is
// written against them.
int    IOSBridge_DataMaps( void )      { return dataSets[IOS_DATA_SET_CAMPAIGN].maps; }
int    IOSBridge_DataFiles( void )     { return dataSets[IOS_DATA_SET_CAMPAIGN].entries; }
double IOSBridge_DataMegabytes( void ) { return dataSets[IOS_DATA_SET_CAMPAIGN].megabytes; }

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
static char     launcherExtraArgs[512];
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
	int mask = 0;
	int i;

	// Straight off the campaign manifest, so the bit order the launcher has
	// always read stays tied to the list this file scans.
	for ( i = 0; i < (int)ARRAY_LEN( campaignFiles ); i++ ) {
		char path[MAX_OSPATH];

		Com_sprintf( path, sizeof( path ), "%s/main/%s",
			Sys_IOS_DataPath(), campaignFiles[i].name );

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
is latched.

net_enabled is 0 in the campaign build so a single-player game never raises the
Local Network permission prompt -- a game with no network asking for the local
one looks exactly like something to be suspicious of. Multiplayer needs it on,
and 1 means IPv4 only, which is all the masters have: not one of the three has
an AAAA record.
==============
*/
const char *IOSBridge_BuildCommandLine( void )
{
	const char *hunk = IOSBridge_GetCvar( "com_hunkMegs" );

	// logfile 2 is on by default and flushes each line. On a sideloaded build
	// with no debugger attached, Documents/main/rtcwconsole.log is the only way
	// to see what the engine did, and it is readable from Files.app.
	Com_sprintf( launcherCommandLine, sizeof( launcherCommandLine ),
		"+set com_hunkMegs %s +set net_enabled %s +set logfile 2",
		( hunk && hunk[0] ) ? hunk : "512",
		IOSBridge_IsMultiplayer() ? "1" : "0" );

	// Values the generated config cannot carry, because they are read before
	// any exec runs: "dedicated" is CVAR_INIT, net_port is CVAR_LATCH.
	if ( launcherExtraArgs[0] ) {
		Q_strcat( launcherCommandLine, sizeof( launcherCommandLine ), " " );
		Q_strcat( launcherCommandLine, sizeof( launcherCommandLine ),
			launcherExtraArgs );
	}

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
IOSBridge_SetExtraArgs
==============
*/
void IOSBridge_SetExtraArgs( const char *args )
{
	Q_strncpyz( launcherExtraArgs, args ? args : "",
		sizeof( launcherExtraArgs ) );
}

/*
==============
IOSBridge_IsMultiplayer
==============
*/
bool IOSBridge_IsMultiplayer( void )
{
#ifdef IORTCW_MP_BUILD
	return true;
#else
	return false;
#endif
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
