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

#ifdef USE_LOCAL_HEADERS
#	include "SDL.h"
#else
#	include <SDL.h>
#endif

#if TARGET_OS_IPHONE
#ifdef USE_LOCAL_HEADERS
#	include "SDL_syswm.h"
#else
#	include <SDL_syswm.h>
#endif
#endif

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "../client/client.h"
#include "../sys/sys_local.h"

#if !SDL_VERSION_ATLEAST(2, 0, 17)
#define KMOD_SCROLL KMOD_RESERVED
#endif

static cvar_t *in_keyboardDebug     = NULL;

static SDL_GameController *gamepad = NULL;
static SDL_Joystick *stick = NULL;

static qboolean mouseAvailable = qfalse;
static qboolean mouseActive = qfalse;


static cvar_t *in_mouse             = NULL;
static cvar_t *in_nograb;

static cvar_t *in_joystick          = NULL;
static cvar_t *in_joystickThreshold = NULL;
static cvar_t *in_joystickNo        = NULL;
static cvar_t *in_joystickUseAnalog = NULL;

// DualSense (and any other controller that exposes the same features).
static cvar_t *in_gyro              = NULL;  // 0 off, 1 always on, 2 only while aiming
static cvar_t *in_gyroSens          = NULL;  // degrees of view per degree of tilt
static cvar_t *in_gyroDeadzone      = NULL;  // rad/s taken off the tilt before it counts
static cvar_t *in_gyroInvertYaw     = NULL;  // for a sensor that does not match SDL's frame
static cvar_t *in_gyroInvertPitch   = NULL;
static cvar_t *in_touchpad          = NULL;  // 0 off, 1 gestures, 2 gestures + drag-to-look
static cvar_t *in_touchpadSens      = NULL;
static cvar_t *in_triggerSoft       = NULL;  // fraction of travel that counts as pressed
static cvar_t *in_triggerHard       = NULL;  // deeper threshold, bound separately
static cvar_t *in_rumble            = NULL;  // master scale, 0 disables
static cvar_t *in_ledFeedback       = NULL;  // tint the light bar by player health
static cvar_t *in_gamepadDirect     = NULL;  // read sticks directly, bypassing the key/bind indirection
static cvar_t *in_debugTouch        = NULL;  // log touch and synthesised-mouse events
static cvar_t *in_debugPad          = NULL;  // log gamepad buttons and sticks
static cvar_t *in_touchLookSens     = NULL;  // how fast a finger turns the view
static cvar_t *in_stickExpo         = NULL;  // look curve: 0 linear, 1 fully cubed
static cvar_t *in_moveExpo          = NULL;  // movement curve, deliberately flatter
static cvar_t *in_moveDigital       = NULL;  // quantise the movement stick to eight directions
static cvar_t *in_dpadMove          = NULL;  // D-pad walks, like the arrow keys
static cvar_t *in_invertLook        = NULL;
static cvar_t *in_menuCursorSpeed   = NULL;  // pixels per frame at full deflection
static cvar_t *in_lookYawSpeed      = NULL;  // degrees per second at full deflection
static cvar_t *in_lookPitchSpeed    = NULL;

static int vidRestartTime = 0;

static int in_eventTime = 0;

// Where the UI's cursor is, in its own 640x480 space. Kept in step with
// _UI_MouseEvent, which is the only thing that moves it and clamps it exactly
// like this. Touch needs it because a finger is an absolute position and the UI
// only accepts relative ones.
static int menuCursorX = 0;
static int menuCursorY = 0;

// Set once the player touches the pad. See IOSTouch_ControllerConnected.
static qboolean gamepadUsed = qfalse;

static void IN_NoteGamepadActivity( void )
{
	int i;

	if ( gamepadUsed || !gamepad ) {
		return;
	}

	for ( i = 0; i < SDL_CONTROLLER_BUTTON_MAX; i++ ) {
		if ( SDL_GameControllerGetButton( gamepad, i ) ) {
			gamepadUsed = qtrue;
			Com_Printf( "Gamepad in use\n" );
			return;
		}
	}

	for ( i = 0; i < SDL_CONTROLLER_AXIS_MAX; i++ ) {
		if ( abs( SDL_GameControllerGetAxis( gamepad, i ) ) > 8000 ) {
			gamepadUsed = qtrue;
			Com_Printf( "Gamepad in use\n" );
			return;
		}
	}
}

static void IN_QueueMouseDelta( int dx, int dy )
{
	if ( !dx && !dy ) {
		return;
	}

	menuCursorX = Com_Clamp( 0, 640, menuCursorX + dx );
	menuCursorY = Com_Clamp( 0, 480, menuCursorY + dy );

	Com_QueueEvent( in_eventTime, SE_MOUSE, dx, dy, 0, NULL );
}

/*
===============
IN_MenuCursorTo

Put the menu cursor on a point now, without going through the event queue.

Queueing would be too late for a keypress that has to act on a particular item:
Com_EventLoop is already handling that key, so anything queued from here is
processed after it.
===============
*/
void IN_MenuCursorTo( int x, int y )
{
	int dx = x - menuCursorX;
	int dy = y - menuCursorY;

	if ( !dx && !dy ) {
		return;
	}

	menuCursorX = Com_Clamp( 0, 640, menuCursorX + dx );
	menuCursorY = Com_Clamp( 0, 480, menuCursorY + dy );

	CL_MouseEvent( dx, dy, 0 );
}

/*
===============
IN_ResetMenuCursor

Called when the UI is (re)started, which puts its cursor back at the origin.

Resynchronising any other way is not possible: Com_QueueEvent folds consecutive
mouse events into one, so the obvious trick of slamming the cursor into a corner
and then moving it out lands in the corner and stays there.
===============
*/
void IN_ResetMenuCursor( void )
{
	menuCursorX = 0;
	menuCursorY = 0;
}


static SDL_Window *SDL_window = NULL;

#define CTRL(a) ((a)-'a'+1)

/*
===============
IN_PrintKey
===============
*/
static void IN_PrintKey( const SDL_Keysym *keysym, keyNum_t key, qboolean down )
{
	if( down )
		Com_Printf( "+ " );
	else
		Com_Printf( "  " );

	Com_Printf( "Scancode: 0x%02x(%s) Sym: 0x%02x(%s)",
			keysym->scancode, SDL_GetScancodeName( keysym->scancode ),
			keysym->sym, SDL_GetKeyName( keysym->sym ) );

	if( keysym->mod & KMOD_LSHIFT )   Com_Printf( " KMOD_LSHIFT" );
	if( keysym->mod & KMOD_RSHIFT )   Com_Printf( " KMOD_RSHIFT" );
	if( keysym->mod & KMOD_LCTRL )    Com_Printf( " KMOD_LCTRL" );
	if( keysym->mod & KMOD_RCTRL )    Com_Printf( " KMOD_RCTRL" );
	if( keysym->mod & KMOD_LALT )     Com_Printf( " KMOD_LALT" );
	if( keysym->mod & KMOD_RALT )     Com_Printf( " KMOD_RALT" );
	if( keysym->mod & KMOD_LGUI )     Com_Printf( " KMOD_LGUI" );
	if( keysym->mod & KMOD_RGUI )     Com_Printf( " KMOD_RGUI" );
	if( keysym->mod & KMOD_NUM )      Com_Printf( " KMOD_NUM" );
	if( keysym->mod & KMOD_CAPS )     Com_Printf( " KMOD_CAPS" );
	if( keysym->mod & KMOD_MODE )     Com_Printf( " KMOD_MODE" );
	if( keysym->mod & KMOD_SCROLL )   Com_Printf( " KMOD_SCROLL" );

	Com_Printf( " Q:0x%02x(%s)\n", key, Key_KeynumToString( key, qtrue ) );
}

#define MAX_CONSOLE_KEYS 16

/*
===============
IN_IsConsoleKey

TODO: If the SDL_Scancode situation improves, use it instead of
      both of these methods
===============
*/
static qboolean IN_IsConsoleKey( keyNum_t key, int character )
{
	typedef struct consoleKey_s
	{
		enum
		{
			QUAKE_KEY,
			CHARACTER
		} type;

		union
		{
			keyNum_t key;
			int character;
		} u;
	} consoleKey_t;

	static consoleKey_t consoleKeys[ MAX_CONSOLE_KEYS ];
	static int numConsoleKeys = 0;
	int i;

	// Only parse the variable when it changes
	if( cl_consoleKeys->modified )
	{
		char *text_p, *token;

		cl_consoleKeys->modified = qfalse;
		text_p = cl_consoleKeys->string;
		numConsoleKeys = 0;

		while( numConsoleKeys < MAX_CONSOLE_KEYS )
		{
			consoleKey_t *c = &consoleKeys[ numConsoleKeys ];
			int charCode = 0;

			token = COM_Parse( &text_p );
			if( !token[ 0 ] )
				break;

			charCode = Com_HexStrToInt( token );

			if( charCode > 0 )
			{
				c->type = CHARACTER;
				c->u.character = charCode;
			}
			else
			{
				c->type = QUAKE_KEY;
				c->u.key = Key_StringToKeynum( token );

				// 0 isn't a key
				if( c->u.key <= 0 )
					continue;
			}

			numConsoleKeys++;
		}
	}

	// If the character is the same as the key, prefer the character
	if( key == character )
		key = 0;

	for( i = 0; i < numConsoleKeys; i++ )
	{
		consoleKey_t *c = &consoleKeys[ i ];

		switch( c->type )
		{
			case QUAKE_KEY:
				if( key && c->u.key == key )
					return qtrue;
				break;

			case CHARACTER:
				if( c->u.character == character )
					return qtrue;
				break;
		}
	}

	return qfalse;
}

/*
===============
IN_TranslateSDLToQ3Key
===============
*/
static keyNum_t IN_TranslateSDLToQ3Key( SDL_Keysym *keysym, qboolean down )
{
	keyNum_t key = 0;

	if( keysym->scancode >= SDL_SCANCODE_1 && keysym->scancode <= SDL_SCANCODE_0 )
	{
		// Always map the number keys as such even if they actually map
		// to other characters (eg, "1" is "&" on an AZERTY keyboard).
		// This is required for SDL before 2.0.6, except on Windows
		// which already had this behavior.
		if( keysym->scancode == SDL_SCANCODE_0 )
			key = '0';
		else
			key = '1' + keysym->scancode - SDL_SCANCODE_1;
	}
	else if( keysym->sym >= SDLK_SPACE && keysym->sym < SDLK_DELETE )
	{
		// These happen to match the ASCII chars
		key = (int)keysym->sym;
	}
	else
	{
		switch( keysym->sym )
		{
			case SDLK_PAGEUP:       key = K_PGUP;          break;
			case SDLK_KP_9:         key = K_KP_PGUP;       break;
			case SDLK_PAGEDOWN:     key = K_PGDN;          break;
			case SDLK_KP_3:         key = K_KP_PGDN;       break;
			case SDLK_KP_7:         key = K_KP_HOME;       break;
			case SDLK_HOME:         key = K_HOME;          break;
			case SDLK_KP_1:         key = K_KP_END;        break;
			case SDLK_END:          key = K_END;           break;
			case SDLK_KP_4:         key = K_KP_LEFTARROW;  break;
			case SDLK_LEFT:         key = K_LEFTARROW;     break;
			case SDLK_KP_6:         key = K_KP_RIGHTARROW; break;
			case SDLK_RIGHT:        key = K_RIGHTARROW;    break;
			case SDLK_KP_2:         key = K_KP_DOWNARROW;  break;
			case SDLK_DOWN:         key = K_DOWNARROW;     break;
			case SDLK_KP_8:         key = K_KP_UPARROW;    break;
			case SDLK_UP:           key = K_UPARROW;       break;
			case SDLK_ESCAPE:       key = K_ESCAPE;        break;
			case SDLK_KP_ENTER:     key = K_KP_ENTER;      break;
			case SDLK_RETURN:       key = K_ENTER;         break;
			case SDLK_TAB:          key = K_TAB;           break;
			case SDLK_F1:           key = K_F1;            break;
			case SDLK_F2:           key = K_F2;            break;
			case SDLK_F3:           key = K_F3;            break;
			case SDLK_F4:           key = K_F4;            break;
			case SDLK_F5:           key = K_F5;            break;
			case SDLK_F6:           key = K_F6;            break;
			case SDLK_F7:           key = K_F7;            break;
			case SDLK_F8:           key = K_F8;            break;
			case SDLK_F9:           key = K_F9;            break;
			case SDLK_F10:          key = K_F10;           break;
			case SDLK_F11:          key = K_F11;           break;
			case SDLK_F12:          key = K_F12;           break;
			case SDLK_F13:          key = K_F13;           break;
			case SDLK_F14:          key = K_F14;           break;
			case SDLK_F15:          key = K_F15;           break;

			case SDLK_BACKSPACE:    key = K_BACKSPACE;     break;
			case SDLK_KP_PERIOD:    key = K_KP_DEL;        break;
			case SDLK_DELETE:       key = K_DEL;           break;
			case SDLK_PAUSE:        key = K_PAUSE;         break;

			case SDLK_LSHIFT:
			case SDLK_RSHIFT:       key = K_SHIFT;         break;

			case SDLK_LCTRL:
			case SDLK_RCTRL:        key = K_CTRL;          break;

#ifdef __APPLE__
			case SDLK_RGUI:
			case SDLK_LGUI:         key = K_COMMAND;       break;
#else
			case SDLK_RGUI:
			case SDLK_LGUI:         key = K_SUPER;         break;
#endif

			case SDLK_RALT:
			case SDLK_LALT:         key = K_ALT;           break;

			case SDLK_KP_5:         key = K_KP_5;          break;
			case SDLK_INSERT:       key = K_INS;           break;
			case SDLK_KP_0:         key = K_KP_INS;        break;
			case SDLK_KP_MULTIPLY:  key = K_KP_STAR;       break;
			case SDLK_KP_PLUS:      key = K_KP_PLUS;       break;
			case SDLK_KP_MINUS:     key = K_KP_MINUS;      break;
			case SDLK_KP_DIVIDE:    key = K_KP_SLASH;      break;

			case SDLK_MODE:         key = K_MODE;          break;
			case SDLK_HELP:         key = K_HELP;          break;
			case SDLK_PRINTSCREEN:  key = K_PRINT;         break;
			case SDLK_SYSREQ:       key = K_SYSREQ;        break;
			case SDLK_MENU:         key = K_MENU;          break;
			case SDLK_APPLICATION:	key = K_MENU;          break;
			case SDLK_POWER:        key = K_POWER;         break;
			case SDLK_UNDO:         key = K_UNDO;          break;
			case SDLK_SCROLLLOCK:   key = K_SCROLLOCK;     break;
			case SDLK_NUMLOCKCLEAR: key = K_KP_NUMLOCK;    break;
			case SDLK_CAPSLOCK:     key = K_CAPSLOCK;      break;

			default:
				if( !( keysym->sym & SDLK_SCANCODE_MASK ) && keysym->scancode <= 95 )
				{
					// Map Unicode characters to 95 world keys using the key's scan code.
					// FIXME: There aren't enough world keys to cover all the scancodes.
					// Maybe create a map of scancode to quake key at start up and on
					// key map change; allocate world key numbers as needed similar
					// to SDL 1.2.
					key = K_WORLD_0 + (int)keysym->scancode;
				}
				break;
		}
	}

	if( in_keyboardDebug->integer )
		IN_PrintKey( keysym, key, down );

	if( IN_IsConsoleKey( key, 0 ) )
	{
		// Console keys can't be bound or generate characters
		key = K_CONSOLE;
	}

	return key;
}

