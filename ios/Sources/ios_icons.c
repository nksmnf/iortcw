/*
===========================================================================
iORTCW for iPadOS -- touch overlay iconography. See ios_icons.h.
===========================================================================
*/

#include "ios_icons.h"

#include <math.h>

/*
==============
The system

Every glyph is drawn on a 24 x 24 grid with two units of air on each side, so
nothing comes closer than that to the ring. Coordinates below read as grid
units; the transform puts the grid in the middle of the button.

The stroke is set in grid units but computed back from the scale, so that it
lands on screen at the same 2pt the ring is stroked with, on the 88pt action
buttons and on the 64pt menu button alike. A set whose line weight drifts with
the button size is a set that looks drawn by two people.
==============
*/
#define ICON_GRID       24.0f
#define ICON_STROKE     2.0f

// How much of the button the grid is given. The ring is stroked 2pt inside a
// 3pt inset, and a glyph wants to sit clear of it rather than touch it: at 0.46
// an 88pt button carries a 40pt glyph with 21pt of quiet round it.
#define ICON_SCALE      0.46f

// The ring, unchanged from what the overlay always drew -- the palette is not
// being redecorated here, only the thing in the middle of it.
#define RING_INSET      3.0f
#define RING_STROKE     2.0f

static void Icon_Begin( CGContextRef ctx, CGRect rect, CGFloat alpha, CGFloat *scaleOut )
{
	CGFloat side  = ( rect.size.width < rect.size.height ? rect.size.width : rect.size.height );
	CGFloat span  = side * ICON_SCALE;
	CGFloat scale = span / ICON_GRID;

	CGContextSaveGState( ctx );
	CGContextTranslateCTM( ctx,
		rect.origin.x + ( rect.size.width  - span ) * 0.5f,
		rect.origin.y + ( rect.size.height - span ) * 0.5f );
	CGContextScaleCTM( ctx, scale, scale );

	// 2pt on screen, whatever the button's size, because the CTM scale is
	// divided back out.
	CGContextSetLineWidth( ctx, ICON_STROKE / scale );
	CGContextSetLineCap( ctx, kCGLineCapRound );
	CGContextSetLineJoin( ctx, kCGLineJoinRound );
	CGContextSetRGBStrokeColor( ctx, 1, 1, 1, alpha );
	CGContextSetRGBFillColor( ctx, 1, 1, 1, alpha );

	if ( scaleOut ) {
		*scaleOut = scale;
	}
}

static void Icon_End( CGContextRef ctx )
{
	CGContextRestoreGState( ctx );
}

static void Icon_Line( CGContextRef ctx, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2 )
{
	CGContextMoveToPoint( ctx, x1, y1 );
	CGContextAddLineToPoint( ctx, x2, y2 );
	CGContextStrokePath( ctx );
}

// An arrowhead as two strokes rather than a filled triangle: a solid head on a
// stroked shaft is the same weight mismatch the words had, in miniature.
static void Icon_ArrowHead( CGContextRef ctx, CGFloat tipX, CGFloat tipY,
							CGFloat dx, CGFloat dy, CGFloat wing )
{
	// Perpendicular to the direction the arrow points.
	CGFloat px = -dy, py = dx;

	CGContextMoveToPoint( ctx, tipX - dx * wing + px * wing, tipY - dy * wing + py * wing );
	CGContextAddLineToPoint( ctx, tipX, tipY );
	CGContextAddLineToPoint( ctx, tipX - dx * wing - px * wing, tipY - dy * wing - py * wing );
	CGContextStrokePath( ctx );
}

/*
==============
The glyphs

Drawn in a top-left origin space -- y grows downward, as it does in UIKit. The
contact sheet flips its own context to match, so what is drawn here is what
ships.
==============
*/

static void Icon_Fire( CGContextRef ctx )
{
	// A reticle. Not a bullet and not a muzzle flash: the reticle is what every
	// shooter on this device puts on its fire button, and a control the player
	// has to learn is a control that has already failed.
	CGContextStrokeEllipseInRect( ctx, CGRectMake( 12 - 6, 12 - 6, 12, 12 ) );

	// Four ticks, breaking the ring at the cardinals so it reads as a sight
	// rather than as a second, smaller button.
	Icon_Line( ctx, 12,  2, 12,  4.5f );
	Icon_Line( ctx, 12, 19.5f, 12, 22 );
	Icon_Line( ctx,  2, 12,  4.5f, 12 );
	Icon_Line( ctx, 19.5f, 12, 22, 12 );

	// The one deliberate accent: a filled centre, because a reticle with a
	// hollow middle reads as a target and not as a shot.
	CGContextFillEllipseInRect( ctx, CGRectMake( 12 - 1.6f, 12 - 1.6f, 3.2f, 3.2f ) );
}

