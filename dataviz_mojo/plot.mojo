"""Plot -- the fluent builder for this package's first vertical slice:
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
"""

from std.math import pi

from canvas_mojo.buffer import Canvas
from canvas_mojo.color import Color
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
from dataviz_mojo.box import _box_stats, _render_box
from dataviz_mojo.bullet import _render_bullet
from dataviz_mojo.candlestick import _render_candlestick
from dataviz_mojo.gantt import _render_gantt
from dataviz_mojo.grouped_bar import _render_grouped_bar
from dataviz_mojo.histogram import _bin_histogram
from dataviz_mojo.lollipop import _render_lollipop
from dataviz_mojo.stacked_bar import _render_stacked_bar
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
# consistency between the two), _CONTINUOUS_LEGEND_BAR_HEIGHT tall,
# approximated as _CONTINUOUS_LEGEND_BAR_STEPS thin solid-colored
# strips rather than a true smooth gradient -- DrawTarget (see its own
# docstring) has no gradient-fill method at all, only fill_rect, so
# this is the one construct available that works identically on both
# the raster and SVG backends; see _draw_continuous_color_legend's own
# docstring for why that's the right tradeoff here. 20 steps is dense
# enough that individual strip boundaries aren't visually obvious at
# this bar's own size.
comptime _CONTINUOUS_LEGEND_BAR_WIDTH = _LEGEND_SWATCH_SIZE
comptime _CONTINUOUS_LEGEND_BAR_HEIGHT = 100
comptime _CONTINUOUS_LEGEND_BAR_STEPS = 20

# Small breathing-room buffer beyond a dynamically measured label's
# own width -- see _max_label_width/the dynamic left-margin
# computation in render()/_render_bar.
comptime _MARGIN_BUFFER = 8


struct _Scaled(Movable):
    """Every pixel-sized quantity render()/_render_bar/_render_arc/
    _draw_legend actually draw with, pre-multiplied by `theme.scale`
    once here -- the single place the "* theme.scale" formula lives,
    so it can't drift between the several render paths that each need
    it (see Theme.scale's own docstring for what this is for). Built
    fresh from a Theme at the top of each of those functions; cheap
    (a handful of Float64/Int multiplies), not cached anywhere.
    """

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
        if not found:
            result.append(v)
    return result^


def _index_of(data: List[String], value: String) -> Int:
    for i in range(len(data)):
        if data[i] == value:
            return i
    return -1


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
    """A continuous color legend: a vertical gradient bar approximated
    as `_CONTINUOUS_LEGEND_BAR_STEPS` thin solid strips (see that
    constant's own docstring for why a true smooth gradient isn't
    available here), `color_scale`'s own high value at the top,
    low at the bottom -- the same "more/bigger is up" convention a
    y-axis itself already uses. Each strip colored at its own vertical
    *midpoint* value, not its top or bottom edge, so the visible band
    of color represents that strip's own value range symmetrically.
    Two labels (`_format_fixed`, one decimal place, matching `encode_
    histogram()`'s own bin-label convention): the domain max at the
    bar's own top, the domain min at its own bottom.

    Returns the y-coordinate just below this section (bar height plus
    one row gap) -- where `_draw_continuous_size_legend` starts if a
    plot combines continuous color *and* size (a real, existing case --
    see `examples/bubble.mojo`), so the two stack vertically in one
    legend column instead of overlapping.
    """
    var sc = _Scaled(theme)
    var bar_width = sc.continuous_legend_bar_width
    var bar_height = sc.continuous_legend_bar_height
    var steps = _CONTINUOUS_LEGEND_BAR_STEPS
    for i in range(steps):
        var t0 = Float64(i) / Float64(steps)
        var t1 = Float64(i + 1) / Float64(steps)
        var mid_t = (t0 + t1) / 2.0
        var value = color_scale.domain_max - mid_t * (color_scale.domain_max - color_scale.domain_min)
        var color = color_scale.color_at(value)
        var strip_y0 = y + _round_to_int(t0 * Float64(bar_height))
        var strip_y1 = y + _round_to_int(t1 * Float64(bar_height))
        target.fill_rect(x, strip_y0, bar_width, strip_y1 - strip_y0, color)

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


def _data_extent(data: List[Float64]) -> LinearScale:
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


