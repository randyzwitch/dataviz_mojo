"""Ready-made `Theme`s for the four contexts a default chart is wrong in
(#333): `dark()`, `minimal()`, `high_contrast()` and `print_safe()`.

`Theme` has 56 parameters and, before this module, no presets. Nothing
here is newly *expressible* -- every value below is a keyword a caller
could already have passed. What was missing is knowing *which* of the 56
to turn, and to what, so that the whole chart moves together. That is
the entire content of a preset, and it is why the failure mode is not "a
chart that looks wrong" but "a chart that looks right except for the one
mark that draws the field you forgot".

```mojo
from dataviz.plot import Plot, save
from dataviz.themes import dark

var plot = Plot().mark_line().encode(x=x, y=y).theme(dark())
```

**Overriding a preset.** A preset is a starting point, not a mode.
`Theme`'s fields are plain `var`s, so take one and assign:

```mojo
var t = dark()
t.mark_color = CORNFLOWERBLUE
t.show_gridlines = False
var plot = Plot().mark_line().encode(x=x, y=y).theme(t)
```

A `Theme(preset=..., mark_color=X)` keyword was considered and is not
implementable here. Mojo cannot distinguish an argument the caller
passed from one that fell back to its default, so `Theme(preset=DARK)`
would apply `DARK`'s background and then overwrite all 55 other fields
with the *light* theme's defaults -- the partial-application bug this
module exists to prevent, promoted to the API's happy path. Free
functions returning a fully-populated `Theme` cannot express that state.

Presets do not compose: `dark()` and `minimal()` disagree about
`axis_color`, so there is no meaningful `dark(minimal())`. Take the one
that is closer and assign the handful of fields you want from the other.

**What "coherent" means, measured.** The default `Theme` is a light
theme, and several of its fields are near-white by design:
`minor_gridline_color` (240, 240, 240), `radialbar_track_color`
(230, 230, 230), `color_scale_mid` (235, 235, 235),
`annotation_area_color` (224, 236, 246), `bullet_range_color_light`
(224, 224, 224). A dark preset that sets `background`, `text_color`,
`axis_color`, `gridline_color` and `mark_color` -- the five a person
reaches for -- still renders a near-white ring on every radial bar
chart, a near-white band on every annotated area, and a near-white
midpoint on every heatmap. Each preset below therefore names every
color field whose *role* changes with the context, and this docstring
plus each function's own says which ones are deliberately left alone.

**Why these four.** They are the four contexts in which the default is
not merely a different taste but actually unreadable:

- `dark()` -- the chart is on a dark ground (a dashboard tile, a slide,
  a dark-mode page). Ink and ground swap roles; every neutral has to be
  re-derived from the new ground rather than reused.
- `minimal()` -- editorial. Reduces non-data ink and reduces nothing
  else; see its docstring for the line it draws.
- `high_contrast()` -- low vision, a projector, or bright ambient light.
  Luminance contrast and size are the levers, and hue is made redundant
  rather than load-bearing.
- `print_safe()` -- the chart will be printed, photocopied or faxed in
  grayscale. Hue is gone; only lightness survives.

A fashionable house palette (a `ggplot()` or a `fivethirtyeight()`) is
deliberately not among them. Those are aesthetics, and copying them by
name invites a comparison to matplotlib's own sheets that this package
does not need; more to the point, none of them makes a chart legible
that was not legible before.

**Grayscale, measured.** `print_safe()` exists because of numbers, not
taste. Rec.709 luma (`0.2126R + 0.7152G + 0.0722B`), which is what a
grayscale reproduction keeps, of the default theme's own colors:

- `mark_color` (30, 100, 180) is **90.9** and `mark_color_negative`
  (200, 60, 60) is **89.8**. A `color_by_sign=True` bar chart printed
  in grayscale is one flat shade: 1.1 levels out of 255.
- `color_scale_low` (60, 110, 200) is **105.9** and `color_scale_high`
  (220, 90, 40) is **114.0**. A printed heatmap's coldest and hottest
  cells are 8.2 levels apart -- the two ends of the scale are the same
  gray, and `color_scale_mid` (235.0) is the lightest of the three, so
  the map reads as a single peak in the middle whichever way the data
  runs. That is inherent to a *diverging* scale, not a bug in these
  three colors: two opposite extremes are supposed to be equally
  emphatic, and lightness has only one axis.

`print_safe()` replaces the sign pair with 25 and 170 (a 145-level gap)
and the scale with `viridis()`, whose 64 stops run 21.2 to 221.7 in luma
and are monotonic at every step -- a 200.4-level span against the
default's 8.2. `dataviz.colormaps` exists precisely because equal steps
in the value should look like equal steps in the color, and monotonic
lightness is what makes that survive being printed.

**What a preset cannot fix yet.** Categorical fill colors do not come
from `Theme` at all -- `default_categorical_palette()` (color_scale.mojo)
is a free function, because a `List` field would break `Theme`'s
`ImplicitlyCopyable` conformance. So no preset can restyle a multi-series
chart's series colors, and that palette is not grayscale-separable: its
green (44, 160, 44) and gray (127, 127, 127) are both luma **127.0**,
and its orange (255, 127, 14) at 146.1 and pink (227, 119, 194) at 147.4
are 1.3 apart. `print_safe()` and `high_contrast()` therefore set
`shape_by_category=True`, which is redundant coding that does work today
-- but only for `Mark.POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER`. A themeable
categorical palette is tracked as #426, and a dash cycle for line
series alongside it; until then a print chart with several line series needs
`Plot.color_map()` or one `Plot.mark_line(style=...)` per layer.
"""

