"""The geometric primitive a data row becomes -- the grammar-of-
graphics `mark` concept. Follows the same small-struct-with-comptime-
constants-and-`__eq__` pattern canvas_mojo.FillRule/canvas_mojo.TextAlign
already established, not a distinct enum mechanism.

POINT (scatter) and LINE were this package's first vertical slice
(see the wiki). LINE's own `Theme.line_smoothing` (default
0.0, plain straight segments) optionally curves it through a Catmull-
Rom-derived spline instead -- see that field's own docstring and
`plot.mojo`'s `_build_line_path`. BAR is the first mark with a categorical
axis -- see ordinal_scale.mojo and Plot.encode_categorical(). AREA
shares LINE's continuous x/y encoding but fills to a zero baseline the
way BAR does. ARC (pie/donut wedges) shares BAR's `encode_categorical`
data shape (category + value) -- a pie chart is the same underlying
data as a bar chart, wrapped around a circle instead of laid out
linearly -- but has no x/y axis frame at all, so it renders through
its own, fully separate path (see plot.mojo's `_render_arc`).

LOLLIPOP, WATERFALL, and BOX ("Phase 2a" of the broader chart-type
survey, see the wiki) are three more categorical-x-axis
marks alongside BAR: LOLLIPOP reuses BAR's own `encode_categorical`
data shape unchanged (a stem + point instead of a filled rect is
purely a rendering difference); WATERFALL has its own `encode_
waterfall` (a category + a *signed delta*, not a plain value -- see
that method's own docstring for the running-total bookkeeping this
does, including its optional `is_total` running-total-checkpoint rows,
drawn full band width in `Theme.waterfall_total_color` instead of a
narrower rising/falling delta bar); BOX has its own `encode_boxplot`
(a category + a whole
*distribution* of raw values, not one number -- see that method's own
docstring for the quartile/whisker/outlier computation it does up
front). All four now share one axis-frame layout core (`_draw_
categorical_axis_frame`) rather than each duplicating it -- see that
function's own docstring for why sharing became the right call once a
third and fourth mark type needed the identical layout.

CANDLESTICK and BULLET ("Phase 2b", the marks that need their own new
shape rather than building on BAR's data directly -- see
the wiki) are a fifth and sixth categorical-x-axis mark
sharing that same axis-frame core. CANDLESTICK's own `encode_
candlestick` (a category plus four values -- open/high/low/close, not
BAR's single value) draws a high-low wick plus an open-close body per
category, colored by whether the category closed up or down -- see
`_render_candlestick`'s own docstring for the drawing order and why it
reuses `Theme.mark_color`/`mark_color_negative` unconditionally rather
than adding dedicated bullish/bearish fields. BULLET's own `encode_
bullet` (a category plus a measure, a target, and a whole *list* of
qualitative-range thresholds -- the most values any `encode_*` here
takes) draws Stephen Few's bullet-chart composite: shaded background
range bands, a narrower measure bar, and a target tick -- see
`_render_bullet`'s own docstring for the drawing order and why, unlike
CANDLESTICK/WATERFALL, its measure bar is never colored by sign.

GANTT (the last of "Phase 2b") is the first mark whose categories run
along a *horizontal* axis instead of a vertical one -- a project-
schedule/span chart, one floating horizontal bar per category from a
start value to an end value (`encode_gantt`, deliberately no Date/Time
type of its own -- see that method's own docstring). Shares nothing
structurally with `_draw_categorical_axis_frame` (`x`/`y`'s roles are
swapped throughout: the continuous scale is now `x`, the categorical
one now `y`) -- see its own mirror-image core, `_draw_horizontal_
categorical_axis_frame`, and its docstring for why this stayed a
separate function rather than a generalized, orientation-flagged
version of the vertical one.

GROUPED_BAR is BAR generalized from one value per category to *several*
(`encode_grouped_bar`: categories, a name per series, and a value per
(series, category) pair) -- back on `_draw_categorical_axis_frame`'s
own shared vertical axis-frame core (categories still run one way, the
same as BAR/LOLLIPOP/etc.), just subdividing each category's own band
into one sub-bar per series instead of drawing a single bar across the
whole band. The one other new thing: a legend (series name -> color),
which no other categorical-x-axis mark needs -- see `_render_grouped_
bar`'s own docstring for the palette/legend-reservation details.

STACKED_BAR reuses `encode_grouped_bar`'s own data shape completely
unchanged (`Plot.mark_stacked_bar().encode_grouped_bar(...)`, the exact
same call LOLLIPOP's own reuse of BAR's `encode_categorical` already
established the precedent for -- identical data, purely a rendering
difference) -- each category's own series stack vertically instead of
sitting side by side: full band width per segment, one segment on top
of the previous one's own running total instead of `GROUPED_BAR`'s
divided sub-bars. See `_render_stacked_bar`'s own docstring for the
mixed-sign running-total bookkeeping (positive and negative values
stack in their own direction from zero, independently) and why no
extra pixel-boundary-rounding trick is needed here the way `GROUPED_
BAR`'s own sub-bar division needed one.

POPULATION_PYRAMID ("Phase 3" of the broader chart-type survey, the
first of the ECharts-parity gap-closing marks) is `GANTT`'s own
horizontal categorical axis frame (`_draw_horizontal_categorical_axis_
frame`, reused unchanged) with two magnitude bars per row instead of
one start/end span: `encode_population_pyramid`'s `left_values`/
`right_values` each grow outward from a shared, always-centered zero
baseline instead of floating between two arbitrary endpoints the way
`GANTT`'s span does -- see that method's own docstring, and `_render_
population_pyramid`'s for the symmetric domain this forces (so equal
magnitudes on each side draw visually equal-length bars) and the
two-color legend (`left_name`/`right_name`), the one other new thing
no other horizontal mark needs.

HEATMAP (the second gap-closing mark) is the first mark with *two*
categorical axes and no continuous one at all: `encode_heatmap`'s `x`/
`y`/`value` (one row per grid cell, `x`/`y` deduplicated into each
axis's own domain via `_categorical_indices`, the same helper `Mark.
POINT`'s own categorical color channel already uses) draws a filled
cell per row, colored through a continuous `ColorScale` spanning
`value`'s own [min, max] -- `Theme.color_scale_low`/`color_scale_high`,
the exact gradient `Mark.POINT`'s own continuous `color=` channel
already uses. Its own `_draw_grid_axis_frame` (heatmap.mojo), not a
generalization of either existing categorical-axis core -- see that
function's own docstring for why, and for the `padding=0.0` choice
that makes cells tile edge-to-edge instead of `Mark.BAR`'s own
separated bands.

CHORD (the third and, so far, last of the gap-closing marks -- not
"Arc Diagram" in the network-node-link-over-a-line sense, a genuinely
different chart type that happens to share a name with this package's
own pre-existing `ARC`) is the first mark drawn from an *edge list*
(`encode_chord`'s `from_categories`/`to_categories`/`values`, one row
per flow) rather than one row per category. Its nodes reuse `Mark.
ARC`'s own start-at-12-o'clock, sweep-clockwise ring-sector convention
(sized by each node's total flow, not one value), connected by curved
ribbons (`_draw_chord_ribbon`, chord.mojo -- a real `Path.arc_to` for
each rim, plus a `Path.quad_curve_to` pulled toward the circle's own
center for each cross connection) drawn through `DrawTarget.
fill_path_aa`. See
chord.mojo's own docstrings for the per-node running-angle bookkeeping
(`_render_chord`) and the ribbon geometry itself (`_draw_chord_
ribbon`).

SINGLE_AXIS ("Phase 2", the ECharts-parity gap-closing marks that
build on existing infrastructure at low cost -- see the wiki) is the
first mark with only *one* axis drawn at all: `encode_single_axis`'s
own `x` (plus the usual optional `color`/`color_categories`/`size`
channels `Mark.POINT` already supports), one point per row, all placed
at a single fixed pixel row via a degenerate zero-span `y_scale` --
reuses `Mark.POINT`'s own `_draw_point_layer` completely unchanged.
Its own one-axis frame, `_draw_single_axis_frame` (single_axis.mojo).

EFFECT_SCATTER needs no new file, no new `encode_*` method, and no new
axis frame at all -- it's `Mark.POINT`'s own continuous x/y encoding
and channels, unchanged, through the exact same `_draw_point_layer`,
with one flag flipped (`draw_halo=True`): a lighter, larger circle
drawn under each point first. A static stand-in for ECharts' own real
effect-scatter behavior (an animated ripple around each point), which
a raster/SVG renderer with no animation concept has no way to
reproduce -- see `_draw_point_layer`'s own `draw_halo` paragraph and
`_lighten`'s docstring (plot.mojo) for why this uses `Color.blend_over`
rather than real alpha transparency.

FUNNEL reuses `Mark.BAR`/`ARC`'s own `encode_categorical` data shape
unchanged (category + value) -- like `ARC`, it has no axis frame at
all, drawing one trapezoid per category top to bottom, largest value
first (`_descending_value_order`, funnel.mojo -- ECharts' own default
"highest to lowest" ordering, not the caller's own row order every
other categorical mark here keeps), each row's own bottom width equal
to the *next* row's own top width for a continuous taper. See
`_render_funnel`'s own docstring for the row-height/palette-by-
display-position rules.

BUMP reuses `Mark.GROUPED_BAR`/`STACKED_BAR`'s own `encode_grouped_bar`
data shape unchanged (categories, one name and one value per series) --
but plots each series' own *rank* at each category (1 = highest value
among every series there, via `_descending_value_order`, reused from
funnel.mojo -- one sort per category) instead of its raw value, as one
line per series (`Mark.LINE`'s own `_build_line_path`, smoothing
included). Its own hand-rolled rank axis, `_draw_bump_axis_frame`
(bump.mojo) -- see that function's own docstring for why a real
`LinearScale` doesn't work for "rank 1 at the top."

STREAMGRAPH (the last of Phase 2) reuses `Mark.STACKED_BAR`'s own
running-total stacking over `encode_grouped_bar`'s data, but each
category's own stack starts from `-total_i / 2` instead of a shared
zero (`_symmetric_zero_baseline_y_extent`, streamgraph.mojo -- the
same "forced symmetric" reasoning `POPULATION_PYRAMID`'s own x-domain
helper already established, applied to a per-category stacked total
instead), so the whole picture floats centered around zero -- the
"silhouette" look -- and each series draws as one flowing filled band
across every category (straight `line_to` between category centers,
`DrawTarget.fill_path_aa`) instead of `STACKED_BAR`'s own discrete
rects. Reuses `_draw_categorical_axis_frame` unchanged.

BEESWARM (the first of "Phase 3", the distribution-shape family --
see the wiki) has its own new `encode_distribution` (categories, one
*list* of raw values per category, kept unsummarized -- the same
outer-list-indexes-categories shape `encode_boxplot` already
established, but `Mark.BOX` immediately reduces each list to a five-
number summary, discarding the raw values; `VIOLIN`/`RIDGELINE` share
this same new encode method, since both need the raw values too, for a
density estimate). One point per raw value, jittered sideways within
its own category's band to avoid overlap (`_beeswarm_offsets`,
beeswarm.mojo -- a deterministic row-clustering swarm, not a full
physics-style one; see that function's own docstring for why).
Reuses `_draw_categorical_axis_frame` unchanged, `_data_extent` (not
zero-forced) over every value across every category -- the same
domain reasoning `Mark.BOX` already gives for this same data shape.

VIOLIN reuses `BEESWARM`'s own `encode_distribution` unchanged, drawing
a symmetric kernel-density-estimate silhouette per category instead of
individual jittered points -- Silverman's rule of thumb (std-only, a
deliberate simplification of the fuller IQR-adjusted version -- see
`_kde_bandwidth`'s own docstring, violin.mojo) for the KDE's own
bandwidth, sampled at `_KDE_SAMPLES` points across each category's own
`[min, max]`, each violin's own peak density independently scaled to
`_VIOLIN_WIDTH_FRACTION` of its own band width (ggplot2's own default
`scale = "width"`, not `scale = "area"` -- see `_render_violin`'s own
docstring for why). Reuses `_draw_categorical_axis_frame` unchanged.

RIDGELINE (the last of Phase 3) reuses `VIOLIN`'s own `_kde_bandwidth`/
`_kde_density`/`_KDE_SAMPLES` completely unchanged, but on `GANTT`'s
own horizontal categorical frame instead of the vertical one -- called
with `padding=0.0` (that function's own default is 0.2, right for
`GANTT`'s own separated floating bars but not this: rows need to sit
edge-to-edge so `_RIDGE_OVERLAP` alone controls overlap, not an
incidental padding gap -- see `_draw_horizontal_categorical_axis_
frame`'s own docstring for the bug this fixed): each category's own
curve rises upward from its own row's bottom edge (`_RIDGE_OVERLAP`
times the row's own height, deliberately more than one row tall, so a
tall peak overlaps into the row above -- the defining ridgeline look),
drawn top to bottom in `x_categories`' own given order so a lower
row's own curve sits on top of an upper row's wherever they overlap.
See ridgeline.mojo's own docstring for the full reasoning.

NIGHTINGALE ("Phase 4" of the broader chart-type survey, the polar-
axis family -- see the wiki) reuses `ARC`'s own `encode_categorical`
data shape, start-at-12-o'clock/sweep-clockwise convention, and value
validation, but gives every wedge the *same* angular width (`2*pi / N`)
instead of `ARC`'s value-proportional one -- a wedge's own magnitude is
encoded by its radius instead, scaled against the data's own largest
value (`Plot.mark_nightingale(area=...)`'s own `False`/`"radius"` mode
scales linearly; `True`/`"area"` mode scales by `sqrt(value / max)`
instead, so a wedge's own *area*, not just its radius, is proportional
to its value -- ECharts' own second `rose_type`). See nightingale.
mojo's own `_render_nightingale` docstring for the full reasoning.

POLAR_BAR reuses `NIGHTINGALE`'s own equal-angle-slot, radius-by-
`value/max` geometry, palette, legend, and validation, but carves a
small gap out of each bar's own angular slot (`_POLAR_BAR_PADDING`,
polar_bar.mojo -- the same "separated bands vs. edge-to-edge cells"
distinction `HEATMAP`'s own docstring already draws against `BAR`,
applied here against `NIGHTINGALE`'s own touching sectors) so bars
read as separated columns radiating from the center instead of pie-
like wedges. Always linear (`value/max`) -- no `NIGHTINGALE`-style
`rose_type="area"` equivalent; ECharts' own `polarbar` has no such
mode. See polar_bar.mojo's own `_render_polar_bar` docstring.

POLAR is the odd one out among the polar-axis family: not a
categorical mark at all, but the polar equivalent of `LINE` -- its own
new `encode_polar()` maps a continuous `angle` (radians, used exactly
as given, never wrapped `mod 2*pi` -- so a caller plotting angle
values past a full turn gets a real spiral, ECharts.jl's own "spiral"
example) and a continuous `radius` (linearly scaled from `[0,
max(radius)]`, always zero-anchored at the chart's own center) onto
one stroked polyline plus point markers, drawn over a new polar grid
(`_draw_polar_grid`, polar.mojo -- concentric rings via a real `Path.
arc_to` sweep, plus straight angular spokes). Its own shared `_polar_
point` (angle/radius -> pixel) is the one primitive `RADAR`/`GAUGE`
(below) both reuse too. See polar.mojo's own `_render_polar` docstring
for the full reasoning, including the deliberate v1 scope cuts (no
axis tick labels, single unlabeled series only).

RADAR is the polar-axis family's own categorical mark: one spoke per
named indicator (`encode_radar()`'s own `indicators`, each with its
own `max_values[i]` -- unlike `POLAR`'s single shared radius domain,
a radar chart's whole point is comparing differently-scaled
dimensions on one shared-looking grid), one closed, filled-and-
stroked polygon per named series (`series_names`/`series_values`).
Reuses `POLAR`'s own `_polar_point`, but its own grid (`_draw_radar_
grid`, radar.mojo) draws straight-edged polygon "web" rings, not
`POLAR`'s circles -- a radar's own axes are discrete, so there's no
meaningful position between two spokes for a circle to pass through.
See radar.mojo's own `_render_radar` docstring for the full reasoning.

GAUGE closes out Phase 4: a single `value` (`encode_gauge()`, clamped
to `[min_value, max_value]` rather than rejected out of range -- a
gauge's whole point is a live reading that can legitimately exceed
its expected range) shown as a needle over a 270-degree color-banded
dial (green/blue/red at ECharts' own default 20%/80%/100%
breakpoints, fixed constants for now -- see gauge.mojo's own
docstring). Reuses `POLAR`/`RADAR`'s own shared `_polar_point` for
both the needle tip and the band boundaries, `ARC`'s own `fill_ring_
sector_aa` primitive for the bands themselves. No axis frame, no
legend -- a single value has no categories to key one by. See
gauge.mojo's own `_render_gauge` docstring for the full reasoning.

PARALLEL ("Phase 5" of the broader chart-type survey, its own new
N-axis core) is a cartesian, not polar, multi-axis mark: `encode_
parallel()`'s own `dims` (one vertical axis per name, evenly spaced
left to right, each independently scaled to its own column's own
`[min, max]` -- unlike `RADAR`'s caller-supplied per-indicator max)
and `row_names`/`data` (one polyline per named row, one value per
dimension -- the same "outer list indexes named things" shape `RADAR`'s
own `series_values` already established). No axis tick labels beyond
each dimension's own name -- the same deliberate v1 simplification
`POLAR`'s own grid already documents. See parallel.mojo's own
`_render_parallel` docstring for the full reasoning.

SPAN_CHART (investigated during Phase 2, built later once the polar
family and Phase 5 were done) is `GANTT`'s own mirror image: the exact
same `encode_gantt()` data (category + start + end) completely
unchanged, but drawn as a floating *vertical* bar per category on the
normal `_draw_categorical_axis_frame` instead of `GANTT`'s own
horizontal one -- ECharts.jl's own `spanchart`, useful for a range
that isn't anchored to zero (confidence intervals, daily temperature
highs/lows). See span_chart.mojo's own `_render_span_chart` docstring
for the full reasoning.

CALENDAR_HEATMAP ("Phase 6" of the broader chart-type survey, the
grid/matrix family that extends `HEATMAP`'s own grid-cell idea) lays
`encode_calendar()`'s own `dates`/`values` out in a GitHub-
contributions-style calendar grid -- one column per week, one row per
day of the week, colored through the exact same continuous `ColorScale`
gradient `HEATMAP` already uses. Its own bespoke layout (calendar_
heatmap.mojo), not `_draw_grid_axis_frame` -- a calendar's row domain
is a fixed 7-day week and its column domain is a *computed* week
index, not two caller-given category domains. Includes a small, self-
contained proleptic-Gregorian date calculation (`_days_from_civil`/
`_day_of_week`, Howard Hinnant's well-known public-domain algorithm)
purely for grid placement -- not a general Date/Time type, which this
package deliberately still doesn't have (see `GANTT`'s own docstring).
See calendar_heatmap.mojo's own `_render_calendar_heatmap` docstring
for the full reasoning.

CORRPLOT (second of Phase 6) reuses `HEATMAP`'s own `_draw_grid_axis_
frame` directly -- unlike `HEATMAP`'s two independent category
domains, `encode_corrplot()`'s own `variables` list labels *both*
axes (a correlation matrix is always square). One bubble per
surviving cell, radius scaling with `abs(matrix[row][col])`, color
through `HEATMAP`'s own continuous gradient but spanning the fixed
`[-1.0, 1.0]` correlation domain, not a data-derived one. `Plot.
mark_corrplot(layout=..., diag=..., labels=...)` controls which
cells draw and whether each one's own value is labeled -- the same
lower/upper-triangle convention ECharts.jl's own `corrplot()` uses.
See corrplot.mojo's own `_render_corrplot` docstring for the full
reasoning.
"""