def _zero_baseline_y_extent(data: List[Float64]) -> LinearScale:
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
    otherwise center on anyway."""

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
    inner rect `_render_generic` goes on to fill again itself -- so a
    title's own reserved margin strip gets painted too, rather than
    showing whatever `canvas` held before this call (which usually
    happens to match anyway, but isn't guaranteed to).
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
    if plot._mark == Mark.ARC:
        return _render_arc(target, plot, ox0, oy0, ox1, oy1)

    if len(plot.x_data) != len(plot.y_data):
        raise Error(
            "Plot.encode(): x and y must have the same length (got "
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
            "Plot.encode(): color must be the same length as x/y (got "
            + String(len(plot.color_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_color_categories and len(plot.color_categories) != len(plot.x_data):
        raise Error(
            "Plot.encode(): color_categories must be the same length as"
            " x/y (got "
            + String(len(plot.color_categories))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_color and has_color_categories:
        raise Error(
            "Plot.encode(): color and color_categories are mutually"
            " exclusive -- pass one or the other, not both"
        )
    if has_size and len(plot.size_data) != len(plot.x_data):
        raise Error(
            "Plot.encode(): size must be the same length as x/y (got "
            + String(len(plot.size_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if (has_color or has_color_categories or has_size) and not (plot._mark == Mark.POINT):
        raise Error(
            "Plot: color/size encoding is only supported for"
            " Mark.POINT today"
        )

    var theme = plot._theme
    target.fill_rect(ox0, oy0, ox1 - ox0, oy1 - oy0, theme.background)

    var text_requests = List[_TextRequest]()
    if len(plot.x_data) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Every pixel-sized Theme/module-constant quantity below, scaled
    # once by theme.scale -- see _Scaled's own docstring.
    var sc = _Scaled(theme)

    # Reserve a legend column on the right only when there's actually
    # something to put in it -- any of the three Mark.POINT-only
    # encodings (categorical color, continuous color, continuous size;
    # every other mark either has its own separate legend logic --
    # Mark.GROUPED_BAR/STACKED_BAR/ARC -- or none at all).
    var show_legend = theme.show_legend and plot._mark == Mark.POINT and (
        has_color_categories or has_color or has_size
    )
    # Every one of these built unconditionally (even when its own
    # channel isn't encoded, or show_legend is False) so there's one
    # code path, not a branch duplicated per combination -- matching
    # color_scale/size_scale's own existing "built unconditionally,
    # queried only when actually used" convention just below. All
    # computed *before* plot_x1 is finalized, the same "measure the
    # real labels/content before sizing the margin around them"
    # ordering the y-axis's own dynamic left margin already requires --
    # see _dynamic_legend_width's own docstring.
    var color_categories_domain = (
        _unique_categories(plot.color_categories) if has_color_categories else List[String]()
    )
    var color_mm = _min_max(plot.color_data) if has_color else MinMax(0.0, 1.0)
    var color_scale = ColorScale(color_mm.min, color_mm.max)
    color_scale.add_stop(0.0, theme.color_scale_low)
    color_scale.add_stop(1.0, theme.color_scale_high)
    var size_mm = _min_max(plot.size_data) if has_size else MinMax(0.0, 1.0)
    var size_scale = LinearScale(size_mm.min, size_mm.max, sc.size_range_min, sc.size_range_max)

    # A plot can combine continuous color *and* size (a real, existing
    # case -- see examples/bubble.mojo), stacking both sections in one
    # legend column -- the column's own width is whichever section
    # needs more room, not a sum (they stack vertically, not side by
    # side). Categorical color and continuous color are mutually
    # exclusive already (Plot.encode()'s own validation, above), so at
    # most one of the first two ever contributes.
    var legend_reserve = 0
    if show_legend:
        if has_color_categories:
            legend_reserve = max(
                legend_reserve, _dynamic_legend_width(color_categories_domain, sc.legend_swatch_size, sc)
            )
        elif has_color:
            var color_labels = List[String]()
            color_labels.append(_format_fixed(color_scale.domain_max, 1))
            color_labels.append(_format_fixed(color_scale.domain_min, 1))
            legend_reserve = max(
                legend_reserve,
                _dynamic_legend_width(color_labels, sc.continuous_legend_bar_width, sc),
            )
        if has_size:
            var size_labels = List[String]()
            size_labels.append(_format_fixed(size_mm.max, 1))
            size_labels.append(_format_fixed((size_mm.min + size_mm.max) / 2.0, 1))
            size_labels.append(_format_fixed(size_mm.min, 1))
            var circle_content_width = 2 * _round_to_int(sc.size_range_max)
            legend_reserve = max(
                legend_reserve, _dynamic_legend_width(size_labels, circle_content_width, sc)
            )

    # y-domain computed before plot_x0 is finalized -- a scale's own
    # tick *values* (and so their formatted label text) depend only on
    # domain_min/domain_max, never on range_min/range_max (see
    # LinearScale.ticks()'s own docstring), so its labels can be
    # measured and the left margin sized to actually fit them,
    # `max`'d against Theme's own configured minimum so no existing
    # plot's layout ever gets *narrower* than it already was -- purely
    # additive, only ever growing the margin for labels wide enough to
    # actually need it (see _max_label_width's own docstring).
    var y_scale = (
        _zero_baseline_y_extent(plot.y_data) if plot._mark == Mark.AREA else _data_extent(plot.y_data)
    )
    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels()
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var x_scale = _data_extent(plot.x_data)
    x_scale.range_min = Float64(plot_x0)
    x_scale.range_max = Float64(plot_x1)

    # y range is reversed: domain_min (smallest data value) lands at
    # the *bottom* of the plot area (the larger pixel y), domain_max
    # at the top -- see LinearScale's own docstring.
    y_scale.range_min = Float64(plot_y1)
    y_scale.range_max = Float64(plot_y0)

    var x_ticks = x_scale.ticks()
    var x_labels = x_ticks.labels()

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(x_scale, x_ticks.values[i])
            target.draw_line_aa(px, plot_y0, px, plot_y1, theme.gridline_color)
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(y_scale, y_ticks.values[i])
            target.draw_line_aa(plot_x0, py, plot_x1, py, theme.gridline_color)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color)

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(x_scale, x_ticks.values[i])
        target.draw_line_aa(px, plot_y1, px, plot_y1 + sc.tick_length, theme.axis_color)
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
        var py = _axis_pixel(y_scale, y_ticks.values[i])
        target.draw_line_aa(plot_x0 - sc.tick_length, py, plot_x0, py, theme.axis_color)
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

    if plot._mark == Mark.POINT:
        # color_categories_domain/color_mm/color_scale/size_mm/
        # size_scale are all computed earlier now (see this function's
        # own top, before legend_reserve) -- reused here unchanged, not
        # recomputed. color_scale/size_scale stay unused (never queried
        # below) when their own channel wasn't encoded -- built
        # unconditionally anyway so there's one code path per point,
        # not a branch duplicated for "has both" / "has neither" /
        # every combination in between.
        var palette = default_categorical_palette() if has_color_categories else List[Color]()

        for i in range(len(plot.x_data)):
            var px = _axis_pixel(x_scale, plot.x_data[i])
            var py = _axis_pixel(y_scale, plot.y_data[i])
            var color: Color
            if has_color:
                color = color_scale.color_at(plot.color_data[i])
            elif has_color_categories:
                var idx = _index_of(color_categories_domain, plot.color_categories[i])
                color = palette[idx % len(palette)]
            else:
                color = theme.mark_color
            var radius = (
                _round_to_int(size_scale.to_pixel(plot.size_data[i]))
                if has_size
                else _round_to_int(sc.point_radius)
            )
            target.fill_circle_aa(px, py, radius, color)

        if show_legend:
            # Sections stack top to bottom in one column, each one's
            # own draw function returning the y just below it for the
            # next to start at -- categorical-or-continuous color
            # first (mutually exclusive, see legend_reserve's own
            # computation above), then size, matching the same order
            # legend_reserve considered them in.
            var legend_x = plot_x1 + sc.margin_right
            var legend_y = plot_y0
            if has_color_categories:
                _draw_legend(target, text_requests, color_categories_domain, palette, legend_x, legend_y, theme)
                legend_y += len(color_categories_domain) * (sc.legend_swatch_size + sc.legend_row_gap)
            elif has_color:
                legend_y = _draw_continuous_color_legend(target, text_requests, color_scale, legend_x, legend_y, theme)
            if has_size:
                _ = _draw_continuous_size_legend(target, text_requests, size_mm, size_scale, legend_x, legend_y, theme)
    elif plot._mark == Mark.LINE:
        if theme.line_smoothing < 0.0 or theme.line_smoothing > 1.0:
            raise Error(
                "Theme.line_smoothing must be in [0.0, 1.0] (got "
                + String(theme.line_smoothing)
                + ")"
            )
        var px = List[Float64](capacity=len(plot.x_data))
        var py = List[Float64](capacity=len(plot.x_data))
        for i in range(len(plot.x_data)):
            px.append(x_scale.to_pixel(plot.x_data[i]))
            py.append(y_scale.to_pixel(plot.y_data[i]))
        var path = _build_line_path(px, py, theme.line_smoothing)
        target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)
    elif plot._mark == Mark.AREA:
        # The same curve mark_line() draws (_build_line_path, `Theme.
        # line_smoothing` included -- no longer LINE-only, see that
        # field's own docstring), but closed down to the zero baseline
        # (y_scale's own domain already guarantees zero is a real point
        # in range -- see _zero_baseline_y_extent) and filled instead
        # of stroked. Only the *top* edge (through the data points)
        # smooths; the bottom edge (the two line_to()s down to and
        # along baseline) is always straight -- baseline is a fixed
        # reference line, not data, so there's nothing for it to curve
        # through, the same reasoning a real chart library's own
        # smoothed-area fill never bends its own flat baseline either.
        if theme.line_smoothing < 0.0 or theme.line_smoothing > 1.0:
            raise Error(
                "Theme.line_smoothing must be in [0.0, 1.0] (got "
                + String(theme.line_smoothing)
                + ")"
            )
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

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


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
            target.draw_line_aa(plot_x0, py, plot_x1, py, theme.gridline_color)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color)

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(plot_x0 - sc.tick_length, py, plot_x0, py, theme.axis_color)
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
        target.draw_line_aa(center_px, plot_y1, center_px, plot_y1 + sc.tick_length, theme.axis_color)
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
    appearance (`mark_color`, `point_radius`, `line_width`, each still
    scaled by that plot's own `Theme.scale` -- see `_Scaled`'s own
    docstring). Each encoding-using `Mark.POINT` layer draws its own
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
    split (see that function's own docstring). Deliberately a
    standalone function, not `_render_generic` itself made to accept
    a list -- the domain/margin/axis logic below is structurally the
    same shape as `_render_generic`'s own continuous-x path, but
    computed across *all* layered plots' data at once rather than
    one plot's own, different enough in where each value comes from
    that threading both through one function would read as two
    functions wearing a trenchcoat; duplicated here instead, matching
    this codebase's general tolerance for a little duplication between
    two near-identical paths over a premature shared abstraction (see
    `_render_bar`'s own docstring for the same reasoning elsewhere).

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
        if not (
            plots[i]._mark == Mark.POINT or plots[i]._mark == Mark.LINE or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): only Mark.POINT/Mark.LINE/Mark.AREA can be layered"
                " (got a different mark -- see the wiki's Backlog for why Mark.BAR/"
                "Mark.ARC aren't supported here yet)"
            )
        if len(plots[i].x_data) != len(plots[i].y_data):
            raise Error(
                "render_layers(): a layered plot's own x and y must have the same"
                " length (got "
                + String(len(plots[i].x_data))
                + " and "
                + String(len(plots[i].y_data))
                + ")"
            )
        var has_color_i = len(plots[i].color_data) > 0
        var has_color_categories_i = len(plots[i].color_categories) > 0
        var has_size_i = len(plots[i].size_data) > 0
        if (has_color_i or has_color_categories_i or has_size_i) and not (plots[i]._mark == Mark.POINT):
            raise Error(
                "render_layers(): color/color_categories/size encoding is only"
                " supported for a layer whose own mark is Mark.POINT (layer "
                + String(i)
                + " uses a different mark)"
            )
        if has_color_i and len(plots[i].color_data) != len(plots[i].x_data):
            raise Error(
                "render_layers(): a layer's own color must be the same length as"
                " its own x/y (layer "
                + String(i)
                + ", got "
                + String(len(plots[i].color_data))
                + " and "
                + String(len(plots[i].x_data))
                + ")"
            )
        if has_color_categories_i and len(plots[i].color_categories) != len(plots[i].x_data):
            raise Error(
                "render_layers(): a layer's own color_categories must be the same"
                " length as its own x/y (layer "
                + String(i)
                + ", got "
                + String(len(plots[i].color_categories))
                + " and "
                + String(len(plots[i].x_data))
                + ")"
            )
        if has_color_i and has_color_categories_i:
            raise Error(
                "render_layers(): a layer's own color and color_categories are"
                " mutually exclusive -- pass one or the other, not both (layer "
                + String(i)
                + ")"
            )
        if has_size_i and len(plots[i].size_data) != len(plots[i].x_data):
            raise Error(
                "render_layers(): a layer's own size must be the same length as"
                " its own x/y (layer "
                + String(i)
                + ", got "
                + String(len(plots[i].size_data))
                + " and "
                + String(len(plots[i].x_data))
                + ")"
            )

    var theme = plots[0]._theme
    target.fill_rect(ox0, oy0, ox1 - ox0, oy1 - oy0, theme.background)

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

    var y_scale = _zero_baseline_y_extent(combined_y) if any_area else _data_extent(combined_y)
    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels()
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    # legend_reserve, computed across every encoding-using Mark.POINT
    # layer before plot_x1 is finalized -- the same "measure the real
    # content before sizing the margin around it" ordering _render_
    # generic's own single-plot legend_reserve already established (see
    # that function's own comment). Each layer's own section width
    # measured with that layer's own _Scaled (font size, swatch size
    # all independently scaled, matching every other per-layer style
    # choice here), `max`'d together into one shared column width --
    # sections stack vertically in one column, so the column's own
    # width is whichever section needs the most room, not a sum.
    var legend_reserve = 0
    for j in range(len(plots)):
        if not (plots[j]._mark == Mark.POINT):
            continue
        var p_theme_j = plots[j]._theme
        if not p_theme_j.show_legend:
            continue
        var p_sc_j = _Scaled(p_theme_j)
        var has_color_j = len(plots[j].color_data) > 0
        var has_color_categories_j = len(plots[j].color_categories) > 0
        var has_size_j = len(plots[j].size_data) > 0
        if has_color_categories_j:
            var domain_j = _unique_categories(plots[j].color_categories)
            legend_reserve = max(
                legend_reserve, _dynamic_legend_width(domain_j, p_sc_j.legend_swatch_size, p_sc_j)
            )
        elif has_color_j:
            var color_mm_j = _min_max(plots[j].color_data)
            var color_labels_j = List[String]()
            color_labels_j.append(_format_fixed(color_mm_j.max, 1))
            color_labels_j.append(_format_fixed(color_mm_j.min, 1))
            legend_reserve = max(
                legend_reserve,
                _dynamic_legend_width(color_labels_j, p_sc_j.continuous_legend_bar_width, p_sc_j),
            )
        if has_size_j:
            var size_mm_j = _min_max(plots[j].size_data)
            var size_labels_j = List[String]()
            size_labels_j.append(_format_fixed(size_mm_j.max, 1))
            size_labels_j.append(_format_fixed((size_mm_j.min + size_mm_j.max) / 2.0, 1))
            size_labels_j.append(_format_fixed(size_mm_j.min, 1))
            var circle_content_width_j = 2 * _round_to_int(p_sc_j.size_range_max)
            legend_reserve = max(
                legend_reserve, _dynamic_legend_width(size_labels_j, circle_content_width_j, p_sc_j)
            )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var x_scale = _data_extent(combined_x)
    x_scale.range_min = Float64(plot_x0)
    x_scale.range_max = Float64(plot_x1)

    y_scale.range_min = Float64(plot_y1)
    y_scale.range_max = Float64(plot_y0)

    var x_ticks = x_scale.ticks()
    var x_labels = x_ticks.labels()

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(x_scale, x_ticks.values[i])
            target.draw_line_aa(px, plot_y0, px, plot_y1, theme.gridline_color)
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(y_scale, y_ticks.values[i])
            target.draw_line_aa(plot_x0, py, plot_x1, py, theme.gridline_color)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color)

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(x_scale, x_ticks.values[i])
        target.draw_line_aa(px, plot_y1, px, plot_y1 + sc.tick_length, theme.axis_color)
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

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(y_scale, y_ticks.values[i])
        target.draw_line_aa(plot_x0 - sc.tick_length, py, plot_x0, py, theme.axis_color)
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

    # legend_y is a running cursor, shared across every encoding-using
    # layer's own section(s) -- the same "each section returns the y
    # just below it for the next to start at" stacking `_render_
    # generic`'s own single-plot legend already uses (see its own
    # comment), just walked once per encoding-using layer here instead
    # of once per plot.
    var legend_y = plot_y0
    for j in range(len(plots)):
        if len(plots[j].x_data) == 0:
            continue
        var p_theme = plots[j]._theme
        var p_sc = _Scaled(p_theme)
        if plots[j]._mark == Mark.POINT:
            var has_color_j = len(plots[j].color_data) > 0
            var has_color_categories_j = len(plots[j].color_categories) > 0
            var has_size_j = len(plots[j].size_data) > 0
            var palette_j = default_categorical_palette() if has_color_categories_j else List[Color]()
            var color_categories_domain_j = (
                _unique_categories(plots[j].color_categories) if has_color_categories_j else List[String]()
            )
            var color_mm_j = _min_max(plots[j].color_data) if has_color_j else MinMax(0.0, 1.0)
            var color_scale_j = ColorScale(color_mm_j.min, color_mm_j.max)
            color_scale_j.add_stop(0.0, p_theme.color_scale_low)
            color_scale_j.add_stop(1.0, p_theme.color_scale_high)
            var size_mm_j = _min_max(plots[j].size_data) if has_size_j else MinMax(0.0, 1.0)
            var size_scale_j = LinearScale(size_mm_j.min, size_mm_j.max, p_sc.size_range_min, p_sc.size_range_max)

            for i in range(len(plots[j].x_data)):
                var px = _axis_pixel(x_scale, plots[j].x_data[i])
                var py = _axis_pixel(y_scale, plots[j].y_data[i])
                var color: Color
                if has_color_j:
                    color = color_scale_j.color_at(plots[j].color_data[i])
                elif has_color_categories_j:
                    var idx = _index_of(color_categories_domain_j, plots[j].color_categories[i])
                    color = palette_j[idx % len(palette_j)]
                else:
                    color = p_theme.mark_color
                var radius = (
                    _round_to_int(size_scale_j.to_pixel(plots[j].size_data[i]))
                    if has_size_j
                    else _round_to_int(p_sc.point_radius)
                )
                target.fill_circle_aa(px, py, radius, color)

            if p_theme.show_legend and (has_color_categories_j or has_color_j or has_size_j):
                var legend_x = plot_x1 + sc.margin_right
                if has_color_categories_j:
                    _draw_legend(
                        target, text_requests, color_categories_domain_j, palette_j, legend_x, legend_y, p_theme
                    )
                    legend_y += len(color_categories_domain_j) * (p_sc.legend_swatch_size + p_sc.legend_row_gap)
                elif has_color_j:
                    legend_y = _draw_continuous_color_legend(
                        target, text_requests, color_scale_j, legend_x, legend_y, p_theme
                    )
                if has_size_j:
                    legend_y = _draw_continuous_size_legend(
                        target, text_requests, size_mm_j, size_scale_j, legend_x, legend_y, p_theme
                    )
        elif plots[j]._mark == Mark.LINE:
            var path = Path()
            path.move_to(x_scale.to_pixel(plots[j].x_data[0]), y_scale.to_pixel(plots[j].y_data[0]))
            for i in range(1, len(plots[j].x_data)):
                path.line_to(x_scale.to_pixel(plots[j].x_data[i]), y_scale.to_pixel(plots[j].y_data[i]))
            target.stroke_path_aa(path, p_theme.mark_color, width=p_sc.line_width)
        elif plots[j]._mark == Mark.AREA:
            var baseline_py = y_scale.to_pixel(0.0)
            var path = Path()
            path.move_to(x_scale.to_pixel(plots[j].x_data[0]), y_scale.to_pixel(plots[j].y_data[0]))
            for i in range(1, len(plots[j].x_data)):
                path.line_to(x_scale.to_pixel(plots[j].x_data[i]), y_scale.to_pixel(plots[j].y_data[i]))
            path.line_to(
                x_scale.to_pixel(plots[j].x_data[len(plots[j].x_data) - 1]), baseline_py
            )
            path.line_to(x_scale.to_pixel(plots[j].x_data[0]), baseline_py)
            path.close()
            target.fill_path_aa(path, p_theme.mark_color)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)