from canvas.color import Color

from dataviz.color_ramp import ColorRamp
from dataviz.colormaps import cividis, viridis
from dataviz.colors import WHITE
from dataviz.line_style import LineStyle
from dataviz.theme import Theme


def dark() -> Theme:
    """A chart for a dark ground -- a dashboard tile, a slide, a
    dark-mode page.

    Inverting a light theme is not recoloring five fields; it is
    re-deriving every neutral against a new ground. The background is a
    very dark neutral gray rather than pure black: `#000` against light
    text maximizes contrast but also maximizes halation, the glow that
    makes thin strokes and small type smear on an emissive display, and
    a chart is mostly thin strokes and small type.

    Each neutral keeps the *contrast ratio* it had against white rather
    than its RGB value. Gridlines sit at 1.5:1 against the ground
    (the default's 225-gray is 1.3:1 against white) so they stay
    subordinate to the data instead of becoming a second grid of bright
    lines; minor gridlines at 1.2:1, the same half-step below. Text is
    14.5:1, the axis and the annotation ink 6.2:1.

    `bullet_range_color_light`/`_dark` are inverted in *lightness* while
    keeping their *roles*: the fields are named for how the default
    theme draws them, but what they encode is "the qualitative range
    band gets more present as its index rises", and on a dark ground
    more present means lighter. So the `_light` field holds the darker
    color here. A preset that preserved the names' literal sense would
    draw a bullet chart's least important band the loudest.

    The three continuous stops stay a diverging scale, re-centered: the
    midpoint moves from near-white (235, 235, 235) to a dark neutral, so
    "no signal" reads as the ground rather than as the brightest thing
    on the chart. A sequential map is a reasonable override
    (`t.color_ramp = magma()`), with the caveat that every sequential
    map's dark end approaches the dark background -- `magma()` starts at
    luma 0.3 and `viridis()` at 21.2, against this background's 25.9 --
    so the bottom of the scale is where the resolution goes.

    `halo_alpha` and `radar_fill_alpha` are raised from 90 to 170 to
    compensate for `_lighten()` (continuous.mojo), which flattens those
    fills against a hardcoded white rather than against
    `Theme.background`. At the default 90 the fill is 65% white: a
    rendered `dark()` radar puts 8.8% of the canvas above luma 170,
    almost all of it that fill, and an effect-scatter halo becomes the
    brightest object in the chart. Raising the alpha keeps more of the
    mark's own color, which is a workaround rather than a fix -- the fix
    is for `_lighten` to blend against `Theme.background`, which is
    tracked as #427. Note that this does not change how much a fill
    occludes: `_lighten` returns an opaque color at every alpha, so a
    radar's later series covers its earlier ones either way.

    Deliberately unchanged: `treemap_label_color` (white), because a
    treemap label sits on a palette-colored rectangle and never on the
    background; every size, margin and font field, because a dark ground
    changes what the colors have to be and nothing about the layout; and
    `shape_by_category`, because redundant coding is an accessibility
    choice, not a consequence of the ground being dark.

    Returns:
        A `Theme` for a dark background, ready to override.
    """
    return Theme(
        background=Color(24, 26, 31),
        mark_color=Color(90, 165, 255),
        axis_color=Color(150, 154, 163),
        gridline_color=Color(52, 56, 64),
        text_color=Color(232, 234, 238),
        minor_gridline_color=Color(38, 41, 48),
        color_scale_low=Color(90, 150, 235),
        color_scale_mid=Color(74, 77, 84),
        color_scale_high=Color(244, 132, 80),
        mark_color_negative=Color(244, 120, 110),
        bullet_range_color_light=Color(46, 48, 54),
        bullet_range_color_dark=Color(112, 116, 124),
        waterfall_total_color=Color(150, 153, 160),
        radialbar_track_color=Color(52, 55, 62),
        radar_fill_alpha=170,
        subtitle_color=Color(158, 162, 172),
        annotation_color=Color(152, 156, 166),
        annotation_area_color=Color(64, 78, 100, 200),
        halo_alpha=170,
    )


