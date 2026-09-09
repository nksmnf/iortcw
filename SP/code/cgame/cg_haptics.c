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
CG_HapticFire

Per-weapon recoil. The numbers are deliberately not uniform: a Luger should
feel like a tap and a Panzerfaust should feel like it nearly took your arm off,
because that difference is most of the point of having rumble at all.

low = the heavy motor (body of the shot), high = the light motor (mechanism).
==============
*/
void CG_HapticFire( int weapon ) {
	float low, high;
	int duration;

	if ( !( hapticCaps & HAPTIC_CAP_RUMBLE ) ) {
		return;
	}

	switch ( weapon ) {
	case WP_LUGER:
	case WP_SILENCER:
	case WP_COLT:
	case WP_AKIMBO:
		low = 0.20f; high = 0.35f; duration = 60;
		break;

	case WP_MP40:
	case WP_THOMPSON:
	case WP_STEN:
		// Automatics fire fast enough that a long pulse would smear into a
		// constant buzz, so keep each shot short and let them overlap.
		low = 0.25f; high = 0.20f; duration = 45;
		break;

	case WP_MAUSER:
	case WP_GARAND:
	case WP_SNIPERRIFLE:
	case WP_SNOOPERSCOPE:
		low = 0.55f; high = 0.30f; duration = 110;
		break;

	case WP_FG42:
	case WP_FG42SCOPE:
		low = 0.35f; high = 0.25f; duration = 60;
		break;

	case WP_PANZERFAUST:
		low = 1.00f; high = 0.70f; duration = 320;
		break;

	case WP_VENOM:
		low = 0.45f; high = 0.40f; duration = 50;
		break;

	case WP_FLAMETHROWER:
		// Continuous, so a gentle sustained hum rather than a kick.
		low = 0.18f; high = 0.12f; duration = 90;
		break;

	case WP_TESLA:
		low = 0.30f; high = 0.60f; duration = 80;
		break;

	case WP_GRENADE_LAUNCHER:
	case WP_GRENADE_PINEAPPLE:
	case WP_DYNAMITE:
		low = 0.30f; high = 0.20f; duration = 70;
		break;

	case WP_KNIFE:
		low = 0.10f; high = 0.25f; duration = 40;
		break;

	default:
		low = 0.30f; high = 0.25f; duration = 60;
		break;
	}

	trap_HapticRumble( low, high, duration );
}

/*
==============
CG_HapticDamage

Taking a hit. Scaled by how hard it was, with a floor so light chip damage is
still noticeable and a ceiling so a big hit does not just saturate.
==============
*/
void CG_HapticDamage( int damage ) {
	float scale;

	if ( !( hapticCaps & HAPTIC_CAP_RUMBLE ) ) {
		return;
	}

	scale = damage / 50.0f;

	if ( scale < 0.25f ) {
		scale = 0.25f;
	}
	if ( scale > 1.0f ) {
		scale = 1.0f;
	}

	trap_HapticRumble( scale, scale * 0.4f, 120 + (int)( scale * 180 ) );
}

/*
==============
CG_HapticExplosion

Nearby blast. distance is in world units; beyond a few hundred it is not worth
feeling.
==============
*/
void CG_HapticExplosion( float distance ) {
	float falloff;

	if ( !( hapticCaps & HAPTIC_CAP_RUMBLE ) ) {
		return;
	}

	falloff = 1.0f - ( distance / 800.0f );

	if ( falloff <= 0.0f ) {
		return;
	}

	trap_HapticRumble( falloff, falloff * 0.5f, 150 + (int)( falloff * 250 ) );
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
