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
// ios_dispatch.h -- choosing which of the two engines the app is running.
//
// One application, both games. They are separate copies of the engine and only
// one of them ever runs in a given launch: the launcher asks which, and from
// then on every bridge call goes to that one (see ios_dispatch.c, generated).

#ifndef IOS_DISPATCH_H
#define IOS_DISPATCH_H

#ifdef __cplusplus
extern "C" {
#endif

// IORTCW_GAME_* and IOSDispatch_SetGame/Game are declared in ios_bridge.h,
// which is the launcher's bridging header and therefore has to carry them.
#include "ios_bridge.h"

// The launcher, implemented in Swift (@_cdecl). Runs before either engine and
// decides which one this launch is.
void IOSLauncher_RunModal( void );
void IOSLauncher_Show( void );

// The two engines' entry points. Each is its tree's main(), renamed when the
// tree was collapsed into one object.
int SP_EngineMain( int argc, char **argv );
int MP_EngineMain( int argc, char **argv );

#ifdef __cplusplus
}
#endif

#endif // IOS_DISPATCH_H