def minimal() -> Theme:
    """An editorial chart: less non-data ink, and nothing else reduced.

    The whole difficulty of a minimal style is where to stop. Gridlines,
    a heavy axis line, long ticks and generous margins are furniture --
    they help locate a value but carry none themselves, and a chart
    reproduced at magazine size does not have room for all of them. A
    legend and a tick label are not furniture: they are how a reader
    knows what a series *is* and what a position *means*. This preset
    removes the first kind and touches none of the second.

    That line is worth stating because the obvious "minimal" move is to
    pass `show_legend=False` as well -- it is the single biggest ink
    saving available, and it silently deletes the mapping from color to
    category. A preset that did it would turn every multi-series chart
    into an unreadable one on the strength of a style choice.

    So: gridlines off, the axis line and ticks faded to a light gray
    that reads as a boundary rather than a rule, ticks and label gaps
    shortened, margins tightened to match the furniture that is no
    longer there. Tick labels stay at full `text_color` strength -- they
    get *more* important once the gridlines are gone, not less. Minor
    ticks are shortened to 2px so that a caller who turns them on still
    gets the "labeled ticks read as structure" hierarchy that
    `minor_tick_length` exists to preserve.

    `gridline_style` is set to `DOTTED` and `annotation_line_style` to
    `DASHED` even though gridlines are off, so the two settings a caller
    is most likely to reach back for land in the preset's register
    rather than the default's: a re-enabled gridline comes back dotted,
    and a reference line reads as a reference line on a chart that has
    no other rules on it to compare against.

    Deliberately unchanged: `mark_color` and every other data color,
    because reducing furniture is not a reason to restyle the data;
    `title_bold`, because this preset is about chart furniture rather
    than typography, and a caller who wants a lighter title has one
    field to set; and `font_size`, because shrinking type is how a
    minimal chart becomes an illegible one.

    Returns:
        A `Theme` with the chart furniture reduced, ready to override.
    """
    return Theme(
        axis_color=Color(170, 170, 170),
        text_color=Color(55, 55, 55),
        margin_left=46,
        margin_right=14,
        margin_top=14,
        margin_bottom=42,
        show_gridlines=False,
        minor_tick_length=2,
        subtitle_color=Color(135, 135, 135),
        annotation_color=Color(140, 140, 140),
        tick_length=3,
        label_gap=3,
        margin_buffer=6,
        gridline_style=LineStyle.DOTTED,
        annotation_line_style=LineStyle.DASHED,
    )


