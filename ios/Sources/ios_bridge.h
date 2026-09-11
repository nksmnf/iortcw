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
// ios_bridge.h -- the surface the Swift launcher is allowed to touch.
//
// This is the bridging header for the launcher target. It deliberately exposes
// a small, flat C API rather than the engine's own headers: q_shared.h and
// friends do not import cleanly into Swift, and a narrow surface is easier to
// keep honest.
//
// Everything here is safe to call before Com_Init (the launcher runs first) as
// well as after, unless noted.

#ifndef IOS_BRIDGE_H
#define IOS_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- game data -------------------------------------------------------------

// <container>/Documents -- where the user drops their pk3s. Shown in the UI so
// they can find it in Files.app.
const char *IOSBridge_DataPath( void );

// Is main/pak0.pk3 there yet? The launcher polls this so the Play button lights
// up as soon as the files land, without needing a relaunch.
bool IOSBridge_HasGameData( void );

// Which of the expected pk3s are present, as a bitmask in the order
// pak0, sp_pak1, sp_pak2, sp_pak3, sp_pak4. Drives the per-file checklist.
int IOSBridge_GameDataMask( void );

// Move any .pk3 dropped at the top level of the app's folder down into main/.
// Finder refuses to drop files into a subfolder over file sharing, so this is
// how data copied from a Mac actually gets where the engine looks for it.
// Returns how many files were moved. Safe to call repeatedly; it ignores files
// that are still being written.
int IOSBridge_ImportLooseData( void );

// --- settings --------------------------------------------------------------
//
// Written to Documents/main/ios_launcher.cfg, which the engine execs last --
// after default.cfg and wolfconfig.cfg -- so these always win. Values that are
// CVAR_INIT or are read before the configs run (com_hunkMegs, fs_*) go through
// the command line instead; see IOSBridge_BuildCommandLine.
//
// The getters answer from that file when the engine is not up yet, which is the
// usual case: the launcher runs before Com_Init. So what a cold start reads
// back is what the player last chose, not a set of empty strings that the
// launcher would mistake for a first run.

void IOSBridge_SetCvar( const char *name, const char *value );
const char *IOSBridge_GetCvar( const char *name );

// Stop writing a setting, leaving its value to the engine and to the player.
// For defaults the launcher seeds once and then offers no control for: left in
// the generated config they would be re-applied over the player's own choice on
// every launch, which is not what a default is.
void IOSBridge_ForgetCvar( const char *name );

// Replace one binding. action is a console command such as "+attack".
void IOSBridge_SetBinding( const char *keyName, const char *action );
const char *IOSBridge_GetBinding( const char *keyName );

// Flush the launcher's settings and bindings to ios_launcher.cfg.
void IOSBridge_WriteConfig( void );

// A console command to run once the engine is up, or "" for none. Used by the
// launcher's "start campaign" button, which exists because RTCW's own menus are
// awkward to drive without a mouse.
void IOSBridge_SetStartupCommand( const char *command );

// Extra arguments the engine should start with, as a single string. Built from
// the launcher's choices for the values that must be set before the configs are
// read.
const char *IOSBridge_BuildCommandLine( void );

// Additional "+set name value" arguments to append to that command line, for
// cvars the generated config cannot carry: "dedicated" is CVAR_INIT and
// net_port is CVAR_LATCH, so both are already fixed by the time any exec runs.
// Pass "" to clear.
void IOSBridge_SetExtraArgs( const char *args );

// --- build flavour ---------------------------------------------------------

// True in the multiplayer build. SP and MP are separate applications built from
// two source trees that share no symbols, so this is fixed at compile time; it
// exists so one launcher source can serve both.
bool IOSBridge_IsMultiplayer( void );

// --- background hosting ----------------------------------------------------
//
// iOS suspends an ordinary app seconds after it leaves the screen, which would
// kill a listening socket and end a hosted game. Turning this on keeps the
// process scheduled; see ios_keepalive.m for how, and what it costs.

