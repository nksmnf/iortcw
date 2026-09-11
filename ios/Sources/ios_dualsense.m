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
// ios_dualsense.m -- DualSense adaptive triggers.
//
// SDL drives everything else about the controller, but it has no API for the
// adaptive triggers, so this talks to GameController.framework directly.
//
// That is safe to do alongside SDL: SDL's MFi backend works with the same
// GCController objects and only reads from them, while this file only writes
// trigger state. There is no second connection and no ownership conflict.
//
// Availability: GCDualSenseGamepad and GCDualSenseAdaptiveTrigger have been
// public since iOS 14.5, and are present in the iOS 26 SDK. Everything here is
// guarded anyway, so a non-DualSense controller simply gets nothing.

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

/*
==============
IOS_FindDualSense

The first connected DualSense, or nil. Cheap enough to call per effect change --
GCController.controllers is a small in-memory array.
==============
*/
static GCDualSenseGamepad *IOS_FindDualSense( void )
{
	if ( @available( iOS 14.5, * ) ) {
		for ( GCController *controller in [GCController controllers] ) {
			GCExtendedGamepad *pad = controller.extendedGamepad;

			if ( [pad isKindOfClass:[GCDualSenseGamepad class]] ) {
				return (GCDualSenseGamepad *)pad;
			}
		}
	}

	return nil;
}

/*
==============
Sys_IOS_SetAdaptiveTrigger

side:  0 = left (L2), 1 = right (R2)
mode:  one of ADAPTIVE_TRIGGER_*
start: where resistance begins, 0..1 of travel
end:   where it ends (weapon mode only)
force: strength, 0..1

Weapon mode is the one that matters for a shooter: the trigger resists, then
gives way at the "break", which reads as a trigger pull. Feedback is a constant
resistance, useful for a heavy weapon that is merely heavy. Vibration is for
automatics, where the trigger buzzes at the fire rate.
==============
*/
void Sys_IOS_SetAdaptiveTrigger( int side, int mode, float start, float end, float force )
{
	if ( @available( iOS 14.5, * ) ) {
		GCDualSenseGamepad *ds = IOS_FindDualSense();
		GCDualSenseAdaptiveTrigger *trigger;

		if ( !ds ) {
			return;
		}

		trigger = side ? ds.rightTrigger : ds.leftTrigger;

		if ( !trigger ) {
			return;
		}

		start = Com_Clamp( 0.0f, 1.0f, start );
		end   = Com_Clamp( 0.0f, 1.0f, end );
		force = Com_Clamp( 0.0f, 1.0f, force );

		switch ( mode ) {
		case ADAPTIVE_TRIGGER_OFF:
			[trigger setModeOff];
			break;

		case ADAPTIVE_TRIGGER_FEEDBACK:
			[trigger setModeFeedbackWithStartPosition:start resistiveStrength:force];
			break;

		case ADAPTIVE_TRIGGER_WEAPON:
			if ( end <= start ) {
				end = start + 0.1f;
				if ( end > 1.0f ) {
					end = 1.0f;
				}
			}
			[trigger setModeWeaponWithStartPosition:start endPosition:end resistiveStrength:force];
			break;

		case ADAPTIVE_TRIGGER_VIBRATION:
			// frequency is in Hz; 10 reads as a rattle rather than a hum, which
			// is what an automatic weapon should feel like.
			[trigger setModeVibrationWithStartPosition:start amplitude:force frequency:10.0f];
			break;

		default:
			[trigger setModeOff];
			break;
		}
	}
}

/*
==============
Sys_IOS_HasAdaptiveTriggers
==============
*/
qboolean Sys_IOS_HasAdaptiveTriggers( void )
{
	if ( @available( iOS 14.5, * ) ) {
		return IOS_FindDualSense() != nil ? qtrue : qfalse;
	}

	return qfalse;
}

/*
==============
Sys_IOS_ClaimControllerEvents

Says, to the system, that the view given here reads the controller itself.

Without it iPadOS delivers a connected controller twice: once through
GameController, which is what SDL reads, and again through UIKit, which turns
the D-pad and the sticks into arrow key presses and pushes the system pointer
about. RTCW's stock bindings put +left and +right on the arrows -- turn, not
strafe -- and a key turns at a fixed cl_yawspeed however gently the stick is
leaning, so the second copy walked the player and span his view at full speed
at the same time, from either stick, identically. That is the fault this is
here to end.

GCEventInteraction is the switch for it. Declared on a view rather than on the
app, and it does not depend on who is first responder or which window is key --
which matters, because the older switch, GCEventViewController, does, and on
this port it only took hold once the player happened to touch the screen. Until
then the game was being played entirely through the echo.

Called for SDL's window and again for the touch overlay's, since they are two
windows and the system need only find one of them.
==============
*/
void Sys_IOS_ClaimControllerEvents( void *windowOrView )
{
	if ( @available( iOS 18.0, * ) ) {
		id object = (__bridge id)windowOrView;
		UIView *view = nil;

		if ( [object isKindOfClass:[UIWindow class]] ) {
			view = ( (UIWindow *)object ).rootViewController.view;
		} else if ( [object isKindOfClass:[UIView class]] ) {
			view = (UIView *)object;
		}

		if ( !view ) {
			return;
		}

		for ( id<UIInteraction> existing in view.interactions ) {
			if ( [existing isKindOfClass:[GCEventInteraction class]] ) {
				return;
			}
		}

		{
			GCEventInteraction *interaction = [[GCEventInteraction alloc] init];

			// receivesEventsInView defaults to NO, which is the half that
			// matters: the gamepad is then delivered *exclusively* through
			// GameController and UIKit never sees it. Set explicitly, because a
			// default that quiet is worth writing down.
			interaction.handledEventTypes = GCUIEventTypeGamepad;

			if ( @available( iOS 26.0, * ) ) {
				interaction.receivesEventsInView = NO;
			}

			[view addInteraction:interaction];

			Com_Printf( "Controller events claimed for %s\n",
				[object isKindOfClass:[UIWindow class]] ? "the game window" : "the touch overlay" );
		}
	}
}

/*
==============
Sys_IOS_HasHardwareKeyboard

Whether there is a real keyboard attached.

Asked because of what it rules out. iPadOS synthesises arrow key presses from a
game controller, and SDL delivers them as ordinary keys; the engine cannot tell
those from a player's own arrow keys by looking at the key. It can tell by
looking for the keyboard: SDL only takes the synthesised path when GameController
reports no keyboard, so with a pad open and no keyboard attached, an arrow is
the pad's echo and nothing else.
==============
*/
qboolean Sys_IOS_HasHardwareKeyboard( void )
{
	if ( @available( iOS 14.0, * ) ) {
		return GCKeyboard.coalescedKeyboard != nil ? qtrue : qfalse;
	}

	return qfalse;
}
