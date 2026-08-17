Mojo module [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/theme.mojo)

# `theme`

Visual defaults for a Plot -- colors, sizes, margins -- kept as one small struct with sensible defaults rather than a dozen optional parameters scattered across Plot's own builder methods. This is deliberately the one place in this early vertical slice that borrows ECharts' "config object" ergonomics (a bundle of display knobs) rather than the grammar-of-graphics vocabulary the rest of dataviz follows -- appropriate here specifically because a theme isn't part of the data grammar (it doesn't change what a mark or scale *means*), just how it looks.

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

## Structs

- [`Theme`](Theme.md)

