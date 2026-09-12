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
// ios_app_main.c -- the application's entry point.
//
// One app, both games. Each engine was collapsed into its own object with its
// main() renamed (SP_EngineMain, MP_EngineMain), so neither is the process
// entry point any more and this is.
//
// The order matters and is the reason the launcher moved out here:
//
//   1. Create the folders, so the launcher can see and describe them.
//   2. Audio session and SDL hints, both of which must precede SDL_Init.
//   3. Run the launcher. It picks the game and writes the settings.
//   4. Hand over to that engine, for good -- the two never run in one launch.
//
// Previously step 3 happened inside the engine, which was fine when the binary
// was one game. It cannot be now: the choice of engine has to be made before
// one of them is entered.

// SDL.h redefines main to SDL_main so that SDL's own main can wrap it. This
// file *is* the program's main, so that has to be off -- otherwise the entry
// point silently becomes SDL_main and the linker reports no main at all.
#define SDL_MAIN_HANDLED
#include <SDL.h>

#include "ios_bridge.h"
#include "ios_dispatch.h"

/*
==============
iortcw_main

Runs inside SDL's UIKit application, so UIKit and the runloop are live: the
launcher can put up a window and spin, which is exactly what it does.
==============
*/
static int iortcw_main( int argc, char *argv[] )
{
	IOSBridge_InitPaths();
	IOSBridge_InitAudioSession();
	IOSBridge_InitSDLHints();

	// Blocks until the player presses Campaign or Multiplayer, and records
	// which through IOSDispatch_SetGame.
	IOSLauncher_RunModal();

	if ( IOSDispatch_Game() == IORTCW_GAME_MULTIPLAYER ) {
		return MP_EngineMain( argc, argv );
	}

	return SP_EngineMain( argc, argv );
}

/*
==============
main

SDL_UIKitRunApp is what SDL's own main does: it starts UIApplicationMain with
SDL's delegate and calls back once the application is up. We provide main
ourselves rather than linking SDL2main, because that one would call an
SDL_main, and there is no single SDL_main here -- there are two, one per game,
and which to run is not known until the launcher has been.
==============
*/
int main( int argc, char *argv[] )
{
	return SDL_UIKitRunApp( argc, argv, iortcw_main );
}
