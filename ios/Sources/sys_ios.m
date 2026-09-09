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
// sys_ios.m -- the iOS half of the platform layer.
//
// This replaces sys_osx.m, which cannot be built for iOS: it imports Carbon
// and Cocoa, and its Sys_StripAppBundle is meaningless in a sandbox. The rest
// of the Unix platform layer (sys_unix.c) is shared, with small
// TARGET_OS_IPHONE branches.
//
// Filesystem layout on device:
//
//   <container>/Documents/            <- fs_homepath and fs_basepath both
//     main/                              point here; UIFileSharingEnabled
//       pak0.pk3, sp_pak1..4.pk3         exposes it as "iORTCW" in Files.app
//       save/                            so the user can drop the retail data
//       wolfconfig.cfg                   in without any transfer tooling
//       qconsole.log
//
// The app bundle itself is read-only and is exposed separately as fs_apppath,
// which is where anything we ship (as opposed to what the user copies in)
// lives.

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/sys/sys_local.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <os/log.h>

static char iosDataPath[MAX_OSPATH] = { 0 };
static char iosAppPath[MAX_OSPATH] = { 0 };

/*
==============
Sys_IOS_DataPath

The writable game directory: <app container>/Documents. Both fs_basepath and
fs_homepath resolve here, which is deliberate -- FS_Startup skips adding the
homepath when it matches the basepath, so the 600+ MB of pk3s get indexed once
rather than twice.
==============
*/
const char *Sys_IOS_DataPath( void )
{
	if ( !*iosDataPath ) {
		@autoreleasepool {
			NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES );
			if ( [paths count] > 0 ) {
				Q_strncpyz( iosDataPath, [[paths objectAtIndex:0] UTF8String],
					sizeof( iosDataPath ) );
			} else {
				// Should not happen, but a sandboxed app always has $HOME.
				const char *home = getenv( "HOME" );
				Com_sprintf( iosDataPath, sizeof( iosDataPath ), "%s/Documents",
					home ? home : "." );
			}
		}
	}

	return iosDataPath;
}

/*
==============
Sys_IOS_AppPath

The read-only bundle resource directory, used as fs_apppath so that anything we
ship alongside the executable is found even before the user has copied their
retail data in.
==============
*/
const char *Sys_IOS_AppPath( void )
{
	if ( !*iosAppPath ) {
		@autoreleasepool {
			NSString *res = [[NSBundle mainBundle] resourcePath];
			Q_strncpyz( iosAppPath, res ? [res UTF8String] : ".",
				sizeof( iosAppPath ) );
		}
	}

	return iosAppPath;
}

/*
==============
Sys_IOS_InitPaths

Creates main/ and main/save/ up front. Without this the Files.app entry for the
app shows an empty folder and the user has nowhere obvious to put the pk3s.
==============
*/
void Sys_IOS_InitPaths( void )
{
	@autoreleasepool {
		NSString *base = [NSString stringWithUTF8String:Sys_IOS_DataPath()];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSArray<NSString *> *subdirs = @[ @"main", @"main/save" ];

		for ( NSString *sub in subdirs ) {
			NSString *path = [base stringByAppendingPathComponent:sub];
			NSError *err = nil;

			if ( ![fm createDirectoryAtPath:path
				  withIntermediateDirectories:YES
								   attributes:nil
										error:&err] ) {
				os_log_error( OS_LOG_DEFAULT, "iORTCW: cannot create %{public}s: %{public}s",
					[path UTF8String], [[err localizedDescription] UTF8String] );
			}
		}
	}
}

/*
==============
Sys_IOS_HasGameData

Whether the retail data is present yet. The launcher polls this so it can show
the copy-your-data screen and then flip to Play the moment the files land,
without the user having to relaunch.
==============
*/
qboolean Sys_IOS_HasGameData( void )
{
	char path[MAX_OSPATH];

	Com_sprintf( path, sizeof( path ), "%s/main/pak0.pk3", Sys_IOS_DataPath() );

	return access( path, R_OK ) == 0 ? qtrue : qfalse;
}

/*
==============
Sys_IOS_InitAudioSession

SDL's default audio category is "ambient", which means the game goes silent
when the screen locks or another app plays anything. Playback is what a game
wants. This has to run before SDL_Init(SDL_INIT_AUDIO).
==============
*/
void Sys_IOS_InitAudioSession( void )
{
	@autoreleasepool {
		NSError *err = nil;
		AVAudioSession *session = [AVAudioSession sharedInstance];

		if ( ![session setCategory:AVAudioSessionCategoryPlayback
						   options:AVAudioSessionCategoryOptionMixWithOthers
							 error:&err] ) {
			os_log_error( OS_LOG_DEFAULT, "iORTCW: audio session category failed: %{public}s",
				[[err localizedDescription] UTF8String] );
		}

		if ( ![session setActive:YES error:&err] ) {
			os_log_error( OS_LOG_DEFAULT, "iORTCW: audio session activate failed: %{public}s",
				[[err localizedDescription] UTF8String] );
		}
	}
}

/*
==============
Sys_Dialog

There is no modal dialog worth showing here. The one fatal case that matters --
missing game data -- is caught by the launcher before Com_Init runs, and by the
time the engine calls this during a crash the UI is not in a state to present
anything. Log it instead; on a sideloaded build qconsole.log in Documents is the
only diagnostic channel available.
==============
*/
dialogResult_t Sys_Dialog( dialogType_t type, const char *message, const char *title )
{
	os_log_error( OS_LOG_DEFAULT, "iORTCW [%{public}s]: %{public}s",
		title ? title : "", message ? message : "" );
	Com_Printf( "%s: %s\n", title ? title : "", message ? message : "" );

	return DR_OK;
}

/*
=================
Sys_StripAppBundle

Not meaningful on iOS -- the executable always lives inside the bundle and
fs_basepath is the Documents directory, not a sibling of the binary. Kept so
the shared sys_main.c does not need another #ifdef.
=================
*/
char *Sys_StripAppBundle( char *dir )
{
	return dir;
}
