# ios/tools

Small things that run on the Mac, so that parts of the iPad build can be looked
at without an iPad.

## icon_sheet

Renders the touch overlay's buttons to a PNG contact sheet — every glyph as it
ships, resting and pressed, over the three kinds of background the overlay has
to survive: a dark room, a mid-lit wall, and snow.

```sh
cc -o /tmp/icon_sheet ios/tools/icon_sheet.c ios/Sources/ios_icons.c \
   -framework CoreGraphics -framework ImageIO -framework CoreText \
   -framework CoreFoundation -framework ApplicationServices
/tmp/icon_sheet /tmp/icons.png
```

It calls `IORTCWIcon_DrawButton` — the same function `IORTCWTouchButton`'s
`drawRect:` calls, not a copy of it — so what the sheet shows is what the player
gets. Run it after touching `ios/Sources/ios_icons.c` and **look at the result**.
Two of the nine glyphs were only caught that way:

- the interact glyph was a hand with the index finger out, the convention every
  engine uses, and at 2pt on a 24-unit grid it came out reading as a thumbs-up.
  It is a door now;
- the kick glyph was a boot with a wide shaft, and it read as a capital L. The
  shaft is narrower, the foot is longer, and the sole is its own line.

Neither was visible in the source. Both were obvious in the sheet.

## Why the glyphs are drawn rather than downloaded

The overlay is a thin-line system: a 2pt white ring at 28% alpha with a 14%
fill. The icon sets worth having for game actions —
[game-icons.net](https://game-icons.net/) is the best of them, 4180 icons under
CC BY 3.0, and [Nieobie's pack](https://nieobie.itch.io/free-icons) is CC0 —
are solid silhouettes, drawn to be read as filled shapes. Dropping one of those
into this ring puts a heavy black glyph inside a delicate translucent circle,
which is the weight mismatch the old text labels already had. Restyling them to
outlines is redrawing them.

Apple's SF Symbols would match the weight and cost nothing, and it covers
reload, next, previous and menu well — but it has no fire, no crouch and no
kick, and a set that is half borrowed and half drawn is a set that looks it.

Nine glyphs on one grid at one stroke weight is a smaller job than any of those,
and it is the only one of them that ends with the overlay looking like one
thing.
