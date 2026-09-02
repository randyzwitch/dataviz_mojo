"""Named colors -- the full CSS Color Module Level 3 / X11 "extended
color keywords" list (<https://www.w3.org/TR/css-color-3/#svg-color>),
plus `REBECCAPURPLE` (added in Level 4, but universally bundled
alongside the rest of this list by every implementation of "the CSS
named colors" in practice, not just formally part of Level 3), as
`Color` constants: `Theme(mark_color=CORNFLOWERBLUE)` instead of
hand-typing `Theme(mark_color=Color(100, 149, 237))` (see #10 -- "make
'green' and similar colors just available to specify"). Each name is
the CSS keyword itself, uppercased, with no separators added
(`CORNFLOWERBLUE`, not `CORNFLOWER_BLUE`) -- that keeps every name a
direct, greppable match for the CSS spec/any color picker a caller
already knows the keyword from, rather than a second, dataviz-
specific spelling to remember. Both spellings CSS itself standardizes
(`GRAY`/`GREY`, `DARKGRAY`/`DARKGREY`, `DIMGRAY`/`DIMGREY`,
`LIGHTGRAY`/`LIGHTGREY`, `LIGHTSLATEGRAY`/`LIGHTSLATEGREY`,
`SLATEGRAY`/`SLATEGREY`) are both included, each the identical `Color`
value under both names -- picking one and dropping the other would
just be a different, equally arbitrary standard.

`comptime`, not a `def`-returned value or a `Dict[String, Color]`
lookup -- a plain, zero-cost constant, importable and usable exactly
the same way as any other `Color` literal (works as a Theme keyword
argument, in a List[Color] palette, anywhere `Color` already does),
with no runtime string-matching/raises path a name-string lookup would
need. `CSS`-standard names only, not an invented palette -- an actual
"agreed-upon standard" (the issue's phrasing) beats a curated
subset that someone would eventually ask to extend one color at a
time.

Deliberately not part of `canvas.Color` itself (see color_scale.
mojo's `default_categorical_palette()` docstring for the same "keep
the core type minimal" reasoning) -- this file has no dependency on
anything else in
dataviz (`Plot`, `Theme`, marks, ...), just `Color` values, so it
could move to canvas_mojo directly (e.g. as its `named_colors`
module, re-exported from here) if another canvas_mojo consumer beyond
this package ever wants the identical list -- nothing here assumes
dataviz-specific machinery.

Sorted alphabetically by name (matching how the CSS spec itself lists
them), not grouped by hue/family -- there's no unambiguous single way
to group 148 colors by "family," and alphabetical is the one order a
caller can actually predict without scrolling: looking for `orange`
means jumping to the O's, not guessing whether it counts as "warm" or
"reds" here.
"""

from canvas.color import Color

