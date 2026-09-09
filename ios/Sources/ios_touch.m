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
// ios_touch.m -- on-screen controls, for playing without a gamepad.
//
// This is a UIKit view over SDL's GL view rather than something drawn inside
// cgame, for three reasons: it is independent of the renderer (so it survives
// any change there), it gets real multitouch for free, and it costs zero GL
// state changes in a fixed-function pipeline where every state change is
// expensive.
//
// It hides itself whenever a controller is connected, which is the behaviour
// asked for: the DualSense is the primary input and the overlay is a fallback.
//
// Two gestures stay live even when the overlay is hidden, and they are not
// decoration -- on a sideloaded build with no debugger attached, they are the
// only way to reach the menu and the console:
//
//   three-finger tap -> Escape
//   four-finger tap  -> console

#include "../../SP/code/qcommon/q_shared.h"
#include "../../SP/code/qcommon/qcommon.h"
#include "../../SP/code/sys/sys_local.h"
#include "../../SP/code/client/keycodes.h"

#import <UIKit/UIKit.h>

// Implemented in sdl_input.c
extern void IOSTouch_QueueKey( int key, int down );
extern void IOSTouch_QueueAxis( int axis, int value );
extern void IOSTouch_QueueMouse( int dx, int dy );
extern int  IOSTouch_ControllerConnected( void );
extern int  IOSTouch_MovementAxis( int forward );
extern int  IOSTouch_CinematicActive( void );
extern void IOSTouch_SkipCinematic( void );

#define STICK_RADIUS      110.0f
#define STICK_DEADZONE    0.15f
#define BUTTON_SIZE       88.0f
#define BUTTON_GAP        16.0f
#define EDGE_MARGIN       40.0f

// A button on the overlay: a circle with a label, bound to one key.
@interface IORTCWTouchButton : UIView
@property (nonatomic) int keyCode;
@property (nonatomic, copy) NSString *label;
@property (nonatomic) BOOL held;
@end

@implementation IORTCWTouchButton

- (void)drawRect:(CGRect)rect
{
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGFloat alpha = self.held ? 0.55 : 0.28;

	CGContextSetRGBFillColor( ctx, 1, 1, 1, alpha * 0.5 );
	CGContextFillEllipseInRect( ctx, CGRectInset( rect, 3, 3 ) );
	CGContextSetRGBStrokeColor( ctx, 1, 1, 1, alpha + 0.2 );
	CGContextSetLineWidth( ctx, 2.0 );
	CGContextStrokeEllipseInRect( ctx, CGRectInset( rect, 3, 3 ) );

	if ( self.label.length ) {
		UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
		NSDictionary *attrs = @{
			NSFontAttributeName: font,
			NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.9]
		};
		CGSize size = [self.label sizeWithAttributes:attrs];
		[self.label drawAtPoint:CGPointMake( ( rect.size.width - size.width ) / 2,
											 ( rect.size.height - size.height ) / 2 )
				 withAttributes:attrs];
	}
}

@end

// The movement stick. Reports on the joystick axes so it inherits the engine's
// existing movement scaling.
@interface IORTCWTouchStick : UIView
@property (nonatomic) CGPoint origin;
@property (nonatomic) CGPoint current;
@property (nonatomic) BOOL active;
@end

@implementation IORTCWTouchStick

- (void)drawRect:(CGRect)rect
{
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGPoint centre = CGPointMake( rect.size.width / 2, rect.size.height / 2 );
	CGPoint knob = self.active
		? CGPointMake( centre.x + ( self.current.x - self.origin.x ),
					   centre.y + ( self.current.y - self.origin.y ) )
		: centre;

	CGContextSetRGBStrokeColor( ctx, 1, 1, 1, 0.30 );
	CGContextSetLineWidth( ctx, 2.0 );
	CGContextStrokeEllipseInRect( ctx, CGRectInset( rect, 4, 4 ) );

	CGContextSetRGBFillColor( ctx, 1, 1, 1, self.active ? 0.45 : 0.25 );
	CGContextFillEllipseInRect( ctx,
		CGRectMake( knob.x - 34, knob.y - 34, 68, 68 ) );
}

@end