static void Icon_Jump( CGContextRef ctx )
{
	// Ground, then an arrow leaving it.
	Icon_Line( ctx, 5, 21, 19, 21 );
	Icon_Line( ctx, 12, 18, 12, 5 );
	Icon_ArrowHead( ctx, 12, 4, 0, -1, 4.5f );
}

static void Icon_Crouch( CGContextRef ctx )
{
	// The same drawing, mirrored. The pair is read as a pair, and two glyphs
	// that differ only in the thing that differs is the whole trick.
	Icon_Line( ctx, 5, 21, 19, 21 );
	Icon_Line( ctx, 12, 3, 12, 16 );
	Icon_ArrowHead( ctx, 12, 17, 0, 1, 4.5f );
}

static void Icon_Reload( CGContextRef ctx )
{
	// Three quarters of a turn. The gap is at the top, where the eye enters the
	// glyph, and the head is big enough to be the thing that is seen -- a small
	// head on a long arc reads as a broken circle rather than as a rotation.
	const CGFloat r = 8.0f;
	const CGFloat endDeg = -70.0f;

	CGContextAddArc( ctx, 12, 12, r,
		(CGFloat)( endDeg * M_PI / 180.0 ),
		(CGFloat)( 205.0 * M_PI / 180.0 ), 0 );
	CGContextStrokePath( ctx );

	// On the end of the arc, pointing along it: for a counter-clockwise sweep
	// the tangent at the end runs up and to the right.
	{
		CGFloat a  = (CGFloat)( endDeg * M_PI / 180.0 );
		CGFloat tx = 12 + r * cosf( a );
		CGFloat ty = 12 + r * sinf( a );

		Icon_ArrowHead( ctx, tx, ty, sinf( a ), -cosf( a ), 5.0f );
	}
}

static void Icon_Kick( CGContextRef ctx )
{
	// A boot in profile, toe to the right.
	//
	// The first attempt was the same shape with a wider shaft and a flatter
	// instep, and it read as a capital L. What makes a boot a boot at this size
	// is the proportion -- a narrow shaft on a foot half again as long -- and
	// the sole drawn as its own line under it. Both are here; the detail that
	// is not is the heel, which at 2pt is a bump nobody sees.
	CGContextMoveToPoint( ctx, 7.5f, 3 );
	CGContextAddLineToPoint( ctx, 12, 3 );				// top of the shaft
	CGContextAddLineToPoint( ctx, 12, 11 );				// shin, front
	CGContextAddCurveToPoint( ctx, 15.5f, 11.4f, 18.5f, 12.8f, 20.5f, 15 );	// instep
	CGContextAddCurveToPoint( ctx, 21.2f, 15.8f, 21, 16.6f, 20, 16.6f );	// toe cap
	CGContextAddLineToPoint( ctx, 7.5f, 16.6f );		// under the foot
	CGContextClosePath( ctx );							// back of the shaft
	CGContextStrokePath( ctx );

	// The sole, set a little proud of the foot. This is the line that says
	// footwear rather than shape.
	Icon_Line( ctx, 6.6f, 19.4f, 20, 19.4f );
}

static void Icon_Use( CGContextRef ctx )
{
	// A door coming open, with its handle.
	//
	// This was a hand with the index finger out -- the interact glyph every
	// engine uses -- and drawn at 2pt on a 24 grid it came out as a thumbs-up,
	// or worse. There is no amount of tuning that makes a hand safe at this
	// size, and a glyph that can be misread as a gesture is not a glyph.
	//
	// A door is what this key is actually for. +activate in Wolfenstein opens
	// doors, turns valves and throws levers, and the door is the one of those
	// three that survives being drawn small.
	CGContextMoveToPoint( ctx, 6.5f, 3.5f );
	CGContextAddLineToPoint( ctx, 6.5f, 20.5f );	// jamb
	CGContextAddLineToPoint( ctx, 14, 20.5f );		// threshold
	CGContextStrokePath( ctx );

	// The leaf, swung open towards the viewer: narrower at the hinge, taller at
	// the free edge, which is all the perspective a glyph needs.
	CGContextMoveToPoint( ctx, 14, 20.5f );
	CGContextAddLineToPoint( ctx, 14, 6.5f );
	CGContextAddLineToPoint( ctx, 6.5f, 3.5f );
	CGContextStrokePath( ctx );

	CGContextMoveToPoint( ctx, 14, 6.5f );
	CGContextAddLineToPoint( ctx, 19.5f, 8.7f );	// top of the open leaf
	CGContextAddLineToPoint( ctx, 19.5f, 22 );		// free edge, down to the floor
	CGContextAddLineToPoint( ctx, 14, 20.5f );
	CGContextStrokePath( ctx );

	// The handle, on the free edge where a hand would find it.
	CGContextFillEllipseInRect( ctx, CGRectMake( 15.4f, 14.4f, 2.0f, 2.0f ) );
}

