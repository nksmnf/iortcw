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
extern void IOSTouch_QueueCommand( const char *command, int key );
extern float IOSTouch_LookSensitivity( void );
extern int  IOSTouch_ControllerConnected( void );
extern int  IOSTouch_DebugEnabled( void );
extern int  IOSTouch_MovementAxis( int forward );
extern int  IOSTouch_CinematicActive( void );
extern void IOSTouch_SkipCinematic( void );

// Implemented in cl_keys.c. Which module owns the keyboard also decides where a
// mouse delta ends up, and the cursor work below has to know: CL_MouseEvent only
// gives one to the UI while KEYCATCH_UI is set.
extern int  Key_GetCatcher( void );

#define STICK_RADIUS      110.0f
#define STICK_DEADZONE    0.15f
#define BUTTON_SIZE       88.0f
#define BUTTON_GAP        16.0f
#define EDGE_MARGIN       40.0f
#define MENU_BUTTON_SIZE  64.0f

// How far the movement stick has to go before it means "run". Past the point a
// thumb reaches without deciding to.
#define SPRINT_THRESHOLD  0.85f

// How long the on-screen controls stay up after the last touch when a
// controller is also in use. Long enough to cross the screen and press
// something, short enough that they are gone by the time it matters.
#define TOUCH_IDLE_HIDE   5.0

// How far a finger may travel in a menu and still be a tap rather than a slide,
// in points. Measured from where the finger went down rather than between
// events, because the two answer different questions: a careful slide moves a
// point or two per event and was being called a tap when it ended, which threw
// away the aim it had just been used to build.
#define MENU_TAP_SLOP     6.0f


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
@property (nonatomic, strong) UITouch *menuTouch;   // the finger acting as the mouse
@property (nonatomic) CFTimeInterval lastTouchTime; // for the automatic hide
@property (nonatomic) CGPoint menuTouchLast;
@property (nonatomic) CGPoint menuTouchOrigin; // where the finger went down
@property (nonatomic) BOOL menuTouchMoved;
@property (nonatomic) BOOL menuTwoFinger;
@property (nonatomic) CGPoint menuCursorRemainder;
@property (nonatomic) BOOL sprinting;
@property (nonatomic) CGPoint lookRemainder;
- (void)releaseTouch:(UITouch *)touch;
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
		// The keys are the game's own: these go through the normal bindings, so
		// they follow whatever the player has set in the Controls menu.
		{ "FIRE",   K_MOUSE1,  0, 0 },
		{ "JUMP",   K_SPACE,   1, 0 },
		{ "RELOAD", 'r',       2, 0 },

		// Kick earns a button: it opens doors, breaks crates and finishes
		// people without spending ammunition, and touch had no way to do it.
		{ "KICK",   'g',       3, 0 },

		{ "USE",    'f',       0, 1 },
		{ "CROUCH", 'c',       1, 1 },

		// '[' is weapnext and ']' is weapprev in default.cfg. The single button
		// here was labelled NEXT and bound to ']', so it cycled backwards.
		{ "NEXT",   '[',       2, 1 },
		{ "PREV",   ']',       3, 1 },
	};

	// Escape, where it can be found. A three-finger tap does the same and still
	// works, but nobody discovers a gesture, and this is the button that leads
	// to saving, loading and quitting.
	{
		IORTCWTouchButton *b = [[IORTCWTouchButton alloc] initWithFrame:
			CGRectMake( w - EDGE_MARGIN - MENU_BUTTON_SIZE, EDGE_MARGIN,
						MENU_BUTTON_SIZE, MENU_BUTTON_SIZE )];
		b.backgroundColor = [UIColor clearColor];
		b.opaque = NO;
		b.userInteractionEnabled = NO;
		b.keyCode = K_ESCAPE;
		b.label = @"MENU";
		[self addSubview:b];
		[self.buttons addObject:b];
	}

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

/*
 * The overlay sits on the window above SDL's view and takes every touch.
 *
 * Handing menu touches down to SDL instead looks tidier and does not work: SDL
 * turns touches into mouse events, but with relative mouse mode on -- which the
 * engine enables for aiming -- those arrive pinned to the centre of the window
 * with a zero delta. The menu cursor never moves and the tap activates whatever
 * it was already sitting on. Owning the touch and driving the cursor to it is
 * both exact and one code path instead of two fighting over the same cursor.
 */
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	UIView *hit = [super hitTest:point withEvent:event];

	return hit ? hit : self;
}