@interface IORTCWTouchOverlay : UIView
@property (nonatomic, strong) IORTCWTouchStick *stick;
@property (nonatomic, strong) NSMutableArray<IORTCWTouchButton *> *buttons;
@property (nonatomic, strong) NSMutableDictionary *touchOwners;  // touch ptr -> view
@property (nonatomic) CGPoint lookLast;
@property (nonatomic, strong) UITouch *lookTouch;
@property (nonatomic, strong) UITouch *stickTouch;
@property (nonatomic) CGPoint menuTouchStart;
@property (nonatomic) BOOL menuTouchMoved;
@end

@implementation IORTCWTouchOverlay

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if ( !self ) {
		return nil;
	}

	self.backgroundColor = [UIColor clearColor];
	self.opaque = NO;
	self.multipleTouchEnabled = YES;
	self.touchOwners = [NSMutableDictionary dictionary];
	self.buttons = [NSMutableArray array];

	[self buildControls];

	return self;
}

- (void)buildControls
{
	CGFloat h = self.bounds.size.height;
	CGFloat w = self.bounds.size.width;

	CGFloat stickSize = STICK_RADIUS * 2;
	self.stick = [[IORTCWTouchStick alloc] initWithFrame:
		CGRectMake( EDGE_MARGIN, h - stickSize - EDGE_MARGIN, stickSize, stickSize )];
	self.stick.backgroundColor = [UIColor clearColor];
	self.stick.opaque = NO;
	self.stick.userInteractionEnabled = NO;
	[self addSubview:self.stick];

	// Right-hand cluster: the things needed to actually play a level.
	struct { const char *label; int key; int col; int row; } layout[] = {
		{ "FIRE",   K_MOUSE1,  0, 0 },
		{ "JUMP",   K_SPACE,   1, 0 },
		{ "USE",    'f',       0, 1 },
		{ "CROUCH", 'c',       1, 1 },
		{ "RELOAD", 'r',       2, 0 },
		{ "NEXT",   ']',       2, 1 },
	};

	for ( size_t i = 0; i < sizeof( layout ) / sizeof( layout[0] ); i++ ) {
		CGFloat x = w - EDGE_MARGIN - ( layout[i].col + 1 ) * ( BUTTON_SIZE + BUTTON_GAP );
		CGFloat y = h - EDGE_MARGIN - ( layout[i].row + 1 ) * ( BUTTON_SIZE + BUTTON_GAP );

		IORTCWTouchButton *b = [[IORTCWTouchButton alloc] initWithFrame:
			CGRectMake( x, y, BUTTON_SIZE, BUTTON_SIZE )];
		b.backgroundColor = [UIColor clearColor];
		b.opaque = NO;
		b.userInteractionEnabled = NO;
		b.keyCode = layout[i].key;
		b.label = [NSString stringWithUTF8String:layout[i].label];
		[self addSubview:b];
		[self.buttons addObject:b];
	}
}

- (IORTCWTouchButton *)buttonAtPoint:(CGPoint)p
{
	for ( IORTCWTouchButton *b in self.buttons ) {
		if ( CGRectContainsPoint( CGRectInset( b.frame, -8, -8 ), p ) ) {
			return b;
		}
	}
	return nil;
}

/*
 * Menus are cursor-driven and the engine only ever moves that cursor by
 * relative deltas, so to make "tap the thing you want" work we have to track
 * where the cursor is ourselves and steer it there.
 *
 * The engine's cursor lives in the virtual 640x480 space its menus are laid out
 * in, which is why the touch position is scaled into that rather than used in
 * screen pixels.
 */
static CGPoint menuCursor = { 320.0f, 240.0f };

- (BOOL)menuActive
{
	return ( Key_GetCatcher() & ( KEYCATCH_UI | KEYCATCH_CONSOLE ) ) != 0;
}

- (CGPoint)virtualPointFor:(CGPoint)p
{
	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;

	if ( w <= 0 || h <= 0 ) {
		return menuCursor;
	}

	return CGPointMake( ( p.x / w ) * 640.0f, ( p.y / h ) * 480.0f );
}

