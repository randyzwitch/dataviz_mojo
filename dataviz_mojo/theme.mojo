"""Visual defaults for a Plot -- colors, sizes, margins -- kept as one
small struct with sensible defaults rather than a dozen optional
parameters scattered across Plot's own builder methods. This is
deliberately the one place in this early vertical slice that borrows
ECharts' "config object" ergonomics (a bundle of display knobs) rather
than the grammar-of-graphics vocabulary the rest of dataviz follows --
appropriate here specifically because a theme isn't part of the data
grammar (it doesn't change what a mark or scale *means*), just how it
looks.

Every field below typed `Color` takes a `dataviz_mojo.colors` named
constant exactly as it does a hand-built `Color(r, g, b)` -- `Theme(
mark_color=CORNFLOWERBLUE)` instead of `Theme(mark_color=Color(100,
149, 237))` -- see that module's own docstring for the full list.

`scale` (default 1.0, purely multiplicative, so every existing Theme
keeps rendering exactly as it always has) uniformly multiplies every
*other* pixel-sized quantity render() computes -- font size, margins,
point radius, line width, tick length, legend layout, all of it --
without changing what any individual field means at scale=1.0. Meant
for rendering the exact same chart at a higher pixel density (pair
`Theme(scale=2.0)` with a Canvas twice the width/height) so text and
strokes stay crisp when a viewer displays the output larger than its
native pixel size -- see the wiki for the concrete case
that motivated this (a small raster canvas, viewed upscaled in an
Electron/webview-based image preview, loses sharpness to the
viewer's own interpolation; more native pixels per glyph is the fix
that holds regardless of which viewer is doing the upscaling). Not a
crop/zoom -- the plot's own logical layout (data domain, tick
positions, legend contents) is identical at every scale, only the
pixel measurements of everything drawn change.

A distinct thing from the supersample-then-shrink-back-down
anti-aliasing every one-call convenience function (`bar()`,
`scatter()`, ...) now bakes into its own output automatically (see
`dataviz_mojo.plot._rendered`'s own docstring) -- that one always
returns a `Canvas` at the exact size asked for, `scale` untouched by
it from the caller's own point of view; internally it composes with
whatever `scale` the caller already set (a real HiDPI export that
also wants quickplot's own smoother edges gets both, multiplied
together), it just isn't a knob a caller sets to get supersampling in
the first place -- `render()`, `Plot`'s own direct entry point, has no
such hidden factor at all, so a `Theme(scale=3.0)` built by hand and
handed to `render()` is exactly, only, three times the pixels, with
none of `_rendered`'s own automatic multiplication on top.

`donut_inner_radius_fraction` (default 0.0 -- an ordinary pie, `Mark.
ARC` unchanged) is a *fraction* of the outer radius `_render_arc`
already computes from the plot area, not a pixel value -- the outer
radius itself already scales with canvas size, so a fraction keeps
the donut hole proportionally correct at any size the same way a
percentage would, rather than a fixed pixel value that would look
right at one canvas size and wrong at every other. Must be in
`[0.0, 1.0)` -- `_render_arc` raises otherwise (an inner radius that
reaches or exceeds the outer one has no ring left to draw).

`color_by_sign` (default `False` -- every `Mark.BAR` bar stays
`mark_color`, unchanged) switches `_render_bar` to color each bar by
whether its own value is negative (`mark_color_negative`) or not
(`mark_color`) -- what a diverging bar chart's own coloring
conventionally means (`Mark.BAR` already draws bars extending below a
zero baseline for negative values with no changes needed -- see
`_zero_baseline_y_extent`'s own docstring; this is the one further
thing a genuinely *diverging* bar chart adds on top of that: making
the sign visually obvious by color too, not just by direction). An
explicit opt-in flag, not inferred from whether `mark_color_negative`
differs from `mark_color`, so there's no ambiguous default to guess
at from color equality.

`Mark.WATERFALL` and `Mark.CANDLESTICK` also use `mark_color`/
`mark_color_negative`, but unconditionally, with no `color_by_sign`
equivalent of their own -- sign coloring isn't an optional extra for
either (a waterfall's rising/falling color and a candlestick's up/down
color both *are* what the chart conventionally shows), the way it is
for an otherwise-complete plain bar chart. See either mark's own
`_render_*` docstring in plot.mojo.

`bullet_range_color_light`/`bullet_range_color_dark` are `Mark.BULLET`'s
own pair, unrelated to the sign-coloring fields above: the two ends of
a small monochrome gradient (via `dataviz_mojo.color_scale.ColorScale`, the
same stop-interpolation machinery `Plot.encode(color=...)`'s own
continuous channel uses) `_render_bullet` shades each category's
qualitative range bands with, lightest-to-darkest by range index --
deliberately grayscale by default (Stephen Few's own original bullet-
chart convention), not `mark_color`-derived, so the shaded background
bands read as neutral context behind the one thing that *is* colored
with `mark_color`: the measure bar itself. Unlike `mark_color_negative`,
`Mark.BULLET`'s measure bar is never colored by sign -- see
`_render_bullet`'s own docstring for why.

`line_smoothing` (default `0.0` -- `Mark.LINE`/`Mark.AREA` draw exactly
the straight point-to-point segments they always have) controls how
much `_build_line_path` curves a line (or an area's own top edge)
through its own data points, via a Catmull-Rom-derived cubic Bezier
spline -- `0.0` builds a plain straight-segment `Path` (no curve math
touched at all, not merely a degenerate curve that happens to look
straight, so the default is byte-for-byte identical to every pre-
existing `Mark.LINE`/`AREA` render, not just visually close), `1.0` the
full, standard Catmull-Rom curve through every point, and anything in
between scales each segment's own tangent vector by that fraction --
so `0.5` bows exactly half as far from the straight path as `1.0` does
at the same point. Must be in `[0.0, 1.0]` -- `_render_generic` raises
otherwise, an overshoot tension this package assigns no meaning to
rather than silently rendering an unbounded, likely-self-intersecting
curve. `Mark.AREA` only smooths its own *top* edge (through the data
points) -- the bottom edge down to/along the zero baseline stays
straight, since baseline is a fixed reference line, not data, with
nothing to curve through. See `_build_line_path`'s own docstring
(plot.mojo) for the control-point formula, shared unchanged by both
marks.

`title_font_size`/`axis_title_font_size` are the two new sizes `Plot.
labels()` needs (see that method's own docstring for the three strings
themselves -- `title`/`x_title`/`y_title` -- and the layout math that
uses these): a chart title reads as a heading, so it defaults larger
than everything else on the plot (18.0, vs. `font_size`'s own 12.0 for
tick/legend labels); an axis title (a caption under the x-axis or
rotated alongside the y-axis, e.g. "Revenue ($)") reads as a
subordinate label, not body text or a heading, so it defaults between
the two (14.0). Both are plain `Float64` points, scaled by `Theme.
scale` the same as `font_size` itself -- see `_Scaled`'s own docstring
(plot.mojo) for why every pixel-sized quantity goes through that one
struct rather than each render path applying `* scale` itself. No
titles are drawn by default (`Plot._title`/`_x_title`/`_y_title` all
default to `""`), so these two sizes only ever matter once a caller
actually calls `.labels(...)` -- an empty string never reserves layout
space or emits a `_TextRequest`, the same "absent means absent, not a
zero-size version of present" rule `Plot.encode_gantt`'s own start/end
pair and every other optional feature in this file already follow.

`waterfall_total_color` is `Mark.WATERFALL`'s own third color, for a
row `encode_waterfall()`'s own `is_total` marks as a running-total
checkpoint rather than a rising/falling delta -- deliberately a third,
neutral color (default a plain gray, `Color(100, 100, 100)`), not
`mark_color`/`mark_color_negative` reused: a total bar isn't "a big
increase" or "a big decrease," it's a different *kind* of thing on the
same chart (where things stand, not what just changed), so it reads
clearest with its own color rather than borrowing meaning from the
rising/falling pair. See `_render_waterfall`'s own docstring for the
full total-bar drawing story (also wider than a delta bar -- full band
width vs. `_WATERFALL_DELTA_WIDTH_FRACTION`, a plain module constant
in plot.mojo, not a `Theme` field, since nothing about it is a color/
size a caller would plausibly want to retheme independently of the
mark's own shape).

`font_family` (default `"sans-serif"`) is every `_TextRequest`'s own
typeface -- tick/legend labels, axis titles, the chart title, all of
it, baked into each `_TextRequest` at the point it's built (the same
"read straight off `theme`, per construction site" convention every
other `_TextRequest` field -- `color`, `size` -- already follows,
*not* a single value read once by `render()`/`render_svg()`'s own
final draw loop: `render_facets()`/`render_layers()` combine several
independently themed `Plot`s into one shared draw pass, so a family
read once, globally, would silently apply the wrong plot's own choice
to every other plot sharing that canvas). `"sans-serif"` is
deliberately a value valid in *both* worlds a caller's chosen family
ends up in -- `canvas_mojo.text.draw_text`'s own raster path resolves
it as a fontconfig family/alias (fontconfig ships `sans-serif` as a
recognized generic alias, the same generic-substitution concept CSS's
own `sans-serif` keyword is, alongside its older capitalized `Sans`
form), while `SvgCanvas.draw_text`'s own `family` parameter is a
literal CSS `font-family` value the SVG viewer interprets directly --
two genuinely different value spaces (a fontconfig alias resolves to
one concrete font *file*; a CSS value is interpreted by whatever's
rendering the SVG, with no file resolution on this package's own side
at all), which happen to agree on this one generic keyword. A caller
naming a *specific* installed font instead (`"Georgia"`, `"Helvetica
Neue"`) gets that request honored identically by both backends too,
as long as it's a real, installed font name -- but a real CSS fallback
*stack* (`"Helvetica Neue, Arial, sans-serif"`) only means anything to
the SVG side; fontconfig has no comma-separated-list syntax of its
own, so a raster render would treat the whole string as one (almost
certainly unmatched) family name. Threading a stack through safely for
both backends is a real, separate feature, not something this single
string field takes on implicitly.
"""

