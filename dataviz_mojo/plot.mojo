"""Plot -- the [fluent](https://martinfowler.com/bliki/FluentInterface.html)
builder for this package's first vertical slice:
basic X-Y plots (scatter via Mark.POINT, line via Mark.LINE). Data is
plain columnar `List[Float64]`/`List[String]`, passed to `encode()`/
`encode_categorical()` directly -- a 1-D array is all any chart type
here needs; a named-column `Table` abstraction was built and then
removed (see the wiki's Changelog) once it turned out to add a second
way to do the same thing without a concrete need for named-column
lookup driving it.

Builder methods consume and return `Self` (`var self` -> `return
self^`) so calls chain: `Plot().mark_point().encode(x=xs,
y=ys).theme(t)` -- matches `canvas`'s own Path/Canvas builder feel in
spirit, chained rather than one statement per call since that's the
composition style settled on for this package specifically.

`render(canvas, plot)`/`render_svg(svg, plot)` are the two entry
points that turn a Plot into pixels or into SVG markup -- both a
single batch pass, no retained scene graph and no reactive signals
(see dataviz-api-design for why: `canvas` itself has neither, so
there's nothing for either to attach to yet). By default each owns
the whole target it's given (fills the background, computes margins
from `Theme`, plus any extra margin `Plot.labels()`'s own chart/axis
titles need -- see `_apply_labels`'s own docstring) rather than
compositing into an existing drawing; their optional `ox0`/`oy0`/
`ox1`/`oy1` bounds narrow that to a sub-rectangle instead -- the
mechanism `render_facets()` (small multiples: a grid of independently
laid-out plots on one canvas) composes on top of, without `render()`
itself knowing facets exist.

Both entry points share one generic rendering core (`_render_generic`,
`_render_bar`, `_render_arc` -- each `[T: DrawTarget]`, see canvas/
draw_target.mojo's own docstring for what that trait is and why it
exists) for everything except *text*: `DrawTarget` deliberately has no
`draw_text` method (drawing real text needs `canvas_mojo.text`'s own
native FreeType/fontconfig glyph machinery for the raster path, or
SVG-specific markup for the vector one, and forcing either dependency
onto the other would defeat the point), so text is
collected as a `List[_TextRequest]` while the generic pass runs, then
`render()`/`render_svg()` each draw that list their own way once it
returns -- see `_TextRequest`'s own docstring.

Every raster draw call the generic core makes through `Canvas` is the
anti-aliased variant -- `fill_circle_aa` for points, `stroke_path_aa`
for lines, `draw_line_aa` for gridlines/axis lines/tick marks --
rather than reasoning per call site about whether AA is "worth it."
For the axis-aligned lines specifically this makes no visual
difference (a perfectly horizontal or vertical, integer-positioned
line has no diagonal stepping for AA to smooth away in the first place
-- confirmed directly against draw_line_aa's own coverage math, not
assumed), but there's no real cost to it either given how few short
lines these are, and one consistent default is simpler to reason about
than an exception that has to be re-justified every time someone reads
this file. `SvgCanvas` has no equivalent AA choice to make at all --
an SVG renderer handles that itself, at whatever resolution it's
displayed at (see the wiki's Changelog, its own entry for the concrete
problem that motivated adding it).

Per-primitive AA is one layer of that; whole-canvas supersampling is
the other, coarser one -- rendering everything above at several times
its final size, then shrinking back down (see `canvas_mojo.resize.
downsample`'s own docstring for the mechanism). `render()` itself
never does this on its own -- see its own docstring, and `_rendered`'s,
for exactly where it does and doesn't happen and why.

This file holds only what every mark shares: the `Plot` struct itself
(its methods can't be split across files -- a Mojo struct's own
methods all have to live with its definition -- so `encode_histogram(
)`/`encode_waterfall()` are thin wrappers that immediately delegate to
a free function living with the rest of that mark's own code, the same
way `encode_boxplot()` already delegated to `_box_stats()`), `_render_
generic`'s dispatch, and machinery genuinely shared by several marks
(`_draw_categorical_axis_frame`, legends, labels, scales, facets,
layers). Each mark with its own dedicated rendering -- everything but
`Mark.POINT`/`LINE`/`AREA`, which stay inline in `_render_generic`
itself as the plain-continuous-axis default case with no special axis
frame of their own to justify a file -- has exactly one file holding
its own `_render_*` plus whatever calculation is specific to it: bar.
mojo, lollipop.mojo, waterfall.mojo, box.mojo, candlestick.mojo,
bullet.mojo, gantt.mojo, grouped_bar.mojo, stacked_bar.mojo, arc.mojo,
histogram.mojo (the last has no `_render_histogram` of its own --
`encode_histogram()`'s binning feeds `Mark.BAR`'s own `_render_bar`
unchanged -- so it holds only the binning calculation). These import
`Plot`/the shared machinery back from this file, and this file imports
each mark's own `_render_*`/calculation function back from theirs --
a real circular import, which Mojo resolves fine within one package.

## The one-call convenience functions

Alongside its own rendering, each of those files also holds that
mark's own one-call convenience function -- `bar()` in bar.mojo,
`pie()` in arc.mojo, `waterfall()` in waterfall.mojo, and so on --
with `scatter()`/`line()`/`area()` here in this file, beside the
`Mark.POINT`/`LINE`/`AREA` rendering they wrap. One rule, no
exceptions: a mark's convenience function lives with that mark's own
code. (These were all one `quickplot.mojo` module before; see the
wiki's Changelog for the move.) Import them from the package itself --
`from dataviz_mojo import bar, scatter` -- not from the mark file
they happen to live in.

Each wraps `Plot`/`Theme`/`Canvas`/`render()` for the common case: a
single chart, one mark, sane defaults for everything that isn't the
data itself. Every one does exactly what `examples/bar.mojo`'s own
`main()` used to do by hand -- build a `Theme`, build a `Canvas` sized
to match, build a `Plot`, `encode*()` the data onto it, `render()`
into the canvas -- collapsed into one call (`_rendered()` below is the
shared tail all thirteen delegate that to).

Not a replacement for the fluent `Plot` builder -- facets, layering,
`color`/`size` encoding, and the SVG backend all still need `Plot`
built directly, the same way `examples/` already shows for each. They
sit *on top of* that builder, not instead of it: every one still ends
up calling `Plot`/`render()` itself, so dropping down to the full
builder later (a second series, a facet grid) is a rewrite of one
call, not a different mental model.

Named after the mark, not the `Plot.mark_*()` method each wraps
(`bar`, not `mark_bar`) -- they're meant to be the first thing a
caller reaches for, not a shorthand for people who already know the
builder's vocabulary. Each takes exactly the data shape its own
`encode*()` counterpart needs (a plain `(x, y)` pair for the
continuous marks, `(categories, values)` for the categorical ones,
and each mark-specific shape beyond that -- `waterfall()`'s `deltas`,
`box()`'s per-category value lists, `candlestick()`'s OHLC columns,
`bullet()`'s measure/target/ranges, `gantt()`'s start/end,
`grouped_bar()`/`stacked_bar()`'s per-series values), plus five
parameters shared across all of them:

- `theme`: a full `Theme`, for every knob these don't surface as
  their own parameter (colors beyond `mark_color`, margins, font
  sizes, gridlines, `line_smoothing`, ...) --
  `Theme(mark_color=SEAGREEN)` (see `dataviz_mojo.colors`'s own
  docstring for that constant and every other CSS-named one alongside
  it, or `Color(40, 130, 90)` directly) works exactly as it does
  building a `Plot` by hand; only how it's handed in differs (an
  argument here, instead of a chained `.theme(...)`).
- `width`/`height`: the returned `Canvas`'s pixel size, defaulting to
  640x420 -- the final size of the returned `Canvas`; see `_rendered`'s
  own docstring for the internal supersampling every one of these
  functions now bakes in before handing that `Canvas` back, invisibly
  to the caller.
- `title`/`x_title`/`y_title`: forwarded to `Plot.labels()` as-is.

Every one returns a `Canvas`, already rendered -- call
`.write_png(path)`/`.write_bmp(path)` (both `canvas_mojo.io`) on the
result. There's no SVG equivalent yet -- build a `Plot` and call
`render_svg()` into an `SvgCanvas` directly for that (see
`examples/scatter_svg.mojo`), same as for any mark these don't cover.
"""

from std.collections import Dict
from std.math import pi

from canvas_mojo.buffer import Canvas
from canvas_mojo.color import Color
from canvas_mojo.gradient import LinearGradient
from canvas_mojo.resize import downsample
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.text.render import draw_text, measure_text, TextAlign

from dataviz_mojo.color_scale import ColorScale, default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.ordinal_scale import OrdinalScale
from dataviz_mojo.scale import LinearScale, MinMax, _format_fixed, _min_max
from dataviz_mojo.theme import Theme

from dataviz_mojo.arc import _render_arc
from dataviz_mojo.bar import _render_bar
from dataviz_mojo.beeswarm import _render_beeswarm
from dataviz_mojo.violin import _render_violin
from dataviz_mojo.box import _box_stats, _render_box
from dataviz_mojo.bullet import _render_bullet
from dataviz_mojo.candlestick import _render_candlestick
from dataviz_mojo.gantt import _render_gantt
from dataviz_mojo.bump import _render_bump
from dataviz_mojo.chord import _render_chord
from dataviz_mojo.funnel import _render_funnel
from dataviz_mojo.grouped_bar import _render_grouped_bar
from dataviz_mojo.heatmap import _render_heatmap
from dataviz_mojo.histogram import _bin_histogram
from dataviz_mojo.lollipop import _render_lollipop
from dataviz_mojo.single_axis import _render_single_axis
from dataviz_mojo.population_pyramid import _render_population_pyramid
from dataviz_mojo.stacked_bar import _render_stacked_bar
from dataviz_mojo.streamgraph import _render_streamgraph
from dataviz_mojo.waterfall import _render_waterfall, _waterfall_running_totals

# Pixel length of an axis tick mark, and the gap between a tick mark
# and its label -- small, fixed layout constants rather than Theme
# fields, since nothing built so far has needed them configurable
# (Theme's own fields are all things a real chart visibly varies:
# colors, sizes, margins; these two are just spacing).
comptime _TICK_LENGTH = 5
comptime _LABEL_GAP = 4

# Minimum pixel width reserved on the right for a legend (when one is
# shown -- see Theme.show_legend) -- the actual reservation grows
# beyond this to fit a real legend's own widest label (see _dynamic_
# legend_width), the same "fixed value is a floor, not the whole
# story" relationship Theme.margin_left has to the dynamic left
# margin. Also the layout of each legend row (a small colored square,
# then a gap, then the category label). Fixed rather than a Theme
# field for the same reason _TICK_LENGTH/_LABEL_GAP are: nothing built
# so far has needed the row layout itself configurable.
comptime _LEGEND_WIDTH = 130
comptime _LEGEND_SWATCH_SIZE = 14
comptime _LEGEND_ROW_GAP = 8

# A continuous color legend's own gradient bar -- _LEGEND_SWATCH_SIZE
# wide (matching a categorical legend's own swatch width, for visual
# consistency between the two), _CONTINUOUS_LEGEND_BAR_HEIGHT tall.
# A real DrawTarget.fill_rect_gradient call now (canvas_mojo >=0.3.0)
# -- this used to be approximated as many thin solid-colored fill_rect
# strips, back when DrawTarget had no gradient-fill method at all; see
# _draw_continuous_color_legend's own docstring for how the real
# gradient is built from ColorScale's own stops.
comptime _CONTINUOUS_LEGEND_BAR_WIDTH = _LEGEND_SWATCH_SIZE
comptime _CONTINUOUS_LEGEND_BAR_HEIGHT = 100

# Small breathing-room buffer beyond a dynamically measured label's
# own width -- see _max_label_width/the dynamic left-margin
# computation in render()/_render_bar.
comptime _MARGIN_BUFFER = 8

# The fixed internal supersampling factor `_rendered()` renders every
# one-call convenience function's raster output at before shrinking it
# back down -- see that function's own docstring for the mechanism and
# why it lives only there, not in `render()` itself. Not a `Theme`
# field and not exposed as a parameter anywhere: unlike `Theme.scale`
# (a real, user-visible choice -- render genuinely larger, for a
# viewer that upscales), this one exists purely so quickplot's output
# doesn't look worse than it has to, which isn't a decision a caller
# should need to make or even know is happening. 3x was picked the
# same way every example here used to hardcode it -- clearly enough
# finer-grained to matter, not so large that a 640x420 chart's own
# scratch canvas becomes wasteful; not benchmarked against 2x/4x.
comptime _QUICKPLOT_SUPERSAMPLE = 3


struct _Scaled(Movable):
    """Every pixel-sized quantity render()/_render_bar/_render_arc/
    _draw_legend actually draw with, pre-multiplied by `theme.scale`
    once here -- the single place the "* theme.scale" formula lives,
    so it can't drift between the several render paths that each need
    it (see Theme.scale's own docstring for what this is for). Built
    fresh from a Theme at the top of each of those functions; cheap
    (a handful of Float64/Int multiplies), not cached anywhere.

    `scale` itself (the raw multiplier, not multiplied by anything --
    every other field here already *is* the scaled quantity) exists
    for the one place that needs the bare factor rather than something
    pre-multiplied by it: every axis line/gridline/tick mark
    (`draw_line_aa(..., theme.axis_color)`/`(..., theme.gridline_
    color)`) is drawn `width=sc.scale` pixels wide, not the
    library-wide implicit default of a flat 1.0 -- these are the one
    kind of stroke this package draws whose own width has no `Theme`
    field of its own to already be scaled by `_Scaled.__init__` above
    (unlike `line_width`, `point_radius`, ...), so without this they'd
    stay exactly 1 raw pixel wide at any `scale`, visibly thinner than
    everything else in a `scale=2.0` render, not "the same chart at
    higher density" the way `Theme.scale`'s own docstring promises.
    """

    var scale: Float64
    var font_size: Float64
    var point_radius: Float64
    var line_width: Float64
    var size_range_min: Float64
    var size_range_max: Float64
    var margin_left: Int
    var margin_right: Int
    var margin_top: Int
    var margin_bottom: Int
    var tick_length: Int
    var label_gap: Int
    var legend_width: Int
    var legend_swatch_size: Int
    var legend_row_gap: Int
    var margin_buffer: Int
    var title_font_size: Float64
    var axis_title_font_size: Float64
    var continuous_legend_bar_width: Int
    var continuous_legend_bar_height: Int

    def __init__(out self, theme: Theme):
        var s = theme.scale
        self.scale = s
        self.font_size = theme.font_size * s
        self.point_radius = theme.point_radius * s
        self.line_width = theme.line_width * s
        self.size_range_min = theme.size_range_min * s
        self.size_range_max = theme.size_range_max * s
        self.margin_left = Int(Float64(theme.margin_left) * s)
        self.margin_right = Int(Float64(theme.margin_right) * s)
        self.margin_top = Int(Float64(theme.margin_top) * s)
        self.margin_bottom = Int(Float64(theme.margin_bottom) * s)
        self.tick_length = Int(Float64(_TICK_LENGTH) * s)
        self.label_gap = Int(Float64(_LABEL_GAP) * s)
        self.legend_width = Int(Float64(_LEGEND_WIDTH) * s)
        self.legend_swatch_size = Int(Float64(_LEGEND_SWATCH_SIZE) * s)
        self.legend_row_gap = Int(Float64(_LEGEND_ROW_GAP) * s)
        self.margin_buffer = Int(Float64(_MARGIN_BUFFER) * s)
        self.title_font_size = theme.title_font_size * s
        self.axis_title_font_size = theme.axis_title_font_size * s
        self.continuous_legend_bar_width = Int(Float64(_CONTINUOUS_LEGEND_BAR_WIDTH) * s)
        self.continuous_legend_bar_height = Int(Float64(_CONTINUOUS_LEGEND_BAR_HEIGHT) * s)


