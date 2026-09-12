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

#include "ios_engine.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
// AVAudioSession lives in AVFAudio; importing only AVFoundation leaves the
// category setters undeclared and they silently default to returning id.
#import <AVFAudio/AVFAudio.h>
#include <os/log.h>
#include <SDL_hints.h>

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

	// Pick up anything dropped at the top level. Finder will not drop into a
	// subfolder, so this is the only way data copied from a Mac ever reaches
	// main/.
	Sys_IOS_ImportLooseData();
}

/*
==============
IOS_FileLooksComplete

Whether a .pk3 has finished copying. Moving a half-written file would leave the
user with a corrupt archive and no clue why.

A pk3 is a zip, so this checks both ends: the local file header signature at the
start, and the end-of-central-directory record near the end. A partially copied
file has the former but not the latter.
==============
*/
static BOOL IOS_FileLooksComplete( NSString *path )
{
	NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
	unsigned long long size;
	NSData *head, *tail;
	const uint8_t *bytes;
	NSUInteger i;

	if ( !fh ) {
		return NO;
	}

	size = [fh seekToEndOfFile];

	// Smallest possible zip is the 22-byte end-of-central-directory record.
	if ( size < 22 ) {
		[fh closeFile];
		return NO;
	}

	[fh seekToFileOffset:0];
	head = [fh readDataOfLength:4];

	if ( [head length] < 4 ) {
		[fh closeFile];
		return NO;
	}

	bytes = [head bytes];
	if ( !( bytes[0] == 'P' && bytes[1] == 'K' && bytes[2] == 3 && bytes[3] == 4 ) ) {
		[fh closeFile];
		return NO;
	}

	// The EOCD sits in the last 22 bytes, plus up to 64KB of trailing comment.
	{
		unsigned long long window = ( size < 65558ULL ) ? size : 65558ULL;

		[fh seekToFileOffset:size - window];
		tail = [fh readDataOfLength:(NSUInteger)window];
	}

	[fh closeFile];

	if ( [tail length] < 22 ) {
		return NO;
	}

	bytes = [tail bytes];
	for ( i = [tail length] - 22 + 1; i-- > 0; ) {
		if ( bytes[i] == 'P' && bytes[i + 1] == 'K' &&
			 bytes[i + 2] == 5 && bytes[i + 3] == 6 ) {
			return YES;
		}
	}

	return NO;
}

/*
==============
Sys_IOS_ImportLooseData

Move any .pk3 the user has dropped into the top of the app's folder down into
main/, where the engine looks for it.

This exists because of a Finder limitation, not a preference: when you drag
files onto an app under Files on the Mac, Finder will only drop them at the top
level of the container -- it refuses to drop into a subfolder. So telling people
to "copy them into main" does not work from a Mac at all.

Also handles a whole Main/ folder being dropped in, which is the other obvious
thing to do since that is what the folder is called in a GOG or Steam install.

Returns the number of files moved, so the launcher can say something.
==============
*/
int Sys_IOS_ImportLooseData( void )
{
	__block int moved = 0;

	@autoreleasepool {
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *root = [NSString stringWithUTF8String:Sys_IOS_DataPath()];
		NSString *dest = [root stringByAppendingPathComponent:@"main"];
		NSMutableArray<NSString *> *searchDirs = [NSMutableArray arrayWithObject:root];

		// Any subfolder that is not main/ is worth a look -- most likely a
		// dropped-in "Main" from the original install.
		for ( NSString *entry in [fm contentsOfDirectoryAtPath:root error:nil] ) {
			NSString *full = [root stringByAppendingPathComponent:entry];
			BOOL isDir = NO;

			if ( [fm fileExistsAtPath:full isDirectory:&isDir] && isDir &&
				 [entry caseInsensitiveCompare:@"main"] != NSOrderedSame ) {
				[searchDirs addObject:full];
			}
		}

		for ( NSString *dir in searchDirs ) {
			for ( NSString *entry in [fm contentsOfDirectoryAtPath:dir error:nil] ) {
				NSString *src, *target;
				NSError *err = nil;

				if ( [[entry pathExtension] caseInsensitiveCompare:@"pk3"] != NSOrderedSame ) {
					continue;
				}

				src = [dir stringByAppendingPathComponent:entry];
				target = [dest stringByAppendingPathComponent:[entry lowercaseString]];

				if ( [fm fileExistsAtPath:target] ) {
					// Already have it; drop the stray copy rather than leaving
					// the folder cluttered with something that does nothing.
					[fm removeItemAtPath:src error:nil];
					continue;
				}

				if ( !IOS_FileLooksComplete( src ) ) {
					// Still being copied. It will be picked up on the next pass.
					continue;
				}

				if ( [fm moveItemAtPath:src toPath:target error:&err] ) {
					Com_Printf( "Imported %s into main/\n", [entry UTF8String] );
					moved++;
				} else {
					os_log_error( OS_LOG_DEFAULT, "iORTCW: cannot move %{public}s: %{public}s",
						[entry UTF8String], [[err localizedDescription] UTF8String] );
				}
			}
		}
	}

	return moved;
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

		// Note the mode: argument. There is no -setCategory:options:error:
		// overload; calling it throws NSInvalidArgumentException at launch.
		if ( ![session setCategory:AVAudioSessionCategoryPlayback
							  mode:AVAudioSessionModeDefault
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
Sys_IOS_PumpRunLoop

Give UIKit a turn.

A client gets this for free: SDL's event handling runs the runloop every frame.
A dedicated server never starts the renderer, so nothing does -- and the
launcher sitting on top of it, showing the server's console, would never redraw.
Called once per server frame, with a zero timeout, so it returns as soon as
whatever was queued has been handled and the server's own tick keeps the pace.
==============
*/
void Sys_IOS_PumpRunLoop( void )
{
	CFRunLoopRunInMode( kCFRunLoopDefaultMode, 0.0, true );
}

/*
==============
Sys_IOS_InitSDLHints

Hints that have to be set before SDL creates its window. The Info.plist
orientation keys are not enough on their own: SDL's view controller decides
what it will rotate to from this hint, and without it the game can come up in
portrait on a landscape-only app.
==============
*/
void Sys_IOS_InitSDLHints( void )
{
	SDL_SetHint( SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight" );

	// Let the game draw under the home indicator and dim it after a moment,
	// rather than reserving a strip of the screen for it.
	SDL_SetHint( SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2" );

	// Off, because it does not work here and the overlay does the job properly.
	// SDL turns a touch into a mouse event at the touch position, but the engine
	// runs the mouse in relative mode for aiming, and in that mode the
	// synthesised event arrives pinned to the centre of the window with a zero
	// delta -- so the menu cursor never moves and a tap activates whatever it
	// was already over. ios_touch.m places the cursor on the touch instead.
	SDL_SetHint( SDL_HINT_TOUCH_MOUSE_EVENTS, "0" );
	SDL_SetHint( SDL_HINT_MOUSE_TOUCH_EVENTS, "0" );

	// SDL presents the device's accelerometer as a joystick by default, and it
	// takes index 0 -- ahead of any real pad. The game has no use for tilt as a
	// stick and every use for the indices being predictable.
	SDL_SetHint( SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0" );

	// PS5 controllers report their full feature set only when SDL is allowed to
	// talk to them in enhanced mode.
	SDL_SetHint( SDL_HINT_JOYSTICK_HIDAPI_PS5, "1" );
	SDL_SetHint( SDL_HINT_JOYSTICK_HIDAPI_PS5_RUMBLE, "1" );
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
