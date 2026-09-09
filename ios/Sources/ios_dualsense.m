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