def high_contrast() -> Theme:
    """A chart for low vision, a washed-out projector, or bright ambient
    light: maximum luminance contrast, larger everything, and hue made
    redundant rather than load-bearing.

    Two separate requirements, which is why this is not just "darker
    colors". The first is luminance contrast against the ground:
    text and axes go to pure black (21:1), and the mark ink to a
    darkened Okabe-Ito blue at 7.5:1, which clears WCAG AAA for normal
    text -- a stricter bar than a chart needs, chosen because a stroke
    2px wide is thinner than the text that standard was written for.
    Gridlines move the other way, from the default's near-invisible
    225-gray (1.3:1) to 120-gray (4.4:1); a gridline a low-vision reader
    cannot see is not a subtle gridline, it is a missing one. They are
    switched to `DOTTED` so that becoming visible does not also make
    them compete with the data. `annotation_area_color` moves the same
    way, from a composited luma of 238.7 against white to 204.3: a
    reference band is context rather than data, but context nobody can
    see is not context.

    `annotation_line_style` becomes `DASHED` for the reason that runs
    through the whole preset. A reference line at (64, 64, 64) and this
    mark ink at (0, 84, 166) are obviously different in color and 8.1
    luma levels apart -- which is to say they are the same line to
    anyone reading the chart by lightness. Dashing is the channel that
    still says "this is a threshold, not a measurement" when hue is not
    doing any work.

    The second is that color-vision deficiency must not cost
    information. The mark pair is Okabe & Ito's blue and vermillion,
    darkened for contrast: blue-versus-orange is the axis that survives
    the common red-green deficiencies, where the default theme's
    blue-versus-red pair does not separate reliably. The continuous
    scale becomes `cividis()`, which was built for exactly this -- it is
    the one map in `dataviz.colormaps` designed so a viewer with
    deuteranopia sees the same ordering as a viewer without.
    `shape_by_category` is on, so a categorical point mark carries its
    identity in shape as well as hue and a reader who cannot separate
    the palette can still read the legend.

    Sizes rise with the contrast, because acuity and contrast
    sensitivity fail together: base type 12 -> 14, title 18 -> 22, axis
    titles and subtitle 14 -> 16, strokes 2.0 -> 3.0, points 3.5 -> 5.0,
    ticks 5 -> 7. The margins, `margin_buffer`, `legend_width` and
    `legend_swatch_size` grow to match, since every one of them is
    reserved space that larger text would otherwise overrun.

    Not a print preset: this keeps hue, and pairs it with lightness so
    that losing hue costs less. `print_safe()` is the one that assumes
    hue is gone entirely.

    Returns:
        A high-contrast `Theme`, ready to override.
    """
    return Theme(
        mark_color=Color(0, 84, 166),
        axis_color=Color(0, 0, 0),
        gridline_color=Color(120, 120, 120),
        text_color=Color(0, 0, 0),
        font_size=14.0,
        point_radius=5.0,
        line_width=3.0,
        margin_left=70,
        margin_right=24,
        margin_top=24,
        margin_bottom=58,
        minor_gridline_color=Color(178, 178, 178),
        color_scale_low=Color(0, 84, 166),
        color_scale_mid=Color(240, 240, 240),
        color_scale_high=Color(166, 42, 0),
        color_ramp=cividis(),
        mark_color_negative=Color(166, 42, 0),
        bullet_range_color_light=Color(238, 238, 238),
        bullet_range_color_dark=Color(72, 72, 72),
        waterfall_total_color=Color(48, 48, 48),
        radialbar_track_color=Color(214, 214, 214),
        shape_by_category=True,
        title_font_size=22.0,
        subtitle_font_size=16.0,
        subtitle_color=Color(58, 58, 58),
        axis_title_font_size=16.0,
        annotation_color=Color(64, 64, 64),
        annotation_area_color=Color(168, 194, 222, 200),
        tick_length=7,
        legend_width=155,
        legend_swatch_size=18,
        margin_buffer=10,
        gridline_style=LineStyle.DOTTED,
        annotation_line_style=LineStyle.DASHED,
    )