- (void)moveMenuCursorTo:(CGPoint)target
{
	int dx = (int)lround( target.x - menuCursor.x );
	int dy = (int)lround( target.y - menuCursor.y );

	if ( dx || dy ) {
		IOSTouch_QueueMouse( dx, dy );
		// Track what we asked for, not what we wanted, so rounding does not
		// accumulate into drift over many taps.
		menuCursor.x += dx;
		menuCursor.y += dy;
	}
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	// Multi-finger taps are the escape hatches, and they must work whether or
	// not the overlay itself is visible.
	NSUInteger count = event.allTouches.count;

	if ( count == 3 ) {
		IOSTouch_QueueKey( K_ESCAPE, 1 );
		IOSTouch_QueueKey( K_ESCAPE, 0 );
		return;
	}
	if ( count == 4 ) {
		IOSTouch_QueueKey( K_CONSOLE, 1 );
		IOSTouch_QueueKey( K_CONSOLE, 0 );
		return;
	}

	// A tap anywhere skips a cutscene, which is the one thing everyone reaches
	// for and the game otherwise only offers on a keyboard.
	if ( IOSTouch_CinematicActive() ) {
		IOSTouch_SkipCinematic();
		return;
	}

	if ( [self menuActive] ) {
		// Move the pointer to the touch, but do not click yet. Clicking on
		// touch-down made every attempt to reposition the cursor also activate
		// whatever it passed over; the click happens on release instead, and
		// only if the finger stayed put.
		UITouch *touch = [touches anyObject];

		self.menuTouchStart = [touch locationInView:self];
		self.menuTouchMoved = NO;
		[self moveMenuCursorTo:[self virtualPointFor:self.menuTouchStart]];
		return;
	}

	for ( UITouch *touch in touches ) {
		CGPoint p = [touch locationInView:self];
		IORTCWTouchButton *b = [self buttonAtPoint:p];

		if ( b ) {
			b.held = YES;
			[b setNeedsDisplay];
			self.touchOwners[[NSValue valueWithNonretainedObject:touch]] = b;
			IOSTouch_QueueKey( b.keyCode, 1 );
			continue;
		}

		if ( !self.stickTouch && p.x < self.bounds.size.width * 0.5f ) {
			// Left half drives movement. The stick recentres on the touch so it
			// does not matter exactly where the thumb lands.
			self.stickTouch = touch;
			self.stick.origin = p;
			self.stick.current = p;
			self.stick.active = YES;
			self.stick.center = p;
			[self.stick setNeedsDisplay];
			continue;
		}

		if ( !self.lookTouch ) {
			self.lookTouch = touch;
			self.lookLast = p;
		}
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if ( [self menuActive] ) {
		UITouch *touch = [touches anyObject];
		CGPoint p = [touch locationInView:self];

		if ( fabs( p.x - self.menuTouchStart.x ) > 8.0 ||
			 fabs( p.y - self.menuTouchStart.y ) > 8.0 ) {
			self.menuTouchMoved = YES;
		}

		[self moveMenuCursorTo:[self virtualPointFor:p]];
		return;
	}

	for ( UITouch *touch in touches ) {
		CGPoint p = [touch locationInView:self];

		if ( touch == self.stickTouch ) {
			CGFloat dx = p.x - self.stick.origin.x;
			CGFloat dy = p.y - self.stick.origin.y;
			CGFloat len = sqrt( dx * dx + dy * dy );

			if ( len > STICK_RADIUS ) {
				dx *= STICK_RADIUS / len;
				dy *= STICK_RADIUS / len;
				len = STICK_RADIUS;
			}

			self.stick.current = CGPointMake( self.stick.origin.x + dx,
											  self.stick.origin.y + dy );
			[self.stick setNeedsDisplay];

			CGFloat nx = dx / STICK_RADIUS;
			CGFloat ny = dy / STICK_RADIUS;

			if ( fabs( nx ) < STICK_DEADZONE ) nx = 0;
			if ( fabs( ny ) < STICK_DEADZONE ) ny = 0;

			IOSTouch_QueueAxis( IOSTouch_MovementAxis( 0 ), (int)( nx * 32767 ) );
			IOSTouch_QueueAxis( IOSTouch_MovementAxis( 1 ), (int)( ny * 32767 ) );
			continue;
		}

		if ( touch == self.lookTouch ) {
			IOSTouch_QueueMouse( (int)( p.x - self.lookLast.x ),
								 (int)( p.y - self.lookLast.y ) );
			self.lookLast = p;
		}
	}
}

- (void)releaseTouch:(UITouch *)touch
{
	NSValue *key = [NSValue valueWithNonretainedObject:touch];
	IORTCWTouchButton *b = self.touchOwners[key];

	if ( b ) {
		b.held = NO;
		[b setNeedsDisplay];
		IOSTouch_QueueKey( b.keyCode, 0 );
		[self.touchOwners removeObjectForKey:key];
	}

	if ( touch == self.stickTouch ) {
		self.stickTouch = nil;
		self.stick.active = NO;
		[self.stick setNeedsDisplay];
		IOSTouch_QueueAxis( IOSTouch_MovementAxis( 0 ), 0 );
		IOSTouch_QueueAxis( IOSTouch_MovementAxis( 1 ), 0 );
	}

	if ( touch == self.lookTouch ) {
		self.lookTouch = nil;
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if ( [self menuActive] ) {
		// Only a tap selects. A drag was the player aiming the cursor.
		if ( !self.menuTouchMoved ) {
			IOSTouch_QueueKey( K_MOUSE1, 1 );
			IOSTouch_QueueKey( K_MOUSE1, 0 );
		}
		return;
	}

	for ( UITouch *touch in touches ) {
		[self releaseTouch:touch];
	}
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	for ( UITouch *touch in touches ) {
		[self releaseTouch:touch];
	}
}

@end

static IORTCWTouchOverlay *touchOverlay = nil;
static cvar_t *in_touchControls = NULL;

/*
==============
Sys_IOS_TouchOverlayInit

Attaches the overlay to SDL's own view rather than to a new UIWindow, so there
are no window-level games and unhandled touches fall through naturally.
==============
*/
void Sys_IOS_TouchOverlayInit( void *sdlWindowHandle )
{
	UIWindow *window = (__bridge UIWindow *)sdlWindowHandle;
	UIView *host;

	if ( touchOverlay || !window ) {
		return;
	}

	host = window.rootViewController.view;
	if ( !host ) {
		return;
	}

	in_touchControls = Cvar_Get( "in_touchControls", "0", CVAR_ARCHIVE );
	Cvar_CheckRange( in_touchControls, 0, 2, qtrue );

	touchOverlay = [[IORTCWTouchOverlay alloc] initWithFrame:host.bounds];
	touchOverlay.autoresizingMask =
		UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[host addSubview:touchOverlay];

	Com_Printf( "Touch overlay: attached, host %.0fx%.0f, in_touchControls %d\n",
		host.bounds.size.width, host.bounds.size.height,
		in_touchControls->integer );

	Sys_IOS_TouchOverlayUpdate();
}

/*
==============
Sys_IOS_TouchOverlayUpdate

in_touchControls: 0 = automatic (hide when a controller is connected),
1 = always shown, 2 = never shown. Called on controller connect and disconnect,
and whenever the cvar changes.
==============
*/
void Sys_IOS_TouchOverlayUpdate( void )
{
	BOOL visible;

	if ( !touchOverlay ) {
		return;
	}

	switch ( in_touchControls ? in_touchControls->integer : 0 ) {
		case 1:  visible = YES; break;
		case 2:  visible = NO;  break;
		default: visible = !IOSTouch_ControllerConnected(); break;
	}

	// The view stays in the hierarchy either way: the multi-finger escape
	// gestures have to keep working when the controls are hidden, since on a
	// sideloaded build they are the only route to the menu and console.
	for ( UIView *sub in touchOverlay.subviews ) {
		sub.hidden = !visible;
	}

	Com_DPrintf( "Touch overlay: %s (mode %d, controller %s)\n",
		visible ? "shown" : "hidden",
		in_touchControls ? in_touchControls->integer : 0,
		IOSTouch_ControllerConnected() ? "yes" : "no" );
}

/*
==============
Sys_IOS_TouchOverlayShutdown
==============
*/
void Sys_IOS_TouchOverlayShutdown( void )
{
	if ( touchOverlay ) {
		[touchOverlay removeFromSuperview];
		touchOverlay = nil;
	}
}
