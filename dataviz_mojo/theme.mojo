"""Visual defaults for a Plot -- colors, sizes, margins -- kept as one
small struct with sensible defaults rather than a dozen optional
parameters scattered across Plot's builder methods. This is
deliberately the one place in this early vertical slice that borrows
ECharts' "config object" ergonomics (a bundle of display knobs) rather
than the grammar-of-graphics vocabulary the rest of dataviz follows --
appropriate here specifically because a theme isn't part of the data
grammar (it doesn't change what a mark or scale *means*), just how it
looks.

Every field below typed `Color` takes a `dataviz_mojo.colors` named
constant exactly as it does a hand-built `Color(r, g, b)` -- `Theme(
mark_color=CORNFLOWERBLUE)` instead of `Theme(mark_color=Color(100,
149, 237))` -- see that module's docstring for the full list.

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
viewer's interpolation; more native pixels per glyph is the fix
that holds regardless of which viewer is doing the upscaling). Not a
crop/zoom -- the plot's logical layout (data domain, tick
positions, legend contents) is identical at every scale, only the
pixel measurements of everything drawn change.

Every one-call convenience function (`bar()`, `scatter()`, ...)
reads `scale` exactly the same way a hand-built `Plot` does -- it
returns a plain `Plot` (`dataviz_mojo.plot._finished`'s docstring),
not a rendered `Canvas`, so there's no separate quickplot-only
scaling behavior to distinguish `scale` from here at all.

Distinct from `render()`'s own internal supersampling
(`_RASTER_SUPERSAMPLE`, plot.mojo): that's a fixed, unconditional
multiplier `render()` applies and un-applies around one raster render
pass so PNG/BMP output just looks good, not a `Theme` field or
something this value composes with explicitly -- `scale` is the one
knob a caller actually sets to ask for a bigger/sharper export;
`render()`'s own supersampling is invisible plumbing underneath that
choice, not a second version of it.

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
whether its value is negative (`mark_color_negative`) or not
(`mark_color`) -- what a diverging bar chart's coloring
conventionally means (`Mark.BAR` already draws bars extending below a
zero baseline for negative values with no changes needed -- see
`_zero_baseline_y_extent`'s docstring; this is the one further
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
for an otherwise-complete plain bar chart. See either mark's `_render_*` docstring in plot.mojo.

`bullet_range_color_light`/`bullet_range_color_dark` are `Mark.BULLET`'s pair, unrelated to the sign-coloring fields above: the two ends of
a small monochrome gradient (via `dataviz_mojo.color_scale.ColorScale`, the
same stop-interpolation machinery `Plot.encode(color=...)`'s continuous channel uses) `_render_bullet` shades each category's
qualitative range bands with, lightest-to-darkest by range index --
deliberately grayscale by default (Stephen Few's original bullet-
chart convention), not `mark_color`-derived, so the shaded background
bands read as neutral context behind the one thing that *is* colored
with `mark_color`: the measure bar itself. Unlike `mark_color_negative`,
`Mark.BULLET`'s measure bar is never colored by sign -- see
`_render_bullet`'s docstring for why.

`color_scale_low`/`color_scale_mid`/`color_scale_high` are `Plot.encode(
color=...)`'s continuous channel (and every mark built directly on
`dataviz_mojo.color_scale.ColorScale` over its data domain --
`Mark.HEATMAP`/`CORRPLOT`/`CALENDAR_HEATMAP`, see each one's
`_render_*` docstring) -- three stops, not two: a real,
rendering-caught readability bug. Two stops alone (the
low/high colors directly, no `color_scale_mid`) linearly interpolate
in plain RGB space, and the *midpoint* of two saturated, hue-opposite
colors (the default low/high pair is blue/orange, chosen for
contrast) in RGB space is a desaturated, muddy brownish-grey -- not a
blend a viewer reads as "partway between blue and orange" at all. A
mark whose data happens to sit near the domain's extremes never shows
this, but the *legend* always spans the full domain end to end, so
that muddy
middle dominated most of its length -- reading as "one flat color"
even though the underlying gradient math was working correctly the
whole time. `color_scale_mid` (default a light neutral grey, `Color(
235, 235, 235)`) is the fix every real diverging colormap (matplotlib's
`coolwarm`, ColorBrewer's `RdBu`, ...) already uses: route the
transition through a genuine third, deliberately desaturated color
instead of letting linear RGB interpolation pick an accidental one.
Added at gradient offset `0.5` alongside the existing `0.0`/`1.0`
stops everywhere a `ColorScale` gets built from `Theme` (see `dataviz_
mojo.color_scale.ColorScale.from_theme`'s docstring) -- a caller
who genuinely wants a plain two-hue transition (a sequential, not
diverging, scale) can still set `color_scale_mid` to whatever reads
right for that specific pair, the same way every other color field
here is a real, overridable default, not a hardcoded internal.

`line_smoothing` (default `0.0` -- `Mark.LINE`/`Mark.AREA` draw exactly
the straight point-to-point segments they always have) controls how
much `_build_line_path` curves a line (or an area's top edge)
through its data points, via a Catmull-Rom-derived cubic Bezier
spline -- `0.0` builds a plain straight-segment `Path` (no curve math
touched at all, not merely a degenerate curve that happens to look
straight, so the default is byte-for-byte identical to every pre-
existing `Mark.LINE`/`AREA` render, not just visually close), `1.0` the
full, standard Catmull-Rom curve through every point, and anything in
between scales each segment's tangent vector by that fraction --
so `0.5` bows exactly half as far from the straight path as `1.0` does
at the same point. Must be in `[0.0, 1.0]` -- `_render_generic` raises
otherwise, an overshoot tension this package assigns no meaning to
rather than silently rendering an unbounded, likely-self-intersecting
curve. `Mark.AREA` only smooths its *top* edge (through the data
points) -- the bottom edge down to/along the zero baseline stays
straight, since baseline is a fixed reference line, not data, with
nothing to curve through. See `_build_line_path`'s docstring
(plot.mojo) for the control-point formula, shared unchanged by both
marks.

`title_font_size`/`subtitle_font_size`/`axis_title_font_size` are the
three sizes `Plot.labels()` needs (see that method's docstring for
the four strings themselves -- `title`/`subtitle`/`x_title`/`y_title`
-- and the layout math that uses these): a chart title reads as a
heading, so it defaults larger than everything else on the plot (18.0,
vs. `font_size`'s 12.0 for tick/legend labels); an axis title (a
caption under the x-axis or rotated alongside the y-axis, e.g.
"Revenue ($)") reads as a subordinate label, not body text or a
heading, so it defaults between the two (14.0); `subtitle` shares that
same 14.0 default -- the classic editorial two-tier headline reads
title-then-subtitle as "heading, then a smaller supporting line," the
identical size relationship an axis title already has to the title,
not a fourth distinct size this package would need to separately
justify. All three are plain `Float64` points, scaled by `Theme.scale`
the same as `font_size` itself -- see `_Scaled`'s docstring
(plot.mojo) for why every pixel-sized quantity goes through that one
struct rather than each render path applying `* scale` itself. No
titles are drawn by default (`Plot._labels`'s `title`/`subtitle`/
`x_title`/`y_title` all default to `""`), so these three sizes only matter
once a caller actually calls `.labels(...)` -- an empty string never
reserves layout space or emits a `_TextRequest`, the same "absent
means absent, not a zero-size version of present" rule `Plot.encode_
gantt`'s start/end
pair and every other optional feature in this file follow.

`subtitle_color` (default a muted gray, `Color(110, 110, 110)`,
distinct from `text_color`'s default `Color(40, 40, 40)`) is
`subtitle`'s dedicated color, not `text_color` reused -- the
second half of the two-tier-headline reading `title_bold`'s docstring gives for the title itself: a subtitle is
supporting context, not body text or a heading, so it recedes rather
than competing with either -- the same "a genuinely distinct visual
role gets its color, not a borrowed one" reasoning `waterfall_
total_color` below gives.

`waterfall_total_color` is `Mark.WATERFALL`'s third color, for a
row `encode_waterfall()`'s `is_total` marks as a running-total
checkpoint rather than a rising/falling delta -- deliberately a third,
neutral color (default a plain gray, `Color(100, 100, 100)`), not
`mark_color`/`mark_color_negative` reused: a total bar isn't "a big
increase" or "a big decrease," it's a different *kind* of thing on the
same chart (where things stand, not what just changed), so it reads
clearest with its color rather than borrowing meaning from the
rising/falling pair. See `_render_waterfall`'s docstring for the
full total-bar drawing story (also wider than a delta bar -- full band
width vs. `waterfall_delta_width_fraction` below).

`waterfall_delta_width_fraction` (default 0.6) is how much of its band a rising/falling delta bar occupies; a total bar always spans the
full band, so this is what visually separates the two.

`bullet_measure_width_fraction` (default 0.35) is how thick `Mark.
BULLET`'s measure bar is relative to its band, and
`chord_ring_fraction` (default 0.08) how thick `Mark.CHORD`'s node ring
is relative to the outer radius -- the same *fraction of something the
layout already computed* shape `donut_inner_radius_fraction` has, and
for the same reason: a fixed pixel value would look right at one canvas
size and wrong at every other.

`radialbar_track_color` (default a light grey) is the unfilled track
`Mark.RADIALBAR` sweeps its rings over, and `treemap_label_color`
(default white) the label drawn on a `Mark.TREEMAP` leaf rect -- both
sit on top of palette-colored shapes, so both are real contrast
choices a caller may need to change rather than internal details.

`halo_alpha` (default 90) is the opacity `Mark.EFFECT_SCATTER` blends
each point's halo at, before flattening it against white -- see
`_lighten`'s docstring for why it is flattened rather than drawn
translucent. `radar_fill_alpha` (also 90) is the same treatment for
`Mark.RADAR`'s filled series polygons.

Two fields rather than one shared "tint alpha", even though both
default to 90: a single shared constant would silently couple a
scatter halo's tint to a radar fill's. Nothing connects those two
beyond the number having happened to suit both, so retheming one
should not move the other.

`annotation_color` (default a plain medium gray, `Color(150, 150,
150)`) is `Plot.annotate_line()`'s color -- both the reference
line itself and its optional label share this one color, reading as
one cohesive annotation rather than two independently colored pieces.
Distinct from `mark_color` (a reference line is explicitly *not* data,
so borrowing the data's color would blur that distinction) and
from `axis_color`/`gridline_color` (this needs to read as more present
than either -- a reference line is meant to be noticed, not recede
into the chrome). Not `subtitle_color` reused either, even though both
default to a similarly muted gray -- two different roles that happen
to share a similar visual weight today, not a promise they'll always
share a value; each gets its field so retheming one doesn't
silently retheme the other.

`annotation_area_color` (default a pale blue-gray at partial opacity,
`Color(224, 236, 246, 200)`) is `Plot.annotate_area()`'s fill -- a
genuinely separate field from `annotation_color`, not that same gray
reused, because a *filled* rectangle needs to read very differently
from a *line*: solid medium gray as a fill would read as an opaque,
obtrusive block, while a 1px stroke in the same gray reads as a thin,
unobtrusive mark. `Plot.annotate_area()`'s label text still uses
`annotation_color`, not this field -- ink and fill are two different
jobs even on the same annotation, the same split `mark_color`/
`text_color` already have everywhere else. Real alpha (`a=200`, not
the `_lighten()`-style pre-blend-against-white `halo_alpha`/
`radar_fill_alpha` use), unlike those two: a halo/radar fill wants a
*consistent* tint regardless of what happens to be behind it, but a
reference band's whole point is marking a region on the *existing*
chart, so it should let whatever the mark drew there keep showing
through instead of painting fully over it. Both canvas_mojo backends
already composite `Color.a` correctly (`Canvas.write_pixel`'s
`blend_over`, `SvgCanvas.fill_rect`'s `fill-opacity`), so this is a
plain color value, not special-cased draw logic. Tuned so the over-white look
stays close to the old fully-opaque pale fill (`a=200` over white
lands within a few units of `(224, 236, 246)`), while a mark's own
color still visibly shows through wherever a band overlaps it.

`font_family` (default `"sans-serif"`) is every `_TextRequest`'s typeface -- tick/legend labels, axis titles, the chart title, all of
it, baked into each `_TextRequest` at the point it's built (the same
"read straight off `theme`, per construction site" convention every
other `_TextRequest` field -- `color`, `size` -- follows,
*not* a single value read once by `render()`/`render_svg()`'s final draw loop: `render_facets()`/`render_layers()` combine several
independently themed `Plot`s into one shared draw pass, so a family
read once, globally, would silently apply the wrong plot's choice
to every other plot sharing that canvas). `"sans-serif"` is
deliberately a value valid in *both* worlds a caller's chosen family
ends up in -- `canvas_mojo.text.draw_text`'s raster path resolves
it as a fontconfig family/alias (fontconfig ships `sans-serif` as a
recognized generic alias, the same generic-substitution concept CSS's `sans-serif` keyword is, alongside its older capitalized `Sans`
form), while `SvgCanvas.draw_text`'s `family` parameter is a
literal CSS `font-family` value the SVG viewer interprets directly --
two genuinely different value spaces (a fontconfig alias resolves to
one concrete font *file*; a CSS value is interpreted by whatever's
rendering the SVG, with no file resolution on this package's side
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

`title_bold` (default `True`) bolds `Plot.labels()`'s chart
title -- and only the title: `x_title`/`y_title` and every other
`_TextRequest` (tick/legend labels) stay normal weight always, not
configurable here, the same "one deliberate exception, not a general
knob" scope this field itself is. The one default in this whole
struct that isn't backward-compatible: every other field's default
reproduces exactly what `render()` already produces without it (see
`font_family`'s docstring for why that one does); this one exists
because a plain-weight title doesn't read as polished enough on its
own -- the one place a caller-visible aesthetic default, not just a
new capability, changed. Still overridable
(`Theme(title_bold=False)` reproduces the old look exactly) for a
caller who wants it. Threaded the identical way `font_family` is --
`_TextRequest`'s `bold: Bool = False` field, left untouched at
every construction site except the title's in `_label_text_
requests` (`bold=theme.title_bold`) -- rather than baked in
everywhere `font_family` needed to be, since nothing else ever wants
`True`."""

