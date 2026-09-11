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
// ios_keepalive.m -- keeping a hosted game alive while the app is not on screen.
//
// The problem: iOS suspends an ordinary application a few seconds after it
// leaves the screen. A suspended process is not scheduled at all, so the
// server's socket stops being read, every client times out, and the heartbeat
// to the master stops. Backgrounding the app would end the game.
//
// There is no background mode for "keep listening on a socket". The list is
// fixed -- audio, location, VoIP, external accessory, and a few more -- and a
// game server is none of them. What *is* available is this: an app playing
// audio keeps running, and that is a real, documented mode rather than a
// loophole in the scheduler.
//
// So hosting starts an audio graph that renders silence. The process stays
// scheduled, the socket keeps being read, and the game survives the screen
// going off or the user switching apps.
//
// Being honest about what this is:
//
//   * It is the mechanism Apple provides for audio apps, used here by an app
//     that is not primarily an audio app. App Review would reject it on those
//     grounds. This build is distributed through AltStore, where there is no
//     review -- but anyone taking it to the App Store needs to know.
//   * It costs battery. The CPU is kept awake, and the server keeps running a
//     full simulation tick. Hosting from a tablet on battery drains it fast;
//     this is a plugged-in feature.
//   * The session is configured to mix with others, so it never interrupts
//     whatever the user is actually listening to.
//
// The silence is not digital zero. A stream of exact zeroes can be spotted as
// "not really playing audio", and the safe, cheap insurance is a signal far
// below the threshold of hearing but not identically nothing.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#include "ios_bridge.h"

static AVAudioEngine       *keepAliveEngine;
static AVAudioSourceNode   *keepAliveSource;
static BOOL                 keepAliveActive;
// UIBackgroundTaskInvalid is not a compile-time constant in the current SDK, so
// this cannot be its initialiser; zero is never a valid identifier and the
// accessor below turns it into the real sentinel.
static UIBackgroundTaskIdentifier keepAliveTask;

/*
==============
IOSKeepAlive_Start

Brings up an audio graph that renders near-silence. Safe to call when already
running.
==============
*/
static void IOSKeepAlive_Start( void )
{
	NSError *err = nil;

	if ( keepAliveActive ) {
		return;
	}

	AVAudioSession *session = [AVAudioSession sharedInstance];

	// .playback is the category that keeps running in the background.
	// MixWithOthers so hosting a game never silences the user's music.
	if ( ![session setCategory:AVAudioSessionCategoryPlayback
					   mode:AVAudioSessionModeDefault
					options:AVAudioSessionCategoryOptionMixWithOthers
					  error:&err] ) {
		NSLog( @"iortcw: keepalive category failed: %@", err );
		return;
	}

	if ( ![session setActive:YES error:&err] ) {
		NSLog( @"iortcw: keepalive activation failed: %@", err );
		return;
	}

	keepAliveEngine = [[AVAudioEngine alloc] init];

	AVAudioFormat *fmt = [[AVAudioFormat alloc]
		initStandardFormatWithSampleRate:44100.0 channels:2];

	// A hair above nothing: inaudible, but not a stream of exact zeroes.
	keepAliveSource = [[AVAudioSourceNode alloc] initWithFormat:fmt
		renderBlock:^OSStatus( BOOL *isSilence,
							   const AudioTimeStamp *timestamp,
							   AVAudioFrameCount frameCount,
							   AudioBufferList *outputData ) {
			for ( UInt32 b = 0; b < outputData->mNumberBuffers; b++ ) {
				float *out = (float *)outputData->mBuffers[b].mData;

				if ( !out ) {
					continue;
				}

				for ( AVAudioFrameCount f = 0; f < frameCount; f++ ) {
					out[f] = 1.0e-5f;
				}
			}

			*isSilence = NO;
			return noErr;
		}];

	[keepAliveEngine attachNode:keepAliveSource];
	[keepAliveEngine connect:keepAliveSource
						  to:keepAliveEngine.mainMixerNode
					  format:fmt];
	keepAliveEngine.mainMixerNode.outputVolume = 0.0f;

	if ( ![keepAliveEngine startAndReturnError:&err] ) {
		NSLog( @"iortcw: keepalive engine failed: %@", err );
		keepAliveEngine = nil;
		keepAliveSource = nil;
		return;
	}

	// The screen staying on is a separate thing from the process staying
	// scheduled; a host wants both, since the common case is a tablet propped
	// up and plugged in.
	dispatch_async( dispatch_get_main_queue(), ^{
		[UIApplication sharedApplication].idleTimerDisabled = YES;
	} );

	keepAliveActive = YES;
	NSLog( @"iortcw: keepalive active -- hosting will survive backgrounding" );
}

/*
==============
IOSKeepAlive_Stop
==============
*/
static void IOSKeepAlive_Stop( void )
{
	if ( !keepAliveActive ) {
		return;
	}

	[keepAliveEngine stop];
	keepAliveEngine = nil;
	keepAliveSource = nil;

	[[AVAudioSession sharedInstance] setActive:NO
		withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
			  error:nil];

	dispatch_async( dispatch_get_main_queue(), ^{
		[UIApplication sharedApplication].idleTimerDisabled = NO;

		if ( keepAliveTask != 0 && keepAliveTask != UIBackgroundTaskInvalid ) {
			[[UIApplication sharedApplication] endBackgroundTask:keepAliveTask];
			keepAliveTask = 0;
		}
	} );

	keepAliveActive = NO;
	NSLog( @"iortcw: keepalive stopped" );
}

/*
==============
IOSBridge_SetKeepAwake
==============
*/
void IOSBridge_SetKeepAwake( bool on )
{
	if ( on ) {
		IOSKeepAlive_Start();
	} else {
		IOSKeepAlive_Stop();
	}
}

/*
==============
IOSBridge_IsKeepAwake
==============
*/
bool IOSBridge_IsKeepAwake( void )
{
	return keepAliveActive ? true : false;
}
