/*
===========================================================================

Return to Castle Wolfenstein single player GPL Source Code
Copyright (C) 1999-2010 id Software LLC, a ZeniMax Media company.

This file is part of the Return to Castle Wolfenstein single player GPL Source Code (RTCW SP Source Code).

RTCW SP Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

RTCW SP Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with RTCW SP Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the RTCW SP Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the RTCW SP Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/
// cg_haptics.c -- controller rumble and light bar feedback.
//
// The engine exposes the controller through three traps (CG_HAPTIC_*); this
// file decides what each game event should feel like. Everything here is a
// no-op when no capable controller is attached, which is what trap_HapticInfo
// is for -- it is queried once per level rather than per event.

#include "cg_local.h"

static int   hapticCaps;
static int   hapticLastLED;      // packed rgb, to avoid resending an unchanged colour
static int   hapticNextLEDCheck;

/*
==============
CG_HapticsInit
==============
*/
void CG_HapticsInit( void ) {
	hapticCaps = trap_HapticInfo();
	hapticLastLED = -1;
	hapticNextLEDCheck = 0;

	if ( hapticCaps ) {
		CG_Printf( "Controller haptics:%s%s\n",
			( hapticCaps & HAPTIC_CAP_RUMBLE ) ? " rumble" : "",
			( hapticCaps & HAPTIC_CAP_LED ) ? " led" : "" );
	}
}

/*
==============
CG_HapticDamage

The only thing the pad rumbles for, and it says how much it hurt.

Rumbling for every shot fired turns the pad into background noise and tells the
player nothing they did not already know -- they pulled the trigger. A hit is
different: it is the one piece of information the screen conveys badly, in a
number at the bottom of the display that nobody reads mid-fight.

So the length of the pulse carries the damage and the strength stays low and
roughly even. Length is what a hand can judge without counting: a graze is a
tick, a serious hit lasts long enough to be alarming, and the difference between
them is felt rather than read. Amplitude is deliberately not the signal -- it
saturates quickly and every pad and every player scales it differently.

A little over 20ms per point of health, so a 10-point graze is a 190ms tick and
anything past about 60 sits at the 1.3s ceiling, which is already long enough to
mean "that was very bad".
==============
*/
void CG_HapticDamage( int damage ) {
	int duration;
	float low, high;

	if ( !( hapticCaps & HAPTIC_CAP_RUMBLE ) ) {
		return;
	}

	if ( damage <= 0 ) {
		return;
	}

	duration = 80 + damage * 21;

	if ( duration > 1300 ) {
		duration = 1300;
	}

	// Light, and only barely rising with the damage: enough that a big hit still
	// feels heavier, not so much that it drowns out the length.
	low  = 0.18f + ( damage > 40 ? 0.12f : damage * 0.003f );
	high = low * 0.45f;

	trap_HapticRumble( low, high, duration );
}

/*
==============
CG_HapticsFrame

Light bar colour from health: green when healthy through to red when nearly
dead. Rate-limited because the colour only needs to track health, not frames,
and every call is a Bluetooth write.
==============
*/
void CG_HapticsFrame( void ) {
	int health, r, g, b, packed;

	if ( !( hapticCaps & HAPTIC_CAP_LED ) ) {
		return;
	}

	if ( cg.time < hapticNextLEDCheck ) {
		return;
	}
	hapticNextLEDCheck = cg.time + 250;

	health = cg.snap ? cg.snap->ps.stats[STAT_HEALTH] : 100;

	if ( health > 100 ) {
		health = 100;
	}
	if ( health < 0 ) {
		health = 0;
	}

	if ( health > 50 ) {
		// green -> yellow
		r = (int)( 255 * ( 100 - health ) / 50.0f );
		g = 255;
	} else {
		// yellow -> red
		r = 255;
		g = (int)( 255 * health / 50.0f );
	}
	b = 0;

	packed = ( r << 16 ) | ( g << 8 ) | b;

	if ( packed != hapticLastLED ) {
		trap_HapticLED( r, g, b );
		hapticLastLED = packed;
	}
}

/*
==============
CG_HapticWeaponChanged

Adaptive trigger profile for the weapon now in hand. This is the DualSense
feature that has no equivalent anywhere else: the trigger itself can resist,
break, or rattle, so each weapon can feel different before a shot is even
fired.

Set once on weapon change rather than per shot -- the effect is a property of
the trigger, not an event.
==============
*/
void CG_HapticWeaponChanged( int weapon ) {
	int mode;
	float start, end, force;

	if ( !( hapticCaps & HAPTIC_CAP_ADAPTIVE ) ) {
		return;
	}

	switch ( weapon ) {
	case WP_KNIFE:
		// nothing to pull against
		mode = ADAPTIVE_TRIGGER_OFF;
		start = end = force = 0.0f;
		break;

	case WP_LUGER:
	case WP_SILENCER:
	case WP_COLT:
		mode = ADAPTIVE_TRIGGER_WEAPON;
		start = 0.35f; end = 0.55f; force = 0.35f;
		break;

	case WP_AKIMBO:
		mode = ADAPTIVE_TRIGGER_WEAPON;
		start = 0.30f; end = 0.50f; force = 0.40f;
		break;

	case WP_MP40:
	case WP_THOMPSON:
	case WP_STEN:
		// automatics buzz through the trigger while held
		mode = ADAPTIVE_TRIGGER_VIBRATION;
		start = 0.25f; end = 0.0f; force = 0.45f;
		break;

	case WP_MAUSER:
	case WP_GARAND:
	case WP_SNIPERRIFLE:
	case WP_SNOOPERSCOPE:
		// a heavy, deliberate break
		mode = ADAPTIVE_TRIGGER_WEAPON;
		start = 0.45f; end = 0.70f; force = 0.75f;
		break;

	case WP_FG42:
	case WP_FG42SCOPE:
		mode = ADAPTIVE_TRIGGER_WEAPON;
		start = 0.35f; end = 0.60f; force = 0.50f;
		break;

	case WP_PANZERFAUST:
		// heaviest thing you can carry
		mode = ADAPTIVE_TRIGGER_WEAPON;
		start = 0.50f; end = 0.85f; force = 1.00f;
		break;

	case WP_VENOM:
		mode = ADAPTIVE_TRIGGER_VIBRATION;
		start = 0.20f; end = 0.0f; force = 0.70f;
		break;

	case WP_FLAMETHROWER:
		// constant back-pressure while the fuel flows
		mode = ADAPTIVE_TRIGGER_FEEDBACK;
		start = 0.20f; end = 0.0f; force = 0.40f;
		break;

	case WP_TESLA:
		mode = ADAPTIVE_TRIGGER_VIBRATION;
		start = 0.30f; end = 0.0f; force = 0.55f;
		break;

	default:
		mode = ADAPTIVE_TRIGGER_WEAPON;
		start = 0.35f; end = 0.60f; force = 0.45f;
		break;
	}

	// Right trigger is fire. Left is left free for aiming, which should not
	// fight the player.
	trap_HapticTrigger( 1, mode, start, end, force );
	trap_HapticTrigger( 0, ADAPTIVE_TRIGGER_OFF, 0.0f, 0.0f, 0.0f );
}