void IOSBridge_SetKeepAwake( bool on );
bool IOSBridge_IsKeepAwake( void );

// --- what is in the game data ----------------------------------------------

// Reads the pk3 directories -- not their contents -- and reports what is there,
// for both sets of data below. Cached, so the launcher's once-a-second refresh
// is free after the first call; pass true to force a rescan after files have
// been added. Even a forced rescan only reopens pk3s whose size or timestamp
// has changed, so polling while the user copies costs a stat per file.
//
// Returns false if nothing could be read yet.
bool IOSBridge_ScanData( bool rescan );

// The campaign, as they always have been. The Play button and everything below
// it is written against these three.
int    IOSBridge_DataMaps( void );      // maps/*.bsp across every pak
int    IOSBridge_DataFiles( void );     // entries in total
double IOSBridge_DataMegabytes( void ); // uncompressed size of the lot

// --- the two sets of data ---------------------------------------------------
//
// RTCW ships its single-player campaign and its multiplayer as separate pk3s,
// and a player may have one and not the other, so the launcher shows them as
// two lists. The bridge owns what each list contains: it is the side that knows
// which files the engine refuses to start without.
//
// Every getter below scans on first use, so they can be called in any order.
// index runs 0 .. IOSBridge_SetFileCount(set) - 1; out-of-range arguments
// answer 0, "" or false rather than trapping.

#define IOS_DATA_SET_CAMPAIGN     0
#define IOS_DATA_SET_MULTIPLAYER  1
#define IOS_DATA_SET_COUNT        2

int         IOSBridge_SetFileCount( int set );
const char *IOSBridge_SetFileName( int set, int index );
bool        IOSBridge_SetFilePresent( int set, int index );

// Required files are the ones the engine calls Com_Error over. The optional
// ones -- multiplayer's bonus map packs and mp_bin.pk3 -- cost the player
// nothing to skip beyond the servers they can join, but they are part of the
// complete set, so IOSBridge_SetIsRecommended does count them.
bool        IOSBridge_SetFileRequired( int set, int index );

// Statistics over the files of the set that are present. pak0.pk3 is retail
// media that both halves of the game load, so it is in both sets and counted
// in both -- the two totals deliberately do not add up to what is on disk.
//
// SetMaps counts maps/mp_*.bsp for multiplayer and every maps/*.bsp for the
// campaign, because pak0.pk3's 32 maps are all campaign maps and none of them
// is a level any server runs.
int         IOSBridge_SetMaps( int set );
int         IOSBridge_SetFiles( int set );      // entries inside its pk3s
double      IOSBridge_SetMegabytes( int set );  // uncompressed size of the set

// Will the engine start on this? Every required file present, and readable as
// a zip -- a pk3 halfway through being copied is not yet in place.
bool        IOSBridge_SetIsPlayable( int set );

// Has the player exactly what they should have: the complete set at the last
// official patch level (1.41 for multiplayer, the Game of the Year files for
// the campaign), with nothing missing and nothing extra wearing an id pak's
// name. Stricter than IOSBridge_SetIsPlayable, which only asks whether it runs.
bool        IOSBridge_SetIsRecommended( int set );

// "iortcw 1.51d-SP ios-arm64", the same string the engine prints on startup.
const char *IOSBridge_EngineVersion( void );

// --- launcher lifecycle ----------------------------------------------------

// Set by the Swift side when the user presses Play; the C side spins the
// runloop until this goes true.
void IOSBridge_LauncherFinished( void );

// Read by the Swift side's runloop pump. Declared here (rather than in
// sys_local.h) so the launcher needs only this one header.
bool Sys_IOS_LauncherIsFinished( void );
void Sys_IOS_LauncherReset( void );

#ifdef __cplusplus
}
#endif

#endif // IOS_BRIDGE_H
