"""The geometric primitive a data row becomes -- the grammar-of-
graphics `mark` concept. Follows the same small-struct-with-comptime-
constants-and-`__eq__` pattern canvas_mojo.FillRule/canvas_mojo.TextAlign
already established, not a distinct enum mechanism.

POINT (scatter) and LINE share continuous x/y encoding. LINE's
`Theme.line_smoothing` (default 0.0, plain straight segments)
optionally curves it through a Catmull-Rom-derived spline instead --
see that field's docstring and `plot.mojo`'s `_build_line_path`. BAR
has a categorical axis -- see ordinal_scale.mojo and
Plot.encode_categorical(). AREA shares LINE's continuous x/y encoding
but fills to a zero baseline the way BAR does. ARC (pie/donut wedges)
shares BAR's `encode_categorical` data shape (category + value) -- a
pie chart is the same underlying data as a bar chart, wrapped around a
circle instead of laid out linearly -- but has no x/y axis frame at
all, so it renders through its own, fully separate path (see
plot.mojo's `_render_arc`).

LOLLIPOP, WATERFALL, and BOX are three more categorical-x-axis marks
alongside BAR: LOLLIPOP reuses BAR's `encode_categorical` data shape
unchanged (a stem + point instead of a filled rect is purely a
rendering difference); WATERFALL has its `encode_waterfall` (a
category + a *signed delta*, not a plain value -- see that method's
docstring for the running-total bookkeeping this does, including its
optional `is_total` running-total-checkpoint rows, drawn full band
width in `Theme.waterfall_total_color` instead of a narrower
rising/falling delta bar); BOX has its `encode_boxplot` (a category
+ a whole *distribution* of raw values, not one number -- see that
method's docstring for the quartile/whisker/outlier computation it
does up front). All four share one axis-frame layout core (`_draw_
categorical_axis_frame`) -- see that function's docstring for why
sharing is the right call once several mark types need the identical
layout.

CANDLESTICK and BULLET share that same axis-frame core.
CANDLESTICK's `encode_candlestick` (a category plus four values --
open/high/low/close, not BAR's single value) draws a high-low wick
plus an open-close body per category, colored by whether the category
closed up or down -- see `_render_candlestick`'s docstring for the
drawing order and why it reuses `Theme.mark_color`/`mark_color_
negative` unconditionally rather than adding dedicated bullish/bearish
fields. BULLET's `encode_bullet` (a category plus a measure, a target,
and a whole *list* of qualitative-range thresholds -- the most values
any `encode_*` here takes) draws Stephen Few's bullet-chart composite:
shaded background range bands, a narrower measure bar, and a target
tick -- see `_render_bullet`'s docstring for the drawing order and
why, unlike CANDLESTICK/WATERFALL, its measure bar is never colored by
sign.

GANTT is the first mark whose categories run along a *horizontal* axis
instead of a vertical one -- a project-schedule/span chart, one
floating horizontal bar per category from a start value to an end
value (`encode_gantt`, deliberately no Date/Time type of its own --
see that method's docstring). Shares nothing structurally with
`_draw_categorical_axis_frame` (`x`/`y`'s roles are swapped throughout:
the continuous scale is now `x`, the categorical one now `y`) -- see
its mirror-image core, `_draw_horizontal_categorical_axis_frame`, and
its docstring for why this stayed a separate function rather than a
generalized, orientation-flagged version of the vertical one.

GROUPED_BAR is BAR generalized from one value per category to
*several* (`encode_grouped_bar`: categories, a name per series, and a
value per (series, category) pair) -- back on `_draw_categorical_axis_
frame`'s shared vertical axis-frame core (categories still run one
way, the same as BAR/LOLLIPOP/etc.), just subdividing each category's
band into one sub-bar per series instead of drawing a single bar
across the whole band. The one other new thing: a legend (series name
-> color), which no other categorical-x-axis mark needs -- see
`_render_grouped_bar`'s docstring for the palette/legend-reservation
details.

STACKED_BAR reuses `encode_grouped_bar`'s data shape completely
unchanged (`Plot.mark_stacked_bar().encode_grouped_bar(...)`, the same
call LOLLIPOP's reuse of BAR's `encode_categorical` establishes as a
precedent -- identical data, purely a rendering difference) -- each
category's series stack vertically instead of sitting side by side:
full band width per segment, one segment on top of the previous one's
running total instead of `GROUPED_BAR`'s divided sub-bars. See
`_render_stacked_bar`'s docstring for the mixed-sign running-total
bookkeeping (positive and negative values stack in their direction
from zero, independently) and why no extra pixel-boundary-rounding
trick is needed here the way `GROUPED_BAR`'s sub-bar division needs
one.

POPULATION_PYRAMID is `GANTT`'s horizontal categorical axis frame
(`_draw_horizontal_categorical_axis_frame`, reused unchanged) with two
magnitude bars per row instead of one start/end span:
`encode_population_pyramid`'s `left_values`/`right_values` each grow
outward from a shared, always-centered zero baseline instead of
floating between two arbitrary endpoints the way `GANTT`'s span does
-- see that method's docstring, and `_render_population_pyramid`'s for
the symmetric domain this forces (so equal magnitudes on each side
draw visually equal-length bars) and the two-color legend
(`left_name`/`right_name`), the one other new thing no other
horizontal mark needs.

HEATMAP is the first mark with *two* categorical axes and no
continuous one at all: `encode_heatmap`'s `x`/`y`/`value` (one row per
grid cell, `x`/`y` deduplicated into each axis's domain via
`_categorical_indices`, the same helper `Mark.POINT`'s categorical
color channel already uses) draws a filled cell per row, colored
through a continuous `ColorScale` spanning `value`'s [min, max] --
`Theme.color_scale_low`/`color_scale_high`, the exact gradient
`Mark.POINT`'s continuous `color=` channel already uses. Its own
`_draw_grid_axis_frame` (heatmap.mojo), not a generalization of either
existing categorical-axis core -- see that function's docstring for
why, and for the `padding=0.0` choice that makes cells tile
edge-to-edge instead of `Mark.BAR`'s separated bands.

CHORD (not "Arc Diagram" in the network-node-link-over-a-line sense, a
genuinely different chart type that happens to share a name with this
package's pre-existing `ARC`) is the first mark drawn from an *edge
list* (`encode_chord`'s `from_categories`/`to_categories`/`values`,
one row per flow) rather than one row per category. Its nodes reuse
`Mark.ARC`'s start-at-12-o'clock, sweep-clockwise ring-sector
convention (sized by each node's total flow, not one value), connected
by curved ribbons (`_draw_chord_ribbon`, chord.mojo -- a real
`Path.arc_to` for each rim, plus a `Path.quad_curve_to` pulled toward
the circle's center for each cross connection) drawn through
`DrawTarget.fill_path_aa`. See chord.mojo's docstrings for the
per-node running-angle bookkeeping (`_render_chord`) and the ribbon
geometry itself (`_draw_chord_ribbon`).

SINGLE_AXIS is the first mark with only *one* axis drawn at all:
`encode_single_axis`'s `x` (plus the usual optional `color`/`color_
categories`/`size` channels `Mark.POINT` already supports), one point
per row, all placed at a single fixed pixel row via a degenerate
zero-span `y_scale` -- reuses `Mark.POINT`'s `_draw_point_layer`
completely unchanged. Its one-axis frame, `_draw_single_axis_
frame` (single_axis.mojo).

EFFECT_SCATTER needs no new file, no new `encode_*` method, and no new
axis frame at all -- it's `Mark.POINT`'s continuous x/y encoding and
channels, unchanged, through the exact same `_draw_point_layer`, with
one flag flipped (`draw_halo=True`): a lighter, larger circle drawn
under each point first. A static stand-in for ECharts' real
effect-scatter behavior (an animated ripple around each point), which
a raster/SVG renderer with no animation concept has no way to
reproduce -- see `_draw_point_layer`'s `draw_halo` paragraph and
`_lighten`'s docstring (plot.mojo) for why this uses `Color.blend_over`
rather than real alpha transparency.

FUNNEL reuses `Mark.BAR`/`ARC`'s `encode_categorical` data shape
unchanged (category + value) -- like `ARC`, it has no axis frame at
all, drawing one trapezoid per category top to bottom, largest value
first (`_descending_value_order`, funnel.mojo -- ECharts' default
"highest to lowest" ordering, not the caller's row order every other
categorical mark here keeps), each row's bottom width equal to the
*next* row's top width for a continuous taper. See `_render_funnel`'s
docstring for the row-height/palette-by-display-position rules.

BUMP reuses `Mark.GROUPED_BAR`/`STACKED_BAR`'s `encode_grouped_bar`
data shape unchanged (categories, one name and one value per series)
-- but plots each series' *rank* at each category (1 = highest value
among every series there, via `_descending_value_order`, reused from
funnel.mojo -- one sort per category) instead of its raw value, as one
line per series (`Mark.LINE`'s `_build_line_path`, smoothing
included). Its hand-rolled rank axis, `_draw_bump_axis_frame`
(bump.mojo) -- see that function's docstring for why a real
`LinearScale` doesn't work for "rank 1 at the top."

STREAMGRAPH reuses `Mark.STACKED_BAR`'s running-total stacking over
`encode_grouped_bar`'s data, but each category's stack starts from
`-total_i / 2` instead of a shared zero (`_symmetric_zero_baseline_y_
extent`, streamgraph.mojo -- the same "forced symmetric" reasoning
`POPULATION_PYRAMID`'s x-domain helper already establishes, applied to
a per-category stacked total instead), so the whole picture floats
centered around zero -- the "silhouette" look -- and each series draws
as one flowing filled band across every category (straight `line_to`
between category centers, `DrawTarget.fill_path_aa`) instead of
`STACKED_BAR`'s discrete rects. Reuses `_draw_categorical_axis_frame`
unchanged.

BEESWARM has its `encode_distribution` (categories, one *list* of
raw values per category, kept unsummarized -- the same outer-list-
indexes-categories shape `encode_boxplot` already establishes, but
`Mark.BOX` immediately reduces each list to a five-number summary,
discarding the raw values; `VIOLIN`/`RIDGELINE` share this same encode
method, since both need the raw values too, for a density estimate).
One point per raw value, jittered sideways within its category's band
to avoid overlap (`_beeswarm_offsets`, beeswarm.mojo -- a
deterministic row-clustering swarm, not a full physics-style one; see
that function's docstring for why). Reuses `_draw_categorical_axis_
frame` unchanged, `_data_extent` (not zero-forced) over every value
across every category -- the same domain reasoning `Mark.BOX` already
gives for this same data shape.

VIOLIN reuses `BEESWARM`'s `encode_distribution` unchanged, drawing a
symmetric kernel-density-estimate silhouette per category instead of
individual jittered points -- Silverman's rule of thumb (std-only, a
deliberate simplification of the fuller IQR-adjusted version -- see
`_kde_bandwidth`'s docstring, violin.mojo) for the KDE's bandwidth by
default, or `mark_violin()`'s optional `bandwidth` applied identically
to every category instead (a real need: comparing several categories'
*shapes* without a wider- or narrower-spread category also reading as
smoother or spikier purely from Silverman's rule reacting to its
sample size), sampled at `_KDE_SAMPLES` points across each category's
`[min, max]`, each violin's peak density independently scaled to
`theme.violin_width_fraction` of its band width by default (ggplot2's
`scale = "width"`), or `mark_violin()`'s `scale_by_count=True` for
ggplot2's `scale = "area"` instead (multiplying that width by
`sqrt(n_i / max(n))`, so a category built from fewer raw values draws
visibly narrower). Reuses `_draw_categorical_axis_frame` unchanged.

RIDGELINE reuses `VIOLIN`'s `_kde_bandwidth`/`_kde_density`/
`_KDE_SAMPLES` completely unchanged (including its optional
`bandwidth`/`scale_by_count` overrides, `mark_ridgeline()`'s
parameters of the same names), but on `GANTT`'s horizontal categorical
frame instead of the vertical one -- called with `padding=0.0` (that
function's default is 0.2, right for `GANTT`'s separated floating bars
but not this: rows need to sit edge-to-edge so `theme.ridgeline_
overlap` alone controls overlap, not an incidental padding gap -- see
`_draw_horizontal_categorical_axis_frame`'s docstring): each
category's curve rises upward from its row's bottom edge (`theme.
ridgeline_overlap` times the row's height, deliberately more than one
row tall, so a tall peak overlaps into the row above -- the defining
ridgeline look), drawn top to bottom in `x_categories`' given order so
a lower row's curve sits on top of an upper row's wherever they
overlap. See ridgeline.mojo's docstring for the full reasoning.

NIGHTINGALE reuses `ARC`'s `encode_categorical` data shape,
start-at-12-o'clock/sweep-clockwise convention, and value validation,
but gives every wedge the *same* angular width (`2*pi / N`) instead of
`ARC`'s value-proportional one -- a wedge's magnitude is encoded by
its radius instead, scaled against the data's largest value
(`Plot.mark_nightingale(area=...)`'s `False`/`"radius"` mode scales
linearly; `True`/`"area"` mode scales by `sqrt(value / max)` instead,
so a wedge's *area*, not just its radius, is proportional to its value
-- ECharts' second `rose_type`). See nightingale.mojo's `_render_
nightingale` docstring for the full reasoning.

POLAR_BAR reuses `NIGHTINGALE`'s equal-angle-slot, radius-by-
`value/max` geometry, palette, legend, and validation, but carves a
small gap out of each bar's angular slot (`theme.polar_bar_padding`,
polar_bar.mojo -- the same "separated bands vs. edge-to-edge cells"
distinction `HEATMAP`'s docstring already draws against `BAR`, applied
here against `NIGHTINGALE`'s touching sectors) so bars read as
separated columns radiating from the center instead of pie-like
wedges. Always linear (`value/max`) -- no `NIGHTINGALE`-style
`rose_type="area"` equivalent; ECharts' `polarbar` has no such mode.
See polar_bar.mojo's `_render_polar_bar` docstring.

POLAR is the odd one out among the polar-axis family: not a
categorical mark at all, but the polar equivalent of `LINE` -- its
`encode_polar()` maps a continuous `angle` (radians, used exactly as
given, never wrapped `mod 2*pi` -- so a caller plotting angle values
past a full turn gets a real spiral, ECharts.jl's "spiral" example)
and a continuous `radius` (linearly scaled from `[0, max(radius)]`,
always zero-anchored at the chart's center) onto one stroked polyline
plus point markers, drawn over a polar grid (`_draw_polar_grid`,
polar.mojo -- concentric rings via a real `Path.arc_to` sweep, plus
straight angular spokes). Its shared `_polar_point` (angle/radius
-> pixel) is the one primitive `RADAR`/`GAUGE` (below) both reuse too.
`encode_polar()` maps one unnamed series; `encode_polar_series()`
maps several named series sharing one `angle` domain and one radius
scale, palette-colored with a legend -- `polar()`/`polar_series()`
mirror `pie()`/`donut()`'s "one mark, two quickplot entry points"
split. See polar.mojo's `_render_polar` docstring for the full
reasoning, including the one remaining scope limit: no axis tick
labels.

RADAR is the polar-axis family's categorical mark: one spoke per named
indicator (`encode_radar()`'s `indicators`, each with its
`max_values[i]` -- unlike `POLAR`'s single shared radius domain, a
radar chart's whole point is comparing differently-scaled dimensions
on one shared-looking grid), one closed, filled-and-stroked polygon
per named series (`series_names`/`series_values`). Reuses `POLAR`'s
`_polar_point`, but its grid (`_draw_radar_grid`, radar.mojo) draws
straight-edged polygon "web" rings, not `POLAR`'s circles -- a radar's
axes are discrete, so there's no meaningful position between two
spokes for a circle to pass through. See radar.mojo's `_render_radar`
docstring for the full reasoning.

GAUGE: a single `value` (`encode_gauge()`, clamped to `[min_value,
max_value]` rather than rejected out of range -- a gauge's whole point
is a live reading that can legitimately exceed its expected range)
shown as a needle over a 270-degree color-banded dial -- green/blue/
red at ECharts' default 20%/80%/100% breakpoints, or a caller's
`breakpoints`/`band_colors` (an ascending list of dial-span fractions
plus one color per band, same length; empty means "use the default",
the same sentinel convention `encode()`'s optional `color`/`size`
channels already use, see gauge.mojo's docstring). Reuses `POLAR`/
`RADAR`'s shared `_polar_point` for both the needle tip and the band
boundaries, `ARC`'s `fill_ring_sector_aa` primitive for the bands
themselves. No axis frame, no legend -- a single value has no
categories to key one by. See gauge.mojo's `_render_gauge` docstring
for the full reasoning.

PARALLEL is a cartesian, not polar, multi-axis mark: `encode_
parallel()`'s `dims` (one vertical axis per name, evenly spaced left
to right, each independently scaled to its column's `[min, max]`
-- unlike `RADAR`'s caller-supplied per-indicator max) and
`row_names`/`data` (one polyline per named row, one value per
dimension -- the same "outer list indexes named things" shape
`RADAR`'s `series_values` already establishes). No axis tick labels
beyond each dimension's name -- the same simplification `POLAR`'s grid
already carries. See parallel.mojo's `_render_parallel` docstring for
the full reasoning.

SPAN_CHART is `GANTT`'s mirror image: the exact same `encode_gantt()`
data (category + start + end) completely unchanged, but drawn as a
floating *vertical* bar per category on the normal `_draw_categorical_
axis_frame` instead of `GANTT`'s horizontal one -- ECharts.jl's
`spanchart`, useful for a range that isn't anchored to zero
(confidence intervals, daily temperature highs/lows). See span_chart.
mojo's `_render_span_chart` docstring for the full reasoning.

CALENDAR_HEATMAP extends `HEATMAP`'s grid-cell idea: lays
`encode_calendar()`'s `dates`/`values` out in a GitHub-contributions-
style calendar grid -- one column per week, one row per day of the
week, colored through the exact same continuous `ColorScale` gradient
`HEATMAP` already uses. Its bespoke layout (calendar_heatmap.mojo),
not `_draw_grid_axis_frame` -- a calendar's row domain is a fixed
7-day week and its column domain is a *computed* week index, not two
caller-given category domains. Includes a small, self-contained
proleptic-Gregorian date calculation (`_days_from_civil`/`_day_of_
week`, Howard Hinnant's well-known public-domain algorithm) purely for
grid placement -- not a general Date/Time type, which this package
deliberately doesn't have (see `GANTT`'s docstring). See calendar_
heatmap.mojo's `_render_calendar_heatmap` docstring for the full
reasoning.

CORRPLOT reuses `HEATMAP`'s `_draw_grid_axis_frame` directly --
unlike `HEATMAP`'s two independent category domains, `encode_
corrplot()`'s `variables` list labels *both* axes (a correlation
matrix is always square). One bubble per surviving cell, radius
scaling with `abs(matrix[row][col])`, color through `HEATMAP`'s
continuous gradient but spanning the fixed `[-1.0, 1.0]` correlation
domain, not a data-derived one. `Plot.mark_corrplot(layout=...,
diag=..., labels=...)` controls which cells draw and whether each
one's value is labeled -- the same lower/upper-triangle convention
ECharts.jl's `corrplot()` uses. See corrplot.mojo's `_render_corrplot`
docstring for the full reasoning.

PUNCHCARD reuses `HEATMAP`'s `_draw_grid_axis_frame` and `_categorical_
indices` domain derivation unchanged -- a "scatter plot on a
categorical grid" (ECharts.jl's description), one bubble per row
instead of `HEATMAP`'s filled cell, magnitude read from bubble *size*
(`sizes[i] / scale`, a plain pixel-space divisor, `Plot.
mark_punchcard(scale=10.0)`'s default) rather than color -- unlike
`CORRPLOT`'s cell-normalized bubble sizing, a punchcard's bubbles are
meant to visually overflow a small cell when the underlying count is
large. A repeated `(x, y)` pair draws its independent bubble
rather than merging, and there's no legend (no categorical color
channel to key one by). See punchcard.mojo's `_render_punchcard`
docstring for the full reasoning.

MARIMEKKO generalizes `STACKED_BAR`'s "one stacked column per
category" idea to two dimensions at once: `encode_marimekko()`'s
`categories` (columns) and `subcategories` (stacked segments) both
carry real proportions -- column *widths* are each category's share of
the grand total, and each column's segment *heights* are that
column's subcategory composition (a 0-100% stack), not
`STACKED_BAR`'s equal-width columns with a stacked absolute magnitude.
No shared `OrdinalScale` x-axis -- column positions come directly from
cumulative share-of-total math. Every rect boundary (column edges and
segment edges alike) rounds a *cumulative* continuous position rather
than an independently-rounded width/height, the same "round the
boundaries, not the size" pattern `STACKED_BAR`'s `_axis_pixel`-per-
running-total approach already uses, so adjacent columns/segments
never show a hairline gap. See marimekko.mojo's `_render_marimekko`
docstring for the full reasoning.

SUNBURST is built on the shared `_build_hierarchy_index`
(hierarchy.mojo) -- a `d3.stratify()`-style flattened tree
(`encode_hierarchy()`'s `ids`/`parent_ids`/`values`), the same "the
data already says what's needed" precedent `encode_chord()`'s edge
list already sets for graphs, generalized to trees. Drawn as
concentric `fill_ring_sector_aa` rings (`ARC`'s primitive, reused
directly) -- one ring per depth level, each node's angular span
proportional to its share of its parent's subtree total (not the
grand total the way `NIGHTINGALE`'s wedges are), so a sunburst is a
multi-level generalization of `NIGHTINGALE`'s single-level rose. Every
descendant of one of the root's direct children shares that child's
palette color, so one glance shows which top-level branch a deeply
nested ring segment belongs to. See sunburst.mojo's `_render_sunburst`
docstring for the full reasoning.

TREE reuses the exact same `_build_hierarchy_index`/`encode_
hierarchy()` data `SUNBURST` does, but as a classic top-to-bottom
node-link diagram instead of a radial one: `depth` picks each node's
row, `_assign_leaf_positions` (tree.mojo -- a deliberately simplified
layout, *not* a real Reingold-Tilford algorithm, see its docstring)
picks each node's column (every leaf gets the next sequential slot,
left to right; an internal node sits at the plain average of its
children's slots). The same "one color per top-level branch, shared by
every descendant" idea `SUNBURST` already establishes, computed once
up front here (`_assign_branch_colors`) rather than threaded through a
recursive draw call, since `TREE` draws every edge first, then every
node marker on top, two separate passes rather than one recursive one.
See tree.mojo's `_render_tree` docstring for the full reasoning.

TREEMAP reuses the same `encode_hierarchy()` data `SUNBURST`/`TREE`
do, laid out as nested, area-proportional rectangles via slice-and-
dice (`_draw_treemap_node`, treemap.mojo -- alternating split axis by
depth, each child's share of a split proportional to its
`subtree_value` share of its parent's total) -- a deliberately
simplified layout, not a real squarified algorithm (see that
function's docstring, the same "simpler, still genuinely correct"
tolerance `TREE`'s layout already takes). Every leaf draws filled and
labeled in white (the one mark in this package whose label sits *over*
a solid fill rather than the background); an internal node draws
nothing of its own, just partitions space for its children. The same
"one color per top-level branch" convention `SUNBURST`/`TREE` already
establish. See treemap.mojo's `_render_treemap` docstring for the full
reasoning.

ARC_DIAGRAM reuses `CHORD`'s `encode_chord()` edge-list data
completely unchanged (the same "identical data, purely a rendering
difference" precedent `STACKED_BAR`'s reuse of `GROUPED_BAR` already
establishes) -- not this package's pre-existing `ARC` (pie/donut
wedges), a genuinely different chart type that happens to share a
name, the same naming collision `CHORD`'s docstring already notes.
Every distinct node sits on one straight line instead of `CHORD`'s
circle, edges drawn as semicircular arcs bulging upward -- nodes far
apart get tall arcs, close nodes get shallow ones, not scaled to fit
any particular height. Edge stroke width scales with
`value/max(values)`; edge and node marker color both follow the
edge's `from` node's palette color, the same convention `CHORD`'s
ribbons already use. Every node is labeled directly beneath its
marker -- no legend, unlike `CHORD` (which needs one since its ring
sectors are often too thin to label directly). See arc_diagram.mojo's
`_render_arc_diagram` docstring for the full reasoning.

GRAPH reuses `CHORD`'s edge-list data too, a third genuinely different
network layout: nodes evenly spaced around a circle (`ARC`'s
start-at-12-o'clock convention, reused for position only), edges drawn
as straight lines cutting across the interior instead of `CHORD`'s
ring-sectors-plus-ribbons or `ARC_DIAGRAM`'s nodes-on-a-line-plus-arcs.
A deliberately simple, deterministic circular layout, not a real
force-directed simulation -- the same "not a full physics simulation"
scope choice `BEESWARM`'s docstring already makes for a completely
different layout problem, for the identical reason (this package's
test methodology needs exact, hand-verifiable positions). Labels align
by which side of center they fall on, the same rule `RADAR`'s axis
labels already use. See graph.mojo's `_render_graph` docstring for the
full reasoning.

SANKEY reuses `CHORD`'s edge-list data one more time, laid out
left-to-right by column -- a node's column is the length of the
*longest* path reaching it from any source, computed via one
Kahn's-algorithm topological pass (which also detects a cycle and
raises, since a real Sankey's flow data must be a DAG). Each node is a
thin bar, height proportional to `max(total inflow, total outflow)`;
nodes sharing a column stack via the same "round the cumulative
boundary" pattern `MARIMEKKO`/`TREEMAP` already establish. Each flow
draws as one or more filled quadrilaterals ("ribbon" segments) between
a slice of its `from` node's right edge and its `to` node's
left edge -- straight edges, not a smooth curve, the same "straight,
not curved" simplification `CHORD`'s straight-rim ribbons already are.
A "skip" edge (spanning more than one column) is spliced into a chain
through one invisible pass-through node per intermediate column --
each competing for that column's vertical space exactly like a real
node, so real nodes sharing the column get pushed to make room for it
instead of the flow just cutting straight through them (every segment
in one flow's chain still colors by that flow's original source,
not whichever pass-through node a given segment starts from). A
self-loop is dropped before layout entirely (no meaningful
column-distance to lay out). See sankey.mojo's `_render_sankey`
docstring for the full reasoning.

RADIALBAR reuses `POLAR_BAR`'s `encode_categorical` data shape and
always-linear-against-`max(values)` normalization unchanged, but is a
genuinely different geometry from it: one full concentric *ring* per
category, swept clockwise from 12 o'clock over a light-gray track,
instead of `POLAR_BAR`'s bars radiating outward from a shared center
-- the "multi-ring progress indicator" shape (Apple Watch's activity
rings, GitHub's contribution-ring widgets), not a circular column
chart. The first category's ring draws outermost, each later one
nesting further in -- display prominence, not `SUNBURST`'s
hierarchy-depth ordering (there's no hierarchy here). See radialbar.
mojo's `_render_radialbar` docstring for the full reasoning.
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
    comptime PUNCHCARD = Self(33)
    comptime MARIMEKKO = Self(34)
    comptime SUNBURST = Self(35)
    comptime TREE = Self(36)
    comptime TREEMAP = Self(37)
    comptime ARC_DIAGRAM = Self(38)
    comptime GRAPH = Self(39)
    comptime SANKEY = Self(40)
    comptime RADIALBAR = Self(41)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
