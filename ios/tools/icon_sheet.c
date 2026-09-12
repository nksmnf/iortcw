/*
===========================================================================
icon_sheet -- render the touch overlay's buttons to a PNG so they can be
looked at.

The overlay only exists on a running iPad, which is a slow way to judge a
2pt stroke. This builds on the Mac, calls the very same drawing code the app
calls (ios/Sources/ios_icons.c, no copy), and writes a contact sheet: every
glyph as it ships, in both states, over the three kinds of background the
overlay actually has to survive -- a dark room, a mid-lit wall, and snow.

    cc -o icon_sheet ios/tools/icon_sheet.c ios/Sources/ios_icons.c \
       -framework CoreGraphics -framework ImageIO -framework CoreText \
       -framework CoreFoundation
    ./icon_sheet /tmp/icons.png
===========================================================================
*/

#include "../Sources/ios_icons.h"

#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdio.h>
#include <string.h>

// The overlay's own numbers, so the sheet is at the size the player sees.
#define BUTTON_SIZE   88.0f
#define BUTTON_GAP    16.0f
#define MENU_SIZE     64.0f

#define SCALE         3.0f      // the iPad renders at 3x; judge the stroke there
#define MARGIN        28.0f
#define BAND_PAD      22.0f
#define CAPTION_H     20.0f

static const iortcwIcon_t kOrder[] = {
	IORTCW_ICON_FIRE, IORTCW_ICON_JUMP, IORTCW_ICON_RELOAD, IORTCW_ICON_KICK,
	IORTCW_ICON_USE, IORTCW_ICON_CROUCH, IORTCW_ICON_WEAPON_NEXT,
	IORTCW_ICON_WEAPON_PREV, IORTCW_ICON_MENU
};
#define ICON_N ( (int)( sizeof( kOrder ) / sizeof( kOrder[0] ) ) )

static void DrawText( CGContextRef ctx, const char *s, CGFloat x, CGFloat y,
					  CGFloat size, CGFloat grey )
{
	CFStringRef str = CFStringCreateWithCString( NULL, s, kCFStringEncodingUTF8 );
	CTFontRef font = CTFontCreateWithName( CFSTR( "Menlo" ), size, NULL );
	CGColorRef col = CGColorCreateGenericRGB( grey, grey, grey, 1.0 );

	CFStringRef keys[]   = { kCTFontAttributeName, kCTForegroundColorAttributeName };
	CFTypeRef   values[] = { font, col };
	CFDictionaryRef attrs = CFDictionaryCreate( NULL, (const void **)keys,
		(const void **)values, 2, &kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks );

	CFAttributedStringRef as = CFAttributedStringCreate( NULL, str, attrs );
	CTLineRef line = CTLineCreateWithAttributedString( as );

	CGContextSaveGState( ctx );
	CGContextSetTextMatrix( ctx, CGAffineTransformIdentity );
	CGContextTranslateCTM( ctx, x, y );
	CGContextScaleCTM( ctx, 1, -1 );		// the context is y-down; text is not
	CGContextSetTextPosition( ctx, 0, 0 );
	CTLineDraw( line, ctx );
	CGContextRestoreGState( ctx );

	CFRelease( line ); CFRelease( as ); CFRelease( attrs );
	CGColorRelease( col ); CFRelease( font ); CFRelease( str );
}

/// One band: a background, then the nine buttons across it.
static void DrawBand( CGContextRef ctx, CGFloat y, CGFloat width, CGFloat bg,
					  int held, const char *caption )
{
	CGFloat h = BUTTON_SIZE + BAND_PAD * 2;

	CGContextSetRGBFillColor( ctx, bg, bg, bg, 1 );
	CGContextFillRect( ctx, CGRectMake( 0, y, width, h ) );

	DrawText( ctx, caption, MARGIN, y + 16, 11, bg > 0.5 ? 0.15 : 0.75 );

	for ( int i = 0; i < ICON_N; i++ ) {
		CGFloat x = MARGIN + i * ( BUTTON_SIZE + BUTTON_GAP );

		IORTCWIcon_DrawButton( ctx,
			CGRectMake( x, y + BAND_PAD, BUTTON_SIZE, BUTTON_SIZE ),
			kOrder[i], held );
	}
}

int main( int argc, char **argv )
{
	const char *out = ( argc > 1 ) ? argv[1] : "icons.png";

	CGFloat width  = MARGIN * 2 + ICON_N * BUTTON_SIZE + ( ICON_N - 1 ) * BUTTON_GAP;
	CGFloat bandH  = BUTTON_SIZE + BAND_PAD * 2;
	CGFloat height = bandH * 4 + CAPTION_H + MARGIN;

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate( NULL,
		(size_t)( width * SCALE ), (size_t)( height * SCALE ), 8, 0, cs,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host );

	if ( !ctx ) {
		fprintf( stderr, "could not make the bitmap\n" );
		return 1;
	}

	CGContextScaleCTM( ctx, SCALE, SCALE );

	// UIKit's drawRect gives a y-down context. Match it, or every glyph comes
	// out upside down here and right way up on the device, which is the worst
	// of both.
	CGContextTranslateCTM( ctx, 0, height );
	CGContextScaleCTM( ctx, 1, -1 );

	CGContextSetRGBFillColor( ctx, 0.08, 0.08, 0.09, 1 );
	CGContextFillRect( ctx, CGRectMake( 0, 0, width, height ) );

	CGContextSetAllowsAntialiasing( ctx, true );
	CGContextSetShouldAntialias( ctx, true );

	CGFloat y = 0;
	DrawBand( ctx, y, width, 0.13, 0, "dark room -- resting" );          y += bandH;
	DrawBand( ctx, y, width, 0.13, 1, "dark room -- pressed" );          y += bandH;
	DrawBand( ctx, y, width, 0.38, 0, "mid-lit wall -- resting" );       y += bandH;
	DrawBand( ctx, y, width, 0.78, 0, "snow / sky -- resting" );         y += bandH;

	// Names under the columns, so a glyph that needs a second look can be
	// named when it is talked about.
	CGContextSetRGBFillColor( ctx, 0.08, 0.08, 0.09, 1 );
	CGContextFillRect( ctx, CGRectMake( 0, y, width, CAPTION_H + MARGIN ) );
	for ( int i = 0; i < ICON_N; i++ ) {
		CGFloat x = MARGIN + i * ( BUTTON_SIZE + BUTTON_GAP );

		DrawText( ctx, IORTCWIcon_Name( kOrder[i] ), x + 6, y + 14, 11, 0.62 );
	}

	CGImageRef img = CGBitmapContextCreateImage( ctx );
	CFStringRef path = CFStringCreateWithCString( NULL, out, kCFStringEncodingUTF8 );
	CFURLRef url = CFURLCreateWithFileSystemPath( NULL, path, kCFURLPOSIXPathStyle, false );
	CGImageDestinationRef dst = CGImageDestinationCreateWithURL( url, CFSTR( "public.png" ), 1, NULL );

	if ( !dst ) {
		fprintf( stderr, "could not write %s\n", out );
		return 1;
	}

	CGImageDestinationAddImage( dst, img, NULL );
	CGImageDestinationFinalize( dst );

	printf( "wrote %s (%.0f x %.0f at %.0fx)\n", out, width, height, SCALE );

	CFRelease( dst ); CFRelease( url ); CFRelease( path );
	CGImageRelease( img ); CGContextRelease( ctx ); CGColorSpaceRelease( cs );
	return 0;
}