- (IORTCWTouchButton *)buttonAtPoint:(CGPoint)p
{
	for ( IORTCWTouchButton *b in self.buttons ) {
		// A hidden button is not there. Without this, playing with a pad still
		// fires the weapon when a thumb rests where FIRE used to be drawn.
		if ( b.hidden ) {
			continue;
		}

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
 *
 * It starts on the origin because that is where the UI leaves its own cursor
 * when it starts -- _UI_Init sets it there and CL_InitUI tells the input layer
 * so. This used to start in the middle of the screen, which was a claim about a
 * position nothing had ever put the cursor in.
 */
static CGPoint menuCursor = { 0.0f, 0.0f };

- (BOOL)menuActive
{
	// Includes the loading screen and the pregame briefing, neither of which is
	// gameplay even though only one of them sets the key catcher.
	return CL_UIActive() ? YES : NO;
}

/*
 * Whether the UI will actually accept a cursor, which is narrower than
 * -menuActive above.
 *
 * A loading screen, the pregame briefing and the console all count as the UI
 * owning the screen, but CL_MouseEvent only hands a delta to the UI while
 * KEYCATCH_UI is set; at any of those it falls through to the branch that adds
 * the delta to the player's view angles instead. Driving a cursor there moves
 * nothing that can be seen and quietly turns the player's head.
 */
- (BOOL)menuTakesCursor
{
	return ( Key_GetCatcher() & KEYCATCH_UI ) ? YES : NO;
}

- (CGPoint)virtualPointFor:(CGPoint)p
{
	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;

	if ( w <= 0 || h <= 0 ) {
		// Falling back to the current cursor would mean every touch asked for the
		// place the cursor already is, which reads as touch being dead rather
		// than as a layout problem.
		w = self.superview ? self.superview.bounds.size.width : 0;
		h = self.superview ? self.superview.bounds.size.height : 0;

		if ( w <= 0 || h <= 0 ) {
			return menuCursor;
		}
	}

	return CGPointMake( ( p.x / w ) * 640.0f, ( p.y / h ) * 480.0f );
}

/*
 * Put the cursor on a point exactly, whatever state anything else has left it
 * in. This is what a tap in a menu comes down to, and it is where taps were
 * landing somewhere other than the finger.
 *
 * The obvious route was to ask the engine for the difference between the point
 * and where the cursor already is, which IOSTouch_QueueMouseTo does against the
 * shadow position IN_QueueMouseDelta keeps. That shadow is not the UI's cursor
 * and cannot be: IN_QueueMouseDelta sees every mouse delta the game produces,
 * while the UI's cursor only moves when KEYCATCH_UI is set. Looking around by
 * touch pushes hundreds of deltas through that same function during play -- one
 * swipe is enough to drive the shadow into a corner, where it clamps -- so by
 * the time the menu is opened the two have drifted apart and the difference the
 * engine reports is wrong by exactly that drift. It is the same drift wherever
 * the finger lands, which is why it reads as the cursor sitting a fixed distance
 * from the touch rather than as the screen being scaled wrongly, and why it gets
 * reported against one menu entry: a constant offset simply presses the item
 * next to the one that was aimed at, and it is the item you meant to press that
 * you remember.
 *
 * So the difference is not asked for; it is made irrelevant. Both the shadow and
 * the UI's cursor clamp to the same 640x480 box, so one deliberately impossible
 * move puts both of them on the origin no matter where either of them was, and
 * the second move then travels from a position the two sides agree on.
 *
 * IN_MenuCursorTo rather than the queue, for two reasons. The queue folds
 * consecutive mouse events into one by adding them together, which would turn
 * the pair below back into a single relative move and undo the whole point of
 * it. And the click follows immediately: moving the cursor now means the queued
 * mouse button is read against the item under the finger rather than against
 * whatever the cursor was on before.
 */
- (void)moveMenuCursorTo:(CGPoint)target
{
	menuCursor = target;

	if ( [self menuTakesCursor] ) {
		IN_MenuCursorTo( -SCREEN_WIDTH * 2, -SCREEN_HEIGHT * 2 );
		IN_MenuCursorTo( (int)lround( target.x ), (int)lround( target.y ) );
	}

	if ( IOSTouch_DebugEnabled() ) {
		// The catcher is here because it decides whether the two lines above ran
		// at all: a tap that reports a cursor and does not move one is a tap that
		// arrived while something other than a menu owned the screen.
		Com_Printf( "touch: menu cursor -> %.0f,%.0f (view %.0fx%.0f, catcher %d)\n",
			target.x, target.y,
			self.bounds.size.width, self.bounds.size.height,
			Key_GetCatcher() );
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

	self.lastTouchTime = CACurrentMediaTime();

	// One line, once, so a report of "touch does nothing" can be separated from
	// "touch never reaches us" without a debugger.
	static BOOL loggedFirstTouch = NO;
	if ( !loggedFirstTouch ) {
		loggedFirstTouch = YES;
		Com_Printf( "Touch overlay: first touch received\n" );
	}

	// A tap anywhere skips a cutscene, which is the one thing everyone reaches
	// for and the game otherwise only offers on a keyboard.
	if ( IOSTouch_CinematicActive() ) {
		IOSTouch_SkipCinematic();
		return;
	}

	// Menus, the console and the pregame briefing: the finger is the cursor.
	if ( [self menuActive] ) {
		UITouch *touch = touches.anyObject;

		// Two fingers press whatever the cursor is already on, without moving
		// it. That is the one thing the other two gestures cannot do: a slide
		// aims and a tap jumps, so a carefully aimed cursor had no way to be
		// clicked without being moved first.
		if ( count == 2 ) {
			self.menuTwoFinger = YES;
			self.menuTouch = nil;
			return;
		}

		if ( touch && !self.menuTouch ) {
			// Two gestures, because neither alone is enough on a screen this
			// size. A slide nudges the cursor, the way a trackpad does, which is
			// how you land on something small. A tap puts the cursor where the
			// finger is and presses, which is how you reach the other side of
			// the screen without three strokes to get there.
			self.menuTouch = touch;
			self.menuTouchLast = [touch locationInView:self];
			self.menuTouchOrigin = self.menuTouchLast;
			self.menuTouchMoved = NO;
			self.menuCursorRemainder = CGPointZero;
		}
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
	self.lastTouchTime = CACurrentMediaTime();

	if ( [self menuActive] ) {
		CGFloat w = self.bounds.size.width;
		CGFloat h = self.bounds.size.height;

		for ( UITouch *touch in touches ) {
			CGPoint p;
			CGFloat dx, dy;

			if ( touch != self.menuTouch ) {
				continue;
			}

			p = [touch locationInView:self];
			dx = p.x - self.menuTouchLast.x;
			dy = p.y - self.menuTouchLast.y;
			self.menuTouchLast = p;

			// Against where the finger went down, not against the last event.
			// Judging each event on its own called a slow slide a tap, and a tap
			// throws the cursor to the finger -- so the gesture meant for fine
			// aim was the one gesture guaranteed to lose it.
			if ( fabs( p.x - self.menuTouchOrigin.x ) > MENU_TAP_SLOP ||
				 fabs( p.y - self.menuTouchOrigin.y ) > MENU_TAP_SLOP ) {
				self.menuTouchMoved = YES;
			}

			// Exactly the ratio between the screen and the 640x480 the menus are
			// laid out in, per axis. A round number here is what made the cursor
			// outrun the finger: 0.70 against the 0.465 this screen actually
			// needs is half again too fast, and the gap grows with the stroke,
			// which reads as the cursor being scaled rather than dragged.
			if ( w > 0.0f && h > 0.0f ) {
				self.menuCursorRemainder = CGPointMake(
					self.menuCursorRemainder.x + dx * ( 640.0f / w ),
					self.menuCursorRemainder.y + dy * ( 480.0f / h ) );

				// Nothing is sent until the gesture is known to be a slide.
				// A finger rolls a point or two on its way up, and that wobble
				// would be queued while the placement a tap ends with is
				// immediate -- so the wobble would be applied after the
				// placement and drag the cursor back off the item it had just
				// been put on. The fraction keeps accumulating either way, so a
				// slide loses nothing by starting late.
				if ( self.menuTouchMoved && [self menuTakesCursor] ) {
					int qx = (int)( self.menuCursorRemainder.x );
					int qy = (int)( self.menuCursorRemainder.y );

					if ( qx || qy ) {
						// The engine's cursor is whole units, so keep the
						// fraction rather than throwing it away on every small
						// movement -- otherwise a slow drag never moves the
						// cursor at all.
						self.menuCursorRemainder = CGPointMake(
							self.menuCursorRemainder.x - qx,
							self.menuCursorRemainder.y - qy );
						IOSTouch_QueueMouse( qx, qy );

						// Clamped the way _UI_MouseEvent clamps, or a slide that
						// runs off the edge of the screen would leave this copy
						// claiming a position outside the box the real cursor is
						// held inside.
						menuCursor = CGPointMake(
							Com_Clamp( 0.0f, SCREEN_WIDTH, menuCursor.x + qx ),
							Com_Clamp( 0.0f, SCREEN_HEIGHT, menuCursor.y + qy ) );
					}
				}
			}
		}
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

			// Sprint on a full push, rather than another button.
			//
			// Stamina is part of how RTCW plays and there was no way to spend it
			// by touch. A thumb already tells the difference between walking the
			// stick over and shoving it to the edge, so the gesture is free --
			// and it cannot be held by accident, because holding the edge is
			// exactly what running is.
			[self setSprint:( sqrt( nx * nx + ny * ny ) > SPRINT_THRESHOLD )];
			continue;
		}

		if ( touch == self.lookTouch ) {
			// Carry the fraction, or a slow drag is rounded away to nothing and
			// fine aim by touch becomes impossible.
			float sens = IOSTouch_LookSensitivity();
			int dx, dy;

			self.lookRemainder = CGPointMake(
				self.lookRemainder.x + ( p.x - self.lookLast.x ) * sens,
				self.lookRemainder.y + ( p.y - self.lookLast.y ) * sens );

			dx = (int)self.lookRemainder.x;
			dy = (int)self.lookRemainder.y;

			if ( dx || dy ) {
				self.lookRemainder = CGPointMake( self.lookRemainder.x - dx,
												  self.lookRemainder.y - dy );
				IOSTouch_QueueMouse( dx, dy );
			}

			self.lookLast = p;
		}
	}
}

- (void)setSprint:(BOOL)on
{
	if ( on == self.sprinting ) {
		return;
	}

	self.sprinting = on;
	IOSTouch_QueueCommand( on ? "+sprint" : "-sprint", K_PAD0_LEFTSTICK_CLICK );
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
		[self setSprint:NO];
	}

	if ( touch == self.lookTouch ) {
		self.lookTouch = nil;
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if ( self.menuTwoFinger && event.allTouches.count <= touches.count ) {
		// The last of the two came up: press where the cursor is.
		self.menuTwoFinger = NO;
		IOSTouch_QueueKey( K_MOUSE1, 1 );
		IOSTouch_QueueKey( K_MOUSE1, 0 );
		return;
	}

	for ( UITouch *touch in touches ) {
		if ( touch == self.menuTouch ) {
			BOOL tapped = !self.menuTouchMoved;
			CGPoint p = [touch locationInView:self];

			self.menuTouch = nil;

			if ( tapped ) {
				[self moveMenuCursorTo:[self virtualPointFor:p]];
				IOSTouch_QueueKey( K_MOUSE1, 1 );
				IOSTouch_QueueKey( K_MOUSE1, 0 );
			}
			continue;
		}

		[self releaseTouch:touch];
	}
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	for ( UITouch *touch in touches ) {
		if ( touch == self.menuTouch ) {
			self.menuTouch = nil;
			continue;
		}

		[self releaseTouch:touch];
	}
}

@end

/*
 * The overlay lives in its own window, and that window's root view controller.
 *
 * A subview of SDL's window is not good enough. It worked in the simulator and
 * received nothing at all on a device: the launcher puts up its own UIWindow
 * before the engine starts, and between that and SDL's own view management the
 * overlay ends up somewhere touches do not reach. A separate window above
 * SDL's cannot be reordered by anything SDL does.
 *
 * It is deliberately never made key -- SDL keeps that, and with it the keyboard
 * and the rest of its event handling. A visible window still receives touches
 * without being key.
 */
@interface IORTCWTouchController : UIViewController
@end

@implementation IORTCWTouchController

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskLandscape;
}

@end

static IORTCWTouchOverlay *touchOverlay = nil;
static UIWindow *touchWindow = nil;
static cvar_t *in_touchControls = NULL;

/*
==============
Sys_IOS_TouchOverlayInit
==============
*/
void Sys_IOS_TouchOverlayInit( void *sdlWindowHandle )
{
	UIWindow *sdlWindow = (__bridge UIWindow *)sdlWindowHandle;
	IORTCWTouchController *controller;

	if ( touchOverlay || !sdlWindow ) {
		return;
	}

	in_touchControls = Cvar_Get( "in_touchControls", "1", CVAR_ARCHIVE );
	Cvar_CheckRange( in_touchControls, 0, 2, qtrue );

	touchOverlay = [[IORTCWTouchOverlay alloc] initWithFrame:sdlWindow.bounds];
	touchOverlay.autoresizingMask =
		UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	touchOverlay.backgroundColor = [UIColor clearColor];
	touchOverlay.opaque = NO;

	controller = [[IORTCWTouchController alloc] init];
	controller.view = touchOverlay;

	if ( sdlWindow.windowScene ) {
		touchWindow = [[UIWindow alloc] initWithWindowScene:sdlWindow.windowScene];
	} else {
		touchWindow = [[UIWindow alloc] initWithFrame:sdlWindow.bounds];
	}

	touchWindow.frame = sdlWindow.bounds;
	touchWindow.backgroundColor = [UIColor clearColor];
	touchWindow.opaque = NO;
	touchWindow.rootViewController = controller;

	// Above the game, below anything the system or the launcher puts up.
	touchWindow.windowLevel = UIWindowLevelNormal + 1;

	// Visible, but never key: makeKeyAndVisible here would take the keyboard
	// and the rest of the event handling away from SDL.
	touchWindow.hidden = NO;

	Com_Printf( "Touch overlay: own window %.0fx%.0f level %.0f, in_touchControls %d\n",
		touchWindow.bounds.size.width, touchWindow.bounds.size.height,
		(double)touchWindow.windowLevel, in_touchControls->integer );

	// The readout lives in the same window: it is already above the game and
	// already knows about the safe area.
	Sys_IOS_PerfInit( (__bridge void *)touchOverlay );
	Sys_IOS_GyroInit();

	Sys_IOS_TouchOverlayUpdate();
}

/*
==============
Sys_IOS_TouchOverlayUpdate

in_touchControls: 0 = automatic (hide when a controller is connected),
1 = always shown, 2 = never shown.

Called every frame from IN_Frame, so it also tracks the one thing that changes
constantly: whether the game or the UI owns the screen. The controls have no
meaning over a menu, a loading screen or the pregame briefing, and leaving FIRE
and JUMP drawn on top of the mission briefing is how the briefing came to look
like something that could not be dismissed.
==============
*/
void Sys_IOS_TouchOverlayUpdate( void )
{
	static BOOL wasVisible = NO;
	static BOOL everSet = NO;
	BOOL visible;

	if ( !touchOverlay ) {
		return;
	}

	switch ( in_touchControls ? in_touchControls->integer : 0 ) {
		case 1:  visible = YES; break;
		case 2:  visible = NO;  break;

		default:
			// Automatic: the pad and the screen take turns rather than one
			// locking the other out. With no controller in use the controls are
			// simply there. With one in use they stay out of the way, and come
			// back the moment a finger touches the screen -- then fade out again
			// once the screen has been left alone for a while.
			if ( !IOSTouch_ControllerConnected() ) {
				visible = YES;
			} else {
				visible = ( touchOverlay.lastTouchTime &&
							CACurrentMediaTime() - touchOverlay.lastTouchTime
								< TOUCH_IDLE_HIDE ) ? YES : NO;
			}
			break;
	}

	// Menus, loading screens and cutscenes are all times when there is nothing
	// for these to do, and a cutscene is watched, not played.
	if ( CL_UIActive() || IOSTouch_CinematicActive() ) {
		visible = NO;
	}

	// A touch that never reported its end would leave the stick held, and with
	// it the pad locked out of the movement axes. UIKit keeps the object alive
	// and its phase truthful, so this is cheap insurance against a lost event.
	if ( touchOverlay.stickTouch &&
		 ( touchOverlay.stickTouch.phase == UITouchPhaseEnded ||
		   touchOverlay.stickTouch.phase == UITouchPhaseCancelled ) ) {
		[touchOverlay releaseTouch:touchOverlay.stickTouch];
	}

	// Keep the window over the whole screen. Nothing should move it, but a zero
	// or stale frame would send every touch to the same place, which reads as
	// touch being dead rather than as a layout problem.
	if ( touchWindow && touchWindow.screen &&
		 !CGRectEqualToRect( touchWindow.frame, touchWindow.screen.bounds ) ) {
		touchWindow.frame = touchWindow.screen.bounds;
	}

	if ( everSet && visible == wasVisible ) {
		return;
	}

	wasVisible = visible;
	everSet = YES;

	// Only the controls are hidden, never the overlay itself: it still has to
	// receive touches so menus, cutscene skipping and the multi-finger gestures
	// keep working with a controller attached.
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
/*
==============
IOSTouch_MovementActive

Whether the on-screen stick is being held.

The pad's own movement handling writes the movement axes every frame -- zeroing
them when it is using the digital path -- which wiped whatever the on-screen
stick had just put there. Walking by touch stopped after a step or two unless
the thumb kept moving, because only the frames between the touch event and the
next pad update survived.
==============
*/
int IOSTouch_MovementActive( void )
{
	return ( touchOverlay && touchOverlay.stickTouch ) ? 1 : 0;
}

void Sys_IOS_TouchOverlayShutdown( void )
{
	if ( touchWindow ) {
		touchWindow.hidden = YES;
		touchWindow.rootViewController = nil;
		touchWindow = nil;
	}

	touchOverlay = nil;
}
