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
y=ys).theme(t)` -- matches `canvas`'s Path/Canvas builder feel in
spirit, chained rather than one statement per call since that's the
composition style settled on for this package specifically.

`render(canvas, plot)`/`render_svg(svg, plot)` are the two entry
points that turn a Plot into pixels or into SVG markup -- both a
single batch pass, no retained scene graph and no reactive signals
(see dataviz-api-design for why: `canvas` itself has neither, so
there's nothing for either to attach to yet). By default each owns
the whole target it's given (fills the background, computes margins
from `Theme`, plus any extra margin `Plot.labels()`'s chart/axis
titles need -- see `_apply_labels`'s docstring) rather than
compositing into an existing drawing; their optional `ox0`/`oy0`/
`ox1`/`oy1` bounds narrow that to a sub-rectangle instead -- the
mechanism `render_facets()` (small multiples: a grid of independently
laid-out plots on one canvas) composes on top of, without `render()`
itself knowing facets exist.

Both entry points share one generic rendering core (`_render_generic`,
`_render_bar`, `_render_arc` -- each `[T: DrawTarget]`, see canvas/
draw_target.mojo's docstring for what that trait is and why it
exists) for everything except *text*: `DrawTarget` deliberately has no
`draw_text` method (drawing real text needs `canvas_mojo.text`'s native FreeType/fontconfig glyph machinery for the raster path, or
SVG-specific markup for the vector one, and forcing either dependency
onto the other would defeat the point), so text is
collected as a `List[_TextRequest]` while the generic pass runs, then
`render()`/`render_svg()` each draw that list their way once it
returns -- see `_TextRequest`'s docstring.

Every raster draw call the generic core makes through `Canvas` is the
anti-aliased variant -- `fill_circle_aa` for points, `stroke_path_aa`
for lines, `draw_line_aa` for gridlines/axis lines/tick marks -- one
consistent default rather than reasoning per call site about whether
AA is "worth it." For the axis-aligned lines specifically this makes
no visual difference: a perfectly horizontal or vertical,
integer-positioned line has no diagonal stepping for AA to smooth
away in the first place. `SvgCanvas` has no equivalent AA choice to make at all --
an SVG renderer handles that itself, at whatever resolution it's
displayed at (see the wiki's Changelog, its entry for the concrete
problem that motivated adding it).

Per-primitive AA is one layer of that; whole-canvas supersampling is
the other, coarser one -- rendering everything above at several times
its final size, then shrinking back down (see `canvas_mojo.resize.
downsample`'s docstring for the mechanism). `render()` itself
never does this on its own -- see its docstring, and `_rendered`'s,
for exactly where it does and doesn't happen and why.

This file holds only what every mark shares: the `Plot` struct itself
(its methods can't be split across files -- a Mojo struct's methods all have to live with its definition -- so `encode_histogram(
)`/`encode_waterfall()` are thin wrappers that immediately delegate to
a free function living with the rest of that mark's code, the same
way `encode_boxplot()` already delegated to `_box_stats()`), `_render_
generic`'s dispatch, and machinery genuinely shared by several marks
(`_draw_categorical_axis_frame`, legends, labels, scales, facets,
layers). Each mark with its dedicated rendering -- everything but
`Mark.POINT`/`LINE`/`AREA`, which stay inline in `_render_generic`
itself as the plain-continuous-axis default case with no special axis
frame of their own to justify a file -- has exactly one file holding
its `_render_*` plus whatever calculation is specific to it: bar.
mojo, lollipop.mojo, waterfall.mojo, box.mojo, candlestick.mojo,
bullet.mojo, gantt.mojo, grouped_bar.mojo, stacked_bar.mojo, arc.mojo,
histogram.mojo (the last has no `_render_histogram` of its own --
`encode_histogram()`'s binning feeds `Mark.BAR`'s `_render_bar`
unchanged -- so it holds only the binning calculation). These import
`Plot`/the shared machinery back from this file, and this file imports
each mark's `_render_*`/calculation function back from theirs --
a real circular import, which Mojo resolves fine within one package.

## The one-call convenience functions

Alongside its rendering, each of those files also holds that
mark's one-call convenience function -- `bar()` in bar.mojo,
`pie()` in arc.mojo, `waterfall()` in waterfall.mojo, and so on --
with `scatter()`/`line()`/`area()` here in this file, beside the
`Mark.POINT`/`LINE`/`AREA` rendering they wrap. One rule, no
exceptions: a mark's convenience function lives with that mark's code. (These were all one `quickplot.mojo` module before; see the
wiki's Changelog for the move.) Import them from the package itself --
`from dataviz_mojo import bar, scatter` -- not from the mark file
they happen to live in.

Each wraps `Plot`/`Theme`/`Canvas`/`render()` for the common case: a
single chart, one mark, sane defaults for everything that isn't the
data itself. Every one builds a `Theme`, builds a `Canvas` sized to
match, builds a `Plot`, `encode*()`s the data onto it, and `render()`s
into the canvas, in one call (`_rendered()` below is the shared tail
all thirteen delegate that to).

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
builder's vocabulary. Each takes exactly the data shape its `encode*()` counterpart needs (a plain `(x, y)` pair for the
continuous marks, `(categories, values)` for the categorical ones,
and each mark-specific shape beyond that -- `waterfall()`'s `deltas`,
`box()`'s per-category value lists, `candlestick()`'s OHLC columns,
`bullet()`'s measure/target/ranges, `gantt()`'s start/end,
`grouped_bar()`/`stacked_bar()`'s per-series values), plus five
parameters shared across all of them:

- `theme`: a full `Theme`, for every knob these don't surface as
  their parameter (colors beyond `mark_color`, margins, font
  sizes, gridlines, `line_smoothing`, ...) --
  `Theme(mark_color=SEAGREEN)` (see `dataviz_mojo.colors`'s docstring for that constant and every other CSS-named one alongside
  it, or `Color(40, 130, 90)` directly) works exactly as it does
  building a `Plot` by hand; only how it's handed in differs (an
  argument here, instead of a chained `.theme(...)`).
- `width`/`height`: the returned `Canvas`'s pixel size, defaulting to
  640x420 -- the final size of the returned `Canvas`; see `_rendered`'s docstring for the internal supersampling every one of these
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
from canvas_mojo.vector.svg import SvgCanvas, _escape_xml_text, _escape_xml_attr
from canvas_mojo.text.render import draw_text, measure_text, FontWeight, TextAlign
from canvas_mojo.text.font_cache import FontCache

from dataviz_mojo.color_scale import ColorScale, default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.ordinal_scale import OrdinalScale
from dataviz_mojo.scale import LinearScale, MinMax, _format_fixed, _min_max
from dataviz_mojo.theme import Theme

from dataviz_mojo.arc import _render_arc
from dataviz_mojo.nightingale import _render_nightingale
from dataviz_mojo.polar import _render_polar
from dataviz_mojo.polar_bar import _render_polar_bar
from dataviz_mojo.gauge import _render_gauge
from dataviz_mojo.parallel import _render_parallel
from dataviz_mojo.radar import _render_radar
from dataviz_mojo.bar import _render_bar
from dataviz_mojo.beeswarm import _render_beeswarm
from dataviz_mojo.ridgeline import _render_ridgeline
from dataviz_mojo.violin import _render_violin
from dataviz_mojo.waterfall import _WaterfallData
from dataviz_mojo.box import _BoxData
from dataviz_mojo.candlestick import _CandleData
from dataviz_mojo.bullet import _BulletData
from dataviz_mojo.population_pyramid import _PyramidData
from dataviz_mojo.heatmap import _HeatmapData
from dataviz_mojo.polar import _PolarData
from dataviz_mojo.radar import _RadarData
from dataviz_mojo.gauge import _GaugeData
from dataviz_mojo.parallel import _ParallelData
from dataviz_mojo.calendar_heatmap import _CalendarData
from dataviz_mojo.corrplot import _CorrplotData
from dataviz_mojo.punchcard import _PunchcardData
from dataviz_mojo.marimekko import _MarimekkoData
from dataviz_mojo.edges import _EdgeData
from dataviz_mojo.hierarchy import _HierarchyData
from dataviz_mojo.box import _box_stats, _render_box
from dataviz_mojo.bullet import _render_bullet
from dataviz_mojo.candlestick import _render_candlestick
from dataviz_mojo.gantt import _render_gantt
from dataviz_mojo.span_chart import _render_span_chart
from dataviz_mojo.bump import _render_bump
from dataviz_mojo.chord import _render_chord
from dataviz_mojo.funnel import _render_funnel
from dataviz_mojo.grouped_bar import _render_grouped_bar
from dataviz_mojo.heatmap import _render_heatmap
from dataviz_mojo.calendar_heatmap import _render_calendar_heatmap
from dataviz_mojo.corrplot import _render_corrplot
from dataviz_mojo.punchcard import _render_punchcard
from dataviz_mojo.marimekko import _render_marimekko
from dataviz_mojo.sunburst import _render_sunburst
from dataviz_mojo.tree import _render_tree
from dataviz_mojo.treemap import _render_treemap
from dataviz_mojo.arc_diagram import _render_arc_diagram
from dataviz_mojo.graph import _render_graph
from dataviz_mojo.sankey import _render_sankey
from dataviz_mojo.radialbar import _render_radialbar
from dataviz_mojo.histogram import _bin_histogram
from dataviz_mojo.lollipop import _render_lollipop
from dataviz_mojo.single_axis import _render_single_axis
from dataviz_mojo.population_pyramid import _render_population_pyramid
from dataviz_mojo.stacked_bar import _render_stacked_bar
from dataviz_mojo.streamgraph import _render_streamgraph
from dataviz_mojo.waterfall import _render_waterfall, _waterfall_running_totals


# The fixed internal supersampling factor `_rendered()` renders every
# one-call convenience function's raster output at before shrinking it
# back down -- see that function's docstring for the mechanism and
# why it lives only there, not in `render()` itself. Not a `Theme`
# field and not exposed as a parameter anywhere: unlike `Theme.scale`
# (a real, user-visible choice -- render genuinely larger, for a
# viewer that upscales), this one exists purely so quickplot's output
# doesn't look worse than it has to, which isn't a decision a caller
# should need to make or even know is happening. 3x is clearly enough
# finer-grained to matter without a 640x420 chart's scratch canvas
# becoming wasteful; not benchmarked against 2x/4x.
comptime _QUICKPLOT_SUPERSAMPLE = 3


struct _Scaled(Movable):
    """Every pixel-sized quantity render()/_render_bar/_render_arc/
    _draw_legend actually draw with, pre-multiplied by `theme.scale`
    once here -- the single place the "* theme.scale" formula lives,
    so it can't drift between the several render paths that each need
    it (see Theme.scale's docstring for what this is for). Built
    fresh from a Theme at the top of each of those functions; cheap
    (a handful of Float64/Int multiplies), not cached anywhere.

    `scale` itself (the raw multiplier, not multiplied by anything --
    every other field here already *is* the scaled quantity) exists
    for the one place that needs the bare factor rather than something
    pre-multiplied by it: every axis line/gridline/tick mark
    (`draw_line_aa(..., theme.axis_color)`/`(..., theme.gridline_
    color)`) is drawn `width=sc.scale` pixels wide, not the
    library-wide implicit default of a flat 1.0 -- these are the one
    kind of stroke this package draws whose width has no `Theme`
    field of its own to already be scaled by `_Scaled.__init__` above
    (unlike `line_width`, `point_radius`, ...), so without this they'd
    stay exactly 1 raw pixel wide at any `scale`, visibly thinner than
    everything else in a `scale=2.0` render, not "the same chart at
    higher density" the way `Theme.scale`'s docstring promises.
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
    var subtitle_font_size: Float64
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
        self.tick_length = Int(Float64(theme.tick_length) * s)
        self.label_gap = Int(Float64(theme.label_gap) * s)
        self.legend_width = Int(Float64(theme.legend_width) * s)
        self.legend_swatch_size = Int(Float64(theme.legend_swatch_size) * s)
        self.legend_row_gap = Int(Float64(theme.legend_row_gap) * s)
        self.margin_buffer = Int(Float64(theme.margin_buffer) * s)
        self.title_font_size = theme.title_font_size * s
        self.subtitle_font_size = theme.subtitle_font_size * s
        self.axis_title_font_size = theme.axis_title_font_size * s
        self.continuous_legend_bar_width = Int(Float64(theme.continuous_legend_bar_width) * s)
        self.continuous_legend_bar_height = Int(Float64(theme.continuous_legend_bar_height) * s)


struct _GanttData(Movable):
    """
    Mark.GANTT only -- one start/end span per category. See
    encode_gantt()'s docstring.

    Grouped onto `Plot._gantt` -- see `Plot`'s docstring.
    """

    var start: List[Float64]
    var end: List[Float64]

    def __init__(out self):
        self.start = List[Float64]()
        self.end = List[Float64]()


struct _GroupedBarData(Movable):
    """
    Mark.GROUPED_BAR only -- one name per series, one value per (series,
    category) pair. See encode_grouped_bar()'s docstring.

    Grouped onto `Plot._grouped_bar` -- see `Plot`'s docstring.
    """

    var series_names: List[String]
    var values: List[List[Float64]]

    def __init__(out self):
        self.series_names = List[String]()
        self.values = List[List[Float64]]()


struct _DistributionData(Movable):
    """
    Mark.BEESWARM/VIOLIN/RIDGELINE only -- one *list* of raw values per
    category, kept unsummarized (unlike Mark.BOX's encode_boxplot,
    which reduces each category's list to a five-number summary
    immediately). See encode_distribution()'s docstring.

    `kde_bandwidth_override` is a caller's kernel-density-estimate
    bandwidth, overriding each category's Silverman's-rule default
    (0.0 is the sentinel for "use the default", the same
    empty-means-default convention `encode()`'s optional channels
    already use -- a scalar 0.0 here, since a real bandwidth is never
    zero or negative). `kde_scale_by_count` selects ggplot2's `scale = "area"` mode: False (the default) is `scale = "width"`,
    where every category's peak density maps to the same maximum
    width/rise regardless of sample count; True additionally scales
    that maximum by `sqrt(n_i / max(n))`, so a category built from
    fewer points draws visibly narrower. See mark_violin()'s and
    mark_ridgeline()'s docstrings for both.

    Grouped onto `Plot._distribution` -- see `Plot`'s docstring.
    """

    var values: List[List[Float64]]
    var kde_bandwidth_override: Float64
    var kde_scale_by_count: Bool

    def __init__(out self):
        self.values = List[List[Float64]]()
        self.kde_bandwidth_override = 0.0
        self.kde_scale_by_count = False


struct _LabelData(Movable):
    """
    Chart/axis title text, set via .labels() -- see that method's docstring. Empty string means "not set", the same "absent means
    absent" convention every other optional feature here follows.

    Grouped onto `Plot._labels` -- see `Plot`'s docstring.
    """

    var title: String
    var subtitle: String
    var x_title: String
    var y_title: String

    def __init__(out self):
        self.title = ""
        self.subtitle = ""
        self.x_title = ""
        self.y_title = ""


struct _AnnotationData(Movable):
    """
    A horizontal reference line per (value, label) pair, set via
    .annotate_line() -- see that method's docstring. Parallel lists,
    the same "outer list indexes named things" shape RADAR's series_names/series_values use -- callable more than
    once (each call appends, doesn't replace), so a caller wanting both
    an "average" and a "target" line just calls it twice.

    `area_*` is a shaded horizontal band per (y0, y1, label) triple
    from .annotate_area(); `vline_*` a vertical reference line per
    (value, label) pair from .annotate_vline(); `point_*` a single
    labeled point per (x, y, label) triple from .annotate_point().
    Every one keeps the same parallel-lists shape, for the same reason:
    each method is additive and may be called more than once.

    `line_*` (horizontal, an x-independent y value) and `vline_*`
    stay separate fields rather than sharing one list. They aren't
    interchangeable data, so merging them would need a "which axis"
    flag per entry, where separate fields already keep them apart.

    Grouped onto `Plot._annotations` -- see `Plot`'s docstring.
    """

    var line_values: List[Float64]
    var line_labels: List[String]
    var area_y0: List[Float64]
    var area_y1: List[Float64]
    var area_labels: List[String]
    var vline_values: List[Float64]
    var vline_labels: List[String]
    var point_x: List[Float64]
    var point_y: List[Float64]
    var point_labels: List[String]

    def __init__(out self):
        self.line_values = List[Float64]()
        self.line_labels = List[String]()
        self.area_y0 = List[Float64]()
        self.area_y1 = List[Float64]()
        self.area_labels = List[String]()
        self.vline_values = List[Float64]()
        self.vline_labels = List[String]()
        self.point_x = List[Float64]()
        self.point_y = List[Float64]()
        self.point_labels = List[String]()


struct Plot(Movable):
    """One chart's mark, theme, labels and data, built up through the
    fluent `mark_*()`/`encode_*()`/`labels()`/`theme()` chain and
    consumed by `render()` (see this module's docstring for that
    convention).

    Data columns are grouped one struct per mark family rather than
    left loose on this type: each sub-struct's docstring documents its
    own fields, so the documentation sits with the data it describes,
    and a mark's render function only sees its own group's columns,
    not every other mark's.

    `_edges` earns its name particularly: `Mark.CHORD`, `ARC_DIAGRAM`,
    `GRAPH` and `SANKEY` all read the same three columns --
    `_edge_node_index` already resolves that shared shape; this names
    it.

    What stays ungrouped is deliberate: `x_data`/`y_data`/
    `x_categories`/`color_data`/`color_categories`/`size_data` are the
    shared encoding channels many marks read, not any one mark's columns, and `_mark`/`_theme`/`_secondary_axis`/`_nightingale_area`
    are single settings rather than data.
    """

    var x_data: List[Float64]
    var y_data: List[Float64]
    var x_categories: List[String]
    var color_data: List[Float64]
    var color_categories: List[String]
    var size_data: List[Float64]
    var _waterfall: _WaterfallData
    var _box: _BoxData
    var _candle: _CandleData
    var _bullet: _BulletData
    var _gantt: _GanttData
    var _grouped_bar: _GroupedBarData
    var _pyramid: _PyramidData
    var _heatmap: _HeatmapData
    var _edges: _EdgeData
    var _distribution: _DistributionData
    # Mark.NIGHTINGALE only -- which of ECharts' two `rose_type` radius
    # formulas each wedge uses (False = "radius", True = "area"). See
    # mark_nightingale()'s docstring. Ungrouped: a lone mode flag,
    # not a data column.
    var _nightingale_area: Bool
    var _polar: _PolarData
    var _radar: _RadarData
    var _gauge: _GaugeData
    var _parallel: _ParallelData
    var _calendar: _CalendarData
    var _corrplot: _CorrplotData
    var _punchcard: _PunchcardData
    var _marimekko: _MarimekkoData
    var _hierarchy: _HierarchyData
    var _labels: _LabelData
    var _annotations: _AnnotationData
    # Set via .secondary_axis() -- render_layers()/render_layers_svg()
    # only: this layer's y values scale against a second,
    # independent y-domain drawn on the plot's right edge, instead of
    # the shared left-axis domain every other layer is combined into.
    # Meaningless on a standalone plot (render() raises if it's set --
    # there's only one series, nothing for a second axis to pair
    # against).
    var _secondary_axis: Bool
    var _mark: Mark
    var _theme: Theme

    def __init__(out self):
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self.x_categories = List[String]()
        self.color_data = List[Float64]()
        self.color_categories = List[String]()
        self.size_data = List[Float64]()
        self._waterfall = _WaterfallData()
        self._box = _BoxData()
        self._candle = _CandleData()
        self._bullet = _BulletData()
        self._gantt = _GanttData()
        self._grouped_bar = _GroupedBarData()
        self._pyramid = _PyramidData()
        self._heatmap = _HeatmapData()
        self._edges = _EdgeData()
        self._distribution = _DistributionData()
        self._nightingale_area = False
        self._polar = _PolarData()
        self._radar = _RadarData()
        self._gauge = _GaugeData()
        self._parallel = _ParallelData()
        self._calendar = _CalendarData()
        self._corrplot = _CorrplotData()
        self._punchcard = _PunchcardData()
        self._marimekko = _MarimekkoData()
        self._hierarchy = _HierarchyData()
        self._labels = _LabelData()
        self._annotations = _AnnotationData()
        self._secondary_axis = False
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
        every grammar-of-graphics library's behavior; sort the
        data yourself first if that's not the order you want drawn)."""
        self._mark = Mark.LINE
        return self^

    def mark_bar(var self) -> Self:
        """A bar chart: one bar per category, encoded via
        `encode_categorical()` rather than `encode()` -- a bar's
        x-axis is discrete categories, not continuous positions (see
        `encode_categorical()`'s docstring)."""
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
        `_zero_baseline_y_extent` takes for BAR/AREA's baseline."""
        self._mark = Mark.ARC
        return self^

    def mark_nightingale(var self, area: Bool = False) -> Self:
        """A rose/coxcomb chart: one wedge per category, all wedges the
        same angular width -- magnitude encoded by radius instead of
        angle (unlike `mark_arc()`) -- encoded via `encode_categorical()`,
        the same category + value data shape `mark_arc()`/`mark_bar()`
        use. `area=True` scales each wedge's radius by
        `sqrt(value / max)` (ECharts' `rose_type="area"`, wedge *area*
        proportional to value) instead of the default `area=False`
        linear `value / max` scaling (`rose_type="radius"`) -- see
        `_render_nightingale`'s docstring for why the two modes
        read differently. Every value must be non-negative, and at
        least one must be positive -- checked at render() time, the
        same as `mark_arc()`."""
        self._mark = Mark.NIGHTINGALE
        self._nightingale_area = area
        return self^

    def mark_polar_bar(var self) -> Self:
        """A circular column chart: bars radiate outward from the
        chart's center, one equal-width angular slot per category
        (like `mark_nightingale()`'s wedges, but with a small gap
        between bars instead of edge-to-edge sectors) -- encoded via
        `encode_categorical()`, the same category + value data shape
        `mark_arc()`/`mark_bar()`/`mark_nightingale()` use. Bar length
        always scales linearly by `value / max(values)` -- no `area`
        mode the way `mark_nightingale()` has. Every value must be
        non-negative, and at least one must be positive -- checked at
        render() time, the same as `mark_arc()`/`mark_nightingale()`."""
        self._mark = Mark.POLAR_BAR
        return self^

    def mark_radialbar(var self) -> Self:
        """A radial (multi-ring) progress chart: one full concentric
        ring per category, swept clockwise from 12 o'clock over a
        light-gray track to `value / max(values)` of the way around --
        the "activity rings" shape, unlike `mark_polar_bar()`'s bars radiating outward from a shared center. Encoded via
        `encode_categorical()`, the same category + value data shape
        `mark_polar_bar()`/`mark_arc()`/`mark_nightingale()` use. The
        first category draws as the outermost ring. Every value must
        be non-negative, and at least one must be positive -- checked
        at render() time, the same as `mark_polar_bar()`."""
        self._mark = Mark.RADIALBAR
        return self^

    def mark_polar(var self) -> Self:
        """A polar-coordinate line plot: (angle, radius) pairs
        connected in row order, drawn over a polar grid -- encoded via
        `encode_polar()` (one unnamed series) or `encode_polar_series()`
        (several named series sharing one angle domain), not
        `encode()`/`encode_categorical()` (a polar plot's two
        channels are an angle and a radius, not an x/y position or a
        category + value). See `_render_polar`'s docstring for the
        full reasoning, including why `angle` is never wrapped `mod
        2*pi`."""
        self._mark = Mark.POLAR
        return self^

    def mark_radar(var self) -> Self:
        """A radar/spider chart: one spoke per named indicator, one
        polygon per named series -- encoded via `encode_radar()`, not
        `encode()`/`encode_categorical()` (see that method's docstring for the full shape)."""
        self._mark = Mark.RADAR
        return self^

    def mark_gauge(var self) -> Self:
        """A gauge chart: a single value shown as a needle over a
        color-banded dial (bands customizable via `encode_gauge()`'s `breakpoints`/`band_colors`) -- encoded via `encode_gauge()`,
        not `encode()`/`encode_categorical()` (see that method's docstring for the full shape)."""
        self._mark = Mark.GAUGE
        return self^

    def mark_parallel(var self) -> Self:
        """A parallel-coordinates chart: one row drawn as a polyline
        across evenly spaced, independently scaled vertical axes, one
        per dimension -- encoded via `encode_parallel()`, not
        `encode()`/`encode_categorical()` (see that method's docstring for the full shape)."""
        self._mark = Mark.PARALLEL
        return self^

    def mark_lollipop(var self) -> Self:
        """A lollipop chart: one stem-plus-point per category, encoded
        via `encode_categorical()` -- exactly `mark_bar()`'s data
        shape (a bar chart and a lollipop chart differ only in how each
        category's magnitude is drawn, a filled rect vs. a thin stem
        with a point at its end, not in what the underlying data
        means)."""
        self._mark = Mark.LOLLIPOP
        return self^

    def mark_waterfall(var self) -> Self:
        """A waterfall chart: one floating bar per category, each
        running from the previous bar's cumulative total to the
        next -- encoded via `encode_waterfall()` (a category + a
        *signed delta*, not `encode_categorical()`'s plain value; see
        that method's docstring)."""
        self._mark = Mark.WATERFALL
        return self^

    def mark_box(var self) -> Self:
        """A box plot: one box-and-whiskers per category, summarizing
        a whole distribution of raw values -- encoded via
        `encode_boxplot()` (a category + a *list* of values, not
        `encode_categorical()`'s single number per category; see that
        method's docstring for the quartile/whisker/outlier
        computation it does immediately, not deferred to render()
        time)."""
        self._mark = Mark.BOX
        return self^

    def mark_candlestick(var self) -> Self:
        """A candlestick chart: one open/high/low/close bar per
        category (a trading period, typically), encoded via `encode_
        candlestick()` -- a category plus four values, not `encode_
        categorical()`'s single value (see that method's docstring)."""
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
        """A gantt chart: one horizontal bar per category, from a
        start value to an end value, encoded via `encode_gantt()` --
        categories run along the *y*-axis instead of the x-axis (see
        that method's docstring). See `mark_
        span_chart()` for the same data, drawn vertically instead."""
        self._mark = Mark.GANTT
        return self^

    def mark_span_chart(var self) -> Self:
        """A span chart: `mark_gantt()`'s mirror image -- one
        floating *vertical* bar per category, from a low value to a
        high value, on the normal categorical x-axis instead of
        `Mark.GANTT`'s horizontal one. Encoded via `encode_gantt()`,
        the exact same category + start + end shape, completely
        unchanged -- only the orientation this renders it in
        differs."""
        self._mark = Mark.SPAN_CHART
        return self^

    def mark_calendar_heatmap(var self) -> Self:
        """A calendar heatmap: daily values laid out in a GitHub-
        contributions-style calendar grid, colored through a
        continuous gradient -- encoded via `encode_calendar()`, not
        `encode()`/`encode_categorical()` (see that method's docstring for the exact shape, including the plain
        `"YYYY-MM-DD"` date format)."""
        self._mark = Mark.CALENDAR_HEATMAP
        return self^

    def mark_corrplot(var self, layout: String = "full", diag: Bool = True, labels: Bool = True) -> Self:
        """A correlation plot: one bubble per cell of a square
        correlation matrix, sized/colored by strength and sign --
        encoded via `encode_corrplot()`, not `encode()`/`encode_
        categorical()`. `layout` ("full"/"lower"/"upper") and `diag`
        control which cells draw at all -- see `_render_corrplot`'s docstring for what each means."""
        self._mark = Mark.CORRPLOT
        self._corrplot.layout = layout
        self._corrplot.diag = diag
        self._corrplot.labels = labels
        return self^

    def mark_punchcard(var self, scale: Float64 = 10.0) -> Self:
        """A punchcard: a scatter plot on a categorical grid where
        bubble size encodes a third variable -- encoded via `encode_
        punchcard()`. `scale` (default 10.0, matching ECharts.jl's keyword) is the plain pixel-space divisor each bubble's radius comes from (`size / scale`) -- see `_render_punchcard`'s docstring for why this isn't normalized to the cell size
        the way `mark_corrplot()`'s bubbles are."""
        self._mark = Mark.PUNCHCARD
        self._punchcard.scale = scale
        return self^

    def mark_marimekko(var self) -> Self:
        """A Marimekko/mosaic chart: column widths proportional to
        each category's share of the grand total, stacked segment
        heights showing each column's subcategory composition --
        encoded via `encode_marimekko()`, not `encode()`/`encode_
        categorical()`/`encode_grouped_bar()` (see that method's docstring for the full shape)."""
        self._mark = Mark.MARIMEKKO
        return self^

    def mark_sunburst(var self) -> Self:
        """A sunburst chart: a hierarchy laid out as concentric rings,
        one ring per depth level, each node's angular span
        proportional to its share of its parent's total --
        encoded via `encode_hierarchy()`, not `encode()`/`encode_
        categorical()` (see that method's docstring for the exact
        shape)."""
        self._mark = Mark.SUNBURST
        return self^

    def mark_tree(var self) -> Self:
        """A tree diagram: a hierarchy laid out top-to-bottom as a
        node-link diagram -- encoded via `encode_hierarchy()`, the
        same shape `mark_sunburst()` uses (see that method's docstring)."""
        self._mark = Mark.TREE
        return self^

    def mark_treemap(var self) -> Self:
        """A treemap: a hierarchy laid out as nested, area-proportional
        rectangles via slice-and-dice -- encoded via `encode_hierarchy()`,
        the same shape `mark_sunburst()`/`mark_tree()` use (see that
        method's docstring)."""
        self._mark = Mark.TREEMAP
        return self^

    def mark_grouped_bar(var self) -> Self:
        """A grouped bar chart: several bars side by side per category,
        one per series, encoded via `encode_grouped_bar()` -- a category
        plus a name and a value *per series*, not `encode_categorical()`'s
        single value."""
        self._mark = Mark.GROUPED_BAR
        return self^

    def mark_stacked_bar(var self) -> Self:
        """A stacked bar chart: one bar per category, each series' value stacked as a segment on top of the previous one's running total, instead of `Mark.GROUPED_BAR`'s side-by-side
        sub-bars -- encoded via the exact same `encode_grouped_bar()`,
        no separate encode method needed (the data is identical; only
        the rendering differs, the same relationship `Mark.LOLLIPOP`
        already has to `Mark.BAR`'s `encode_categorical()`)."""
        self._mark = Mark.STACKED_BAR
        return self^

    def mark_population_pyramid(var self) -> Self:
        """A population pyramid: two magnitude bars per category,
        growing outward left/right from a shared, always-centered zero
        baseline -- encoded via `encode_population_pyramid()`. `Mark.
        GANTT`'s horizontal-categories-along-y layout, reused
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
        an edge list's `from`/`to` columns, connected by ribbons
        sized by each flow's value -- encoded via `encode_chord()`.
        No x/y axis frame at all, the same as `Mark.ARC`, whose ring-
        sector conventions this reuses directly."""
        self._mark = Mark.CHORD
        return self^

    def mark_arc_diagram(var self) -> Self:
        """An arc diagram: `mark_chord()`'s edge list, drawn as
        nodes on one line connected by semicircular arcs instead of a
        circular ribbon diagram -- encoded via `encode_chord()`, the
        exact same shape (see that method's docstring)."""
        self._mark = Mark.ARC_DIAGRAM
        return self^

    def mark_graph(var self) -> Self:
        """A network graph: `mark_chord()`'s edge list, drawn as
        nodes evenly spaced around a circle connected by straight
        lines instead of a circular ribbon diagram -- encoded via
        `encode_chord()`, the exact same shape (see that method's docstring)."""
        self._mark = Mark.GRAPH
        return self^

    def mark_sankey(var self) -> Self:
        """A Sankey diagram: `mark_chord()`'s edge list, laid out
        left-to-right by column and drawn as proportionally sized flow
        ribbons instead of a circular ribbon diagram -- encoded via
        `encode_chord()`, the exact same shape (see that method's docstring). The edges must form a DAG (no cycles)."""
        self._mark = Mark.SANKEY
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
        static equivalent of ECharts' animated-ripple effect
        scatter (see `_draw_point_layer`'s `draw_halo` paragraph in
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
        """A bump chart: one line per series tracking its rank (1 =
        highest value) among every series at each category, not its raw
        value -- encoded via `encode_grouped_bar()`, the exact same data
        `mark_grouped_bar()`/`mark_stacked_bar()` use."""
        self._mark = Mark.BUMP
        return self^

    def mark_streamgraph(var self) -> Self:
        """A streamgraph: `mark_stacked_bar()`'s running-total
        stack, floated centered around zero instead of sitting on a
        fixed baseline, drawn as flowing bands instead of discrete
        rects -- encoded via `encode_grouped_bar()`, the exact same
        data `mark_grouped_bar()`/`mark_stacked_bar()`/`mark_bump()`
        use."""
        self._mark = Mark.STREAMGRAPH
        return self^

    def mark_beeswarm(var self) -> Self:
        """A beeswarm plot: one point per raw value, jittered sideways
        within its category's band to avoid overlap -- encoded via
        `encode_distribution()`, the same data `mark_violin()`/`mark_
        ridgeline()` will use."""
        self._mark = Mark.BEESWARM
        return self^

    def mark_violin(var self, bandwidth: Float64 = 0.0, scale_by_count: Bool = False) -> Self:
        """A violin plot: a symmetric kernel-density-estimate
        silhouette per category -- encoded via `encode_distribution()`,
        the same data `mark_beeswarm()`/`mark_ridgeline()` use.

        `bandwidth` overrides every category's kernel-density-
        estimate bandwidth (left at its default `0.0`, each category
        gets its Silverman's-rule bandwidth computed from its std/n -- see `_kde_bandwidth()` in violin.mojo). A caller-given
        `bandwidth` applies identically to every category instead --
        useful for comparing several categories' *shapes* without a
        wider- or narrower-spread category also reading as smoother or
        spikier purely from Silverman's rule reacting to its sample size, not the underlying distribution. Must be positive
        (checked at render() time, the same deferred-validation stance
        every other value-validated mark here takes) -- zero or
        negative has no kernel width to mean.

        `scale_by_count` (default `False`, ggplot2's `scale =
        "width"`) additionally scales each category's maximum
        width by `sqrt(n_i / max(n))` when `True` (ggplot2's `scale = "area"`) -- a category built from fewer raw values
        draws visibly narrower, instead of every category's peak
        mapping to the identical maximum width regardless of how many
        points went into it. Mirrors `mark_nightingale(area=...)`'s
        boolean toggle, applied here to sample size instead of
        `NIGHTINGALE`'s value magnitude."""
        self._mark = Mark.VIOLIN
        self._distribution.kde_bandwidth_override = bandwidth
        self._distribution.kde_scale_by_count = scale_by_count
        return self^

    def mark_ridgeline(var self, bandwidth: Float64 = 0.0, scale_by_count: Bool = False) -> Self:
        """A ridgeline plot: one overlapping kernel-density-estimate
        row per category, top to bottom -- encoded via `encode_
        distribution()`, the same data `mark_beeswarm()`/`mark_violin()`
        use. `bandwidth`/`scale_by_count` are the same optional
        Silverman's-rule override / ggplot2 `scale = "area"` toggle
        `mark_violin()`'s parameters of the same names are (applied
        to each row's maximum rise instead of width) -- see that
        method's docstring."""
        self._mark = Mark.RIDGELINE
        self._distribution.kde_bandwidth_override = bandwidth
        self._distribution.kde_scale_by_count = scale_by_count
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
        `x`/`y`'s length match is: encode() itself has no way to
        raise partway through a fluent chain without breaking the
        chain for every caller who *did* pass matching lengths).
        Omitting all three (the default, empty lists) means "use
        Theme's flat `mark_color`/`point_radius`" -- the exact
        pre-existing behavior, unchanged, for every caller who doesn't
        need a data-driven channel.

        `color` (continuous, `List[Float64]`, mapped through a
        `ColorScale` spanning the column's [min, max]) and
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
        render()'s check. A per-segment color/width gradient along
        a `Mark.LINE` is a real, fancier feature, not silently
        approximated by reusing the scatter-point machinery.

        For a categorical x-axis (`Mark.BAR`), use
        `encode_categorical()` instead -- this method's `x`
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
        bands), not continuous positions the way `encode()`'s `x`
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
        `encode_categorical()` does (a bin's range, formatted, as
        its category label; its count as the value) -- for `Mark.BAR`,
        the same as `encode_categorical()` itself; a histogram *is* a
        bar chart, just one whose categories are computed from
        continuous data instead of given directly. No `_render_
        histogram` of its own -- `Mark.BAR`'s `_render_bar` (see
        bar.mojo) draws whatever this method produces unchanged.

        Unlike `encode()`'s x/y length checks (deferred to
        render() time, see that method's docstring for why), the
        binning itself has to happen right here to produce any x/y
        data at all, so this raises immediately on `data` that can't
        be binned meaningfully -- see `_bin_histogram()`'s docstring (histogram.mojo) for the exact binning algorithm
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
        `Mark.WATERFALL`'s floating-bar shape: `deltas[i]` is how
        much the running total changes at category `i`, not the bar's absolute height the way `encode_categorical()`'s `y` is for
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
        running_totals()`'s docstring (waterfall.mojo) for exactly
        what that changes about how a row draws, and `examples/
        waterfall.mojo` for the conventional start-then-deltas-then-end
        shape it enables.

        Unlike `encode_histogram()`'s binning, this never needs to
        raise immediately: a running sum is well-defined for any
        (possibly empty) list of deltas, with no degenerate-span case
        the way binning has -- `categories`/`deltas` length matching is
        still checked, but deferred to render() time like `encode_
        categorical()`'s x/y, for the same reason (see that
        method's docstring). `is_total`, if non-empty, must also
        match `categories`' length -- checked the same deferred way.

        `deltas` itself is kept as this Plot's `y_data` (not just
        the derived `y0`/`y1` bounds) so `_render_waterfall` can still
        color each non-total bar by its delta's sign -- see `Theme.
        mark_color_negative`'s docstring; unlike `Mark.BAR`, a
        waterfall chart colors by sign unconditionally, not gated by
        `Theme.color_by_sign`, since that coloring *is* what a
        waterfall chart conventionally shows, not an opt-in extra. A
        total row's `deltas[i]` is stored the same way but never
        read for coloring -- see `Theme.waterfall_total_color`'s docstring for what colors a total bar instead.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = deltas.copy()
        self._waterfall.is_total = is_total.copy()
        var bars = _waterfall_running_totals(deltas, is_total)
        self._waterfall.y0 = bars.y0.copy()
        self._waterfall.y1 = bars.y1.copy()
        return self^

    def encode_boxplot(var self, categories: List[String], values: List[List[Float64]]) raises -> Self:
        """Map a category column and, per category, a *list* of raw
        values onto `Mark.BOX`'s box-and-whiskers shape: unlike
        every other `encode_*` here, each category's "y" isn't one
        number but a whole distribution, summarized immediately (not
        deferred to render() time) into a five-number summary --
        quartiles via linear interpolation (the same method `numpy.
        percentile`'s default, `"linear"`, uses, so results match
        what a caller could independently verify) -- plus every
        outlier beyond the conventional 1.5*IQR fence, via `_box_stats()`
        (see its docstring, box.mojo, for the exact algorithm).

        Raises immediately, the same "can't produce a coherent result
        at all, not merely a length mismatch" reasoning `encode_
        histogram()`'s binning raises for: a mismatched `categories`/
        `values` length, or any category whose value list is empty
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
        self._box.q1 = q1^
        self._box.median = median^
        self._box.q3 = q3^
        self._box.low = low^
        self._box.high = high^
        self._box.outlier_cat = outlier_cat^
        self._box.outlier_value = outlier_value^
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
        CANDLESTICK`'s wick-plus-body shape -- a category plus
        *four* numbers, not `encode_categorical()`'s single value.

        Unlike `encode_boxplot()`/`encode_histogram()`, nothing here
        needs computing up front (no summary statistic, no binning --
        every value is drawn exactly as given), so length checking is
        deferred to render() time, the same as `encode_categorical()`/
        `encode_waterfall()` (see either's docstring for why: this
        method has no way to raise partway through a fluent chain
        without breaking it for callers who *did* pass matching
        lengths).
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._candle.open_price = open.copy()
        self._candle.high = high.copy()
        self._candle.low = low.copy()
        self._candle.close_price = close.copy()
        return self^

    def encode_bullet(
        var self,
        categories: List[String],
        measures: List[Float64],
        targets: List[Float64],
        ranges: List[List[Float64]],
    ) -> Self:
        """Map a category column plus three more columns onto `Mark.
        BULLET`'s composite shape: `measures` (the actual value,
        drawn as a narrower bar), `targets` (a comparison value, drawn
        as a tick mark), and `ranges` (per category, an ascending list
        of qualitative-range thresholds -- e.g. `[50.0, 75.0, 100.0]`
        for a conventional poor/satisfactory/good split -- drawn as
        shaded background bands from 0 up to each threshold in turn).

        Like `encode_candlestick()`, nothing here needs computing up
        front (every value is drawn exactly as given), so length
        checking -- `categories`/`measures`/`targets`/`ranges` all the
        same length, and each category's `ranges` entry non-empty
        and non-decreasing (the band-stacking math in `_render_bullet`
        depends on that order) -- is deferred to `render()` time, the
        same as every other categorical `encode_*` here (see `encode_
        categorical()`'s docstring for why).
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._bullet.measure = measures.copy()
        self._bullet.target = targets.copy()
        self._bullet.ranges = ranges.copy()
        return self^

    def encode_gantt(var self, categories: List[String], start: List[Float64], end: List[Float64]) -> Self:
        """Map a category column and two continuous value columns
        (`start`/`end`) onto `Mark.GANTT`'s horizontal-span shape --
        a category plus a range, not `encode_categorical()`'s single
        value. Deliberately plain `Float64`, the same as every other
        `encode_*` here, not a dedicated date/time type -- this whole
        package has no `Date`/`Time` type anywhere (see dataviz-api-
        design's "plain columnar arrays are the whole data model"
        decision), so a project schedule's dates are just numbers
        here (day-of-year, a Unix timestamp, whatever a caller's data already uses) the same way every other numeric column in
        this package is -- which is also exactly why this mark doubles
        as a generic "span chart" for any numeric start/end range per
        category, not something scheduling-specific.

        Like `encode_candlestick()`, nothing needs computing up front,
        so length checking (`categories`/`start`/`end` all the same
        length) is deferred to `render()` time, the same as every other
        categorical `encode_*` here. `start[i] > end[i]` isn't checked
        or rejected either -- `_render_gantt` draws from `min(start[i],
        end[i])` to `max(...)`, the same "use min/max rather than
        assume an order" tolerance `Mark.CANDLESTICK`'s open/close
        handling has, so a reversed pair still renders
        sensibly rather than raising over what's likely just a data
        convention difference, not an error.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._gantt.start = start.copy()
        self._gantt.end = end.copy()
        return self^

    def encode_grouped_bar(
        var self,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
    ) -> Self:
        """Map a category column plus *several* value series onto
        `Mark.GROUPED_BAR`'s side-by-side-bars-per-category shape --
        `values[j]` is series `series_names[j]`'s value for every
        category (so `values[j][i]` is series `j`'s value for `categories
        [i]`), the same "outer list indexes the thing being repeated,
        inner list indexes categories" shape `encode_boxplot()` uses
        for a *distribution* per category -- here it's a
        *series* per category instead.

        Nothing needs computing up front, so length checking (`series_
        names`/`values` the same length, and every `values[j]` the same
        length as `categories`) is deferred to `render()` time, the same
        as every other categorical `encode_*` here.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._grouped_bar.series_names = series_names.copy()
        self._grouped_bar.values = values.copy()
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
        `Mark.POPULATION_PYRAMID`'s mirrored-bars shape --
        `left_values[i]`/`right_values[i]` are each drawn as a bar
        growing outward from a shared, always-centered zero baseline
        for `categories[i]` (the classic age-band-by-sex layout, but
        generic: any two magnitudes worth comparing side by side per
        category). Both are read as non-negative magnitudes regardless
        of sign (`_render_population_pyramid` takes `max(v, -v)`, the
        same "use the shape that makes sense rather than raise over a
        likely data-convention difference" tolerance `Mark.GANTT`'s `start > end` handling has) -- a caller with genuinely
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
        self._pyramid.left = left_values.copy()
        self._pyramid.right = right_values.copy()
        self._pyramid.left_name = left_name
        self._pyramid.right_name = right_name
        return self^

    def encode_heatmap(var self, x: List[String], y: List[String], value: List[Float64]) -> Self:
        """Map two category columns plus a continuous value column onto
        `Mark.HEATMAP`'s grid-cell shape -- one row per cell (`x[i]`,
        `y[i]`, `value[i]`), not a separate axis-category list: each
        axis's domain is derived from `x`/`y` themselves (their
        distinct values in first-seen order, via `_categorical_indices`
        at render() time -- the same helper `Plot.encode()`'s `color_categories` channel resolves its domain through),
        the same "the data already says what the axis needs" shape
        `encode_categorical()` uses for a single categorical
        axis, generalized to two.

        A caller need not give every (x, y) combination -- a missing
        cell simply isn't drawn (see `_render_heatmap`'s docstring
        for why that's not treated as an error or a zero).

        Nothing needs computing up front, so length checking (`x`/`y`/
        `value` all the same length) is deferred to `render()` time,
        the same as every other categorical `encode_*` here.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._heatmap.x = x.copy()
        self._heatmap.y = y.copy()
        self._heatmap.value = value.copy()
        return self^

    def encode_calendar(var self, dates: List[String], values: List[Float64]) -> Self:
        """Map a date column and a continuous value column onto `Mark.
        CALENDAR_HEATMAP`'s shape: one row per day (`dates[i]`, a
        plain `"YYYY-MM-DD"` string -- this package deliberately has
        no Date/Time type of its own, the same stance `encode_gantt()`
        takes; parsed only for calendar-grid placement math,
        see calendar_heatmap.mojo's `_parse_date`/`_days_from_
        civil`) and `values[i]`, colored through the same continuous
        gradient `encode_heatmap()`'s `value` channel uses.

        Every date must fall in the same calendar year -- checked at
        render() time (inferred from the first date, not a separate
        `year` parameter), along with the usual `dates`/`values`
        length match. See `_render_calendar_heatmap`'s docstring
        for why this differs from ECharts.jl's explicit `year`
        argument.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._calendar.dates = dates.copy()
        self._calendar.values = values.copy()
        return self^

    def encode_corrplot(var self, variables: List[String], matrix: List[List[Float64]]) -> Self:
        """Map a variable-name list and a square correlation `matrix`
        onto `Mark.CORRPLOT`'s shape: `matrix[row][col]` is the
        correlation between `variables[row]` and `variables[col]` --
        one row per variable, one value per variable within each row
        (checked at render() time, along with every value falling in
        `[-1.0, 1.0]`, the same deferred-validation stance every other
        `encode_*` here takes)."""
        self._corrplot.variables = variables.copy()
        self._corrplot.matrix = matrix.copy()
        return self^

    def encode_punchcard(var self, x: List[String], y: List[String], sizes: List[Float64]) -> Self:
        """Map two category columns plus a continuous size column onto
        `Mark.PUNCHCARD`'s grid-cell-plus-bubble shape -- the same
        `x`/`y` domain-derivation `encode_heatmap()` uses
        (`_categorical_indices` at render() time, first-
        seen order), `sizes` in place of that method's `value`.
        Unlike `encode_heatmap()`, a repeated `(x, y)` pair is not
        deduplicated or merged -- each row draws its independent
        bubble (see `_render_punchcard`'s docstring).

        Length checking (`x`/`y`/`sizes` all the same length, `sizes`
        all non-negative) is deferred to render() time, the same as
        every other categorical `encode_*` here.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._punchcard.x = x.copy()
        self._punchcard.y = y.copy()
        self._punchcard.sizes = sizes.copy()
        return self^

    def encode_marimekko(
        var self, categories: List[String], subcategories: List[String], values: List[List[Float64]]
    ) -> Self:
        """Map `Mark.MARIMEKKO`'s shape onto its three channels:
        `categories` (one column each), `subcategories` (one stacked
        segment each), and `values` -- `values[i][j]` is `subcategories
        [i]`'s value for `categories[j]` (rows are subcategories,
        columns are categories, matching ECharts.jl's `marimekko()`
        matrix convention -- the opposite orientation from `encode_
        grouped_bar()`'s `series_values[series][category]`, kept
        deliberately matched to the reference library here rather than
        this package's usual convention, since there's no data-
        shape reason to prefer one over the other and matching the
        library callers may already know reduces surprise more).

        Length checking (`values` has one row per subcategory, each
        row one value per category, every value non-negative) is
        deferred to render() time, the same as every other categorical
        `encode_*` here.
        """
        self._marimekko.categories = categories.copy()
        self._marimekko.subcategories = subcategories.copy()
        self._marimekko.values = values.copy()
        return self^

    def encode_hierarchy(var self, ids: List[String], parent_ids: List[String], values: List[Float64]) -> Self:
        """Map a flattened hierarchy onto `Mark.SUNBURST`/`TREE`/
        `TREEMAP`'s shared shape: one row per node, `ids[i]` its name, `parent_ids[i]` its parent's `id` (empty string
        `""` for the single root -- the same `d3.stratify()`-style
        flattening `hierarchy.mojo`'s module docstring explains),
        `values[i]` its magnitude if it's a leaf (an internal
        node's displayed value is always its descendant leaves' sum instead, computed at render() time -- see `_build_
        hierarchy_index`'s docstring).

        Length checking (`ids`/`parent_ids`/`values` all the same
        length), the single-root/no-duplicate-id/every-parent-id-
        resolves validation, and the non-negative-values check are all
        deferred to render() time, the same as every other categorical
        `encode_*` here.
        """
        self._hierarchy.ids = ids.copy()
        self._hierarchy.parent_ids = parent_ids.copy()
        self._hierarchy.values = values.copy()
        return self^

    def encode_chord(
        var self, from_categories: List[String], to_categories: List[String], values: List[Float64]
    ) -> Self:
        """Map an edge list onto `Mark.CHORD`'s ring-sectors-plus-
        ribbons shape: one row per flow (`from_categories[i]` to `to_
        categories[i]`, magnitude `values[i]`) -- every distinct name
        across *both* columns becomes one node (`_edge_node_index`
        over the two concatenated at render() time, first-seen order,
        `from_categories` first -- see that function's docstring),
        not a separate node list; the same
        "the data already says what's needed" shape `encode_heatmap()`'s two-categorical-axis domain derivation uses,
        generalized from a grid to a graph.

        `values` must be non-negative (checked at render() time, along
        with the usual length match, the same as every other categorical
        `encode_*` here) -- a negative flow has no ribbon-width meaning,
        the same reasoning `encode_categorical()`'s `Mark.ARC` path
        gives for rejecting negative wedge values.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._edges.from_categories = from_categories.copy()
        self._edges.to_categories = to_categories.copy()
        self._edges.values = values.copy()
        return self^

    def encode_polar(var self, angle: List[Float64], radius: List[Float64]) -> Self:
        """Map an angle column (radians) and a radius column onto
        `Mark.POLAR`'s two channels -- one point per row, connected
        in the given row order (not sorted by angle -- the same "the
        caller's order is the order drawn" stance `mark_line()`'s docstring takes, and the only order that lets a
        spiral -- `angle` values beyond `2*pi` -- draw correctly at
        all). A single, unnamed series -- no legend, since there's
        nothing to key one by (see `encode_polar_series()` for several
        named series sharing one polar grid instead).

        `angle`/`radius` length match and `radius`'s non-negative
        requirement are both checked at render() time, not here -- the
        same "encode() itself can't raise partway through a fluent
        chain" reasoning `encode()`'s docstring gives.
        """
        self._polar.angle = angle.copy()
        self._polar.radius = radius.copy()
        self._polar.series_names = List[String]()
        self._polar.series_radius = List[List[Float64]]()
        return self^

    def encode_polar_series(
        var self, angle: List[Float64], series_names: List[String], series_values: List[List[Float64]]
    ) -> Self:
        """Map a shared angle column (radians) plus one or more named
        series onto `Mark.POLAR`'s two channels -- the multi-series
        generalization of `encode_polar()` (which stays the plain
        single-unnamed-series entry point, the same relationship
        `encode_grouped_bar()` has alongside `encode_categorical()`),
        for comparing several traces on one shared
        polar grid instead of drawing just one.

        Every series shares the same `angle` domain and the same
        radius scale (`max(radius)` computed across *every* series
        together, not each independently -- so equal-magnitude points
        in different series draw at the same radius, the comparison a
        multi-series chart is for) -- unlike `Mark.RADAR`'s per-indicator independent max, since a polar angle axis (unlike
        radar's discrete named indicators) is one continuous domain
        every series is a reading *of*, not a separate dimension with
        its natural scale.

        `series_values[i]` must be the same length as `angle` for every
        series, and every value non-negative -- both checked at
        render() time, the same deferred-validation stance every other
        encode method here takes.
        """
        self._polar.angle = angle.copy()
        self._polar.radius = List[Float64]()
        self._polar.series_names = series_names.copy()
        self._polar.series_radius = series_values.copy()
        return self^

    def encode_radar(
        var self,
        indicators: List[String],
        max_values: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises -> Self:
        """Map `Mark.RADAR`'s shape onto its four channels: one
        named axis per `indicators` entry (each with its `max_values[i]`, since a radar chart's whole point is
        comparing differently-scaled dimensions on one shared-looking
        grid -- unlike `encode_polar()`'s single shared radius domain),
        and one named series per `series_names` entry, each a *list*
        of values in `series_values` -- one value per indicator, the
        same "outer list indexes categories, inner list is that
        category's numbers" shape `encode_distribution()` uses,
        but here the inner list's length is fixed
        (one value per indicator) rather than an arbitrary raw
        distribution.

        Raises immediately (the same "can't produce a coherent result
        at all" reasoning `encode_distribution()`'s checks give, generalized to four lists instead of two) on any length
        mismatch: `indicators`/`max_values`, `series_names`/`series_
        values`, or any individual series whose value count
        doesn't match `indicators`'s count.
        """
        if len(indicators) != len(max_values):
            raise Error(
                "Plot.encode_radar(): indicators and max_values must have the same length"
                " (got "
                + String(len(indicators))
                + " and "
                + String(len(max_values))
                + ")"
            )
        if len(series_names) != len(series_values):
            raise Error(
                "Plot.encode_radar(): series_names and series_values must have the same length"
                " (got "
                + String(len(series_names))
                + " and "
                + String(len(series_values))
                + ")"
            )
        for values in series_values:
            if len(values) != len(indicators):
                raise Error(
                    "Plot.encode_radar(): every series in series_values must have one value per"
                    " indicator (expected "
                    + String(len(indicators))
                    + ", got "
                    + String(len(values))
                    + ")"
                )
        self._radar.indicators = indicators.copy()
        self._radar.max_values = max_values.copy()
        self._radar.series_names = series_names.copy()
        self._radar.series_values = series_values.copy()
        return self^

    def encode_gauge(
        var self,
        value: Float64,
        min_value: Float64 = 0.0,
        max_value: Float64 = 100.0,
        breakpoints: List[Float64] = List[Float64](),
        band_colors: List[Color] = List[Color](),
    ) -> Self:
        """Map a single reading onto `Mark.GAUGE`'s dial: `value`
        (clamped to `[min_value, max_value]` at render() time, not
        rejected -- see `_render_gauge`'s docstring for why an
        out-of-range value pins visibly at the end of the dial instead
        of raising) against a `[min_value, max_value]` range (default
        `[0, 100]`, a plain percentage-style gauge -- ECharts.jl's default too). `min_value < max_value` is checked at render()
        time, the same deferred-validation stance every other encode
        method here takes.

        `breakpoints`/`band_colors` together replace the dial's color-banded background -- `breakpoints` an ascending list of
        fractions of the full `[min_value, max_value]` span (e.g.
        `[0.5, 1.0]` for a two-band low/high split), `band_colors` one
        color per band, same length. Left at their defaults (both
        empty -- the same empty-list-is-a-sentinel convention `encode()`'s `color`/`size` channels use), this reproduces
        ECharts' fixed 20%/80%/100% green/blue/red default exactly,
        unchanged (see `_gauge_breakpoints()`/`_gauge_band_colors()` in
        gauge.mojo, still what every default call ultimately draws) --
        the same "purely additive" guarantee every other optional
        feature in this package makes. Length-matching and ascending-
        order validation (when non-default) is deferred to render()
        time, the same as everything else here.
        """
        self._gauge.value = value
        self._gauge.min_value = min_value
        self._gauge.max_value = max_value
        self._gauge.breakpoints = breakpoints.copy()
        self._gauge.band_colors = band_colors.copy()
        return self^

    def encode_parallel(
        var self, dims: List[String], row_names: List[String], data: List[List[Float64]]
    ) raises -> Self:
        """Map `Mark.PARALLEL`'s shape onto its three channels:
        `dims` (one vertical axis per name, each independently scaled
        to its column's `[min, max]` -- see `_render_parallel`'s docstring for why there's no per-dimension max parameter
        the way `encode_radar()`'s `max_values` is), `row_names`
        (one polyline per name), and `data` (one list per row, one
        value per dimension -- the same "outer list indexes named
        things, inner list is that thing's numbers" shape `encode_
        radar()`'s `series_values` uses, generalized
        from "one value per named indicator" to "one value per named
        dimension").

        Raises immediately (the same up-front "can't produce a
        coherent result at all" reasoning `encode_radar()`'s checks give) on a `row_names`/`data` length mismatch,
        or any individual row whose value count doesn't match
        `dims`'s count.
        """
        if len(row_names) != len(data):
            raise Error(
                "Plot.encode_parallel(): row_names and data must have the same length"
                " (got "
                + String(len(row_names))
                + " and "
                + String(len(data))
                + ")"
            )
        for row in data:
            if len(row) != len(dims):
                raise Error(
                    "Plot.encode_parallel(): every row in data must have one value per"
                    " dimension (expected "
                    + String(len(dims))
                    + ", got "
                    + String(len(row))
                    + ")"
                )
        self._parallel.dims = dims.copy()
        self._parallel.row_names = row_names.copy()
        self._parallel.data = data.copy()
        return self^

    def encode_distribution(var self, categories: List[String], values: List[List[Float64]]) raises -> Self:
        """Map a category column and, per category, a *list* of raw
        values onto the shape `Mark.BEESWARM`/`VIOLIN`/`RIDGELINE` all
        share -- the same "outer list indexes categories, inner list is
        that category's distribution" shape `encode_boxplot()`
        uses, but kept as the raw values themselves,
        not immediately reduced to a five-number summary the way `Mark.
        BOX` needs: a swarm plot draws every individual point, and a
        density estimate needs the raw values to estimate from, neither
        of which a quartile summary alone could reconstruct.

        Raises immediately (the same "can't produce a coherent result
        at all" reasoning `encode_boxplot()`'s checks give)
        on a `categories`/`values` length mismatch, or any category
        whose value list is empty.
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
        self._distribution.values = values.copy()
        return self^

    def encode_single_axis(
        var self,
        x: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
    ) -> Self:
        """Map one continuous column plus the usual optional `color`/
        `color_categories`/`size` channels onto `Mark.SINGLE_AXIS`'s one-axis shape -- the same three optional channels `encode()`
        itself takes, just without a `y`. `y_data` is filled with one
        placeholder `0.0` per row (never read as a real value -- see
        `_render_single_axis`'s docstring for why) purely so this
        mark can reuse `_validate_continuous_encoding`'s existing x/y-
        length-match check and `Mark.POINT`'s `_draw_point_layer`
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

    def labels(
        var self, title: String = "", subtitle: String = "", x_title: String = "", y_title: String = ""
    ) -> Self:
        """Set the chart title/subtitle and/or axis titles -- text
        captions, not data. Named `x_title`/`y_title`, not `x`/`y`, so a
        call site reading `.labels(x_title=..., y_title=...)` next to
        `.encode(x=..., y=...)` never reads as if it's setting data
        columns; the two mean completely different things (a caption
        string vs. a `List[Float64]`) despite the visual similarity.

        Each of the four is independent and defaults to `""` (not
        set) -- call with only the ones actually wanted, e.g. `.labels
        (title="Quarterly Revenue")` alone, with no subtitle or axis
        titles at all. `render()`/`render_svg()` reserve layout space
        for exactly the ones that are non-empty and no others (see
        their docstring for the margin math) -- an unset title
        costs nothing, the same "absent means absent" rule this file's
        other optional features (`Theme.line_smoothing`, `donut_inner_
        radius_fraction`, etc.) follow.

        `subtitle` draws as its own line directly beneath `title`,
        smaller and in `Theme.subtitle_color`'s muted tone rather
        than `title`'s bold `text_color` -- the classic editorial two-
        tier headline (a bold, short title plus a longer, quieter
        subtitle giving context or a source note). Independent of
        `title`: a `subtitle` set with no `title` still draws, at the
        same top position `title` would have used, just with no title
        line above it -- the same "each of the four is independent"
        rule every other field here follows, not "subtitle only means
        something once title is set."

        `x_title`/`y_title` caption whatever's drawn along the bottom/
        left edge respectively -- which axis that actually *is*
        depends on the mark's orientation (the continuous axis for
        `Mark.POINT`/`LINE`/`AREA`/`GANTT`'s `x`; the categorical
        one for every vertical categorical mark's `x`; `GANTT`'s categorical `y` instead of a continuous one) -- `x_title`/
        `y_title` describe screen position, not "the continuous axis"
        specifically, so the same two names stay meaningful across
        every orientation without special-casing.

        `Mark.ARC` has no x/y axes at all (see `_render_arc`'s docstring) -- `x_title`/`y_title` raise at render() time if set
        on an `Mark.ARC` plot (only `title`/`subtitle` apply there), the
        same "raise on a setting that can't apply, don't silently drop
        it" rule `Plot.encode`'s color/size-on-a-non-POINT-mark
        check follows.
        """
        self._labels.title = title
        self._labels.subtitle = subtitle
        self._labels.x_title = x_title
        self._labels.y_title = y_title
        return self^

    def annotate_line(var self, value: Float64, label: String = "") -> Self:
        """Add a horizontal reference line at `value` on the y-axis --
        ECharts' `markLine` (a fixed, explicit value only; not its
        other "average"/"max"/"min" auto-computed modes, a real,
        deliberate scope cut). Callable more than once -- each call
        *adds* a line, doesn't replace the previous one, so `.annotate_
        line(target).annotate_line(average, label="avg")` draws both.
        `label`, when non-empty, draws to the right of the line, in
        `Theme.annotation_color`'s muted tone; the line itself
        spans the full plot width, solid (not dashed -- canvas_mojo has
        no dashed-stroke primitive at all yet, a real, separate gap,
        not something this feature works around). A `value` outside
        the mark's (padded) y-domain draws nothing at all -- not
        clamped to an edge, not extrapolated off-plot into the chrome
        above -- see `_draw_annotation_lines`'s docstring for what an
        unclamped extrapolation would draw instead.

        Only meaningful on a mark whose y-axis is a genuine continuous
        `LinearScale` -- checked at render() time (`_RenderResult`'s `has_y_scale`, see its docstring), raising a clear error
        rather than silently drawing nothing or drawing somewhere
        wrong, the same "raise on a setting that can't apply" rule
        `x_title`/`y_title`-on-`Mark.ARC` follows. Supported
        today: `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER` (the shared
        continuous path) and every mark sharing `_CategoricalFrame`
        (`BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`/`CANDLESTICK`/`BULLET`/
        `GROUPED_BAR`/`STACKED_BAR`/`STREAMGRAPH`) -- the two places
        `_RenderResult` actually gets a real y-scale from today. Every
        other mark (categorical-only axes, polar coordinates,
        hierarchy/edge-list layouts, `Mark.ARC`'s no-axes-at-all
        shape, `Mark.BUMP`'s rank-not-value y-axis, ...) has no
        y *value* domain a reference line could mean anything against
        -- a scope limit: growing this list only needs a call site
        update, not new machinery (see `_CategoricalFrame.result`'s
        docstring for how the first nine got it "for free").

        Also wired into `render_facets()` (each cell's annotations
        draw against that cell's real y-scale, exactly like a
        standalone render) and `render_layers()` (each layer's annotations draw against that layer's y-scale -- primary or
        secondary, whichever `Plot.secondary_axis()` put it on -- not
        some other layer's) -- see `_render_facets_generic`'s and
        `_render_layers_generic`'s docstrings for the full mechanics
        of each.
        """
        self._annotations.line_values.append(value)
        self._annotations.line_labels.append(label)
        return self^

    def annotate_area(var self, y0: Float64, y1: Float64, label: String = "") -> Self:
        """Add a shaded horizontal band from `y0` to `y1` on the y-axis
        -- ECharts' `markArea` (a fixed, explicit `(y0, y1)` pair
        only; not its other "between two series"/auto-computed-range
        modes, the same deliberate scope cut `annotate_line()`'s docstring explains for `markLine`). Callable more than
        once -- each call *adds* a band. `label`, when non-empty, draws
        inside the band near its top edge, in `Theme.annotation_
        color` (the same ink `annotate_line()`'s label uses -- see
        `Theme.annotation_area_color`'s docstring for why the fill
        and the label ink are two separate fields). `y0`/`y1` don't need
        to be given low-to-high -- whichever is smaller becomes the
        band's bottom edge.

        Unlike `annotate_line()`'s all-or-nothing value, a band that
        only *partially* overlaps the mark's (padded) y-domain
        clips to the visible portion instead of disappearing entirely
        -- an area has real width, so showing the part that's actually
        in range is what every other chart library's shaded-region
        feature does; hiding all of it just because one edge overshoots
        would throw away real, valid information the caller asked for.
        A band with *no* overlap at all still draws nothing, the same
        as `annotate_line()`'s out-of-range case.

        A design choice, not an oversight: this draws as a fully opaque
        rectangle *on top of* whatever the mark itself drew in that
        band, not real alpha over it (both backends can render true
        alpha now -- see `Theme.annotation_area_color`'s docstring),
        which is why its default stays deliberately pale. On `Mark.POINT`/`LINE`/`EFFECT_SCATTER`
        this reads well (a thin stroke/dot only loses the small stretch
        that falls inside the band, the rest is untouched), but on
        `Mark.BAR`/`WATERFALL`/`STACKED_BAR`/any other solid-fill mark, a
        bar whose height *enters* the band has that whole entering
        portion overwritten by the band's color -- it can read as if
        the bar's height changed, not just that a band was drawn behind
        it. Not broken, just something to know before combining the two;
        this method still works there (the raise below is only about
        having a continuous y-axis at all, not about this), but a line/
        point/area-family mark is where it actually looks right today.

        Same mark-support rule as `annotate_line()`, and wired into
        `render_facets()`/`render_layers()` the same way -- raises the
        identical clear error rather than silently drawing nothing or
        somewhere wrong on a mark with no genuine continuous y-axis
        (both reuse the identical `_RenderResult.y_scale`/`has_y_scale`
        mechanism). See `annotate_line()`'s docstring for the exact
        supported list and the facets/layers mechanics, both shared
        exactly.
        """
        self._annotations.area_y0.append(y0)
        self._annotations.area_y1.append(y1)
        self._annotations.area_labels.append(label)
        return self^

    def annotate_vline(var self, value: Float64, label: String = "") -> Self:
        """Add a vertical reference line at `value` on the x-axis --
        `annotate_line()`'s mirror image, for the other axis. Same
        fixed-value-only scope, same additive/repeatable behavior,
        same solid `Theme.annotation_color` styling, same silent skip
        on an out-of-(padded)-domain value (see `annotate_line()`'s docstring for the full reasoning behind each of those, which
        this repeats exactly, just transposed to the other axis).

        Narrower mark support than `annotate_line()`/`annotate_area()`,
        though: a categorical x-axis (`Mark.BAR`/`LOLLIPOP`/`WATERFALL`/
        `BOX`/`CANDLESTICK`/`BULLET`/`GROUPED_BAR`/`STACKED_BAR`/
        `STREAMGRAPH`) has no numeric x *value* a vertical line could
        mean anything against -- only `Mark.POINT`/`LINE`/`AREA`/
        `EFFECT_SCATTER`, the marks with a genuine continuous x-axis,
        support this (see `_RenderResult`'s docstring for exactly
        why the two annotation families diverge here). Raises the same
        "no axis to place this against" error `annotate_line()` does if
        called on an unsupported mark.

        Only wired into `render()`/`render_svg()` so far, the same
        `render_facets()`/`render_layers()` scope cut every annotation
        method here currently has.
        """
        self._annotations.vline_values.append(value)
        self._annotations.vline_labels.append(label)
        return self^

    def annotate_point(var self, x: Float64, y: Float64, label: String = "") -> Self:
        """Add a single labeled point at `(x, y)` -- ECharts' `markPoint` (a fixed, explicit coordinate only; not its other
        "max"/"min"/"average" auto-computed modes, the same deliberate
        scope cut `annotate_line()`'s docstring explains
        for `markLine`). Draws a small filled marker at the data
        coordinate, in `Theme.annotation_color`, with `label` (when
        non-empty) just above it. Additive/repeatable -- each call adds
        one more point.

        Needs a genuine coordinate on *both* axes, so it's the narrowest
        of the four annotation methods here: only `Mark.POINT`/`LINE`/
        `AREA`/`EFFECT_SCATTER` support it, the same set `annotate_
        vline()` does and for the identical reason (see that method's docstring, and `_RenderResult`'s, for why a categorical
        x-axis rules the other nine marks out). Raises the same clear
        error on an unsupported mark.

        A point outside the mark's (padded) domain on *either* axis
        draws nothing at all, the same silent-skip-not-clamp rule
        `annotate_line()`'s docstring explains and the real bug that
        discipline exists to avoid.

        Only wired into `render()`/`render_svg()` so far -- not `render_
        facets()`/`render_layers()`, the same scope cut every annotation
        method here currently has.
        """
        self._annotations.point_x.append(x)
        self._annotations.point_y.append(y)
        self._annotations.point_labels.append(label)
        return self^

    def secondary_axis(var self) -> Self:
        """Draw this layer's y values against a second, independent
        y-domain on the plot's right edge, instead of `render_layers()`'s
        usual shared left-axis domain -- ECharts' `yAxisIndex: 1`,
        simplified to a boolean since dataviz_mojo only ever draws two
        y-axes (left/right), never a third. The real, common pattern
        this exists for: a revenue-bars-plus-growth-rate-line combo
        chart, where the two series' units/scales are too different
        to share one axis without one of them going flat -- see
        `_render_layers_generic`'s docstring for the full mechanics.

        `render_layers()`/`render_layers_svg()` only -- meaningless on a
        standalone plot (there's only ever one series, so nothing for a
        second axis to pair against); `render()`/`render_svg()` raise a
        clear error if a plot with this set reaches them directly,
        rather than silently ignoring it, the same "raise on a setting
        that can't apply" rule `annotate_line()`/`x_title`/`y_title`-on-
        `Mark.ARC` follow.

        At least one layer in the list must stay on the primary axis --
        `render_layers()` raises if *every* layer calls this (there'd be
        nothing left for "secondary" to mean relative to). No gridlines
        draw for the secondary axis (only the primary domain's gridlines
        show -- two independent grids overlaid would just look like
        visual noise, the same convention ECharts/Vega/matplotlib's twin-axis charts all follow); it still gets its axis line,
        ticks, and tick labels, mirrored onto the plot's right edge.

        A secondary-axis layer's `Plot.labels()`'s `y_title` captions
        this axis specifically -- set it on *this* layer (the one
        calling `.secondary_axis()`), not `plots[0]`: `render_layers()`
        reads it from whichever layer actually has `.secondary_axis()`
        set, not from shared chrome (see `_secondary_axis_y_title`'s docstring for the mechanics). Leave it unset for no caption at
        all, the same as the primary axis's `y_title`.
        """
        self._secondary_axis = True
        return self^


def _unique_categories(data: List[String]) -> List[String]:
    """Every distinct value in `data`, in first-seen order -- the
    domain a categorical color palette indexes into. Deliberately not
    shared with `encode_categorical()`'s `x_categories` (which is
    used as-given, no dedup -- see that method's docstring): a
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
    """`_categorical_indices`'s result: a categorical column's
    `domain` (its distinct values in first-seen order, exactly what
    `_unique_categories` returns) *plus* `indices`, that domain's position for every row of the original column -- `indices[i]` is
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
    `Mark.POINT`'s categorical color channel needs it for (see
    `_PointChannels`), and also `Mark.HEATMAP`/`PUNCHCARD`'s two axis
    domains and `_edge_node_index`'s node resolution for the edge-list
    family.

    Hashes each row once, making this O(n) on average for `n` rows;
    each row's domain position is then a plain `indices[i]` lookup
    for every later caller, not a domain scan.

    `domain`'s append order agrees with `_unique_categories` (this
    module's documented, separately tested first-seen-order helper)
    exactly by construction -- this function additionally keeps each
    row's landing position, the answer every caller otherwise has to
    recompute from the domain.

    First-seen order comes from `domain`'s append order, not from
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
    """The `Path` a `Mark.LINE` plot strokes through its already-
    pixel-projected points -- also the curve `Mark.AREA` fills down to
    baseline from, since an area chart's top edge is exactly a line
    chart's path (see the `Mark.AREA` branch's comment in `_render_
    generic` for the two extra `line_to`s/`close()` that turn this
    function's returned open curve into a closed, fillable region).
    `smoothing == 0.0` (`Theme.line_smoothing`'s default) builds a plain
    `move_to` plus one `line_to` per remaining point, so the default
    case never touches curve math at all and stays byte-for-byte
    identical to a render with `line_smoothing` never touched (see
    `Theme.line_smoothing`'s docstring -- deliberately an explicit
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
    not just claimed, in this function's tests, so the two code
    paths are known to agree at the boundary even though only one of
    them actually runs there.

    Every control-point coordinate hand-derived via `python3` (both
    the plain tangent formula and, separately, a real cubic Bezier
    evaluated at `t=0.5` compared against the straight-line midpoint at
    the same `t`, confirming the curve visibly bows away from the
    straight path, not just that *some* curve command got emitted) --
    see `test_plot.mojo`'s tests for both checks.
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


struct _Decimated(Movable):
    """`_decimate_to_pixel_columns`' result -- the reduced `px`/`py`
    pair, plus `applied` recording whether anything was actually
    dropped (so a caller can tell "decimation ran and kept everything"
    from "decimation was declined")."""

    var px: List[Float64]
    var py: List[Float64]
    var applied: Bool

    def __init__(out self, var px: List[Float64], var py: List[Float64], applied: Bool):
        self.px = px^
        self.py = py^
        self.applied = applied


def _decimate_to_pixel_columns(px: List[Float64], py: List[Float64]) -> _Decimated:
    """Reduce a dense polyline to at most four points per horizontal
    pixel column, preserving what that column can actually show.

    A `Mark.LINE`/`Mark.AREA` plot of 5000 points into a ~640px-wide
    plot area hands the rasterizer roughly eight segments per pixel
    column. Seven of every eight are sub-pixel and cannot draw anything
    a shorter path wouldn't -- but `stroke_path_aa` still pays full
    per-segment cost for each (measured at ~263us/segment, which is
    what makes a 5000-point line chart take ~1.7s against ~21ms for the
    same points as a scatter). Dropping them is the only fix available
    from this side of the library; the per-segment constant itself
    lives in canvas_mojo.

    Per column this keeps exactly the **minimum** and **maximum** y,
    emitted in original data order (and collapsed to one point when a
    column holds only one, or when min and max are the same sample).
    Keeping both extremes -- rather than the first point per column,
    the naive version of this -- is what preserves the *envelope*: a
    spike that rises and falls inside a single pixel column still
    reaches its true extent, where first-point-per-column would flatten
    it away and quietly lie about the data.

    Two per column and not four: an earlier draft also kept each
    column's first and last point, reasoning that it would keep the
    joins between columns exactly where they were. That turned out to
    defeat the whole purpose -- at four points per column a 2000-point
    series over ~500 columns is already at its budget and nothing gets
    dropped at all (measured: no improvement whatsoever). Min and max
    are themselves real samples from the column, so the path still
    starts and ends inside it; the joins move by at most a pixel, which
    is the same tolerance the decimation itself is working at. Two per
    column is also what every time-series plotting library uses for
    this.

    Two guards, both deliberate:

    `px` must be **non-decreasing**. `mark_line()`'s docstring is
    explicit that points connect in *data order*, never sorted by x --
    which is what lets a caller draw a loop, a hysteresis curve, or any
    path that doubles back. Grouping by pixel column assumes x advances
    monotonically; applied to a path that reverses, it would reorder
    the drawing and produce a visibly different (wrong) shape. So a
    non-monotonic path is left completely untouched.

    It only engages when there are more than twice as many points as
    columns to put them in. Below that, points are individually
    resolvable, dropping any of them could be visible, and the saving
    would be small anyway -- so every chart small enough for that (which
    is every chart in this repo's test suite) renders byte-for-byte
    as it always has.
    """
    var n = len(px)
    if n < 4:
        return _Decimated(px.copy(), py.copy(), False)

    var lo = px[0]
    var hi = px[0]
    for i in range(1, n):
        if px[i] < px[i - 1]:
            # Not monotonic -- decline entirely (see docstring).
            return _Decimated(px.copy(), py.copy(), False)
        if px[i] < lo:
            lo = px[i]
        if px[i] > hi:
            hi = px[i]

    var columns = Int(hi) - Int(lo) + 1
    if columns < 1 or n <= 2 * columns:
        return _Decimated(px.copy(), py.copy(), False)

    var out_x = List[Float64](capacity=2 * columns)
    var out_y = List[Float64](capacity=2 * columns)

    var start = 0
    while start < n:
        var col = Int(px[start])
        var end = start
        while end + 1 < n and Int(px[end + 1]) == col:
            end += 1

        var i_min = start
        var i_max = start
        for i in range(start + 1, end + 1):
            if py[i] < py[i_min]:
                i_min = i
            if py[i] > py[i_max]:
                i_max = i

        # The column's two extremes, in whichever order the data
        # visited them -- collapsing to one when they're the same
        # sample (a single-point column, or a perfectly flat one).
        var first = i_min if i_min <= i_max else i_max
        var second = i_max if i_min <= i_max else i_min
        out_x.append(px[first])
        out_y.append(py[first])
        if second != first:
            out_x.append(px[second])
            out_y.append(py[second])

        start = end + 1

    return _Decimated(out_x^, out_y^, True)


def _max_label_width(labels: List[String], font_size: Float64) raises -> Float64:
    """The widest of `labels`' rendered ink width at `font_size`
    -- what the left margin needs to fit the y-axis's tick labels
    without clipping or crowding the axis line (see the dynamic-
    left-margin computation in render()/_render_bar, both of which
    call this on a scale's `ticks().labels()` before that scale's
    pixel range -- and therefore the plot area's actual left edge --
    is finalized; a y-axis's tick *values*, and so their formatted
    label text, depend only on the data domain, never on the pixel
    range they'll eventually be drawn into, so measuring them this
    early is exact, not a guess to be corrected later).

    Resolves its font fresh (one `FontCache` for this call's label
    list). A caller that measures *twice* in one render -- a y-axis
    tick list and then a legend's labels, which several marks do --
    should use the `cache=` overload below and share one cache between
    the two instead, since a fresh cache re-pays canvas_mojo's font
    resolution and TTF parse: measured at 0.44ms for a 5-label call
    against 0.056ms once the cache is warm. Two overloads rather than
    one required parameter deliberately mirrors canvas_mojo's `measure_text`/`draw_text` pair, and keeps the two dozen
    single-measurement call sites in this package untouched.
    """
    var cache = FontCache()
    return _max_label_width(labels, font_size, cache=cache)


def _max_label_width(
    labels: List[String], font_size: Float64, *, mut cache: FontCache
) raises -> Float64:
    """`_max_label_width` resolving fonts through `cache` instead of
    fresh -- see the overload above for when to reach for this.
    """
    var max_width = 0.0
    for label in labels:
        var m = measure_text(label, font_size, cache=cache)
        if m.width > max_width:
            max_width = m.width
    return max_width


def _dynamic_legend_width(labels: List[String], content_width: Int, sc: _Scaled) raises -> Int:
    """How wide a legend column actually needs to be to fit `labels`
    next to `content_width`-wide content (a swatch for `_draw_legend`'s categorical rows; a gradient bar for `_draw_continuous_color_
    legend`; the widest possible circle for `_draw_continuous_size_
    legend` -- `content_width` generalizes over all three rather than
    this function assuming a swatch specifically) -- `content_width`,
    then `label_gap`, then the widest label's rendered width
    (`_max_label_width`, the same measurement technique the dynamic
    left margin already uses for y-axis tick labels, just applied to
    legend labels instead), then `margin_buffer` breathing room --
    `max`'d against `sc.legend_width` (`Theme`'s fixed 130px
    default, scaled) so no existing plot's legend column ever gets
    *narrower* than it already was -- purely additive, only ever
    growing the column for labels wide enough to actually need it, the
    same "purely additive" contract every dynamic-margin computation in
    this file follows. Every call site (`Mark.POINT`'s categorical color/continuous color/continuous size legends,
    `Mark.GROUPED_BAR`/`STACKED_BAR`'s series-name legend,
    `Mark.ARC`'s category legend) has to know its actual label
    list *before* finalizing `plot_x1`, the same "measure first, size
    the margin second" ordering the y-axis's tick labels
    require -- see each call site's comment for where that
    reordering was needed.

    Has a `cache=` overload for the same reason `_max_label_width`
    does -- a mark sizing both an axis and a legend in one render
    shares one cache across the two.
    """
    var cache = FontCache()
    return _dynamic_legend_width(labels, content_width, sc, cache=cache)


def _dynamic_legend_width(
    labels: List[String], content_width: Int, sc: _Scaled, *, mut cache: FontCache
) raises -> Int:
    """`_dynamic_legend_width` resolving fonts through `cache` instead
    of fresh -- see the overload above."""
    return max(
        sc.legend_width,
        content_width
        + sc.label_gap
        + Int(_max_label_width(labels, sc.font_size, cache=cache))
        + sc.margin_buffer,
    )


struct _TextRequest(Copyable, Movable):
    """One deferred `draw_text()` call -- collected while the generic,
    `DrawTarget`-bounded rendering pass runs, instead of drawn inline
    right away (see canvas_mojo/draw_target.mojo's docstring for why
    `DrawTarget` itself has no `draw_text` method to call). `render()`/
    `render_svg()` each replay a returned list of these their way
    -- `canvas_mojo.text.draw_text` for the former, `SvgCanvas.draw_text`
    for the latter -- once the shared generic pass that collected them
    returns; see either function's body for exactly where.

    `family` is baked in here, at construction time, from whichever
    `Theme` built this particular request -- read once and stored,
    the same way `color`/`size` already are, *not* a single value the
    final draw loop reads once from one outer `Theme` -- see `Theme.
    font_family`'s docstring for why that distinction matters
    (`render_facets()`/`render_layers()` combine several independently
    themed `Plot`s' `_TextRequest`s into one shared draw pass).

    `bold` (default `False`) is the opposite shape from `family` --
    left at its default everywhere except `_label_text_requests`'s chart-title request (`bold=theme.title_bold`), rather than
    baked in from `theme` at every one of this struct's construction sites, since nothing else here ever wants `True` --
    see `Theme.title_bold`'s docstring.
    """

    var x: Int
    var y: Int
    var text: String
    var color: Color
    var size: Float64
    var align: TextAlign
    var family: String
    var bold: Bool
    var rotation: Float64

    def __init__(
        out self,
        x: Int,
        y: Int,
        text: String,
        color: Color,
        size: Float64,
        align: TextAlign,
        family: String,
        bold: Bool = False,
        rotation: Float64 = 0.0,
    ):
        self.x = x
        self.y = y
        self.text = text
        self.color = color
        self.size = size
        self.align = align
        self.family = family
        self.bold = bold
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
    `Mark.POINT`'s categorical color legend and `Mark.ARC`'s legend use, since both reduce to "a list of category labels plus
    the palette that colored them" by the time they get here (see
    render()/`_render_arc` for how each computes that list). `palette`
    is indexed the same `i % len(palette)` way the actual points/
    wedges were colored, not `labels[i]`'s index directly, so a
    legend row always shows the exact color that category actually
    got, cycling included.

    Computes its `_Scaled(theme)` rather than taking one as a
    parameter -- keeps this function's signature stable (still
    just `theme` in) and the "* theme.scale" formula in the one place
    `_Scaled` itself lives, at the cost of one extra (cheap) `_Scaled`
    construction per legend drawn. Each label's text is appended
    to `text_requests` (a caller-owned, shared list -- see
    `_TextRequest`'s docstring for why), not drawn directly; only
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
                theme.font_family,
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
    method's docstring; before it existed, this was approximated
    as many thin solid-colored `fill_rect` strips), `color_scale`'s high value at the top, low at the bottom -- the same "more/
    bigger is up" convention a y-axis itself already uses. Two labels
    (`_format_fixed`, one decimal place, matching `encode_histogram()`'s bin-label convention): the domain max at the bar's top, the
    domain min at its bottom.

    The `LinearGradient` is built directly from `color_scale`'s `stops` (each already an `(offset, color)` pair over `color_scale`'s `[domain_min, domain_max]`, three of them -- `ColorScale.
    from_theme`'s low/mid/high at `0.0`/`0.5`/`1.0` -- in every
    caller so far, see that method's docstring for why a middle
    stop matters here specifically), not re-derived from `color_at()`
    sampled at many points the way the old strip approximation had to:
    `color_scale`'s offsets run low (0.0) to high (1.0), but the
    bar's gradient axis runs top (`y`) to bottom (`y + bar_height`)
    -- top has to be the *high* value, so each stop's gradient
    offset is `1.0 - stop.offset`, not `stop.offset` directly. Because
    that flip reverses their order, the stops are then sorted back into
    ascending offset order before being added -- SVG requires it, and
    emitting them descending rendered the bar as one flat color; see
    the body's comment for the full story.

    Returns the y-coordinate just below this section (bar height plus
    one row gap) -- where `_draw_continuous_size_legend` starts if a
    plot combines continuous color *and* size, so the two stack
    vertically in one legend column instead of overlapping.
    """
    var sc = _Scaled(theme)
    var bar_width = sc.continuous_legend_bar_width
    var bar_height = sc.continuous_legend_bar_height
    var gradient = LinearGradient(Float64(x), Float64(y), Float64(x), Float64(y + bar_height))

    # Stops are emitted in ascending offset order, which SVG requires
    # and the raster backend does not care about.
    #
    # SVG's <linearGradient> clamps each <stop>'s offset to be no
    # less than the previous one's. Emitting `1.0 - offset` straight
    # off an ascending ColorScale runs *descending* (1.0, 0.5, 0.0), so
    # every stop after the first got clamped up to 1.0, collapsing all
    # three onto one offset -- and the legend bar rendered as a single
    # flat color with no gradient at all.
    #
    # The raster path was always correct, which is exactly why this
    # survived: `_color_at_t` scans for the bracketing pair rather than
    # assuming sorted input (see canvas_mojo/gradient.mojo), so the
    # same code produced a correct .png and a broken .svg from one
    # render. Only the vector output was ever wrong.
    #
    # Sorted rather than simply iterating `color_scale.stops` backwards:
    # `ColorScale.add_stop` deliberately accepts stops in any order (it
    # tracks its `_lowest`/`_highest` incrementally for precisely
    # the same reason `LinearGradient` does), so "the reverse of
    # ascending" is only ascending for the scales `from_theme` happens
    # to build. Sorting is correct for any `ColorScale`, including the
    # hand-built ones in tests/test_color_scale.mojo. Insertion sort
    # because the list is three stops long.
    var offsets = List[Float64](capacity=len(color_scale.stops))
    var colors = List[Color](capacity=len(color_scale.stops))
    for stop in color_scale.stops:
        offsets.append(1.0 - stop.offset)
        colors.append(stop.color)
    for a in range(1, len(offsets)):
        var key_offset = offsets[a]
        var key_color = colors[a]
        var b = a - 1
        while b >= 0 and offsets[b] > key_offset:
            offsets[b + 1] = offsets[b]
            colors[b + 1] = colors[b]
            b -= 1
        offsets[b + 1] = key_offset
        colors[b + 1] = key_color
    for i in range(len(offsets)):
        gradient.add_stop(offsets[i], colors[i])

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
            theme.font_family,
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
            theme.font_family,
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
    midpoint, min of the actual data's size domain -- not evenly
    spaced *radii*, evenly spaced *values*, so the legend shows real
    data points a caller could look up, the same reason a y-axis's "nice" ticks are picked from the data domain rather than the pixel
    range) at `size_scale`'s radius for each, the identical scale
    real data points are sized with. Circles left-aligned on their *widest* possible edge (`x + sc.size_range_max`, `Theme`'s configured largest radius, not this particular plot's largest
    circle) so every circle's label lines up at the same x
    regardless of which circle is biggest -- this reads better than
    centering each circle independently, which would stagger the
    labels.

    Returns the y-coordinate just below the last circle (plus one row
    gap) -- unused today (this is always the last legend section drawn
    in `_render_generic`'s current stacking order) but returned for
    the same reason `_draw_continuous_color_legend` does: consistency,
    and so a third section could stack after this one someday without
    this function's signature needing to change.
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
                theme.font_family,
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
    data's extremes, not a padded approximation of them (see
    MinMax's docstring).
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
    """`_apply_labels`'s finished result: the outer rect `render()`/
    `render_svg()` actually hand to `_render_generic` (shrunk to make
    room for `Plot.labels()`'s title/x_title/y_title -- see that
    method's docstring). Just the shrunk rect: `_apply_labels` builds
    no title `_TextRequest`s itself; see `_label_text_requests`,
    called *after* rendering instead. A named
    struct even though only `render()`/`render_svg()` call
    `_apply_labels` -- this file's established convention
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
    legend `_TextRequest`s it always returned (see `_render_generic`'s docstring for why text is collected, not drawn directly), plus
    the *inner* plot rect it actually laid the mark out in (`px0`/`py0`/
    `px1`/`py1` -- dynamic left margin, optional legend column, all
    already resolved). That second part exists for exactly one
    consumer, `_label_text_requests` (see its docstring): `Plot.
    labels()`'s title/x_title/y_title center on this rect rather than
    the full outer bounds `render()`/`render_svg()` were called with,
    so a wide legend or long y-axis tick labels shifting the real data
    area off-center doesn't throw a title's centering off with it.
    A named struct, not a raw tuple -- this file's established
    convention for every multi-value return.

    When a `_render_*` function returns before any layout has actually
    happened (no data to draw -- see e.g. `_render_bar`'s early
    `len(plot.x_categories) == 0` check), `px0`..`py1` fall back to the
    full outer bounds it was given: there's no narrower rect to report,
    and the outer bounds are exactly what `_label_text_requests` would
    otherwise center on anyway -- that case is `_empty_result` below.

    `y_scale`/`has_y_scale` are `Plot.annotate_line()`'s consumer
    (see `_draw_annotation_lines`'s docstring): the *real* finished
    `LinearScale` a mark's y-axis used to place its data, exposed
    here for a `render()`/`render_svg()`-level annotation pass to reuse
    directly (`LinearScale.to_pixel(annotation_value)`) rather than
    independently recomputing whatever domain math that particular
    mark happened to use internally -- a recomputed-elsewhere version
    could silently drift out of sync with the real one if either ever
    changed without the other; reusing the actual object can't.
    `has_y_scale` defaults `False` (`y_scale` itself defaults to an
    inert `LinearScale(0, 0, 0, 0)`, never read when the flag is
    `False`) so every pre-existing `_RenderResult(...)` call keeps
    compiling, and thus rendering, completely unchanged -- only the
    handful of `_render_*` functions `annotate_line()` actually
    supports (see that method's docstring for which, and why not
    every mark type yet) pass a real one.

    `x_scale`/`has_x_scale` are the identical mechanism, mirrored for
    the x-axis -- `Plot.annotate_vline()`'s and `Plot.annotate_point()`'s consumer (see `_draw_annotation_vlines`'/`_draw_annotation_
    points`'s docstrings). Set only by `_ContinuousFrame.result()`,
    never `_CategoricalFrame.result()`: a categorical x-axis has no
    genuine numeric domain a vertical line or a point's x coordinate
    could mean anything against (see `_CategoricalFrame`'s docstring), so `annotate_vline()`/`annotate_point()` support a
    narrower mark list than `annotate_line()`/`annotate_area()` do --
    `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER` only, not the nine
    marks sharing `_CategoricalFrame` too."""

    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int
    var y_scale: LinearScale
    var has_y_scale: Bool
    var x_scale: LinearScale
    var has_x_scale: Bool

    def __init__(
        out self,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
        y_scale: LinearScale = LinearScale(0.0, 0.0, 0.0, 0.0),
        has_y_scale: Bool = False,
        x_scale: LinearScale = LinearScale(0.0, 0.0, 0.0, 0.0),
        has_x_scale: Bool = False,
    ):
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1
        self.y_scale = y_scale
        self.has_y_scale = has_y_scale
        self.x_scale = x_scale
        self.has_x_scale = has_x_scale


def _empty_result(ox0: Int, oy0: Int, ox1: Int, oy1: Int) -> _RenderResult:
    """The `_RenderResult` every `_render_*` function returns when it
    has nothing to draw (no categories, no points) -- no text requests,
    and the full outer bounds as the inner rect, for the reason
    `_RenderResult`'s docstring gives. One helper rather than the
    same three lines (`var text_requests = List[_TextRequest]()`, the
    length check, the constructor call) opening all eleven of them.
    """
    return _RenderResult(List[_TextRequest](), ox0, oy0, ox1, oy1)


def _apply_labels(plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _LabelsFrame:
    """Reserves margin space for `Plot.labels()`'s chart/axis
    titles, given the *original* outer bounds `render()`/`render_svg()`
    were called with. Called once, by those two functions only, *before*
    handing off to `_render_generic` -- not threaded through
    `_render_generic`, `_draw_categorical_axis_frame`, `_draw_
    horizontal_categorical_axis_frame`, or any mark-specific `_render_*`
    function, all of which stay completely unaware titles exist. This
    is deliberate, the same "a little duplication/a small wrapper over
    threading a flag through many functions" reasoning `_render_bar`'s docstring gives -- titles are pure outer-rect
    geometry (how much smaller a rectangle to hand downstream), so
    shrinking that rectangle *before* any mark-specific layout runs
    gets the same effect as threading title state through every one of
    those functions, for a small fraction of the surface area touched.

    Only reserves margin here -- doesn't build the title `_TextRequest`s
    themselves, unlike its original version. A title/x_title's along-axis position (how far from the very top/bottom edge) only
    ever depends on this margin reservation, known immediately; but its
    cross-axis position (centered *where*, horizontally for title/
    x_title, vertically for y_title) should track the real inner plot
    rect -- dynamic left margin, optional legend column -- which isn't
    known until `_render_generic` (or whichever `_render_*` it
    dispatches to) actually runs and returns it (`_RenderResult`'s `px0`..`py1`, see its docstring). Splitting into two phases this
    way -- reserve margin before rendering, center text after -- is what
    makes a title/x_title land pixel-precisely over the inner plot rect
    instead of the full outer width/height, immune to a wide legend or
    long y-axis tick labels throwing it off-center (see the wiki's
    Changelog, "Plot.labels() precise centering", for the history).
    `_label_text_
    requests`, called by `render()`/`render_svg()` right after
    `_render_generic` returns, is phase two.

    `Mark.ARC` has no x/y axes at all (`_render_arc`'s docstring),
    so `x_title`/`y_title` raise here if set on an `Mark.ARC` plot --
    unlike `title` (which centers over the outer width regardless of
    mark type, and works fine for `ARC` too -- a pie chart can
    absolutely have a heading), there's no sensible "axis" to caption.
    """
    if (plot._labels.x_title.byte_length() > 0 or plot._labels.y_title.byte_length() > 0) and plot._mark == Mark.ARC:
        raise Error(
            "Plot.labels(): x_title/y_title don't apply to Mark.ARC (it"
            " has no x/y axes to caption) -- only title applies to a"
            " pie/donut chart"
        )

    var sc = _Scaled(plot._theme)
    var extra_top = Int(sc.title_font_size) + sc.label_gap if plot._labels.title.byte_length() > 0 else 0
    extra_top += Int(sc.subtitle_font_size) + sc.label_gap if plot._labels.subtitle.byte_length() > 0 else 0
    var extra_bottom = (
        Int(sc.axis_title_font_size) + sc.label_gap if plot._labels.x_title.byte_length() > 0 else 0
    )
    var extra_left = (
        Int(sc.axis_title_font_size) + sc.label_gap if plot._labels.y_title.byte_length() > 0 else 0
    )

    return _LabelsFrame(ox0 + extra_left, oy0 + extra_top, ox1, oy1 - extra_bottom)


def _label_text_requests(
    plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int, px0: Int, py0: Int, px1: Int, py1: Int
) raises -> List[_TextRequest]:
    """Builds `Plot.labels()`'s title/x_title/y_title `_TextRequest`s
    -- called by `render()`/`render_svg()` *after* `_render_generic`
    returns, unlike `_apply_labels` (phase one, see its docstring),
    which only reserves the margin these titles sit in, before
    rendering. Takes both rects: the *original* outer bounds (`ox0`..
    `oy1`, `render()`/`render_svg()` were called with -- each title's along-axis position, how far from the very top/bottom/left
    edge, is always relative to this one, unaffected by legend width)
    and the *actual* inner plot rect `_render_generic` (or whichever
    `_render_*` it dispatched to) laid the mark out in (`px0`..`py1`,
    `_RenderResult`'s fields -- each title's cross-axis
    position, centered *where*, uses this one instead: horizontal
    center for title/x_title, vertical center for y_title).
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var text_requests = List[_TextRequest]()

    if plot._labels.title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy0 + Int(sc.title_font_size * 0.8),
                plot._labels.title,
                theme.text_color,
                sc.title_font_size,
                TextAlign.CENTER,
                theme.font_family,
                bold=theme.title_bold,
            )
        )

    if plot._labels.subtitle.byte_length() > 0:
        # Stacks directly below title's reserved band -- 0 when
        # title itself is absent, the same "each of the four is
        # independent" semantics Plot.labels()'s docstring
        # establishes (a lone subtitle draws at the very top, not
        # floating below a title that isn't there).
        var title_band = Int(sc.title_font_size) + sc.label_gap if plot._labels.title.byte_length() > 0 else 0
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy0 + title_band + Int(sc.subtitle_font_size * 0.8),
                plot._labels.subtitle,
                theme.subtitle_color,
                sc.subtitle_font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    if plot._labels.x_title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy1 - Int(sc.axis_title_font_size * 0.25),
                plot._labels.x_title,
                theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    if plot._labels.y_title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                ox0 + Int(sc.axis_title_font_size * 0.8),
                (py0 + py1) // 2,
                plot._labels.y_title,
                theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                theme.font_family,
                rotation=-pi / 2.0,
            )
        )

    return text_requests^


def _draw_annotation_areas[
    T: DrawTarget
](mut target: T, plot: Plot, result: _RenderResult, theme: Theme) raises -> List[_TextRequest]:
    """Draws every `Plot.annotate_area()` shaded band directly (a plain
    `fill_rect` needs no font/glyph machinery, the same reasoning
    `_draw_annotation_lines`'s docstring gives for why *that*
    doesn't need deferring either), and returns each one's optional
    label as a `_TextRequest` for the caller to draw afterward.

    Called by `render()`/`render_svg()` right after `_render_generic`
    returns, *before* `_draw_annotation_lines` -- areas are the
    bottom-most annotation layer (a reference line or its label drawn
    on top of a band still needs to read clearly), matching every real
    chart library's markArea-under-markLine stacking order. Reuses
    the identical `result.y_scale`/`has_y_scale` mechanism `_draw_
    annotation_lines` does (see its docstring, and `_RenderResult`'s,
    for why that's the *real* scale object, not one recomputed here).
    Raises the identical clear error if any bands were requested but
    `result.has_y_scale` is `False`.

    Each band spans the *inner* plot rect's full width (`result.px0`
    to `result.px1`), filled in `Theme.annotation_area_color` -- see
    that field's docstring for why this draws as a fully opaque
    rectangle rather than a translucent overlay. Its own label, when
    non-empty, draws inside
    the band near its top edge, in `Theme.annotation_color` (not
    `annotation_area_color` -- ink and fill are different jobs, see
    that field's docstring).

    Unlike `_draw_annotation_lines`'s all-or-nothing skip, a band
    that only partially overlaps the mark's (padded) y-domain draws
    the clipped, visible portion instead of disappearing entirely --
    see `Plot.annotate_area()`'s docstring for why an area's real
    width makes that the right call where a single-row value's
    can't-partially-exist case made an outright skip the right one
    there. A band with zero overlap still draws nothing.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.area_y0) == 0:
        return text_requests^
    if not result.has_y_scale:
        raise Error(
            "Plot.annotate_area(): this mark has no continuous y-axis to place a shaded band"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER and every mark sharing"
            " _CategoricalFrame (BAR/LOLLIPOP/WATERFALL/BOX/CANDLESTICK/BULLET/GROUPED_BAR/"
            "STACKED_BAR/STREAMGRAPH)"
        )

    var sc = _Scaled(theme)
    var plot_top = min(result.py0, result.py1)
    var plot_bottom = max(result.py0, result.py1)
    for i in range(len(plot._annotations.area_y0)):
        var py_a = _axis_pixel(result.y_scale, plot._annotations.area_y0[i])
        var py_b = _axis_pixel(result.y_scale, plot._annotations.area_y1[i])
        var band_top = min(py_a, py_b)
        var band_bottom = max(py_a, py_b)
        # Clip to the visible plot rect rather than skip outright --
        # see this function's docstring for why an area's real
        # width makes clipping the right call here, unlike a reference
        # line's single-row value.
        var draw_top = max(band_top, plot_top)
        var draw_bottom = min(band_bottom, plot_bottom)
        if draw_top >= draw_bottom:
            continue
        target.fill_rect(
            result.px0, draw_top, result.px1 - result.px0, draw_bottom - draw_top, theme.annotation_area_color
        )
        var label = plot._annotations.area_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    result.px1 - sc.label_gap,
                    draw_top + Int(sc.font_size),
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.RIGHT,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_lines[
    T: DrawTarget
](mut target: T, plot: Plot, result: _RenderResult, theme: Theme) raises -> List[_TextRequest]:
    """Draws every `Plot.annotate_line()` reference line directly (a
    plain horizontal `draw_line_aa` needs no font/glyph machinery, so
    unlike a label it doesn't need to be deferred -- see `_TextRequest`'s docstring for why *that* has to be), and returns each one's optional label as a `_TextRequest` for the caller to draw afterward,
    the same split every other text-producing render step here uses.

    Called by `render()`/`render_svg()` right after `_render_generic`
    returns, using `result`'s real `y_scale` (see `_RenderResult`'s docstring for why that's the *real* scale object the mark
    itself used, not one independently recomputed here) to place each
    line's data `value` at the exact same pixel row the mark's data would land on. Raises immediately if any lines were requested
    but `result.has_y_scale` is `False` -- see `Plot.annotate_line()`'s docstring for exactly which mark types that covers today.

    Each line spans the *inner* plot rect's full width (`result.px0`
    to `result.px1`), solid, in `Theme.annotation_color`. Its own label,
    when non-empty, right-aligns just above the line's right end
    (`result.px1 - sc.label_gap`, `py - sc.label_gap`) -- a fixed,
    deterministic position, not collision-avoided against the mark's data or another annotation line landing nearby, the same
    "simple, not force-directed" scope this package's layout code
    accepts elsewhere (`Mark.GRAPH`/`BEESWARM`) when a fully
    general placement solver would be real, separate, unbuilt work.

    A `value` outside the mark's (padded) domain is silently
    skipped, not drawn wherever `LinearScale.to_pixel`'s unclamped
    linear extrapolation puts it: an unclamped out-of-range annotation
    draws well up into the title/subtitle band above the plot,
    `Theme.scale`-independent of anything about the mark itself. Not a
    raise -- an out-of-range
    target is a legitimate reading (the data just hasn't reached it
    yet), not a caller mistake the way an invalid `Theme` value would
    be, so it disappears quietly rather than erroring the whole render.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.line_values) == 0:
        return text_requests^
    if not result.has_y_scale:
        raise Error(
            "Plot.annotate_line(): this mark has no continuous y-axis to place a reference line"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER and every mark sharing"
            " _CategoricalFrame (BAR/LOLLIPOP/WATERFALL/BOX/CANDLESTICK/BULLET/GROUPED_BAR/"
            "STACKED_BAR/STREAMGRAPH)"
        )

    var sc = _Scaled(theme)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    for i in range(len(plot._annotations.line_values)):
        var py = _axis_pixel(result.y_scale, plot._annotations.line_values[i])
        # A value outside the mark's (padded) domain maps to a
        # pixel outside the visible plot rect entirely -- silently
        # skipped, not drawn wherever the unclamped linear math lands
        # (which can be well up into the title/subtitle band above the
        # plot). Not a raise: an out-of-range annotation
        # value is a legitimate state (the caller's "target" simply
        # isn't reached by the visible range yet), not a caller mistake
        # the way an invalid Theme parameter would be.
        if py < py_top or py > py_bottom:
            continue
        target.draw_line_aa(result.px0, py, result.px1, py, theme.annotation_color, width=sc.scale)
        var label = plot._annotations.line_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    result.px1 - sc.label_gap,
                    py - sc.label_gap,
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.RIGHT,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_vlines[
    T: DrawTarget
](mut target: T, plot: Plot, result: _RenderResult, theme: Theme) raises -> List[_TextRequest]:
    """`_draw_annotation_lines`'s mirror image for `Plot.annotate_
    vline()` -- a vertical line at a given x `value` instead of a
    horizontal one at a y `value`. Same mechanics throughout, just
    transposed to the other axis: uses `result.x_scale`/`has_x_scale`
    instead of `y_scale`/`has_y_scale` (raises the identical kind of
    error if a vline was requested on a mark with no continuous x-axis
    -- see `Plot.annotate_vline()`'s docstring for exactly which
    marks that is), spans the *inner* plot rect's full height
    (`result.py0` to `result.py1`) instead of its full width, and
    silently skips (never clamps) a `value` outside the mark's (padded) x-domain the same way.

    The one real difference is label placement, since the line itself
    is now vertical: right-aligned-just-above-the-line (`annotate_
    line()`'s choice, sized to avoid the line's right end)
    becomes left-aligned-just-right-of-the-line here (`px + label_gap,
    py0 + font_size`, sized to avoid the line's top end instead) --
    the same "hug the line, stay inside the plot rect" idea, just
    rotated 90 degrees with it.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.vline_values) == 0:
        return text_requests^
    if not result.has_x_scale:
        raise Error(
            "Plot.annotate_vline(): this mark has no continuous x-axis to place a reference line"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = min(result.px0, result.px1)
    var px_right = max(result.px0, result.px1)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    for i in range(len(plot._annotations.vline_values)):
        var px = _axis_pixel(result.x_scale, plot._annotations.vline_values[i])
        if px < px_left or px > px_right:
            continue
        target.draw_line_aa(px, py_top, px, py_bottom, theme.annotation_color, width=sc.scale)
        var label = plot._annotations.vline_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    px + sc.label_gap,
                    py_top + Int(sc.font_size),
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.LEFT,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_points[
    T: DrawTarget
](mut target: T, plot: Plot, result: _RenderResult, theme: Theme) raises -> List[_TextRequest]:
    """Draws every `Plot.annotate_point()` marker directly (a plain
    `fill_circle_aa` needs no font/glyph machinery, the same reasoning
    `_draw_annotation_lines`'s docstring gives), and returns each
    one's optional label as a `_TextRequest` for the caller to draw
    afterward.

    Called by `render()`/`render_svg()` last among the four annotation
    passes (areas, then vlines/lines, then points) -- a point is meant
    to call out one specific spot, so it draws on top of every other
    annotation layer, not underneath any of them. Needs *both*
    `result.x_scale` and `result.y_scale` (raises if either is missing
    -- see `Plot.annotate_point()`'s docstring for exactly which
    marks supply both), unlike every other annotation method here,
    which only ever needed one.

    A point outside the mark's (padded) domain on *either* axis is
    silently skipped, the same "an out-of-range annotation is a
    legitimate reading, not a caller mistake" rule `annotate_line()`'s docstring explains -- checked against the *inner* plot rect
    (`result.px0`..`py1`) exactly the way every other annotation method
    here already does.

    The marker itself is a plain filled circle, `sc.point_radius` (the
    same radius a standalone `Mark.POINT` plot's points use), in
    `Theme.annotation_color` -- not a distinct "pin" glyph the way
    ECharts' `markPoint` defaults to (canvas_mojo has no such shape
    primitive to draw one with; a circle is what `_draw_point_layer`
    has, and reusing it keeps this consistent with everything
    else `Theme.annotation_color` marks). Its own label, when
    non-empty, centers just above the marker (`px`, `py - radius -
    label_gap`).
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.point_x) == 0:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_point(): this mark has no continuous x/y axes to place a point"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = min(result.px0, result.px1)
    var px_right = max(result.px0, result.px1)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    var radius = _round_to_int(sc.point_radius)
    for i in range(len(plot._annotations.point_x)):
        var px = _axis_pixel(result.x_scale, plot._annotations.point_x[i])
        var py = _axis_pixel(result.y_scale, plot._annotations.point_y[i])
        if px < px_left or px > px_right or py < py_top or py > py_bottom:
            continue
        target.fill_circle_aa(px, py, radius, theme.annotation_color)
        var label = plot._annotations.point_labels[i]
        if label.byte_length() > 0:
            text_requests.append(
                _TextRequest(
                    px,
                    py - radius - sc.label_gap,
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )
    return text_requests^


def _replay_text_requests(mut canvas: Canvas, requests: List[_TextRequest], mut cache: FontCache) raises:
    """Draw every `_TextRequest` in `requests` into `canvas` via
    `canvas_mojo.text.draw_text` -- the raster half of replaying the
    deferred labels `_render_generic` and friends hand back (see
    `_TextRequest`'s docstring for why they're deferred at all).

    Shared by every raster entry point (`render()`, `render_facets()`,
    `render_layers()`) across every request list each one draws --
    the same nine-argument `draw_text` call one function, not several
    near-identical copies, so the argument list is a single place to
    change (see `_replay_text_requests_svg` for the vector
    mirror of the same collapse).
    """
    for req in requests:
        draw_text(
            canvas,
            req.x,
            req.y,
            req.text,
            req.color,
            req.size,
            align=req.align,
            family=req.family,
            weight=FontWeight.BOLD if req.bold else FontWeight.NORMAL,
            rotation=req.rotation,
            cache=cache,
        )


def _replay_text_requests_svg(mut svg: SvgCanvas, requests: List[_TextRequest]) raises:
    """`_replay_text_requests`' exact counterpart for `SvgCanvas` --
    same deferred-label replay, `SvgCanvas.draw_text` (plain markup
    emission, no glyph machinery) in place of `canvas_mojo.text.
    draw_text`, the same relationship `render_svg()` has to `render()`.
    Kept a separate function rather than folded into one `DrawTarget`-
    generic helper because `DrawTarget` deliberately has no `draw_text`
    method to dispatch through -- see canvas_mojo/draw_target.mojo's docstring for why text is the one thing that never crosses
    that trait boundary.
    """
    for req in requests:
        svg.draw_text(
            req.x,
            req.y,
            req.text,
            req.color,
            req.size,
            req.align,
            family=req.family,
            weight=FontWeight.BOLD if req.bold else FontWeight.NORMAL,
            rotation=req.rotation,
        )


def _extend_text_requests(mut dst: List[_TextRequest], src: List[_TextRequest]):
    """Append a copy of every `_TextRequest` in `src` onto `dst` -- the
    accumulate-side counterpart to the replay helpers above, collapsing
    the same `for req in ...: dst.append(req.copy())` loop that
    `_render_facets_generic`/`_render_layers_generic` each carried
    several copies of while gathering their per-cell/per-layer labels
    into one combined list.
    """
    for req in src:
        dst.append(req.copy())


def render(
    mut canvas: Canvas, plot: Plot, ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1
) raises:
    """Render `plot` into `canvas` -- fills its outer bounds
    (background, then gridlines, axes, tick labels, and finally the
    mark itself, in that back-to-front order) rather than compositing
    into whatever was there before.

    `ox0`/`oy0`/`ox1`/`oy1` default to the whole canvas (`ox1`/`oy1`'s
    default of -1 means "canvas.width"/"canvas.height" -- a real
    negative bound is never meaningful, so it's a safe sentinel, not
    an ambiguous one) -- every existing single-plot call keeps
    rendering into the entire canvas exactly as before. Passing a
    narrower rectangle instead (what `render_facets()` does, one call
    per grid cell) makes this one plot's margins, axes, and
    optional legend lay out relative to that sub-rectangle instead of
    the whole canvas -- the plot has no idea it's sharing a canvas
    with anything else.

    A thin wrapper around `_render_generic` (see this module's docstring for why rendering is split this way): resolves the
    sentinel bounds against `canvas`'s size, reserves room for any
    `Plot.labels()` title/axis titles via `_apply_labels` (see its docstring for why that happens *here*, not inside `_render_generic`
    itself), hands the shrunk rect off to the shared generic core for
    everything else, then builds the title(s)' `_TextRequest`s via
    `_label_text_requests` -- only now, using the *inner* plot rect
    `_render_generic` actually returned (`_RenderResult`'s `px0`..
    `py1`), so a title/x_title centers on the real data area rather
    than the full outer bounds (see `_apply_labels`'s docstring for
    why this is a two-phase split) -- and finally draws every
    `_TextRequest` (the title(s) plus whatever `_render_generic` itself
    returned) via `canvas_mojo.text.draw_text` -- the one piece
    `_render_generic` itself can't do, since it's generic over any
    `DrawTarget` and drawing real text needs `canvas_mojo.text`'s native glyph machinery, specific to this raster path (see
    `_TextRequest`'s docstring).

    The whole *original* `(ox0, oy0)`-`(cx1, cy1)` rect is filled with
    `theme.background` before anything else -- not just the shrunk
    inner rect handed downstream -- so a title's reserved margin
    strip gets painted too, rather than showing whatever `canvas` held
    before this call (which usually happens to match anyway, but isn't
    guaranteed to).

    This is the *only* background fill on this path -- `_render_
    generic` and every mark-specific `_render_*` fill nothing of their
    own, since any second fill would always be a strict subset of this
    one, in the same color: one whole extra full-target fill per render
    (at a 640x420 chart's quickplot-supersampled 1920x1260 scratch
    canvas -- see `_rendered`'s docstring -- about 2.4M redundant pixel
    writes per chart). Painting the background is the *entry point's*
    job, once, and each of the four entry points does it: here,
    `render_svg()`, `_render_facets_generic` (per cell -- see its
    comment) and `render_layers()`/`render_layers_svg()`.

    Never supersampled on its own -- every pixel-sized quantity here
    scales only by `plot._theme.scale` (see `Theme`'s docstring),
    exactly the value the caller set, nothing added silently. This is
    the precise, pixel-for-pixel entry point real HiDPI export and
    this whole test suite's hand-verified pixel assertions rely
    on; `_rendered()` -- what every one-call convenience function
    (`bar()`, `scatter()`, ...) calls instead of this directly -- is
    the one place a fixed supersample factor gets applied
    automatically, invisibly to its caller, precisely because nothing
    there needs that precision (see its docstring for why the two
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
    var area_annotation_requests = _draw_annotation_areas(canvas, plot, result, plot._theme)
    var vline_annotation_requests = _draw_annotation_vlines(canvas, plot, result, plot._theme)
    var annotation_requests = _draw_annotation_lines(canvas, plot, result, plot._theme)
    var point_annotation_requests = _draw_annotation_points(canvas, plot, result, plot._theme)
    # One FontCache shared by every label this render draws. Without
    # it each draw_text() resolves its font from scratch -- twice,
    # in fact, since draw_text measures and then renders (see canvas_
    # mojo/text/font_cache.mojo's docstring). A chart's labels all
    # share one font, so resolving it once per render instead of twice
    # per label is pure saved work, with byte-identical output.
    var text_cache = FontCache()
    _replay_text_requests(canvas, label_requests, text_cache)
    _replay_text_requests(canvas, area_annotation_requests, text_cache)
    _replay_text_requests(canvas, vline_annotation_requests, text_cache)
    _replay_text_requests(canvas, annotation_requests, text_cache)
    _replay_text_requests(canvas, point_annotation_requests, text_cache)
    _replay_text_requests(canvas, result.text_requests, text_cache)


def render_svg(
    mut svg: SvgCanvas, plot: Plot, ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1
) raises:
    """`render()`'s exact counterpart for `SvgCanvas` -- same
    sentinel-resolution, same `_apply_labels`/`_render_generic` core,
    same `_TextRequest` lists handed back afterward; the only
    difference is *how* those get drawn (`SvgCanvas.draw_text`, plain
    markup emission, no font/glyph machinery involved at all) -- see
    `render()`'s docstring for the shared story, and canvas_mojo/
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
    var area_annotation_requests = _draw_annotation_areas(svg, plot, result, plot._theme)
    var vline_annotation_requests = _draw_annotation_vlines(svg, plot, result, plot._theme)
    var annotation_requests = _draw_annotation_lines(svg, plot, result, plot._theme)
    var point_annotation_requests = _draw_annotation_points(svg, plot, result, plot._theme)
    _replay_text_requests_svg(svg, label_requests)
    _replay_text_requests_svg(svg, area_annotation_requests)
    _replay_text_requests_svg(svg, vline_annotation_requests)
    _replay_text_requests_svg(svg, annotation_requests)
    _replay_text_requests_svg(svg, point_annotation_requests)
    _replay_text_requests_svg(svg, result.text_requests)


def accessible_svg_string(svg: SvgCanvas, title: String, description: String = "") raises -> String:
    """`svg.to_string()`, with real SVG accessibility markup added:
    `role="img"` and `aria-label` on the root `<svg>` element, plus a
    `<title>` (and, when `description` is non-empty, a `<desc>`) as its
    very first child elements -- exactly what the SVG accessibility
    spec, and every screen reader that supports SVG at all, looks for:
    `<title>` becomes the element's accessible name, `<desc>` its
    longer description, `aria-label` a redundant fallback for tools
    that only read attributes and never walk into child elements at
    all.

    `title` is required (there's no sensible fallback text a chart's data could supply on its own -- unlike `Plot.labels()`'s `title`, which is optional chrome, an *accessible* name is the one
    piece of text a screen reader user gets in place of seeing the
    chart, so silently shipping a blank one would be strictly worse
    than raising). Reasonable text is often the same string already
    passed to `.labels(title=...)` -- this function doesn't read `Plot`
    at all, so nothing stops a caller from just passing that same
    variable to both.

    A thin post-processing wrapper around `svg.to_string()`, not a
    canvas_mojo change: reuses that package's (leading-underscore,
    so importable -- see the wiki's Mojo-conventions entry) `_escape_
    xml_text`/`_escape_xml_attr` helpers rather than duplicating XML-
    escaping logic here, and depends on `to_string()`'s exact,
    currently-stable output shape (`<svg ...>` as the literal first
    four bytes, its opening tag's first `>` therefore always the
    very first `>` in the whole string) to find where to splice new
    markup in -- there's no public seam in `SvgCanvas` today for
    attaching root-element attributes or leading child elements, so
    this reconstructs the opening tag itself around the original one
    rather than asking canvas_mojo to grow one; if `SvgCanvas.to_string`
    ever changes shape, this needs revisiting too.

    A real, honest scope note: this only helps when the SVG's accessible tree actually gets walked -- inline `<svg>...</svg>`
    markup in an HTML page, a standalone `.svg` opened directly, or an
    `<object data="...">`/`<iframe>` embed all expose it. A plain `<img
    src="chart.svg">` -- which is exactly how this project's docs
    site embeds every example (see gen_example_docs.mojo's docstring) -- does not: a browser treats an `<img>`-embedded SVG as
    an opaque image and never parses its inner markup into the
    accessible tree at all, so a screen reader there reads the `<img>`
    tag's `alt` text instead (which the docs site already gets, for
    free, from Markdown's own `![alt](url)` syntax -- see gen_example_
    docs.mojo's page-building code -- a separate, pre-existing
    mechanism this function doesn't touch). Nothing about that makes
    this function pointless -- inline/standalone/object embedding are
    all real, common ways an SVG chart ends up on a page -- just know
    which category a given embedding falls into before expecting this
    to be what makes it accessible there.
    """
    var s = svg.to_string()
    var tag_end = s.find(">")
    if tag_end == -1:
        raise Error(
            "accessible_svg_string: svg.to_string() produced no root element to attach"
            " accessibility markup to"
        )
    var opening_tag = String(s[byte=0:tag_end])
    var rest = String(s[byte=tag_end:])

    var escaped_title_attr = _escape_xml_attr(title)
    var accessible_tag = opening_tag + ' role="img" aria-label="' + escaped_title_attr + '"'

    var children = "<title>" + _escape_xml_text(title) + "</title>\n"
    if description.byte_length() > 0:
        children += "<desc>" + _escape_xml_text(description) + "</desc>\n"

    return accessible_tag + String(rest[byte=0:1]) + children + String(rest[byte=1:])


def write_accessible_svg(svg: SvgCanvas, path: String, title: String, description: String = "") raises:
    """`accessible_svg_string()`, written to `path` -- the same
    relationship `canvas_mojo.vector.svg.write_svg` has to `SvgCanvas.
    to_string()`. See that function's docstring for what gets
    added and why, including its honest scope note about which
    embedding contexts actually benefit from any of this.
    """
    var f = open(path, "w")
    f.write(accessible_svg_string(svg, title, description))
    f.close()


struct _PointChannels(Movable):
    """Every derived value `Mark.POINT`'s three optional data-driven
    channels (categorical color, continuous color, continuous size --
    see `Plot.encode`'s docstring) need: which of the three are
    actually encoded, the categorical domain and palette a discrete
    color column indexes into, and the `ColorScale`/`LinearScale` a
    continuous color/size column maps through.

    Built unconditionally, even for a plot encoding none of the three
    (every `has_*` False, both lists empty, both scales built over a
    placeholder `[0, 1]` domain and never queried) -- one code
    path, not a branch duplicated per combination.

    A struct rather than five separate locals because these are needed
    at *two* different points in one render, either side of a step that
    happens in between: once before the plot rect is finalized, to size
    the legend column around the labels that will actually go in it
    (`_legend_reserve_for`), and once after, to color/size each point
    and draw those same legend sections (`_draw_point_layer`). Computing
    them once and handing the same value to both is what keeps the two
    provably consistent -- a column sized for one palette and then drawn
    with another would be a silent layout bug.
    """

    var has_color: Bool
    var has_color_categories: Bool
    var has_size: Bool
    # The categorical color column's domain *and* each row's index
    # into it, resolved once here rather than searched per point at
    # draw time -- see `_categorical_indices`' docstring. Held as
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
        self.color_scale = ColorScale.from_theme(plot._theme, color_mm.min, color_mm.max)
        self.size_mm = _min_max(plot.size_data) if self.has_size else MinMax(0.0, 1.0)
        self.size_scale = LinearScale(
            self.size_mm.min, self.size_mm.max, sc.size_range_min, sc.size_range_max
        )


def _validate_categorical_encoding(plot: Plot) raises:
    """`Plot.encode_categorical()`'s length check -- the categorical
    counterpart to `_validate_continuous_encoding` below, and extracted
    for exactly the reason that one was: every `Mark` reading a
    category/value pair carried a verbatim copy of it, differing in
    nothing at all.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_categorical(): x and y must have the same length"
            " (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )


def _require_non_negative(values: List[Float64], mark_name: String) raises:
    """Every value non-negative, or raise naming `mark_name`.

    A negative value has no meaningful width/radius/area for any of the
    marks that call this, so they all refuse to draw rather than
    silently misrepresent the data -- see `mark_arc()`'s docstring
    for that stance stated in full.
    """
    for v in values:
        if v < 0.0:
            raise Error(
                "Plot: " + mark_name + " values must be non-negative (got " + String(v) + ")"
            )


def _require_some_positive(values: List[Float64], mark_name: String) raises -> Float64:
    """The largest of `values`, having checked at least one is strictly
    positive -- the companion to `_require_non_negative` for the marks
    whose geometry divides by the maximum (`value / max` for a rose's radius, a polar bar's length, a ring's sweep), where
    all-zero input has no defined layout at all rather than merely a
    degenerate one.

    Returns that maximum rather than just raising on a bad one, because
    every caller needs it immediately afterwards as the divisor -- and
    computing it twice (once to check, once to use) is exactly the
    split that let the check and the value drift apart in the first
    place.
    """
    var largest = 0.0
    for v in values:
        if v > largest:
            largest = v
    if largest <= 0.0:
        raise Error(
            "Plot: "
            + mark_name
            + " requires at least one positive value (largest value was "
            + String(largest)
            + ")"
        )
    return largest


def _validate_continuous_encoding(plot: Plot, context: String) raises:
    """Every check `Plot.encode()`'s x/y/color/color_categories/size
    channels need before a continuous-axis render can start -- shared
    verbatim by the single-plot path (`_render_generic`) and the
    layered one (`_render_layers_generic`).

    `context` prefixes every message so each caller still reports the
    thing a caller can actually act on: `"Plot.encode()"` for a
    standalone plot, `"render_layers(): layer 2"` for one layer of a
    stack (strictly more locating than the old layered wording, which
    said "a layered plot's x and y" without ever naming which one).

    Deliberately *not* the `Mark.POINT`/`LINE`/`AREA` allow-list
    `render_layers()` also enforces -- that one is genuinely specific to
    layering (a standalone `Mark.BAR` plot is perfectly legal, a layered
    one isn't), so it stays at its call site rather than becoming a
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
    """`Theme.line_smoothing`'s `[0.0, 1.0]` range check -- see that
    field's docstring (theme.mojo) for why anything outside that
    range has no assigned meaning here rather than being clamped.
    Called by `_draw_line_layer`/`_draw_area_layer`, so it now covers
    the layered render path too; that path built its `Path` inline
    and never checked (nor applied) smoothing at all before those two
    functions existed.
    """
    if theme.line_smoothing < 0.0 or theme.line_smoothing > 1.0:
        raise Error(
            "Theme.line_smoothing must be in [0.0, 1.0] (got " + String(theme.line_smoothing) + ")"
        )


def _legend_reserve_for(plot: Plot, ch: _PointChannels, sc: _Scaled) raises -> Int:
    """How much width `plot`'s legend column needs, or `0` when it
    has no legend at all (`Theme.show_legend` off, a non-`Mark.POINT`
    mark, or no data-driven channel encoded -- every other mark either
    has its separate legend logic or none).

    A plot can combine continuous color *and* size, stacking both
    sections in one column -- so the width is whichever section needs
    more room, not a sum (they stack vertically, not side by side). Categorical color and
    continuous color are mutually exclusive already
    (`_validate_continuous_encoding`), so at most one of the first two
    ever contributes.

    Called *before* the plot rect is finalized, the same "measure the
    real labels before sizing the margin around them" ordering the
    y-axis's dynamic left margin requires -- see
    `_dynamic_legend_width`'s docstring.

    Has a `cache=` overload, for the same reason `_max_label_width`
    does -- `_render_generic` shares one cache between this and the
    axis frame's tick measurement.
    """
    var cache = FontCache()
    return _legend_reserve_for(plot, ch, sc, cache=cache)


def _legend_reserve_for(
    plot: Plot, ch: _PointChannels, sc: _Scaled, *, mut cache: FontCache
) raises -> Int:
    """`_legend_reserve_for` measuring through `cache` instead of
    fresh -- see the overload above. A plot combining continuous color
    *and* size measures twice in here alone, so even a single call
    benefits from sharing."""
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
        reserve = max(
            reserve, _dynamic_legend_width(ch.cat.domain, sc.legend_swatch_size, sc, cache=cache)
        )
    elif ch.has_color:
        var color_labels = List[String]()
        color_labels.append(_format_fixed(ch.color_scale.domain_max, 1))
        color_labels.append(_format_fixed(ch.color_scale.domain_min, 1))
        reserve = max(
            reserve,
            _dynamic_legend_width(color_labels, sc.continuous_legend_bar_width, sc, cache=cache),
        )
    if ch.has_size:
        var size_labels = List[String]()
        size_labels.append(_format_fixed(ch.size_mm.max, 1))
        size_labels.append(_format_fixed((ch.size_mm.min + ch.size_mm.max) / 2.0, 1))
        size_labels.append(_format_fixed(ch.size_mm.min, 1))
        var circle_content_width = 2 * _round_to_int(sc.size_range_max)
        reserve = max(
            reserve, _dynamic_legend_width(size_labels, circle_content_width, sc, cache=cache)
        )
    return reserve


struct _ContinuousFrame(Movable):
    """`_draw_continuous_axis_frame`'s finished layout -- the
    continuous-x counterpart to `_CategoricalFrame` (see its docstring), with a `LinearScale` on both axes instead of an
    `OrdinalScale` on one.

    `px0`/`py0`/`px1`/`py1` are the finished inner plot rect, carried
    through unchanged for the caller's `_RenderResult` -- same
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
        `_CategoricalFrame.result`'s docstring, which this mirrors
        exactly (including passing `self.y_scale` through for `Plot.
        annotate_line()`, covering `Mark.POINT`/`LINE`/`AREA`/`EFFECT_
        SCATTER` -- and, since `_render_layers_generic` shares this
        exact frame, every layered plot too). Also passes `self.x_scale`
        through, unlike `_CategoricalFrame.result()` -- this is the one
        frame with a genuine continuous x-axis, so it's the only one
        `Plot.annotate_vline()`/`annotate_point()` can support (see
        `_RenderResult`'s docstring)."""
        return _RenderResult(
            self.text_requests.copy(),
            self.px0,
            self.py0,
            self.px1,
            self.py1,
            self.y_scale,
            True,
            self.x_scale,
            True,
        )


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
    *,
    mut cache: FontCache,
) raises -> _ContinuousFrame:
    """The layout and axis-frame-drawing core every continuous-x render
    path shares -- `_draw_categorical_axis_frame`'s direct
    counterpart (see its docstring for the shared reasoning) for a plot
    whose x-axis is a continuous `LinearScale` rather than
    `OrdinalScale` bands: computes the dynamic left margin from
    `y_scale`'s ticks, resolves both scales' pixel ranges against
    the resulting plot rect, and draws gridlines, both axis lines, and
    every x/y tick mark plus its label.

    Extracted for exactly the reason its categorical sibling was: a
    *second* caller needed the identical ~90 lines. `_render_generic`'s continuous path and `_render_layers_generic` had carried
    near-verbatim copies of this since layering was added, and they had
    already drifted apart in a user-visible way (see
    `_draw_line_layer`'s docstring for the specific behavior the
    layered copy silently lost).

    Both scales' *domains* must already be decided (their ranges are the
    usual `[0, 1]` placeholder `_data_extent`/`_zero_baseline_y_extent`
    return) -- deliberately parameters, not computed in here, since the
    two callers decide them differently: one plot's data for a
    standalone render, every layered plot's data combined for a stacked
    one, with the zero-baseline rule keyed off `Mark.AREA` in each case.
    That is the entire difference between the two paths, which is
    exactly why it's the only thing left at their call sites.

    `legend_reserve` is subtracted from the right edge before the rect
    is finalized (`0` when there's no legend) -- the same "shrink the
    rect from outside, don't thread a flag through the shared core"
    pattern `_apply_labels` and `_render_grouped_bar` both use.
    """
    var sc = _Scaled(theme)

    # y-domain ticks computed before plot_x0 is finalized -- a scale's
    # own tick *values* (and so their formatted label text) depend only
    # on domain_min/domain_max, never on range_min/range_max (see
    # LinearScale.ticks()'s docstring), so its labels can be
    # measured and the left margin sized to actually fit them, `max`'d
    # against Theme's configured minimum so no existing plot's
    # layout ever gets *narrower* than it already was -- purely
    # additive, only ever growing the margin for labels wide enough to
    # actually need it (see _max_label_width's docstring).
    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels()
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size, cache=cache))
        + sc.tick_length
        + sc.label_gap
        + sc.margin_buffer
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
    # at the top -- see LinearScale's docstring.
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
                theme.font_family,
            )
        )

    # Baseline offset so a label's glyphs sit roughly vertically
    # centered on its tick, not hanging entirely below it --
    # draw_text's y is the text baseline (see text.mojo's docstring), so without this every y-axis label would appear
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
                theme.font_family,
            )
        )

    return _ContinuousFrame(
        out_x_scale, out_y_scale, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1
    )


def _lighten(color: Color, alpha: UInt8) -> Color:
    """`color` blended toward opaque white by `alpha` -- `Mark.
    EFFECT_SCATTER`'s halo tint (see `_draw_point_layer`'s `draw_halo` paragraph) and `Mark.RADAR`'s series-polygon fill,
    which pass `Theme.halo_alpha` and `Theme.radar_fill_alpha`
    respectively. `alpha` is a parameter, not a fixed constant, because
    the two callers are unrelated -- a single shared number would
    silently tie a scatter halo's tint to a radar fill's. Built via
    `Color.blend_over` (give `color`
    a reduced alpha, composite it over white, keep the fully-opaque
    result) rather than real alpha transparency on the halo circle
    itself: both backends can render true alpha now, but that would
    blend against whatever's *behind* the halo, not always white --
    a real design choice to revisit, not a workaround for a missing
    primitive.
    """
    return Color(color.r, color.g, color.b, alpha).blend_over(Color(255, 255, 255))


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
    """Draw one `Mark.POINT` plot's points into an already-laid-out
    continuous axis frame, plus whatever legend sections its encoded
    channels call for -- the whole of what a `Mark.POINT` mark
    contributes to a render, shared by the standalone path and by each
    `Mark.POINT` layer of a stacked one. Also `Mark.EFFECT_SCATTER`'s
    entire render (`draw_halo=True`) -- see this function's halo
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

    Everything else comes from `plot`'s `Theme` -- row height, font
    size, colors, point radius -- so a layer styled differently from its
    neighbors draws its section correctly rather than being forced
    through the shared chrome's styling.

    `draw_halo`, when set, draws one extra circle *underneath* each
    point first -- `_lighten`ed toward white, ~2x the radius -- a
    static stand-in for `Mark.EFFECT_SCATTER`'s real ECharts
    behavior (an animated ripple), which a raster/SVG renderer with no
    animation concept can't reproduce; see `_lighten`'s docstring
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
            # every row's domain index up front (see
            # _categorical_indices' docstring).
            color = ch.palette[ch.cat.indices[i] % len(ch.palette)]
        else:
            color = theme.mark_color
        var radius = (
            _round_to_int(ch.size_scale.to_pixel(plot.size_data[i]))
            if ch.has_size
            else _round_to_int(sc.point_radius)
        )
        if draw_halo:
            target.fill_circle_aa(px, py, _round_to_int(Float64(radius) * 2.2), _lighten(color, theme.halo_alpha))
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
    """Draw one `Mark.LINE` plot's stroked path into an already-
    laid-out continuous axis frame -- `Theme.line_smoothing` included
    (`_build_line_path`, see its docstring).

    Shared by the standalone and layered paths, which is the point: a
    layered `Mark.LINE` honors `Theme.line_smoothing` and its range
    check exactly the way a standalone one does -- exactly the kind
    of thing two near-identical copies of the same drawing code are
    for. Routing both through one function guarantees it by
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
    # Drop sub-pixel detail before the rasterizer has to pay for it --
    # a no-op for any series small enough that its points are
    # individually resolvable (see _decimate_to_pixel_columns).
    var thinned = _decimate_to_pixel_columns(px, py)
    var path = _build_line_path(thinned.px, thinned.py, theme.line_smoothing)
    target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)


def _draw_area_layer[
    T: DrawTarget
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.AREA` plot's filled region into an already-
    laid-out continuous axis frame: the same curve `_draw_line_layer`
    strokes (`_build_line_path`, `Theme.line_smoothing` included), but
    closed down to the zero baseline (`y_scale`'s domain already
    guarantees zero is a real point in range -- see
    `_zero_baseline_y_extent`) and filled instead of stroked.

    Only the *top* edge (through the data points) smooths; the bottom
    edge (the two `line_to`s down to and along baseline) is always
    straight -- baseline is a fixed reference line, not data, so there's
    nothing for it to curve through, the same reasoning a real chart
    library's smoothed-area fill never bends its flat baseline
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
    # Same sub-pixel thinning the stroked path gets -- the fill's top edge is exactly that curve (see this function's docstring).
    var thinned = _decimate_to_pixel_columns(px, py)
    var path = _build_line_path(thinned.px, thinned.py, theme.line_smoothing)
    path.line_to(thinned.px[len(thinned.px) - 1], baseline_py)
    path.line_to(thinned.px[0], baseline_py)
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
    drawn as text (see `_TextRequest`'s docstring for why they
    aren't drawn directly here).

    `Mark.BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`/`CANDLESTICK`/`BULLET`/
    `GANTT`/`GROUPED_BAR`/`STACKED_BAR`/`ARC` dispatch to their fully separate functions immediately -- the first nine have a
    genuinely different axis layout (`OrdinalScale` bands for at least
    one axis, not a plain continuous `LinearScale` pair; the first six
    plus `GROUPED_BAR`/`STACKED_BAR` share one vertical axis-frame core
    with each other -- see `_draw_categorical_axis_frame`'s docstring -- while `GANTT` has its horizontal mirror, `_draw_
    horizontal_categorical_axis_frame`, see its docstring for why
    it isn't a third shared core), and `ARC` has no x/y axis frame at
    all, so threading any of them through nearly every line below would
    be far less readable than each staying its function (see
    `_render_bar`/`_render_arc`'s docstrings).

    What's left after the dispatch -- the `Mark.POINT`/`LINE`/`AREA`
    continuous-axis path -- is itself just a short assembly of
    shared pieces, in the same shape every categorical `_render_*`
    has: decide the two domains (the only genuinely per-path
    decision, see `_draw_continuous_axis_frame`'s docstring), size
    the legend column (`_legend_reserve_for`), draw the axis frame
    (`_draw_continuous_axis_frame`), then draw the one mark
    (`_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`). Every
    one of those is shared with `_render_layers_generic`.

    `Plot.secondary_axis()` only means anything inside `render_layers()`/
    `render_layers_svg()` (a second series to pair its y-domain
    against) -- raises here rather than silently ignoring it on a
    standalone plot, the same "raise on a setting that can't apply"
    rule `annotate_line()`/`x_title`/`y_title`-on-`Mark.ARC` already
    follow.
    """
    if plot._secondary_axis:
        raise Error(
            "Plot.secondary_axis() only applies inside render_layers()/"
            "render_layers_svg() -- a standalone plot has only one"
            " series, nothing for a second y-axis to pair against"
        )
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
    if plot._mark == Mark.SPAN_CHART:
        return _render_span_chart(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.POPULATION_PYRAMID:
        return _render_population_pyramid(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.HEATMAP:
        return _render_heatmap(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.CALENDAR_HEATMAP:
        return _render_calendar_heatmap(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.CORRPLOT:
        return _render_corrplot(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.PUNCHCARD:
        return _render_punchcard(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.MARIMEKKO:
        return _render_marimekko(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.SUNBURST:
        return _render_sunburst(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.TREE:
        return _render_tree(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.TREEMAP:
        return _render_treemap(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.CHORD:
        return _render_chord(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.ARC_DIAGRAM:
        return _render_arc_diagram(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.GRAPH:
        return _render_graph(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.SANKEY:
        return _render_sankey(target, plot, ox0, oy0, ox1, oy1)
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
    if plot._mark == Mark.RIDGELINE:
        return _render_ridgeline(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.ARC:
        return _render_arc(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.NIGHTINGALE:
        return _render_nightingale(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.POLAR_BAR:
        return _render_polar_bar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.RADIALBAR:
        return _render_radialbar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.POLAR:
        return _render_polar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.RADAR:
        return _render_radar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.GAUGE:
        return _render_gauge(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.PARALLEL:
        return _render_parallel(target, plot, ox0, oy0, ox1, oy1)

    _validate_continuous_encoding(plot, "Plot.encode()")

    var theme = plot._theme
    if len(plot.x_data) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    # Every pixel-sized Theme/module-constant quantity below, scaled
    # once by theme.scale -- see _Scaled's docstring.
    var sc = _Scaled(theme)

    # Built once and handed to both _legend_reserve_for (which sizes
    # the legend column before the plot rect is final) and _draw_point_
    # layer (which colors/sizes each point afterward) -- see
    # _PointChannels' docstring for why the two have to agree.
    var ch = _PointChannels(plot, sc)

    # One FontCache for every measurement this render makes. Both the
    # legend sizing below and the axis frame's tick-label
    # measurement resolve the same font; a fresh cache per call re-pays
    # canvas_mojo's font resolution *and* its TTF parse (0.44ms for a
    # 5-label call, against 0.056ms once warm), which is pure waste
    # when the two calls are microseconds apart in the same render.
    var measure_cache = FontCache()
    var legend_reserve = _legend_reserve_for(plot, ch, sc, cache=measure_cache)

    # The one thing that differs between this path and the layered one:
    # whose data the two domains are computed over (see _draw_
    # continuous_axis_frame's docstring). Mark.AREA forces a zero
    # baseline into the y-domain, every other continuous mark just pads
    # around its data.
    var y_scale = (
        _zero_baseline_y_extent(plot.y_data) if plot._mark == Mark.AREA else _data_extent(plot.y_data)
    )
    var x_scale = _data_extent(plot.x_data)

    var frame = _draw_continuous_axis_frame(
        target, x_scale, y_scale, theme, legend_reserve, ox0, oy0, ox1, oy1, cache=measure_cache
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
    (`Mark.BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`) draws its per-
    category shape into -- see `_draw_categorical_axis_frame`'s docstring for what it computes and why factoring this out (and not
    the continuous-x path `_render_generic` itself covers) was the
    right call.

    `px0`/`py0`/`px1`/`py1` are the finished inner plot rect (the same
    `plot_x0`/`plot_y0`/`plot_x1`/`plot_y1` this frame's axis lines
    are drawn at) -- carried through unchanged so each caller can build
    its `_RenderResult` from them, rather than re-deriving the rect
    from `x_scale`/`y_scale`'s range fields (see `_RenderResult`'s docstring for why that rect matters)."""

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
        line every mark's `_render_*` ends with, once it has drawn
        whatever per-category shape it exists to draw.

        A `.copy()` of `text_requests`, not a `^` transfer: Mojo's
        ownership checker rejects moving a single field out of a struct
        ("field 'self.text_requests' destroyed out of the middle of a
        value"), since the rest of the frame still owns `x_scale`/
        `y_scale`/`sc` and needs its normal end-of-scope destruction --
        including with an owned `var self` and with every field
        consumed in turn. Mojo has no piecewise-destructuring form that
        satisfies it, so the copy isn't a workaround for a borrow that
        could have been avoided by restructuring. It's a small `List`
        either way, and it now happens in exactly one place instead of
        eleven.

        Passes `self.y_scale` through as `_RenderResult`'s real
        y-scale (`has_y_scale=True`) -- every mark sharing this frame
        (`BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`/`CANDLESTICK`/`BULLET`/
        `GROUPED_BAR`/`STACKED_BAR`/`STREAMGRAPH`) gets `Plot.annotate_
        line()` support this way, for free, from this one change --
        see `_RenderResult`'s docstring for why exposing the real
        scale object here (not a value independently recomputed later)
        is the point.
        """
        return _RenderResult(
            self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1, self.y_scale, True
        )


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
    categorical-x-axis mark (`Mark.BAR`, `LOLLIPOP`, `WATERFALL`, `BOX`):
    computes the dynamic left margin from `y_scale`'s ticks, builds the
    `OrdinalScale` x-axis, draws gridlines/axis lines/y-tick
    marks+labels and every category's x-tick mark+label -- everything
    these mark types draw identically. Returns the finished
    `x_scale`/`y_scale` (pixel ranges resolved) plus the already-scaled
    `_Scaled` theme and the `_TextRequest`s collected so far, for the
    caller to draw its per-category shape into (a filled rect, a
    stem+point, a floating rect, a box+whiskers -- the one genuinely
    different piece between these mark types, deliberately left to
    each one's function rather than threaded through here, matching
    `_render_bar`'s long-standing "a mark-type branch through nearly
    every line is worse than each path staying its function"
    reasoning). Shared once four near-identical ~130-line copies of
    this same layout math exist -- past the two-call-sites-tolerate-
    duplication threshold `_draw_horizontal_categorical_axis_frame`'s
    own docstring states for the opposite case (why *that* one stays
    unshared).

    The per-category x-tick+label loop and the per-category
    mark-drawing loop are two separate passes -- harmless for both
    backends, since ticks/labels live below the plot area and every
    mark shape lives inside it, regions that never overlap; every
    hand-derived pixel and SVG-substring assertion for `Mark.BAR`
    passes completely unchanged.

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
    # LinearScale's docstring.
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
                theme.font_family,
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
                theme.font_family,
            )
        )

    return _CategoricalFrame(x_scale^, out_y_scale, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def render_facets(mut canvas: Canvas, plots: List[Plot], cols: Int) raises:
    """Render each of `plots` into its evenly sized grid cell on
    `canvas` -- see `_render_facets_generic`'s docstring for the
    actual cell-layout contract this and `render_facets_svg` share. A
    thin wrapper exactly like `render()`'s own: resolve `canvas`'s size, hand off to the shared generic core, draw the `_TextRequest`s
    it returns via `canvas_mojo.text.draw_text`.
    """
    var text_requests = _render_facets_generic(canvas, canvas.width, canvas.height, plots, cols)
    # One FontCache for every cell's labels -- see render()'s own.
    var text_cache = FontCache()
    _replay_text_requests(canvas, text_requests, text_cache)


def render_facets_svg(mut svg: SvgCanvas, plots: List[Plot], cols: Int) raises:
    """`render_facets()`'s exact counterpart for `SvgCanvas` -- same
    shared `_render_facets_generic` core, `SvgCanvas.draw_text` in
    place of `canvas_mojo.text.draw_text` for the returned labels, the same
    relationship `render_svg()` has to `render()` (see that function's docstring).
    """
    var text_requests = _render_facets_generic(svg, svg.width, svg.height, plots, cols)
    _replay_text_requests_svg(svg, text_requests)


def _render_facets_generic[
    T: DrawTarget
](mut target: T, width: Int, height: Int, plots: List[Plot], cols: Int) raises -> List[_TextRequest]:
    """The shared cell-layout core `render_facets()`/`render_facets_svg()`
    both delegate to -- generic over any `DrawTarget`, the same
    `_render_generic`/`render()`/`render_svg()` split (see that
    function's docstring). `width`/`height` are passed in
    explicitly by each wrapper (`Canvas.width`/`.height` for one,
    `SvgCanvas.width`/`.height` for the other) rather than read off
    `target` itself -- `DrawTarget` deliberately has no width/height
    accessor of its own, the same reason it has no `draw_text` (see
    that trait's docstring): `Canvas` already has a public `width`
    field, and a same-named trait *method* would collide with it.

    `cols` columns, enough rows to fit `len(plots)` (a final row
    that isn't completely full just leaves its remaining cells blank,
    not stretched to cover them). Each cell is laid out exactly the
    way a standalone `render(canvas, plot)` call would lay out the
    whole target -- its margins, its axes, its optional
    legend, even its mark type, *and*, unlike this function's original version, its `Plot.labels()` title/x_title/y_title too
    (`_apply_labels`/`_label_text_requests`, the same two-phase split
    `render()`/`render_svg()` use -- see their docstrings) -- one
    title per cell, from that cell's `Plot`, not one shared title
    for the whole grid: each cell is its independent small
    multiple, with its data and potentially its mark type, so a
    per-cell caption is the only reading that makes sense here (see
    the wiki's Changelog, its "Plot.labels() reaches render_facets/
    render_layers" entry for why `render_layers`, sharing one
    combined domain across every layer, reads differently). `_render_
    generic`'s `ox0`/`oy0`/`ox1`/`oy1` bounds are simply pointed at
    one cell's *label-shrunk* rect instead of the whole target per
    call, so nothing about it needed to know facets exist. Every cell's `_TextRequest`s (label text plus whatever `_render_generic`
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
    left edge): a naive per-cell width computed once and repeated
    would let integer-division rounding error accumulate across
    columns instead of resetting at every boundary.

    A separate function from `_render_generic` itself, not a `plots:
    List` overload of it -- one `Plot` in, one whole target out is
    `_render_generic`'s contract; this is a distinct "many plots,
    one target, grid layout" contract composed on top of it, the same
    relationship `_render_bar`/`_render_arc` have to `_render_generic`'s continuous-x path (composition, not a mode flag threaded
    through one function).

    Each cell's `Plot.annotate_area()`/`annotate_line()` draw too
    (`render()`/`render_svg()`'s scope note about this not being
    wired up yet was for `render_facets()`/`render_layers()` both --
    this closes the `render_facets()` half): one cell, one independent
    `Plot`, so a cell's annotations mean exactly what they'd mean
    rendered standalone, no shared-coordinate-system ambiguity to
    resolve the way `render_layers()`'s single combined domain has (see
    `_render_layers_generic`'s docstring for that one instead).
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
        # Each cell's *full* rect, filled from that cell's Plot's
        # background before anything else -- the same "the whole
        # original rect gets painted, including the strip a title's
        # margin reserved" contract render()/render_svg() already
        # document. Filling only _render_generic's own label-shrunk
        # rect instead would leave a titled cell's top band showing
        # whatever the canvas held before this call.
        target.fill_rect(
            cell_x0, cell_y0, cell_x1 - cell_x0, cell_y1 - cell_y0, plots[i]._theme.background
        )
        var frame = _apply_labels(plots[i], cell_x0, cell_y0, cell_x1, cell_y1)
        var cell_result = _render_generic(target, plots[i], frame.ox0, frame.oy0, frame.ox1, frame.oy1)
        var label_requests = _label_text_requests(
            plots[i], cell_x0, cell_y0, cell_x1, cell_y1, cell_result.px0, cell_result.py0, cell_result.px1, cell_result.py1
        )
        # Each cell's Plot.annotate_area()/annotate_line() draw
        # against that cell's real y_scale, exactly the way a
        # standalone render()/render_svg() call already does -- one
        # cell, one independent Plot, so there's no "which cell's annotations should draw" ambiguity the way render_layers()'s
        # shared coordinate system has (see _render_layers_generic's
        # own docstring for how that one's handled instead). Areas
        # drawn before lines, the same per-plot stacking order render()/
        # render_svg() use.
        var cell_area_requests = _draw_annotation_areas(target, plots[i], cell_result, plots[i]._theme)
        var cell_line_requests = _draw_annotation_lines(target, plots[i], cell_result, plots[i]._theme)
        _extend_text_requests(text_requests, label_requests)
        _extend_text_requests(text_requests, cell_area_requests)
        _extend_text_requests(text_requests, cell_line_requests)
        _extend_text_requests(text_requests, cell_result.text_requests)

    return text_requests^


def _secondary_axis_y_title(plots: List[Plot]) -> String:
    """`render_layers()`'s secondary (right) y-axis caption -- the
    first layer's `Plot.labels()`'s `y_title` where that layer also
    called `.secondary_axis()`, read per-layer the same way `mark_color`/
    `line_smoothing`/`annotate_line()` already are there, not shared
    chrome sourced from `plots[0]` the way `title`/`x_title`/the *primary*
    `y_title` are. No new field or builder method needed for this --
    `Plot.secondary_axis()`'s docstring flagged a caption as
    deferred, real work; reusing the `y_title` every layer already has,
    read from whichever layer actually owns the secondary axis, turned
    out to be enough. Empty (the common case, and every pre-existing
    render_layers() call's case) when no secondary-axis layer set
    one, or there's no secondary-axis layer at all."""
    for i in range(len(plots)):
        if plots[i]._secondary_axis and plots[i]._labels.y_title.byte_length() > 0:
            return plots[i]._labels.y_title
    return ""


def render_layers(mut canvas: Canvas, plots: List[Plot], ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1) raises:
    """Render every `Plot` in `plots` onto *one shared* coordinate
    system on `canvas` -- one combined x/y domain (computed across
    every layered plot's data together, not each plot's independent domain the way `render_facets()`'s cells each get),
    one shared set of axes/gridlines/ticks, each plot's mark drawn
    on top of the last in the order given -- a line overlaid on a
    scatter, three comparison lines sharing one y-axis, and so on.

    Restricted to `Mark.POINT`/`LINE`/`AREA` --
    `Mark.BAR`'s categorical x-axis and `Mark.ARC`'s lack of one don't
    share a domain shape with continuous marks or each other; layering
    those in is real, separate, deferred work (see the wiki's Backlog).
    Raises if any layered plot uses a different mark.

    A layer built via `Plot.secondary_axis()` scales its y values
    against a second, independent y-domain drawn on the plot's right
    edge instead of the shared (primary/left) one every other layer's
    data combines into -- a revenue-bars-and-growth-rate-line combo
    chart, where the two series' units are too different to share
    one axis without one going flat. See that method's docstring
    for the full mechanics (no gridlines of its own, at least one layer
    must stay on the primary axis).

    A layer whose mark is `Mark.POINT` can use `color`/`color_
    categories`/`size` encoding exactly like a standalone `Mark.POINT`
    plot (see `Plot.encode`'s docstring) -- each such layer's domain (color scale, size scale, category palette) is independent
    of every other layer's, the same "each layer's `Theme` only
    governs its mark's appearance" independence `mark_color`/
    `point_radius`/`line_width` already have. Raises the identical
    "only Mark.POINT" error `Plot.encode`'s single-plot path raises
    if a `LINE`/`AREA` layer tries to use one of these instead. A
    caller wanting several distinctly colored *series* instead (rather
    than per-point encoding within one series) still sets each layer's flat `Theme.mark_color` (the same per-layer-styling `examples/
    facets.mojo` uses, just overlaid here instead of laid out
    in a grid) -- `render_layers` still has no per-*series* name/label
    concept for a "which layer is which" legend built from several
    flat-colored layers (see the wiki's Backlog, its "Explicitly
    still open" section); that's a separate feature from per-point
    encoding within a single layer, which this one now supports.

    Shared chrome -- background, gridlines, axis colors, margins, font
    size, tick spacing -- comes from `plots[0]`'s `Theme`; every
    other layered plot's `Theme` only governs its mark's
    appearance (`mark_color`, `point_radius`, `line_width`, and --
    since every render path now builds its curve through the same
    `_build_line_path`, see `_draw_line_layer`'s docstring -- `line_
    smoothing`, each still scaled by that plot's `Theme.scale`; see
    `_Scaled`'s docstring). A layered `Mark.LINE`/`AREA` curves exactly
    the way the identical plot rendered standalone through `render()`
    does, and rejects an out-of-`[0.0, 1.0]` value there the same way
    too. Each encoding-using `Mark.POINT` layer draws its legend
    section(s) (gated by that layer's `Theme.show_legend`,
    not `plots[0]`'s), stacked in one shared column in layer order --
    the same categorical/continuous-color/size section types and
    stacking order `_render_generic`'s single-plot `Mark.POINT`
    legend uses (see its docstring), just once per
    encoding-using layer instead of once per plot. The legend column's horizontal position is shared (every section starts at the
    identical x, from the combined `plot_x1`), but each section's row height/font size/colors come from that specific layer's `Theme` -- so differently-scaled or differently-styled layers each
    draw their section correctly, not forced through `plots[0]`'s
    styling.

    `Plot.labels()`'s title/x_title/y_title -- like every other piece of
    shared chrome -- come from `plots[0]`'s labels, not each layer's (a layered plot has one combined coordinate system, so one
    shared title is the only reading that makes sense here, unlike
    `render_facets()`'s per-cell titles -- see that function's docstring). The same `_apply_labels`/`_label_text_requests`
    two-phase split `render()`/`render_svg()` use.

    The one exception: a secondary-axis layer's `y_title` captions
    the secondary axis itself, mirrored onto the plot's right edge (see
    `_secondary_axis_y_title`'s docstring for why this reads per-
    layer rather than only from `plots[0]`) -- absent whenever no
    secondary-axis layer sets one, which is every pre-existing call.

    `ox0`/`oy0`/`ox1`/`oy1` are the exact same sentinel-bounds
    convention `render()` itself uses (see that function's docstring) -- default to the whole canvas.
    """
    var cx1 = ox1 if ox1 >= 0 else canvas.width
    var cy1 = oy1 if oy1 >= 0 else canvas.height
    # An empty plots list is a real, tested no-op (test_render_layers_
    # with_empty_list_is_a_noop) -- _apply_labels needs plots[0], so
    # labels are skipped entirely rather than indexing an empty list;
    # _render_layers_generic's own empty check leaves the canvas
    # untouched in that case.
    if len(plots) == 0:
        _ = _render_layers_generic(canvas, plots, ox0, oy0, cx1, cy1)
        return
    canvas.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plots[0]._theme.background)
    var sc = _Scaled(plots[0]._theme)
    var y2_title = _secondary_axis_y_title(plots)
    var frame = _apply_labels(plots[0], ox0, oy0, cx1, cy1)
    if y2_title.byte_length() > 0:
        # Mirrors _apply_labels's extra_left reservation for the
        # primary y_title exactly, just on the right edge instead --
        # see _secondary_axis_y_title's docstring for why this
        # isn't inside _apply_labels itself (that function only ever
        # sees plots[0], never the full layer list a secondary-axis
        # caption has to be found in).
        frame.ox1 -= Int(sc.axis_title_font_size) + sc.label_gap
    var result = _render_layers_generic(canvas, plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1)
    var label_requests = _label_text_requests(
        plots[0], ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    if y2_title.byte_length() > 0:
        # The mirror image of _label_text_requests's primary y_title
        # block: rotated the opposite way (+pi/2 instead of -pi/2, the
        # standard "read top-to-bottom" convention a right-side axis
        # caption uses, vs. the left side's "read bottom-to-top"),
        # anchored to the outer right edge instead of the outer left one.
        label_requests.append(
            _TextRequest(
                cx1 - Int(sc.axis_title_font_size * 0.8),
                (result.py0 + result.py1) // 2,
                y2_title,
                plots[0]._theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                plots[0]._theme.font_family,
                rotation=pi / 2.0,
            )
        )
    # One FontCache for every layer's labels -- see render()'s own.
    var text_cache = FontCache()
    _replay_text_requests(canvas, label_requests, text_cache)
    _replay_text_requests(canvas, result.text_requests, text_cache)


def render_layers_svg(mut svg: SvgCanvas, plots: List[Plot], ox0: Int = 0, oy0: Int = 0, ox1: Int = -1, oy1: Int = -1) raises:
    """`render_layers()`'s exact counterpart for `SvgCanvas` -- same
    shared `_render_layers_generic` core, `SvgCanvas.draw_text` in
    place of `canvas_mojo.text.draw_text` for the returned labels, the same
    relationship `render_svg()` has to `render()`.
    """
    var cx1 = ox1 if ox1 >= 0 else svg.width
    var cy1 = oy1 if oy1 >= 0 else svg.height
    # See render_layers()'s comment just above -- same empty-list
    # guard, needed here too since _apply_labels indexes plots[0].
    if len(plots) == 0:
        _ = _render_layers_generic(svg, plots, ox0, oy0, cx1, cy1)
        return
    svg.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plots[0]._theme.background)
    var sc = _Scaled(plots[0]._theme)
    var y2_title = _secondary_axis_y_title(plots)
    var frame = _apply_labels(plots[0], ox0, oy0, cx1, cy1)
    if y2_title.byte_length() > 0:
        frame.ox1 -= Int(sc.axis_title_font_size) + sc.label_gap
    var result = _render_layers_generic(svg, plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1)
    var label_requests = _label_text_requests(
        plots[0], ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    if y2_title.byte_length() > 0:
        label_requests.append(
            _TextRequest(
                cx1 - Int(sc.axis_title_font_size * 0.8),
                (result.py0 + result.py1) // 2,
                y2_title,
                plots[0]._theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                plots[0]._theme.font_family,
                rotation=pi / 2.0,
            )
        )
    _replay_text_requests_svg(svg, label_requests)
    _replay_text_requests_svg(svg, result.text_requests)


def _render_layers_generic[
    T: DrawTarget
](mut target: T, plots: List[Plot], ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """The shared-domain layout/draw core `render_layers()`/
    `render_layers_svg()` both delegate to -- generic over any
    `DrawTarget`, the same `_render_generic`/`render()`/`render_svg()`
    split (see that function's docstring). Still a standalone
    function, not `_render_generic` itself made to accept a list --
    "one plot, one target" and "many plots, one shared coordinate
    system" stay two contracts, not one function with a mode flag --
    but no longer a standalone *copy* of it: the domain/margin/axis
    layout and every mark's drawing are the same shared functions
    the single-plot path calls (`_draw_continuous_axis_frame`,
    `_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`), leaving
    only what's genuinely different here -- domains computed across
    *all* layered plots' data at once, a legend column sized across
    every layer, and a legend-y cursor threaded through them in order.

    Returns a `_RenderResult`, like every other `_render_*` function
    (see its docstring) -- `render_layers()`/`render_layers_svg()`
    use the inner rect it carries to center `Plot.labels()`'s title/x_title/y_title (sourced from `plots[0]`, see their docstrings) on the real, shared plot area.

    `Plot.secondary_axis()`: a layer with it set is excluded from the
    combined (primary) y-domain and instead gets its own, built the
    same way -- `_zero_baseline_y_extent`/`_data_extent` over just its group's data, the identical `Mark.AREA`-forces-zero-baseline
    rule applied independently within each group. The secondary axis
    draws mirrored onto the plot's right edge (its axis line, ticks,
    tick labels -- measured and reserved the same "measure the domain's ticks, size the margin to fit them" way `_draw_continuous_axis_
    frame` sizes the *left* margin, just inlined here since it's
    the only caller), with no gridlines of its own (see `Plot.secondary_
    axis()`'s docstring for why). Its reserved width sits between
    the plot's inner rect and the legend column -- `legend_x` shifts
    right by exactly that amount so a legend and a secondary axis never
    overlap; `0` (and so an unchanged `legend_x`) whenever no layer uses
    one, keeping every pre-existing single-axis render byte-for-byte
    unchanged.

    Each layer's `Plot.annotate_area()`/`annotate_line()` draw too --
    see `_render_facets_generic`'s docstring for the `render_facets()`
    side of the same wiring. Unlike `render_facets()`'s "one cell, one
    Plot" case, several layers share one coordinate system here, so
    which layer's annotations mean what against which axis needed
    an actual answer: each layer's annotations draw against *that
    layer's own* y_scale (primary or secondary, whichever `Plot.
    secondary_axis()` put it on) -- the identical scale that layer's mark just drew against, not the combined domain some other
    layer might be using. Drawn last, on top of every layer's mark,
    the same "annotations after the mark" order `render()`/`render_svg()`
    use.
    """
    var text_requests = List[_TextRequest]()
    if len(plots) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    for i in range(len(plots)):
        # The one check that's genuinely layering-specific and so stays
        # here rather than moving into the shared validator: a
        # standalone Mark.BAR plot is perfectly legal, a layered one
        # isn't (see _validate_continuous_encoding's docstring).
        if not (
            plots[i]._mark == Mark.POINT or plots[i]._mark == Mark.LINE or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): only Mark.POINT/Mark.LINE/Mark.AREA can be layered"
                " (got a different mark -- see the wiki's Backlog for why Mark.BAR/"
                "Mark.ARC aren't supported here yet)"
            )
        _validate_continuous_encoding(plots[i], "render_layers(): layer " + String(i))

    var has_secondary = False
    var has_primary = False
    for i in range(len(plots)):
        if plots[i]._secondary_axis:
            has_secondary = True
        else:
            has_primary = True
    if has_secondary and not has_primary:
        raise Error(
            "render_layers(): at least one layer must stay on the primary y-axis"
            " (every layer calling .secondary_axis() leaves nothing for"
            " \"secondary\" to mean relative to)"
        )

    var theme = plots[0]._theme

    var combined_x = List[Float64]()
    var combined_y = List[Float64]()
    var combined_y2 = List[Float64]()
    var any_area = False
    var any_area2 = False
    for i in range(len(plots)):
        for v in plots[i].x_data:
            combined_x.append(v)
        if plots[i]._secondary_axis:
            for v in plots[i].y_data:
                combined_y2.append(v)
            if plots[i]._mark == Mark.AREA:
                any_area2 = True
        else:
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
    # domains span *every* primary-axis layer's data at once, rather
    # than one plot's own (see _draw_continuous_axis_frame's docstring). A single Mark.AREA layer anywhere in the primary group
    # forces the zero baseline in for the whole primary y-axis, the same
    # rule Mark.AREA follows on its own -- and independently again for
    # the secondary group, if there is one.
    var y_scale = _zero_baseline_y_extent(combined_y) if any_area else _data_extent(combined_y)
    var x_scale = _data_extent(combined_x)

    var has_secondary_data = has_secondary and len(combined_y2) > 0
    var y_scale2 = LinearScale(0.0, 0.0, 0.0, 1.0)
    if has_secondary_data:
        y_scale2 = _zero_baseline_y_extent(combined_y2) if any_area2 else _data_extent(combined_y2)

    # secondary_axis_reserve, sized the same way _draw_continuous_axis_
    # frame sizes the dynamic *left* margin for the primary axis: measure
    # the secondary domain's tick labels (depends only on the
    # domain, decided above, never on pixel range -- see _max_label_
    # width's docstring), then tick_length + label_gap + margin_
    # buffer beyond that. 0 when no layer uses a secondary axis, so
    # legend_x below is unchanged for every single-axis render.
    # One FontCache for every measurement this layered render makes --
    # see _render_generic's own. This path benefits most: the secondary
    # axis measures here, then the loop below sizes one legend section
    # per layer, so an N-layer chart was building N+2 separate caches
    # (re-resolving and re-parsing the same font each time) where one
    # now serves the whole render.
    var measure_cache = FontCache()

    var secondary_axis_reserve = 0
    if has_secondary_data:
        var y2_ticks_for_margin = y_scale2.ticks()
        var y2_labels_for_margin = y2_ticks_for_margin.labels()
        secondary_axis_reserve = (
            Int(_max_label_width(y2_labels_for_margin, sc.font_size, cache=measure_cache))
            + sc.tick_length
            + sc.label_gap
            + sc.margin_buffer
        )

    # legend_reserve, computed across every encoding-using Mark.POINT
    # layer before the plot rect is finalized. Each layer's section
    # width measured with that layer's _Scaled (font size, swatch
    # size all independently scaled, matching every other per-layer
    # style choice here), `max`'d together into one shared column width
    # -- sections stack vertically in one column, so the column's width is whichever section needs the most room, not a sum.
    var legend_reserve = 0
    for j in range(len(plots)):
        var p_sc_j = _Scaled(plots[j]._theme)
        var ch_j = _PointChannels(plots[j], p_sc_j)
        legend_reserve = max(
            legend_reserve, _legend_reserve_for(plots[j], ch_j, p_sc_j, cache=measure_cache)
        )

    var frame = _draw_continuous_axis_frame(
        target,
        x_scale,
        y_scale,
        theme,
        legend_reserve + secondary_axis_reserve,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=measure_cache,
    )
    _extend_text_requests(text_requests, frame.text_requests)

    # The secondary axis line/ticks/labels -- drawn at the plot rect's
    # own right edge (frame.px1), the mirror image of the primary axis
    # already drawn at frame.px0 by _draw_continuous_axis_frame above:
    # ticks point right instead of left, labels sit left-aligned just
    # past them instead of right-aligned just before. No gridlines (see
    # Plot.secondary_axis()'s docstring for why).
    var out_y_scale2 = y_scale2
    out_y_scale2.range_min = Float64(frame.py1)
    out_y_scale2.range_max = Float64(frame.py0)
    if has_secondary_data:
        var y2_ticks = out_y_scale2.ticks()
        var y2_labels = y2_ticks.labels()
        var y2_label_baseline_offset = Int(sc.font_size * 0.35)
        target.draw_line_aa(frame.px1, frame.py0, frame.px1, frame.py1, theme.axis_color, width=sc.scale)
        for i in range(len(y2_ticks.values)):
            var py = _axis_pixel(out_y_scale2, y2_ticks.values[i])
            target.draw_line_aa(
                frame.px1, py, frame.px1 + sc.tick_length, py, theme.axis_color, width=sc.scale
            )
            text_requests.append(
                _TextRequest(
                    frame.px1 + sc.tick_length + sc.label_gap,
                    py + y2_label_baseline_offset,
                    y2_labels[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.LEFT,
                    theme.font_family,
                )
            )

    # The legend column's x is shared (every section starts at the
    # identical x, from the combined plot rect, shifted past the
    # secondary axis's reserved width when one is drawn), while
    # legend_y is a running cursor threaded through every encoding-using
    # layer's section(s) -- the same "each section returns the y
    # just below it for the next to start at" stacking a single plot's
    # own legend uses, just walked once per layer here instead of once
    # per plot.
    var legend_x = frame.px1 + secondary_axis_reserve + sc.margin_right
    var legend_y = frame.py0
    for j in range(len(plots)):
        if len(plots[j].x_data) == 0:
            continue
        var layer_y_scale = out_y_scale2 if plots[j]._secondary_axis else frame.y_scale
        if plots[j]._mark == Mark.POINT:
            var p_sc = _Scaled(plots[j]._theme)
            var ch_j = _PointChannels(plots[j], p_sc)
            legend_y = _draw_point_layer(
                target, text_requests, plots[j], ch_j, frame.x_scale, layer_y_scale, legend_x, legend_y
            )
        elif plots[j]._mark == Mark.LINE:
            _draw_line_layer(target, plots[j], frame.x_scale, layer_y_scale)
        elif plots[j]._mark == Mark.AREA:
            _draw_area_layer(target, plots[j], frame.x_scale, layer_y_scale)

    # Each layer's Plot.annotate_area()/annotate_line() draw last,
    # on top of every layer's mark (the same "annotations drawn
    # after the mark itself" order render()/render_svg() use) --
    # against *that layer's own* y_scale (primary or secondary,
    # whichever `Plot.secondary_axis()` put it on), not render_facets()'s
    # simpler "one cell, one Plot" case: a layered render shares one
    # coordinate system across several Plots, so which layer's annotations mean what against which axis needed an actual answer,
    # not just reusing render_facets()'s approach unchanged. A
    # throwaway `_RenderResult` per layer, built from the shared plot
    # rect plus that one layer's y_scale, is enough to reuse `_draw_
    # annotation_areas`/`_draw_annotation_lines` unmodified -- neither
    # function needs anything else `_RenderResult` carries.
    for j in range(len(plots)):
        var layer_y_scale = out_y_scale2 if plots[j]._secondary_axis else frame.y_scale
        var layer_result = _RenderResult(
            List[_TextRequest](), frame.px0, frame.py0, frame.px1, frame.py1, layer_y_scale, True
        )
        var layer_area_requests = _draw_annotation_areas(target, plots[j], layer_result, plots[j]._theme)
        var layer_line_requests = _draw_annotation_lines(target, plots[j], layer_result, plots[j]._theme)
        _extend_text_requests(text_requests, layer_area_requests)
        _extend_text_requests(text_requests, layer_line_requests)

    return _RenderResult(text_requests^, frame.px0, frame.py0, frame.px1, frame.py1)


def _rendered(
    var plot: Plot,
    theme: Theme,
    width: Int,
    height: Int,
    title: String,
    x_title: String,
    y_title: String,
    subtitle: String = "",
) raises -> Canvas:
    """Everything every function in this module does once its mark
    and data are chosen: apply the shared `title`/`subtitle`/`x_title`/
    `y_title` and `theme` to the half-built `plot`, then render it -- at
    `_QUICKPLOT_SUPERSAMPLE` times `width`/`height`, into a scratch
    `Canvas` that size, immediately shrunk back down via
    `canvas_mojo.resize.downsample` -- and return the result, a
    `Canvas` of exactly `width`x`height` with genuinely finer-grained
    anti-aliasing baked in than a direct `render()` at that same size
    would produce (see `downsample()`'s docstring for why this,
    not a single-resolution render, is what "finer AA" actually means
    here).

    Shared by all thirteen functions here -- the two chained builder
    calls that pick the mark and encode the data are the only part
    that differs between them. `.labels()`/`.theme()` are applied here
    rather than at each call site for the same reason: nothing about
    them varies by mark.

    Supersampling is the one place this logic exists at all, not a
    cleaned-up version of a pattern each caller writes for itself --
    nothing about it (the `_QUICKPLOT_SUPERSAMPLE` factor, the scaled
    `Theme`, the `downsample()` call) is about *what chart to draw*,
    only *how not to make its edges look worse than they have to*. A
    caller who wants that control back still has it, just spelled
    explicitly rather than defaulted invisibly: build the `Canvas`/
    `Plot` by hand and call `render()` directly, whose `Theme.scale` is
    exactly the same multiplicative knob this function uses internally
    (see its docstring) -- `render()` itself stays exactly as un-
    supersampled as it always was, deliberately: it's the precise,
    pixel-for-pixel entry point real HiDPI export and this whole test
    suite's hand-verified pixel assertions depend on, so hiding
    this mechanism inside quickplot's convenience layer doesn't
    touch it at all.

    A caller who renders the same `plot` through this function twice
    at different sizes sees no leftover effect of one call on the
    next -- `theme` is never mutated in place, only copied into a
    fresh, larger-`scale` `Theme` each time, since `Theme` is a plain
    value type and `theme.scale` here is always relative to the
    caller's untouched `theme.scale`, not something this function
    remembers between calls.

    Takes `plot` as `var` (owned) because `Plot`'s builder methods
    consume and return `Self` -- see plot.mojo's module docstring
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
    render(
        scratch,
        plot^.labels(title=title, subtitle=subtitle, x_title=x_title, y_title=y_title).theme(scaled_theme),
    )
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
