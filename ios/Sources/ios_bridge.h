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

// --- settings --------------------------------------------------------------
//
// Written to Documents/main/ios_launcher.cfg, which the engine execs last --
// after default.cfg and wolfconfig.cfg -- so these always win. Values that are
// CVAR_INIT or are read before the configs run (com_hunkMegs, fs_*) go through
// the command line instead; see IOSBridge_BuildCommandLine.

void IOSBridge_SetCvar( const char *name, const char *value );
const char *IOSBridge_GetCvar( const char *name );

// Replace one binding. action is a console command such as "+attack".
void IOSBridge_SetBinding( const char *keyName, const char *action );
const char *IOSBridge_GetBinding( const char *keyName );

// Flush the launcher's settings and bindings to ios_launcher.cfg.
void IOSBridge_WriteConfig( void );

// Extra arguments the engine should start with, as a single string. Built from
// the launcher's choices for the values that must be set before the configs are
// read.
const char *IOSBridge_BuildCommandLine( void );

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