struct Mark(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime POINT = Self(0)
    comptime LINE = Self(1)
    comptime BAR = Self(2)
    comptime AREA = Self(3)
    comptime ARC = Self(4)
    comptime LOLLIPOP = Self(5)
    comptime WATERFALL = Self(6)
    comptime BOX = Self(7)
    comptime CANDLESTICK = Self(8)
    comptime BULLET = Self(9)
    comptime GANTT = Self(10)
    comptime GROUPED_BAR = Self(11)
    comptime STACKED_BAR = Self(12)
    comptime POPULATION_PYRAMID = Self(13)
    comptime HEATMAP = Self(14)
    comptime CHORD = Self(15)
    comptime SINGLE_AXIS = Self(16)
    comptime EFFECT_SCATTER = Self(17)
    comptime FUNNEL = Self(18)
    comptime BUMP = Self(19)
    comptime STREAMGRAPH = Self(20)
    comptime BEESWARM = Self(21)
    comptime VIOLIN = Self(22)
    comptime RIDGELINE = Self(23)
    comptime NIGHTINGALE = Self(24)
    comptime POLAR_BAR = Self(25)
    comptime POLAR = Self(26)
    comptime RADAR = Self(27)
    comptime GAUGE = Self(28)
    comptime PARALLEL = Self(29)
    comptime SPAN_CHART = Self(30)
    comptime CALENDAR_HEATMAP = Self(31)
    comptime CORRPLOT = Self(32)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