/*
===============
IN_GobbleMotionEvents
===============
*/
static void IN_GobbleMotionEvents( void )
{
	SDL_Event dummy[ 1 ];
	int val = 0;

	// Gobble any mouse motion events
	SDL_PumpEvents( );
	while( ( val = SDL_PeepEvents( dummy, 1, SDL_GETEVENT,
		SDL_MOUSEMOTION, SDL_MOUSEMOTION ) ) > 0 ) { }

	if ( val < 0 )
		Com_Printf( "IN_GobbleMotionEvents failed: %s\n", SDL_GetError( ) );
}

/*
===============
IN_ActivateMouse
===============
*/
static void IN_ActivateMouse( qboolean isFullscreen )
{
	if (!mouseAvailable || !SDL_WasInit( SDL_INIT_VIDEO ) )
		return;

	if( !mouseActive )
	{
		SDL_SetRelativeMouseMode( SDL_TRUE );
		SDL_SetWindowGrab( SDL_window, SDL_TRUE );

		IN_GobbleMotionEvents( );
	}

	// in_nograb makes no sense in fullscreen mode
	if( !isFullscreen )
	{
		if( in_nograb->modified || !mouseActive )
		{
			if( in_nograb->integer ) {
				SDL_SetRelativeMouseMode( SDL_FALSE );
				SDL_SetWindowGrab( SDL_window, SDL_FALSE );
			} else {
				SDL_SetRelativeMouseMode( SDL_TRUE );
				SDL_SetWindowGrab( SDL_window, SDL_TRUE );
			}

			in_nograb->modified = qfalse;
		}
	}

	mouseActive = qtrue;
}

/*
===============
IN_DeactivateMouse
===============
*/
static void IN_DeactivateMouse( qboolean isFullscreen )
{
	if( !SDL_WasInit( SDL_INIT_VIDEO ) )
		return;

	// Always show the cursor when the mouse is disabled,
	// but not when fullscreen
	if( !isFullscreen )
		SDL_ShowCursor( SDL_TRUE );

	if( !mouseAvailable )
		return;

	if( mouseActive )
	{
		IN_GobbleMotionEvents( );

		SDL_SetWindowGrab( SDL_window, SDL_FALSE );
		SDL_SetRelativeMouseMode( SDL_FALSE );

		// Don't warp the mouse unless the cursor is within the window
		if( SDL_GetWindowFlags( SDL_window ) & SDL_WINDOW_MOUSE_FOCUS )
			SDL_WarpMouseInWindow( SDL_window, cls.glconfig.vidWidth / 2, cls.glconfig.vidHeight / 2 );

		mouseActive = qfalse;
	}
}

// We translate axes movement into keypresses
static int joy_keys[16] = {
	K_LEFTARROW, K_RIGHTARROW,
	K_UPARROW, K_DOWNARROW,
	K_JOY17, K_JOY18,
	K_JOY19, K_JOY20,
	K_JOY21, K_JOY22,
	K_JOY23, K_JOY24,
	K_JOY25, K_JOY26,
	K_JOY27, K_JOY28
};

// translate hat events into keypresses
// the 4 highest buttons are used for the first hat ...
static int hat_keys[16] = {
	K_JOY29, K_JOY30,
	K_JOY31, K_JOY32,
	K_JOY25, K_JOY26,
	K_JOY27, K_JOY28,
	K_JOY21, K_JOY22,
	K_JOY23, K_JOY24,
	K_JOY17, K_JOY18,
	K_JOY19, K_JOY20
};


struct
{
	qboolean buttons[SDL_CONTROLLER_BUTTON_MAX + 1]; // +1 because old max was 16, current SDL_CONTROLLER_BUTTON_MAX is 15

	// How each held button was delivered, so its release can be delivered the
	// same way even if the game changed underneath it. See IN_GamepadMove.
	byte     buttonRoute[SDL_CONTROLLER_BUTTON_MAX + 1];
	unsigned int oldaxes;
	int oldaaxes[MAX_JOYSTICK_AXIS];
	unsigned int oldhats;

	// Second stage of the analogue triggers, tracked separately from the
	// K_PAD0_*TRIGGER keys the axis loop already emits at the soft threshold.
	qboolean triggerHard[2];

	// Touchpad. SDL reports normalised 0..1 coordinates per finger; we keep the
	// press origin so a release can be classified as a tap or a swipe.
	qboolean touchDown;
	float    touchStartX, touchStartY;
	float    touchLastX, touchLastY;
	int      touchStartTime;
	qboolean touchSwiped;      // a swipe already fired for this contact
} stick_state;

// The controller's own feature set, queried once when it is opened.
static struct
{
	qboolean hasGyro;
	qboolean hasRumble;
	qboolean hasLED;
	int      numTouchpads;
} gamepadCaps;

enum { ROUTE_KEY = 0, ROUTE_MENU, ROUTE_DPAD, ROUTE_SKIP };

// What counts as "not moving" for the gyro, in rad/s. About 2 degrees a second:
// below anything a hand does on purpose, above what a still controller reports.
#define GYRO_REST_RATE  0.035f

// How long the readings have to stay that small before they are believed, in
// milliseconds. Long enough that a slow deliberate pan is never mistaken for
// rest and learned as bias.
#define GYRO_REST_SETTLE  250

// Time constant of the bias estimate, in seconds. Expressed as a time rather
// than as a per-frame fraction so it converges at the same speed at 60Hz and
// at 120Hz.
#define GYRO_BIAS_TAU  0.4f

// Degrees of view per second for each rad/s of real rotation, at in_gyroSens
// 1.0. This is exactly what the old chain -- 32767/4 into the axis and then
// j_pitch's 0.022 in CL_JoystickMove -- worked out to, and it is kept to the
// decimal so that a sensitivity someone has already settled on still means the
// same thing after the rest of this was rewritten.
#define GYRO_VIEW_DEGREES_PER_RAD  180.2185f

// Units the gyro axes are carried in. Must match GYRO_AXIS_SCALE in
// cl_input.c, which reads them, and in ios_gyro.m, which writes the same two
// axes from the iPad's own sensor.
#define GYRO_AXIS_SCALE  32.0f

// Resting bias of the controller's gyro, and the last values put on the axes.
// At file scope rather than inside IN_GamepadGyro because both have to be
// thrown away when the controller changes -- see IN_GyroReset.
static float gyroBias[3];
static int   gyroRestSince;
static int   gyroSampleTime;
static int   gyroAxis[2];      // [0] pitch, [1] yaw

static qboolean IN_TouchOwnsMovement( void );
static void IN_GamepadTriggers( void );
static void IN_GamepadTouchpad( void );
static void IN_GamepadGyro( void );
static void IN_GyroReset( void );


/*
===============
IN_InitJoystick
===============
*/
static void IN_InitJoystick( void )
{
	int i = 0;
	int total = 0;
	char buf[16384] = "";

	if (gamepad)
		SDL_GameControllerClose(gamepad);

	if (stick != NULL)
		SDL_JoystickClose(stick);

	stick = NULL;
	gamepad = NULL;
	gamepadUsed = qfalse;
	memset(&stick_state, '\0', sizeof (stick_state));

	// Before any of the early returns below: the controller list has changed,
	// so whatever the gyro had learned or last sent belongs to a pad that may
	// no longer be there.
	IN_GyroReset();

	// SDL 2.0.4 requires SDL_INIT_JOYSTICK to be initialized separately from
	// SDL_INIT_GAMECONTROLLER for SDL_JoystickOpen() to work correctly,
	// despite https://wiki.libsdl.org/SDL_Init (retrieved 2016-08-16)
	// indicating SDL_INIT_JOYSTICK should be initialized automatically.
	if (!SDL_WasInit(SDL_INIT_JOYSTICK))
	{
		Com_DPrintf("Calling SDL_Init(SDL_INIT_JOYSTICK)...\n");
		if (SDL_Init(SDL_INIT_JOYSTICK) != 0)
		{
			Com_DPrintf("SDL_Init(SDL_INIT_JOYSTICK) failed: %s\n", SDL_GetError());
			return;
		}
		Com_DPrintf("SDL_Init(SDL_INIT_JOYSTICK) passed.\n");
	}

	if (!SDL_WasInit(SDL_INIT_GAMECONTROLLER))
	{
		Com_DPrintf("Calling SDL_Init(SDL_INIT_GAMECONTROLLER)...\n");
		if (SDL_Init(SDL_INIT_GAMECONTROLLER) != 0)
		{
			Com_DPrintf("SDL_Init(SDL_INIT_GAMECONTROLLER) failed: %s\n", SDL_GetError());
			return;
		}
		Com_DPrintf("SDL_Init(SDL_INIT_GAMECONTROLLER) passed.\n");
	}

	total = SDL_NumJoysticks();
	if ( total )
		Com_Printf("%d possible joysticks\n", total);

	// Print list and build cvar to allow ui to select joystick.
	for (i = 0; i < total; i++)
	{
		// Named, not just counted. On a controller-first port the difference
		// between "the pad is here" and "SDL is reporting something else"
		// decides where to look next, and there is no console to ask on.
		Com_Printf( "  %d: %s%s\n", i, SDL_JoystickNameForIndex(i),
			SDL_IsGameController(i) ? " (gamepad)" : "" );

		Q_strcat(buf, sizeof(buf), SDL_JoystickNameForIndex(i));
		Q_strcat(buf, sizeof(buf), "\n");
	}

	Cvar_Get( "in_availableJoysticks", "", CVAR_ROM );

	// Update cvar on in_restart or controller add/remove.
	Cvar_Set( "in_availableJoysticks", buf );

	if( !in_joystick->integer ) {
		Com_DPrintf( "Joystick is not active.\n" );
		SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
		return;
	}

	in_joystickNo = Cvar_Get( "in_joystickNo", "0", CVAR_ARCHIVE );
	if( in_joystickNo->integer < 0 || in_joystickNo->integer >= total )
		Cvar_Set( "in_joystickNo", "0" );

	// Prefer a device SDL recognises as a game controller.
	//
	// Index order is not ours to choose and the first device is not necessarily
	// the interesting one -- on iOS index 0 is "iOS Accelerometer", so a pad
	// plugged in afterwards lands at index 1 and the default of 0 opens the
	// accelerometer instead. That looks exactly like a pad that does nothing.
	if( !SDL_IsGameController( in_joystickNo->integer ) )
	{
		for( i = 0; i < total; i++ )
		{
			if( SDL_IsGameController( i ) )
			{
				Com_Printf( "Joystick %d is not a gamepad, using %d (%s) instead\n",
					in_joystickNo->integer, i, SDL_JoystickNameForIndex( i ) );
				Cvar_Set( "in_joystickNo", va( "%d", i ) );
				break;
			}
		}
	}

	in_joystickUseAnalog = Cvar_Get( "in_joystickUseAnalog", "0", CVAR_ARCHIVE );

	stick = SDL_JoystickOpen( in_joystickNo->integer );

	if (stick == NULL) {
		Com_DPrintf( "No joystick opened: %s\n", SDL_GetError() );
		return;
	}

	if (SDL_IsGameController(in_joystickNo->integer))
		gamepad = SDL_GameControllerOpen(in_joystickNo->integer);

	Com_DPrintf( "Joystick %d opened\n", in_joystickNo->integer );
	Com_DPrintf( "Name:       %s\n", SDL_JoystickNameForIndex(in_joystickNo->integer) );
	Com_DPrintf( "Axes:       %d\n", SDL_JoystickNumAxes(stick) );
	Com_DPrintf( "Hats:       %d\n", SDL_JoystickNumHats(stick) );
	Com_DPrintf( "Buttons:    %d\n", SDL_JoystickNumButtons(stick) );
	Com_DPrintf( "Balls:      %d\n", SDL_JoystickNumBalls(stick) );
	Com_DPrintf( "Use Analog: %s\n", in_joystickUseAnalog->integer ? "Yes" : "No" );
	Com_DPrintf( "Is gamepad: %s\n", gamepad ? "Yes" : "No" );

	Com_Memset( &gamepadCaps, 0, sizeof( gamepadCaps ) );

	if ( gamepad )
	{
#if SDL_VERSION_ATLEAST( 2, 0, 14 )
		gamepadCaps.numTouchpads = SDL_GameControllerGetNumTouchpads( gamepad );
		gamepadCaps.hasRumble    = SDL_GameControllerRumble( gamepad, 0, 0, 0 ) == 0;
		gamepadCaps.hasLED       = SDL_GameControllerHasLED( gamepad );
		gamepadCaps.hasGyro      = SDL_GameControllerHasSensor( gamepad, SDL_SENSOR_GYRO );

		if ( gamepadCaps.hasGyro ) {
			// The sensor stays enabled for the life of the controller; in_gyro
			// decides whether its samples are actually used, so toggling the
			// cvar takes effect immediately rather than needing a reconnect.
			SDL_GameControllerSetSensorEnabled( gamepad, SDL_SENSOR_GYRO, SDL_TRUE );
		}

		Com_Printf( "Gamepad: %s%s%s%s\n",
			gamepadCaps.numTouchpads ? "touchpad " : "",
			gamepadCaps.hasGyro      ? "gyro "     : "",
			gamepadCaps.hasRumble    ? "rumble "   : "",
			gamepadCaps.hasLED       ? "led"       : "" );
#endif
	}

	SDL_JoystickEventState(SDL_QUERY);
	SDL_GameControllerEventState(SDL_QUERY);
}