from canvas_mojo.color import Color

from dataviz_mojo.colors import WHITE


struct Theme(ImplicitlyCopyable, Movable):
    var background: Color
    var mark_color: Color
    var axis_color: Color
    var gridline_color: Color
    var text_color: Color
    var font_size: Float64
    var point_radius: Float64
    var line_width: Float64
    var margin_left: Int
    var margin_right: Int
    var margin_top: Int
    var margin_bottom: Int
    var show_gridlines: Bool
    var color_scale_low: Color
    var color_scale_high: Color
    var size_range_min: Float64
    var size_range_max: Float64
    var show_legend: Bool
    var scale: Float64
    var donut_inner_radius_fraction: Float64
    var color_by_sign: Bool
    var mark_color_negative: Color
    var bullet_range_color_light: Color
    var bullet_range_color_dark: Color
    var line_smoothing: Float64
    var title_font_size: Float64
    var axis_title_font_size: Float64
    var waterfall_total_color: Color
    var font_family: String

    def __init__(
        out self,
        background: Color = WHITE,
        mark_color: Color = Color(30, 100, 180),
        axis_color: Color = Color(80, 80, 80),
        gridline_color: Color = Color(225, 225, 225),
        text_color: Color = Color(40, 40, 40),
        font_size: Float64 = 12.0,
        point_radius: Float64 = 3.5,
        line_width: Float64 = 2.0,
        margin_left: Int = 60,
        margin_right: Int = 20,
        margin_top: Int = 20,
        margin_bottom: Int = 50,
        show_gridlines: Bool = True,
        color_scale_low: Color = Color(60, 110, 200),
        color_scale_high: Color = Color(220, 90, 40),
        size_range_min: Float64 = 3.0,
        size_range_max: Float64 = 15.0,
        show_legend: Bool = True,
        scale: Float64 = 1.0,
        donut_inner_radius_fraction: Float64 = 0.0,
        color_by_sign: Bool = False,
        mark_color_negative: Color = Color(200, 60, 60),
        bullet_range_color_light: Color = Color(224, 224, 224),
        bullet_range_color_dark: Color = Color(120, 120, 120),
        line_smoothing: Float64 = 0.0,
        title_font_size: Float64 = 18.0,
        axis_title_font_size: Float64 = 14.0,
        waterfall_total_color: Color = Color(100, 100, 100),
        font_family: String = "sans-serif",
    ):
        self.background = background
        self.mark_color = mark_color
        self.axis_color = axis_color
        self.gridline_color = gridline_color
        self.text_color = text_color
        self.font_size = font_size
        self.point_radius = point_radius
        self.line_width = line_width
        self.margin_left = margin_left
        self.margin_right = margin_right
        self.margin_top = margin_top
        self.margin_bottom = margin_bottom
        self.show_gridlines = show_gridlines
        self.color_scale_low = color_scale_low
        self.color_scale_high = color_scale_high
        self.size_range_min = size_range_min
        self.size_range_max = size_range_max
        self.show_legend = show_legend
        self.scale = scale
        self.donut_inner_radius_fraction = donut_inner_radius_fraction
        self.color_by_sign = color_by_sign
        self.mark_color_negative = mark_color_negative
        self.bullet_range_color_light = bullet_range_color_light
        self.bullet_range_color_dark = bullet_range_color_dark
        self.line_smoothing = line_smoothing
        self.title_font_size = title_font_size
        self.axis_title_font_size = axis_title_font_size
        self.waterfall_total_color = waterfall_total_color
        self.font_family = font_family

    @staticmethod
    def default() -> Self:
        """Named the same way `FontSlant.NORMAL`-style call sites in
        this workspace read -- `Theme.default()` rather than relying
        on every caller remembering that `Theme()` alone already means
        the same thing (it does; this is purely for readability at
        call sites like `.theme(Theme.default())`).
        """
        return Self()