// Skip-forward and skip-back, the transport glyphs. Weapon cycling is "the next
// one" and "the one before", and no drawing of a rifle says that as plainly as
// the pair everyone already knows from every player they have ever used.
static void Icon_WeaponStep( CGContextRef ctx, int forward )
{
	CGFloat dir = forward ? 1.0f : -1.0f;
	CGFloat cx  = 12.0f;

	// Two chevrons: open shapes, so the weight matches the rest of the set
	// where a solid triangle would not. Set back from centre by half the bar's
	// offset, so the group sits centred in the ring rather than the chevrons
	// sitting centred with the bar hanging off one side.
	for ( int i = 0; i < 2; i++ ) {
		CGFloat x = cx + dir * ( -7.5f + i * 5.0f );

		CGContextMoveToPoint( ctx, x, 6.5f );
		CGContextAddLineToPoint( ctx, x + dir * 4.0f, 12 );
		CGContextAddLineToPoint( ctx, x, 17.5f );
		CGContextStrokePath( ctx );
	}

	// The stop bar that turns "forward" into "next": without it a double
	// chevron means fast-forward, which is not what the button does.
	Icon_Line( ctx, cx + dir * 7.0f, 6.0f, cx + dir * 7.0f, 18.0f );
}

static void Icon_Menu( CGContextRef ctx )
{
	Icon_Line( ctx, 5,  7, 19,  7 );
	Icon_Line( ctx, 5, 12, 19, 12 );
	Icon_Line( ctx, 5, 17, 19, 17 );
}

void IORTCWIcon_Draw( CGContextRef ctx, CGRect rect, iortcwIcon_t icon, CGFloat alpha )
{
	if ( icon <= IORTCW_ICON_NONE || icon >= IORTCW_ICON_COUNT ) {
		return;
	}

	Icon_Begin( ctx, rect, alpha, NULL );

	switch ( icon ) {
		case IORTCW_ICON_FIRE:        Icon_Fire( ctx );            break;
		case IORTCW_ICON_JUMP:        Icon_Jump( ctx );            break;
		case IORTCW_ICON_CROUCH:      Icon_Crouch( ctx );          break;
		case IORTCW_ICON_RELOAD:      Icon_Reload( ctx );          break;
		case IORTCW_ICON_KICK:        Icon_Kick( ctx );            break;
		case IORTCW_ICON_USE:         Icon_Use( ctx );             break;
		case IORTCW_ICON_WEAPON_NEXT: Icon_WeaponStep( ctx, 1 );   break;
		case IORTCW_ICON_WEAPON_PREV: Icon_WeaponStep( ctx, 0 );   break;
		case IORTCW_ICON_MENU:        Icon_Menu( ctx );            break;
		default: break;
	}

	Icon_End( ctx );
}

void IORTCWIcon_DrawButton( CGContextRef ctx, CGRect rect, iortcwIcon_t icon, int held )
{
	CGRect  ring  = CGRectInset( rect, RING_INSET, RING_INSET );
	CGFloat alpha = held ? 0.55f : 0.28f;

	CGContextSetRGBFillColor( ctx, 1, 1, 1, alpha * 0.5f );
	CGContextFillEllipseInRect( ctx, ring );

	CGContextSetRGBStrokeColor( ctx, 1, 1, 1, alpha + 0.2f );
	CGContextSetLineWidth( ctx, RING_STROKE );
	CGContextStrokeEllipseInRect( ctx, ring );

	// The glyph is brighter than the ring on purpose, and brighter still when
	// the button is down. It is the part being read; the ring only says where.
	IORTCWIcon_Draw( ctx, rect, icon, held ? 1.0f : 0.9f );
}

const char *IORTCWIcon_Name( iortcwIcon_t icon )
{
	switch ( icon ) {
		case IORTCW_ICON_FIRE:        return "FIRE";
		case IORTCW_ICON_JUMP:        return "JUMP";
		case IORTCW_ICON_CROUCH:      return "CROUCH";
		case IORTCW_ICON_RELOAD:      return "RELOAD";
		case IORTCW_ICON_KICK:        return "KICK";
		case IORTCW_ICON_USE:         return "USE";
		case IORTCW_ICON_WEAPON_NEXT: return "NEXT";
		case IORTCW_ICON_WEAPON_PREV: return "PREV";
		case IORTCW_ICON_MENU:        return "MENU";
		default:                      return "";
	}
}