from std.math import pi

from canvas_mojo.color import Color

from dataviz_mojo.colors import WHITE
from dataviz_mojo.output_format import OutputFormat


struct Theme(ImplicitlyCopyable, Movable):
    var background: Color
    """The canvas's fill color, drawn behind everything else."""
    var mark_color: Color
    """The default ink a mark draws in -- bar fill, line stroke,
    point fill, ... -- whenever no data-driven `color`/`color_categories`
    channel or per-mark override (`mark_color_negative`, a palette,
    ...) applies instead."""
    var axis_color: Color
    """The axis line/tick/frame color."""
    var gridline_color: Color
    """Gridline color, drawn when `show_gridlines` is `True`."""
    var text_color: Color
    """The default text color -- tick labels, the chart title, and
    anywhere else no more specific color field (`subtitle_color`,
    `annotation_color`, ...) applies."""
    var font_size: Float64
    """The base font size, in points, for tick/legend labels --
    scaled by `Theme.scale` the same as every other pixel-sized
    quantity (see `_Scaled`'s docstring, plot.mojo)."""
    var point_radius: Float64
    """The default pixel radius for `Mark.POINT`/`EFFECT_SCATTER`
    markers, before any data-driven `size` channel overrides it."""
    var line_width: Float64
    """The default stroke width, in pixels, for `Mark.LINE`/`AREA`
    and every other stroked mark."""
    var margin_left: Int
    """Reserved pixel space along the plot's left edge, before the
    y-axis's own tick-label width/`margin_buffer` are added on top."""
    var margin_right: Int
    """Reserved pixel space along the plot's right edge, before a
    legend's own reserved width (if any) is added on top."""
    var margin_top: Int
    """Reserved pixel space along the plot's top edge, before a
    title/subtitle's own reserved height (if any) is added on top."""
    var margin_bottom: Int
    """Reserved pixel space along the plot's bottom edge, before an
    x-axis title's own reserved height (if any) is added on top."""
    var show_gridlines: Bool
    """Whether to draw gridlines at all; defaults to `True`."""
    var color_scale_low: Color
    """The low end of the default continuous color gradient (`Plot.
    encode(color=...)`, `Mark.HEATMAP`/`CORRPLOT`/`CALENDAR_HEATMAP`)."""
    var color_scale_mid: Color
    """The midpoint of the default continuous color gradient -- a
    deliberate third stop, not a two-color blend; see this struct's
    own module docstring for why a plain low/high interpolation reads
    as a muddy, desaturated middle."""
    var color_scale_high: Color
    """The high end of the default continuous color gradient."""
    var size_range_min: Float64
    """The smallest pixel radius a data-driven `size` channel maps
    its column's minimum value to."""
    var size_range_max: Float64
    """The largest pixel radius a data-driven `size` channel maps
    its column's maximum value to."""
    var show_legend: Bool
    """Whether to draw a legend at all, for every mark that has one;
    defaults to `True`."""
    var scale: Float64
    """Uniformly multiplies every other pixel-sized quantity
    `render()` computes (font size, margins, point radius, line
    width, tick length, legend layout, ...); see this struct's own
    module docstring for the full HiDPI-rendering reasoning."""
    var donut_inner_radius_fraction: Float64
    """A fraction (`[0.0, 1.0)`) of `Mark.ARC`'s outer radius to leave
    as a hole -- `0.0` (the default) draws an ordinary pie; any
    positive value draws a donut."""
    var color_by_sign: Bool
    """Whether `Mark.BAR` colors each bar by whether its value is
    negative (`mark_color_negative`) or not (`mark_color`); defaults
    to `False` (every bar stays `mark_color`)."""
    var mark_color_negative: Color
    """The ink for a negative value -- `Mark.BAR` when `color_by_sign`
    is `True`, and unconditionally for `Mark.WATERFALL`/`CANDLESTICK`,
    whose falling/down coloring isn't optional."""
    var bullet_range_color_light: Color
    """The lightest end of `Mark.BULLET`'s grayscale qualitative-range
    band gradient (lowest range index)."""
    var bullet_range_color_dark: Color
    """The darkest end of `Mark.BULLET`'s grayscale qualitative-range
    band gradient (highest range index)."""
    var line_smoothing: Float64
    """How much `Mark.LINE`/`AREA` curves through its data points, via
    a Catmull-Rom-derived spline -- `0.0` (the default) draws plain
    straight segments; `1.0` the full curve; must be in `[0.0, 1.0]`."""
    var title_font_size: Float64
    """The chart title's font size, in points; defaults larger than
    `font_size` since a title reads as a heading."""
    var subtitle_font_size: Float64
    """The subtitle's font size, in points -- the same size an axis
    title uses, both reading as a subordinate label under the title."""
    var subtitle_color: Color
    """The subtitle's dedicated color, distinct from `text_color` so
    it recedes as supporting context rather than competing with the
    title."""
    var axis_title_font_size: Float64
    """The x/y-axis title's font size, in points."""
    var waterfall_total_color: Color
    """`Mark.WATERFALL`'s third color, for a row `encode_waterfall()`'s
    `is_total` marks as a running-total checkpoint -- deliberately
    distinct from `mark_color`/`mark_color_negative` since a total bar
    is a different kind of thing, not a big increase or decrease."""
    var annotation_color: Color
    """`Plot.annotate_line()`/`annotate_vline()`/`annotate_point()`'s
    color -- the reference mark itself and its optional label."""
    var annotation_area_color: Color
    """`Plot.annotate_area()`'s fill -- a separate field from
    `annotation_color` since a filled band needs real partial opacity
    to let the mark underneath keep showing through, unlike a line."""
    var font_family: String
    """Every `_TextRequest`'s typeface; defaults to `"sans-serif"`, a
    generic keyword both the raster (fontconfig) and SVG (CSS) text
    backends resolve consistently."""
    var title_bold: Bool
    """Whether the chart title draws bold; defaults to `True`. The one
    field in this struct whose default isn't backward-compatible with
    pre-existing renders -- see this struct's own module docstring."""
    var waterfall_delta_width_fraction: Float64
    """How much of its band a rising/falling `Mark.WATERFALL` delta
    bar occupies; a total bar always spans the full band."""
    var bullet_measure_width_fraction: Float64
    """How thick `Mark.BULLET`'s measure bar is relative to its band."""
    var chord_ring_fraction: Float64
    """How thick `Mark.CHORD`'s node ring is relative to the outer
    radius."""
    var radialbar_track_color: Color
    """The unfilled background track `Mark.RADIALBAR` sweeps its
    rings over."""
    var treemap_label_color: Color
    """The label color drawn on a `Mark.TREEMAP` leaf rectangle."""
    var halo_alpha: UInt8
    """The opacity `Mark.EFFECT_SCATTER` blends each point's halo at,
    before flattening it against white."""
    var radar_fill_alpha: UInt8
    """The opacity `Mark.RADAR` blends each series' filled polygon at,
    before flattening it against white -- a separate field from
    `halo_alpha` even though both default to the same value, so
    retheming one never silently moves the other."""
    var radialbar_ring_gap_fraction: Float64
    """The gap between adjacent `Mark.RADIALBAR` rings, as a fraction
    of each ring's own slot."""
    var violin_width_fraction: Float64
    """How much of its category's band width a `Mark.VIOLIN`'s peak
    density maps to, by default (ggplot2's `scale = "width"`)."""
    var corrplot_bubble_fraction: Float64
    """How much of a `Mark.CORRPLOT` cell's smaller dimension its
    bubble's maximum radius (at `abs(correlation) == 1.0`) fills."""
    var gauge_band_inner_fraction: Float64
    """`Mark.GAUGE`'s color-banded dial ring's inner radius, as a
    fraction of the dial's outer radius."""
    var gauge_needle_fraction: Float64
    """`Mark.GAUGE`'s needle length, as a fraction of the dial's
    outer radius."""
    var ridgeline_overlap: Float64
    """How far a `Mark.RIDGELINE` row's curve may rise into the row
    above it, as a multiple of one row's own height."""
    var polar_bar_padding: Float64
    """The gap `Mark.POLAR_BAR` leaves out of each bar's angular slot,
    as a fraction of that slot."""
    var polar_grid_rings: Int
    """How many evenly spaced concentric gridline rings `Mark.POLAR`
    draws."""
    var polar_grid_spokes: Int
    """How many straight radial gridline spokes `Mark.POLAR` draws."""
    var radar_grid_rings: Int
    """How many concentric gridline rings `Mark.RADAR` draws."""
    var gauge_start_angle: Float64
    """`Mark.GAUGE`'s dial start angle, in radians (this package's
    usual clockwise-from-3-o'clock convention)."""
    var gauge_sweep_angle: Float64
    """`Mark.GAUGE`'s total dial sweep, in radians, from
    `gauge_start_angle`."""
    var tick_length: Int
    """The pixel length of each axis tick mark."""
    var label_gap: Int
    """The pixel gap between a tick mark and its label."""
    var legend_width: Int
    """The reserved pixel width for a legend's swatch-plus-label
    column, when its dynamic width can't be computed some other way."""
    var legend_swatch_size: Int
    """The pixel size of each legend entry's color swatch."""
    var legend_row_gap: Int
    """The pixel gap between consecutive legend entries."""
    var continuous_legend_bar_width: Int
    """The pixel width of a continuous (gradient) legend's color bar."""
    var continuous_legend_bar_height: Int
    """The pixel height of a continuous (gradient) legend's color
    bar."""
    var margin_buffer: Int
    """Extra breathing-room padding, in pixels, added after a
    margin's own tick-label-width/tick-length/label-gap computation."""
    var sankey_node_width: Float64
    """The pixel width of each `Mark.SANKEY` node column's bar."""
    var error_bar_cap_width: Float64
    """Half the pixel width of the horizontal cap `Plot.encode()`'s
    `y_err` channel draws at each end of a point's error-bar whisker --
    `Mark.BOX`'s own whisker caps are sized from each category's own
    band width instead (there's a natural width to derive one from,
    a `Mark.BOX` category has no equivalent), so this is a real,
    independent `Theme` field, not a reuse of anything else here."""
    var output_format: OutputFormat
    """The file format `save()` (plot.mojo) writes when given a `Plot`
    and a path, with no `canvas_mojo` backend named at the call site --
    defaults to `OutputFormat.SVG` (see that struct's docstring for why
    vector is the default). `render()`/`render_svg()` ignore this field
    entirely; it only governs `save()`'s own choice."""
    var show_data_labels: Bool
    """Whether `Mark.BAR`/`GROUPED_BAR`/`STACKED_BAR` draws each bar's
    own value as text -- `False` (the default, every existing render
    stays byte-identical) draws nothing extra; `True` draws the same
    value the bar's own height already encodes, in `text_color` at
    `font_size`. Formatted via `_label_decimals()` (scale.mojo) --
    the fewest decimal places that represent that specific value
    exactly, deliberately *not* the y-axis's own (coarser) `Ticks.
    decimals`, so a label always shows the real number a bar's height
    alone can't convey precisely, not the tick grid's rounded version
    of it. An opt-in flag on `Theme` rather than a new `encode()`
    channel, the same "changes how a mark draws, not new data" pattern
    `color_by_sign` already sets -- unlike `color_by_sign`, this is a
    single flag shared by every categorical-bar mark (`Mark.POINT`'s
    own data-label case needs a genuine text column via `encode()`,
    a real, separate feature -- not attempted here)."""

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
        color_scale_mid: Color = Color(235, 235, 235),
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
        subtitle_font_size: Float64 = 14.0,
        subtitle_color: Color = Color(110, 110, 110),
        axis_title_font_size: Float64 = 14.0,
        waterfall_total_color: Color = Color(100, 100, 100),
        annotation_color: Color = Color(150, 150, 150),
        annotation_area_color: Color = Color(224, 236, 246, 200),
        font_family: String = "sans-serif",
        title_bold: Bool = True,
        waterfall_delta_width_fraction: Float64 = 0.6,
        bullet_measure_width_fraction: Float64 = 0.35,
        chord_ring_fraction: Float64 = 0.08,
        radialbar_track_color: Color = Color(230, 230, 230),
        treemap_label_color: Color = Color(255, 255, 255),
        halo_alpha: UInt8 = 90,
        radar_fill_alpha: UInt8 = 90,
        radialbar_ring_gap_fraction: Float64 = 0.25,
        violin_width_fraction: Float64 = 0.4,
        corrplot_bubble_fraction: Float64 = 0.42,
        gauge_band_inner_fraction: Float64 = 0.7,
        gauge_needle_fraction: Float64 = 0.9,
        ridgeline_overlap: Float64 = 1.3,
        polar_bar_padding: Float64 = 0.2,
        polar_grid_rings: Int = 4,
        polar_grid_spokes: Int = 12,
        radar_grid_rings: Int = 4,
        gauge_start_angle: Float64 = 3.0 * pi / 4.0,
        gauge_sweep_angle: Float64 = 3.0 * pi / 2.0,
        tick_length: Int = 5,
        label_gap: Int = 4,
        legend_width: Int = 130,
        legend_swatch_size: Int = 14,
        legend_row_gap: Int = 8,
        continuous_legend_bar_width: Int = 14,
        continuous_legend_bar_height: Int = 100,
        margin_buffer: Int = 8,
        sankey_node_width: Float64 = 12.0,
        error_bar_cap_width: Float64 = 4.0,
        output_format: OutputFormat = OutputFormat.SVG,
        show_data_labels: Bool = False,
    ):
        """Construct a `Theme`, overriding any subset of its fields by
        keyword -- every parameter here is one field, same name, same
        default; see each field's own docstring above for what it
        controls rather than this method repeating it, so a change to
        one never has a second copy elsewhere to fall out of sync."""
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
        self.color_scale_mid = color_scale_mid
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
        self.subtitle_font_size = subtitle_font_size
        self.subtitle_color = subtitle_color
        self.axis_title_font_size = axis_title_font_size
        self.waterfall_total_color = waterfall_total_color
        self.annotation_color = annotation_color
        self.annotation_area_color = annotation_area_color
        self.font_family = font_family
        self.title_bold = title_bold
        self.waterfall_delta_width_fraction = waterfall_delta_width_fraction
        self.bullet_measure_width_fraction = bullet_measure_width_fraction
        self.chord_ring_fraction = chord_ring_fraction
        self.radialbar_track_color = radialbar_track_color
        self.treemap_label_color = treemap_label_color
        self.halo_alpha = halo_alpha
        self.radar_fill_alpha = radar_fill_alpha
        self.radialbar_ring_gap_fraction = radialbar_ring_gap_fraction
        self.violin_width_fraction = violin_width_fraction
        self.corrplot_bubble_fraction = corrplot_bubble_fraction
        self.gauge_band_inner_fraction = gauge_band_inner_fraction
        self.gauge_needle_fraction = gauge_needle_fraction
        self.ridgeline_overlap = ridgeline_overlap
        self.polar_bar_padding = polar_bar_padding
        self.polar_grid_rings = polar_grid_rings
        self.polar_grid_spokes = polar_grid_spokes
        self.radar_grid_rings = radar_grid_rings
        self.gauge_start_angle = gauge_start_angle
        self.gauge_sweep_angle = gauge_sweep_angle
        self.tick_length = tick_length
        self.label_gap = label_gap
        self.legend_width = legend_width
        self.legend_swatch_size = legend_swatch_size
        self.legend_row_gap = legend_row_gap
        self.continuous_legend_bar_width = continuous_legend_bar_width
        self.continuous_legend_bar_height = continuous_legend_bar_height
        self.margin_buffer = margin_buffer
        self.sankey_node_width = sankey_node_width
        self.error_bar_cap_width = error_bar_cap_width
        self.output_format = output_format
        self.show_data_labels = show_data_labels

    @staticmethod
    def default() -> Self:
        """Named the same way `FontSlant.NORMAL`-style call sites in
        this workspace read -- `Theme.default()` rather than relying
        on every caller remembering that `Theme()` alone already means
        the same thing (it does; this is purely for readability at
        call sites like `.theme(Theme.default())`).
        """
        return Self()
