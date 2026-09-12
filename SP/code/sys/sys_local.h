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

#include "../qcommon/q_shared.h"
#include "../qcommon/qcommon.h"

#ifndef DEDICATED
#ifdef USE_LOCAL_HEADERS
#	include "SDL_version.h"
#else
#	include <SDL_version.h>
#endif

// Require a minimum version of SDL
#define MINSDL_MAJOR 2
#define MINSDL_MINOR 0
#if SDL_VERSION_ATLEAST( 2, 0, 5 )
#define MINSDL_PATCH 5
#else
#define MINSDL_PATCH 0
#endif
#endif

// Console
void CON_Shutdown( void );
void CON_Init( void );
char *CON_Input( void );
void CON_Print( const char *message );

unsigned int CON_LogSize( void );
unsigned int CON_LogWrite( const char *in );
unsigned int CON_LogRead( char *out, unsigned int outSize );

#ifdef __APPLE__
char *Sys_StripAppBundle( char *pwd );
#endif

#if TARGET_OS_IPHONE
// implemented in ios/Sources/sys_ios.m
const char *Sys_IOS_DataPath( void );      // <container>/Documents, read/write
const char *Sys_IOS_AppPath( void );       // bundle resources, read-only
void        Sys_IOS_InitPaths( void );     // creates main/ and main/save/
qboolean    Sys_IOS_HasGameData( void );   // is main/pak0.pk3 there yet?
int         Sys_IOS_ImportLooseData( void ); // move stray pk3s into main/
void        Sys_IOS_InitAudioSession( void );
void        Sys_IOS_InitSDLHints( void );  // must run before SDL creates its window
// ios_dualsense.m -- adaptive triggers, which SDL does not expose
void        Sys_IOS_SetAdaptiveTrigger( int side, int mode, float start, float end, float force );
qboolean    Sys_IOS_HasAdaptiveTriggers( void );

// ios_touch.m -- on-screen controls, shown only when no controller is attached
void        Sys_IOS_TouchOverlayInit( void *sdlWindowHandle );

// Tell iPadOS that this part of the interface reads the controller itself, so
// it stops delivering the same input a second time through UIKit. Takes a
// UIWindow or a UIView; safe to call more than once on the same one.
void        Sys_IOS_ClaimControllerEvents( void *windowOrView );

// Whether a real keyboard is attached, as opposed to the arrow keys iPadOS
// synthesises from a game controller.
qboolean    Sys_IOS_HasHardwareKeyboard( void );
void        Sys_IOS_PerfInit( void *parentView );
void        Sys_IOS_PerfFrame( void );
void        Sys_IOS_PerfNoteSwap( double ms );

// A monotonic clock in seconds, finer than Sys_Milliseconds. For the swap
// timing above, which at 120Hz is a couple of milliseconds all told.
double      Sys_IOS_PerfSeconds( void );
void        Sys_IOS_GyroInit( void );
void        Sys_IOS_GyroFrame( void );
void        Sys_IOS_GyroShutdown( void );
void        Sys_IOS_TouchOverlayUpdate( void );
void        Sys_IOS_TouchOverlayShutdown( void );

// Launcher (Swift, via @_cdecl) and its C-side bridge
void        IOSLauncher_RunModal( void );
void        IOSLauncher_Show( void );
const char *IOSBridge_BuildCommandLine( void );
void        IOSBridge_LogAppend( const char *msg );

// Let UIKit run for a moment. Only needed by a dedicated server, which has no
// renderer and therefore nothing else that gives the runloop a turn.
void        Sys_IOS_PumpRunLoop( void );
#endif

void Sys_GLimpSafeInit( void );
void Sys_GLimpInit( void );
void Sys_PlatformInit( void );
void Sys_PlatformExit( void );
void Sys_SigHandler( int signal ) __attribute__ ((noreturn));
void Sys_ErrorDialog( const char *error );
void Sys_AnsiColorPrint( const char *msg );

int Sys_PID( void );
qboolean Sys_PIDIsRunning( int pid );