/*
===============
IN_Rumble

Drives the controller's motors. lowFreq/highFreq are 0..1; duration is in
milliseconds. Called from the client on behalf of cgame (trap CG_HAPTIC_RUMBLE)
and always on the main thread, which matters because SDL's rumble path is not
safe to call from a notification callback.
===============
*/
void IN_Rumble( float lowFreq, float highFreq, int durationMs )
{
#if SDL_VERSION_ATLEAST( 2, 0, 9 )
	float scale;

	if ( !gamepad || !gamepadCaps.hasRumble || !in_rumble )
		return;

	scale = in_rumble->value * 0.01f;

	if ( scale <= 0.0f )
		return;

	if ( scale > 1.0f )
		scale = 1.0f;

	lowFreq  = Com_Clamp( 0.0f, 1.0f, lowFreq  * scale );
	highFreq = Com_Clamp( 0.0f, 1.0f, highFreq * scale );

	SDL_GameControllerRumble( gamepad,
		(Uint16)( lowFreq  * 65535.0f ),
		(Uint16)( highFreq * 65535.0f ),
		durationMs );
#endif
}

/*
===============
IN_SetAdaptiveTrigger

DualSense adaptive triggers. SDL has no API for these, so on iOS this hands off
to ios_dualsense.m, which drives GameController.framework directly. Elsewhere it
is a no-op -- on macOS SDL's HIDAPI backend claims the device exclusively, so
GameController never sees it.
===============
*/
void IN_SetAdaptiveTrigger( int side, int mode, float start, float end, float force )
{
#if TARGET_OS_IPHONE
	if ( !gamepad ) {
		return;
	}

	Sys_IOS_SetAdaptiveTrigger( side, mode, start, end, force );
#endif
}

/*
===============
IN_GetHapticCaps

What the currently open controller can actually do, so cgame can skip building
effects for hardware that will ignore them.
===============
*/
int IN_GetHapticCaps( void )
{
	int caps = 0;

	if ( !gamepad )
		return 0;

	if ( gamepadCaps.hasRumble )
		caps |= HAPTIC_CAP_RUMBLE;
	if ( gamepadCaps.hasLED )
		caps |= HAPTIC_CAP_LED;
	if ( gamepadCaps.hasGyro )
		caps |= HAPTIC_CAP_GYRO;
	if ( gamepadCaps.numTouchpads > 0 )
		caps |= HAPTIC_CAP_TOUCHPAD;
#if TARGET_OS_IPHONE
	if ( Sys_IOS_HasAdaptiveTriggers() )
		caps |= HAPTIC_CAP_ADAPTIVE;
#endif

	return caps;
}

/*
===============
IN_SetControllerLED

Tints the DualSense light bar. The client drives this from player health, which
gives a peripheral damage cue that costs nothing on screen.
===============
*/
void IN_SetControllerLED( int red, int green, int blue )
{
#if SDL_VERSION_ATLEAST( 2, 0, 14 )
	if ( !gamepad || !gamepadCaps.hasLED || !in_ledFeedback || !in_ledFeedback->integer )
		return;

	SDL_GameControllerSetLED( gamepad, (Uint8)red, (Uint8)green, (Uint8)blue );
#endif
}

/*
===============
IN_ShutdownJoystick
===============
*/
static void IN_ShutdownJoystick( void )
{
	if ( !SDL_WasInit( SDL_INIT_GAMECONTROLLER ) )
		return;

	if ( !SDL_WasInit( SDL_INIT_JOYSTICK ) )
		return;

	if (gamepad)
	{
		SDL_GameControllerClose(gamepad);
		gamepad = NULL;
	}

	if (stick)
	{
		SDL_JoystickClose(stick);
		stick = NULL;
	}

	SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
	SDL_QuitSubSystem(SDL_INIT_JOYSTICK);
}


static qboolean KeyToAxisAndSign(int keynum, int *outAxis, int *outSign)
{
	char *bind;

	if (!keynum)
		return qfalse;

	bind = Key_GetBinding(keynum);

	if (!bind || *bind != '+')
		return qfalse;

	*outSign = 0;

	if (Q_stricmp(bind, "+forward") == 0)
	{
		*outAxis = j_forward_axis->integer;
		*outSign = j_forward->value > 0.0f ? 1 : -1;
	}
	else if (Q_stricmp(bind, "+back") == 0)
	{
		*outAxis = j_forward_axis->integer;
		*outSign = j_forward->value > 0.0f ? -1 : 1;
	}
	else if (Q_stricmp(bind, "+moveleft") == 0)
	{
		*outAxis = j_side_axis->integer;
		*outSign = j_side->value > 0.0f ? -1 : 1;
	}
	else if (Q_stricmp(bind, "+moveright") == 0)
	{
		*outAxis = j_side_axis->integer;
		*outSign = j_side->value > 0.0f ? 1 : -1;
	}
	else if (Q_stricmp(bind, "+lookup") == 0)
	{
		*outAxis = j_pitch_axis->integer;
		*outSign = j_pitch->value > 0.0f ? -1 : 1;
	}
	else if (Q_stricmp(bind, "+lookdown") == 0)
	{
		*outAxis = j_pitch_axis->integer;
		*outSign = j_pitch->value > 0.0f ? 1 : -1;
	}
	else if (Q_stricmp(bind, "+left") == 0)
	{
		*outAxis = j_yaw_axis->integer;
		*outSign = j_yaw->value > 0.0f ? 1 : -1;
	}
	else if (Q_stricmp(bind, "+right") == 0)
	{
		*outAxis = j_yaw_axis->integer;
		*outSign = j_yaw->value > 0.0f ? -1 : 1;
	}
	else if (Q_stricmp(bind, "+moveup") == 0)
	{
		*outAxis = j_up_axis->integer;
		*outSign = j_up->value > 0.0f ? 1 : -1;
	}
	else if (Q_stricmp(bind, "+movedown") == 0)
	{
		*outAxis = j_up_axis->integer;
		*outSign = j_up->value > 0.0f ? -1 : 1;
	}

	return *outSign != 0;
}

/*
===============
IN_NonZero

Guards against a divide by zero if a j_* cvar has been set to 0, which would
otherwise silently produce an infinite axis value.
===============
*/
static float IN_NonZero( float value, float fallback )
{
	float v = fabs( value );

	return ( v > 0.0001f ) ? v : fallback;
}

/*
===============
IN_ApplyStickCurve

Turns a raw stick reading into something usable.

Two things matter here and both were wrong before. First, the deadzone has to be
*radial*: applied per-axis, a stick pushed straight up still leaks a little X,
and if that X is driving yaw the player walks in a slow circle. That is exactly
the "walks in circles when I push forward" symptom. Second, the response is
curved rather than linear, because a linear stick makes small aiming
corrections almost impossible on a thumbstick.

x and y come in as -1..1 and are rewritten in place.
===============
*/
static void IN_ApplyStickCurve( float *x, float *y, float deadzone, float expo )
{
	float mag = sqrt( (*x) * (*x) + (*y) * (*y) );
	float scaled, curved;

	if ( mag < deadzone ) {
		*x = 0.0f;
		*y = 0.0f;
		return;
	}

	if ( mag > 1.0f ) {
		mag = 1.0f;
	}

	// Rescale so the stick starts moving from zero at the edge of the deadzone
	// instead of jumping to whatever the deadzone cut off.
	scaled = ( mag - deadzone ) / ( 1.0f - deadzone );

	// expo 0 is linear, 1 is fully cubed. Blending keeps the top end at full
	// speed while making the centre much finer.
	curved = scaled * ( ( 1.0f - expo ) + expo * scaled * scaled );

	// Renormalise the direction vector and reapply the curved magnitude, which
	// keeps diagonals at the same speed as the cardinals.
	*x = ( *x / mag ) * curved;
	*y = ( *y / mag ) * curved;
}

/*
===============
IN_DigitalMove

Quantise the movement stick into eight directions and drive the same movement
commands the keyboard uses.

Each of the four commands is held while the stick is anywhere in its 180-degree
half, which is what makes the diagonals work: north-east lands in both the
forward half and the right half, so both are held, exactly as pressing W and D
together would. A small overlap either side of each boundary would cause
flicker, so the halves are trimmed slightly and the deadzone does the rest.

Keys are emitted only on change, so the engine sees clean presses and releases
rather than a stream of repeats.
===============
*/
static void IN_DigitalMove( float x, float y )
{
	static qboolean held[4];   // forward, back, left, right
	const char *commands[4] = { "+forward", "+back", "+moveleft", "+moveright" };

	// One key number per direction, and not the ones the D-pad uses.
	//
	// A +command carries the key that pressed it, and a -command with no key at
	// all clears every holder. Leaving these blank meant the stick and the D-pad
	// shared a slot: whichever let go first released the other one too, so
	// holding a direction on the D-pad did nothing as soon as the stick moved.
	const int keys[4] = { K_PAD0_LEFTSTICK_UP, K_PAD0_LEFTSTICK_DOWN,
						  K_PAD0_LEFTSTICK_LEFT, K_PAD0_LEFTSTICK_RIGHT };
	qboolean want[4] = { qfalse, qfalse, qfalse, qfalse };
	float mag = sqrt( x * x + y * y );
	int i;

	if ( mag > 0.0f ) {
		// 0.383 is sin(22.5 degrees): the point at which a direction stops
		// counting towards a neighbouring axis, which is what gives eight even
		// sectors rather than four wide ones with narrow diagonals.
		const float edge = 0.383f;
		float nx = x / mag;
		float ny = y / mag;

		want[0] = ( ny < -edge ) ? qtrue : qfalse;   // stick up    -> forward
		want[1] = ( ny >  edge ) ? qtrue : qfalse;   // stick down  -> back
		want[2] = ( nx < -edge ) ? qtrue : qfalse;   // stick left  -> strafe left
		want[3] = ( nx >  edge ) ? qtrue : qfalse;   // stick right -> strafe right
	}

	for ( i = 0; i < 4; i++ ) {
		if ( !want[i] && !held[i] ) {
			continue;
		}

		// Sent as console commands rather than key events because these are not
		// bindable keys -- the stick is the stick, and routing it through a
		// binding is what put turn on the left stick in the first place.
		//
		// A held direction is re-sent every frame rather than only when it
		// changes. IN_KeyDown treats a repeat of the same key as a no-op, so
		// this costs nothing, and it heals the one thing that kept breaking:
		// Key_ClearStates, which the UI calls whenever a menu closes, wipes the
		// engine's idea of what is held while this function still believes it is
		// pressed -- after which the direction stayed dead until the stick was
		// centred and pushed again.
		Cbuf_AddText( va( "%c%s %d\n", want[i] ? '+' : '-', commands[i] + 1, keys[i] ) );

		if ( in_debugPad && in_debugPad->integer && want[i] != held[i] ) {
			Com_Printf( "pad: stick %c%s\n", want[i] ? '+' : '-', commands[i] + 1 );
		}

		held[i] = want[i];
	}
}