struct Plot(Movable):
    var x_data: List[Float64]
    var y_data: List[Float64]
    var x_categories: List[String]
    var color_data: List[Float64]
    var color_categories: List[String]
    var size_data: List[Float64]
    # Mark.WATERFALL only -- the running-total bounds encode_waterfall()
    # computes from each category's own signed delta (y_data), see that
    # method's own docstring.
    var _waterfall_y0: List[Float64]
    var _waterfall_y1: List[Float64]
    # Mark.WATERFALL only -- which rows are running-total checkpoints
    # (drawn full-band-width in Theme.waterfall_total_color) rather than
    # rising/falling deltas. Empty means "no total rows" -- see
    # encode_waterfall()'s own docstring.
    var _waterfall_is_total: List[Bool]
    # Mark.BOX only -- the five-number summary encode_boxplot() computes
    # per category up front, plus every outlier tagged with which
    # category (by index into x_categories) it belongs to. See that
    # method's own docstring for the quartile/whisker/outlier math.
    var _box_q1: List[Float64]
    var _box_median: List[Float64]
    var _box_q3: List[Float64]
    var _box_low: List[Float64]
    var _box_high: List[Float64]
    var _box_outlier_cat: List[Int]
    var _box_outlier_value: List[Float64]
    # Mark.CANDLESTICK only -- one open/high/low/close value per
    # category, from encode_candlestick(). See that method's own
    # docstring.
    var _candle_open: List[Float64]
    var _candle_high: List[Float64]
    var _candle_low: List[Float64]
    var _candle_close: List[Float64]
    # Mark.BULLET only -- one measure/target pair, plus a whole list of
    # ascending qualitative-range thresholds, per category. See
    # encode_bullet()'s own docstring.
    var _bullet_measure: List[Float64]
    var _bullet_target: List[Float64]
    var _bullet_ranges: List[List[Float64]]
    # Mark.GANTT only -- one start/end span per category. See
    # encode_gantt()'s own docstring.
    var _gantt_start: List[Float64]
    var _gantt_end: List[Float64]
    # Mark.GROUPED_BAR only -- one name per series, one value per
    # (series, category) pair. See encode_grouped_bar()'s own docstring.
    var _grouped_bar_series_names: List[String]
    var _grouped_bar_values: List[List[Float64]]
    # Mark.POPULATION_PYRAMID only -- one magnitude per side per
    # category, plus each side's own legend name. See encode_
    # population_pyramid()'s own docstring.
    var _pyramid_left: List[Float64]
    var _pyramid_right: List[Float64]
    var _pyramid_left_name: String
    var _pyramid_right_name: String
    # Mark.HEATMAP only -- one (x category, y category, value) row per
    # grid cell. See encode_heatmap()'s own docstring.
    var _heatmap_x: List[String]
    var _heatmap_y: List[String]
    var _heatmap_value: List[Float64]
    # Mark.CHORD only -- one (from node, to node, value) flow per row.
    # See encode_chord()'s own docstring.
    var _chord_from: List[String]
    var _chord_to: List[String]
    var _chord_value: List[Float64]
    # Mark.BEESWARM/VIOLIN/RIDGELINE only -- one *list* of raw values
    # per category, kept unsummarized (unlike Mark.BOX's own encode_
    # boxplot, which reduces each category's own list to a five-number
    # summary immediately). See encode_distribution()'s own docstring.
    var _distribution_values: List[List[Float64]]
    # Chart/axis title text, set via .labels() -- see that method's own
    # docstring. Empty string means "not set", the same "absent means
    # absent" convention every other optional feature here follows.
    var _title: String
    var _x_title: String
    var _y_title: String
    var _mark: Mark
    var _theme: Theme

    def __init__(out self):
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self.x_categories = List[String]()
        self.color_data = List[Float64]()
        self.color_categories = List[String]()
        self.size_data = List[Float64]()
        self._waterfall_y0 = List[Float64]()
        self._waterfall_y1 = List[Float64]()
        self._waterfall_is_total = List[Bool]()
        self._box_q1 = List[Float64]()
        self._box_median = List[Float64]()
        self._box_q3 = List[Float64]()
        self._box_low = List[Float64]()
        self._box_high = List[Float64]()
        self._box_outlier_cat = List[Int]()
        self._box_outlier_value = List[Float64]()
        self._candle_open = List[Float64]()
        self._candle_high = List[Float64]()
        self._candle_low = List[Float64]()
        self._candle_close = List[Float64]()
        self._bullet_measure = List[Float64]()
        self._bullet_target = List[Float64]()
        self._bullet_ranges = List[List[Float64]]()
        self._gantt_start = List[Float64]()
        self._gantt_end = List[Float64]()
        self._grouped_bar_series_names = List[String]()
        self._grouped_bar_values = List[List[Float64]]()
        self._pyramid_left = List[Float64]()
        self._pyramid_right = List[Float64]()
        self._pyramid_left_name = ""
        self._pyramid_right_name = ""
        self._heatmap_x = List[String]()
        self._heatmap_y = List[String]()
        self._heatmap_value = List[Float64]()
        self._chord_from = List[String]()
        self._chord_to = List[String]()
        self._chord_value = List[Float64]()
        self._distribution_values = List[List[Float64]]()
        self._title = ""
        self._x_title = ""
        self._y_title = ""
        self._mark = Mark.POINT
        self._theme = Theme.default()

    def mark_point(var self) -> Self:
        """A scatter plot: one point per (x, y) pair."""
        self._mark = Mark.POINT
        return self^

    def mark_line(var self) -> Self:
        """A line plot: (x, y) pairs connected in data order (not
        sorted by x -- a caller plotting a time series or any other
        naturally-ordered data gets the order they gave, matching
        every grammar-of-graphics library's own behavior; sort the
        data yourself first if that's not the order you want drawn)."""
        self._mark = Mark.LINE
        return self^

    def mark_bar(var self) -> Self:
        """A bar chart: one bar per category, encoded via
        `encode_categorical()` rather than `encode()` -- a bar's
        x-axis is discrete categories, not continuous positions (see
        `encode_categorical()`'s own docstring)."""
        self._mark = Mark.BAR
        return self^

    def mark_area(var self) -> Self:
        """An area chart: the same continuous (x, y) pairs `mark_line()`
        draws as a stroked line, instead filled from each point down to
        a zero baseline (`encode()`, not `encode_categorical()` -- an
        area chart's x-axis is continuous, like a line chart's, not
        categorical like a bar chart's)."""
        self._mark = Mark.AREA
        return self^

    def mark_arc(var self) -> Self:
        """A pie chart: one wedge per category, its angular span
        proportional to its value -- encoded via `encode_categorical()`
        (the same category + value data shape `mark_bar()` uses; a pie
        chart is that same data wrapped around a circle instead of laid
        out linearly), not `encode()`. Every value must be non-negative,
        and at least one must be positive -- checked at render() time,
        the same "raise, don't silently misrepresent the data" stance
        `_zero_baseline_y_extent` takes for BAR/AREA's own baseline."""
        self._mark = Mark.ARC
        return self^

    def mark_lollipop(var self) -> Self:
        """A lollipop chart: one stem-plus-point per category, encoded
        via `encode_categorical()` -- exactly `mark_bar()`'s own data
        shape (a bar chart and a lollipop chart differ only in how each
        category's magnitude is drawn, a filled rect vs. a thin stem
        with a point at its end, not in what the underlying data
        means)."""
        self._mark = Mark.LOLLIPOP
        return self^

    def mark_waterfall(var self) -> Self:
        """A waterfall chart: one floating bar per category, each
        running from the previous bar's own cumulative total to the
        next -- encoded via `encode_waterfall()` (a category + a
        *signed delta*, not `encode_categorical()`'s plain value; see
        that method's own docstring)."""
        self._mark = Mark.WATERFALL
        return self^

    def mark_box(var self) -> Self:
        """A box plot: one box-and-whiskers per category, summarizing
        a whole distribution of raw values -- encoded via
        `encode_boxplot()` (a category + a *list* of values, not
        `encode_categorical()`'s single number per category; see that
        method's own docstring for the quartile/whisker/outlier
        computation it does immediately, not deferred to render()
        time)."""
        self._mark = Mark.BOX
        return self^

    def mark_candlestick(var self) -> Self:
        """A candlestick chart: one open/high/low/close bar per
        category (a trading period, typically), encoded via `encode_
        candlestick()` -- a category plus four values, not `encode_
        categorical()`'s single value (see that method's own
        docstring)."""
        self._mark = Mark.CANDLESTICK
        return self^

    def mark_bullet(var self) -> Self:
        """A bullet chart (Stephen Few's design): one measure-vs-target-
        against-qualitative-ranges composite per category, encoded via
        `encode_bullet()` -- a category plus a measure, a target, and a
        whole list of range thresholds, not `encode_categorical()`'s
        single value."""
        self._mark = Mark.BULLET
        return self^

    def mark_gantt(var self) -> Self:
        """A gantt/span chart: one horizontal bar per category, from a
        start value to an end value, encoded via `encode_gantt()` --
        the first mark whose categories run along the *y*-axis instead
        of the x-axis (see that method's own docstring)."""
        self._mark = Mark.GANTT
        return self^

    def mark_grouped_bar(var self) -> Self:
        """A grouped bar chart: several bars side by side per category,
        one per series, encoded via `encode_grouped_bar()` -- a category
        plus a name and a value *per series*, not `encode_categorical()`'s
        single value."""
        self._mark = Mark.GROUPED_BAR
        return self^

    def mark_stacked_bar(var self) -> Self:
        """A stacked bar chart: one bar per category, each series' own
        value stacked as a segment on top of the previous one's own
        running total, instead of `Mark.GROUPED_BAR`'s side-by-side
        sub-bars -- encoded via the exact same `encode_grouped_bar()`,
        no separate encode method needed (the data is identical; only
        the rendering differs, the same relationship `Mark.LOLLIPOP`
        already has to `Mark.BAR`'s own `encode_categorical()`)."""
        self._mark = Mark.STACKED_BAR
        return self^

    def mark_population_pyramid(var self) -> Self:
        """A population pyramid: two magnitude bars per category,
        growing outward left/right from a shared, always-centered zero
        baseline -- encoded via `encode_population_pyramid()`. `Mark.
        GANTT`'s own horizontal-categories-along-y layout, reused
        unchanged; only the bars themselves (two, mirrored, instead of
        one floating span) differ."""
        self._mark = Mark.POPULATION_PYRAMID
        return self^

    def mark_heatmap(var self) -> Self:
        """A heatmap: one colored grid cell per (x, y) category pair,
        encoded via `encode_heatmap()` -- two categorical axes and no
        continuous one at all, unlike every other mark here."""
        self._mark = Mark.HEATMAP
        return self^

    def mark_chord(var self) -> Self:
        """A chord diagram: ring sectors for every distinct node across
        an edge list's own `from`/`to` columns, connected by ribbons
        sized by each flow's own value -- encoded via `encode_chord()`.
        No x/y axis frame at all, the same as `Mark.ARC`, whose ring-
        sector conventions this reuses directly."""
        self._mark = Mark.CHORD
        return self^

    def mark_single_axis(var self) -> Self:
        """A single-axis chart: every value plotted along one
        horizontal axis, no y-axis at all -- encoded via `encode_
        single_axis()`. Supports the same optional `color`/`color_
        categories`/`size` channels `Mark.POINT` does."""
        self._mark = Mark.SINGLE_AXIS
        return self^

    def mark_effect_scatter(var self) -> Self:
        """A scatter plot with a halo drawn under each point -- the
        static equivalent of ECharts' own animated-ripple effect
        scatter (see `_draw_point_layer`'s own `draw_halo` paragraph in
        plot.mojo). Encoded exactly like `Mark.POINT`, via `encode()` --
        no dedicated `encode_*` method, same continuous `x`/`y` plus the
        same optional `color`/`color_categories`/`size` channels."""
        self._mark = Mark.EFFECT_SCATTER
        return self^

    def mark_funnel(var self) -> Self:
        """A funnel chart: one tapering trapezoid per category, largest
        value first, encoded via `encode_categorical()` -- the same
        category+value shape `mark_bar()`/`mark_arc()` use. No x/y axis
        frame at all, the same as `mark_arc()`."""
        self._mark = Mark.FUNNEL
        return self^

    def mark_bump(var self) -> Self:
        """A bump chart: one line per series tracking its own rank (1 =
        highest value) among every series at each category, not its raw
        value -- encoded via `encode_grouped_bar()`, the exact same data
        `mark_grouped_bar()`/`mark_stacked_bar()` use."""
        self._mark = Mark.BUMP
        return self^

    def mark_streamgraph(var self) -> Self:
        """A streamgraph: `mark_stacked_bar()`'s own running-total
        stack, floated centered around zero instead of sitting on a
        fixed baseline, drawn as flowing bands instead of discrete
        rects -- encoded via `encode_grouped_bar()`, the exact same
        data `mark_grouped_bar()`/`mark_stacked_bar()`/`mark_bump()`
        use."""
        self._mark = Mark.STREAMGRAPH
        return self^

    def mark_beeswarm(var self) -> Self:
        """A beeswarm plot: one point per raw value, jittered sideways
        within its own category's band to avoid overlap -- encoded via
        `encode_distribution()`, the same data `mark_violin()`/`mark_
        ridgeline()` will use."""
        self._mark = Mark.BEESWARM
        return self^

    def mark_violin(var self) -> Self:
        """A violin plot: a symmetric kernel-density-estimate
        silhouette per category -- encoded via `encode_distribution()`,
        the same data `mark_beeswarm()`/`mark_ridgeline()` use."""
        self._mark = Mark.VIOLIN
        return self^

    def encode(
        var self,
        x: List[Float64],
        y: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
    ) -> Self:
        """Map data columns onto channels. `x`/`y` are required;
        `color`/`color_categories`/`size` are optional data-driven
        channels -- when given, each must be the same length as `x`/`y`
        (checked at render() time, not here, for the same reason
        `x`/`y`'s own length match is: encode() itself has no way to
        raise partway through a fluent chain without breaking the
        chain for every caller who *did* pass matching lengths).
        Omitting all three (the default, empty lists) means "use
        Theme's flat `mark_color`/`point_radius`" -- the exact
        pre-existing behavior, unchanged, for every caller who doesn't
        need a data-driven channel.

        `color` (continuous, `List[Float64]`, mapped through a
        `ColorScale` spanning the column's own [min, max]) and
        `color_categories` (discrete, `List[String]`, mapped through
        `default_categorical_palette()` by each value's position among
        the column's *unique* values in first-seen order -- unlike
        `encode_categorical()`'s `x`, this one *is* deduplicated,
        since a color column is expected to repeat values across many
        rows, not name one category per row the way bar categories
        do) are mutually exclusive -- passing both raises at render()
        time, since there's no principled way to blend a continuous
        gradient and a discrete palette into one answer. `size` is
        continuous only; a "categorical size" doesn't have an
        equivalent meaning the way categorical color obviously does.

        Only `Mark.POINT` supports these three channels today -- see
        render()'s own check. A per-segment color/width gradient along
        a `Mark.LINE` is a real, fancier feature, not silently
        approximated by reusing the scatter-point machinery.

        For a categorical x-axis (`Mark.BAR`), use
        `encode_categorical()` instead -- this method's own `x`
        parameter is continuous `Float64` positions, not category
        labels.
        """
        self.x_data = x.copy()
        self.y_data = y.copy()
        self.x_categories = List[String]()
        self.color_data = color.copy()
        self.color_categories = color_categories.copy()
        self.size_data = size.copy()
        return self^

    def encode_categorical(var self, x: List[String], y: List[Float64]) -> Self:
        """Map a categorical x column and a continuous y column onto
        the x/y channels -- for `Mark.BAR`, whose x-axis is discrete
        category labels (mapped through `OrdinalScale`'s evenly spaced
        bands), not continuous positions the way `encode()`'s own `x`
        is.

        One bar per entry in `x`, in the order given -- `x` is treated
        as already being the axis's category order, not deduplicated
        or re-sorted; repeated categories (grouped/stacked bars) is a
        different, not-yet-built feature (see the wiki's Backlog), not
        silently merged.
        """
        self.x_categories = x.copy()
        self.x_data = List[Float64]()
        self.y_data = y.copy()
        return self^

    def encode_histogram(var self, data: List[Float64], bins: Int = 10) raises -> Self:
        """Bin `data` into `bins` equal-width intervals and map the
        result onto the same categorical x/continuous y shape
        `encode_categorical()` does (a bin's own range, formatted, as
        its category label; its count as the value) -- for `Mark.BAR`,
        the same as `encode_categorical()` itself; a histogram *is* a
        bar chart, just one whose categories are computed from
        continuous data instead of given directly. No `_render_
        histogram` of its own -- `Mark.BAR`'s own `_render_bar` (see
        bar.mojo) draws whatever this method produces unchanged.

        Unlike `encode()`'s own x/y length checks (deferred to
        render() time, see that method's own docstring for why), the
        binning itself has to happen right here to produce any x/y
        data at all, so this raises immediately on `data` that can't
        be binned meaningfully -- see `_bin_histogram()`'s own
        docstring (histogram.mojo) for the exact binning algorithm
        (half-open bins except the last, label formatting, ...) and
        every case it raises on.
        """
        var binned = _bin_histogram(data, bins)
        self.x_categories = binned.labels.copy()
        self.x_data = List[Float64]()
        self.y_data = binned.counts.copy()
        return self^

    def encode_waterfall(
        var self,
        categories: List[String],
        deltas: List[Float64],
        is_total: List[Bool] = List[Bool](),
    ) -> Self:
        """Map a category column and a *signed delta* column onto
        `Mark.WATERFALL`'s own floating-bar shape: `deltas[i]` is how
        much the running total changes at category `i`, not the bar's
        own absolute height the way `encode_categorical()`'s `y` is for
        `Mark.BAR` -- each bar is drawn from the running total *before*
        it (`y0`) to the running total *after* it (`y1`), computed
        right here (via `_waterfall_running_totals()`, waterfall.mojo)
        as a running cumulative sum starting from 0.0 (the conventional
        waterfall starting point), not deferred to render() time --
        there's no reason to recompute a running sum on every render
        when the deltas themselves don't change.

        `is_total` (default empty -- no row is a total, every row is a
        plain rising/falling delta, `Mark.WATERFALL`'s original and
        still-default behavior, unchanged) optionally marks specific
        rows as running-total *checkpoints* instead -- see `_waterfall_
        running_totals()`'s own docstring (waterfall.mojo) for exactly
        what that changes about how a row draws, and `examples/
        waterfall.mojo` for the conventional start-then-deltas-then-end
        shape it enables.

        Unlike `encode_histogram()`'s binning, this never needs to
        raise immediately: a running sum is well-defined for any
        (possibly empty) list of deltas, with no degenerate-span case
        the way binning has -- `categories`/`deltas` length matching is
        still checked, but deferred to render() time like `encode_
        categorical()`'s own x/y, for the same reason (see that
        method's own docstring). `is_total`, if non-empty, must also
        match `categories`' own length -- checked the same deferred way.

        `deltas` itself is kept as this Plot's own `y_data` (not just
        the derived `y0`/`y1` bounds) so `_render_waterfall` can still
        color each non-total bar by its own delta's sign -- see `Theme.
        mark_color_negative`'s own docstring; unlike `Mark.BAR`, a
        waterfall chart colors by sign unconditionally, not gated by
        `Theme.color_by_sign`, since that coloring *is* what a
        waterfall chart conventionally shows, not an opt-in extra. A
        total row's own `deltas[i]` is stored the same way but never
        read for coloring -- see `Theme.waterfall_total_color`'s own
        docstring for what colors a total bar instead.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = deltas.copy()
        self._waterfall_is_total = is_total.copy()
        var bars = _waterfall_running_totals(deltas, is_total)
        self._waterfall_y0 = bars.y0.copy()
        self._waterfall_y1 = bars.y1.copy()
        return self^

    def encode_boxplot(var self, categories: List[String], values: List[List[Float64]]) raises -> Self:
        """Map a category column and, per category, a *list* of raw
        values onto `Mark.BOX`'s own box-and-whiskers shape: unlike
        every other `encode_*` here, each category's own "y" isn't one
        number but a whole distribution, summarized immediately (not
        deferred to render() time) into a five-number summary --
        quartiles via linear interpolation (the same method `numpy.
        percentile`'s own default, `"linear"`, uses, so results match
        what a caller could independently verify) -- plus every
        outlier beyond the conventional 1.5*IQR fence, via `_box_stats()`
        (see its own docstring, box.mojo, for the exact algorithm).

        Raises immediately, the same "can't produce a coherent result
        at all, not merely a length mismatch" reasoning `encode_
        histogram()`'s own binning raises for: a mismatched `categories`/
        `values` length, or any category whose own value list is empty
        (quartiles are undefined for zero data points -- there's no
        sensible fallback the way an empty histogram bin's count-of-
        zero is).
        """
        if len(categories) != len(values):
            raise Error(
                "Plot.encode_boxplot(): categories and values must have"
                " the same length (got "
                + String(len(categories))
                + " and "
                + String(len(values))
                + ")"
            )

        var q1 = List[Float64]()
        var median = List[Float64]()
        var q3 = List[Float64]()
        var low = List[Float64]()
        var high = List[Float64]()
        var outlier_cat = List[Int]()
        var outlier_value = List[Float64]()

        for i in range(len(values)):
            if len(values[i]) == 0:
                raise Error(
                    "Plot.encode_boxplot(): category '"
                    + categories[i]
                    + "' has no values -- can't compute a box plot from"
                    " an empty distribution"
                )
            var stats = _box_stats(values[i])
            q1.append(stats.q1)
            median.append(stats.median)
            q3.append(stats.q3)
            low.append(stats.low)
            high.append(stats.high)
            for v in stats.outliers:
                outlier_cat.append(i)
                outlier_value.append(v)

        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._box_q1 = q1^
        self._box_median = median^
        self._box_q3 = q3^
        self._box_low = low^
        self._box_high = high^
        self._box_outlier_cat = outlier_cat^
        self._box_outlier_value = outlier_value^
        return self^

    def encode_candlestick(
        var self,
        categories: List[String],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) -> Self:
        """Map a category column and four continuous value columns
        (open/high/low/close, the conventional OHLC shape) onto `Mark.
        CANDLESTICK`'s own wick-plus-body shape -- a category plus
        *four* numbers, not `encode_categorical()`'s single value.

        Unlike `encode_boxplot()`/`encode_histogram()`, nothing here
        needs computing up front (no summary statistic, no binning --
        every value is drawn exactly as given), so length checking is
        deferred to render() time, the same as `encode_categorical()`/
        `encode_waterfall()` (see either's own docstring for why: this
        method has no way to raise partway through a fluent chain
        without breaking it for callers who *did* pass matching
        lengths).
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._candle_open = open.copy()
        self._candle_high = high.copy()
        self._candle_low = low.copy()
        self._candle_close = close.copy()
        return self^

    def encode_bullet(
        var self,
        categories: List[String],
        measures: List[Float64],
        targets: List[Float64],
        ranges: List[List[Float64]],
    ) -> Self:
        """Map a category column plus three more columns onto `Mark.
        BULLET`'s own composite shape: `measures` (the actual value,
        drawn as a narrower bar), `targets` (a comparison value, drawn
        as a tick mark), and `ranges` (per category, an ascending list
        of qualitative-range thresholds -- e.g. `[50.0, 75.0, 100.0]`
        for a conventional poor/satisfactory/good split -- drawn as
        shaded background bands from 0 up to each threshold in turn).

        Like `encode_candlestick()`, nothing here needs computing up
        front (every value is drawn exactly as given), so length
        checking -- `categories`/`measures`/`targets`/`ranges` all the
        same length, and each category's own `ranges` entry non-empty
        and non-decreasing (the band-stacking math in `_render_bullet`
        depends on that order) -- is deferred to `render()` time, the
        same as every other categorical `encode_*` here (see `encode_
        categorical()`'s own docstring for why).
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._bullet_measure = measures.copy()
        self._bullet_target = targets.copy()
        self._bullet_ranges = ranges.copy()
        return self^

    def encode_gantt(var self, categories: List[String], start: List[Float64], end: List[Float64]) -> Self:
        """Map a category column and two continuous value columns
        (`start`/`end`) onto `Mark.GANTT`'s own horizontal-span shape --
        a category plus a range, not `encode_categorical()`'s single
        value. Deliberately plain `Float64`, the same as every other
        `encode_*` here, not a dedicated date/time type -- this whole
        package has no `Date`/`Time` type anywhere (see dataviz-api-
        design's own "plain columnar arrays are the whole data model"
        decision), so a project schedule's own dates are just numbers
        here (day-of-year, a Unix timestamp, whatever a caller's own
        data already uses) the same way every other numeric column in
        this package is -- which is also exactly why this mark doubles
        as a generic "span chart" for any numeric start/end range per
        category, not something scheduling-specific.

        Like `encode_candlestick()`, nothing needs computing up front,
        so length checking (`categories`/`start`/`end` all the same
        length) is deferred to `render()` time, the same as every other
        categorical `encode_*` here. `start[i] > end[i]` isn't checked
        or rejected either -- `_render_gantt` draws from `min(start[i],
        end[i])` to `max(...)`, the same "use min/max rather than
        assume an order" tolerance `Mark.CANDLESTICK`'s own open/close
        handling already has, so a reversed pair still renders
        sensibly rather than raising over what's likely just a data
        convention difference, not an error.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._gantt_start = start.copy()
        self._gantt_end = end.copy()
        return self^

    def encode_grouped_bar(
        var self,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
    ) -> Self:
        """Map a category column plus *several* value series onto
        `Mark.GROUPED_BAR`'s own side-by-side-bars-per-category shape --
        `values[j]` is series `series_names[j]`'s own value for every
        category (so `values[j][i]` is series `j`'s value for `categories
        [i]`), the same "outer list indexes the thing being repeated,
        inner list indexes categories" shape `encode_boxplot()` already
        established for a *distribution* per category -- here it's a
        *series* per category instead.

        Nothing needs computing up front, so length checking (`series_
        names`/`values` the same length, and every `values[j]` the same
        length as `categories`) is deferred to `render()` time, the same
        as every other categorical `encode_*` here.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._grouped_bar_series_names = series_names.copy()
        self._grouped_bar_values = values.copy()
        return self^

    def encode_population_pyramid(
        var self,
        categories: List[String],
        left_values: List[Float64],
        right_values: List[Float64],
        left_name: String = "",
        right_name: String = "",
    ) -> Self:
        """Map a category column plus two magnitude columns onto
        `Mark.POPULATION_PYRAMID`'s own mirrored-bars shape --
        `left_values[i]`/`right_values[i]` are each drawn as a bar
        growing outward from a shared, always-centered zero baseline
        for `categories[i]` (the classic age-band-by-sex layout, but
        generic: any two magnitudes worth comparing side by side per
        category). Both are read as non-negative magnitudes regardless
        of sign (`_render_population_pyramid` takes `max(v, -v)`, the
        same "use the shape that makes sense rather than raise over a
        likely data-convention difference" tolerance `Mark.GANTT`'s own
        `start > end` handling already has) -- a caller with genuinely
        signed data should decide which side each value belongs on
        before calling this, not rely on sign to pick a side here.

        `left_name`/`right_name` label the two-entry legend `_render_
        population_pyramid` draws when `Theme.show_legend` is on and at
        least one name is given -- empty strings (the default) fall
        back to "Left"/"Right" at render time rather than needing every
        caller who doesn't care about the legend to name both sides.

        Nothing needs computing up front, so length checking
        (`categories`/`left_values`/`right_values` all the same length)
        is deferred to `render()` time, the same as every other
        categorical `encode_*` here.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._pyramid_left = left_values.copy()
        self._pyramid_right = right_values.copy()
        self._pyramid_left_name = left_name
        self._pyramid_right_name = right_name
        return self^

    def encode_heatmap(var self, x: List[String], y: List[String], value: List[Float64]) -> Self:
        """Map two category columns plus a continuous value column onto
        `Mark.HEATMAP`'s own grid-cell shape -- one row per cell (`x[i]`,
        `y[i]`, `value[i]`), not a separate axis-category list: each
        axis's own domain is derived from `x`/`y` themselves (their
        distinct values in first-seen order, via `_categorical_indices`
        at render() time -- the same helper `Plot.encode()`'s own
        `color_categories` channel already resolves its domain through),
        the same "the data already says what the axis needs" shape
        `encode_categorical()` established for a single categorical
        axis, generalized to two.

        A caller need not give every (x, y) combination -- a missing
        cell simply isn't drawn (see `_render_heatmap`'s own docstring
        for why that's not treated as an error or a zero).

        Nothing needs computing up front, so length checking (`x`/`y`/
        `value` all the same length) is deferred to `render()` time,
        the same as every other categorical `encode_*` here.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._heatmap_x = x.copy()
        self._heatmap_y = y.copy()
        self._heatmap_value = value.copy()
        return self^

    def encode_chord(
        var self, from_categories: List[String], to_categories: List[String], values: List[Float64]
    ) -> Self:
        """Map an edge list onto `Mark.CHORD`'s own ring-sectors-plus-
        ribbons shape: one row per flow (`from_categories[i]` to `to_
        categories[i]`, magnitude `values[i]`) -- every distinct name
        across *both* columns becomes one node (`_unique_categories`
        over the two concatenated at render() time, first-seen order,
        `from_categories` first), not a separate node list; the same
        "the data already says what's needed" shape `encode_heatmap()`'s
        own two-categorical-axis domain derivation already established,
        generalized from a grid to a graph.

        `values` must be non-negative (checked at render() time, along
        with the usual length match, the same as every other categorical
        `encode_*` here) -- a negative flow has no ribbon-width meaning,
        the same reasoning `encode_categorical()`'s own `Mark.ARC` path
        already gives for rejecting negative wedge values.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._chord_from = from_categories.copy()
        self._chord_to = to_categories.copy()
        self._chord_value = values.copy()
        return self^

    def encode_distribution(var self, categories: List[String], values: List[List[Float64]]) raises -> Self:
        """Map a category column and, per category, a *list* of raw
        values onto the shape `Mark.BEESWARM`/`VIOLIN`/`RIDGELINE` all
        share -- the same "outer list indexes categories, inner list is
        that category's own distribution" shape `encode_boxplot()`
        already established, but kept as the raw values themselves,
        not immediately reduced to a five-number summary the way `Mark.
        BOX` needs: a swarm plot draws every individual point, and a
        density estimate needs the raw values to estimate from, neither
        of which a quartile summary alone could reconstruct.

        Raises immediately (the same "can't produce a coherent result
        at all" reasoning `encode_boxplot()`'s own checks already give)
        on a `categories`/`values` length mismatch, or any category
        whose own value list is empty.
        """
        if len(categories) != len(values):
            raise Error(
                "Plot.encode_distribution(): categories and values must"
                " have the same length (got "
                + String(len(categories))
                + " and "
                + String(len(values))
                + ")"
            )
        for i in range(len(values)):
            if len(values[i]) == 0:
                raise Error(
                    "Plot.encode_distribution(): category '"
                    + categories[i]
                    + "' has no values -- can't draw a distribution for"
                    " an empty one"
                )
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._distribution_values = values.copy()
        return self^

    def encode_single_axis(
        var self,
        x: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
    ) -> Self:
        """Map one continuous column plus the usual optional `color`/
        `color_categories`/`size` channels onto `Mark.SINGLE_AXIS`'s own
        one-axis shape -- the same three optional channels `encode()`
        itself takes, just without a `y`. `y_data` is filled with one
        placeholder `0.0` per row (never read as a real value -- see
        `_render_single_axis`'s own docstring for why) purely so this
        mark can reuse `_validate_continuous_encoding`'s existing x/y-
        length-match check and `Mark.POINT`'s own `_draw_point_layer`
        unchanged, instead of duplicating either.
        """
        self.x_data = x.copy()
        self.x_categories = List[String]()
        self.y_data = List[Float64]()
        for _ in range(len(x)):
            self.y_data.append(0.0)
        self.color_data = color.copy()
        self.color_categories = color_categories.copy()
        self.size_data = size.copy()
        return self^

    def theme(var self, t: Theme) -> Self:
        self._theme = t
        return self^

    def labels(var self, title: String = "", x_title: String = "", y_title: String = "") -> Self:
        """Set the chart title and/or axis titles -- text captions, not
        data. Named `x_title`/`y_title`, not `x`/`y`, so a call site
        reading `.labels(x_title=..., y_title=...)` next to `.encode(x=
        ..., y=...)` never reads as if it's setting data columns; the
        two mean completely different things (a caption string vs. a
        `List[Float64]`) despite the visual similarity.

        Each of the three is independent and defaults to `""` (not
        set) -- call with only the ones actually wanted, e.g. `.labels
        (title="Quarterly Revenue")` alone, with no axis titles at all.
        `render()`/`render_svg()` reserve layout space for exactly the
        ones that are non-empty and no others (see their own docstring
        for the margin math) -- an unset title costs nothing, the same
        "absent means absent" rule this file's other optional features
        (`Theme.line_smoothing`, `donut_inner_radius_fraction`, etc.)
        already follow.

        `x_title`/`y_title` caption whatever's drawn along the bottom/
        left edge respectively -- which axis that actually *is*
        depends on the mark's own orientation (the continuous axis for
        `Mark.POINT`/`LINE`/`AREA`/`GANTT`'s own `x`; the categorical
        one for every vertical categorical mark's own `x`; `GANTT`'s
        own categorical `y` instead of a continuous one) -- `x_title`/
        `y_title` describe screen position, not "the continuous axis"
        specifically, so the same two names stay meaningful across
        every orientation without special-casing.

        `Mark.ARC` has no x/y axes at all (see `_render_arc`'s own
        docstring) -- `x_title`/`y_title` raise at render() time if set
        on an `Mark.ARC` plot (only `title` applies there), the same
        "raise on a setting that can't apply, don't silently drop it"
        rule `Plot.encode`'s own color/size-on-a-non-POINT-mark check
        already follows.
        """
        self._title = title
        self._x_title = x_title
        self._y_title = y_title
        return self^


def _unique_categories(data: List[String]) -> List[String]:
    """Every distinct value in `data`, in first-seen order -- the
    domain a categorical color palette indexes into. Deliberately not
    shared with `encode_categorical()`'s own `x_categories` (which is
    used as-given, no dedup -- see that method's own docstring): a
    color column is expected to repeat values across many rows (many
    points share a category), while a bar chart's `x` is one row per
    category already."""
    var result = List[String]()
    for v in data:
        var found = False
        for existing in result:
            if existing == v:
                found = True
                break
        if not found:
            result.append(v)
    return result^


def _index_of(data: List[String], value: String) -> Int:
    for i in range(len(data)):
        if data[i] == value:
            return i
    return -1


struct _CategoricalIndex(Movable):
    """`_categorical_indices`'s own result: a categorical column's
    `domain` (its distinct values in first-seen order, exactly what
    `_unique_categories` returns) *plus* `indices`, that domain's own
    position for every row of the original column -- `indices[i]` is
    where `data[i]` sits in `domain`, so a caller never has to search
    the domain by string equality again."""

    var domain: List[String]
    var indices: List[Int]

    def __init__(out self, var domain: List[String], var indices: List[Int]):
        self.domain = domain^
        self.indices = indices^


def _categorical_indices(data: List[String]) raises -> _CategoricalIndex:
    """A categorical column's domain and its per-row indices into that
    domain, resolved together in one pass through a `Dict` -- what
    `Mark.POINT`'s own categorical color channel actually needs (see
    `_PointChannels`, its only caller).

    Replaces a pair of nested-loop scans that were quadratic in the
    column's own distinct-value count: `_unique_categories` compared
    each row against every domain entry found so far, and then the
    per-point draw loop called `_index_of` -- another full domain scan
    -- once *per point*. For a scatter of `n` points over `k`
    categories that was O(n*k) twice over; hashing each row once makes
    it O(n) on average, and the draw loop a plain `indices[i]` lookup.

    `_unique_categories` itself stays (it's this module's own
    documented, separately tested first-seen-order helper, and the
    domain half of this function agrees with it exactly by
    construction) -- this just also keeps the answer to "and where did
    each row land," which every caller previously threw away and then
    recomputed the expensive way.

    First-seen order comes from `domain`'s own append order, not from
    the `Dict` (whose iteration order this never relies on) -- the same
    order `_unique_categories` guarantees, and the order a categorical
    palette is indexed in.
    """
    var seen = Dict[String, Int]()
    var domain = List[String]()
    var indices = List[Int](capacity=len(data))
    for v in data:
        if v in seen:
            indices.append(seen[v])
        else:
            var idx = len(domain)
            seen[v] = idx
            domain.append(v)
            indices.append(idx)
    return _CategoricalIndex(domain^, indices^)


def _axis_pixel(scale: LinearScale, value: Float64) -> Int:
    return _round_to_int(scale.to_pixel(value))


def _build_line_path(px: List[Float64], py: List[Float64], smoothing: Float64) raises -> Path:
    """The `Path` a `Mark.LINE` plot strokes through its own already-
    pixel-projected points -- also the curve `Mark.AREA` fills down to
    baseline from, since an area chart's own top edge is exactly a line
    chart's path (see the `Mark.AREA` branch's own comment in `_render_
    generic` for the two extra `line_to`s/`close()` that turn this
    function's returned open curve into a closed, fillable region).
    `smoothing == 0.0` (`Theme.line_smoothing`'s
    own default) builds it exactly as `Mark.LINE` always has, a plain
    `move_to` plus one `line_to` per remaining point, so the default
    case never touches curve math at all and stays byte-for-byte
    identical to every render from before this feature existed (see
    `Theme.line_smoothing`'s own docstring -- deliberately an explicit
    early branch, not a degenerate curve formula that happens to
    reduce to the same shape, since a flattened cubic Bezier samples
    its 16 fixed steps at *even parameter spacing*, not even *pixel*
    spacing, so even a geometrically-straight cubic can flatten into a
    visibly different set of intermediate points than a single
    `line_to` -- not worth the risk when a plain early branch is both
    simpler and provably identical).

    `smoothing > 0.0` builds one cubic Bezier segment between each
    consecutive pair of points via a Catmull-Rom-derived tangent at
    each endpoint -- the standard "uniform Catmull-Rom to Bezier"
    conversion (control point = endpoint +/- (next-point minus
    previous-point)/6): for interior point `i`, the tangent looks at
    both its neighbors (`px[i-1]`/`px[i+1]`), giving the curve the
    smooth (tangent-continuous) look through every point a "connect
    the dots with straight lines" path doesn't have; the first and
    last points clamp to a one-sided tangent (their one real neighbor
    stands in for the missing one on the other side), the conventional
    open-curve endpoint rule. `smoothing` scales the tangent length
    directly -- not a blend between two separately-computed control-
    point sets -- so `1.0` is the textbook Catmull-Rom curve, `0.5`
    bows exactly half as far from the straight path at the same point,
    and (though this case is handled by the early branch above instead,
    for the byte-identical-default reason already given) `0.0` would
    algebraically collapse the tangent term to zero and reduce to the
    same straight line anyway -- confirmed by direct hand derivation,
    not just claimed, in this function's own tests, so the two code
    paths are known to agree at the boundary even though only one of
    them actually runs there.

    Every control-point coordinate hand-derived via `python3` (both
    the plain tangent formula and, separately, a real cubic Bezier
    evaluated at `t=0.5` compared against the straight-line midpoint at
    the same `t`, confirming the curve visibly bows away from the
    straight path, not just that *some* curve command got emitted) --
    see `test_plot.mojo`'s own tests for both checks.
    """
    var path = Path()
    if len(px) == 0:
        return path^
    path.move_to(px[0], py[0])
    if smoothing <= 0.0:
        for i in range(1, len(px)):
            path.line_to(px[i], py[i])
        return path^

    var n = len(px)
    for i in range(n - 1):
        var prev = i - 1 if i > 0 else i
        var next2 = i + 2 if i + 2 < n else i + 1
        var t1x = (px[i + 1] - px[prev]) / 6.0 * smoothing
        var t1y = (py[i + 1] - py[prev]) / 6.0 * smoothing
        var t2x = (px[next2] - px[i]) / 6.0 * smoothing
        var t2y = (py[next2] - py[i]) / 6.0 * smoothing
        path.cubic_curve_to(px[i] + t1x, py[i] + t1y, px[i + 1] - t2x, py[i + 1] - t2y, px[i + 1], py[i + 1])
    return path^


def _max_label_width(labels: List[String], font_size: Float64) raises -> Float64:
    """The widest of `labels`' own rendered ink width at `font_size`
    -- what the left margin needs to fit the y-axis's own tick labels
    without clipping or crowding the axis line (see the dynamic-
    left-margin computation in render()/_render_bar, both of which
    call this on a scale's own `ticks().labels()` before that scale's
    pixel range -- and therefore the plot area's actual left edge --
    is finalized; a y-axis's tick *values*, and so their formatted
    label text, depend only on the data domain, never on the pixel
    range they'll eventually be drawn into, so measuring them this
    early is exact, not a guess to be corrected later).
    """
    var max_width = 0.0
    for label in labels:
        var m = measure_text(label, font_size)
        if m.width > max_width:
            max_width = m.width
    return max_width


def _dynamic_legend_width(labels: List[String], content_width: Int, sc: _Scaled) raises -> Int:
    """How wide a legend column actually needs to be to fit `labels`
    next to `content_width`-wide content (a swatch for `_draw_legend`'s
    own categorical rows; a gradient bar for `_draw_continuous_color_
    legend`; the widest possible circle for `_draw_continuous_size_
    legend` -- `content_width` generalizes over all three rather than
    this function assuming a swatch specifically) -- `content_width`,
    then `label_gap`, then the widest label's own rendered width
    (`_max_label_width`, the same measurement technique the dynamic
    left margin already uses for y-axis tick labels, just applied to
    legend labels instead), then `margin_buffer` breathing room --
    `max`'d against `sc.legend_width` (`Theme`'s own fixed 130px
    default, scaled) so no existing plot's own legend column ever gets
    *narrower* than it already was -- purely additive, only ever
    growing the column for labels wide enough to actually need it, the
    same "purely additive" contract every dynamic-margin computation in
    this file already follows. Every call site (`Mark.POINT`'s own
    categorical color/continuous color/continuous size legends,
    `Mark.GROUPED_BAR`/`STACKED_BAR`'s own series-name legend,
    `Mark.ARC`'s own category legend) has to know its own actual label
    list *before* finalizing `plot_x1`, the same "measure first, size
    the margin second" ordering the y-axis's own tick labels already
    require -- see each call site's own comment for where that
    reordering was needed.
    """
    return max(
        sc.legend_width,
        content_width + sc.label_gap + Int(_max_label_width(labels, sc.font_size)) + sc.margin_buffer,
    )


struct _TextRequest(Copyable, Movable):
    """One deferred `draw_text()` call -- collected while the generic,
    `DrawTarget`-bounded rendering pass runs, instead of drawn inline
    right away (see canvas_mojo/draw_target.mojo's own docstring for why
    `DrawTarget` itself has no `draw_text` method to call). `render()`/
    `render_svg()` each replay a returned list of these their own way
    -- `canvas_mojo.text.draw_text` for the former, `SvgCanvas.draw_text`
    for the latter -- once the shared generic pass that collected them
    returns; see either function's own body for exactly where.
    """

    var x: Int
    var y: Int
    var text: String
    var color: Color
    var size: Float64
    var align: TextAlign
    var rotation: Float64

    def __init__(
        out self,
        x: Int,
        y: Int,
        text: String,
        color: Color,
        size: Float64,
        align: TextAlign,
        rotation: Float64 = 0.0,
    ):
        self.x = x
        self.y = y
        self.text = text
        self.color = color
        self.size = size
        self.align = align
        self.rotation = rotation


def _draw_legend[T: DrawTarget](
    mut target: T,
    mut text_requests: List[_TextRequest],
    labels: List[String],
    palette: List[Color],
    x: Int,
    y: Int,
    theme: Theme,
) raises:
    """A simple swatch+label legend, one row per entry in `labels`,
    starting at (x, y) and growing downward -- the shared layout both
    `Mark.POINT`'s categorical color legend and `Mark.ARC`'s own
    legend use, since both reduce to "a list of category labels plus
    the palette that colored them" by the time they get here (see
    render()/`_render_arc` for how each computes that list). `palette`
    is indexed the same `i % len(palette)` way the actual points/
    wedges were colored, not `labels[i]`'s own index directly, so a
    legend row always shows the exact color that category actually
    got, cycling included.

    Computes its own `_Scaled(theme)` rather than taking one as a
    parameter -- keeps this function's own signature stable (still
    just `theme` in) and the "* theme.scale" formula in the one place
    `_Scaled` itself lives, at the cost of one extra (cheap) `_Scaled`
    construction per legend drawn. Each label's own text is appended
    to `text_requests` (a caller-owned, shared list -- see
    `_TextRequest`'s own docstring for why), not drawn directly; only
    the swatch itself is drawn here, through `target`.
    """
    var sc = _Scaled(theme)
    for i in range(len(labels)):
        var row_y = y + i * (sc.legend_swatch_size + sc.legend_row_gap)
        var color = palette[i % len(palette)]
        target.fill_rect(x, row_y, sc.legend_swatch_size, sc.legend_swatch_size, color)
        text_requests.append(
            _TextRequest(
                x + sc.legend_swatch_size + sc.label_gap,
                row_y + sc.legend_swatch_size - 3,
                labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
            )
        )


def _draw_continuous_color_legend[T: DrawTarget](
    mut target: T,
    mut text_requests: List[_TextRequest],
    color_scale: ColorScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """A continuous color legend: a real vertical gradient bar
    (`DrawTarget.fill_rect_gradient`, canvas_mojo >=0.3.0 -- see that
    method's own docstring; before it existed, this was approximated
    as many thin solid-colored `fill_rect` strips), `color_scale`'s
    own high value at the top, low at the bottom -- the same "more/
    bigger is up" convention a y-axis itself already uses. Two labels
    (`_format_fixed`, one decimal place, matching `encode_histogram()`'s
    own bin-label convention): the domain max at the bar's own top, the
    domain min at its own bottom.

    The `LinearGradient` is built directly from `color_scale`'s own
    `stops` (each already an `(offset, color)` pair over `color_scale`'s
    own `[domain_min, domain_max]`, `add_stop(0.0, ...)`/`add_stop(1.0,
    ...)` in every caller so far -- see `_PointChannels`'/`_render_
    heatmap`'s own construction), not re-derived from `color_at()`
    sampled at many points the way the old strip approximation had to:
    `color_scale`'s own offsets run low (0.0) to high (1.0), but the
    bar's own gradient axis runs top (`y`) to bottom (`y + bar_height`)
    -- top has to be the *high* value, so each stop's own gradient
    offset is `1.0 - stop.offset`, not `stop.offset` directly.

    Returns the y-coordinate just below this section (bar height plus
    one row gap) -- where `_draw_continuous_size_legend` starts if a
    plot combines continuous color *and* size (a real, existing case --
    see `examples/bubble.mojo`), so the two stack vertically in one
    legend column instead of overlapping.
    """
    var sc = _Scaled(theme)
    var bar_width = sc.continuous_legend_bar_width
    var bar_height = sc.continuous_legend_bar_height
    var gradient = LinearGradient(Float64(x), Float64(y), Float64(x), Float64(y + bar_height))
    for stop in color_scale.stops:
        gradient.add_stop(1.0 - stop.offset, stop.color)
    target.fill_rect_gradient(x, y, bar_width, bar_height, gradient)

    var label_baseline_offset = Int(sc.font_size * 0.35)
    text_requests.append(
        _TextRequest(
            x + bar_width + sc.label_gap,
            y + label_baseline_offset,
            _format_fixed(color_scale.domain_max, 1),
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
        )
    )
    text_requests.append(
        _TextRequest(
            x + bar_width + sc.label_gap,
            y + bar_height + label_baseline_offset,
            _format_fixed(color_scale.domain_min, 1),
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
        )
    )
    return y + bar_height + sc.legend_row_gap


def _draw_continuous_size_legend[T: DrawTarget](
    mut target: T,
    mut text_requests: List[_TextRequest],
    size_mm: MinMax,
    size_scale: LinearScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """A continuous size legend: three representative circles (max,
    midpoint, min of the actual data's own size domain -- not evenly
    spaced *radii*, evenly spaced *values*, so the legend shows real
    data points a caller could look up, the same reason a y-axis's own
    "nice" ticks are picked from the data domain rather than the pixel
    range) at `size_scale`'s own radius for each, the identical scale
    real data points are sized with. Circles left-aligned on their own
    *widest* possible edge (`x + sc.size_range_max`, `Theme`'s own
    configured largest radius, not this particular plot's own largest
    circle) so every circle's own label lines up at the same x
    regardless of which circle is biggest -- confirmed directly (not
    assumed) that this reads better than centering each circle
    independently, which would stagger the labels.

    Returns the y-coordinate just below the last circle (plus one row
    gap) -- unused today (this is always the last legend section drawn
    in `_render_generic`'s own current stacking order) but returned for
    the same reason `_draw_continuous_color_legend` does: consistency,
    and so a third section could stack after this one someday without
    this function's own signature needing to change.
    """
    var sc = _Scaled(theme)
    var values = List[Float64]()
    values.append(size_mm.max)
    values.append((size_mm.min + size_mm.max) / 2.0)
    values.append(size_mm.min)

    var label_baseline_offset = Int(sc.font_size * 0.35)
    var cx = x + _round_to_int(sc.size_range_max)
    var top_y = y
    for v in values:
        var radius = _round_to_int(size_scale.to_pixel(v))
        var center_y = top_y + radius
        target.fill_circle_aa(cx, center_y, radius, theme.mark_color)
        text_requests.append(
            _TextRequest(
                cx + radius + sc.label_gap,
                center_y + label_baseline_offset,
                _format_fixed(v, 1),
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
            )
        )
        top_y = center_y + radius + sc.legend_row_gap
    return top_y


def _data_extent(data: List[Float64]) raises -> LinearScale:
    """The [min, max] of `data` (via scale.mojo's shared `_min_max`),
    padded 5% on each side for visual breathing room (points/lines
    exactly on the plot edge would otherwise look clipped) -- returned
    as a LinearScale whose range is a placeholder [0, 1]; render()
    overwrites the range once it knows the actual plot area in pixels.
    A zero-span column (every value identical) gets a fixed 1.0
    padding instead of 5% of a zero span, the same degenerate case
    LinearScale.ticks() itself documents handling separately.

    Spatial axes (x/y) only -- color/size domains use `_min_max`
    directly, unpadded: a legend's extremes should mean exactly the
    data's own extremes, not a padded approximation of them (see
    MinMax's own docstring).
    """
    var mm = _min_max(data)
    var span = mm.max - mm.min
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(mm.min - pad, mm.max + pad, 0.0, 1.0)


def _zero_baseline_y_extent(data: List[Float64]) raises -> LinearScale:
    """The y-domain for any mark whose fill/height encodes magnitude
    from a baseline (`Mark.BAR`, `Mark.AREA`) -- always includes a
    zero baseline, not optional the way `_data_extent`'s padding is:
    an axis that doesn't start at zero would visually misrepresent
    every bar's height or every area's fill relative to the others
    (arguably the single most common real charting-correctness
    mistake; this function exists specifically so those marks can't
    get it wrong by construction, not leave it to the caller to
    remember). Unlike `_data_extent`'s symmetric 5% pad (there, purely
    visual breathing room), this pads only the end that isn't already
    zero -- zero itself is always an exact axis endpoint whenever
    every value sits on one side of it, never "close to" one.
    """
    var mm = _min_max(data)
    var lo = min(0.0, mm.min)
    var hi = max(0.0, mm.max)
    var span = hi - lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    var padded_lo = lo - pad if lo < 0.0 else lo
    var padded_hi = hi + pad if hi > 0.0 else hi
    return LinearScale(padded_lo, padded_hi, 0.0, 1.0)


struct _LabelsFrame(Movable):
    """`_apply_labels`'s own finished result: the outer rect `render()`/
    `render_svg()` actually hand to `_render_generic` (shrunk to make
    room for `Plot.labels()`'s own title/x_title/y_title -- see that
    method's own docstring). Just the shrunk rect -- unlike its own
    original version, `_apply_labels` no longer builds the title
    `_TextRequest`s here; see its own docstring for why that moved to
    `_label_text_requests`, called *after* rendering instead. A named
    struct even though only `render()`/`render_svg()` call
    `_apply_labels` -- this file's own established convention
    (`_CategoricalFrame`, `MinMax`, `Ticks`, ...) is always a named
    struct for a multi-value return, never a raw tuple."""

    var ox0: Int
    var oy0: Int
    var ox1: Int
    var oy1: Int

    def __init__(out self, ox0: Int, oy0: Int, ox1: Int, oy1: Int):
        self.ox0 = ox0
        self.oy0 = oy0
        self.ox1 = ox1
        self.oy1 = oy1


struct _RenderResult(Movable):
    """Every `_render_*` function's actual return value: the axis/tick/
    legend `_TextRequest`s it always returned (see `_render_generic`'s
    own docstring for why text is collected, not drawn directly), plus
    the *inner* plot rect it actually laid the mark out in (`px0`/`py0`/
    `px1`/`py1` -- dynamic left margin, optional legend column, all
    already resolved). That second part exists for exactly one
    consumer, `_label_text_requests` (see its own docstring): `Plot.
    labels()`'s title/x_title/y_title center on this rect rather than
    the full outer bounds `render()`/`render_svg()` were called with,
    so a wide legend or long y-axis tick labels shifting the real data
    area off-center doesn't throw a title's own centering off with it.
    A named struct, not a raw tuple -- this file's own established
    convention for every multi-value return.

    When a `_render_*` function returns before any layout has actually
    happened (no data to draw -- see e.g. `_render_bar`'s own early
    `len(plot.x_categories) == 0` check), `px0`..`py1` fall back to the
    full outer bounds it was given: there's no narrower rect to report,
    and the outer bounds are exactly what `_label_text_requests` would
    otherwise center on anyway -- that case is `_empty_result` below."""

    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self, var text_requests: List[_TextRequest], px0: Int, py0: Int, px1: Int, py1: Int
    ):
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1


def _empty_result(ox0: Int, oy0: Int, ox1: Int, oy1: Int) -> _RenderResult:
    """The `_RenderResult` every `_render_*` function returns when it
    has nothing to draw (no categories, no points) -- no text requests,
    and the full outer bounds as the inner rect, for the reason
    `_RenderResult`'s own docstring gives. One helper rather than the
    same three lines (`var text_requests = List[_TextRequest]()`, the
    length check, the constructor call) opening all eleven of them.
    """
    return _RenderResult(List[_TextRequest](), ox0, oy0, ox1, oy1)


def _apply_labels(plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _LabelsFrame:
    """Reserves margin space for `Plot.labels()`'s own chart/axis
    titles, given the *original* outer bounds `render()`/`render_svg()`
    were called with. Called once, by those two functions only, *before*
    handing off to `_render_generic` -- not threaded through
    `_render_generic`, `_draw_categorical_axis_frame`, `_draw_
    horizontal_categorical_axis_frame`, or any mark-specific `_render_*`
    function, all of which stay completely unaware titles exist. This
    is deliberate, the same "a little duplication/a small wrapper over
    threading a flag through many functions" reasoning `_render_bar`'s
    own docstring already established -- titles are pure outer-rect
    geometry (how much smaller a rectangle to hand downstream), so
    shrinking that rectangle *before* any mark-specific layout runs
    gets the same effect as threading title state through every one of
    those functions, for a small fraction of the surface area touched.

    Only reserves margin here -- doesn't build the title `_TextRequest`s
    themselves, unlike its own original version. A title/x_title's own
    along-axis position (how far from the very top/bottom edge) only
    ever depends on this margin reservation, known immediately; but its
    cross-axis position (centered *where*, horizontally for title/
    x_title, vertically for y_title) should track the real inner plot
    rect -- dynamic left margin, optional legend column -- which isn't
    known until `_render_generic` (or whichever `_render_*` it
    dispatches to) actually runs and returns it (`_RenderResult`'s own
    `px0`..`py1`, see its docstring). Splitting into two phases this
    way -- reserve margin before rendering, center text after -- is what
    makes a title/x_title land pixel-precisely over the inner plot rect
    instead of the full outer width/height (a wide legend or long
    y-axis tick labels no longer throws it off-center the way it used
    to -- see the wiki's Changelog, its own "Plot.labels() precise
    centering" entry for the full before/after). `_label_text_
    requests`, called by `render()`/`render_svg()` right after
    `_render_generic` returns, is phase two.

    `Mark.ARC` has no x/y axes at all (`_render_arc`'s own docstring),
    so `x_title`/`y_title` raise here if set on an `Mark.ARC` plot --
    unlike `title` (which centers over the outer width regardless of
    mark type, and works fine for `ARC` too -- a pie chart can
    absolutely have a heading), there's no sensible "axis" to caption.
    """
    if (plot._x_title.byte_length() > 0 or plot._y_title.byte_length() > 0) and plot._mark == Mark.ARC:
        raise Error(
            "Plot.labels(): x_title/y_title don't apply to Mark.ARC (it"
            " has no x/y axes to caption) -- only title applies to a"
            " pie/donut chart"
        )

    var sc = _Scaled(plot._theme)
    var extra_top = Int(sc.title_font_size) + sc.label_gap if plot._title.byte_length() > 0 else 0
    var extra_bottom = (
        Int(sc.axis_title_font_size) + sc.label_gap if plot._x_title.byte_length() > 0 else 0
    )
    var extra_left = (
        Int(sc.axis_title_font_size) + sc.label_gap if plot._y_title.byte_length() > 0 else 0
    )

    return _LabelsFrame(ox0 + extra_left, oy0 + extra_top, ox1, oy1 - extra_bottom)


def _label_text_requests(
    plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int, px0: Int, py0: Int, px1: Int, py1: Int
) raises -> List[_TextRequest]:
    """Builds `Plot.labels()`'s own title/x_title/y_title `_TextRequest`s
    -- called by `render()`/`render_svg()` *after* `_render_generic`
    returns, unlike `_apply_labels` (phase one, see its own docstring),
    which only reserves the margin these titles sit in, before
    rendering. Takes both rects: the *original* outer bounds (`ox0`..
    `oy1`, `render()`/`render_svg()` were called with -- each title's
    own along-axis position, how far from the very top/bottom/left
    edge, is always relative to this one, unaffected by legend width)
    and the *actual* inner plot rect `_render_generic` (or whichever
    `_render_*` it dispatched to) laid the mark out in (`px0`..`py1`,
    `_RenderResult`'s own fields -- each title's own cross-axis
    position, centered *where*, uses this one instead: horizontal
    center for title/x_title, vertical center for y_title).
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var text_requests = List[_TextRequest]()

    if plot._title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy0 + Int(sc.title_font_size * 0.8),
                plot._title,
                theme.text_color,
                sc.title_font_size,
                TextAlign.CENTER,
            )
        )

    if plot._x_title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy1 - Int(sc.axis_title_font_size * 0.25),
                plot._x_title,
                theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
            )
        )

    if plot._y_title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                ox0 + Int(sc.axis_title_font_size * 0.8),
                (py0 + py1) // 2,
                plot._y_title,
                theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                rotation=-pi / 2.0,
            )
        )

    return text_requests^


def render(
    mut canvas: Canvas, plot: Plot, ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1
) raises:
    """Render `plot` into `canvas` -- fills its own outer bounds
    (background, then gridlines, axes, tick labels, and finally the
    mark itself, in that back-to-front order) rather than compositing
    into whatever was there before.

    `ox0`/`oy0`/`ox1`/`oy1` default to the whole canvas (`ox1`/`oy1`'s
    default of -1 means "canvas.width"/"canvas.height" -- a real
    negative bound is never meaningful, so it's a safe sentinel, not
    an ambiguous one) -- every existing single-plot call keeps
    rendering into the entire canvas exactly as before. Passing a
    narrower rectangle instead (what `render_facets()` does, one call
    per grid cell) makes this one plot's own margins, axes, and
    optional legend lay out relative to that sub-rectangle instead of
    the whole canvas -- the plot has no idea it's sharing a canvas
    with anything else.

    A thin wrapper around `_render_generic` (see this module's own
    docstring for why rendering is split this way): resolves the
    sentinel bounds against `canvas`'s own size, reserves room for any
    `Plot.labels()` title/axis titles via `_apply_labels` (see its own
    docstring for why that happens *here*, not inside `_render_generic`
    itself), hands the shrunk rect off to the shared generic core for
    everything else, then builds the title(s)' own `_TextRequest`s via
    `_label_text_requests` -- only now, using the *inner* plot rect
    `_render_generic` actually returned (`_RenderResult`'s own `px0`..
    `py1`), so a title/x_title centers on the real data area rather
    than the full outer bounds (see `_apply_labels`'s own docstring for
    why this is a two-phase split) -- and finally draws every
    `_TextRequest` (the title(s) plus whatever `_render_generic` itself
    returned) via `canvas_mojo.text.draw_text` -- the one piece
    `_render_generic` itself can't do, since it's generic over any
    `DrawTarget` and drawing real text needs `canvas_mojo.text`'s own
    native glyph machinery, specific to this raster path (see
    `_TextRequest`'s own docstring).

    The whole *original* `(ox0, oy0)`-`(cx1, cy1)` rect is filled with
    `theme.background` before anything else -- not just the shrunk
    inner rect handed downstream -- so a title's own reserved margin
    strip gets painted too, rather than showing whatever `canvas` held
    before this call (which usually happens to match anyway, but isn't
    guaranteed to).

    This is now the *only* background fill on this path. `_render_
    generic` and every mark-specific `_render_*` used to open by
    filling their own rect a second time -- always a strict subset of
    this one, in the same color, so always pure waste: one whole extra
    full-target fill per render (at a 640x420 chart's own
    quickplot-supersampled 1920x1260 scratch canvas -- see `_rendered`'s
    own docstring -- about 2.4M redundant pixel writes per chart --
    arithmetic, not a measured speedup; nothing here has been
    benchmarked). Painting the background is the *entry point's* job
    now, once, and each of the four entry points does it: here,
    `render_svg()`, `_render_facets_generic` (per cell -- see its own
    comment) and `render_layers()`/`render_layers_svg()`.

    Never supersampled on its own -- every pixel-sized quantity here
    scales only by `plot._theme.scale` (see `Theme`'s own docstring),
    exactly the value the caller set, nothing added silently. This is
    the precise, pixel-for-pixel entry point real HiDPI export and
    this whole test suite's own hand-verified pixel assertions rely
    on; `_rendered()` -- what every one-call convenience function
    (`bar()`, `scatter()`, ...) calls instead of this directly -- is
    the one place a fixed supersample factor gets applied
    automatically, invisibly to its own caller, precisely because nothing
    there needs that precision (see its own docstring for why the two
    entry points draw that line differently).
    """
    var cx1 = ox1 if ox1 >= 0 else canvas.width
    var cy1 = oy1 if oy1 >= 0 else canvas.height
    canvas.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plot._theme.background)
    var frame = _apply_labels(plot, ox0, oy0, cx1, cy1)
    var result = _render_generic(canvas, plot, frame.ox0, frame.oy0, frame.ox1, frame.oy1)
    var label_requests = _label_text_requests(
        plot, ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    for req in label_requests:
        draw_text(canvas, req.x, req.y, req.text, req.color, req.size, align=req.align, rotation=req.rotation)
    for req in result.text_requests:
        draw_text(canvas, req.x, req.y, req.text, req.color, req.size, align=req.align, rotation=req.rotation)


def render_svg(
    mut svg: SvgCanvas, plot: Plot, ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1
) raises:
    """`render()`'s exact counterpart for `SvgCanvas` -- same
    sentinel-resolution, same `_apply_labels`/`_render_generic` core,
    same `_TextRequest` lists handed back afterward; the only
    difference is *how* those get drawn (`SvgCanvas.draw_text`, plain
    markup emission, no font/glyph machinery involved at all) -- see
    `render()`'s own docstring for the shared story, and canvas_mojo/
    draw_target.mojo's for why text is deferred like this in the first
    place.
    """
    var cx1 = ox1 if ox1 >= 0 else svg.width
    var cy1 = oy1 if oy1 >= 0 else svg.height
    svg.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plot._theme.background)
    var frame = _apply_labels(plot, ox0, oy0, cx1, cy1)
    var result = _render_generic(svg, plot, frame.ox0, frame.oy0, frame.ox1, frame.oy1)
    var label_requests = _label_text_requests(
        plot, ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    for req in label_requests:
        svg.draw_text(req.x, req.y, req.text, req.color, req.size, req.align, rotation=req.rotation)
    for req in result.text_requests:
        svg.draw_text(req.x, req.y, req.text, req.color, req.size, req.align, rotation=req.rotation)


struct _PointChannels(Movable):
    """Every derived value `Mark.POINT`'s own three optional data-driven
    channels (categorical color, continuous color, continuous size --
    see `Plot.encode`'s own docstring) need: which of the three are
    actually encoded, the categorical domain and palette a discrete
    color column indexes into, and the `ColorScale`/`LinearScale` a
    continuous color/size column maps through.

    Built unconditionally, even for a plot encoding none of the three
    (every `has_*` False, both lists empty, both scales built over a
    placeholder `[0, 1]` domain and never queried) -- the same "one code
    path, not a branch duplicated per combination" convention the
    single-plot render path already documented for these values
    individually, back when it computed each of them inline.

    A struct rather than five separate locals because these are needed
    at *two* different points in one render, either side of a step that
    happens in between: once before the plot rect is finalized, to size
    the legend column around the labels that will actually go in it
    (`_legend_reserve_for`), and once after, to color/size each point
    and draw those same legend sections (`_draw_point_layer`). Computing
    them once and handing the same value to both is what keeps the two
    provably consistent -- a column sized for one palette and then drawn
    with another would be a silent layout bug, and the two used to be
    independent recomputations in `_render_layers_generic`, agreeing
    only by inspection.
    """

    var has_color: Bool
    var has_color_categories: Bool
    var has_size: Bool
    # The categorical color column's own domain *and* each row's index
    # into it, resolved once here rather than searched per point at
    # draw time -- see `_categorical_indices`' own docstring. Held as
    # the whole `_CategoricalIndex` rather than unpacked into two
    # fields: Mojo won't let a returned struct's fields be moved out
    # individually (the same rule `_CategoricalFrame.result` documents),
    # so unpacking would mean copying the per-row index list on every
    # render -- the exact O(n) work this is here to avoid. Both halves
    # are empty when the channel isn't encoded.
    var cat: _CategoricalIndex
    var palette: List[Color]
    var color_scale: ColorScale
    var size_mm: MinMax
    var size_scale: LinearScale

    def __init__(out self, plot: Plot, sc: _Scaled) raises:
        self.has_color = len(plot.color_data) > 0
        self.has_color_categories = len(plot.color_categories) > 0
        self.has_size = len(plot.size_data) > 0
        # Branch rather than resolving an empty column: `plot` is
        # borrowed, so feeding `color_categories` through a ternary
        # would need a full copy of it just to hand back an empty
        # result on the unencoded path.
        if self.has_color_categories:
            self.cat = _categorical_indices(plot.color_categories)
        else:
            self.cat = _CategoricalIndex(List[String](), List[Int]())
        self.palette = default_categorical_palette() if self.has_color_categories else List[Color]()
        var color_mm = _min_max(plot.color_data) if self.has_color else MinMax(0.0, 1.0)
        self.color_scale = ColorScale(color_mm.min, color_mm.max)
        self.color_scale.add_stop(0.0, plot._theme.color_scale_low)
        self.color_scale.add_stop(1.0, plot._theme.color_scale_high)
        self.size_mm = _min_max(plot.size_data) if self.has_size else MinMax(0.0, 1.0)
        self.size_scale = LinearScale(
            self.size_mm.min, self.size_mm.max, sc.size_range_min, sc.size_range_max
        )


def _validate_continuous_encoding(plot: Plot, context: String) raises:
    """Every check `Plot.encode()`'s own x/y/color/color_categories/size
    channels need before a continuous-axis render can start -- shared
    verbatim by the single-plot path (`_render_generic`) and the layered
    one (`_render_layers_generic`), which used to carry two independent
    copies of this list differing only in their error strings.

    `context` prefixes every message so each caller still reports the
    thing a caller can actually act on: `"Plot.encode()"` for a
    standalone plot, `"render_layers(): layer 2"` for one layer of a
    stack (strictly more locating than the old layered wording, which
    said "a layered plot's own x and y" without ever naming which one).

    Deliberately *not* the `Mark.POINT`/`LINE`/`AREA` allow-list
    `render_layers()` also enforces -- that one is genuinely specific to
    layering (a standalone `Mark.BAR` plot is perfectly legal, a layered
    one isn't), so it stays at its own call site rather than becoming a
    flag threaded through here.
    """
    if len(plot.x_data) != len(plot.y_data):
        raise Error(
            context
            + ": x and y must have the same length (got "
            + String(len(plot.x_data))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )
    var has_color = len(plot.color_data) > 0
    var has_color_categories = len(plot.color_categories) > 0
    var has_size = len(plot.size_data) > 0
    if has_color and len(plot.color_data) != len(plot.x_data):
        raise Error(
            context
            + ": color must be the same length as x/y (got "
            + String(len(plot.color_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_color_categories and len(plot.color_categories) != len(plot.x_data):
        raise Error(
            context
            + ": color_categories must be the same length as x/y (got "
            + String(len(plot.color_categories))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_color and has_color_categories:
        raise Error(
            context
            + ": color and color_categories are mutually exclusive -- pass"
            " one or the other, not both"
        )
    if has_size and len(plot.size_data) != len(plot.x_data):
        raise Error(
            context
            + ": size must be the same length as x/y (got "
            + String(len(plot.size_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if (has_color or has_color_categories or has_size) and not (
        plot._mark == Mark.POINT or plot._mark == Mark.SINGLE_AXIS or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context + ": color/size encoding is only supported for"
            " Mark.POINT/SINGLE_AXIS/EFFECT_SCATTER today"
        )


def _check_line_smoothing(theme: Theme) raises:
    """`Theme.line_smoothing`'s own `[0.0, 1.0]` range check -- see that
    field's own docstring (theme.mojo) for why anything outside that
    range has no assigned meaning here rather than being clamped.
    Called by `_draw_line_layer`/`_draw_area_layer`, so it now covers
    the layered render path too; that path built its own `Path` inline
    and never checked (nor applied) smoothing at all before those two
    functions existed.
    """
    if theme.line_smoothing < 0.0 or theme.line_smoothing > 1.0:
        raise Error(
            "Theme.line_smoothing must be in [0.0, 1.0] (got " + String(theme.line_smoothing) + ")"
        )


def _legend_reserve_for(plot: Plot, ch: _PointChannels, sc: _Scaled) raises -> Int:
    """How much width `plot`'s own legend column needs, or `0` when it
    has no legend at all (`Theme.show_legend` off, a non-`Mark.POINT`
    mark, or no data-driven channel encoded -- every other mark either
    has its own separate legend logic or none).

    A plot can combine continuous color *and* size (a real, existing
    case -- see `examples/bubble.mojo`), stacking both sections in one
    column -- so the width is whichever section needs more room, not a
    sum (they stack vertically, not side by side). Categorical color and
    continuous color are mutually exclusive already
    (`_validate_continuous_encoding`), so at most one of the first two
    ever contributes.

    Called *before* the plot rect is finalized, the same "measure the
    real labels before sizing the margin around them" ordering the
    y-axis's own dynamic left margin already requires -- see
    `_dynamic_legend_width`'s own docstring.
    """
    if not plot._theme.show_legend:
        return 0
    if not (
        plot._mark == Mark.POINT or plot._mark == Mark.SINGLE_AXIS or plot._mark == Mark.EFFECT_SCATTER
    ):
        return 0
    if not (ch.has_color_categories or ch.has_color or ch.has_size):
        return 0

    var reserve = 0
    if ch.has_color_categories:
        reserve = max(reserve, _dynamic_legend_width(ch.cat.domain, sc.legend_swatch_size, sc))
    elif ch.has_color:
        var color_labels = List[String]()
        color_labels.append(_format_fixed(ch.color_scale.domain_max, 1))
        color_labels.append(_format_fixed(ch.color_scale.domain_min, 1))
        reserve = max(
            reserve, _dynamic_legend_width(color_labels, sc.continuous_legend_bar_width, sc)
        )
    if ch.has_size:
        var size_labels = List[String]()
        size_labels.append(_format_fixed(ch.size_mm.max, 1))
        size_labels.append(_format_fixed((ch.size_mm.min + ch.size_mm.max) / 2.0, 1))
        size_labels.append(_format_fixed(ch.size_mm.min, 1))
        var circle_content_width = 2 * _round_to_int(sc.size_range_max)
        reserve = max(reserve, _dynamic_legend_width(size_labels, circle_content_width, sc))
    return reserve


struct _ContinuousFrame(Movable):
    """`_draw_continuous_axis_frame`'s own finished layout -- the
    continuous-x counterpart to `_CategoricalFrame` (see its own
    docstring), with a `LinearScale` on both axes instead of an
    `OrdinalScale` on one.

    `px0`/`py0`/`px1`/`py1` are the finished inner plot rect, carried
    through unchanged for the caller's own `_RenderResult` -- same
    contract, same reasoning as `_CategoricalFrame`'s."""

    var x_scale: LinearScale
    var y_scale: LinearScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: LinearScale,
        var y_scale: LinearScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.y_scale = y_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        """This frame as the `_RenderResult` its caller returns -- see
        `_CategoricalFrame.result`'s own docstring, which this mirrors
        exactly."""
        return _RenderResult(self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1)


def _draw_continuous_axis_frame[
    T: DrawTarget
](
    mut target: T,
    x_scale: LinearScale,
    y_scale: LinearScale,
    theme: Theme,
    legend_reserve: Int,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
) raises -> _ContinuousFrame:
    """The layout and axis-frame-drawing core every continuous-x render
    path shares -- `_draw_categorical_axis_frame`'s own direct
    counterpart (see its docstring for the shared reasoning) for a plot
    whose x-axis is a continuous `LinearScale` rather than
    `OrdinalScale` bands: computes the dynamic left margin from
    `y_scale`'s own ticks, resolves both scales' pixel ranges against
    the resulting plot rect, and draws gridlines, both axis lines, and
    every x/y tick mark plus its label.

    Extracted for exactly the reason its categorical sibling was: a
    *second* caller needed the identical ~90 lines. `_render_generic`'s
    own continuous path and `_render_layers_generic` had carried
    near-verbatim copies of this since layering was added, and they had
    already drifted apart in a user-visible way (see
    `_draw_line_layer`'s own docstring for the specific behavior the
    layered copy silently lost).

    Both scales' *domains* must already be decided (their ranges are the
    usual `[0, 1]` placeholder `_data_extent`/`_zero_baseline_y_extent`
    return) -- deliberately parameters, not computed in here, since the
    two callers decide them differently: one plot's own data for a
    standalone render, every layered plot's data combined for a stacked
    one, with the zero-baseline rule keyed off `Mark.AREA` in each case.
    That is the entire difference between the two paths, which is
    exactly why it's the only thing left at their own call sites.

    `legend_reserve` is subtracted from the right edge before the rect
    is finalized (`0` when there's no legend) -- the same "shrink the
    rect from outside, don't thread a flag through the shared core"
    pattern `_apply_labels` and `_render_grouped_bar` both already use.
    """
    var sc = _Scaled(theme)

    # y-domain ticks computed before plot_x0 is finalized -- a scale's
    # own tick *values* (and so their formatted label text) depend only
    # on domain_min/domain_max, never on range_min/range_max (see
    # LinearScale.ticks()'s own docstring), so its labels can be
    # measured and the left margin sized to actually fit them, `max`'d
    # against Theme's own configured minimum so no existing plot's
    # layout ever gets *narrower* than it already was -- purely
    # additive, only ever growing the margin for labels wide enough to
    # actually need it (see _max_label_width's own docstring).
    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels()
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var out_x_scale = x_scale
    out_x_scale.range_min = Float64(plot_x0)
    out_x_scale.range_max = Float64(plot_x1)

    # y range is reversed: domain_min (smallest data value) lands at
    # the *bottom* of the plot area (the larger pixel y), domain_max
    # at the top -- see LinearScale's own docstring.
    var out_y_scale = y_scale
    out_y_scale.range_min = Float64(plot_y1)
    out_y_scale.range_max = Float64(plot_y0)

    var x_ticks = out_x_scale.ticks()
    var x_labels = x_ticks.labels()

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale)
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(out_y_scale, y_ticks.values[i])
            target.draw_line_aa(plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale)

    var text_requests = List[_TextRequest]()

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
        target.draw_line_aa(px, plot_y1, px, plot_y1 + sc.tick_length, theme.axis_color, width=sc.scale)
        text_requests.append(
            _TextRequest(
                px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                x_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
            )
        )

    # Baseline offset so a label's glyphs sit roughly vertically
    # centered on its tick, not hanging entirely below it --
    # draw_text's y is the text baseline (see text.mojo's own
    # docstring), so without this every y-axis label would appear
    # shifted upward relative to its tick mark.
    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(plot_x0 - sc.tick_length, py, plot_x0, py, theme.axis_color, width=sc.scale)
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                py + y_label_baseline_offset,
                y_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
            )
        )

    return _ContinuousFrame(
        out_x_scale, out_y_scale, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1
    )


comptime _HALO_ALPHA: UInt8 = 90


def _lighten(color: Color) -> Color:
    """`color` blended toward opaque white by a fixed amount -- `Mark.
    EFFECT_SCATTER`'s own halo tint (see `_draw_point_layer`'s own
    `draw_halo` paragraph). Built via `Color.blend_over` (give `color`
    a reduced alpha, composite it over white, keep the fully-opaque
    result) rather than real alpha transparency on the halo circle
    itself: `SvgCanvas` has no opacity concept at all (only `Canvas`,
    the raster backend, would actually blend a translucent fill), so a
    genuinely translucent halo would render solid in one backend and
    see-through in the other -- the same cross-backend-consistency
    concern `DrawTarget`'s own docstring raises for why it stays
    narrow, just for a primitive (real alpha) that still isn't there.
    """
    return Color(color.r, color.g, color.b, _HALO_ALPHA).blend_over(Color(255, 255, 255))


def _draw_point_layer[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    plot: Plot,
    ch: _PointChannels,
    x_scale: LinearScale,
    y_scale: LinearScale,
    legend_x: Int,
    legend_y: Int,
    draw_halo: Bool = False,
) raises -> Int:
    """Draw one `Mark.POINT` plot's own points into an already-laid-out
    continuous axis frame, plus whatever legend sections its encoded
    channels call for -- the whole of what a `Mark.POINT` mark
    contributes to a render, shared by the standalone path and by each
    `Mark.POINT` layer of a stacked one. Also `Mark.EFFECT_SCATTER`'s
    entire render (`draw_halo=True`) -- see this function's own halo
    paragraph below.

    Legend sections stack top to bottom in one column, each returning
    the y just below it for the next to start at -- categorical-or-
    continuous color first (mutually exclusive), then size, matching the
    order `_legend_reserve_for` sized them in. `legend_y` in / the next
    free y out, so a caller drawing several layers into one shared
    column just threads the return value through as a running cursor;
    a standalone caller ignores it.

    `legend_x` is the caller's, not computed here: a layered render
    shares one column x across every layer (from the *combined* plot
    rect), which this function has no way to know on its own.

    Everything else comes from `plot`'s own `Theme` -- row height, font
    size, colors, point radius -- so a layer styled differently from its
    neighbors draws its own section correctly rather than being forced
    through the shared chrome's styling.

    `draw_halo`, when set, draws one extra circle *underneath* each
    point first -- `_lighten`ed toward white, ~2x the radius -- a
    static stand-in for `Mark.EFFECT_SCATTER`'s own real ECharts
    behavior (an animated ripple), which a raster/SVG renderer with no
    animation concept can't reproduce; see `_lighten`'s own docstring
    for why this uses `Color.blend_over` rather than real alpha
    transparency (`SvgCanvas` doesn't support it, so a translucent halo
    would look different on the two backends).
    """
    var theme = plot._theme
    var sc = _Scaled(theme)

    for i in range(len(plot.x_data)):
        var px = _axis_pixel(x_scale, plot.x_data[i])
        var py = _axis_pixel(y_scale, plot.y_data[i])
        var color: Color
        if ch.has_color:
            color = ch.color_scale.color_at(plot.color_data[i])
        elif ch.has_color_categories:
            # A plain lookup, not a search: _PointChannels resolved
            # every row's own domain index up front (see _categorical_
            # indices' own docstring for what this used to cost here).
            color = ch.palette[ch.cat.indices[i] % len(ch.palette)]
        else:
            color = theme.mark_color
        var radius = (
            _round_to_int(ch.size_scale.to_pixel(plot.size_data[i]))
            if ch.has_size
            else _round_to_int(sc.point_radius)
        )
        if draw_halo:
            target.fill_circle_aa(px, py, _round_to_int(Float64(radius) * 2.2), _lighten(color))
        target.fill_circle_aa(px, py, radius, color)

    if not theme.show_legend:
        return legend_y
    if not (ch.has_color_categories or ch.has_color or ch.has_size):
        return legend_y

    var next_y = legend_y
    if ch.has_color_categories:
        _draw_legend(target, text_requests, ch.cat.domain, ch.palette, legend_x, next_y, theme)
        next_y += len(ch.cat.domain) * (sc.legend_swatch_size + sc.legend_row_gap)
    elif ch.has_color:
        next_y = _draw_continuous_color_legend(
            target, text_requests, ch.color_scale, legend_x, next_y, theme
        )
    if ch.has_size:
        next_y = _draw_continuous_size_legend(
            target, text_requests, ch.size_mm, ch.size_scale, legend_x, next_y, theme
        )
    return next_y


def _draw_line_layer[
    T: DrawTarget
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.LINE` plot's own stroked path into an already-
    laid-out continuous axis frame -- `Theme.line_smoothing` included
    (`_build_line_path`, see its own docstring).

    Shared by the standalone and layered paths, which is the point:
    `_render_layers_generic` used to build its own `Path` inline with a
    plain `move_to` plus one `line_to` per point, so a layered
    `Mark.LINE` silently ignored `Theme.line_smoothing` entirely and
    never range-checked it either -- a straight drift from what
    `Theme.line_smoothing`'s own docstring (theme.mojo) documents, and
    exactly the kind of thing two near-identical copies of the same
    drawing code are for. Routing both through one function fixes it by
    construction rather than by remembering to.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    _check_line_smoothing(theme)
    var px = List[Float64](capacity=len(plot.x_data))
    var py = List[Float64](capacity=len(plot.x_data))
    for i in range(len(plot.x_data)):
        px.append(x_scale.to_pixel(plot.x_data[i]))
        py.append(y_scale.to_pixel(plot.y_data[i]))
    var path = _build_line_path(px, py, theme.line_smoothing)
    target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)


