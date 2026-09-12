/*
===========================================================================
iORTCW for iPadOS -- touch overlay iconography.

The overlay used to write the action on each button in words: FIRE, JUMP,
RELOAD. Words are the wrong thing on a control that sits over the game. They
are only readable in one language, they are read rather than recognised -- which
costs a glance the player does not have in a firefight -- and set in semibold
they carry far more ink than the thin ring they sit inside, so every button
looked like a label with a circle drawn round it rather than a button.

These are nine glyphs drawn to one system instead: a 24x24 grid, a 2pt stroke
that is the same 2pt the ring is stroked with whatever size the button is, round
caps and joins, and the same white the rest of the overlay is made of. Nothing
here is filled except two deliberate accents, because a filled shape beside a
stroked ring is the weight mismatch the words already had.

Kept apart from ios_touch.m so that ios/tools/icon_sheet.m can render the very
same code to a PNG contact sheet and the set can be looked at rather than
imagined. See ios/tools/README.md.
===========================================================================
*/

#ifndef IOS_ICONS_H
#define IOS_ICONS_H

#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
	IORTCW_ICON_NONE = 0,
	IORTCW_ICON_FIRE,		// a reticle -- the one glyph every shooter's fire button wears
	IORTCW_ICON_JUMP,		// arrow leaving the ground
	IORTCW_ICON_CROUCH,		// arrow settling onto it -- deliberately the same drawing, mirrored
	IORTCW_ICON_RELOAD,		// the turning arrow
	IORTCW_ICON_KICK,		// a boot, sole forward
	IORTCW_ICON_USE,		// a hand about to press something
	IORTCW_ICON_WEAPON_NEXT,
	IORTCW_ICON_WEAPON_PREV,
	IORTCW_ICON_MENU,

	IORTCW_ICON_COUNT
} iortcwIcon_t;

/// The whole button: the ring, and the glyph inside it.
///
/// `held` is the pressed state, which lifts both the ring and the glyph rather
/// than only one of them -- a button that brightens in halves reads as broken.
void IORTCWIcon_DrawButton( CGContextRef ctx, CGRect rect, iortcwIcon_t icon, int held );

/// Just the glyph, centred in `rect` and drawn at `alpha`. Exposed for the
/// contact sheet, which shows the set on its own as well as in place.
void IORTCWIcon_Draw( CGContextRef ctx, CGRect rect, iortcwIcon_t icon, CGFloat alpha );

/// The English name of a glyph, for the contact sheet's captions only. Nothing
/// the player ever sees.
const char *IORTCWIcon_Name( iortcwIcon_t icon );

#ifdef __cplusplus
}
#endif

#endif // IOS_ICONS_H