/*
===============
IN_GamepadSticks

Feed the two sticks straight into the joystick axes the client already reads.

The alternative -- what this replaces -- was to synthesise a key press per stick
direction and let KeyToAxisAndSign map it back to an axis through whatever that
key happened to be bound to. That indirection meant the stick layout was decided
by default.cfg inside pak0.pk3, which binds the left stick's horizontal to turn
rather than strafe, so both sticks appeared to do the same thing and pushing
forward walked in a circle.

Left stick is movement, right stick is look. That is not configurable here on
purpose: it is what every player expects, and the bindable surface is the
buttons.
===============
*/
static void IN_GamepadSticks( void )
{
	float lx, ly, rx, ry;
	float deadzone = in_joystickThreshold->value;
	float expo = in_stickExpo->value;
	float moveExpo = in_moveExpo->value;

	if ( deadzone < 0.0f || deadzone > 0.9f ) {
		deadzone = 0.15f;
	}
	if ( expo < 0.0f || expo > 1.0f ) {
		expo = 0.6f;
	}
	if ( moveExpo < 0.0f || moveExpo > 1.0f ) {
		moveExpo = 0.15f;
	}

	lx = (float)SDL_GameControllerGetAxis( gamepad, SDL_CONTROLLER_AXIS_LEFTX ) / 32767.0f;
	ly = (float)SDL_GameControllerGetAxis( gamepad, SDL_CONTROLLER_AXIS_LEFTY ) / 32767.0f;
	rx = (float)SDL_GameControllerGetAxis( gamepad, SDL_CONTROLLER_AXIS_RIGHTX ) / 32767.0f;
	ry = (float)SDL_GameControllerGetAxis( gamepad, SDL_CONTROLLER_AXIS_RIGHTY ) / 32767.0f;

	// Raw, before anything is done to them. This is the only way to tell a stick
	// that reports a small range from a curve that is eating it, and there is no
	// console on a tablet to ask.
	if ( in_debugPad && in_debugPad->integer ) {
		static int nextLog;

		if ( Sys_Milliseconds() >= nextLog &&
			 ( fabs( lx ) > 0.02f || fabs( ly ) > 0.02f ||
			   fabs( rx ) > 0.02f || fabs( ry ) > 0.02f ) ) {
			nextLog = Sys_Milliseconds() + 250;
			Com_Printf( "pad: raw L %.3f %.3f  R %.3f %.3f\n", lx, ly, rx, ry );
		}
	}

	// Different curves for the two sticks, on purpose. Aiming wants a soft
	// centre so small corrections are possible; walking does not -- a strong
	// curve there just makes the character feel sluggish at half deflection,
	// when what the player asked for was "walk forward".
	IN_ApplyStickCurve( &lx, &ly, deadzone, moveExpo );
	IN_ApplyStickCurve( &rx, &ry, deadzone, expo );

	// While a menu or the console is up, the right stick drives the cursor
	// instead. Without this there is no way to start a mission from the pad.
	if ( CL_UIActive() ) {
		float speed = in_menuCursorSpeed->value;
		int dx, dy;

		// Either stick, so it does not matter which one the player reaches for.
		if ( rx == 0.0f && ry == 0.0f ) {
			rx = lx;
			ry = ly;
		}

		dx = (int)( rx * speed );
		dy = (int)( ry * speed );

		IN_QueueMouseDelta( dx, dy );

		// Nothing should reach the movement axes while a menu is up.
		if ( !IN_TouchOwnsMovement() ) {
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_side_axis->integer, 0, 0, NULL );
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_forward_axis->integer, 0, 0, NULL );
		}
		Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_yaw_axis->integer, 0, 0, NULL );
		Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_pitch_axis->integer, 0, 0, NULL );
		return;
	}

	// SDL's Y axes point down, and the engine's j_forward and j_pitch scales are
	// already negative to suit that, so the raw sign is passed through and the
	// direction is left to the cvars. in_invertLook flips pitch only.
	if ( in_invertLook->integer ) {
		ry = -ry;
	}

	// Movement is digital by default: the stick is quantised into the same eight
	// directions a keyboard gives you, and emitted as +forward / +moveleft and
	// friends. Analogue movement sounds better than it plays here -- RTCW has no
	// walk/run gradient worth steering with a thumb, and a stick that is always
	// slightly off-centre makes the character drift. Quantising also means
	// "north-east" is unambiguously forward+right rather than a blend that
	// depends on exactly how the thumb sat.
	if ( in_moveDigital->integer ) {
		IN_DigitalMove( lx, ly );

		// The movement axes must be silent, or the analogue path would fight
		// the keys -- unless the on-screen stick is being held, in which case
		// they are its, and zeroing them here is what stopped touch walking
		// after a step or two.
		if ( !IN_TouchOwnsMovement() ) {
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_side_axis->integer, 0, 0, NULL );
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_forward_axis->integer, 0, 0, NULL );
		}

		{
			float yawScale   = in_lookYawSpeed->value   / IN_NonZero( j_yaw->value, 0.022f );
			float pitchScale = in_lookPitchSpeed->value / IN_NonZero( j_pitch->value, 0.022f );

			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_yaw_axis->integer,
				(int)( rx * yawScale ), 0, NULL );
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_pitch_axis->integer,
				(int)( ry * pitchScale ), 0, NULL );

			if ( in_debugPad && in_debugPad->integer ) {
				static int nextAxisLog;

				if ( Sys_Milliseconds() >= nextAxisLog ) {
					nextAxisLog = Sys_Milliseconds() + 250;
					Com_Printf( "pad: axes side[%d]=%d fwd[%d]=%d yaw[%d]=%d pitch[%d]=%d touchOwns=%d\n",
						j_side_axis->integer, cl.joystickAxis[j_side_axis->integer],
						j_forward_axis->integer, cl.joystickAxis[j_forward_axis->integer],
						j_yaw_axis->integer, (int)( rx * yawScale ),
						j_pitch_axis->integer, (int)( ry * pitchScale ),
						IN_TouchOwnsMovement() );
				}
			}
		}
		return;
	}

	// Scaling, and this is the part that was making the sticks feel broken.
	//
	// CL_JoystickMove multiplies whatever arrives here by j_side / j_forward and
	// then ClampChars the result into a movement byte. j_side defaults to 0.25,
	// so feeding it the full +-32767 produces 8191 and clamps to 127 -- meaning
	// about 2% of stick travel already commands full speed and the stick is
	// effectively a digital switch. Scaling so that full deflection lands
	// exactly on 127 gives back the whole analogue range.
	//
	// The look axes have the opposite problem: +-32767 through j_yaw works out
	// at roughly 720 degrees per second, which is unusable. Because
	// CL_JoystickMove scales by frametime, the per-second turn rate is simply
	// j_yaw * axis, so the axis value for a wanted rate is just rate / j_yaw.
	// That lets the speed be expressed in degrees per second, which is a number
	// a player can reason about, instead of an arbitrary multiplier.
	{
		float sideScale    = 127.0f / IN_NonZero( j_side->value, 0.25f );
		float forwardScale = 127.0f / IN_NonZero( j_forward->value, 0.25f );
		float yawScale     = in_lookYawSpeed->value   / IN_NonZero( j_yaw->value, 0.022f );
		float pitchScale   = in_lookPitchSpeed->value / IN_NonZero( j_pitch->value, 0.022f );

		if ( !IN_TouchOwnsMovement() ) {
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_side_axis->integer,
				(int)( lx * sideScale ), 0, NULL );
			Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_forward_axis->integer,
				(int)( ly * forwardScale ), 0, NULL );
		}
		Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_yaw_axis->integer,
			(int)( rx * yawScale ), 0, NULL );
		Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, j_pitch_axis->integer,
			(int)( ry * pitchScale ), 0, NULL );
	}
}

/*
===============
IN_DpadMoveCommand

Movement command for a D-pad direction, or NULL for anything else.

Returned without the leading sign; the caller prepends + or -.
===============
*/
static const char *IN_DpadMoveCommand( int button )
{
	switch ( button )
	{
		case SDL_CONTROLLER_BUTTON_DPAD_UP:    return "forward";
		case SDL_CONTROLLER_BUTTON_DPAD_DOWN:  return "back";
		case SDL_CONTROLLER_BUTTON_DPAD_LEFT:  return "moveleft";
		case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return "moveright";
		default:                               return NULL;
	}
}

/*
===============
IN_MenuKeyForPadButton

What a pad button should mean while a menu or the console is up, or 0 to leave
it as a normal PAD0_* key.

Cross acts as a click because RTCW's menus are cursor-driven -- the stick moves
the pointer and Cross presses what is under it, which is how a console port of a
mouse-driven menu normally behaves. The D-pad is also mapped to the arrow keys
so list-style menus (difficulty, saved games) can be walked without aiming.
===============
*/
/*
===============
IN_SkipsCutscene

Which buttons mean "get on with it" while a cutscene is playing.

Needed since the keyboard duplicates iPadOS sends for these buttons started
being dropped: skipping used to happen by accident, because the duplicate of
Cross arrived as Return and Options as Escape, and the game skips on those.
===============
*/
/*
===============
IN_TouchOwnsMovement

True while the on-screen stick is held. Only ever true on iOS; elsewhere this
folds away to a constant.
===============
*/
static qboolean IN_TouchOwnsMovement( void )
{
#if TARGET_OS_IPHONE
	extern int IOSTouch_MovementActive( void );

	return IOSTouch_MovementActive() ? qtrue : qfalse;
#else
	return qfalse;
#endif
}

static qboolean IN_CutsceneActive( void )
{
	if ( clc.state == CA_CINEMATIC ) {
		return qtrue;
	}

	// cl.cameraMode rather than the com_cameraMode cvar: it is the flag
	// CL_KeyDownEvent itself tests when deciding that a key means "skip".
	return cl.cameraMode ? qtrue : qfalse;
}

static qboolean IN_SkipsCutscene( int button )
{
	switch ( button )
	{
		case SDL_CONTROLLER_BUTTON_A:
		case SDL_CONTROLLER_BUTTON_B:
		case SDL_CONTROLLER_BUTTON_START:
		case SDL_CONTROLLER_BUTTON_BACK:
			return qtrue;
		default:
			return qfalse;
	}
}

static int IN_MenuKeyForPadButton( int button )
{
	switch ( button )
	{
		case SDL_CONTROLLER_BUTTON_A:          return K_MOUSE1;
		case SDL_CONTROLLER_BUTTON_B:          return K_ESCAPE;
		case SDL_CONTROLLER_BUTTON_X:          return K_ENTER;
		case SDL_CONTROLLER_BUTTON_Y:          return K_SPACE;
		case SDL_CONTROLLER_BUTTON_START:      return K_ESCAPE;
		case SDL_CONTROLLER_BUTTON_BACK:       return K_ESCAPE;
		case SDL_CONTROLLER_BUTTON_DPAD_UP:    return K_UPARROW;
		case SDL_CONTROLLER_BUTTON_DPAD_DOWN:  return K_DOWNARROW;
		case SDL_CONTROLLER_BUTTON_DPAD_LEFT:  return K_LEFTARROW;
		case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return K_RIGHTARROW;

		// The notebook and the mission objectives are paged, not scrolled, and
		// the shoulders are where a pad player reaches for pages.
		case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return K_PGUP;
		case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return K_PGDN;

		default:                               return 0;
	}
}