def print_safe() -> Theme:
    """A chart that still reads after it has been printed, photocopied
    or faxed in grayscale: every distinction carried by lightness, and
    none by hue alone.

    Grayscale reproduction keeps Rec.709 luma and discards everything
    else, which is brutal to a default chart. Measured on this package's
    own defaults: `mark_color` (30, 100, 180) is luma 90.9 and
    `mark_color_negative` (200, 60, 60) is 89.8, so a `color_by_sign`
    bar chart prints as one flat shade -- 1.1 levels out of 255. This
    preset separates that pair by 145 levels (25 against 170) and gives
    `waterfall_total_color` the 100 between them, so a waterfall's
    three roles land on three visibly different grays.

    The continuous scale changes *kind*, not just value. The default
    three stops are a diverging scale, and a diverging scale cannot
    survive grayscale by construction: its two extremes are meant to be
    equally emphatic, lightness has one axis, and so they collide --
    measured at 8.2 levels apart, with the neutral midpoint the
    lightest of the three. Rendered, the default theme's eight-cell
    heatmap of strictly increasing values reads 105.9, 143.0, 179.4,
    216.5, 217.5, 183.3, 148.2, 114.0 in luma -- up and back down, with
    the highest cell 8.1 levels from the lowest.

    `color_ramp` becomes `viridis()`: the same eight cells then read
    21.2 through 221.7, strictly increasing at every step, a 200.4-level
    span with no adjacent pair closer than 21.9. The three scalar stops
    also become a sequential lightness ramp, running dark-to-light in
    the *same direction* as `viridis()` so that a caller who clears the
    ramp changes which map is used but not which end of the data is
    which. Leaving them diverging would have been the real hazard: a
    diverging fallback is unsafe in grayscale by construction, so
    unlike `high_contrast()` -- which keeps a diverging fallback,
    because it is not a grayscale preset -- this one must not have one.
    Genuinely diverging data has no grayscale-safe encoding at all, and
    that is a property of grayscale rather than of this preset; such a
    chart needs a second channel (position, or two panels).

    `gridline_style` is `DOTTED` and `annotation_line_style` is
    `DASHED`, which is the other half of the job: once hue is gone, a
    solid gray gridline and a solid gray reference line and a solid gray
    series are three things telling the reader they are the same kind of
    object. Dash pattern is the channel that survives a photocopy
    intact, which is what `LineStyle` is for.

    Ink stays off both extremes -- 25 rather than 0, and the lightest
    gray at 170 rather than 220 -- because a large solid black fill
    bleeds on paper and a very light tint is what a photocopier drops
    first. `annotation_area_color` is darkened for the same reason: with
    its `a=200` composited against white the default band lands at luma
    238.7, which is inside the range a photocopier renders as paper, and
    this one lands at 220.0.

    `shape_by_category` is on for the same reason it is in
    `high_contrast()`, and with the same limit: it covers
    `Mark.POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER` only. Categorical fills
    still come from `default_categorical_palette()`, which is not a
    `Theme` field and is not grayscale-separable (its green and its gray
    are both luma 127.0); a print chart with several categorical series
    needs `Plot.color_map()` until #426 makes that themeable. See this module's
    own docstring.

    Returns:
        A grayscale-safe `Theme`, ready to override.
    """
    return Theme(
        background=WHITE,
        mark_color=Color(25, 25, 25),
        axis_color=Color(60, 60, 60),
        gridline_color=Color(206, 206, 206),
        text_color=Color(20, 20, 20),
        minor_gridline_color=Color(230, 230, 230),
        color_scale_low=Color(30, 30, 30),
        color_scale_mid=Color(128, 128, 128),
        color_scale_high=Color(235, 235, 235),
        color_ramp=viridis(),
        mark_color_negative=Color(170, 170, 170),
        bullet_range_color_light=Color(232, 232, 232),
        bullet_range_color_dark=Color(96, 96, 96),
        waterfall_total_color=Color(100, 100, 100),
        radialbar_track_color=Color(228, 228, 228),
        shape_by_category=True,
        subtitle_color=Color(95, 95, 95),
        annotation_color=Color(120, 120, 120),
        annotation_area_color=Color(210, 210, 210, 200),
        gridline_style=LineStyle.DOTTED,
        annotation_line_style=LineStyle.DASHED,
    )