comptime ALICEBLUE = Color(240, 248, 255)
comptime ANTIQUEWHITE = Color(250, 235, 215)
comptime AQUA = Color(0, 255, 255)
comptime AQUAMARINE = Color(127, 255, 212)
comptime AZURE = Color(240, 255, 255)
comptime BEIGE = Color(245, 245, 220)
comptime BISQUE = Color(255, 228, 196)
comptime BLACK = Color(0, 0, 0)
comptime BLANCHEDALMOND = Color(255, 235, 205)
comptime BLUE = Color(0, 0, 255)
comptime BLUEVIOLET = Color(138, 43, 226)
comptime BROWN = Color(165, 42, 42)
comptime BURLYWOOD = Color(222, 184, 135)
comptime CADETBLUE = Color(95, 158, 160)
comptime CHARTREUSE = Color(127, 255, 0)
comptime CHOCOLATE = Color(210, 105, 30)
comptime CORAL = Color(255, 127, 80)
comptime CORNFLOWERBLUE = Color(100, 149, 237)
comptime CORNSILK = Color(255, 248, 220)
comptime CRIMSON = Color(220, 20, 60)
comptime CYAN = Color(0, 255, 255)
comptime DARKBLUE = Color(0, 0, 139)
comptime DARKCYAN = Color(0, 139, 139)
comptime DARKGOLDENROD = Color(184, 134, 11)
comptime DARKGRAY = Color(169, 169, 169)
comptime DARKGREEN = Color(0, 100, 0)
comptime DARKGREY = Color(169, 169, 169)
comptime DARKKHAKI = Color(189, 183, 107)
comptime DARKMAGENTA = Color(139, 0, 139)
comptime DARKOLIVEGREEN = Color(85, 107, 47)
comptime DARKORANGE = Color(255, 140, 0)
comptime DARKORCHID = Color(153, 50, 204)
comptime DARKRED = Color(139, 0, 0)
comptime DARKSALMON = Color(233, 150, 122)
comptime DARKSEAGREEN = Color(143, 188, 143)
comptime DARKSLATEBLUE = Color(72, 61, 139)
comptime DARKSLATEGRAY = Color(47, 79, 79)
comptime DARKSLATEGREY = Color(47, 79, 79)
comptime DARKTURQUOISE = Color(0, 206, 209)
comptime DARKVIOLET = Color(148, 0, 211)
comptime DEEPPINK = Color(255, 20, 147)
comptime DEEPSKYBLUE = Color(0, 191, 255)
comptime DIMGRAY = Color(105, 105, 105)
comptime DIMGREY = Color(105, 105, 105)
comptime DODGERBLUE = Color(30, 144, 255)
comptime FIREBRICK = Color(178, 34, 34)
comptime FLORALWHITE = Color(255, 250, 240)
comptime FORESTGREEN = Color(34, 139, 34)
comptime FUCHSIA = Color(255, 0, 255)
comptime GAINSBORO = Color(220, 220, 220)
comptime GHOSTWHITE = Color(248, 248, 255)
comptime GOLD = Color(255, 215, 0)
comptime GOLDENROD = Color(218, 165, 32)
comptime GRAY = Color(128, 128, 128)
comptime GREEN = Color(0, 128, 0)
comptime GREENYELLOW = Color(173, 255, 47)
comptime GREY = Color(128, 128, 128)
comptime HONEYDEW = Color(240, 255, 240)
comptime HOTPINK = Color(255, 105, 180)
comptime INDIANRED = Color(205, 92, 92)
comptime INDIGO = Color(75, 0, 130)
comptime IVORY = Color(255, 255, 240)
comptime KHAKI = Color(240, 230, 140)
comptime LAVENDER = Color(230, 230, 250)
comptime LAVENDERBLUSH = Color(255, 240, 245)
comptime LAWNGREEN = Color(124, 252, 0)
comptime LEMONCHIFFON = Color(255, 250, 205)
comptime LIGHTBLUE = Color(173, 216, 230)
comptime LIGHTCORAL = Color(240, 128, 128)
comptime LIGHTCYAN = Color(224, 255, 255)
comptime LIGHTGOLDENRODYELLOW = Color(250, 250, 210)
comptime LIGHTGRAY = Color(211, 211, 211)
comptime LIGHTGREEN = Color(144, 238, 144)
comptime LIGHTGREY = Color(211, 211, 211)
comptime LIGHTPINK = Color(255, 182, 193)
comptime LIGHTSALMON = Color(255, 160, 122)
comptime LIGHTSEAGREEN = Color(32, 178, 170)
comptime LIGHTSKYBLUE = Color(135, 206, 250)
comptime LIGHTSLATEGRAY = Color(119, 136, 153)
comptime LIGHTSLATEGREY = Color(119, 136, 153)
comptime LIGHTSTEELBLUE = Color(176, 196, 222)
comptime LIGHTYELLOW = Color(255, 255, 224)
comptime LIME = Color(0, 255, 0)
comptime LIMEGREEN = Color(50, 205, 50)
comptime LINEN = Color(250, 240, 230)
comptime MAGENTA = Color(255, 0, 255)
comptime MAROON = Color(128, 0, 0)
comptime MEDIUMAQUAMARINE = Color(102, 205, 170)
comptime MEDIUMBLUE = Color(0, 0, 205)
comptime MEDIUMORCHID = Color(186, 85, 211)
comptime MEDIUMPURPLE = Color(147, 112, 219)
comptime MEDIUMSEAGREEN = Color(60, 179, 113)
comptime MEDIUMSLATEBLUE = Color(123, 104, 238)
comptime MEDIUMSPRINGGREEN = Color(0, 250, 154)
comptime MEDIUMTURQUOISE = Color(72, 209, 204)
comptime MEDIUMVIOLETRED = Color(199, 21, 133)
comptime MIDNIGHTBLUE = Color(25, 25, 112)
comptime MINTCREAM = Color(245, 255, 250)
comptime MISTYROSE = Color(255, 228, 225)
comptime MOCCASIN = Color(255, 228, 181)
comptime NAVAJOWHITE = Color(255, 222, 173)
comptime NAVY = Color(0, 0, 128)
comptime OLDLACE = Color(253, 245, 230)
comptime OLIVE = Color(128, 128, 0)
comptime OLIVEDRAB = Color(107, 142, 35)
comptime ORANGE = Color(255, 165, 0)
comptime ORANGERED = Color(255, 69, 0)
comptime ORCHID = Color(218, 112, 214)
comptime PALEGOLDENROD = Color(238, 232, 170)
comptime PALEGREEN = Color(152, 251, 152)
comptime PALETURQUOISE = Color(175, 238, 238)
comptime PALEVIOLETRED = Color(219, 112, 147)
comptime PAPAYAWHIP = Color(255, 239, 213)
comptime PEACHPUFF = Color(255, 218, 185)
comptime PERU = Color(205, 133, 63)
comptime PINK = Color(255, 192, 203)
comptime PLUM = Color(221, 160, 221)
comptime POWDERBLUE = Color(176, 224, 230)
comptime PURPLE = Color(128, 0, 128)
comptime REBECCAPURPLE = Color(102, 51, 153)
comptime RED = Color(255, 0, 0)
comptime ROSYBROWN = Color(188, 143, 143)
comptime ROYALBLUE = Color(65, 105, 225)
comptime SADDLEBROWN = Color(139, 69, 19)
comptime SALMON = Color(250, 128, 114)
comptime SANDYBROWN = Color(244, 164, 96)
comptime SEAGREEN = Color(46, 139, 87)
comptime SEASHELL = Color(255, 245, 238)
comptime SIENNA = Color(160, 82, 45)
comptime SILVER = Color(192, 192, 192)
comptime SKYBLUE = Color(135, 206, 235)
comptime SLATEBLUE = Color(106, 90, 205)
comptime SLATEGRAY = Color(112, 128, 144)
comptime SLATEGREY = Color(112, 128, 144)
comptime SNOW = Color(255, 250, 250)
comptime SPRINGGREEN = Color(0, 255, 127)
comptime STEELBLUE = Color(70, 130, 180)
comptime TAN = Color(210, 180, 140)
comptime TEAL = Color(0, 128, 128)
comptime THISTLE = Color(216, 191, 216)
comptime TOMATO = Color(255, 99, 71)
comptime TURQUOISE = Color(64, 224, 208)
comptime VIOLET = Color(238, 130, 238)
comptime WHEAT = Color(245, 222, 179)
comptime WHITE = Color(255, 255, 255)
comptime WHITESMOKE = Color(245, 245, 245)
comptime YELLOW = Color(255, 255, 0)
comptime YELLOWGREEN = Color(154, 205, 50)