/*
===============
IN_GamepadMove
===============
*/
static void IN_GamepadMove( void )
{
	int i;
	int translatedAxes[MAX_JOYSTICK_AXIS];
	qboolean translatedAxesSet[MAX_JOYSTICK_AXIS];
	qboolean menuMode;

	SDL_GameControllerUpdate();

	// While a menu or the console is up, the pad drives the UI rather than the
	// player. RTCW's menus only understand mouse and keyboard, so the buttons
	// are translated instead of being sent as PAD0_* keys that no menu binds --
	// otherwise there is no way to pick a difficulty and start a mission
	// without putting the iPad down and using the touchscreen.
	// The sticks are read directly, always, on this platform.
	//
	// The alternative is to synthesise a key per stick direction and let the
	// bindings map it back to an axis -- and default.cfg inside pak0 binds the
	// left stick's horizontal to turn, so the character walks in circles and
	// both sticks appear to do the same thing. That is not a layout anyone
	// would choose, so the cvar is not allowed to select it here; it stays for
	// the desktop builds, where a player might have a reason.
#if TARGET_OS_IPHONE
	Cvar_Set( "in_gamepadDirect", "1" );
#endif

	menuMode = ( in_gamepadDirect->integer && CL_UIActive() ) ? qtrue : qfalse;

	// check buttons
	for (i = 0; i < SDL_CONTROLLER_BUTTON_MAX; i++)
	{
		qboolean pressed = SDL_GameControllerGetButton(gamepad, SDL_CONTROLLER_BUTTON_A + i);

		if (pressed == stick_state.buttons[i])
		{
			continue;
		}

		stick_state.buttons[i] = pressed;

		// A release must travel the same road as its press.
		//
		// Deciding this per frame instead was a real bug with a nasty shape: a
		// button held while a menu opened had its press sent as PAD0_B and its
		// release sent as Escape, so the engine never saw PAD0_B come up and
		// +movedown stayed latched. The player then crouched for the rest of the
		// session and every later press looked like it did two things at once.
		if ( pressed )
		{
			stick_state.buttonRoute[i] = ROUTE_KEY;

			if ( IN_CutsceneActive() && IN_SkipsCutscene( i ) ) {
				stick_state.buttonRoute[i] = ROUTE_SKIP;
			} else if ( menuMode && IN_MenuKeyForPadButton( i ) ) {
				stick_state.buttonRoute[i] = ROUTE_MENU;
			} else if ( in_dpadMove->integer && IN_DpadMoveCommand( i ) ) {
				stick_state.buttonRoute[i] = ROUTE_DPAD;
			}
		}

		switch ( stick_state.buttonRoute[i] )
		{
		case ROUTE_SKIP:
			// Escape is what the game skips a cutscene on, and CL_KeyDownEvent
			// turns it into "cameraInterrupt" so the level script knows.
			Com_QueueEvent(in_eventTime, SE_KEY, K_ESCAPE, pressed, 0, NULL);
			break;

		case ROUTE_MENU:
			Com_QueueEvent(in_eventTime, SE_KEY, IN_MenuKeyForPadButton( i ), pressed, 0, NULL);
			break;

		case ROUTE_DPAD:
			// The D-pad walks, like the arrow keys on a keyboard. It stacks with
			// the stick rather than replacing it, so holding up on the D-pad
			// while aiming with the right stick works.
			//
			// The key number matters: a +command with no key argument occupies a
			// shared slot, and a release with no key argument clears every holder
			// of that button. Without it the stick's own digital movement and the
			// D-pad cancel each other out.
			Cbuf_AddText( va( "%c%s %d\n", pressed ? '+' : '-',
				IN_DpadMoveCommand( i ), K_PAD0_A + i ) );
			break;

		default:
#if SDL_VERSION_ATLEAST( 2, 0, 14 )
			if ( i >= SDL_CONTROLLER_BUTTON_MISC1 ) {
				Com_QueueEvent(in_eventTime, SE_KEY, K_PAD0_MISC1 + i - SDL_CONTROLLER_BUTTON_MISC1, pressed, 0, NULL);
			} else
#endif
			{
				Com_QueueEvent(in_eventTime, SE_KEY, K_PAD0_A + i, pressed, 0, NULL);
			}
			break;
		}

		if ( in_debugPad && in_debugPad->integer ) {
			Com_Printf( "pad: button %d %s via %s\n", i, pressed ? "down" : "up",
				stick_state.buttonRoute[i] == ROUTE_MENU ? "menu" :
				stick_state.buttonRoute[i] == ROUTE_DPAD ? "dpad" : "key" );
		}
	}

	// must defer translated axes until all real axes are processed
	// must be done this way to prevent a later mapped axis from zeroing out a previous one
	if (in_joystickUseAnalog->integer)
	{
		for (i = 0; i < MAX_JOYSTICK_AXIS; i++)
		{
			translatedAxes[i] = 0;
			translatedAxesSet[i] = qfalse;
		}
	}

	// check axes
	for (i = 0; i < SDL_CONTROLLER_AXIS_MAX; i++)
	{
		int axis = SDL_GameControllerGetAxis(gamepad, SDL_CONTROLLER_AXIS_LEFTX + i);
		int oldAxis = stick_state.oldaaxes[i];

		// The sticks are handled by IN_GamepadSticks, which reads them directly
		// instead of routing them through synthesised key presses. Letting this
		// loop see them too would emit both, and the key path is the one that
		// picks up default.cfg's turn-instead-of-strafe layout.
		if ( in_gamepadDirect->integer &&
			 ( SDL_CONTROLLER_AXIS_LEFTX + i ) <= SDL_CONTROLLER_AXIS_RIGHTY ) {
			continue;
		}

		// Smoothly ramp from dead zone to maximum value
		float f = ((float)abs(axis) / 32767.0f - in_joystickThreshold->value) / (1.0f - in_joystickThreshold->value);

		if (f < 0.0f)
			f = 0.0f;

		axis = (int)(32767 * ((axis < 0) ? -f : f));

		if (axis != oldAxis)
		{
			const int negMap[SDL_CONTROLLER_AXIS_MAX] = { K_PAD0_LEFTSTICK_LEFT,  K_PAD0_LEFTSTICK_UP,   K_PAD0_RIGHTSTICK_LEFT,  K_PAD0_RIGHTSTICK_UP, 0, 0 };
			const int posMap[SDL_CONTROLLER_AXIS_MAX] = { K_PAD0_LEFTSTICK_RIGHT, K_PAD0_LEFTSTICK_DOWN, K_PAD0_RIGHTSTICK_RIGHT, K_PAD0_RIGHTSTICK_DOWN, K_PAD0_LEFTTRIGGER, K_PAD0_RIGHTTRIGGER };

			qboolean posAnalog = qfalse, negAnalog = qfalse;
			int negKey = negMap[i];
			int posKey = posMap[i];

			if (in_joystickUseAnalog->integer)
			{
				int posAxis = 0, posSign = 0, negAxis = 0, negSign = 0;

				// get axes and axes signs for keys if available
				posAnalog = KeyToAxisAndSign(posKey, &posAxis, &posSign);
				negAnalog = KeyToAxisAndSign(negKey, &negAxis, &negSign);

				// positive to negative/neutral -> keyup if axis hasn't yet been set
				if (posAnalog && !translatedAxesSet[posAxis] && oldAxis > 0 && axis <= 0)
				{
					translatedAxes[posAxis] = 0;
					translatedAxesSet[posAxis] = qtrue;
				}

				// negative to positive/neutral -> keyup if axis hasn't yet been set
				if (negAnalog && !translatedAxesSet[negAxis] && oldAxis < 0 && axis >= 0)
				{
					translatedAxes[negAxis] = 0;
					translatedAxesSet[negAxis] = qtrue;
				}

				// negative/neutral to positive -> keydown
				if (posAnalog && axis > 0)
				{
					translatedAxes[posAxis] = axis * posSign;
					translatedAxesSet[posAxis] = qtrue;
				}

				// positive/neutral to negative -> keydown
				if (negAnalog && axis < 0)
				{
					translatedAxes[negAxis] = -axis * negSign;
					translatedAxesSet[negAxis] = qtrue;
				}
			}

			// keyups first so they get overridden by keydowns later

			// positive to negative/neutral -> keyup
			if (!posAnalog && posKey && oldAxis > 0 && axis <= 0)
				Com_QueueEvent(in_eventTime, SE_KEY, posKey, qfalse, 0, NULL);

			// negative to positive/neutral -> keyup
			if (!negAnalog && negKey && oldAxis < 0 && axis >= 0)
				Com_QueueEvent(in_eventTime, SE_KEY, negKey, qfalse, 0, NULL);

			// negative/neutral to positive -> keydown
			if (!posAnalog && posKey && oldAxis <= 0 && axis > 0)
				Com_QueueEvent(in_eventTime, SE_KEY, posKey, qtrue, 0, NULL);

			// positive/neutral to negative -> keydown
			if (!negAnalog && negKey && oldAxis >= 0 && axis < 0)
				Com_QueueEvent(in_eventTime, SE_KEY, negKey, qtrue, 0, NULL);

			stick_state.oldaaxes[i] = axis;
		}
	}

	// set translated axes
	if (in_joystickUseAnalog->integer)
	{
		for (i = 0; i < MAX_JOYSTICK_AXIS; i++)
		{
			if (translatedAxesSet[i])
				Com_QueueEvent(in_eventTime, SE_JOYSTICK_AXIS, i, translatedAxes[i], 0, NULL);
		}
	}

	IN_NoteGamepadActivity();

	if ( in_gamepadDirect->integer ) {
		IN_GamepadSticks();
	}

	IN_GamepadTriggers();
	IN_GamepadTouchpad();
	IN_GamepadGyro();
}

/*
===============
IN_GamepadTriggers

Second stage for the analogue triggers. The axis loop above already emits
K_PAD0_LEFTTRIGGER / K_PAD0_RIGHTTRIGGER once the trigger passes the shared
deadzone; this adds a deeper threshold on its own keys, so a weapon can be
aimed at a half pull and fired at a full one.
===============
*/
static void IN_GamepadTriggers( void )
{
	const int axes[2] = { SDL_CONTROLLER_AXIS_TRIGGERLEFT, SDL_CONTROLLER_AXIS_TRIGGERRIGHT };
	const int keys[2] = { K_PAD0_LEFTTRIGGER_HARD, K_PAD0_RIGHTTRIGGER_HARD };
	float hard;
	int i;

	if ( !in_triggerHard )
		return;

	hard = Com_Clamp( 0.05f, 1.0f, in_triggerHard->value );

	for ( i = 0; i < 2; i++ )
	{
		float value = (float)SDL_GameControllerGetAxis( gamepad, axes[i] ) / 32767.0f;
		qboolean down = ( value >= hard ) ? qtrue : qfalse;

		if ( down != stick_state.triggerHard[i] )
		{
			Com_QueueEvent( in_eventTime, SE_KEY, keys[i], down, 0, NULL );
			stick_state.triggerHard[i] = down;
		}
	}
}

/*
===============
IN_GamepadTouchpad

The DualSense touchpad, read by polling rather than through events so it fits
the rest of this file (SDL_GameControllerEventState is SDL_QUERY here).

A short contact that barely moves is a tap; a longer drag past a threshold is a
swipe, reported once per contact so holding a finger still after swiping does
not repeat. With in_touchpad 2 the raw motion additionally drives the view,
which is handy for the objectives and notebook screens.
===============
*/
static void IN_GamepadTouchpad( void )
{
#if SDL_VERSION_ATLEAST( 2, 0, 14 )
	const float swipeThreshold = 0.18f;   // fraction of the pad's width
	const int   tapMaxTime = 250;         // ms
	const float tapMaxMove = 0.05f;

	Uint8 state = 0;
	float x = 0.0f, y = 0.0f, pressure = 0.0f;

	if ( !in_touchpad || !in_touchpad->integer || gamepadCaps.numTouchpads <= 0 )
		return;

	if ( SDL_GameControllerGetTouchpadFinger( gamepad, 0, 0, &state, &x, &y, &pressure ) != 0 )
		return;

	if ( state && !stick_state.touchDown )
	{
		// finger down
		stick_state.touchDown = qtrue;
		stick_state.touchSwiped = qfalse;
		stick_state.touchStartX = stick_state.touchLastX = x;
		stick_state.touchStartY = stick_state.touchLastY = y;
		stick_state.touchStartTime = in_eventTime;
	}
	else if ( state && stick_state.touchDown )
	{
		float dx = x - stick_state.touchStartX;
		float dy = y - stick_state.touchStartY;

		if ( !stick_state.touchSwiped &&
			 ( fabs( dx ) > swipeThreshold || fabs( dy ) > swipeThreshold ) )
		{
			int key;

			if ( fabs( dx ) > fabs( dy ) )
				key = ( dx > 0 ) ? K_PAD0_TOUCH_SWIPE_RIGHT : K_PAD0_TOUCH_SWIPE_LEFT;
			else
				key = ( dy > 0 ) ? K_PAD0_TOUCH_SWIPE_DOWN : K_PAD0_TOUCH_SWIPE_UP;

			// A swipe is a discrete action, so send it as a press and release
			// in the same frame rather than leaving a key stuck down.
			Com_QueueEvent( in_eventTime, SE_KEY, key, qtrue, 0, NULL );
			Com_QueueEvent( in_eventTime, SE_KEY, key, qfalse, 0, NULL );
			stick_state.touchSwiped = qtrue;
		}

		if ( in_touchpad->integer >= 2 )
		{
			float mx = ( x - stick_state.touchLastX ) * in_touchpadSens->value;
			float my = ( y - stick_state.touchLastY ) * in_touchpadSens->value;

			if ( (int)mx || (int)my )
				Com_QueueEvent( in_eventTime, SE_MOUSE, (int)mx, (int)my, 0, NULL );
		}

		stick_state.touchLastX = x;
		stick_state.touchLastY = y;
	}
	else if ( !state && stick_state.touchDown )
	{
		// finger up -- a quick, still contact counts as a tap
		float dx = stick_state.touchLastX - stick_state.touchStartX;
		float dy = stick_state.touchLastY - stick_state.touchStartY;

		if ( !stick_state.touchSwiped &&
			 in_eventTime - stick_state.touchStartTime < tapMaxTime &&
			 fabs( dx ) < tapMaxMove && fabs( dy ) < tapMaxMove )
		{
			Com_QueueEvent( in_eventTime, SE_KEY, K_PAD0_TOUCH_TAP, qtrue, 0, NULL );
			Com_QueueEvent( in_eventTime, SE_KEY, K_PAD0_TOUCH_TAP, qfalse, 0, NULL );
		}

		stick_state.touchDown = qfalse;
	}
#endif
}

/*
===============
IN_GyroSetAxes

Puts the gyro's contribution on the two joystick axes, but only when it has
changed.

CL_JoystickEvent latches -- cl.joystickAxis keeps whatever was last written to
it until something writes again. That is right for a stick, which reports a
position and reports it every frame, and wrong for anything that can decide it
has nothing to say: the old code returned early once both axes fell inside the
deadzone, which left the last non-zero reading latched and the view turning at
that rate for good. Going quiet has to be sent, exactly once.
===============
*/
static void IN_GyroSetAxes( int pitch, int yaw )
{
	if ( pitch != gyroAxis[0] ) {
		gyroAxis[0] = pitch;
		Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, AXIS_GYRO_PITCH, pitch, 0, NULL );
	}

	if ( yaw != gyroAxis[1] ) {
		gyroAxis[1] = yaw;
		Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, AXIS_GYRO_YAW, yaw, 0, NULL );
	}
}