def _draw_area_layer[
    T: DrawTarget
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.AREA` plot's own filled region into an already-
    laid-out continuous axis frame: the same curve `_draw_line_layer`
    strokes (`_build_line_path`, `Theme.line_smoothing` included), but
    closed down to the zero baseline (`y_scale`'s own domain already
    guarantees zero is a real point in range -- see
    `_zero_baseline_y_extent`) and filled instead of stroked.

    Only the *top* edge (through the data points) smooths; the bottom
    edge (the two `line_to`s down to and along baseline) is always
    straight -- baseline is a fixed reference line, not data, so there's
    nothing for it to curve through, the same reasoning a real chart
    library's own smoothed-area fill never bends its own flat baseline
    either. Shared by the standalone and layered paths for the same
    reason -- and with the same drift fixed -- as `_draw_line_layer`.
    """
    var theme = plot._theme
    _check_line_smoothing(theme)
    var baseline_py = y_scale.to_pixel(0.0)
    var px = List[Float64](capacity=len(plot.x_data))
    var py = List[Float64](capacity=len(plot.x_data))
    for i in range(len(plot.x_data)):
        px.append(x_scale.to_pixel(plot.x_data[i]))
        py.append(y_scale.to_pixel(plot.y_data[i]))
    var path = _build_line_path(px, py, theme.line_smoothing)
    path.line_to(px[len(px) - 1], baseline_py)
    path.line_to(px[0], baseline_py)
    path.close()
    target.fill_path_aa(path, theme.mark_color)


def _render_generic[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """The actual dispatch, layout, and shape-drawing core `render()`/
    `render_svg()` both delegate to -- generic over any `DrawTarget`,
    so this exact code draws correctly into a raster `Canvas` or a
    vector `SvgCanvas` alike, with no branch anywhere on which one it
    got. Returns every axis/tick/legend label this render pass needs
    drawn as text (see `_TextRequest`'s own docstring for why they
    aren't drawn directly here).

    `Mark.BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`/`CANDLESTICK`/`BULLET`/
    `GANTT`/`GROUPED_BAR`/`STACKED_BAR`/`ARC` dispatch to their own
    fully separate functions immediately -- the first nine have a
    genuinely different axis layout (`OrdinalScale` bands for at least
    one axis, not a plain continuous `LinearScale` pair; the first six
    plus `GROUPED_BAR`/`STACKED_BAR` share one vertical axis-frame core
    with each other -- see `_draw_categorical_axis_frame`'s own
    docstring -- while `GANTT` has its own horizontal mirror, `_draw_
    horizontal_categorical_axis_frame`, see its own docstring for why
    it isn't a third shared core), and `ARC` has no x/y axis frame at
    all, so threading any of them through nearly every line below would
    be far less readable than each staying its own function (see
    `_render_bar`/`_render_arc`'s own docstrings).

    What's left after the dispatch -- the `Mark.POINT`/`LINE`/`AREA`
    continuous-axis path -- is itself now just a short assembly of
    shared pieces, in the same shape every categorical `_render_*`
    already had: decide the two domains (the only genuinely per-path
    decision, see `_draw_continuous_axis_frame`'s own docstring), size
    the legend column (`_legend_reserve_for`), draw the axis frame
    (`_draw_continuous_axis_frame`), then draw the one mark
    (`_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`). Every
    one of those is shared with `_render_layers_generic`, which used to
    carry its own near-verbatim copy of all of it.
    """
    if plot._mark == Mark.BAR:
        return _render_bar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.LOLLIPOP:
        return _render_lollipop(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.WATERFALL:
        return _render_waterfall(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.BOX:
        return _render_box(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.CANDLESTICK:
        return _render_candlestick(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.BULLET:
        return _render_bullet(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.GROUPED_BAR:
        return _render_grouped_bar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.STACKED_BAR:
        return _render_stacked_bar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.GANTT:
        return _render_gantt(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.POPULATION_PYRAMID:
        return _render_population_pyramid(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.HEATMAP:
        return _render_heatmap(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.CHORD:
        return _render_chord(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.SINGLE_AXIS:
        return _render_single_axis(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.FUNNEL:
        return _render_funnel(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.BUMP:
        return _render_bump(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.STREAMGRAPH:
        return _render_streamgraph(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.BEESWARM:
        return _render_beeswarm(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.VIOLIN:
        return _render_violin(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.ARC:
        return _render_arc(target, plot, ox0, oy0, ox1, oy1)

    _validate_continuous_encoding(plot, "Plot.encode()")

    var theme = plot._theme
    if len(plot.x_data) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    # Every pixel-sized Theme/module-constant quantity below, scaled
    # once by theme.scale -- see _Scaled's own docstring.
    var sc = _Scaled(theme)

    # Built once and handed to both _legend_reserve_for (which sizes
    # the legend column before the plot rect is final) and _draw_point_
    # layer (which colors/sizes each point afterward) -- see
    # _PointChannels' own docstring for why the two have to agree.
    var ch = _PointChannels(plot, sc)
    var legend_reserve = _legend_reserve_for(plot, ch, sc)

    # The one thing that differs between this path and the layered one:
    # whose data the two domains are computed over (see _draw_
    # continuous_axis_frame's own docstring). Mark.AREA forces a zero
    # baseline into the y-domain, every other continuous mark just pads
    # around its own data.
    var y_scale = (
        _zero_baseline_y_extent(plot.y_data) if plot._mark == Mark.AREA else _data_extent(plot.y_data)
    )
    var x_scale = _data_extent(plot.x_data)

    var frame = _draw_continuous_axis_frame(
        target, x_scale, y_scale, theme, legend_reserve, ox0, oy0, ox1, oy1
    )

    if plot._mark == Mark.POINT or plot._mark == Mark.EFFECT_SCATTER:
        _ = _draw_point_layer(
            target,
            frame.text_requests,
            plot,
            ch,
            frame.x_scale,
            frame.y_scale,
            frame.px1 + sc.margin_right,
            frame.py0,
            draw_halo=plot._mark == Mark.EFFECT_SCATTER,
        )
    elif plot._mark == Mark.LINE:
        _draw_line_layer(target, plot, frame.x_scale, frame.y_scale)
    elif plot._mark == Mark.AREA:
        _draw_area_layer(target, plot, frame.x_scale, frame.y_scale)

    return frame.result()


struct _CategoricalFrame(Movable):
    """The shared, finished layout every categorical-x-axis mark
    (`Mark.BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`) draws its own per-
    category shape into -- see `_draw_categorical_axis_frame`'s own
    docstring for what it computes and why factoring this out (and not
    the continuous-x path `_render_generic` itself covers) was the
    right call.

    `px0`/`py0`/`px1`/`py1` are the finished inner plot rect (the same
    `plot_x0`/`plot_y0`/`plot_x1`/`plot_y1` this frame's own axis lines
    are drawn at) -- carried through unchanged so each caller can build
    its own `_RenderResult` from them, rather than re-deriving the rect
    from `x_scale`/`y_scale`'s own range fields (see `_RenderResult`'s
    own docstring for why that rect matters)."""

    var x_scale: OrdinalScale
    var y_scale: LinearScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: OrdinalScale,
        var y_scale: LinearScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.y_scale = y_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        """This frame as the `_RenderResult` its caller returns -- the
        line every mark's own `_render_*` ends with, once it has drawn
        whatever per-category shape it exists to draw.

        A `.copy()` of `text_requests`, not a `^` transfer: Mojo's
        ownership checker rejects moving a single field out of a struct
        ("field 'self.text_requests' destroyed out of the middle of a
        value"), since the rest of the frame still owns `x_scale`/
        `y_scale`/`sc` and needs its own normal end-of-scope
        destruction. Re-confirmed directly against the current compiler
        when this method was extracted, including with an owned `var
        self` and with every field consumed in turn -- Mojo has no
        piecewise-destructuring form that satisfies it, so the copy
        isn't a workaround for a borrow that could have been avoided by
        restructuring. It's a small `List` either way, and it now
        happens in exactly one place instead of eleven.
        """
        return _RenderResult(self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1)


def _draw_categorical_axis_frame[
    T: DrawTarget
](
    mut target: T,
    categories: List[String],
    y_scale: LinearScale,
    theme: Theme,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
) raises -> _CategoricalFrame:
    """The layout and axis-frame-drawing core shared by every
    categorical-x-axis mark (`Mark.BAR`, `LOLLIPOP`, `WATERFALL`, `BOX`
    as of this writing): computes the dynamic left margin from
    `y_scale`'s own ticks, builds the `OrdinalScale` x-axis, draws
    gridlines/axis lines/y-tick marks+labels and every category's own
    x-tick mark+label -- everything these mark types draw identically.
    Returns the finished `x_scale`/`y_scale` (pixel ranges resolved)
    plus the already-scaled `_Scaled` theme and the `_TextRequest`s
    collected so far, for the caller to draw its own per-category shape
    into (a filled rect, a stem+point, a floating rect, a box+whiskers
    -- the one genuinely different piece between these mark types,
    deliberately left to each one's own function rather than threaded
    through here, matching `_render_bar`'s own long-standing "a mark-
    type branch through nearly every line is worse than each path
    staying its own function" reasoning).

    Extracted from `_render_bar`'s own original, self-contained body
    once a *third* categorical mark needed the identical axis-frame
    logic -- two call sites sharing a little duplication was this
    codebase's own established tolerance (see the paragraph above), but
    four near-identical ~130-line copies of the same layout math
    stopped being "a little." The one real behavioral difference from
    `_render_bar`'s original body: the per-category x-tick+label loop
    and the per-category mark-drawing loop are now two separate passes
    (every category's tick+label was interleaved with its own bar
    before) -- harmless for both backends, since ticks/labels live
    below the plot area and every mark shape lives inside it, regions
    that never overlap; confirmed directly, not just by construction --
    every pre-existing hand-derived pixel and SVG-substring assertion
    for `Mark.BAR` kept passing completely unchanged once this landed.

    `y_scale`'s domain must already be decided (its range is the usual
    `[0, 1]` placeholder `_data_extent`/`_zero_baseline_y_extent`
    return) -- deliberately a parameter, not computed in here, since
    these mark types don't all want the same domain rule (`Mark.BAR`/
    `LOLLIPOP`/`WATERFALL` always include a zero baseline; `Mark.BOX`
    doesn't -- a box plot's axis should fit the actual data spread, not
    force in a zero that distribution data has no reason to include).
    """
    var sc = _Scaled(theme)

    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels()
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var x_scale = OrdinalScale(categories.copy(), Float64(plot_x0), Float64(plot_x1))

    # y range is reversed: domain_min lands at the *bottom* of the
    # plot area (the larger pixel y), domain_max at the top -- see
    # LinearScale's own docstring.
    var out_y_scale = y_scale
    out_y_scale.range_min = Float64(plot_y1)
    out_y_scale.range_max = Float64(plot_y0)

    if theme.show_gridlines:
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(out_y_scale, y_ticks.values[i])
            target.draw_line_aa(plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale)

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(plot_x0 - sc.tick_length, py, plot_x0, py, theme.axis_color, width=sc.scale)
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                py + y_label_baseline_offset,
                y_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
            )
        )

    for i in range(len(categories)):
        var center_px = _round_to_int(x_scale.center(i))
        target.draw_line_aa(center_px, plot_y1, center_px, plot_y1 + sc.tick_length, theme.axis_color, width=sc.scale)
        text_requests.append(
            _TextRequest(
                center_px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                categories[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
            )
        )

    return _CategoricalFrame(x_scale^, out_y_scale, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def render_facets(mut canvas: Canvas, plots: List[Plot], cols: Int) raises:
    """Render each of `plots` into its own evenly sized grid cell on
    `canvas` -- see `_render_facets_generic`'s own docstring for the
    actual cell-layout contract this and `render_facets_svg` share. A
    thin wrapper exactly like `render()`'s own: resolve `canvas`'s own
    size, hand off to the shared generic core, draw the `_TextRequest`s
    it returns via `canvas_mojo.text.draw_text`.
    """
    var text_requests = _render_facets_generic(canvas, canvas.width, canvas.height, plots, cols)
    for req in text_requests:
        draw_text(canvas, req.x, req.y, req.text, req.color, req.size, align=req.align, rotation=req.rotation)


def render_facets_svg(mut svg: SvgCanvas, plots: List[Plot], cols: Int) raises:
    """`render_facets()`'s exact counterpart for `SvgCanvas` -- same
    shared `_render_facets_generic` core, `SvgCanvas.draw_text` in
    place of `canvas_mojo.text.draw_text` for the returned labels, the same
    relationship `render_svg()` has to `render()` (see that function's
    own docstring).
    """
    var text_requests = _render_facets_generic(svg, svg.width, svg.height, plots, cols)
    for req in text_requests:
        svg.draw_text(req.x, req.y, req.text, req.color, req.size, req.align, rotation=req.rotation)


def _render_facets_generic[
    T: DrawTarget
](mut target: T, width: Int, height: Int, plots: List[Plot], cols: Int) raises -> List[_TextRequest]:
    """The shared cell-layout core `render_facets()`/`render_facets_svg()`
    both delegate to -- generic over any `DrawTarget`, the same
    `_render_generic`/`render()`/`render_svg()` split (see that
    function's own docstring). `width`/`height` are passed in
    explicitly by each wrapper (`Canvas.width`/`.height` for one,
    `SvgCanvas.width`/`.height` for the other) rather than read off
    `target` itself -- `DrawTarget` deliberately has no width/height
    accessor of its own, the same reason it has no `draw_text` (see
    that trait's own docstring): `Canvas` already has a public `width`
    field, and a same-named trait *method* would collide with it.

    `cols` columns, enough rows to fit `len(plots)` (a final row
    that isn't completely full just leaves its remaining cells blank,
    not stretched to cover them). Each cell is laid out exactly the
    way a standalone `render(canvas, plot)` call would lay out the
    whole target -- its own margins, its own axes, its own optional
    legend, even its own mark type, *and*, unlike this function's own
    original version, its own `Plot.labels()` title/x_title/y_title too
    (`_apply_labels`/`_label_text_requests`, the same two-phase split
    `render()`/`render_svg()` use -- see their own docstrings) -- one
    title per cell, from that cell's own `Plot`, not one shared title
    for the whole grid: each cell is its own independent small
    multiple, with its own data and potentially its own mark type, so a
    per-cell caption is the only reading that makes sense here (see
    the wiki's Changelog, its own "Plot.labels() reaches render_facets/
    render_layers" entry for why `render_layers`, sharing one
    combined domain across every layer, reads differently). `_render_
    generic`'s own `ox0`/`oy0`/`ox1`/`oy1` bounds are simply pointed at
    one cell's own *label-shrunk* rect instead of the whole target per
    call, so nothing about it needed to know facets exist. Every cell's
    own `_TextRequest`s (label text plus whatever `_render_generic`
    itself returned) accumulate into one shared list, returned once at
    the end -- the same "collect while drawing shapes, replay
    afterward" split every other render path here uses, not something
    facets add a second version of.

    Cell boundaries are `width * col // cols` (and the equivalent for
    rows), not `col * (width // cols)` -- the two differ whenever the
    target doesn't divide evenly by `cols`/`rows`, and only the first
    form guarantees adjacent cells share the exact same boundary pixel
    with no gap or 1px overlap (cell `col`'s right edge, `width *
    (col + 1) // cols`, is the identical expression to cell `col + 1`'s
    own left edge) -- confirmed directly, not assumed: a naive per-cell
    width computed once and repeated would let integer-division
    rounding error accumulate across columns instead of resetting at
    every boundary.

    A separate function from `_render_generic` itself, not a `plots:
    List` overload of it -- one `Plot` in, one whole target out is
    `_render_generic`'s own contract; this is a distinct "many plots,
    one target, grid layout" contract composed on top of it, the same
    relationship `_render_bar`/`_render_arc` have to `_render_generic`'s
    own continuous-x path (composition, not a mode flag threaded
    through one function).
    """
    var text_requests = List[_TextRequest]()
    if cols <= 0:
        raise Error("render_facets(): cols must be positive (got " + String(cols) + ")")
    if len(plots) == 0:
        return text_requests^

    var rows = (len(plots) + cols - 1) // cols
    for i in range(len(plots)):
        var row = i // cols
        var col = i % cols
        var cell_x0 = width * col // cols
        var cell_x1 = width * (col + 1) // cols
        var cell_y0 = height * row // rows
        var cell_y1 = height * (row + 1) // rows
        # Each cell's own *full* rect, filled from that cell's own
        # Plot's background before anything else -- the same "the whole
        # original rect gets painted, including the strip a title's
        # margin reserved" contract render()/render_svg() already
        # document. Cells used to rely on _render_generic filling its
        # own (label-shrunk) rect instead, which left a titled cell's
        # top band showing whatever the canvas held before the call.
        target.fill_rect(
            cell_x0, cell_y0, cell_x1 - cell_x0, cell_y1 - cell_y0, plots[i]._theme.background
        )
        var frame = _apply_labels(plots[i], cell_x0, cell_y0, cell_x1, cell_y1)
        var cell_result = _render_generic(target, plots[i], frame.ox0, frame.oy0, frame.ox1, frame.oy1)
        var label_requests = _label_text_requests(
            plots[i], cell_x0, cell_y0, cell_x1, cell_y1, cell_result.px0, cell_result.py0, cell_result.px1, cell_result.py1
        )
        for req in label_requests:
            text_requests.append(req.copy())
        for req in cell_result.text_requests:
            text_requests.append(req.copy())

    return text_requests^


def render_layers(mut canvas: Canvas, plots: List[Plot], ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1) raises:
    """Render every `Plot` in `plots` onto *one shared* coordinate
    system on `canvas` -- one combined x/y domain (computed across
    every layered plot's own data together, not each plot's own
    independent domain the way `render_facets()`'s cells each get),
    one shared set of axes/gridlines/ticks, each plot's own mark drawn
    on top of the last in the order given -- a line overlaid on a
    scatter, three comparison lines sharing one y-axis, and so on.

    Restricted to `Mark.POINT`/`LINE`/`AREA` for this first version --
    `Mark.BAR`'s categorical x-axis and `Mark.ARC`'s lack of one don't
    share a domain shape with continuous marks or each other; layering
    those in is real, separate, deferred work (see the wiki's Backlog).
    Raises if any layered plot uses a different mark.

    A layer whose own mark is `Mark.POINT` can use `color`/`color_
    categories`/`size` encoding exactly like a standalone `Mark.POINT`
    plot (see `Plot.encode`'s own docstring) -- each such layer's own
    domain (color scale, size scale, category palette) is independent
    of every other layer's, the same "each layer's own `Theme` only
    governs its own mark's appearance" independence `mark_color`/
    `point_radius`/`line_width` already have. Raises the identical
    "only Mark.POINT" error `Plot.encode`'s own single-plot path raises
    if a `LINE`/`AREA` layer tries to use one of these instead. A
    caller wanting several distinctly colored *series* instead (rather
    than per-point encoding within one series) still sets each layer's
    own flat `Theme.mark_color` (the same per-layer-styling `examples/
    facets.mojo` already uses, just overlaid here instead of laid out
    in a grid) -- `render_layers` still has no per-*series* name/label
    concept for a "which layer is which" legend built from several
    flat-colored layers (see the wiki's Backlog, its own "Explicitly
    still open" section); that's a separate feature from per-point
    encoding within a single layer, which this one now supports.

    Shared chrome -- background, gridlines, axis colors, margins, font
    size, tick spacing -- comes from `plots[0]`'s own `Theme`; every
    other layered plot's own `Theme` only governs its own mark's
    appearance (`mark_color`, `point_radius`, `line_width`, and --
    since every render path now builds its curve through the same
    `_build_line_path`, see `_draw_line_layer`'s own docstring -- `line_
    smoothing`, each still scaled by that plot's own `Theme.scale`; see
    `_Scaled`'s own docstring). A layered `Mark.LINE`/`AREA` used to
    ignore `line_smoothing` entirely, always drawing straight segments
    no matter what its own `Theme` asked for; it now curves exactly the
    way the identical plot rendered standalone through `render()`
    already did, and rejects an out-of-`[0.0, 1.0]` value there the
    same way too, instead of silently accepting it. Each encoding-using `Mark.POINT` layer draws its own
    legend section(s) (gated by that layer's own `Theme.show_legend`,
    not `plots[0]`'s), stacked in one shared column in layer order --
    the same categorical/continuous-color/size section types and
    stacking order `_render_generic`'s own single-plot `Mark.POINT`
    legend already uses (see its own docstring), just once per
    encoding-using layer instead of once per plot. The legend column's
    own horizontal position is shared (every section starts at the
    identical x, from the combined `plot_x1`), but each section's own
    row height/font size/colors come from that specific layer's own
    `Theme` -- so differently-scaled or differently-styled layers each
    draw their own section correctly, not forced through `plots[0]`'s
    styling.

    `Plot.labels()`'s title/x_title/y_title -- like every other piece of
    shared chrome -- come from `plots[0]`'s own labels, not each layer's
    own (a layered plot has one combined coordinate system, so one
    shared title is the only reading that makes sense here, unlike
    `render_facets()`'s own per-cell titles -- see that function's own
    docstring). The same `_apply_labels`/`_label_text_requests`
    two-phase split `render()`/`render_svg()` use.

    `ox0`/`oy0`/`ox1`/`oy1` are the exact same sentinel-bounds
    convention `render()` itself uses (see that function's own
    docstring) -- default to the whole canvas.
    """
    var cx1 = ox1 if ox1 >= 0 else canvas.width
    var cy1 = oy1 if oy1 >= 0 else canvas.height
    # An empty plots list is a real, tested no-op (test_render_layers_
    # with_empty_list_is_a_noop) -- _apply_labels needs plots[0], so
    # labels are skipped entirely rather than indexing an empty list;
    # _render_layers_generic's own existing empty check still leaves
    # the canvas untouched in that case, same as before this feature.
    if len(plots) == 0:
        _ = _render_layers_generic(canvas, plots, ox0, oy0, cx1, cy1)
        return
    canvas.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plots[0]._theme.background)
    var frame = _apply_labels(plots[0], ox0, oy0, cx1, cy1)
    var result = _render_layers_generic(canvas, plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1)
    var label_requests = _label_text_requests(
        plots[0], ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    for req in label_requests:
        draw_text(canvas, req.x, req.y, req.text, req.color, req.size, align=req.align, rotation=req.rotation)
    for req in result.text_requests:
        draw_text(canvas, req.x, req.y, req.text, req.color, req.size, align=req.align, rotation=req.rotation)


def render_layers_svg(mut svg: SvgCanvas, plots: List[Plot], ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1) raises:
    """`render_layers()`'s exact counterpart for `SvgCanvas` -- same
    shared `_render_layers_generic` core, `SvgCanvas.draw_text` in
    place of `canvas_mojo.text.draw_text` for the returned labels, the same
    relationship `render_svg()` has to `render()`.
    """
    var cx1 = ox1 if ox1 >= 0 else svg.width
    var cy1 = oy1 if oy1 >= 0 else svg.height
    # See render_layers()'s own comment just above -- same empty-list
    # guard, needed here too since _apply_labels indexes plots[0].
    if len(plots) == 0:
        _ = _render_layers_generic(svg, plots, ox0, oy0, cx1, cy1)
        return
    svg.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plots[0]._theme.background)
    var frame = _apply_labels(plots[0], ox0, oy0, cx1, cy1)
    var result = _render_layers_generic(svg, plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1)
    var label_requests = _label_text_requests(
        plots[0], ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    for req in label_requests:
        svg.draw_text(req.x, req.y, req.text, req.color, req.size, req.align, rotation=req.rotation)
    for req in result.text_requests:
        svg.draw_text(req.x, req.y, req.text, req.color, req.size, req.align, rotation=req.rotation)


def _render_layers_generic[
    T: DrawTarget
](mut target: T, plots: List[Plot], ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """The shared-domain layout/draw core `render_layers()`/
    `render_layers_svg()` both delegate to -- generic over any
    `DrawTarget`, the same `_render_generic`/`render()`/`render_svg()`
    split (see that function's own docstring). Still a standalone
    function, not `_render_generic` itself made to accept a list --
    "one plot, one target" and "many plots, one shared coordinate
    system" stay two contracts, not one function with a mode flag --
    but no longer a standalone *copy* of it: the domain/margin/axis
    layout and every mark's own drawing are the same shared functions
    the single-plot path calls (`_draw_continuous_axis_frame`,
    `_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`), leaving
    only what's genuinely different here -- domains computed across
    *all* layered plots' data at once, a legend column sized across
    every layer, and a legend-y cursor threaded through them in order.

    That used to be a near-verbatim copy of `_render_generic`'s own
    continuous-x path, justified as "a little duplication over a
    premature shared abstraction." It didn't hold up: the copies drifted,
    and a layered `Mark.LINE`/`AREA` silently stopped honoring
    `Theme.line_smoothing` (see `_draw_line_layer`'s own docstring).
    Roughly 200 lines of the two paths were identical by then -- well
    past the two-call-sites tolerance `_render_bar`'s own docstring
    describes, and the same threshold `_draw_categorical_axis_frame`
    was extracted at.

    Returns a `_RenderResult`, like every other `_render_*` function
    (see its own docstring) -- `render_layers()`/`render_layers_svg()`
    use the inner rect it carries to center `Plot.labels()`'s own
    title/x_title/y_title (sourced from `plots[0]`, see their own
    docstrings) on the real, shared plot area.
    """
    var text_requests = List[_TextRequest]()
    if len(plots) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    for i in range(len(plots)):
        # The one check that's genuinely layering-specific and so stays
        # here rather than moving into the shared validator: a
        # standalone Mark.BAR plot is perfectly legal, a layered one
        # isn't (see _validate_continuous_encoding's own docstring).
        if not (
            plots[i]._mark == Mark.POINT or plots[i]._mark == Mark.LINE or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): only Mark.POINT/Mark.LINE/Mark.AREA can be layered"
                " (got a different mark -- see the wiki's Backlog for why Mark.BAR/"
                "Mark.ARC aren't supported here yet)"
            )
        _validate_continuous_encoding(plots[i], "render_layers(): layer " + String(i))

    var theme = plots[0]._theme

    var combined_x = List[Float64]()
    var combined_y = List[Float64]()
    var any_area = False
    for i in range(len(plots)):
        for v in plots[i].x_data:
            combined_x.append(v)
        for v in plots[i].y_data:
            combined_y.append(v)
        if plots[i]._mark == Mark.AREA:
            any_area = True

    if len(combined_x) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Every pixel-sized Theme/module-constant quantity below, scaled
    # once by the shared (plots[0]'s own) theme.scale -- see _Scaled's
    # own docstring.
    var sc = _Scaled(theme)

    # The one thing that differs from the single-plot path: both
    # domains span *every* layer's data at once, rather than one plot's
    # own (see _draw_continuous_axis_frame's own docstring). A single
    # Mark.AREA layer anywhere in the stack forces the zero baseline in
    # for the whole shared y-axis, the same rule Mark.AREA follows on
    # its own.
    var y_scale = _zero_baseline_y_extent(combined_y) if any_area else _data_extent(combined_y)
    var x_scale = _data_extent(combined_x)

    # legend_reserve, computed across every encoding-using Mark.POINT
    # layer before the plot rect is finalized. Each layer's own section
    # width measured with that layer's own _Scaled (font size, swatch
    # size all independently scaled, matching every other per-layer
    # style choice here), `max`'d together into one shared column width
    # -- sections stack vertically in one column, so the column's own
    # width is whichever section needs the most room, not a sum.
    var legend_reserve = 0
    for j in range(len(plots)):
        var p_sc_j = _Scaled(plots[j]._theme)
        var ch_j = _PointChannels(plots[j], p_sc_j)
        legend_reserve = max(legend_reserve, _legend_reserve_for(plots[j], ch_j, p_sc_j))

    var frame = _draw_continuous_axis_frame(
        target, x_scale, y_scale, theme, legend_reserve, ox0, oy0, ox1, oy1
    )
    for req in frame.text_requests:
        text_requests.append(req.copy())

    # The legend column's own x is shared (every section starts at the
    # identical x, from the combined plot rect), while legend_y is a
    # running cursor threaded through every encoding-using layer's own
    # section(s) -- the same "each section returns the y just below it
    # for the next to start at" stacking a single plot's own legend
    # uses, just walked once per layer here instead of once per plot.
    var legend_x = frame.px1 + sc.margin_right
    var legend_y = frame.py0
    for j in range(len(plots)):
        if len(plots[j].x_data) == 0:
            continue
        if plots[j]._mark == Mark.POINT:
            var p_sc = _Scaled(plots[j]._theme)
            var ch_j = _PointChannels(plots[j], p_sc)
            legend_y = _draw_point_layer(
                target, text_requests, plots[j], ch_j, frame.x_scale, frame.y_scale, legend_x, legend_y
            )
        elif plots[j]._mark == Mark.LINE:
            _draw_line_layer(target, plots[j], frame.x_scale, frame.y_scale)
        elif plots[j]._mark == Mark.AREA:
            _draw_area_layer(target, plots[j], frame.x_scale, frame.y_scale)

    return _RenderResult(text_requests^, frame.px0, frame.py0, frame.px1, frame.py1)


def _rendered(
    var plot: Plot,
    theme: Theme,
    width: Int,
    height: Int,
    title: String,
    x_title: String,
    y_title: String,
) raises -> Canvas:
    """Everything every function in this module does once its own mark
    and data are chosen: apply the shared `title`/`x_title`/`y_title`
    and `theme` to the half-built `plot`, then render it -- at
    `_QUICKPLOT_SUPERSAMPLE` times `width`/`height`, into a scratch
    `Canvas` that size, immediately shrunk back down via
    `canvas_mojo.resize.downsample` -- and return the result, a
    `Canvas` of exactly `width`x`height` with genuinely finer-grained
    anti-aliasing baked in than a direct `render()` at that same size
    would produce (see `downsample()`'s own docstring for why this,
    not a single-resolution render, is what "finer AA" actually means
    here).

    All thirteen functions here used to carry a verbatim copy of these
    four lines, which is most of what each one *was* -- the two chained
    builder calls that pick the mark and encode the data are the only
    part that ever differed. `.labels()`/`.theme()` are applied here
    rather than at each call site for the same reason: nothing about
    them varies by mark.

    The supersampling itself used to live here too, spelled out by
    hand in every example instead: a `comptime _SUPERSAMPLE = 3`, `
    width`/`height` multiplied by it, `scale=Float64(_SUPERSAMPLE)`
    threaded into `Theme`, and the caller's own `downsample()` call on
    the far end. Every one of those five moving parts was pure
    implementation detail -- nothing about *what chart to draw*, only
    *how not to make its edges look worse than they have to* -- and
    every example carried an identical copy of it, which is the tell
    that it belonged here instead: this is now the one place that
    logic exists at all, not the cleaned-up version of a pattern
    every caller still has to write for themselves. A caller who wants
    that control back still has it, just spelled explicitly rather
    than defaulted invisibly: build the `Canvas`/`Plot` by hand and
    call `render()` directly, whose own `Theme.scale` is exactly the
    same multiplicative knob this function uses internally (see its
    own docstring) -- `render()` itself stays exactly as un-
    supersampled as it always was, deliberately: it's the precise,
    pixel-for-pixel entry point real HiDPI export and this whole test
    suite's own hand-verified pixel assertions depend on, so hiding
    this mechanism inside quickplot's own convenience layer doesn't
    touch it at all.

    A caller who renders the same `plot` through this function twice
    at different sizes sees no leftover effect of one call on the
    next -- `theme` is never mutated in place, only copied into a
    fresh, larger-`scale` `Theme` each time, since `Theme` is a plain
    value type and `theme.scale` here is always relative to the
    caller's own untouched `theme.scale`, not something this function
    remembers between calls.

    Takes `plot` as `var` (owned) because `Plot`'s own builder methods
    consume and return `Self` -- see plot.mojo's own module docstring
    for that convention -- and so the chain below needs an explicit
    `plot^` transfer into the first of them: `Plot` deliberately isn't
    `ImplicitlyCopyable` (it owns every data column), so without the
    `^` the compiler rejects the call outright rather than silently
    copying the columns.
    """
    var factor = _QUICKPLOT_SUPERSAMPLE
    var scaled_theme = theme
    scaled_theme.scale = theme.scale * Float64(factor)
    var scratch = Canvas(width * factor, height * factor, scaled_theme.background)
    render(scratch, plot^.labels(title=title, x_title=x_title, y_title=y_title).theme(scaled_theme))
    return downsample(scratch, factor)


def scatter(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A scatter plot -- `Mark.POINT` over continuous `x`/`y`."""
    var plot = Plot().mark_point().encode(x=x, y=y)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)


def line(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A line chart -- `Mark.LINE` over continuous `x`/`y`, connected
    in data order."""
    var plot = Plot().mark_line().encode(x=x, y=y)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)


def area(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """An area chart -- `Mark.AREA` over continuous `x`/`y`, filled
    down to a zero baseline."""
    var plot = Plot().mark_area().encode(x=x, y=y)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