/*
===============
IN_GyroReset

Throws away the resting-bias estimate and puts both axes back to zero.

Called whenever the controller list changes. The estimate describes one physical
sensor, so carrying it across to the pad that just arrived starts that one off
with a deliberate error; and a pad unplugged mid-turn has to have its last
reading cleared, or nothing will ever clear it -- IN_GamepadGyro is only reached
while a gamepad is open.
===============
*/
static void IN_GyroReset( void )
{
	Com_Memset( gyroBias, 0, sizeof( gyroBias ) );
	gyroRestSince = 0;
	gyroSampleTime = 0;

	// Not through IN_GyroSetAxes: the axes may well be holding a value this
	// side never sent, so the zeros go out unconditionally.
	gyroAxis[0] = 0;
	gyroAxis[1] = 0;

	Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, AXIS_GYRO_PITCH, 0, 0, NULL );
	Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, AXIS_GYRO_YAW,   0, 0, NULL );
}

/*
===============
IN_GyroDeadzone

Takes the deadzone off a rate rather than cutting at it.

A threshold that passes the whole reading once it is exceeded still passes the
whole of whatever bias is left in that reading, which is why the drift got
quieter but never went away. Subtracting leaves nothing at the threshold and
grows smoothly from there, so an offset just outside the deadzone contributes
almost nothing instead of a full deadzone's worth.

Per axis, unlike the sticks' radial deadzone in IN_ApplyStickCurve: a bias sits
on one axis and has to come off there whatever the other axis is doing.
===============
*/
#if SDL_VERSION_ATLEAST( 2, 0, 14 )
static float IN_GyroDeadzone( float rate, float deadzone )
{
	if ( rate > deadzone ) {
		return rate - deadzone;
	}

	if ( rate < -deadzone ) {
		return rate + deadzone;
	}

	return 0.0f;
}
#endif

/*
===============
IN_GamepadGyro

Gyro aiming. SDL reports angular velocity in rad/s as
{ pitch, yaw, roll } in the controller's own frame.

This is fed in as joystick axes rather than as mouse motion on purpose:
CL_JoystickMove scales its contribution by frametime, which is wrong for a
stick (a stick is a position) but exactly right for a gyro (a gyro is a rate,
and angle = rate * dt).
===============
*/
static void IN_GamepadGyro( void )
{
#if SDL_VERSION_ATLEAST( 2, 0, 14 )
	float data[3];
	float pitch, yaw, scale, deadzone, magnitude;
	int   now, elapsed, i;

	if ( !in_gyro || !in_gyro->integer || !gamepadCaps.hasGyro )
	{
		IN_GyroSetAxes( 0, 0 );
		return;
	}

	if ( SDL_GameControllerGetSensorData( gamepad, SDL_SENSOR_GYRO, data, 3 ) != 0 )
	{
		IN_GyroSetAxes( 0, 0 );
		return;
	}

	now = Sys_Milliseconds();
	elapsed = gyroSampleTime ? now - gyroSampleTime : 0;
	gyroSampleTime = now;

	// Take the resting bias out before anything else.
	//
	// A gyro at rest does not read zero; it reads a small, slowly wandering
	// offset. A deadzone can hide it but cannot remove it -- anything just
	// outside the deadzone still leaks, and the aim creeps across the screen
	// while the controller sits on a table. So the offset is measured instead:
	// whenever the readings have been small for a moment the estimate is pulled
	// gently towards them, and it is subtracted from every sample.
	//
	// Roll is estimated too although nothing reads it, because it is the third
	// axis of the same test for "is this controller moving at all", and a pad
	// being rolled is a pad in someone's hands.
	magnitude = 0.0f;

	for ( i = 0; i < 3; i++ ) {
		data[i] -= gyroBias[i];
		magnitude += data[i] * data[i];
	}

	if ( magnitude < GYRO_REST_RATE * GYRO_REST_RATE ) {
		if ( !gyroRestSince ) {
			gyroRestSince = now;
		}

		if ( now - gyroRestSince > GYRO_REST_SETTLE ) {
			float rate = elapsed * 0.001f / GYRO_BIAS_TAU;

			// A long frame -- a level load, the app coming back from the
			// background -- must not let one sample become the whole estimate.
			if ( rate > 1.0f ) {
				rate = 1.0f;
			}

			for ( i = 0; i < 3; i++ ) {
				gyroBias[i] += data[i] * rate;
			}
		}
	} else {
		gyroRestSince = 0;
	}

	// The bias is learned above this test on purpose. "Only while aiming" is
	// the mode where a stale estimate hurts most: the scope comes up, the gyro
	// starts being read, and it has to be right at that instant rather than
	// after a quarter of a second of settling that the player spends drifting
	// off target.
	if ( in_gyro->integer == 2 && cl.cgameSensitivity >= 0.95f )
	{
		// RTCW has no explicit ADS flag, but cgame scales cgameSensitivity down
		// whenever the view is zoomed (scope, binoculars, snooper), which is
		// exactly the state we want gyro for.
		IN_GyroSetAxes( 0, 0 );
		return;
	}

	deadzone = in_gyroDeadzone->value;

	// data[0] is pitch (tipping the pad's nose up and down), data[1] is yaw
	// (swinging it left and right).
	pitch = IN_GyroDeadzone( data[0], deadzone );
	yaw   = IN_GyroDeadzone( data[1], deadzone );

	// Direction, decided here rather than left to the signs of j_yaw and
	// j_pitch. Negating both axes and then multiplying by two cvars of opposite
	// sign did come out right with the defaults, but only by cancellation: the
	// vertical was one edit to j_pitch away from running backwards, and nothing
	// in either file said so.
	//
	// SDL's frame, with the pad held in front of you: +x points right, +y up,
	// +z towards you, and rotation is counter-clockwise seen from the positive
	// end of each axis. So a positive data[0] lifts the nose and a positive
	// data[1] swings it to the left; following the pad one for one means the
	// view goes up and to the left. The axes are in the mouse's convention --
	// positive yaw right, positive pitch down -- so both are negated once.
	pitch = -pitch;
	yaw   = -yaw;

	// Inverted look has to reach the gyro as well. It only flipped the stick
	// before, so switching it on left the two halves of the same aim pulling
	// against each other: the thumb turned one way, the wrist the other. Pitch
	// only, exactly as in IN_GamepadSticks.
	if ( in_invertLook->integer ) {
		pitch = -pitch;
	}

	// Last resort for a sensor that does not report in the frame SDL documents.
	// There is no way to tell from here which way a given pad measures, and no
	// way for the player to find out except by trying it.
	if ( in_gyroInvertPitch->integer ) {
		pitch = -pitch;
	}
	if ( in_gyroInvertYaw->integer ) {
		yaw = -yaw;
	}

	// rad/s -> view degrees per second -> axis units. in_gyroSens is the only
	// thing in here that a player sets, it multiplies both axes by the same
	// number, and nothing else in the chain scales them again.
	scale = in_gyroSens->value * GYRO_VIEW_DEGREES_PER_RAD * GYRO_AXIS_SCALE;

	IN_GyroSetAxes(
		(int)Com_Clamp( -32767.0f, 32767.0f, pitch * scale ),
		(int)Com_Clamp( -32767.0f, 32767.0f, yaw * scale ) );
#else
	IN_GyroSetAxes( 0, 0 );
#endif
}


/*
===============
IN_JoyMove
===============
*/
static void IN_JoyMove( void )
{
	unsigned int axes = 0;
	unsigned int hats = 0;
	int total = 0;
	int i = 0;

	if (gamepad)
	{
		IN_GamepadMove();
		return;
	}

	if (!stick)
		return;

	SDL_JoystickUpdate();

	// update the ball state.
	total = SDL_JoystickNumBalls(stick);
	if (total > 0)
	{
		int balldx = 0;
		int balldy = 0;
		for (i = 0; i < total; i++)
		{
			int dx = 0;
			int dy = 0;
			SDL_JoystickGetBall(stick, i, &dx, &dy);
			balldx += dx;
			balldy += dy;
		}
		if (balldx || balldy)
		{
			// !!! FIXME: is this good for stick balls, or just mice?
			// Scale like the mouse input...
			if (abs(balldx) > 1)
				balldx *= 2;
			if (abs(balldy) > 1)
				balldy *= 2;
			Com_QueueEvent( in_eventTime, SE_MOUSE, balldx, balldy, 0, NULL );
		}
	}

	// now query the stick buttons...
	total = SDL_JoystickNumButtons(stick);
	if (total > 0)
	{
		if (total > ARRAY_LEN(stick_state.buttons))
			total = ARRAY_LEN(stick_state.buttons);
		for (i = 0; i < total; i++)
		{
			qboolean pressed = (SDL_JoystickGetButton(stick, i) != 0);
			if (pressed != stick_state.buttons[i])
			{
				Com_QueueEvent( in_eventTime, SE_KEY, K_JOY1 + i, pressed, 0, NULL );
				stick_state.buttons[i] = pressed;
			}
		}
	}

	// look at the hats...
	total = SDL_JoystickNumHats(stick);
	if (total > 0)
	{
		if (total > 4) total = 4;
		for (i = 0; i < total; i++)
		{
			((Uint8 *)&hats)[i] = SDL_JoystickGetHat(stick, i);
		}
	}

	// update hat state
	if (hats != stick_state.oldhats)
	{
		for( i = 0; i < 4; i++ ) {
			if( ((Uint8 *)&hats)[i] != ((Uint8 *)&stick_state.oldhats)[i] ) {
				// release event
				switch( ((Uint8 *)&stick_state.oldhats)[i] ) {
					case SDL_HAT_UP:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 0], qfalse, 0, NULL );
						break;
					case SDL_HAT_RIGHT:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 1], qfalse, 0, NULL );
						break;
					case SDL_HAT_DOWN:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 2], qfalse, 0, NULL );
						break;
					case SDL_HAT_LEFT:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 3], qfalse, 0, NULL );
						break;
					case SDL_HAT_RIGHTUP:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 0], qfalse, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 1], qfalse, 0, NULL );
						break;
					case SDL_HAT_RIGHTDOWN:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 2], qfalse, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 1], qfalse, 0, NULL );
						break;
					case SDL_HAT_LEFTUP:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 0], qfalse, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 3], qfalse, 0, NULL );
						break;
					case SDL_HAT_LEFTDOWN:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 2], qfalse, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 3], qfalse, 0, NULL );
						break;
					default:
						break;
				}
				// press event
				switch( ((Uint8 *)&hats)[i] ) {
					case SDL_HAT_UP:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 0], qtrue, 0, NULL );
						break;
					case SDL_HAT_RIGHT:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 1], qtrue, 0, NULL );
						break;
					case SDL_HAT_DOWN:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 2], qtrue, 0, NULL );
						break;
					case SDL_HAT_LEFT:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 3], qtrue, 0, NULL );
						break;
					case SDL_HAT_RIGHTUP:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 0], qtrue, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 1], qtrue, 0, NULL );
						break;
					case SDL_HAT_RIGHTDOWN:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 2], qtrue, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 1], qtrue, 0, NULL );
						break;
					case SDL_HAT_LEFTUP:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 0], qtrue, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 3], qtrue, 0, NULL );
						break;
					case SDL_HAT_LEFTDOWN:
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 2], qtrue, 0, NULL );
						Com_QueueEvent( in_eventTime, SE_KEY, hat_keys[4*i + 3], qtrue, 0, NULL );
						break;
					default:
						break;
				}
			}
		}
	}

	// save hat state
	stick_state.oldhats = hats;

	// finally, look at the axes...
	total = SDL_JoystickNumAxes(stick);
	if (total > 0)
	{
		if (in_joystickUseAnalog->integer)
		{
			if (total > MAX_JOYSTICK_AXIS) total = MAX_JOYSTICK_AXIS;
			for (i = 0; i < total; i++)
			{
				Sint16 axis = SDL_JoystickGetAxis(stick, i);
				float f = ( (float) abs(axis) ) / 32767.0f;
				
				if( f < in_joystickThreshold->value ) axis = 0;

				if ( axis != stick_state.oldaaxes[i] )
				{
					Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, i, axis, 0, NULL );
					stick_state.oldaaxes[i] = axis;
				}
			}
		}
		else
		{
			if (total > 16) total = 16;
			for (i = 0; i < total; i++)
			{
				Sint16 axis = SDL_JoystickGetAxis(stick, i);
				float f = ( (float) axis ) / 32767.0f;
				if( f < -in_joystickThreshold->value ) {
					axes |= ( 1 << ( i * 2 ) );
				} else if( f > in_joystickThreshold->value ) {
					axes |= ( 1 << ( ( i * 2 ) + 1 ) );
				}
			}
		}
	}

	/* Time to update axes state based on old vs. new. */
	if (axes != stick_state.oldaxes)
	{
		for( i = 0; i < 16; i++ ) {
			if( ( axes & ( 1 << i ) ) && !( stick_state.oldaxes & ( 1 << i ) ) ) {
				Com_QueueEvent( in_eventTime, SE_KEY, joy_keys[i], qtrue, 0, NULL );
			}

			if( !( axes & ( 1 << i ) ) && ( stick_state.oldaxes & ( 1 << i ) ) ) {
				Com_QueueEvent( in_eventTime, SE_KEY, joy_keys[i], qfalse, 0, NULL );
			}
		}
	}

	/* Save for future generations. */
	stick_state.oldaxes = axes;
}

/*
===============
IN_PadEchoKey

iPadOS hands a game controller's buttons to the app twice: once as controller
input, and again as UIPress events for menu navigation. SDL turns the second
copy into keyboard keys -- D-pad to the arrows, Cross to Return, Options to
Escape, the PS button to Pause -- and RTCW's stock keyboard bindings then act on
them as well as on ours.

The result was one press doing two things: D-pad left walked left and turned the
view, Cross jumped and opened the door, Options opened the menu and printed
"unknown cmd pause".

Dropping these keys outright would break a real Bluetooth keyboard, so a key is
only dropped while the controller button that would have produced it is actually
held. A release is matched to the press that was dropped, since the button may
already be up by then.

Returns qtrue if the key is an echo of the pad and should be ignored.
===============
*/
static qboolean IN_PadEchoKey( int key, qboolean down )
{
	static qboolean dropped[8];
	int i;

	const struct { int key; int button; } echoes[] = {
		{ K_LEFTARROW,  SDL_CONTROLLER_BUTTON_DPAD_LEFT  },
		{ K_RIGHTARROW, SDL_CONTROLLER_BUTTON_DPAD_RIGHT },
		{ K_UPARROW,    SDL_CONTROLLER_BUTTON_DPAD_UP    },
		{ K_DOWNARROW,  SDL_CONTROLLER_BUTTON_DPAD_DOWN  },
		{ K_ENTER,      SDL_CONTROLLER_BUTTON_A          },
		{ K_ESCAPE,     SDL_CONTROLLER_BUTTON_START      },
		{ K_ESCAPE,     SDL_CONTROLLER_BUTTON_B          },
		{ K_PAUSE,      SDL_CONTROLLER_BUTTON_GUIDE      },
	};

	if ( !gamepad ) {
		return qfalse;
	}

	for ( i = 0; i < (int)ARRAY_LEN( echoes ); i++ ) {
		if ( echoes[i].key != key ) {
			continue;
		}

		if ( down ) {
			if ( SDL_GameControllerGetButton( gamepad, echoes[i].button ) ) {
				dropped[i] = qtrue;
				if ( in_debugPad && in_debugPad->integer ) {
					Com_Printf( "pad: dropped keyboard echo of button %d\n",
						echoes[i].button );
				}
				return qtrue;
			}
		} else if ( dropped[i] ) {
			dropped[i] = qfalse;
			return qtrue;
		}
	}

	return qfalse;
}

/*
===============
IN_ProcessEvents
===============
*/
static void IN_ProcessEvents( void )
{
	SDL_Event e;
	keyNum_t key = 0;
	static keyNum_t lastKeyDown = 0;

	if( !SDL_WasInit( SDL_INIT_VIDEO ) )
			return;

	while( SDL_PollEvent( &e ) )
	{
		switch( e.type )
		{
			case SDL_KEYDOWN:
				if ( e.key.repeat && Key_GetCatcher( ) == 0 )
					break;

				if( ( key = IN_TranslateSDLToQ3Key( &e.key.keysym, qtrue ) ) )
				{
					if ( IN_PadEchoKey( key, qtrue ) )
						break;

					Com_QueueEvent( in_eventTime, SE_KEY, key, qtrue, 0, NULL );
				}

				if( key == K_BACKSPACE )
					Com_QueueEvent( in_eventTime, SE_CHAR, CTRL('h'), 0, 0, NULL );
				else if( keys[K_CTRL].down && key >= 'a' && key <= 'z' )
					Com_QueueEvent( in_eventTime, SE_CHAR, CTRL(key), 0, 0, NULL );

				lastKeyDown = key;
				break;

			case SDL_KEYUP:
				if( ( key = IN_TranslateSDLToQ3Key( &e.key.keysym, qfalse ) ) )
				{
					if ( IN_PadEchoKey( key, qfalse ) )
						break;

					Com_QueueEvent( in_eventTime, SE_KEY, key, qfalse, 0, NULL );
				}

				lastKeyDown = 0;
				break;

			case SDL_TEXTINPUT:
				if( lastKeyDown != K_CONSOLE )
				{
					char *c = e.text.text;

					// Quick and dirty UTF-8 to UTF-32 conversion
					while( *c )
					{
						int utf32 = 0;

						if( ( *c & 0x80 ) == 0 )
							utf32 = *c++;
						else if( ( *c & 0xE0 ) == 0xC0 ) // 110x xxxx
						{
							utf32 |= ( *c++ & 0x1F ) << 6;
							utf32 |= ( *c++ & 0x3F );
						}
						else if( ( *c & 0xF0 ) == 0xE0 ) // 1110 xxxx
						{
							utf32 |= ( *c++ & 0x0F ) << 12;
							utf32 |= ( *c++ & 0x3F ) << 6;
							utf32 |= ( *c++ & 0x3F );
						}
						else if( ( *c & 0xF8 ) == 0xF0 ) // 1111 0xxx
						{
							utf32 |= ( *c++ & 0x07 ) << 18;
							utf32 |= ( *c++ & 0x3F ) << 12;
							utf32 |= ( *c++ & 0x3F ) << 6;
							utf32 |= ( *c++ & 0x3F );
						}
						else
						{
							Com_DPrintf( "Unrecognised UTF-8 lead byte: 0x%x\n", (unsigned int)*c );
							c++;
						}

						if( utf32 != 0 )
						{
							if( IN_IsConsoleKey( 0, utf32 ) )
							{
								Com_QueueEvent( in_eventTime, SE_KEY, K_CONSOLE, qtrue, 0, NULL );
								Com_QueueEvent( in_eventTime, SE_KEY, K_CONSOLE, qfalse, 0, NULL );
							}
							else
								Com_QueueEvent( in_eventTime, SE_CHAR, utf32, 0, 0, NULL );
						}
					}
				}
				break;

#if TARGET_OS_IPHONE
			case SDL_FINGERDOWN:
			case SDL_FINGERUP:
				if ( in_debugTouch && in_debugTouch->integer ) {
					Com_Printf( "touch: finger %s at %.3f,%.3f\n",
						e.type == SDL_FINGERDOWN ? "down" : "up",
						e.tfinger.x, e.tfinger.y );
				}
				break;
#endif

			case SDL_MOUSEMOTION:
#if TARGET_OS_IPHONE
				if ( in_debugTouch && in_debugTouch->integer &&
					 e.motion.which == SDL_TOUCH_MOUSEID ) {
					Com_Printf( "touch: move to %d,%d (rel %d,%d) of %dx%d\n",
						e.motion.x, e.motion.y, e.motion.xrel, e.motion.yrel,
						cls.glconfig.vidWidth, cls.glconfig.vidHeight );
				}
#endif
				if( mouseActive )
				{
					IN_QueueMouseDelta( e.motion.xrel, e.motion.yrel );
				}
				break;

			case SDL_MOUSEBUTTONDOWN:
			case SDL_MOUSEBUTTONUP:
				{
					int b;

#if TARGET_OS_IPHONE
					// There is no console on a tablet, so the only way to see
					// what the touch layer is doing is to write it down.
					if ( in_debugTouch && in_debugTouch->integer ) {
						Com_Printf( "touch: button %d %s which=%s catcher=%d state=%d ui=%d\n",
							e.button.button,
							e.type == SDL_MOUSEBUTTONDOWN ? "down" : "up",
							e.button.which == SDL_TOUCH_MOUSEID ? "touch" : "mouse",
							Key_GetCatcher(), clc.state, CL_UIActive() );
					}

					// A click SDL made up from a touch is exactly what the menus
					// need and exactly what gameplay does not: there it lands on
					// +attack, so simply touching the screen fires the weapon.
					// Shooting by touch is the overlay's fire button instead.
					if ( e.button.which == SDL_TOUCH_MOUSEID && !CL_UIActive() ) {
						break;
					}
#endif
					switch( e.button.button )
					{
						case SDL_BUTTON_LEFT:   b = K_MOUSE1;     break;
						case SDL_BUTTON_MIDDLE: b = K_MOUSE3;     break;
						case SDL_BUTTON_RIGHT:  b = K_MOUSE2;     break;
						case SDL_BUTTON_X1:     b = K_MOUSE4;     break;
						case SDL_BUTTON_X2:     b = K_MOUSE5;     break;
						default:                b = K_AUX1 + ( e.button.button - SDL_BUTTON_X2 + 1 ) % 16; break;
					}
					Com_QueueEvent( in_eventTime, SE_KEY, b,
						( e.type == SDL_MOUSEBUTTONDOWN ? qtrue : qfalse ), 0, NULL );
				}
				break;

			case SDL_MOUSEWHEEL:
				if( e.wheel.y > 0 )
				{
					Com_QueueEvent( in_eventTime, SE_KEY, K_MWHEELUP, qtrue, 0, NULL );
					Com_QueueEvent( in_eventTime, SE_KEY, K_MWHEELUP, qfalse, 0, NULL );
				}
				else if( e.wheel.y < 0 )
				{
					Com_QueueEvent( in_eventTime, SE_KEY, K_MWHEELDOWN, qtrue, 0, NULL );
					Com_QueueEvent( in_eventTime, SE_KEY, K_MWHEELDOWN, qfalse, 0, NULL );
				}
				break;

			case SDL_CONTROLLERDEVICEADDED:
			case SDL_CONTROLLERDEVICEREMOVED:
				if (in_joystick->integer)
					IN_InitJoystick();
#if TARGET_OS_IPHONE
				// Show or hide the on-screen controls to match: a controller
				// arriving is exactly when the overlay should get out of the way.
				Sys_IOS_TouchOverlayUpdate();
#endif
				break;

			case SDL_QUIT:
				Cbuf_ExecuteText(EXEC_NOW, "quit Closed window\n");
				break;

			case SDL_WINDOWEVENT:
				switch( e.window.event )
				{
					case SDL_WINDOWEVENT_RESIZED:
						{
							int width, height;

							width = e.window.data1;
							height = e.window.data2;

							// ignore this event on fullscreen
							if( cls.glconfig.isFullscreen )
							{
								break;
							}

							// check if size actually changed
							if( cls.glconfig.vidWidth == width && cls.glconfig.vidHeight == height )
							{
								break;
							}

							Cvar_SetValue( "r_customwidth", width );
							Cvar_SetValue( "r_customheight", height );
							Cvar_Set( "r_mode", "-1" );

							// Wait until user stops dragging for 1 second, so
							// we aren't constantly recreating the GL context while
							// he tries to drag...
							vidRestartTime = Sys_Milliseconds( ) + 1000;
						}
						break;

					case SDL_WINDOWEVENT_MINIMIZED:    Cvar_SetValue( "com_minimized", 1 ); break;
					case SDL_WINDOWEVENT_RESTORED:
					case SDL_WINDOWEVENT_MAXIMIZED:    Cvar_SetValue( "com_minimized", 0 ); break;
					case SDL_WINDOWEVENT_FOCUS_LOST:   Cvar_SetValue( "com_unfocused", 1 ); break;
					case SDL_WINDOWEVENT_FOCUS_GAINED: Cvar_SetValue( "com_unfocused", 0 ); break;
				}
				break;

			default:
				break;
		}
	}
}

/*
===============
IN_Frame
===============
*/
#if TARGET_OS_IPHONE
/*
===============
Touch overlay bridge

The on-screen controls are a UIKit view (ios_touch.m) over SDL's GL view, so
they need a way into the engine's event queue.

No locking is needed here, which is worth stating: UIKit is pumped *by*
Com_Frame -- SDL's UIKit_PumpEvents drains the CFRunLoop on every SDL_PollEvent
-- so these run on the same thread as the frame loop, never concurrently.
===============
*/
void IOSTouch_QueueKey( int key, int down )
{
	Com_QueueEvent( in_eventTime, SE_KEY, key, down ? qtrue : qfalse, 0, NULL );
}

void IOSTouch_QueueAxis( int axis, int value )
{
	// Reuses the joystick path, so the on-screen stick honours j_forward and
	// j_side exactly like a real one.
	Com_QueueEvent( in_eventTime, SE_JOYSTICK_AXIS, axis, value, 0, NULL );
}

void IOSTouch_QueueMouse( int dx, int dy )
{
	// Deliberately mouse rather than joystick: CL_MouseMove is not
	// frametime-scaled whereas CL_JoystickMove is, and the unscaled path is what
	// makes touch look feel 1:1.
	IN_QueueMouseDelta( dx, dy );
}

/*
===============
IOSTouch_QueueMouseTo

Put the menu cursor on a point in the game's 640x480 menu space.

Touch is absolute and the UI's cursor is not -- it only accepts deltas, and it
lives inside the UI VM where nothing outside can read it -- so the difference is
worked out against the shadow copy IN_QueueMouseDelta keeps.
===============
*/
void IOSTouch_QueueMouseTo( int x, int y )
{
	IN_QueueMouseDelta( x - menuCursorX, y - menuCursorY );
}


int IOSTouch_ControllerConnected( void )
{
	// Being connected is not enough to take the on-screen controls away. iOS
	// reports a gamepad that nobody plugged in -- the simulator always does, and
	// a device may too -- and hiding the controls on that alone leaves a tablet
	// with no way to play at all. Wait until the pad is actually used.
	return gamepad != NULL && gamepadUsed;
}

int IOSTouch_DebugEnabled( void )
{
	return in_debugTouch && in_debugTouch->integer;
}

/*
===============
IOSTouch_CinematicActive

Whether a cutscene is playing, of either kind: a RoQ movie (clc.state is
CA_CINEMATIC) or an in-engine scripted camera (com_cameraMode). The overlay uses
this to turn a tap into "skip".
===============
*/
int IOSTouch_CinematicActive( void )
{
	return IN_CutsceneActive() ? 1 : 0;
}

/*
===============
IOSTouch_SkipCinematic

Escape, for both kinds of cutscene. That is the key the game itself skips on, so
this takes the same route: CL_KeyDownEvent turns it into "cameraInterrupt" for a
scripted camera, which lets the level script know the cutscene was cut short,
and SCR_StopCinematic for a RoQ movie.

Stopping the camera directly instead would leave the script waiting for an end
that never comes.
===============
*/
void IOSTouch_SkipCinematic( void )
{
	Com_QueueEvent( in_eventTime, SE_KEY, K_ESCAPE, qtrue, 0, NULL );
	Com_QueueEvent( in_eventTime, SE_KEY, K_ESCAPE, qfalse, 0, NULL );
}

/*
===============
IOSTouch_QueueCommand

Run a +command / -command on the overlay's behalf, with its own key number.

The key number is what keeps two sources of the same button apart: a -command
without one releases every holder, so the on-screen controls and the pad would
cancel each other.
===============
*/
void IOSTouch_QueueCommand( const char *command, int key )
{
	if ( !command || !*command ) {
		return;
	}

	Cbuf_AddText( va( "%s %d\n", command, key ) );
}

float IOSTouch_LookSensitivity( void )
{
	if ( !in_touchLookSens || in_touchLookSens->value <= 0.0f ) {
		return 1.0f;
	}

	return in_touchLookSens->value;
}

int IOSTouch_MovementAxis( int forward )
{
	return forward ? Cvar_VariableIntegerValue( "j_forward_axis" )
	               : Cvar_VariableIntegerValue( "j_side_axis" );
}

static qboolean iosSuspended = qfalse;

// The renderer owns SDL_glContext, so stash the current one on the way out
// rather than reaching into sdl_glimp.c for it.
static SDL_GLContext iosSavedContext = NULL;

/*
===============
IN_IOSAppEventWatch

iOS kills an app that issues any GL command while backgrounded, and the
drawable's storage is discarded when it goes away. Both have to be handled
*synchronously*: once applicationDidEnterBackground: returns the process is
frozen, so noticing the state change on the next poll of the event queue is
already too late. Hence an event watch, which SDL calls from inside
SDL_PumpEvents on the main thread, rather than a case in IN_ProcessEvents.
===============
*/
static int SDLCALL IN_IOSAppEventWatch( void *userdata, SDL_Event *event )
{
	switch ( event->type )
	{
		case SDL_APP_WILLENTERBACKGROUND:
			iosSuspended = qtrue;
			iosSavedContext = SDL_GL_GetCurrentContext();
			S_StopAllSounds();
			break;

		case SDL_APP_DIDENTERBACKGROUND:
			// Finish what is already submitted and give up the context before
			// we are frozen.
			SDL_GL_MakeCurrent( SDL_window, NULL );
			break;

		case SDL_APP_WILLENTERFOREGROUND:
			if ( iosSavedContext ) {
				SDL_GL_MakeCurrent( SDL_window, iosSavedContext );
			}
			break;

		case SDL_APP_DIDENTERFOREGROUND:
			iosSuspended = qfalse;
			break;

		case SDL_APP_LOWMEMORY:
			Com_Printf( "iOS: low memory warning\n" );
			break;
	}

	return 0;
}

/*
===============
IN_IsSuspended

Asked by the frame loop so it can idle instead of rendering while backgrounded.
===============
*/
qboolean IN_IsSuspended( void )
{
	return iosSuspended;
}
#endif

void IN_Frame( void )
{
	qboolean loading;

	IN_JoyMove( );

	// If not DISCONNECTED (main menu) or ACTIVE (in game), we're loading
	loading = ( clc.state != CA_DISCONNECTED && clc.state != CA_ACTIVE );

	// update isFullscreen since it might of changed since the last vid_restart
	cls.glconfig.isFullscreen = Cvar_VariableIntegerValue( "r_fullscreen" ) != 0;

	if( !cls.glconfig.isFullscreen && ( Key_GetCatcher( ) & KEYCATCH_CONSOLE ) )
	{
		// Console is down in windowed mode
		IN_DeactivateMouse( cls.glconfig.isFullscreen );
	}
	else if( !cls.glconfig.isFullscreen && loading )
	{
		// Loading in windowed mode
		IN_DeactivateMouse( cls.glconfig.isFullscreen );
	}
	else if( !( SDL_GetWindowFlags( SDL_window ) & SDL_WINDOW_INPUT_FOCUS ) )
	{
		// Window not got focus
		IN_DeactivateMouse( cls.glconfig.isFullscreen );
	}
	else
		IN_ActivateMouse( cls.glconfig.isFullscreen );

	IN_ProcessEvents( );

#if TARGET_OS_IPHONE
	// Cheap when nothing changed, and it has to run every frame: the overlay
	// hides itself whenever a menu, the console or a loading screen takes over.
	Sys_IOS_TouchOverlayUpdate( );
	Sys_IOS_PerfFrame( );
	Sys_IOS_GyroFrame( );
#endif

	// Set event time for next frame to earliest possible time an event could happen
	in_eventTime = Sys_Milliseconds( );

	// In case we had to delay actual restart of video system
	if( ( vidRestartTime != 0 ) && ( vidRestartTime < Sys_Milliseconds( ) ) )
	{
		vidRestartTime = 0;
		Cbuf_AddText( "vid_restart\n" );
	}
}

/*
===============
IN_Init
===============
*/
void IN_Init( void *windowData )
{
	int appState;

	if( !SDL_WasInit( SDL_INIT_VIDEO ) )
	{
		Com_Error( ERR_FATAL, "IN_Init called before SDL_Init( SDL_INIT_VIDEO )" );
		return;
	}

	SDL_window = (SDL_Window *)windowData;

	Com_DPrintf( "\n------- Input Initialization -------\n" );

	in_keyboardDebug = Cvar_Get( "in_keyboardDebug", "0", CVAR_ARCHIVE );

	// mouse variables
	in_mouse = Cvar_Get( "in_mouse", "1", CVAR_ARCHIVE );
	in_nograb = Cvar_Get( "in_nograb", "0", CVAR_ARCHIVE );

#if TARGET_OS_IPHONE
	// A gamepad is the primary input device here, so it is on by default, and
	// not latched: controllers get paired and unpaired while the game is
	// running and requiring in_restart for that would be absurd.
	in_joystick = Cvar_Get( "in_joystick", "1", CVAR_ARCHIVE );
#else
	in_joystick = Cvar_Get( "in_joystick", "0", CVAR_ARCHIVE|CVAR_LATCH );
#endif
	in_joystickThreshold = Cvar_Get( "joy_threshold", "0.12", CVAR_ARCHIVE );

	// DualSense extras. All default to off or neutral so a plain gamepad
	// behaves exactly as before.
	in_gyro         = Cvar_Get( "in_gyro",         "0",    CVAR_ARCHIVE );
	in_gyroSens     = Cvar_Get( "in_gyroSens",     "1.0",  CVAR_ARCHIVE );
	in_gyroDeadzone = Cvar_Get( "in_gyroDeadzone", "0.02", CVAR_ARCHIVE );

	// Off by default because SDL documents which way a controller's gyro
	// reports and the iPad's own sensor is worked out from gravity, so both
	// should already be the right way round. These exist because a sensor that
	// disagrees cannot be detected from here, only felt by the player, and the
	// alternative to a toggle is a rebuild. Read by ios_gyro.m as well, so the
	// two gyros always agree with each other.
	in_gyroInvertYaw   = Cvar_Get( "in_gyroInvertYaw",   "0", CVAR_ARCHIVE );
	in_gyroInvertPitch = Cvar_Get( "in_gyroInvertPitch", "0", CVAR_ARCHIVE );
	in_touchpad     = Cvar_Get( "in_touchpad",     "1",    CVAR_ARCHIVE );
	in_touchpadSens = Cvar_Get( "in_touchpadSens", "600",  CVAR_ARCHIVE );
	in_triggerSoft  = Cvar_Get( "in_triggerSoft",  "0.12", CVAR_ARCHIVE );
	in_triggerHard  = Cvar_Get( "in_triggerHard",  "0.75", CVAR_ARCHIVE );
	in_rumble       = Cvar_Get( "in_rumble",       "100",  CVAR_ARCHIVE );
	in_ledFeedback  = Cvar_Get( "in_ledFeedback",  "1",    CVAR_ARCHIVE );

	in_gamepadDirect   = Cvar_Get( "in_gamepadDirect",   "1",  CVAR_ARCHIVE );
	in_debugTouch      = Cvar_Get( "in_debugTouch",      "0",  CVAR_ARCHIVE );
	in_debugPad        = Cvar_Get( "in_debugPad",        "0",  CVAR_ARCHIVE );
	in_touchLookSens   = Cvar_Get( "in_touchLookSens",   "1.0", CVAR_ARCHIVE );
	in_stickExpo       = Cvar_Get( "in_stickExpo",       "0.35",  CVAR_ARCHIVE );
	in_moveExpo        = Cvar_Get( "in_moveExpo",        "0.15", CVAR_ARCHIVE );
	in_moveDigital     = Cvar_Get( "in_moveDigital",     "1",    CVAR_ARCHIVE );
	in_dpadMove        = Cvar_Get( "in_dpadMove",        "1",    CVAR_ARCHIVE );
	in_invertLook      = Cvar_Get( "in_invertLook",      "0",  CVAR_ARCHIVE );
	in_menuCursorSpeed = Cvar_Get( "in_menuCursorSpeed", "6", CVAR_ARCHIVE );

	in_lookYawSpeed    = Cvar_Get( "in_lookYawSpeed",   "220", CVAR_ARCHIVE );
	in_lookPitchSpeed  = Cvar_Get( "in_lookPitchSpeed", "190", CVAR_ARCHIVE );

	Cvar_CheckRange( in_stickExpo,       0.0f,  1.0f,  qfalse );
	Cvar_CheckRange( in_moveExpo,        0.0f,  1.0f,  qfalse );
	Cvar_CheckRange( in_menuCursorSpeed, 1.0f,  60.0f, qfalse );
	Cvar_CheckRange( in_lookYawSpeed,    20.0f, 720.0f, qfalse );
	Cvar_CheckRange( in_lookPitchSpeed,  20.0f, 720.0f, qfalse );

	Cvar_CheckRange( in_gyroSens,     0.05f, 10.0f, qfalse );
	Cvar_CheckRange( in_gyroDeadzone, 0.0f,  1.0f,  qfalse );
	Cvar_CheckRange( in_triggerHard,  0.05f, 1.0f,  qfalse );
	Cvar_CheckRange( in_rumble,       0,     100,   qtrue  );

#if !TARGET_OS_IPHONE
	// On iOS this raises the on-screen keyboard and leaves it up over the game.
	// Text entry there is driven from the launcher and the console instead, which
	// call SDL_StartTextInput() when they actually need it.
	SDL_StartTextInput( );
#endif

	mouseAvailable = ( in_mouse->value != 0 );
	IN_DeactivateMouse( Cvar_VariableIntegerValue( "r_fullscreen" ) != 0 );

	appState = SDL_GetWindowFlags( SDL_window );
	Cvar_SetValue( "com_unfocused",	!( appState & SDL_WINDOW_INPUT_FOCUS ) );
	Cvar_SetValue( "com_minimized", appState & SDL_WINDOW_MINIMIZED );

	IN_InitJoystick( );

#if TARGET_OS_IPHONE
	SDL_AddEventWatch( IN_IOSAppEventWatch, NULL );

	{
		// The overlay attaches to SDL's own UIWindow, so it needs the handle
		// SDL only exposes through the WM info struct.
		SDL_SysWMinfo wmInfo;

		SDL_VERSION( &wmInfo.version );

		if ( SDL_GetWindowWMInfo( SDL_window, &wmInfo ) ) {
			Sys_IOS_TouchOverlayInit( (void *)wmInfo.info.uikit.window );
		} else {
			Com_Printf( "Touch overlay: SDL_GetWindowWMInfo failed: %s\n", SDL_GetError() );
		}
	}
#endif

	Com_DPrintf( "------------------------------------\n" );
}

/*
===============
IN_Shutdown
===============
*/
void IN_Shutdown( void )
{
#if TARGET_OS_IPHONE
	SDL_DelEventWatch( IN_IOSAppEventWatch, NULL );
#endif

	SDL_StopTextInput( );

	IN_DeactivateMouse( Cvar_VariableIntegerValue( "r_fullscreen" ) != 0 );
	mouseAvailable = qfalse;

	IN_ShutdownJoystick( );

	SDL_window = NULL;
}

/*
===============
IN_Restart
===============
*/
void IN_Restart( void )
{
	IN_ShutdownJoystick( );
	IN_Init( SDL_window );
}
