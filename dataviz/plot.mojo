"""Plot, the fluent builder every chart goes through. Data is plain
columnar `List[Float64]`/`List[String]` passed to `encode()`/
`encode_categorical()`/the other `encode_*` methods; builder methods
consume and return `Self` (`var self` -> `return self^`) so calls
chain: `Plot().mark_point().encode(x=xs, y=ys).theme(t)`.

`render(plot)`/`render_svg(plot)` turn a Plot into a `Canvas`/
`SvgCanvas` sized `plot.width` x `plot.height`; `save()` picks the
backend from the file extension. Each wraps a core (`_render_into`/
`_render_svg_into`) that fills the background, reserves title margins
(`_apply_labels`), and hands off to `_render_generic`;
`render_facets()`/`render_layers()` have their own per-cell/
shared-canvas variants of that pattern.

Everything shares one `[T: DrawTarget]` rendering core except text:
`DrawTarget` has no `draw_text` (raster text needs `canvas.text`'s
FreeType/fontconfig machinery, SVG text needs markup), so labels are
collected as `_TextRequest`s during the generic pass and each entry
point draws them afterward. Raster draws use the anti-aliased
`Canvas` variants throughout.

This file holds what every mark shares: the `Plot` struct (whose
methods must live with its definition, so `encode_histogram()`/
`encode_waterfall()` delegate to free functions in their mark's
file), `_render_generic`'s dispatch, and the shared frames, legends,
labels, scales, facets, and layers. Every other mark's `_render_*`
lives in its own file, which imports from here and is imported back,
a circular import Mojo resolves within one package.

## The one-call convenience functions

Each mark's file also holds its one-call function (`bar()` in
bar.mojo, `pie()` in arc.mojo, ...), with `scatter()`/`line()`/
`area()` here. Import them from the package (`from dataviz import
bar, scatter`). Each is `Plot().mark_*().encode*(...)` plus `theme`,
`width`/`height`, and `title`/`subtitle`/`x_title`/`y_title` applied
by `_finished()`, returning the same plain `Plot` a hand-built chain
would. Facets, layering, and `color`/`size` encoding still need the
`Plot` builder directly.
"""

from std.collections import Dict
from std.math import cos, log10, pi, sin

from canvas.buffer import Canvas
from canvas.color import Color
from canvas.gradient import LinearGradient
from canvas.fill_rule import FillRule
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.resize import downsample
from canvas.vector.draw_target import DrawTarget
from canvas.geometry import _round_to_int
from canvas.path import Path
from canvas.vector.svg import SvgCanvas, _escape_xml_text, _escape_xml_attr
from canvas.text.render import draw_text, measure_text, FontWeight, TextAlign
from canvas.text.font_cache import FontCache

from dataviz.array_like import (
    Float64Sequence,
    StringSequence,
    _materialize_floats,
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
    _materialize_strings,
)
from dataviz.numpy_interop import _materialize_python_floats
from std.python import PythonObject
from dataviz.color_scale import ColorScale, default_categorical_palette
from dataviz.marker import PointShape, _fill_shape_aa, default_marker_shapes
from dataviz.mark import Mark
from dataviz.ordinal_scale import OrdinalScale
from dataviz.output_format import OutputFormat
from dataviz.scale import (
    LinearScale,
    MinMax,
    _format_fixed,
    _format_tick,
    _label_decimals,
    _min_max,
)
from dataviz.theme import Theme
from dataviz.x_label_rotation import XAxisLabelRotation

from dataviz.arc import _render_arc
from dataviz.nightingale import _render_nightingale
from dataviz.polar import _render_polar
from dataviz.polar_bar import _render_polar_bar
from dataviz.gauge import _render_gauge
from dataviz.parallel import _render_parallel
from dataviz.radar import _render_radar
from dataviz.bar import (
    _render_bar,
    _render_horizontal_bar,
    _draw_bar_rects,
    _bar_y_domain_data,
)
from dataviz.beeswarm import _render_beeswarm, _render_horizontal_beeswarm
from dataviz.ridgeline import _render_ridgeline
from dataviz.violin import _render_violin, _render_horizontal_violin
from dataviz.waterfall import _WaterfallData
from dataviz.box import _BoxData
from dataviz.candlestick import _CandleData
from dataviz.bullet import _BulletData
from dataviz.population_pyramid import _PyramidData
from dataviz.heatmap import _HeatmapData
from dataviz.polar import _PolarData
from dataviz.radar import _RadarData
from dataviz.gauge import _GaugeData
from dataviz.parallel import _ParallelData
from dataviz.calendar_heatmap import _CalendarData
from dataviz.corrplot import _CorrplotData
from dataviz.punchcard import _PunchcardData
from dataviz.barbs import _BarbsData
from dataviz.marimekko import _MarimekkoData
from dataviz.edges import _EdgeData
from dataviz.hierarchy import _HierarchyData
from dataviz.box import _box_stats, _render_box, _render_horizontal_box
from dataviz.bullet import _render_bullet
from dataviz.candlestick import _render_candlestick
from dataviz.gantt import _render_gantt
from dataviz.span_chart import _render_span_chart
from dataviz.bump import _render_bump
from dataviz.chord import _render_chord
from dataviz.funnel import _render_funnel
from dataviz.grouped_bar import (
    _render_grouped_bar,
    _render_horizontal_grouped_bar,
)
from dataviz.heatmap import _render_heatmap
from dataviz.calendar_heatmap import _render_calendar_heatmap
from dataviz.corrplot import _render_corrplot
from dataviz.punchcard import _render_punchcard
from dataviz.barbs import _render_barbs
from dataviz.marimekko import _render_marimekko
from dataviz.sunburst import _render_sunburst
from dataviz.tree import _render_tree
from dataviz.treemap import _render_treemap
from dataviz.arc_diagram import _render_arc_diagram
from dataviz.graph import _render_graph
from dataviz.sankey import _render_sankey
from dataviz.radialbar import _render_radialbar
from dataviz.histogram import _bin_histogram
from dataviz.lollipop import _render_lollipop, _render_horizontal_lollipop
from dataviz.single_axis import _render_single_axis
from dataviz.population_pyramid import _render_population_pyramid
from dataviz.stacked_bar import (
    _render_stacked_bar,
    _render_horizontal_stacked_bar,
)
from dataviz.streamgraph import _render_streamgraph
from dataviz.waterfall import _render_waterfall, _waterfall_running_totals


struct _Scaled(Movable):
    """Every pixel-sized quantity the render paths draw with, pre-multiplied
    by `theme.scale` in one place (see `Theme.scale`). Built fresh from a
    Theme at the top of each render function; a handful of multiplies,
    not cached.

    `scale` itself is the raw multiplier, for the one place that needs the
    bare factor: every axis line/gridline/tick mark is drawn
    `width=sc.scale` pixels wide, since those strokes have no `Theme`
    width field of their own and would otherwise stay 1 pixel wide at any
    `scale`.
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
    var error_bar_cap_width: Float64

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
        self.continuous_legend_bar_width = Int(
            Float64(theme.continuous_legend_bar_width) * s
        )
        self.continuous_legend_bar_height = Int(
            Float64(theme.continuous_legend_bar_height) * s
        )
        self.error_bar_cap_width = theme.error_bar_cap_width * s


struct _GanttData(Copyable, Movable):
    """One start/end span per category, for `Mark.GANTT`/`SPAN_CHART`. See
    `encode_gantt()`. Stored on `Plot._gantt`.
    """

    var start: List[Float64]
    var end: List[Float64]

    def __init__(out self):
        self.start = List[Float64]()
        self.end = List[Float64]()


struct _GroupedBarData(Copyable, Movable):
    """One name per series and one value per (series, category) pair, for
    `Mark.GROUPED_BAR`/`STACKED_BAR`/`BUMP`/`STREAMGRAPH`. See
    `encode_grouped_bar()`. Stored on `Plot._grouped_bar`.
    """

    var series_names: List[String]
    var values: List[List[Float64]]
    var errors: List[List[Float64]]
    """Optional per-(series, category) symmetric error-bar half-width
    (#216), shaped like `values`; empty when `encode_grouped_bar()`'s
    `errors` wasn't given. `Mark.GROUPED_BAR` only, checked in
    `_validate_grouped_bar_series`."""

    def __init__(out self):
        self.series_names = List[String]()
        self.values = List[List[Float64]]()
        self.errors = List[List[Float64]]()


struct _DistributionData(Copyable, Movable):
    """One list of raw values per category, kept unsummarized, for
    `Mark.BEESWARM`/`VIOLIN`/`RIDGELINE`. See `encode_distribution()`.
    Stored on `Plot._distribution`.

    `kde_bandwidth_override` is a caller's kernel-density bandwidth,
    overriding each category's Silverman's-rule default; 0.0 means use
    the default. `kde_scale_by_count` selects ggplot2's `scale = "area"`
    (scale each category's maximum width/rise by `sqrt(n_i / max(n))`)
    over the default `scale = "width"`. See `mark_violin()`/
    `mark_ridgeline()`.
    """

    var values: List[List[Float64]]
    var kde_bandwidth_override: Float64
    var kde_scale_by_count: Bool

    def __init__(out self):
        self.values = List[List[Float64]]()
        self.kde_bandwidth_override = 0.0
        self.kde_scale_by_count = False


struct _MarkStyle(Copyable, Movable):
    """Per-mark appearance knobs, each read by exactly one mark's render
    function and set only through that mark's `mark_*()` parameters (or
    its one-call convenience function). Stored on `Plot._mark_style`.

    These are geometry (angles, ring counts, width fractions) describing
    one chart's proportions, so they live here rather than on `Theme`,
    which holds what a theme can restyle; per-mark colors stayed on
    `Theme` so a dark theme can fix contrast without every caller passing
    a color. `point_tooltips` is behavioural rather than geometric but
    belongs here for the same reason: whether a scatter can afford an SVG
    `<title>` per point depends on how many points this chart has (see
    `mark_point()`).

    Field names keep their mark prefix (`gauge_start_angle`) since several
    would otherwise collide (`polar_grid_rings`/`radar_grid_rings`); the
    parameters that set them drop it (`mark_gauge(start_angle=...)`).
    """

    var point_tooltips: Bool
    var donut_inner_radius_fraction: Float64
    var bullet_measure_width_fraction: Float64
    var waterfall_delta_width_fraction: Float64
    var chord_ring_fraction: Float64
    var radialbar_ring_gap_fraction: Float64
    var radar_grid_rings: Int
    var violin_width_fraction: Float64
    var corrplot_bubble_fraction: Float64
    var gauge_band_inner_fraction: Float64
    var gauge_needle_fraction: Float64
    var gauge_start_angle: Float64
    var gauge_sweep_angle: Float64
    var ridgeline_overlap: Float64
    var polar_bar_padding: Float64
    var polar_grid_rings: Int
    var polar_grid_spokes: Int
    var sankey_node_width: Float64

    def __init__(out self):
        self.point_tooltips = False
        self.donut_inner_radius_fraction = 0.0
        self.bullet_measure_width_fraction = 0.35
        self.waterfall_delta_width_fraction = 0.6
        self.chord_ring_fraction = 0.08
        self.radialbar_ring_gap_fraction = 0.25
        self.radar_grid_rings = 4
        self.violin_width_fraction = 0.4
        self.corrplot_bubble_fraction = 0.42
        self.gauge_band_inner_fraction = 0.7
        self.gauge_needle_fraction = 0.9
        self.gauge_start_angle = 3.0 * pi / 4.0
        self.gauge_sweep_angle = 3.0 * pi / 2.0
        self.ridgeline_overlap = 1.3
        self.polar_bar_padding = 0.2
        self.polar_grid_rings = 4
        self.polar_grid_spokes = 12
        self.sankey_node_width = 12.0


struct _DomainOverride(Copyable, Movable):
    """An explicit `[min, max]` axis domain set via `.scale_x_domain()`/
    `.scale_y_domain()` (#209), overriding the padded/zero-baselined
    domain `_data_extent()`/`_zero_baseline_y_extent()` would otherwise
    compute. `has` is `False` (the default -- no override) until one of
    those builder methods sets it. Stored on `Plot._x_domain`/`_y_domain`.
    """

    var has: Bool
    var min: Float64
    var max: Float64

    def __init__(out self):
        self.has = False
        self.min = 0.0
        self.max = 0.0

    def __init__(out self, min: Float64, max: Float64):
        self.has = True
        self.min = min
        self.max = max


struct _LabelData(Copyable, Movable):
    """Chart/axis title text set via `.labels()`; an empty string means not
    set. Stored on `Plot._labels`.
    """

    var title: String
    var subtitle: String
    var x_title: String
    var y_title: String
    var description: String
    """A longer SVG `<desc>` than `subtitle` need be (#212); see
    `Plot.labels()`'s own docstring. `save()`/`save_layers()`/
    `save_facets()` fall back to `subtitle` when this is empty."""
    var series_name: String
    """This layer's name in `render_layers()`'s per-layer legend (#215);
    see `Plot.series_name()`'s own docstring. Empty (the default) draws
    no legend row for this layer. `render()`/`render_svg()` ignore it --
    a standalone plot has only one series, nothing for a legend entry to
    distinguish."""

    def __init__(out self):
        self.title = ""
        self.subtitle = ""
        self.x_title = ""
        self.y_title = ""
        self.description = ""
        self.series_name = ""


struct _AnnotationData(Copyable, Movable):
    """Annotations, stored on `Plot._annotations`. Each `annotate_*()` method
    appends rather than replaces, so the parallel lists hold one entry
    per call: `line_*` is a horizontal reference line per (value, label)
    from `.annotate_line()`; `area_*` a shaded band per (y0, y1, label)
    from `.annotate_area()`; `vline_*` a vertical line per (value, label)
    from `.annotate_vline()`; `point_*` a labeled point per (x, y, label)
    from `.annotate_point()`. `line_*` and `vline_*` stay separate lists
    rather than sharing one with an axis flag.

    `band_*` is one filled region per `.annotate_band()` call, and each
    entry's `x`/`y_lower`/`y_upper` is itself a full series (a curve), so
    the outer list is one level deeper: `band_x[k]` is the k-th band's x
    column.

    `best_fit*` is a single opt-in request to compute a line from this
    `Plot`'s own `x_data`/`y_data` (see `annotate_best_fit()`), plus its
    display options: a `Bool` flag like `_secondary_axis`/`_y_log`, not
    repeatable data.
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
    var band_x: List[List[Float64]]
    var band_y_lower: List[List[Float64]]
    var band_y_upper: List[List[Float64]]
    var band_labels: List[String]
    var best_fit: Bool
    var best_fit_show_equation: Bool
    var best_fit_show_r_squared: Bool
    var best_fit_label: String

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
        self.band_x = List[List[Float64]]()
        self.band_y_lower = List[List[Float64]]()
        self.band_y_upper = List[List[Float64]]()
        self.band_labels = List[String]()
        self.best_fit = False
        self.best_fit_show_equation = False
        self.best_fit_show_r_squared = False
        self.best_fit_label = ""


struct Plot(Copyable, Movable):
    """One chart's mark, theme, labels and data, built through the fluent
    `mark_*()`/`encode_*()`/`labels()`/`theme()` chain and consumed by
    `render()`.

    Data columns are grouped one struct per mark family (`_box`,
    `_edges`, `_hierarchy`, ...) so each render function sees only its
    own columns. The shared encoding channels many marks read (`x_data`/
    `y_data`/`x_categories`/`color_data`/`color_categories`/`size_data`/
    `y_err_*`/`color_map`/`point_labels`) stay ungrouped, as do the
    single settings (`_mark`/`_theme`/`_secondary_axis`/
    `_nightingale_area`, ...).

    `Copyable`, not `ImplicitlyCopyable` (#207): every field is a plain
    data column or a small settings struct, so a member-wise copy is
    always valid, but `Plot` can carry a lot of data -- an accidental
    implicit copy (e.g. passing one by value where a borrow was meant)
    should be visible at the call site. Clone a base plot into facet/
    layer variants with an explicit `.copy()`:

    ```mojo
    var base = Plot().mark_line().theme(t).size(400, 300)
    var a = base.copy().encode(x=xs, y=ys_a).labels(title="A")
    var b = base.copy().encode(x=xs, y=ys_b).labels(title="B")
    ```
    """

    var x_data: List[Float64]
    var y_data: List[Float64]
    var x_categories: List[String]
    var color_data: List[Float64]
    var color_categories: List[String]
    var size_data: List[Float64]
    # Set only via encode()'s labels; Mark.POINT/EFFECT_SCATTER only. A
    # point has no obvious default label, so this is a data channel rather
    # than a Theme flag: providing it is the opt-in. A row's label may be
    # "" to skip that one point.
    var point_labels: List[String]
    var y_err_data: List[Float64]
    # Set together, only via encode()'s y_err_lower/y_err_upper; mutually
    # exclusive with y_err_data.
    var y_err_lower_data: List[Float64]
    var y_err_upper_data: List[Float64]
    var color_map: Dict[String, Color]
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
    # Mark.NIGHTINGALE only: which of ECharts' two `rose_type` radius
    # formulas each wedge uses (False = "radius", True = "area"). See
    # mark_nightingale().
    var _nightingale_area: Bool
    # Mark.STACKED_BAR only: normalize each category's segments to sum to
    # 100% (ggplot's position="fill"). See mark_stacked_bar().
    var _stacked_bar_percent: Bool
    var _polar: _PolarData
    var _radar: _RadarData
    var _gauge: _GaugeData
    var _parallel: _ParallelData
    var _calendar: _CalendarData
    var _corrplot: _CorrplotData
    var _punchcard: _PunchcardData
    var _barbs: _BarbsData
    var _marimekko: _MarimekkoData
    var _hierarchy: _HierarchyData
    var _labels: _LabelData
    var _annotations: _AnnotationData
    var _mark_style: _MarkStyle
    # Set via .secondary_axis(); render_layers()/render_layers_svg() only.
    # This layer's y values scale against a second, independent y-domain
    # drawn on the right edge. render() raises if it's set on a standalone
    # plot.
    var _secondary_axis: Bool
    # Set via .scale_y_log()/.scale_x_log().
    var _y_log: Bool
    var _x_log: Bool
    # Set via .scale_x_domain()/.scale_y_domain() (#209).
    var _x_domain: _DomainOverride
    var _y_domain: _DomainOverride
    # Set only via a mark_*(horizontal=True) parameter (#121); there is no
    # `.horizontal()` builder method, so this is only ever `True` alongside
    # a `_mark` whose `mark_*()` reads it.
    var _horizontal: Bool
    var _mark: Mark
    var _theme: Theme
    var width: Int
    """Pixel width `render()`/`render_svg()`/`save()` construct their target
    at; set via `.size()`, default 640.
    """
    var height: Int
    """Pixel height; see `width`."""

    def __init__(out self):
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self.x_categories = List[String]()
        self.color_data = List[Float64]()
        self.color_categories = List[String]()
        self.size_data = List[Float64]()
        self.point_labels = List[String]()
        self.y_err_data = List[Float64]()
        self.y_err_lower_data = List[Float64]()
        self.y_err_upper_data = List[Float64]()
        self.color_map = Dict[String, Color]()
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
        self._stacked_bar_percent = False
        self._polar = _PolarData()
        self._radar = _RadarData()
        self._gauge = _GaugeData()
        self._parallel = _ParallelData()
        self._calendar = _CalendarData()
        self._corrplot = _CorrplotData()
        self._punchcard = _PunchcardData()
        self._barbs = _BarbsData()
        self._marimekko = _MarimekkoData()
        self._hierarchy = _HierarchyData()
        self._labels = _LabelData()
        self._annotations = _AnnotationData()
        self._mark_style = _MarkStyle()
        self._secondary_axis = False
        self._y_log = False
        self._x_log = False
        self._x_domain = _DomainOverride()
        self._y_domain = _DomainOverride()
        self._horizontal = False
        self._mark = Mark.POINT
        self._theme = Theme.default()
        self.width = 640
        self.height = 420

    def size(var self, width: Int, height: Int) -> Self:
        """Set the pixel dimensions `render()`/`render_svg()`/`save()` construct
        their target at. Defaults to 640x420.
        """
        self.width = width
        self.height = height
        return self^

    def mark_point(var self, tooltips: Bool = False) -> Self:
        """A scatter plot: one point per (x, y) pair.

        `tooltips` (default `False`) gives each point an SVG `<title>` a
        browser shows on hover: the row's `encode(labels=...)` text when it
        has one, otherwise its coordinates. Off by default because a title
        adds about 39 bytes to a 48-byte `<circle>`, so a dense scatter's SVG
        roughly doubles (234 KB to 425 KB at 5000 points). A per-chart
        decision, which is why it lives here rather than on `Theme`; both
        this and `Theme.svg_tooltips` must be on for a title to be emitted.

        Args:
            tooltips: Whether each point carries a hover `<title>`.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.POINT
        self._mark_style.point_tooltips = tooltips
        return self^

    def mark_line(var self) -> Self:
        """A line plot: (x, y) pairs connected in data order, not sorted by x.
        Sort the data first if that isn't the order to draw.
        """
        self._mark = Mark.LINE
        return self^

    def mark_bar(var self, horizontal: Bool = False) -> Self:
        """A bar chart: one bar per category, encoded via `encode_categorical()`.

        `horizontal` (default `False`) draws categories top-to-bottom along
        the y-axis with each bar extending from a zero baseline to the right
        (#121), via `_draw_horizontal_categorical_axis_frame` (gantt.mojo);
        see `_render_horizontal_bar` (bar.mojo).
        """
        self._mark = Mark.BAR
        self._horizontal = horizontal
        return self^

    def mark_area(var self) -> Self:
        """An area chart: `mark_line()`'s continuous (x, y) pairs, filled from
        each point down to a zero baseline. Encoded via `encode()`.
        """
        self._mark = Mark.AREA
        return self^

    def mark_arc(var self, inner_radius_fraction: Float64 = 0.0) -> Self:
        """A pie chart: one wedge per category, its angular span proportional to
        its value, encoded via `encode_categorical()`. Every value must be
        non-negative and at least one positive, checked at render() time.
        `inner_radius_fraction > 0.0` (in `[0.0, 1.0)`) makes a donut.
        """
        self._mark = Mark.ARC
        self._mark_style.donut_inner_radius_fraction = inner_radius_fraction
        return self^

    def mark_nightingale(var self, area: Bool = False) -> Self:
        """A rose/coxcomb chart: one wedge per category, all wedges the same
        angular width, with magnitude encoded by radius (unlike `mark_arc()`).
        Encoded via `encode_categorical()`. `area=True` scales each wedge's
        radius by `sqrt(value / max)` (ECharts' `rose_type="area"`) instead of
        the default linear `value / max` (`rose_type="radius"`); see
        `_render_nightingale`. Every value must be non-negative and at least
        one positive, checked at render() time.

        Args:
            area: `False` (the default) scales each wedge's *radius*
                by `value / max`; `True` scales its *area* instead
                (`sqrt(value / max)`, ECharts' `rose_type="area"`).

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.NIGHTINGALE
        self._nightingale_area = area
        return self^

    def mark_polar_bar(var self, padding: Float64 = 0.2) -> Self:
        """A circular column chart: bars radiate outward from the center, one
        equal-width angular slot per category with a gap of `padding` (a
        fraction of the slot) between bars. Encoded via
        `encode_categorical()`. Bar length scales linearly by
        `value / max(values)`; there is no `area` mode. Every value must be
        non-negative and at least one positive, checked at render() time.
        """
        self._mark = Mark.POLAR_BAR
        self._mark_style.polar_bar_padding = padding
        return self^

    def mark_radialbar(var self, ring_gap_fraction: Float64 = 0.25) -> Self:
        """A radial (multi-ring) progress chart: one concentric ring per
        category, swept clockwise from 12 o'clock over a track to
        `value / max(values)` of the way around, with the first category
        outermost. `ring_gap_fraction` is the gap between rings as a fraction
        of each ring's slot. Encoded via `encode_categorical()`. Every value
        must be non-negative and at least one positive, checked at render()
        time.
        """
        self._mark = Mark.RADIALBAR
        self._mark_style.radialbar_ring_gap_fraction = ring_gap_fraction
        return self^

    def mark_polar(
        var self, grid_rings: Int = 4, grid_spokes: Int = 12
    ) -> Self:
        """A polar-coordinate line plot: (angle, radius) pairs connected in row
        order over a polar grid of `grid_rings` circles and `grid_spokes`
        radial lines. Encoded via `encode_polar()` (one unnamed series) or
        `encode_polar_series()` (several named series sharing one angle
        domain). See `_render_polar`.
        """
        self._mark = Mark.POLAR
        self._mark_style.polar_grid_rings = grid_rings
        self._mark_style.polar_grid_spokes = grid_spokes
        return self^

    def mark_radar(var self, grid_rings: Int = 4) -> Self:
        """A radar/spider chart: one spoke per named indicator, one polygon per
        named series, with `grid_rings` web rings. Encoded via
        `encode_radar()`.
        """
        self._mark = Mark.RADAR
        self._mark_style.radar_grid_rings = grid_rings
        return self^

    def mark_gauge(
        var self,
        band_inner_fraction: Float64 = 0.7,
        needle_fraction: Float64 = 0.9,
        start_angle: Float64 = 3.0 * pi / 4.0,
        sweep_angle: Float64 = 3.0 * pi / 2.0,
    ) -> Self:
        """A gauge chart: a single value shown as a needle over a color-banded
        dial. Encoded via `encode_gauge()`, which also takes the bands'
        `breakpoints`/`band_colors`. `band_inner_fraction`/`needle_fraction`
        are fractions of the dial radius; `start_angle`/`sweep_angle` are
        radians (the defaults give a 270-degree dial opening downward).
        """
        self._mark = Mark.GAUGE
        self._mark_style.gauge_band_inner_fraction = band_inner_fraction
        self._mark_style.gauge_needle_fraction = needle_fraction
        self._mark_style.gauge_start_angle = start_angle
        self._mark_style.gauge_sweep_angle = sweep_angle
        return self^

    def mark_parallel(var self) -> Self:
        """A parallel-coordinates chart: one row drawn as a polyline across
        evenly spaced, independently scaled vertical axes, one per dimension.
        Encoded via `encode_parallel()`.
        """
        self._mark = Mark.PARALLEL
        return self^

    def mark_lollipop(var self, horizontal: Bool = False) -> Self:
        """A lollipop chart: one stem-plus-point per category, encoded via
        `encode_categorical()` (the same data as `mark_bar()`). `horizontal`
        (default `False`) draws categories top-to-bottom with each stem
        extending to the right (#121); see `_render_horizontal_lollipop`
        (lollipop.mojo).
        """
        self._mark = Mark.LOLLIPOP
        self._horizontal = horizontal
        return self^

    def mark_waterfall(var self, delta_width_fraction: Float64 = 0.6) -> Self:
        """A waterfall chart: one floating bar per category, each running from
        the previous running total to the next. Encoded via
        `encode_waterfall()` (a category plus a signed delta).
        `delta_width_fraction` is a delta bar's width as a fraction of the
        band, applied only when `is_total` rows are in use.
        """
        self._mark = Mark.WATERFALL
        self._mark_style.waterfall_delta_width_fraction = delta_width_fraction
        return self^

    def mark_box(var self, horizontal: Bool = False) -> Self:
        """A box plot: one box-and-whiskers per category summarizing a
        distribution of raw values. Encoded via `encode_boxplot()`, which
        computes quartiles/whiskers/outliers immediately. `horizontal`
        (default `False`) draws categories top-to-bottom with each box
        left-to-right (#121); see `_render_horizontal_box` (box.mojo).
        """
        self._mark = Mark.BOX
        self._horizontal = horizontal
        return self^

    def mark_candlestick(var self) -> Self:
        """A candlestick chart: one open/high/low/close bar per category.
        Encoded via `encode_candlestick()`.
        """
        self._mark = Mark.CANDLESTICK
        return self^

    def mark_bullet(var self, measure_width_fraction: Float64 = 0.35) -> Self:
        """A bullet chart (Stephen Few's design): a measure bar, a target tick,
        and qualitative-range bands per category. Encoded via
        `encode_bullet()`. `measure_width_fraction` is the measure bar's
        width as a fraction of the band.
        """
        self._mark = Mark.BULLET
        self._mark_style.bullet_measure_width_fraction = measure_width_fraction
        return self^

    def mark_gantt(var self) -> Self:
        """A gantt chart: one horizontal bar per category from a start value to
        an end value, with categories along the y-axis. Encoded via
        `encode_gantt()`. See `mark_span_chart()` for the same data drawn
        vertically.
        """
        self._mark = Mark.GANTT
        return self^

    def mark_span_chart(var self) -> Self:
        """A span chart: `mark_gantt()`'s mirror image, one floating vertical
        bar per category from a low value to a high value on the normal
        categorical x-axis. Encoded via `encode_gantt()`.
        """
        self._mark = Mark.SPAN_CHART
        return self^

    def mark_calendar_heatmap(var self) -> Self:
        """A calendar heatmap: daily values in a GitHub-contributions-style
        grid, colored through a continuous gradient. Encoded via
        `encode_calendar()` (`"YYYY-MM-DD"` dates).
        """
        self._mark = Mark.CALENDAR_HEATMAP
        return self^

    def mark_corrplot(
        var self,
        layout: String = "full",
        diag: Bool = True,
        labels: Bool = True,
        bubble_fraction: Float64 = 0.42,
    ) -> Self:
        """A correlation plot: one bubble per cell of a square correlation
        matrix, sized by strength and colored by sign. Encoded via
        `encode_corrplot()`. `layout` and `diag` control which cells draw;
        see `_render_corrplot`.

        Args:
            layout: Which triangle to draw -- `"full"` (the default),
                `"lower"`, or `"upper"`.
            diag: Whether to draw the diagonal cells; defaults to
                `True`.
            labels: Whether to draw variable names along the axes;
                defaults to `True`.
            bubble_fraction: Each bubble's maximum radius as a
                fraction of the cell's smaller dimension, at
                `abs(r) == 1`; defaults to `0.42`.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.CORRPLOT
        self._corrplot.layout = layout
        self._corrplot.diag = diag
        self._corrplot.labels = labels
        self._mark_style.corrplot_bubble_fraction = bubble_fraction
        return self^

    def mark_punchcard(var self, scale: Float64 = 10.0) -> Self:
        """A punchcard: a scatter plot on a categorical grid where bubble size
        encodes a third variable. Encoded via `encode_punchcard()`. `scale`
        (default 10.0, matching ECharts.jl) is the pixel-space divisor each
        bubble's radius comes from (`size / scale`); see `_render_punchcard`.

        Args:
            scale: Divides each bubble's raw size before drawing --
                raise it to shrink bubbles that would otherwise
                overlap.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.PUNCHCARD
        self._punchcard.scale = scale
        return self^

    def mark_barbs(
        var self, length: Float64 = 28.0, flip: Bool = False
    ) -> Self:
        """Wind barbs: one station-model glyph per point, its staff pointing
        upwind and its flags/barbs summing to the speed. Encoded via
        `encode_barbs()`; see `_render_barbs` for the glyph and
        `barbs()` for the one-call form.

        Args:
            length: Staff length in pixels before `Theme.scale`, which
                every feature on the glyph is sized as a fraction of.
            flip: Mirror every feature across its staff -- the southern-
                hemisphere convention (matplotlib's `flip_barb`).

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.BARBS
        self._barbs.length = length
        self._barbs.flip = flip
        return self^

    def mark_marimekko(var self) -> Self:
        """A Marimekko/mosaic chart: column widths proportional to each
        category's share of the grand total, stacked segment heights showing
        each column's subcategory composition. Encoded via
        `encode_marimekko()`.
        """
        self._mark = Mark.MARIMEKKO
        return self^

    def mark_sunburst(var self) -> Self:
        """A sunburst chart: a hierarchy as concentric rings, one ring per depth
        level, each node's angular span proportional to its share of its
        parent's total. Encoded via `encode_hierarchy()`.
        """
        self._mark = Mark.SUNBURST
        return self^

    def mark_tree(var self) -> Self:
        """A tree diagram: a hierarchy as a top-to-bottom node-link diagram.
        Encoded via `encode_hierarchy()`.
        """
        self._mark = Mark.TREE
        return self^

    def mark_treemap(var self) -> Self:
        """A treemap: a hierarchy as nested, area-proportional rectangles via
        slice-and-dice. Encoded via `encode_hierarchy()`.
        """
        self._mark = Mark.TREEMAP
        return self^

    def mark_grouped_bar(var self, horizontal: Bool = False) -> Self:
        """A grouped bar chart: several bars side by side per category, one per
        series. Encoded via `encode_grouped_bar()`. `horizontal` (default
        `False`) draws categories top-to-bottom with each row subdivided into
        equal-height sub-bars (#121); see `_render_horizontal_grouped_bar`
        (grouped_bar.mojo).
        """
        self._mark = Mark.GROUPED_BAR
        self._horizontal = horizontal
        return self^

    def mark_stacked_bar(
        var self, percent: Bool = False, horizontal: Bool = False
    ) -> Self:
        """A stacked bar chart: one bar per category, each series' value stacked
        as a segment on the previous running total. Encoded via
        `encode_grouped_bar()`, the same data as `mark_grouped_bar()`.

        `percent=True` normalizes each category's segments to sum to 100%
        (ggplot's `position = "fill"`), fixing the y-axis to `[0, 100]`.
        Every value must then be non-negative, checked at render() time; an
        all-zero category draws as an empty column.

        `horizontal` (default `False`) draws categories top-to-bottom with
        each category's segments stacked left-to-right (#121); see
        `_render_horizontal_stacked_bar` (stacked_bar.mojo).

        Args:
            percent: `False` (the default) stacks raw values, an
                unchanged real-valued y-axis. `True` normalizes each
                category to 100% and fixes the y-axis to `[0, 100]`.
            horizontal: Draw categories running top-to-bottom with each
                category's segments stacked left-to-right instead of
                the default vertical layout.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.STACKED_BAR
        self._stacked_bar_percent = percent
        self._horizontal = horizontal
        return self^

    def mark_population_pyramid(var self) -> Self:
        """A population pyramid: two magnitude bars per category growing outward
        left/right from a shared, centered zero baseline, on `Mark.GANTT`'s
        horizontal categorical frame. Encoded via
        `encode_population_pyramid()`.
        """
        self._mark = Mark.POPULATION_PYRAMID
        return self^

    def mark_heatmap(var self) -> Self:
        """A heatmap: one colored grid cell per (x, y) category pair, on two
        categorical axes. Encoded via `encode_heatmap()`.
        """
        self._mark = Mark.HEATMAP
        return self^

    def mark_chord(var self, ring_fraction: Float64 = 0.08) -> Self:
        """A chord diagram: ring sectors for every distinct node across an edge
        list's `from`/`to` columns, connected by ribbons sized by each flow's
        value. Encoded via `encode_chord()`. `ring_fraction` is the rim's
        thickness as a fraction of the radius. No axis frame.
        """
        self._mark = Mark.CHORD
        self._mark_style.chord_ring_fraction = ring_fraction
        return self^

    def mark_arc_diagram(var self) -> Self:
        """An arc diagram: `mark_chord()`'s edge list drawn as nodes on one line
        connected by semicircular arcs. Encoded via `encode_chord()`.
        """
        self._mark = Mark.ARC_DIAGRAM
        return self^

    def mark_graph(var self) -> Self:
        """A network graph: `mark_chord()`'s edge list drawn as nodes evenly
        spaced around a circle connected by straight lines. Encoded via
        `encode_chord()`.
        """
        self._mark = Mark.GRAPH
        return self^

    def mark_sankey(var self, node_width: Float64 = 12.0) -> Self:
        """A Sankey diagram: `mark_chord()`'s edge list laid out left-to-right by
        column as proportionally sized flow ribbons between node bars
        `node_width` pixels wide (before `Theme.scale`). Encoded via
        `encode_chord()`; the edges must form a DAG.
        """
        self._mark = Mark.SANKEY
        self._mark_style.sankey_node_width = node_width
        return self^

    def mark_single_axis(var self) -> Self:
        """A single-axis chart: every value plotted along one horizontal axis
        with no y-axis. Encoded via `encode_single_axis()`, with the same
        optional `color`/`color_categories`/`size` channels as `Mark.POINT`.
        """
        self._mark = Mark.SINGLE_AXIS
        return self^

    def mark_effect_scatter(var self, tooltips: Bool = False) -> Self:
        """A scatter plot with a halo drawn under each point, the static
        equivalent of ECharts' effect scatter (see `_draw_point_layer`'s
        `draw_halo`). Encoded like `Mark.POINT`, via `encode()`. `tooltips`
        works as in `mark_point()`.
        """
        self._mark = Mark.EFFECT_SCATTER
        self._mark_style.point_tooltips = tooltips
        return self^

    def mark_funnel(var self) -> Self:
        """A funnel chart: one tapering trapezoid per category, largest value
        first, with no axis frame. Encoded via `encode_categorical()`.
        """
        self._mark = Mark.FUNNEL
        return self^

    def mark_bump(var self) -> Self:
        """A bump chart: one line per series tracking its rank (1 = highest
        value) among every series at each category. Encoded via
        `encode_grouped_bar()`.
        """
        self._mark = Mark.BUMP
        return self^

    def mark_streamgraph(var self) -> Self:
        """A streamgraph: `mark_stacked_bar()`'s running-total stack floated
        centered around zero and drawn as flowing bands. Encoded via
        `encode_grouped_bar()`.
        """
        self._mark = Mark.STREAMGRAPH
        return self^

    def mark_beeswarm(
        var self, horizontal: Bool = False, tooltips: Bool = False
    ) -> Self:
        """A beeswarm plot: one point per raw value, jittered sideways within
        its category's band. Encoded via `encode_distribution()`.
        `horizontal` (default `False`) draws categories top-to-bottom with
        each swarm jittered vertically (#121); see
        `_render_horizontal_beeswarm` (beeswarm.mojo). `tooltips` works as in
        `mark_point()`.
        """
        self._mark = Mark.BEESWARM
        self._horizontal = horizontal
        self._mark_style.point_tooltips = tooltips
        return self^

    def mark_violin(
        var self,
        bandwidth: Float64 = 0.0,
        scale_by_count: Bool = False,
        horizontal: Bool = False,
        width_fraction: Float64 = 0.4,
    ) -> Self:
        """A violin plot: a symmetric kernel-density-estimate silhouette per
        category. Encoded via `encode_distribution()`.

        `bandwidth` (when positive; checked at render() time) replaces every
        category's Silverman's-rule bandwidth (`_kde_bandwidth()`,
        violin.mojo) with one shared value, so categories' shapes can be
        compared without Silverman's rule reacting to each sample size.
        `scale_by_count=True` scales each category's maximum width by
        `sqrt(n_i / max(n))` (ggplot2's `scale = "area"`) instead of giving
        every category the same maximum width (`scale = "width"`).

        Args:
            bandwidth: Overrides every category's Silverman's-rule
                kernel-density bandwidth with one shared value; must
                be positive if given. Left at its default `0.0`, each
                category gets its own Silverman's-rule bandwidth.
            scale_by_count: `False` (the default, `scale = "width"`)
                gives every category's peak the same maximum width;
                `True` (`scale = "area"`) additionally scales a
                category's maximum width by `sqrt(n_i / max(n))`.
            horizontal: `False` (the default) draws each silhouette
                bulging left-right around a vertical column, one
                column per category left-to-right. `True` -- exactly
                `mark_bar(horizontal=True)`'s own flip (#121) -- draws
                each silhouette bulging up-down around a horizontal
                row, one row per category top-to-bottom, reusing
                `_draw_horizontal_categorical_axis_frame` (gantt.mojo)
                -- see `_render_horizontal_violin`'s own docstring
                (violin.mojo).
            width_fraction: Each violin's maximum half-width as a
                fraction of its category's band width; defaults to
                `0.4`.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.VIOLIN
        self._distribution.kde_bandwidth_override = bandwidth
        self._distribution.kde_scale_by_count = scale_by_count
        self._horizontal = horizontal
        self._mark_style.violin_width_fraction = width_fraction
        return self^

    def mark_ridgeline(
        var self,
        bandwidth: Float64 = 0.0,
        scale_by_count: Bool = False,
        overlap: Float64 = 1.3,
    ) -> Self:
        """A ridgeline plot: one overlapping kernel-density-estimate row per
        category, top to bottom. Encoded via `encode_distribution()`.
        `bandwidth`/`scale_by_count` work as in `mark_violin()`, applied to
        each row's maximum rise instead of width.

        Args:
            bandwidth: Overrides every category's Silverman's-rule
                kernel-density bandwidth with one shared value; must
                be positive if given. Left at its default `0.0`, each
                category gets its own Silverman's-rule bandwidth.
            scale_by_count: `False` (the default, `scale = "width"`)
                gives every category's peak the same maximum rise;
                `True` (`scale = "area"`) additionally scales a
                category's maximum rise by `sqrt(n_i / max(n))`.
            overlap: How far each row's silhouette may rise into the
                rows above it, as a multiple of the row height;
                defaults to `1.3`, deliberately more than one so the
                ridges interleave.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.RIDGELINE
        self._distribution.kde_bandwidth_override = bandwidth
        self._distribution.kde_scale_by_count = scale_by_count
        self._mark_style.ridgeline_overlap = overlap
        return self^

    def encode(
        var self,
        x: List[Float64],
        y: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
        color_map: Dict[String, Color] = Dict[String, Color](),
        labels: List[String] = List[String](),
    ) -> Self:
        """Map data columns onto channels. `x`/`y` are required; the optional
        channels must match their length, checked at render() time (a
        builder method can't raise mid-chain).

        `color` (continuous, through a `ColorScale` over the column's
        [min, max]) and `color_categories` (discrete, through
        `default_categorical_palette()` by first-seen order of the unique
        values) are mutually exclusive. `size` is continuous only.
        `color_map` pins specific `color_categories` values to colors
        (`{category_name: Color}`); unlisted categories keep their palette
        color, and it raises without `color_categories`.

        `y_err` draws a capped vertical whisker of `+/- y_err[i]` around each
        point (`Theme.error_bar_cap_width`); `y_err_lower`/`y_err_upper`,
        given together, draw an asymmetric one. The two forms are mutually
        exclusive and every value must be `>= 0`. Error bars use the point's
        own resolved color. `labels` draws each row's text above its point;
        `""` skips a row.

        Mark support: `color`/`color_categories`/`size`/`color_map` on
        `POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER`; `labels` on `POINT`/
        `EFFECT_SCATTER`; `y_err` on `POINT`/`LINE`/`EFFECT_SCATTER`;
        `y_err_lower`/`y_err_upper` on `POINT`/`EFFECT_SCATTER`. For a
        categorical x-axis use `encode_categorical()`.

        Args:
            x: The continuous x column, one entry per point.
            y: The continuous y column, one entry per point.
            color: Optional continuous color channel, mapped through a
                `ColorScale` spanning the column's `[min, max]`;
                mutually exclusive with `color_categories`. `Mark.
                POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER` only.
            color_categories: Optional discrete color channel,
                palette-colored by each value's first-seen order
                among its unique values; mutually exclusive with
                `color`. `Mark.POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER`
                only.
            size: Optional point-size channel, continuous only.
                `Mark.POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER` only.
            y_err: Optional symmetric error-bar half-width per point,
                continuous only, every value `>= 0`; mutually exclusive
                with `y_err_lower`/`y_err_upper`. `Mark.POINT`/`LINE`/
                `EFFECT_SCATTER` only (not `SINGLE_AXIS`).
            y_err_lower: Optional asymmetric error-bar downward extent
                per point; must be given together with `y_err_upper`,
                every value `>= 0`. `Mark.POINT`/`EFFECT_SCATTER` only
                (not yet `Mark.LINE`).
            y_err_upper: Optional asymmetric error-bar upward extent
                per point; must be given together with `y_err_lower`,
                every value `>= 0`. `Mark.POINT`/`EFFECT_SCATTER` only
                (not yet `Mark.LINE`).
            color_map: Optional explicit category-to-color overrides,
                keyed by the category's own name; only meaningful
                alongside `color_categories`. `Mark.POINT`/`SINGLE_
                AXIS`/`EFFECT_SCATTER` only (whatever mark `color_
                categories` is used on).
            labels: Optional per-point text, drawn above each point;
                an entry of `""` skips that one point's label.
                `Mark.POINT`/`EFFECT_SCATTER` only.

        Returns:
            Self, for further chaining.

        See the Cookbook's own "Error Bars" recipe (docs/src/
        cookbook_recipes/error_bars.mojo) for a full worked example.
        """
        self.x_data = x.copy()
        self.y_data = y.copy()
        self.x_categories = List[String]()
        self.color_data = color.copy()
        self.color_categories = color_categories.copy()
        self.size_data = size.copy()
        self.y_err_data = y_err.copy()
        self.y_err_lower_data = y_err_lower.copy()
        self.y_err_upper_data = y_err_upper.copy()
        self.color_map = color_map.copy()
        self.point_labels = labels.copy()
        return self^

    def encode[
        T: Float64Sequence
    ](
        var self,
        x: T,
        y: T,
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
        color_map: Dict[String, Color] = Dict[String, Color](),
    ) -> Self:
        """`encode()`'s `x`/`y` generalized to anything conforming to
        `Float64Sequence` (array_like.mojo), for data in a custom buffer
        wrapper or a dataframe column type. A type's author has to declare
        the conformance; `List` itself and numpy arrays can't be retrofitted,
        which is why the concrete overload above still exists. `x` and `y`
        share one type parameter `T`, so both must be the same concrete type.
        Materializes both via `_materialize_floats` and delegates to the
        concrete `encode()`.

        Args:
            x: The continuous x column, one entry per point --
                anything conforming to `Float64Sequence`.
            y: The continuous y column, one entry per point -- the
                same concrete type as `x`.
            color: See `encode()`'s own docstring -- unchanged here,
                still a concrete `List[Float64]`.
            color_categories: See `encode()`'s own docstring.
            size: See `encode()`'s own docstring.
            y_err: See `encode()`'s own docstring.
            y_err_lower: See `encode()`'s own docstring.
            y_err_upper: See `encode()`'s own docstring.
            color_map: See `encode()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode(
            _materialize_floats(x),
            _materialize_floats(y),
            color=color,
            color_categories=color_categories,
            size=size,
            y_err=y_err,
            y_err_lower=y_err_lower,
            y_err_upper=y_err_upper,
            color_map=color_map,
        )

    def encode[
        dtype: DType
    ](
        var self,
        x: List[Scalar[dtype]],
        y: List[Scalar[dtype]],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
        color_map: Dict[String, Color] = Dict[String, Color](),
    ) -> Self:
        """`encode()`'s `x`/`y` generalized over numeric element type
        (`List[Int]`, `List[Float32]`, any `List[Scalar[dtype]]`), a
        different axis from the `Float64Sequence` overload (element type
        rather than container type; see array_like.mojo for why this uses
        `DType` genericity rather than a trait). `x`/`y` share one `dtype`.
        Materializes both via `_materialize_scalar_list` and delegates to the
        concrete `encode()`, which Mojo still picks directly for a plain
        `List[Float64]`.

        Args:
            x: The continuous x column, one entry per point -- any
                numeric `List[Scalar[dtype]]`.
            y: The continuous y column, one entry per point -- the
                same element type as `x`.
            color: See `encode()`'s own docstring -- unchanged here,
                still a concrete `List[Float64]`.
            color_categories: See `encode()`'s own docstring.
            size: See `encode()`'s own docstring.
            y_err: See `encode()`'s own docstring.
            y_err_lower: See `encode()`'s own docstring.
            y_err_upper: See `encode()`'s own docstring.
            color_map: See `encode()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            color=color,
            color_categories=color_categories,
            size=size,
            y_err=y_err,
            y_err_lower=y_err_lower,
            y_err_upper=y_err_upper,
            color_map=color_map,
        )

    def encode(
        var self,
        x: PythonObject,
        y: PythonObject,
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
        color_map: Dict[String, Color] = Dict[String, Color](),
    ) raises -> Self:
        """`encode()`'s `x`/`y` generalized to a numpy `ndarray`, a pandas
        `Series`, or a plain Python list of numbers (see numpy_interop.mojo).
        Requires numpy in the caller's environment; raises numpy's own error
        if it's missing or `x`/`y` can't become a 1-D numeric array. `x`/`y`
        need not share a dtype. Materializes both via
        `_materialize_python_floats` and delegates to the concrete `encode()`.

        Args:
            x: The continuous x column, one entry per point -- a numpy
                `ndarray`, a pandas `Series`, or a plain Python list of
                numbers.
            y: The continuous y column, one entry per point -- same
                shape as `x`.
            color: See `encode()`'s own docstring -- unchanged here,
                still a concrete `List[Float64]`.
            color_categories: See `encode()`'s own docstring.
            size: See `encode()`'s own docstring.
            y_err: See `encode()`'s own docstring.
            y_err_lower: See `encode()`'s own docstring.
            y_err_upper: See `encode()`'s own docstring.
            color_map: See `encode()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode(
            _materialize_python_floats(x),
            _materialize_python_floats(y),
            color=color,
            color_categories=color_categories,
            size=size,
            y_err=y_err,
            y_err_lower=y_err_lower,
            y_err_upper=y_err_upper,
            color_map=color_map,
        )

    def encode_categorical(
        var self,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) -> Self:
        """Map a categorical x column and a continuous y column onto the x/y
        channels, for `Mark.BAR` and the other category-plus-value marks.
        `x` is treated as the axis's category order as given, not
        deduplicated or re-sorted; repeated categories go through
        `encode_grouped_bar()`.

        `y_err`/`y_err_lower`/`y_err_upper` (#216) work exactly as they do on
        `encode()` -- see that method's own docstring for the shared rules
        (mutually exclusive forms, every value `>= 0`) -- except `Mark.BAR`
        is the only mark among `encode_categorical()`'s that draws them
        today; every other mark this method feeds (`LOLLIPOP`, `WATERFALL`,
        `NIGHTINGALE`, `FUNNEL`, `POLAR_BAR`, `RADIALBAR`, ...) raises if
        given one.

        Args:
            x: One category per entry, in the given order -- treated
                as already being the axis's category order, not
                deduplicated or re-sorted.
            y: Each category's value.
            y_err: Optional symmetric error-bar half-width per bar,
                continuous only, every value `>= 0`; mutually
                exclusive with `y_err_lower`/`y_err_upper`. `Mark.BAR`
                only.
            y_err_lower: Optional asymmetric error-bar downward extent
                per bar; must be given together with `y_err_upper`,
                every value `>= 0`. `Mark.BAR` only.
            y_err_upper: Optional asymmetric error-bar upward extent
                per bar; must be given together with `y_err_lower`,
                every value `>= 0`. `Mark.BAR` only.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = x.copy()
        self.x_data = List[Float64]()
        self.y_data = y.copy()
        self.y_err_data = y_err.copy()
        self.y_err_lower_data = y_err_lower.copy()
        self.y_err_upper_data = y_err_upper.copy()
        return self^

    def encode_categorical[
        Tx: StringSequence
    ](
        var self,
        x: Tx,
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) -> Self:
        """`encode_categorical()`'s `x` generalized to anything conforming to
        `StringSequence` (array_like.mojo), as `encode()`'s `Float64Sequence`
        overload does for its `x`/`y`. `y` stays a concrete `List[Float64]`;
        each `encode_categorical()` overload generalizes one parameter at a
        time. Materializes `x` via `_materialize_strings` and delegates to
        the concrete overload.

        Args:
            x: One category per entry, in the given order -- anything
                conforming to `StringSequence`.
            y: Each category's value -- a concrete `List[Float64]`.
            y_err: See `encode_categorical()`'s own docstring.
            y_err_lower: See `encode_categorical()`'s own docstring.
            y_err_upper: See `encode_categorical()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_categorical(
            _materialize_strings(x),
            y,
            y_err=y_err,
            y_err_lower=y_err_lower,
            y_err_upper=y_err_upper,
        )

    def encode_categorical[
        dtype: DType
    ](
        var self,
        x: List[String],
        y: List[Scalar[dtype]],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) -> Self:
        """`encode_categorical()`'s `y` generalized over numeric element type
        (`List[Int]`, `List[Float32]`, ...), as `encode()`'s `DType` overload
        is. `x` stays a concrete `List[String]`. Materializes `y` via
        `_materialize_scalar_list` and delegates to the concrete overload.

        Args:
            x: One category per entry, in the given order.
            y: Each category's value -- any numeric `List[Scalar[
                dtype]]`.
            y_err: See `encode_categorical()`'s own docstring.
            y_err_lower: See `encode_categorical()`'s own docstring.
            y_err_upper: See `encode_categorical()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_categorical(
            x,
            _materialize_scalar_list(y),
            y_err=y_err,
            y_err_lower=y_err_lower,
            y_err_upper=y_err_upper,
        )

    def encode_categorical(
        var self,
        x: List[String],
        y: PythonObject,
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises -> Self:
        """`encode_categorical()`'s `y` generalized to a numpy `ndarray`/pandas
        `Series`/plain Python number list, as `encode()`'s `PythonObject`
        overload is (see numpy_interop.mojo). `x` stays a concrete
        `List[String]`. Materializes `y` via `_materialize_python_floats` and
        delegates to the concrete overload.

        Args:
            x: One category per entry, in the given order.
            y: Each category's value -- a numpy `ndarray`, a pandas
                `Series`, or a plain Python list of numbers.
            y_err: See `encode_categorical()`'s own docstring.
            y_err_lower: See `encode_categorical()`'s own docstring.
            y_err_upper: See `encode_categorical()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_categorical(
            x,
            _materialize_python_floats(y),
            y_err=y_err,
            y_err_lower=y_err_lower,
            y_err_upper=y_err_upper,
        )

    def encode_histogram(
        var self, data: List[Float64], bins: Int = 10
    ) raises -> Self:
        """Bin `data` into `bins` equal-width intervals and map the result onto
        `encode_categorical()`'s shape (each bin's formatted range as its
        category label, its count as the value), for `Mark.BAR`. The binning
        happens here, so this raises immediately on data that can't be
        binned; see `_bin_histogram()` (histogram.mojo) for the algorithm and
        the cases it raises on.

        Args:
            data: The raw values to bin -- not pre-counted; binning
                happens right here.
            bins: How many equal-width intervals to divide `data`'s
                range into (half-open except the last, which includes
                its upper edge).

        Returns:
            Self, for further chaining.
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
        """Map a category column and a signed delta column onto
        `Mark.WATERFALL`'s floating-bar shape: `deltas[i]` is how much the
        running total changes at category `i`. Each bar runs from the running
        total before it (`y0`) to the running total after it (`y1`), computed
        here via `_waterfall_running_totals()` (waterfall.mojo) as a
        cumulative sum from 0.0.

        `is_total` (default empty) marks specific rows as running-total
        checkpoints; see `_waterfall_running_totals()` for how such a row
        draws and `waterfall()`'s `Example:` for the conventional
        start-then-deltas-then-end shape.

        Length matching (`categories`/`deltas`, and `is_total` when
        non-empty) is checked at render() time. `deltas` is kept as `y_data`
        so `_render_waterfall` can color each delta bar by sign.

        Args:
            categories: One floating bar per entry, in the given
                order.
            deltas: How much the running total changes at each
                category -- not the bar's absolute height; the
                cumulative sum starts from `0.0`.
            is_total: Marks specific rows as running-total checkpoints
                instead of a plain rising/falling delta. Left empty
                (the default), every row is a plain delta.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = deltas.copy()
        self._waterfall.is_total = is_total.copy()
        var bars = _waterfall_running_totals(deltas, is_total)
        self._waterfall.y0 = bars.y0.copy()
        self._waterfall.y1 = bars.y1.copy()
        return self^

    def encode_boxplot(
        var self, categories: List[String], values: List[List[Float64]]
    ) raises -> Self:
        """Map a category column and, per category, a list of raw values onto
        `Mark.BOX`'s box-and-whiskers shape. Each category's distribution is
        summarized immediately into a five-number summary (quartiles via
        linear interpolation, `numpy.percentile`'s default) plus every
        outlier beyond the 1.5*IQR fence, via `_box_stats()` (box.mojo).

        Raises immediately on a `categories`/`values` length mismatch or an
        empty value list, since quartiles are undefined for zero points.

        Args:
            categories: One box per entry, in the given order.
            values: Each category's raw values (`values[i]`) -- must
                be non-empty; quartiles/whiskers/outliers are computed
                from these immediately, not deferred to render() time.

        Returns:
            Self, for further chaining.

        Raises:
            If `categories`/`values` lengths don't match, `categories`
            is empty, or any category's value list is empty.
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
        _require_non_empty(len(categories), "Plot.encode_boxplot()")

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

    def encode_boxplot[
        dtype: DType
    ](
        var self, categories: List[String], values: List[List[Scalar[dtype]]]
    ) raises -> Self:
        """`encode_boxplot()`'s `values` generalized over numeric element type
        (`List[List[Int]]`, `List[List[Float32]]`, ...) via
        `_materialize_nested_scalar_list` (array_like.mojo). `categories`
        stays concrete. Delegates to the concrete overload.

        Args:
            categories: One box per entry, in the given order.
            values: Each category's raw values -- any numeric
                `List[List[Scalar[dtype]]]`.

        Returns:
            Self, for further chaining.

        Raises:
            If `categories`/`values` lengths don't match, or any
            category's value list is empty.
        """
        return self^.encode_boxplot(
            categories, _materialize_nested_scalar_list(values)
        )

    def encode_candlestick(
        var self,
        categories: List[String],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) -> Self:
        """Map a category column and four value columns (open/high/low/close)
        onto `Mark.CANDLESTICK`'s wick-plus-body shape. Nothing is computed
        up front, so length checking is deferred to render() time, as for
        `encode_categorical()`.

        Args:
            categories: One bar per entry, in the given order.
            open: Each category's opening value.
            high: Each category's highest value.
            low: Each category's lowest value.
            close: Each category's closing value.

        Returns:
            Self, for further chaining.
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
        """Map a category column plus `measures` (drawn as a narrower bar),
        `targets` (drawn as a tick mark), and `ranges` (per category, an
        ascending list of qualitative-range thresholds, e.g.
        `[50.0, 75.0, 100.0]`, drawn as shaded bands from 0 up to each
        threshold) onto `Mark.BULLET`'s shape. Length checking, and each
        `ranges` entry being non-empty and non-decreasing, is deferred to
        render() time.

        Args:
            categories: One row per entry, in the given order.
            measures: Each category's actual value, drawn as the
                narrower measure bar.
            targets: Each category's goal value, drawn as a tick mark.
            ranges: Each category's own ascending, non-empty list of
                qualitative-range thresholds, drawn as shaded
                background bands.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._bullet.measure = measures.copy()
        self._bullet.target = targets.copy()
        self._bullet.ranges = ranges.copy()
        return self^

    def encode_gantt(
        var self,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) -> Self:
        """Map a category column and two value columns (`start`/`end`) onto
        `Mark.GANTT`/`SPAN_CHART`'s span shape. Plain `Float64`, not a
        date/time type (this package has none); a schedule's dates are
        whatever numbers the caller's data uses, which is also why this mark
        doubles as a generic span chart. Length checking is deferred to
        render() time. `start[i] > end[i]` is allowed: bars draw from `min`
        to `max`.

        Args:
            categories: One horizontal bar per entry, top to bottom.
            start: Each bar's starting value.
            end: Each bar's ending value; not required to be greater
                than `start` -- drawn from `min(start[i], end[i])` to
                `max(...)`.

        Returns:
            Self, for further chaining.
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
        errors: List[List[Float64]] = List[List[Float64]](),
    ) -> Self:
        """Map a category column plus several value series onto
        `Mark.GROUPED_BAR`'s shape (also used by `STACKED_BAR`/`BUMP`/
        `STREAMGRAPH`): `values[j][i]` is series `series_names[j]`'s value
        for `categories[i]`. Length checking (`series_names`/`values`, and
        every `values[j]` against `categories`) is deferred to render() time.

        `errors` (#216), left empty by default, is `values`' per-(series,
        category) symmetric error-bar half-width shape: `errors[j][i]` is
        series `series_names[j]`'s error bar for `categories[i]`. Every
        value must be `>= 0`; `Mark.GROUPED_BAR` only among the marks this
        method feeds -- `STACKED_BAR`/`BUMP`/`STREAMGRAPH` raise if given
        one, the same restriction `encode_categorical()`'s `y_err` has
        against its own wider mark family.

        Args:
            categories: One group of side-by-side bars per entry, in
                the given order.
            series_names: One sub-bar per name.
            values: `values[j]` is `series_names[j]`'s value per
                category.
            errors: Optional per-(series, category) symmetric
                error-bar half-width, shaped like `values`, every
                value `>= 0`. `Mark.GROUPED_BAR` only.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._grouped_bar.series_names = series_names.copy()
        self._grouped_bar.values = values.copy()
        self._grouped_bar.errors = errors.copy()
        return self^

    def encode_grouped_bar[
        Tx: StringSequence
    ](
        var self,
        categories: Tx,
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) -> Self:
        """`encode_grouped_bar()`'s `categories` generalized to anything
        conforming to `StringSequence` (array_like.mojo), as
        `encode_categorical()`'s `StringSequence` overload is.
        `series_names`/`values` stay concrete. Materializes `categories` via
        `_materialize_strings` and delegates to the concrete overload.

        Args:
            categories: One group of side-by-side bars per entry, in
                the given order -- anything conforming to
                `StringSequence`.
            series_names: One sub-bar per name.
            values: `values[j]` is `series_names[j]`'s value per
                category.
            errors: See `encode_grouped_bar()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_grouped_bar(
            _materialize_strings(categories),
            series_names,
            values,
            errors=errors,
        )

    def encode_grouped_bar[
        dtype: DType
    ](
        var self,
        categories: List[String],
        series_names: List[String],
        values: List[List[Scalar[dtype]]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) -> Self:
        """`encode_grouped_bar()`'s `values` generalized over numeric element
        type (`List[List[Int]]`, `List[List[Float32]]`, ...) via
        `_materialize_nested_scalar_list` (array_like.mojo). `categories`/
        `series_names` stay concrete. Delegates to the concrete overload.

        Args:
            categories: One group of side-by-side bars per entry, in
                the given order.
            series_names: One sub-bar per name.
            values: `values[j]` is `series_names[j]`'s value per
                category -- any numeric `List[List[Scalar[dtype]]]`.
            errors: See `encode_grouped_bar()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_grouped_bar(
            categories,
            series_names,
            _materialize_nested_scalar_list(values),
            errors=errors,
        )

    def encode_population_pyramid(
        var self,
        categories: List[String],
        left_values: List[Float64],
        right_values: List[Float64],
        left_name: String = "",
        right_name: String = "",
    ) -> Self:
        """Map a category column plus two magnitude columns onto
        `Mark.POPULATION_PYRAMID`'s mirrored-bars shape: `left_values[i]`/
        `right_values[i]` each grow outward from a shared, centered zero
        baseline. Both are read as magnitudes regardless of sign
        (`max(v, -v)`), so a caller with signed data should decide which side
        each value belongs on. `left_name`/`right_name` label the two-entry
        legend, falling back to "Left"/"Right" when empty. Length checking
        is deferred to render() time.

        Args:
            categories: One row per entry, in the given order.
            left_values: Each row's left-side magnitude, read
                non-negative regardless of sign.
            right_values: Each row's right-side magnitude, read
                non-negative regardless of sign.
            left_name: Legend label for the left side; left empty
                (the default), falls back to "Left" at render time.
            right_name: Legend label for the right side; left empty
                (the default), falls back to "Right" at render time.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = categories.copy()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._pyramid.left = left_values.copy()
        self._pyramid.right = right_values.copy()
        self._pyramid.left_name = left_name
        self._pyramid.right_name = right_name
        return self^

    def encode_heatmap(
        var self, x: List[String], y: List[String], value: List[Float64]
    ) -> Self:
        """Map two category columns plus a value column onto `Mark.HEATMAP`'s
        grid-cell shape: one row per cell (`x[i]`, `y[i]`, `value[i]`). Each
        axis's domain is derived from `x`/`y`'s distinct values in first-seen
        order (`_categorical_indices`, at render() time). A missing (x, y)
        combination is simply not drawn. Length checking is deferred to
        render() time.

        Args:
            x: Each cell's column category, one entry per row of data.
            y: Each cell's row category, one entry per row of data.
            value: Each cell's value, mapped through a continuous
                color gradient.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._heatmap.x = x.copy()
        self._heatmap.y = y.copy()
        self._heatmap.value = value.copy()
        return self^

    def encode_calendar(
        var self, dates: List[String], values: List[Float64]
    ) -> Self:
        """Map a date column and a value column onto `Mark.CALENDAR_HEATMAP`'s
        shape: one row per day, `dates[i]` a `"YYYY-MM-DD"` string (parsed
        only for grid placement; see calendar_heatmap.mojo's `_parse_date`/
        `_days_from_civil`) and `values[i]` colored through the same gradient
        `encode_heatmap()` uses. Every date must fall in the same calendar
        year (inferred from the first), checked at render() time along with
        the length match.

        Args:
            dates: Plain `"YYYY-MM-DD"` strings, one per entry, all in
                the same calendar year (inferred from `dates[0]`).
            values: Each date's value, mapped through a continuous
                color gradient.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._calendar.dates = dates.copy()
        self._calendar.values = values.copy()
        return self^

    def encode_corrplot(
        var self, variables: List[String], matrix: List[List[Float64]]
    ) -> Self:
        """Map a variable-name list and a square correlation `matrix` onto
        `Mark.CORRPLOT`'s shape: `matrix[row][col]` is the correlation
        between `variables[row]` and `variables[col]`. Squareness and every
        value being in `[-1.0, 1.0]` are checked at render() time.

        Args:
            variables: One row and one column per entry -- `matrix`
                must be this length square.
            matrix: The square pairwise-correlation matrix, each value
                in `[-1.0, 1.0]`.

        Returns:
            Self, for further chaining.
        """
        self._corrplot.variables = variables.copy()
        self._corrplot.matrix = matrix.copy()
        return self^

    def encode_corrplot[
        dtype: DType
    ](
        var self, variables: List[String], matrix: List[List[Scalar[dtype]]]
    ) -> Self:
        """`encode_corrplot()`'s `matrix` generalized over numeric element type
        via `_materialize_nested_scalar_list` (array_like.mojo). `variables`
        stays concrete. Delegates to the concrete overload.

        Args:
            variables: One row and one column per entry -- `matrix`
                must be this length square.
            matrix: The square pairwise-correlation matrix -- any
                numeric `List[List[Scalar[dtype]]]`.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_corrplot(
            variables, _materialize_nested_scalar_list(matrix)
        )

    def encode_punchcard(
        var self, x: List[String], y: List[String], sizes: List[Float64]
    ) -> Self:
        """Map two category columns plus a size column onto `Mark.PUNCHCARD`'s
        shape, with the same `x`/`y` domain derivation as `encode_heatmap()`
        and `sizes` in place of `value`. A repeated `(x, y)` pair is not
        merged; each row draws its own bubble. Length checking and `sizes`
        being non-negative are deferred to render() time.

        Args:
            x: Each bubble's column category, one entry per row of
                data.
            y: Each bubble's row category, one entry per row of data.
            sizes: Each bubble's raw size value, non-negative.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._punchcard.x = x.copy()
        self._punchcard.y = y.copy()
        self._punchcard.sizes = sizes.copy()
        return self^

    def encode_barbs(
        var self,
        x: List[Float64],
        y: List[Float64],
        u: List[Float64],
        v: List[Float64],
    ) -> Self:
        """Map `Mark.BARBS`'s four channels: continuous `x`/`y` positions
        plus the `u`/`v` components of the vector at each. Speed is
        `hypot(u, v)` in whatever unit the caller supplies -- knots by
        convention, since the glyph's 50/10/5 increments are the knot ones
        -- and `v` is positive pointing up the page. Length checking is
        deferred to render() time.

        Args:
            x: The continuous x position of each barb.
            y: The continuous y position of each barb.
            u: Each barb's x-component, in the same unit as `v`.
            v: Each barb's y-component, positive pointing up the page.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._barbs.x = x.copy()
        self._barbs.y = y.copy()
        self._barbs.u = u.copy()
        self._barbs.v = v.copy()
        return self^

    def encode_barbs[
        dtype: DType
    ](
        var self,
        x: List[Scalar[dtype]],
        y: List[Scalar[dtype]],
        u: List[Scalar[dtype]],
        v: List[Scalar[dtype]],
    ) -> Self:
        """`encode_barbs()` generalized over numeric element type via
        `_materialize_scalar_list` (array_like.mojo). Delegates to the
        concrete overload.

        Args:
            x: The continuous x position of each barb.
            y: The continuous y position of each barb.
            u: Each barb's x-component -- any numeric `List[Scalar[dtype]]`.
            v: Each barb's y-component -- any numeric `List[Scalar[dtype]]`.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_barbs(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(u),
            _materialize_scalar_list(v),
        )

    def encode_marimekko(
        var self,
        categories: List[String],
        subcategories: List[String],
        values: List[List[Float64]],
    ) -> Self:
        """Map `Mark.MARIMEKKO`'s three channels: `categories` (one column
        each), `subcategories` (one stacked segment each), and `values`,
        where `values[i][j]` is `subcategories[i]`'s value for
        `categories[j]` (rows are subcategories, columns are categories,
        matching ECharts.jl's `marimekko()` and the opposite of
        `encode_grouped_bar()`'s `values[series][category]`). Length checking
        and non-negativity are deferred to render() time.

        Args:
            categories: One column per entry.
            subcategories: One stacked segment per entry.
            values: `values[i][j]` is `subcategories[i]`'s value for
                `categories[j]` (rows are subcategories, columns are
                categories).

        Returns:
            Self, for further chaining.
        """
        self._marimekko.categories = categories.copy()
        self._marimekko.subcategories = subcategories.copy()
        self._marimekko.values = values.copy()
        return self^

    def encode_marimekko[
        dtype: DType
    ](
        var self,
        categories: List[String],
        subcategories: List[String],
        values: List[List[Scalar[dtype]]],
    ) -> Self:
        """`encode_marimekko()`'s `values` generalized over numeric element type
        via `_materialize_nested_scalar_list` (array_like.mojo).
        `categories`/`subcategories` stay concrete. Delegates to the concrete
        overload.

        Args:
            categories: One column per entry.
            subcategories: One stacked segment per entry.
            values: `values[i][j]` is `subcategories[i]`'s value for
                `categories[j]` -- any numeric `List[List[Scalar[
                dtype]]]`.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_marimekko(
            categories, subcategories, _materialize_nested_scalar_list(values)
        )

    def encode_hierarchy(
        var self,
        ids: List[String],
        parent_ids: List[String],
        values: List[Float64],
    ) -> Self:
        """Map a flattened hierarchy onto `Mark.SUNBURST`/`TREE`/`TREEMAP`'s
        shared shape: one row per node, `ids[i]` its name, `parent_ids[i]`
        its parent's id (`""` for the single root, as in `d3.stratify()`),
        `values[i]` its magnitude if it's a leaf. An internal node's
        displayed value is always its descendant leaves' sum, computed at
        render() time (`_build_hierarchy_index`, hierarchy.mojo). Length
        checking, the single-root/duplicate-id/unresolved-parent validation,
        and the non-negative check are all deferred to render() time.

        Args:
            ids: Every node's unique id, flattened (not nested), one
                entry per node.
            parent_ids: Each node's parent id (a value present in
                `ids`, or `""` for the single root); paired with
                `ids[i]`.
            values: Each leaf node's magnitude; an internal node's
                displayed value is always its descendant leaves' sum
                instead, computed at render() time.

        Returns:
            Self, for further chaining.
        """
        self._hierarchy.ids = ids.copy()
        self._hierarchy.parent_ids = parent_ids.copy()
        self._hierarchy.values = values.copy()
        return self^

    def encode_chord(
        var self,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) -> Self:
        """Map an edge list onto `Mark.CHORD`'s shape (also used by
        `ARC_DIAGRAM`/`GRAPH`/`SANKEY`): one row per flow from
        `from_categories[i]` to `to_categories[i]` with magnitude
        `values[i]`. Every distinct name across both columns becomes a node
        (`_edge_node_index`, first-seen order with `from_categories` first,
        at render() time). `values` must be non-negative, checked at render()
        time along with the length match.

        Args:
            from_categories: Each flow's source node, one entry per
                row.
            to_categories: Each flow's destination node, one entry per
                row (paired with `from_categories[i]`).
            values: Each flow's magnitude; must be non-negative.

        Returns:
            Self, for further chaining.
        """
        self.x_categories = List[String]()
        self.x_data = List[Float64]()
        self.y_data = List[Float64]()
        self._edges.from_categories = from_categories.copy()
        self._edges.to_categories = to_categories.copy()
        self._edges.values = values.copy()
        return self^

    def encode_polar(
        var self, angle: List[Float64], radius: List[Float64]
    ) -> Self:
        """Map an angle column (radians) and a radius column onto `Mark.POLAR`'s
        two channels: one point per row, connected in row order (not sorted
        by angle, so a spiral past `2*pi` draws correctly). A single unnamed
        series with no legend; see `encode_polar_series()` for several.
        Length matching and `radius` being non-negative are checked at
        render() time.

        Args:
            angle: Radians, used exactly as given and unwrapped.
            radius: Must be non-negative (checked at render() time).

        Returns:
            Self, for further chaining.
        """
        self._polar.angle = angle.copy()
        self._polar.radius = radius.copy()
        self._polar.series_names = List[String]()
        self._polar.series_radius = List[List[Float64]]()
        return self^

    def encode_polar_series(
        var self,
        angle: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) -> Self:
        """Map a shared angle column (radians) plus one or more named series
        onto `Mark.POLAR`'s two channels, the multi-series form of
        `encode_polar()`. Every series shares the `angle` domain and one
        radius scale (`max(radius)` across every series), unlike
        `Mark.RADAR`'s per-indicator max. Each `series_values[i]` must match
        `angle`'s length and every value must be non-negative, checked at
        render() time.

        Args:
            angle: Radians, used exactly as given and unwrapped;
                shared by every series.
            series_names: One trace per name.
            series_values: `series_values[j]` is `series_names[j]`'s
                radius per angle; same length as `angle`, non-negative.

        Returns:
            Self, for further chaining.
        """
        self._polar.angle = angle.copy()
        self._polar.radius = List[Float64]()
        self._polar.series_names = series_names.copy()
        self._polar.series_radius = series_values.copy()
        return self^

    def encode_polar_series[
        dtype: DType
    ](
        var self,
        angle: List[Float64],
        series_names: List[String],
        series_values: List[List[Scalar[dtype]]],
    ) -> Self:
        """`encode_polar_series()`'s `series_values` generalized over numeric
        element type via `_materialize_nested_scalar_list` (array_like.mojo).
        `angle`/`series_names` stay concrete. Delegates to the concrete
        overload.

        Args:
            angle: Radians, used exactly as given and unwrapped;
                shared by every series.
            series_names: One trace per name.
            series_values: `series_values[j]` is `series_names[j]`'s
                radius per angle -- any numeric `List[List[Scalar[
                dtype]]]`.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_polar_series(
            angle, series_names, _materialize_nested_scalar_list(series_values)
        )

    def encode_radar(
        var self,
        indicators: List[String],
        max_values: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises -> Self:
        """Map `Mark.RADAR`'s four channels: one named axis per `indicators`
        entry with its own `max_values[i]`, and one named series per
        `series_names` entry with one value per indicator in
        `series_values`. Raises immediately on any length mismatch
        (`indicators`/`max_values`, `series_names`/`series_values`, or a
        series whose value count doesn't match `indicators`).

        Args:
            indicators: One spoke per entry, in the given order.
            max_values: Each spoke's own independent maximum, paired
                with `indicators[i]`.
            series_names: One polygon per name.
            series_values: `series_values[j]` is `series_names[j]`'s
                value per indicator.

        Returns:
            Self, for further chaining.

        Raises:
            If `indicators`/`max_values` lengths don't match,
            `series_names`/`series_values` lengths don't match, or any
            series' value count doesn't match `indicators`'s count.
        """
        if len(indicators) != len(max_values):
            raise Error(
                "Plot.encode_radar(): indicators and max_values must have the"
                " same length (got "
                + String(len(indicators))
                + " and "
                + String(len(max_values))
                + ")"
            )
        if len(series_names) != len(series_values):
            raise Error(
                "Plot.encode_radar(): series_names and series_values must have"
                " the same length (got "
                + String(len(series_names))
                + " and "
                + String(len(series_values))
                + ")"
            )
        for values in series_values:
            if len(values) != len(indicators):
                raise Error(
                    "Plot.encode_radar(): every series in series_values must"
                    " have one value per indicator (expected "
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

    def encode_radar[
        dtype: DType
    ](
        var self,
        indicators: List[String],
        max_values: List[Float64],
        series_names: List[String],
        series_values: List[List[Scalar[dtype]]],
    ) raises -> Self:
        """`encode_radar()`'s `series_values` generalized over numeric element
        type via `_materialize_nested_scalar_list` (array_like.mojo). The
        other parameters stay concrete; the overload below covers
        `max_values`. Delegates to the concrete overload.

        Args:
            indicators: One named axis per entry, each with its own
                `max_values[i]`.
            max_values: Each indicator's own maximum, same length as
                `indicators`.
            series_names: One polygon per name.
            series_values: `series_values[j]` is `series_names[j]`'s
                value per indicator -- any numeric `List[List[Scalar[
                dtype]]]`.

        Returns:
            Self, for further chaining.

        Raises:
            If `indicators`/`max_values` lengths don't match,
            `series_names`/`series_values` lengths don't match, or any
            series' value count doesn't match `indicators`'s count.
        """
        return self^.encode_radar(
            indicators,
            max_values,
            series_names,
            _materialize_nested_scalar_list(series_values),
        )

    def encode_radar[
        dtype: DType
    ](
        var self,
        indicators: List[String],
        max_values: List[Scalar[dtype]],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises -> Self:
        """`encode_radar()`'s `max_values` generalized over numeric element type
        via `_materialize_scalar_list` (array_like.mojo). The other
        parameters stay concrete. Delegates to the concrete overload.

        Args:
            indicators: One named axis per entry, each with its own
                `max_values[i]`.
            max_values: Each indicator's own maximum, same length as
                `indicators` -- any numeric `List[Scalar[dtype]]`.
            series_names: One polygon per name.
            series_values: `series_values[j]` is `series_names[j]`'s
                value per indicator.

        Returns:
            Self, for further chaining.

        Raises:
            If `indicators`/`max_values` lengths don't match,
            `series_names`/`series_values` lengths don't match, or any
            series' value count doesn't match `indicators`'s count.
        """
        return self^.encode_radar(
            indicators,
            _materialize_scalar_list(max_values),
            series_names,
            series_values,
        )

    def encode_gauge(
        var self,
        value: Float64,
        min_value: Float64 = 0.0,
        max_value: Float64 = 100.0,
        breakpoints: List[Float64] = List[Float64](),
        band_colors: List[Color] = List[Color](),
    ) -> Self:
        """Map a single reading onto `Mark.GAUGE`'s dial: `value` against
        `[min_value, max_value]` (default `[0, 100]`), clamped at render()
        time rather than rejected. `min_value < max_value` is checked at
        render() time.

        `breakpoints`/`band_colors` together replace the dial's colored
        bands: `breakpoints` an ascending list of fractions of the full span
        (e.g. `[0.5, 1.0]`), `band_colors` one color per band. Left empty,
        both reproduce ECharts' 20%/80%/100% green/blue/red default
        (`_gauge_breakpoints()`/`_gauge_band_colors()`, gauge.mojo). Length
        matching and ascending order are checked at render() time.

        Args:
            value: The reading to show, clamped (not rejected) to
                `[min_value, max_value]`.
            min_value: The dial's low end; defaults to `0.0`.
            max_value: The dial's high end; defaults to `100.0`.
            breakpoints: Ascending fractions of the `[min_value,
                max_value]` span; left empty (the default), reproduces
                ECharts' fixed 20%/80%/100% bands.
            band_colors: One color per `breakpoints` band, same
                length; left empty (the default), reproduces ECharts'
                fixed green/blue/red bands.

        Returns:
            Self, for further chaining.
        """
        self._gauge.value = value
        self._gauge.min_value = min_value
        self._gauge.max_value = max_value
        self._gauge.breakpoints = breakpoints.copy()
        self._gauge.band_colors = band_colors.copy()
        return self^

    def encode_parallel(
        var self,
        dims: List[String],
        row_names: List[String],
        data: List[List[Float64]],
    ) raises -> Self:
        """Map `Mark.PARALLEL`'s three channels: `dims` (one vertical axis per
        name, each scaled to its column's `[min, max]`), `row_names` (one
        polyline per name), and `data` (one list per row, one value per
        dimension). Raises immediately on a `row_names`/`data` length
        mismatch or a row whose value count doesn't match `dims`.

        Args:
            dims: One vertical axis per entry, each independently
                scaled to its own column's `[min, max]` across `data`.
            row_names: One polyline per entry.
            data: `data[row]` is `row_names[row]`'s polyline, one
                value per `dims` entry.

        Returns:
            Self, for further chaining.

        Raises:
            If `row_names`/`data` lengths don't match, or any row's
            value count doesn't match `dims`'s count.
        """
        if len(row_names) != len(data):
            raise Error(
                "Plot.encode_parallel(): row_names and data must have the same"
                " length (got "
                + String(len(row_names))
                + " and "
                + String(len(data))
                + ")"
            )
        for row in data:
            if len(row) != len(dims):
                raise Error(
                    "Plot.encode_parallel(): every row in data must have one"
                    " value per dimension (expected "
                    + String(len(dims))
                    + ", got "
                    + String(len(row))
                    + ")"
                )
        self._parallel.dims = dims.copy()
        self._parallel.row_names = row_names.copy()
        self._parallel.data = data.copy()
        return self^

    def encode_parallel[
        dtype: DType
    ](
        var self,
        dims: List[String],
        row_names: List[String],
        data: List[List[Scalar[dtype]]],
    ) raises -> Self:
        """`encode_parallel()`'s `data` generalized over numeric element type
        via `_materialize_nested_scalar_list` (array_like.mojo). `dims`/
        `row_names` stay concrete. Delegates to the concrete overload.

        Args:
            dims: One vertical axis per entry, each independently
                scaled to its own column's `[min, max]` across `data`.
            row_names: One polyline per entry.
            data: `data[row]` is `row_names[row]`'s polyline, one
                value per `dims` entry -- any numeric `List[List[
                Scalar[dtype]]]`.

        Returns:
            Self, for further chaining.

        Raises:
            If `row_names`/`data` lengths don't match, or any row's
            value count doesn't match `dims`'s count.
        """
        return self^.encode_parallel(
            dims, row_names, _materialize_nested_scalar_list(data)
        )

    def encode_distribution(
        var self, categories: List[String], values: List[List[Float64]]
    ) raises -> Self:
        """Map a category column and, per category, a list of raw values onto
        the shape `Mark.BEESWARM`/`VIOLIN`/`RIDGELINE` share: the same
        outer-list-per-category shape as `encode_boxplot()`, but kept as raw
        values rather than reduced to a five-number summary, since a swarm
        draws every point and a density estimate needs the raw values.
        Raises immediately on a `categories`/`values` length mismatch or an
        empty value list.

        Args:
            categories: One row per entry, in the given order.
            values: Each category's raw values (`values[i]`) -- must
                be non-empty.

        Returns:
            Self, for further chaining.

        Raises:
            If `categories`/`values` lengths don't match, `categories`
            is empty, or any category's value list is empty.
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
        _require_non_empty(len(categories), "Plot.encode_distribution()")
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

    def encode_distribution[
        dtype: DType
    ](
        var self, categories: List[String], values: List[List[Scalar[dtype]]]
    ) raises -> Self:
        """`encode_distribution()`'s `values` generalized over numeric element
        type via `_materialize_nested_scalar_list` (array_like.mojo).
        `categories` stays concrete. Delegates to the concrete overload.

        Args:
            categories: One distribution per entry, in the given
                order.
            values: Each category's raw values -- any numeric
                `List[List[Scalar[dtype]]]`.

        Returns:
            Self, for further chaining.

        Raises:
            If `categories`/`values` lengths don't match, or any
            category's value list is empty.
        """
        return self^.encode_distribution(
            categories, _materialize_nested_scalar_list(values)
        )

    def encode_single_axis(
        var self,
        x: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
    ) -> Self:
        """Map one continuous column plus the optional `color`/
        `color_categories`/`size` channels onto `Mark.SINGLE_AXIS`'s one-axis
        shape: `encode()` without a `y`. `y_data` is filled with one
        placeholder `0.0` per row (never read as a value; see
        `_render_single_axis`) so `_validate_continuous_encoding`'s length
        check and `Mark.POINT`'s `_draw_point_layer` work unchanged.

        Args:
            x: The continuous column, one entry per point.
            color: Optional continuous color channel; mutually
                exclusive with `color_categories`. Left empty (the
                default), every point uses `Theme.mark_color`.
            color_categories: Optional discrete color channel;
                mutually exclusive with `color`. Left empty (the
                default), every point uses `Theme.mark_color`.
            size: Optional point-size channel. Left empty (the
                default), every point uses `Theme.point_radius`.

        Returns:
            Self, for further chaining.
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
        """Attach a full `Theme` to this plot, replacing the default one. Every
        styling knob lives on `Theme`.

        Args:
            t: The `Theme` to attach, replacing whatever was set
                before (the default `Theme()` if this is the first
                call).

        Returns:
            Self, for further chaining.
        """
        self._theme = t
        return self^

    def labels(
        var self,
        title: String = "",
        subtitle: String = "",
        x_title: String = "",
        y_title: String = "",
        description: String = "",
    ) -> Self:
        """Set the chart title/subtitle and/or axis titles. Named `x_title`/
        `y_title` rather than `x`/`y` so a call next to
        `.encode(x=..., y=...)` never reads as setting data.

        Each is independent and defaults to `""` (not set); layout space is
        reserved only for the non-empty visible ones (`title`/`subtitle`/
        `x_title`/`y_title` -- `description` draws nothing). `subtitle`
        draws directly beneath `title`, smaller and in `Theme.subtitle_color`;
        with no `title` it draws at the top position `title` would have used.

        `x_title`/`y_title` caption whatever is drawn along the bottom/left
        edge, whichever axis that is for the mark's orientation. `Mark.ARC`
        has no axes, so `x_title`/`y_title` raise at render() time there;
        only `title`/`subtitle`/`description` apply.

        `description` (#212) is an SVG `<desc>` -- longer, screen-reader-only
        context `subtitle` alone can't carry since it's drawn on the chart
        itself. `save()`/`save_layers()`/`save_facets()` write it (falling
        back to `subtitle` when empty) automatically whenever `title` is set;
        see `accessible_svg_string()`'s own docstring for the full markup.

        Args:
            title: The chart's title. Left empty (the default),
                reserves no layout space for it.
            subtitle: A secondary line shown under the title,
                independent of whether `title` is also set.
            x_title: Caption for whatever's drawn along the bottom
                edge; raises at render() time on `Mark.ARC`.
            y_title: Caption for whatever's drawn along the left edge;
                raises at render() time on `Mark.ARC`.
            description: Optional longer SVG `<desc>` text, drawn
                nowhere on the chart itself; falls back to `subtitle`
                when left empty.

        Returns:
            Self, for further chaining.
        """
        self._labels.title = title
        self._labels.subtitle = subtitle
        self._labels.x_title = x_title
        self._labels.y_title = y_title
        self._labels.description = description
        return self^

    def series_name(var self, name: String) -> Self:
        """Name this layer for `render_layers()`'s/`render_layers_svg()`'s
        per-layer legend (#215): a swatch (this layer's own
        `Theme.mark_color`) plus `name`, one row per named layer, drawn
        before any per-point `color`/`color_categories` legend a `Mark.
        POINT` layer has of its own. A `Plot.secondary_axis()` layer's row
        gets `" (right axis)"` appended, so the reader knows which axis it
        reads against.

        `render_layers()`/`render_layers_svg()` and
        `_render_bar_combo_layers` (the `Mark.BAR`-combo path) only;
        `render()`/`render_svg()` ignore it, since a standalone plot has
        only one series, nothing for a legend entry to distinguish.
        Layers with no name draw no row -- an all-unnamed `plots` list
        renders exactly as before this existed.

        Args:
            name: This layer's label in the per-layer legend. Left
                empty (the default, via not calling this), the layer
                draws no legend row.

        Returns:
            Self, for further chaining.

        See the Cookbook's own "Layer Legend" recipe (docs/src/
        cookbook_recipes/layer_legend.mojo) for a full worked example.
        """
        self._labels.series_name = name
        return self^

    def annotate_line(var self, value: Float64, label: String = "") -> Self:
        """Add a horizontal reference line at `value` on the y-axis (ECharts'
        `markLine` with a fixed value; no auto-computed average/max/min
        modes). Each call adds a line. `label`, when non-empty, draws to the
        right of the line in `Theme.annotation_color`; the line spans the
        full plot width, solid (canvas has no dashed-stroke primitive). A
        `value` outside the mark's padded y-domain draws nothing.

        Only meaningful on a mark whose y-axis is a continuous
        `LinearScale`, checked at render() time via
        `_RenderResult.has_y_scale`: `Mark.POINT`/`LINE`/`AREA`/
        `EFFECT_SCATTER` and every mark sharing `_CategoricalFrame` (`BAR`/
        `LOLLIPOP`/`WATERFALL`/`BOX`/`CANDLESTICK`/`BULLET`/`GROUPED_BAR`/
        `STACKED_BAR`/`STREAMGRAPH`). Other marks raise. Also wired into
        `render_facets()` (per cell) and `render_layers()` (per layer,
        against that layer's own primary or secondary y-scale).

        Args:
            value: The y-value to draw the line at. Outside the
                mark's (padded) y-domain, draws nothing.
            label: Drawn to the right of the line when non-empty; left
                empty (the default), the line draws with no label.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark has no genuine continuous y-axis.

        See the Cookbook's own "Reference Line" recipe (docs/src/
        cookbook_recipes/annotate_line.mojo) for a full worked example.
        """
        self._annotations.line_values.append(value)
        self._annotations.line_labels.append(label)
        return self^

    def annotate_area(
        var self, y0: Float64, y1: Float64, label: String = ""
    ) -> Self:
        """Add a shaded horizontal band from `y0` to `y1` on the y-axis
        (ECharts' `markArea` with a fixed pair). Each call adds a band.
        `label`, when non-empty, draws inside the band near its top edge in
        `Theme.annotation_color`. `y0`/`y1` may be given in either order.

        A band partially overlapping the mark's padded y-domain clips to the
        visible portion; one with no overlap draws nothing. Drawn on top of
        the mark at `Theme.annotation_area_color`'s partial opacity, so the
        mark's ink shows through.

        Same mark support and facets/layers wiring as `annotate_line()`.

        Args:
            y0: One edge of the band; need not be the lower one.
            y1: The other edge of the band; whichever of `y0`/`y1` is
                smaller becomes the band's bottom edge.
            label: Drawn inside the band near its top edge when
                non-empty; left empty (the default), the band draws
                with no label.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark has no genuine continuous y-axis.

        See the Cookbook's own "Reference Band" recipe (docs/src/
        cookbook_recipes/annotate_area.mojo) for a full worked example.
        """
        self._annotations.area_y0.append(y0)
        self._annotations.area_y1.append(y1)
        self._annotations.area_labels.append(label)
        return self^

    def annotate_vline(var self, value: Float64, label: String = "") -> Self:
        """Add a vertical reference line at `value` on the x-axis:
        `annotate_line()`'s mirror image, with the same fixed-value scope,
        additive behavior, styling, and out-of-domain skip.

        Narrower mark support: only `Mark.POINT`/`LINE`/`AREA`/
        `EFFECT_SCATTER`, the marks with a continuous x-axis; a categorical
        x-axis has no numeric value to place a line against (see
        `_RenderResult`). Raises on an unsupported mark. Also wired into
        `render_facets()` (per cell) and `render_layers()` (per layer,
        against the one shared continuous x-scale every layer uses --
        raises on a `Mark.BAR` combo chart's categorical x-axis instead,
        same as a standalone unsupported mark).

        Args:
            value: The x-value to draw the line at. Outside the
                mark's (padded) x-domain, draws nothing.
            label: Drawn near the line when non-empty; left empty
                (the default), the line draws with no label.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark has no genuine continuous x-axis.

        See the Cookbook's own "Vertical Reference Line" recipe (docs/
        src/cookbook_recipes/annotate_vline.mojo) for a full worked
        example.
        """
        self._annotations.vline_values.append(value)
        self._annotations.vline_labels.append(label)
        return self^

    def annotate_point(
        var self, x: Float64, y: Float64, label: String = ""
    ) -> Self:
        """Add a single labeled point at `(x, y)` (ECharts' `markPoint` with a
        fixed coordinate): a small filled marker in `Theme.annotation_color`,
        with `label` just above it when non-empty. Each call adds a point.

        Needs a continuous coordinate on both axes, so only `Mark.POINT`/
        `LINE`/`AREA`/`EFFECT_SCATTER` support it; raises otherwise. A point
        outside the padded domain on either axis draws nothing. Also wired
        into `render_facets()` (per cell) and `render_layers()` (per layer,
        against that layer's own primary or secondary y-scale and the one
        shared x-scale).

        Args:
            x: The point's x-coordinate. Outside the mark's (padded)
                x-domain, draws nothing.
            y: The point's y-coordinate. Outside the mark's (padded)
                y-domain, draws nothing.
            label: Drawn just above the point when non-empty; left
                empty (the default), the point draws with no label.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark has no genuine continuous x/y-axis.

        See the Cookbook's own "Point Marker" recipe (docs/src/
        cookbook_recipes/annotate_point.mojo) for a full worked
        example.
        """
        self._annotations.point_x.append(x)
        self._annotations.point_y.append(y)
        self._annotations.point_labels.append(label)
        return self^

    def annotate_band(
        var self,
        x: List[Float64],
        y_lower: List[Float64],
        y_upper: List[Float64],
        label: String = "",
    ) -> Self:
        """Shade the region between two curves that vary with `x`: a confidence
        band around a trend line, or a min/max envelope (matplotlib's
        `fill_between`, ggplot's `geom_ribbon`). `annotate_area()`'s band is
        a constant `(y0, y1)` pair; this takes two parallel lists keyed by
        `x`. Each call adds a band.

        `x`/`y_lower`/`y_upper` must be the same length and every
        `y_upper[i] >= y_lower[i]`, both checked at render() time. `x` need
        not be sorted; the top edge traces `(x[i], y_upper[i])` in order and
        the bottom edge walks back in reverse.

        Filled in `Theme.annotation_area_color` with straight edges (no
        `Theme.line_smoothing`). `label`, when non-empty, centers above the
        band's middle x-index on its upper edge.

        Only `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER`, as for
        `annotate_point()`. A band is clipped to the overlapping range on
        both axes; one with no overlap draws nothing. Same facets/layers
        wiring as `annotate_point()`.

        Args:
            x: The band's x column, one entry per (`y_lower`, `y_upper`)
                pair, in the order the edges should trace.
            y_lower: The band's bottom edge, one entry per `x`.
            y_upper: The band's top edge, one entry per `x`; every
                value must be `>= y_lower`'s value at that same index.
            label: Drawn centered above the band's middle point when
                non-empty; left empty (the default), the band draws
                with no label.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the lengths mismatch, an upper/lower value
            is inverted, or the mark has no genuine continuous x/y-axis.

        See the Cookbook's own "Confidence Band" recipe (docs/src/
        cookbook_recipes/annotate_band.mojo) for a full worked example.
        """
        self._annotations.band_x.append(x.copy())
        self._annotations.band_y_lower.append(y_lower.copy())
        self._annotations.band_y_upper.append(y_upper.copy())
        self._annotations.band_labels.append(label)
        return self^

    def annotate_best_fit(
        var self,
        show_equation: Bool = False,
        show_r_squared: Bool = False,
        label: String = "",
    ) -> Self:
        """Overlay an ordinary-least-squares best-fit line computed from this
        plot's own `x_data`/`y_data` at render() time, so it works whether
        called before or after `.encode()`. Not additive: the last call wins,
        since the fit is determined by the data.

        Drawn as a solid line in `Theme.annotation_color` across the mark's
        full padded x-domain. `show_equation`/`show_r_squared` each add one
        line of text right-aligned near the plot's top-right corner; `label`,
        when non-empty, draws as a heading above them. R-squared is
        `1 - SS_res/SS_tot`, defined as `1.0` when `SS_tot` is `0.0`.

        Only `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER`. Raises at render()
        time with fewer than 2 points or when every `x` value is identical.
        Also wired into `render_facets()` (per cell, fit to that cell's own
        data) and `render_layers()` (per layer, fit to that layer's own
        data against its primary or secondary y-scale and the shared
        x-scale).

        Args:
            show_equation: Draw the fitted line's own `y = mx + b`
                text when `True`; `False` (the default) draws only the
                line itself.
            show_r_squared: Draw the fit's R-squared text when `True`;
                `False` (the default) omits it.
            label: An optional heading drawn above the equation/
                R-squared text; left empty (the default), no heading
                draws (independent of `show_equation`/`show_r_
                squared` -- a `label` with both left `False` still
                draws only the line, no text at all).

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark has no genuine continuous x/y-axis,
            has fewer than 2 points, or every x value is identical.

        See the Cookbook's own "Best-Fit Trend Line" recipe (docs/src/
        cookbook_recipes/best_fit_line.mojo) for a full worked example.
        """
        self._annotations.best_fit = True
        self._annotations.best_fit_show_equation = show_equation
        self._annotations.best_fit_show_r_squared = show_r_squared
        self._annotations.best_fit_label = label
        return self^

    def scale_y_log(var self) -> Self:
        """Scale the y-axis logarithmically (base 10). Every y value, and every
        y-axis annotation value, must be strictly positive; `render()`/
        `render_svg()` raise otherwise (see `_log_data_extent()`).

        `Mark.POINT`/`LINE`/`EFFECT_SCATTER` only, and standalone `render()`/
        `render_svg()` only: a categorical mark has no continuous y-domain,
        `Mark.AREA`'s y-domain is forced through zero (which has no
        logarithm), and `render_layers()` combines layers into one linear
        scale. Every tick/gridline/point/annotation still goes through
        `LinearScale.to_pixel()` with real-unit values; see that method.

        Returns:
            Self, for further chaining.

        See the Cookbook's own "Log Scale (Y-Axis)" recipe (docs/src/
        cookbook_recipes/log_scale_y.mojo) for a full worked example.
        """
        self._y_log = True
        return self^

    def scale_x_log(var self) -> Self:
        """`scale_y_log()`'s x-axis mirror. `Mark.POINT`/`LINE`/`AREA`/
        `EFFECT_SCATTER` (x is never forced through zero, so `AREA` is
        allowed here), standalone `render()`/`render_svg()` only.

        Returns:
            Self, for further chaining.

        See the Cookbook's own "Log Scale (X-Axis)" recipe (docs/src/
        cookbook_recipes/log_scale_x.mojo) for a full worked example.
        """
        self._x_log = True
        return self^

    def scale_x_domain(var self, min: Float64, max: Float64) -> Self:
        """Pin the x-axis domain to `[min, max]` exactly (#209), replacing
        `_data_extent()`'s 5%-padded domain (or `_log_data_extent()`'s
        when `scale_x_log()` is also set). For comparable charts across
        runs, a fixed reference range, or a zoomed-in view, without
        padding the data with fake points.

        `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER` only (the same marks
        `_render_generic`'s continuous path draws), standalone `render()`/
        `render_svg()` and `render_facets()` only -- `render_layers()`
        raises if any layer sets this, since a shared axis across several
        layers needs one shared answer, not one per layer; the categorical
        marks (`Mark.BAR`, `LOLLIPOP`, ...) raise too, left for a
        follow-up. `render_facets()` applies this per cell, so every cell
        sharing the same override reads as one shared domain -- the
        facets counterpart to `shared_y_scale=True` for the x-axis (which
        has no `shared_y_scale` equivalent otherwise).

        A point outside `[min, max]` still computes a real (off-plot)
        pixel position via `LinearScale.to_pixel()`, same as it would if
        it merely fell outside a padded auto-computed domain; the SVG
        `viewBox`'s own default `overflow: hidden` clips it at the canvas
        edge, and the raster `Canvas`'s own pixel buffer bounds-checks
        every draw call, so nothing paints outside the plot in either
        backend.

        Args:
            min: The domain's lower bound. For a log x-axis
                (`scale_x_log()`), must be `> 0`.
            max: The domain's upper bound; must be `> min`.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if `min >= max`, the mark doesn't support this,
            or (with `scale_x_log()`) `min <= 0`.
        """
        self._x_domain = _DomainOverride(min, max)
        return self^

    def scale_y_domain(var self, min: Float64, max: Float64) -> Self:
        """`scale_x_domain()`'s y-axis mirror -- see that method's own
        docstring for the shared rules. Overrides `_zero_baseline_y_
        extent()`'s forced-zero domain on `Mark.AREA` too: an explicit
        `[min, max]` is what the caller asked for, zero baseline or not.

        Args:
            min: The domain's lower bound. For a log y-axis
                (`scale_y_log()`), must be `> 0`.
            max: The domain's upper bound; must be `> min`.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if `min >= max`, the mark doesn't support this,
            or (with `scale_y_log()`) `min <= 0`.
        """
        self._y_domain = _DomainOverride(min, max)
        return self^

    def secondary_axis(var self) -> Self:
        """Draw this layer's y values against a second, independent y-domain on
        the plot's right edge instead of `render_layers()`'s shared left-axis
        domain (ECharts' `yAxisIndex: 1`, as a boolean since only two y-axes
        are ever drawn). For a combo chart whose series have different
        units; see `_render_layers_generic`.

        `render_layers()`/`render_layers_svg()` only; `render()`/
        `render_svg()` raise if a plot with this set reaches them. At least
        one layer must stay on the primary axis. The secondary axis gets an
        axis line, ticks, and tick labels on the right edge but no
        gridlines. This layer's `Plot.labels()` `y_title` captions the
        secondary axis (see `_secondary_axis_y_title`).

        Returns:
            Self, for further chaining.

        See the Cookbook's own "Dual Y-Axis" recipe (docs/src/
        cookbook_recipes/dual_axis.mojo) for a full worked example.
        """
        self._secondary_axis = True
        return self^


struct _CategoricalIndex(Movable):
    """`_categorical_indices`'s result: a categorical column's `domain` (its
    distinct values in first-seen order) plus `indices`, each row's
    position in that domain.
    """

    var domain: List[String]
    var indices: List[Int]

    def __init__(out self, var domain: List[String], var indices: List[Int]):
        self.domain = domain^
        self.indices = indices^


def _categorical_indices(data: List[String]) raises -> _CategoricalIndex:
    """A categorical column's domain and its per-row indices into that
    domain, resolved in one pass through a `Dict`, so every later lookup
    is an array read rather than a string search. First-seen order.
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


struct _BaselineRect(Movable):
    """`_pull_off_axis_line`'s `(y, height)` result."""

    var y: Int
    var height: Int

    def __init__(out self, y: Int, height: Int):
        self.y = y
        self.height = height


struct _BandLabelPoint(Copyable, ImplicitlyCopyable, Movable):
    """A label's baseline point in pixels; `_Orientation.band_label_point`'s
    result.
    """

    var x: Int
    var y: Int

    def __init__(out self, x: Int, y: Int):
        self.x = x
        self.y = y


struct _BandLabel(Copyable, ImplicitlyCopyable, Movable):
    """A label placed just past a band rect's far end -- position plus
    the `TextAlign` that goes with it, since which side the text hangs
    off depends on the same sign the position does."""

    var x: Int
    var y: Int
    var align: TextAlign

    def __init__(out self, x: Int, y: Int, align: TextAlign):
        self.x = x
        self.y = y
        self.align = align


struct _Orientation(Copyable, ImplicitlyCopyable, Movable):
    """Which way a categorical mark's bands run, and the places that differ
    because of it.

    Every categorical mark has a band axis (one slot per category, an
    `OrdinalScale`) and a value axis (the continuous `LinearScale`).
    Drawing is the same arithmetic either way until band and value become
    concrete x/y pixels: emitting a rect, placing a label, drawing a line
    or point. This holds those moments so a mark's drawing loop is
    written once.

    The axis frames themselves stay two functions
    (`_draw_categorical_axis_frame` and
    `_draw_horizontal_categorical_axis_frame`, gantt.mojo); which scale
    is which type, which axis reverses, and which margin grows differ
    there. Both frames name their fields `x_scale`/`y_scale` with the
    types swapped, so a caller unpacks its own frame into band/value and
    passes those.
    """

    var horizontal: Bool
    """`False`: categories run left-to-right, values upward (the
    default). `True`: categories run top-to-bottom, values rightward."""

    def __init__(out self, horizontal: Bool):
        """Construct an orientation.

        Args:
            horizontal: Whether categories run down the y-axis.
        """
        self.horizontal = horizontal

    def fill_band_rect[
        T: DrawTarget
    ](
        self,
        mut target: T,
        extent: _BaselineRect,
        band_pos: Int,
        band_size: Int,
        color: Color,
    ):
        """Fill one band's rect: `extent` spans the value axis (what
        `_pull_off_axis_line` returns), `band_pos`/`band_size` the band axis.
        """
        if self.horizontal:
            target.fill_rect(
                extent.y, band_pos, extent.height, band_size, color
            )
        else:
            target.fill_rect(
                band_pos, extent.y, band_size, extent.height, color
            )

    def value_line[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along_a: Int,
        along_b: Int,
        across: Int,
        color: Color,
        width: Float64,
    ):
        """A line running *along* the value axis at a fixed band
        position -- a box's whisker, a lollipop's stem."""
        if self.horizontal:
            target.draw_line_aa(
                along_a, across, along_b, across, color, width=width
            )
        else:
            target.draw_line_aa(
                across, along_a, across, along_b, color, width=width
            )

    def band_line[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along: Int,
        across_a: Int,
        across_b: Int,
        color: Color,
        width: Float64,
    ):
        """A line running *across* the band at a fixed value -- a box's
        median line and whisker caps. The perpendicular of
        `value_line`."""
        if self.horizontal:
            target.draw_line_aa(
                along, across_a, along, across_b, color, width=width
            )
        else:
            target.draw_line_aa(
                across_a, along, across_b, along, color, width=width
            )

    def baseline_pull(self) -> Float64:
        """Which direction is into the plot area, away from the categorical
        axis line: `-1.0` vertically (that line is the frame's bottom) and
        `+1.0` horizontally (the frame's left edge). Used to nudge a stroked
        mark 1px clear of the axis line; `_pull_off_axis_line` does the same
        for filled rects.
        """
        return 1.0 if self.horizontal else -1.0

    def path_move_to(
        self, mut path: Path, along: Float64, across: Float64
    ) raises:
        """`Path.move_to` in band/value terms rather than x/y -- for a
        mark whose outline is built point by point (a violin's KDE
        silhouette) rather than from rects and lines."""
        if self.horizontal:
            path.move_to(along, across)
        else:
            path.move_to(across, along)

    def path_line_to(
        self, mut path: Path, along: Float64, across: Float64
    ) raises:
        """`Path.line_to` in band/value terms -- see `path_move_to`."""
        if self.horizontal:
            path.line_to(along, across)
        else:
            path.line_to(across, along)

    def value_stem_path(
        self, along_from: Float64, along_to: Float64, across: Float64
    ) raises -> Path:
        """A straight two-point `Path` running along the value axis at
        a fixed band position -- a lollipop's stem. A `Path` rather
        than `value_line` because it is stroked at `Theme.line_width`
        through `stroke_path_aa`, not drawn as a 1px `draw_line_aa`."""
        var stem = Path()
        if self.horizontal:
            stem.move_to(along_from, across)
            stem.line_to(along_to, across)
        else:
            stem.move_to(across, along_from)
            stem.line_to(across, along_to)
        return stem^

    def band_point[
        T: DrawTarget
    ](self, mut target: T, along: Int, across: Int, radius: Int, color: Color):
        """A filled circle at (value, band) -- a box's outlier, a
        beeswarm's point."""
        if self.horizontal:
            target.fill_circle_aa(along, across, radius, color)
        else:
            target.fill_circle_aa(across, along, radius, color)

    def outside_band_label(
        self,
        extent: _BaselineRect,
        band_pos: Int,
        band_size: Int,
        negative: Bool,
        label_gap: Int,
        font_size: Float64,
    ) -> _BandLabel:
        """Where a label just past the bar's far end goes (`Mark.BAR`/
        `GROUPED_BAR`'s placement, as opposed to `band_label_point`'s
        centered-inside one). `negative` flips which end it hangs off, so a
        bar extending below or left of the baseline never collides with its
        label.

        Vertically the text sits above the bar's top edge and drops a full
        `font_size` when it moves below (the baseline is at the bottom of the
        glyph); horizontally it hangs off the end, vertically centered on the
        band with the `font_size * 0.35` nudge, and the `TextAlign` flips
        instead.
        """
        var across = band_pos + band_size // 2
        if self.horizontal:
            var x = (
                extent.y
                - label_gap if negative else extent.y
                + extent.height
                + label_gap
            )
            var align = TextAlign.RIGHT if negative else TextAlign.LEFT
            return _BandLabel(x, across + Int(font_size * 0.35), align)
        var y = (
            extent.y
            + extent.height
            + label_gap
            + Int(font_size) if negative else extent.y
            - label_gap
        )
        return _BandLabel(across, y, TextAlign.CENTER)

    def band_label_point(
        self,
        extent: _BaselineRect,
        band_pos: Int,
        band_size: Int,
        font_size: Float64,
    ) -> _BandLabelPoint:
        """Where a label centered inside `extent` x `band_pos` goes. `TextAlign`
        has no vertical option, so the returned `y` already carries the
        `font_size * 0.35` baseline-centering nudge; callers pass the point
        straight to `_TextRequest`.
        """
        var along = extent.y + extent.height // 2
        var across = band_pos + band_size // 2
        var nudge = Int(font_size * 0.35)
        if self.horizontal:
            return _BandLabelPoint(along, across + nudge)
        return _BandLabelPoint(across, along + nudge)


def _pull_off_axis_line(
    edge_a: Int, edge_b: Int, axis_line_py: Int
) -> _BaselineRect:
    """The `(y, height)` of a fill spanning `edge_a`..`edge_b` (in either
    order), with whichever edge sits exactly on `axis_line_py` nudged 1px
    toward the other edge.

    Every magnitude-from-baseline mark (`Mark.BAR`/`LOLLIPOP`/`WATERFALL`/
    `BULLET`/`GROUPED_BAR`/`STACKED_BAR`/`AREA`) has one edge at the zero
    baseline. When that baseline is the drawn axis-line row (every value
    non-negative, so `_zero_baseline_y_extent`'s domain is `[0, hi]`), a
    solid fill drawn after the axis frame paints over the line's
    antialiasing (issue #105). Pulling the edge 1px inward leaves a
    hairline of background between mark and line.

    A zero-height span is left alone rather than becoming a 1px sliver.
    A no-op when neither edge is `axis_line_py` (mixed-sign or
    all-negative domains).
    """
    var y = min(edge_a, edge_b)
    var height = max(edge_a, edge_b) - y
    if height <= 0:
        return _BaselineRect(y, height)
    if y == axis_line_py:
        return _BaselineRect(y + 1, height - 1)
    if y + height == axis_line_py:
        return _BaselineRect(y, height - 1)
    return _BaselineRect(y, height)


def _build_line_path(
    px: List[Float64], py: List[Float64], smoothing: Float64
) raises -> Path:
    """The `Path` a `Mark.LINE` plot strokes through its
    already-pixel-projected points, and the curve `Mark.AREA` fills down
    to the baseline from.

    `smoothing == 0.0` builds a `move_to` plus one `line_to` per point
    through an explicit early branch, so the default render is
    byte-identical to one that never touched curve math (a flattened
    cubic Bezier samples at even parameter spacing, not even pixel
    spacing, so even a straight cubic can flatten to different
    intermediate points).

    `smoothing > 0.0` builds one cubic Bezier segment per consecutive
    pair of points with Catmull-Rom-derived tangents: control point =
    endpoint +/- (next point minus previous point)/6, with the first and
    last points clamped to a one-sided tangent. `smoothing` scales the
    tangent length directly, so `1.0` is the textbook Catmull-Rom curve
    and `0.5` bows half as far.
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
        path.cubic_curve_to(
            px[i] + t1x,
            py[i] + t1y,
            px[i + 1] - t2x,
            py[i + 1] - t2y,
            px[i + 1],
            py[i + 1],
        )
    return path^


struct _Decimated(Movable):
    """`_decimate_to_pixel_columns`' result: the reduced `px`/`py` pair plus
    `applied`, whether anything was dropped.
    """

    var px: List[Float64]
    var py: List[Float64]
    var applied: Bool

    def __init__(
        out self, var px: List[Float64], var py: List[Float64], applied: Bool
    ):
        self.px = px^
        self.py = py^
        self.applied = applied


def _decimate_to_pixel_columns(
    px: List[Float64], py: List[Float64]
) -> _Decimated:
    """Reduce a dense polyline to at most two points per horizontal pixel
    column.

    A `Mark.LINE`/`AREA` plot of 5000 points into a ~640px-wide plot area
    hands the rasterizer roughly eight segments per pixel column, and
    `stroke_path_aa` pays full per-segment cost for each (~263us/segment,
    so a 5000-point line took ~1.7s against ~21ms for the same points as
    a scatter).

    Per column this keeps the minimum and maximum y, in original data
    order (collapsed to one point when they are the same sample), which
    preserves the envelope: a spike inside one column still reaches its
    true extent. Keeping four points per column (first/last as well) was
    tried and dropped nothing at all for a 2000-point series over ~500
    columns. Min and max are real samples, so the joins between columns
    move by at most a pixel.

    Two guards: `px` must be non-decreasing, since `mark_line()` connects
    points in data order and a path that doubles back would be
    reordered; and it only engages when there are more than twice as
    many points as columns, so every small chart renders byte-for-byte
    as before.
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

        # The column's two extremes, in the order the data visited them; one
        # point when they're the same sample.
        var first = i_min if i_min <= i_max else i_max
        var second = i_max if i_min <= i_max else i_min
        out_x.append(px[first])
        out_y.append(py[first])
        if second != first:
            out_x.append(px[second])
            out_y.append(py[second])

        start = end + 1

    return _Decimated(out_x^, out_y^, True)


def _max_label_width(
    labels: List[String], font_size: Float64
) raises -> Float64:
    """The widest rendered ink width among `labels` at `font_size`, used to
    size the left margin to the y-axis tick labels before the plot area's
    pixel range is finalized (tick values depend only on the data domain,
    so measuring early is exact).

    Resolves its font fresh in a new `FontCache`. A caller measuring
    twice in one render (an axis tick list and then a legend's labels)
    should use the `cache=` overload and share one cache: a fresh cache
    re-pays font resolution and TTF parsing (0.44ms for a 5-label call
    against 0.056ms warm).
    """
    var cache = FontCache()
    return _max_label_width(labels, font_size, cache=cache)


def _max_label_width(
    labels: List[String], font_size: Float64, *, mut cache: FontCache
) raises -> Float64:
    """`_max_label_width` resolving fonts through `cache`; see the overload
    above.
    """
    var max_width = 0.0
    for label in labels:
        var m = measure_text(label, font_size, cache=cache)
        if m.width > max_width:
            max_width = m.width
    return max_width


def _dynamic_legend_width(
    labels: List[String], content_width: Int, sc: _Scaled
) raises -> Int:
    """How wide a legend column needs to be to fit `labels` next to
    `content_width`-wide content (a swatch, a gradient bar, or the widest
    size-legend circle): `content_width` + `label_gap` + the widest label
    (`_max_label_width`) + `margin_buffer`, `max`'d against
    `sc.legend_width` so a column never gets narrower than `Theme`'s
    fixed default. Every call site measures its real label list before
    finalizing `plot_x1`. Has a `cache=` overload for the same reason
    `_max_label_width` does.
    """
    var cache = FontCache()
    return _dynamic_legend_width(labels, content_width, sc, cache=cache)


def _dynamic_legend_width(
    labels: List[String],
    content_width: Int,
    sc: _Scaled,
    *,
    mut cache: FontCache,
) raises -> Int:
    """`_dynamic_legend_width` resolving fonts through `cache`; see the
    overload above.
    """
    return max(
        sc.legend_width,
        content_width
        + sc.label_gap
        + Int(_max_label_width(labels, sc.font_size, cache=cache))
        + sc.margin_buffer,
    )


struct _TextRequest(Copyable, Movable):
    """One deferred `draw_text()` call, collected while the
    `DrawTarget`-generic rendering pass runs (`DrawTarget` has no
    `draw_text`). `render()`/`render_svg()` each replay the list their own
    way afterward, via `canvas.text.draw_text` or `SvgCanvas.draw_text`.

    `family` is baked in at construction from whichever `Theme` built the
    request, since `render_facets()`/`render_layers()` combine several
    independently themed `Plot`s into one draw pass (see
    `Theme.font_family`). `bold` defaults to `False` everywhere except
    `_label_text_requests`'s chart title.
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


def _draw_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    labels: List[String],
    palette: List[Color],
    x: Int,
    y: Int,
    theme: Theme,
    shapes: List[PointShape] = List[PointShape](),
) raises:
    """A swatch+label legend, one row per entry in `labels`, starting at
    (x, y) and growing downward; shared by every mark with a categorical
    legend. `palette` is indexed `i % len(palette)`, the same way the
    marks were colored, so a row shows the exact color its category got.

    `shapes`, when non-empty (`_PointChannels.shapes`, for
    `Theme.shape_by_category`), draws each row's `PointShape` in place of
    the color square at the same size and position. Labels are appended
    to `text_requests` rather than drawn; only the swatch is drawn here.
    """
    var sc = _Scaled(theme)
    for i in range(len(labels)):
        var row_y = y + i * (sc.legend_swatch_size + sc.legend_row_gap)
        var color = palette[i % len(palette)]
        if len(shapes) > 0:
            var radius = sc.legend_swatch_size // 2
            _fill_shape_aa(
                target,
                x + radius,
                row_y + radius,
                radius,
                shapes[i % len(shapes)],
                color,
            )
        else:
            target.fill_rect(
                x, row_y, sc.legend_swatch_size, sc.legend_swatch_size, color
            )
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


def _draw_continuous_color_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    color_scale: ColorScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """A continuous color legend: a vertical gradient bar
    (`DrawTarget.fill_rect_gradient`) with `color_scale`'s high value at
    the top and low at the bottom, plus two labels (`_format_tick` at
    `theme.y_tick_format`, one decimal place) for the domain max at the
    top and min at the bottom.

    The `LinearGradient` is built from `color_scale.stops` directly. The
    bar runs top to bottom while the scale's offsets run low to high, so
    each stop's gradient offset is `1.0 - stop.offset`; the stops are
    then sorted back into ascending order (see the body's comment).

    Returns the y just below this section (bar height plus one row gap),
    where `_draw_continuous_size_legend` starts when a plot combines
    both.
    """
    var sc = _Scaled(theme)
    var bar_width = sc.continuous_legend_bar_width
    var bar_height = sc.continuous_legend_bar_height
    var gradient = LinearGradient(
        Float64(x), Float64(y), Float64(x), Float64(y + bar_height)
    )

    # Stops are emitted in ascending offset order, which SVG requires (the
    # raster backend doesn't care). SVG's <linearGradient> clamps each
    # <stop>'s offset to be no less than the previous one's, so emitting
    # `1.0 - offset` off an ascending ColorScale (1.0, 0.5, 0.0) collapsed
    # every stop after the first onto 1.0 and the bar rendered as one flat
    # color; the raster path was always correct because `_color_at_t`
    # scans for the bracketing pair regardless of order. Sorted rather
    # than iterated backwards because `ColorScale.add_stop` accepts stops
    # in any order. Insertion sort, since the list is three stops long.
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
            _format_tick(color_scale.domain_max, 1, theme.y_tick_format),
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
            _format_tick(color_scale.domain_min, 1, theme.y_tick_format),
            theme.text_color,
            sc.font_size,
            TextAlign.LEFT,
            theme.font_family,
        )
    )
    return y + bar_height + sc.legend_row_gap


def _draw_continuous_size_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    size_mm: MinMax,
    size_scale: LinearScale,
    x: Int,
    y: Int,
    theme: Theme,
) raises -> Int:
    """A continuous size legend: three circles at the max, midpoint, and min
    of the size domain (evenly spaced values, not radii), each at
    `size_scale`'s radius for that value. Circles are left-aligned on
    their widest possible edge (`x + sc.size_range_max`) so every label
    lines up at the same x.

    Returns the y just below the last circle plus one row gap, for
    consistency with `_draw_continuous_color_legend`; currently the last
    legend section drawn.
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
                _format_tick(v, 1, theme.y_tick_format),
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
                theme.font_family,
            )
        )
        top_y = center_y + radius + sc.legend_row_gap
    return top_y


def _data_extent(data: List[Float64]) raises -> LinearScale:
    """The [min, max] of `data` padded 5% on each side, as a LinearScale
    whose range is a placeholder [0, 1] that render() overwrites once the
    plot area is known. A zero-span column gets a fixed 1.0 padding.
    Spatial axes only; color/size domains use `_min_max` unpadded so a
    legend's extremes are the data's.
    """
    var mm = _min_max(data)
    var span = mm.max - mm.min
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(mm.min - pad, mm.max + pad, 0.0, 1.0)


def _zero_baseline_y_extent(data: List[Float64]) raises -> LinearScale:
    """The y-domain for a mark whose fill/height encodes magnitude from a
    baseline (`Mark.BAR`, `Mark.AREA`, ...): always includes zero. Pads
    only the end that isn't already zero, so zero stays an exact axis
    endpoint whenever every value sits on one side of it.
    """
    var mm = _min_max(data)
    var lo = min(0.0, mm.min)
    var hi = max(0.0, mm.max)
    var span = hi - lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    var padded_lo = lo - pad if lo < 0.0 else lo
    var padded_hi = hi + pad if hi > 0.0 else hi
    return LinearScale(padded_lo, padded_hi, 0.0, 1.0)


def _log_data_extent(data: List[Float64]) raises -> LinearScale:
    """`_data_extent()`'s log10 counterpart for `Plot.scale_y_log()`/
    `scale_x_log()`. Raises if any value isn't strictly positive. The
    domain is computed and padded in log10-space (5% of the log span, or
    a fixed 1.0-decade pad for a zero span), since a log axis's breathing
    room is multiplicative. The returned scale has `is_log=True`; values
    are still passed to `to_pixel()` in real units.
    """
    for v in data:
        if v <= 0.0:
            raise Error(
                "scale_y_log()/scale_x_log(): every value must be > 0 for a"
                " log-scaled axis (log10(0) and log10(negative) are undefined)"
                " -- got "
                + String(v)
            )
    var mm = _min_max(data)
    var log_lo = log10(mm.min)
    var log_hi = log10(mm.max)
    var span = log_hi - log_lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(log_lo - pad, log_hi + pad, 0.0, 1.0, is_log=True)


struct _LabelsFrame(Movable):
    """`_apply_labels`'s result: the outer rect `render()`/`render_svg()`
    hand to `_render_generic`, shrunk to make room for `Plot.labels()`'s
    titles. `_apply_labels` builds no `_TextRequest`s;
    `_label_text_requests` does that after rendering.
    """

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
    """Every `_render_*` function's return value: the axis/tick/legend
    `_TextRequest`s, plus the inner plot rect the mark was laid out in
    (`px0`/`py0`/`px1`/`py1`, with dynamic margins and legend column
    resolved). `_label_text_requests` centers `Plot.labels()`'s titles on
    that rect rather than the outer bounds, so a wide legend or long tick
    labels don't throw a title off-center. Every `_render_*` raises before
    reaching any layout when its own data is empty (`_require_non_empty`,
    #206), so there is no "no data" `_RenderResult` shape to report here.

    `y_scale`/`has_y_scale` expose the real `LinearScale` the mark's
    y-axis used, so the annotation passes (`_draw_annotation_lines`/
    `_draw_annotation_areas`) place values with the same `to_pixel` the
    data went through. `has_y_scale` defaults `False` with an inert
    placeholder scale; only the frames that support annotations pass a
    real one. `x_scale`/`has_x_scale` mirror that for the x-axis, set
    only by `_ContinuousFrame.result()` since a categorical x-axis has no
    numeric domain; `annotate_vline()`/`annotate_point()` therefore
    support only `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER`.
    """

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


def _apply_labels(
    plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _LabelsFrame:
    """Reserve margin space for `Plot.labels()`'s chart/axis titles, given
    the original outer bounds. Called by `_render_into`/
    `_render_svg_into` (and the facet/layer variants) before
    `_render_generic`; the mark-specific code stays unaware titles exist,
    since shrinking the rect up front has the same effect as threading
    title state through every function.

    Only reserves margin. A title's along-axis position depends only on
    this reservation, but its cross-axis centering should track the real
    inner plot rect (dynamic left margin, legend column), which isn't
    known until `_render_generic` returns; `_label_text_requests` builds
    the text afterward using `_RenderResult`'s rect.

    `Mark.ARC` has no axes, so `x_title`/`y_title` raise on an `ARC`
    plot; `title` works for any mark.
    """
    if (
        plot._labels.x_title.byte_length() > 0
        or plot._labels.y_title.byte_length() > 0
    ) and plot._mark == Mark.ARC:
        raise Error(
            "Plot.labels(): x_title/y_title don't apply to Mark.ARC (it"
            " has no x/y axes to caption) -- only title applies to a"
            " pie/donut chart"
        )

    var sc = _Scaled(plot._theme)
    var extra_top = (
        Int(sc.title_font_size)
        + sc.label_gap if plot._labels.title.byte_length()
        > 0 else 0
    )
    extra_top += (
        Int(sc.subtitle_font_size)
        + sc.label_gap if plot._labels.subtitle.byte_length()
        > 0 else 0
    )
    var extra_bottom = (
        Int(sc.axis_title_font_size)
        + sc.label_gap if plot._labels.x_title.byte_length()
        > 0 else 0
    )
    var extra_left = (
        Int(sc.axis_title_font_size)
        + sc.label_gap if plot._labels.y_title.byte_length()
        > 0 else 0
    )

    return _LabelsFrame(
        ox0 + extra_left, oy0 + extra_top, ox1, oy1 - extra_bottom
    )


def _label_text_requests(
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    px0: Int,
    py0: Int,
    px1: Int,
    py1: Int,
) raises -> List[_TextRequest]:
    """Build `Plot.labels()`'s title/subtitle/x_title/y_title
    `_TextRequest`s after `_render_generic` returns. Each title's
    along-axis position (distance from the top/bottom/left edge) is
    relative to the original outer bounds `ox0`..`oy1`; its cross-axis
    centering uses the actual inner plot rect `px0`..`py1` from
    `_RenderResult`.
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
        # Stacks directly below the title's reserved band, which is 0 when
        # there is no title, so a lone subtitle draws at the very top.
        var title_band = (
            Int(sc.title_font_size)
            + sc.label_gap if plot._labels.title.byte_length()
            > 0 else 0
        )
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
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_area()` shaded band directly (a `fill_rect`
    needs no text machinery) and return each one's optional label as a
    `_TextRequest`.

    Called by `_render_into`/`_render_svg_into` right after
    `_render_generic`, before `_draw_annotation_lines`, since areas are
    the bottom-most annotation layer. Uses `result.y_scale`, raising if
    `has_y_scale` is `False`.

    Each band spans the inner plot rect's full width in
    `Theme.annotation_area_color` (translucent, so the mark shows
    through). Its label draws inside the band near its top edge in
    `Theme.annotation_color`. A band partially outside the y-domain draws
    its clipped visible portion; one with zero overlap draws nothing.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.area_y0) == 0:
        return text_requests^
    if not result.has_y_scale:
        raise Error(
            "Plot.annotate_area(): this mark has no continuous y-axis to place"
            " a shaded band"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER and"
            " every mark sharing"
            " _CategoricalFrame"
            " (BAR/LOLLIPOP/WATERFALL/BOX/CANDLESTICK/BULLET/GROUPED_BAR/"
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
        # Clip to the visible plot rect rather than skip outright; a band has
        # real height, so a partial overlap is still meaningful.
        var draw_top = max(band_top, plot_top)
        var draw_bottom = min(band_bottom, plot_bottom)
        if draw_top >= draw_bottom:
            continue
        target.fill_rect(
            result.px0,
            draw_top,
            result.px1 - result.px0,
            draw_bottom - draw_top,
            theme.annotation_area_color,
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


def _draw_annotation_bands[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_band()` filled region with the same
    `fill_path_aa` closed-polygon technique `_draw_area_layer` uses,
    built from `y_upper` left-to-right then `y_lower` right-to-left, and
    return each band's optional label as a `_TextRequest`.

    Called right after `_draw_annotation_areas`, as the other
    translucent-fill layer beneath lines/vlines/points. Needs both
    `result.x_scale` and `result.y_scale`. Raises if a band's `x`/
    `y_lower`/`y_upper` lengths mismatch or any `y_upper[i] < y_lower[i]`.

    No true polygon clip against the inner rect: each vertex's pixel
    position is clamped independently into the rect before the path is
    built. A band mostly in range draws correctly; a vertex clamped on
    one axis draws a straight wall at that boundary rather than a true
    intersection. A band with every vertex clamped to one corner fills a
    zero-area region.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.band_x) == 0:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_band(): this mark has no continuous x/y axes to"
            " place a band against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )

    var sc = _Scaled(theme)
    var px_left = Float64(min(result.px0, result.px1))
    var px_right = Float64(max(result.px0, result.px1))
    var py_top = Float64(min(result.py0, result.py1))
    var py_bottom = Float64(max(result.py0, result.py1))
    for k in range(len(plot._annotations.band_x)):
        var xs = plot._annotations.band_x[k].copy()
        var ys_lower = plot._annotations.band_y_lower[k].copy()
        var ys_upper = plot._annotations.band_y_upper[k].copy()
        if len(xs) != len(ys_lower) or len(xs) != len(ys_upper):
            raise Error(
                "Plot.annotate_band(): x/y_lower/y_upper must be the same"
                " length (got "
                + String(len(xs))
                + ", "
                + String(len(ys_lower))
                + ", and "
                + String(len(ys_upper))
                + ")"
            )
        if len(xs) == 0:
            continue
        var px_upper = List[Float64](capacity=len(xs))
        var py_upper = List[Float64](capacity=len(xs))
        var px_lower = List[Float64](capacity=len(xs))
        var py_lower = List[Float64](capacity=len(xs))
        for i in range(len(xs)):
            if ys_upper[i] < ys_lower[i]:
                raise Error(
                    "Plot.annotate_band(): y_upper must be >= y_lower at every"
                    " index (got y_lower="
                    + String(ys_lower[i])
                    + " and y_upper="
                    + String(ys_upper[i])
                    + " at index "
                    + String(i)
                    + ")"
                )
            var this_px = min(
                max(result.x_scale.to_pixel(xs[i]), px_left), px_right
            )
            px_upper.append(this_px)
            px_lower.append(this_px)
            py_upper.append(
                min(
                    max(result.y_scale.to_pixel(ys_upper[i]), py_top), py_bottom
                )
            )
            py_lower.append(
                min(
                    max(result.y_scale.to_pixel(ys_lower[i]), py_top), py_bottom
                )
            )
        var path = Path()
        path.move_to(px_upper[0], py_upper[0])
        for i in range(1, len(xs)):
            path.line_to(px_upper[i], py_upper[i])
        for i in range(len(xs) - 1, -1, -1):
            path.line_to(px_lower[i], py_lower[i])
        path.close()
        target.fill_path_aa(
            path, theme.annotation_area_color, fill_rule=FillRule.NONZERO
        )

        var label = plot._annotations.band_labels[k]
        if label.byte_length() > 0:
            var mid = len(xs) // 2
            text_requests.append(
                _TextRequest(
                    Int(px_upper[mid]),
                    Int(py_upper[mid]) - sc.label_gap,
                    label,
                    theme.annotation_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )
    return text_requests^


def _draw_annotation_lines[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_line()` reference line directly (a
    horizontal `draw_line_aa` needs no text machinery) and return each
    one's optional label as a `_TextRequest`.

    Called right after `_render_generic` returns, using `result.y_scale`
    so each line lands on the same pixel row the mark's data would;
    raises if `has_y_scale` is `False`.

    Each line spans the inner plot rect's full width in
    `Theme.annotation_color`. Its label right-aligns just above the
    line's right end, at a fixed position with no collision avoidance.

    A `value` outside the mark's padded domain is skipped rather than
    drawn where unclamped extrapolation would put it (up in the title
    band); an out-of-range target is a legitimate reading, not an error.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.line_values) == 0:
        return text_requests^
    if not result.has_y_scale:
        raise Error(
            "Plot.annotate_line(): this mark has no continuous y-axis to place"
            " a reference line"
            " against. Supported today: Mark.POINT/LINE/AREA/EFFECT_SCATTER and"
            " every mark sharing"
            " _CategoricalFrame"
            " (BAR/LOLLIPOP/WATERFALL/BOX/CANDLESTICK/BULLET/GROUPED_BAR/"
            "STACKED_BAR/STREAMGRAPH)"
        )

    var sc = _Scaled(theme)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    for i in range(len(plot._annotations.line_values)):
        var py = _axis_pixel(result.y_scale, plot._annotations.line_values[i])
        if py < py_top or py > py_bottom:
            continue
        target.draw_line_aa(
            result.px0,
            py,
            result.px1,
            py,
            theme.annotation_color,
            width=sc.scale,
        )
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
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """`_draw_annotation_lines`'s mirror image for `Plot.annotate_vline()`:
    a vertical line at an x `value`, using `result.x_scale`/
    `has_x_scale`, spanning the inner rect's full height, skipping an
    out-of-range value the same way. The label is left-aligned just right
    of the line near its top (`px + label_gap`, `py0 + font_size`).
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.vline_values) == 0:
        return text_requests^
    if not result.has_x_scale:
        raise Error(
            "Plot.annotate_vline(): this mark has no continuous x-axis to place"
            " a reference line against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
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
        target.draw_line_aa(
            px, py_top, px, py_bottom, theme.annotation_color, width=sc.scale
        )
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
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw every `Plot.annotate_point()` marker directly and return each
    one's optional label as a `_TextRequest`. Called last among the
    annotation passes so a point draws on top of every other layer. Needs
    both `result.x_scale` and `result.y_scale`. A point outside the
    padded domain on either axis is skipped.

    The marker is a filled circle of `sc.point_radius` in
    `Theme.annotation_color` (canvas has no pin glyph). Its label centers
    just above the marker.
    """
    var text_requests = List[_TextRequest]()
    if len(plot._annotations.point_x) == 0:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_point(): this mark has no continuous x/y axes to"
            " place a point against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
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


def _draw_annotation_best_fit[
    T: DrawTarget
](
    mut target: T, plot: Plot, result: _RenderResult, theme: Theme
) raises -> List[_TextRequest]:
    """Draw `Plot.annotate_best_fit()`'s ordinary-least-squares line and
    return its optional label/equation/R-squared text as `_TextRequest`s.

    The regression is computed here from `plot.x_data`/`plot.y_data`, so
    the fit sees whatever data the plot ends up with regardless of call
    order. Closed-form OLS: `slope = (n*sum_xy - sum_x*sum_y) /
    (n*sum_xx - sum_x^2)`, `intercept = mean_y - slope*mean_x`.

    Needs both `result.x_scale` and `result.y_scale`. Raises with fewer
    than 2 points, or when every x value is identical (the OLS
    denominator is 0).

    Drawn across the mark's full padded x-domain, with each endpoint's y
    clamped into the plot rect so a steep fit doesn't project outside it.
    """
    var text_requests = List[_TextRequest]()
    if not plot._annotations.best_fit:
        return text_requests^
    if not result.has_x_scale or not result.has_y_scale:
        raise Error(
            "Plot.annotate_best_fit(): this mark has no continuous x/y axes to"
            " fit a line against. Supported today:"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER only"
        )
    var n_points = len(plot.x_data)
    if n_points < 2:
        raise Error(
            "Plot.annotate_best_fit(): needs at least 2 points to fit a line"
            " through (got "
            + String(n_points)
            + ")"
        )

    var n = Float64(n_points)
    var sum_x = 0.0
    var sum_y = 0.0
    var sum_xy = 0.0
    var sum_xx = 0.0
    for i in range(n_points):
        sum_x += plot.x_data[i]
        sum_y += plot.y_data[i]
        sum_xy += plot.x_data[i] * plot.y_data[i]
        sum_xx += plot.x_data[i] * plot.x_data[i]
    var denom = n * sum_xx - sum_x * sum_x
    if denom == 0.0:
        raise Error(
            "Plot.annotate_best_fit(): every x value is identical -- there is"
            " no honest non-vertical line to fit through a vertical scatter"
        )
    var slope = (n * sum_xy - sum_x * sum_y) / denom
    var mean_x = sum_x / n
    var mean_y = sum_y / n
    var intercept = mean_y - slope * mean_x

    var sc = _Scaled(theme)
    var py_top = min(result.py0, result.py1)
    var py_bottom = max(result.py0, result.py1)
    var x_left = result.x_scale.domain_min
    var x_right = result.x_scale.domain_max
    var px_left = _axis_pixel(result.x_scale, x_left)
    var px_right = _axis_pixel(result.x_scale, x_right)
    var py_left = min(
        max(_axis_pixel(result.y_scale, slope * x_left + intercept), py_top),
        py_bottom,
    )
    var py_right = min(
        max(_axis_pixel(result.y_scale, slope * x_right + intercept), py_top),
        py_bottom,
    )
    target.draw_line_aa(
        px_left,
        py_left,
        px_right,
        py_right,
        theme.annotation_color,
        width=sc.scale,
    )

    var text_x = max(result.px0, result.px1) - sc.label_gap
    var text_y = py_top + Int(sc.font_size)
    if plot._annotations.best_fit_label.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                text_x,
                text_y,
                plot._annotations.best_fit_label,
                theme.annotation_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )
        text_y += Int(sc.font_size) + sc.label_gap
    if plot._annotations.best_fit_show_equation:
        var slope_str = _format_fixed(slope, 3)
        var eq: String
        if intercept >= 0.0:
            eq = "y = " + slope_str + "x + " + _format_fixed(intercept, 3)
        else:
            eq = "y = " + slope_str + "x - " + _format_fixed(-intercept, 3)
        text_requests.append(
            _TextRequest(
                text_x,
                text_y,
                eq,
                theme.annotation_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )
        text_y += Int(sc.font_size) + sc.label_gap
    if plot._annotations.best_fit_show_r_squared:
        # R-squared = 1 - SS_res/SS_tot. SS_tot == 0.0 (every y identical) is
        # defined as exactly 1.0 rather than 0/0.
        var ss_res = 0.0
        var ss_tot = 0.0
        for i in range(n_points):
            var predicted = slope * plot.x_data[i] + intercept
            var residual = plot.y_data[i] - predicted
            ss_res += residual * residual
            var deviation = plot.y_data[i] - mean_y
            ss_tot += deviation * deviation
        var r_squared = 1.0 if ss_tot == 0.0 else 1.0 - ss_res / ss_tot
        text_requests.append(
            _TextRequest(
                text_x,
                text_y,
                "R² = " + _format_fixed(r_squared, 3),
                theme.annotation_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )
    return text_requests^


def _tooltip_label(category: String, value: Float64) -> String:
    """One datum's hover text: `"Group A: 42"`, formatted with
    `_label_decimals` like `Theme.show_data_labels`. No escaping here;
    canvas_mojo's `begin_annotated_group` escapes the title for XML
    itself.
    """
    return category + ": " + _format_fixed(value, _label_decimals(value))


def _series_tooltip_label(
    category: String, series: String, value: Float64
) -> String:
    """A grouped/stacked datum's hover text: `"Group A / Q1: 42"`. Both
    names, since one bar per (category, series) pair needs both to be
    identified.
    """
    return (
        category
        + " / "
        + series
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )


def _point_tooltip_label(plot: Plot, i: Int) -> String:
    """One scatter point's hover text: the row's `encode(labels=...)` entry
    when it has one, otherwise its coordinates, `"3.5, 12"`.
    """
    if len(plot.point_labels) > 0 and plot.point_labels[i] != "":
        return plot.point_labels[i]
    return (
        _format_fixed(plot.x_data[i], _label_decimals(plot.x_data[i]))
        + ", "
        + _format_fixed(plot.y_data[i], _label_decimals(plot.y_data[i]))
    )


def _replay_text_requests(
    mut canvas: Canvas, requests: List[_TextRequest], mut cache: FontCache
) raises:
    """Draw every `_TextRequest` in `requests` into `canvas` via
    `canvas.text.draw_text`, the raster half of replaying the deferred
    labels. Shared by every raster entry point.
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


def _replay_text_requests_svg(
    mut svg: SvgCanvas, requests: List[_TextRequest]
) raises:
    """`_replay_text_requests`' counterpart for `SvgCanvas`, via
    `SvgCanvas.draw_text`. A separate function because `DrawTarget` has
    no `draw_text` to dispatch through.
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
    """Append a copy of every `_TextRequest` in `src` onto `dst`; used by
    the facet/layer renders to gather per-cell/per-layer labels into one
    list.
    """
    for req in src:
        dst.append(req.copy())


def _require_positive_supersample(factor: Int, context: String) raises:
    """Raise unless `factor >= 1`, naming the caller (`context`). Guards
    `Theme.raster_supersample` at each of its three read sites
    (`render()`/`render_facets()`/`render_layers()`) rather than in
    `Theme`'s own constructor, matching `line_smoothing`'s deferred-to-
    render-time validation (`_check_line_smoothing`, elsewhere in this
    file) -- a `Theme` value isn't wrong to construct, only to render
    with (#231).
    """
    if factor < 1:
        raise Error(
            context
            + "(): Theme.raster_supersample must be >= 1 (got "
            + String(factor)
            + ")"
        )


def _scaled_copy(plots: List[Plot], factor: Int) -> List[Plot]:
    """A copy of `plots` with every `Plot`'s own `_theme.scale` multiplied
    by `factor`: the list version of the temporary scale bump `render()`
    does for supersampling, so every plot in a facet grid/layer stack
    scales its own mark styling. Returns a new list rather than mutating
    `plots` in place (#208), so `render_facets()`/`render_layers()` can
    take `plots` by borrow -- a temporary list literal binds to a borrow
    but not to `mut`.
    """
    var out = List[Plot](capacity=len(plots))
    for i in range(len(plots)):
        var scaled = plots[i].copy()
        scaled._theme.scale = scaled._theme.scale * Float64(factor)
        out.append(scaled^)
    return out^


def render(plot: Plot) raises -> Canvas:
    """Render `plot` into a fresh `Canvas` sized `plot.width` x `plot.height`
    and return it, supersampled by `plot._theme.raster_supersample`
    (default 3): a copy of `plot` has its `_theme.scale` bumped by that
    factor, `_render_into` draws into a scratch canvas that many times
    larger from that copy, and `downsample` shrinks the result.

    `plot` is a plain borrow (#208): copying instead of mutating in
    place means `render(scatter(x, y))` and `save(scatter(x, y), path)`
    both compile inline, with no need to bind a temporary to a variable
    first.
    """
    var factor = plot._theme.raster_supersample
    _require_positive_supersample(factor, "render")
    var scaled = plot.copy()
    scaled._theme.scale = scaled._theme.scale * Float64(factor)
    var scratch = Canvas(
        plot.width * factor, plot.height * factor, scaled._theme.background
    )
    _render_into(scratch, scaled)
    return downsample(scratch, factor)


def _render_into(
    mut canvas: Canvas,
    plot: Plot,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
) raises:
    """Render `plot` into `canvas` within the outer bounds (background, then
    the axis frame and mark, then annotations and text). `ox1`/`oy1`
    default to -1, meaning the canvas's width/height; every current
    caller renders into the whole canvas, but the bounds stay generic
    since `_render_generic` is.

    Fills the whole original rect with `theme.background` (the only
    background fill on this path; the mark-specific renders fill
    nothing), reserves title margins via `_apply_labels`, hands the
    shrunk rect to `_render_generic`, builds the title requests via
    `_label_text_requests` from the inner rect it returned, runs the
    annotation passes, then draws every `_TextRequest` via
    `canvas.text.draw_text`.

    Scales only by `plot._theme.scale` as given; `render()` applies
    `Theme.raster_supersample` by bumping that value on a copy before
    this call. Hand-verified pixel tests go through `render()` and so see
    supersampled output, exact for any solid-color interior point.
    """
    var cx1 = ox1 if ox1 >= 0 else canvas.width
    var cy1 = oy1 if oy1 >= 0 else canvas.height
    canvas.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plot._theme.background)
    var frame = _apply_labels(plot, ox0, oy0, cx1, cy1)
    var result = _render_generic(
        canvas, plot, frame.ox0, frame.oy0, frame.ox1, frame.oy1
    )
    var label_requests = _label_text_requests(
        plot, ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    var area_annotation_requests = _draw_annotation_areas(
        canvas, plot, result, plot._theme
    )
    var band_annotation_requests = _draw_annotation_bands(
        canvas, plot, result, plot._theme
    )
    var vline_annotation_requests = _draw_annotation_vlines(
        canvas, plot, result, plot._theme
    )
    var annotation_requests = _draw_annotation_lines(
        canvas, plot, result, plot._theme
    )
    var point_annotation_requests = _draw_annotation_points(
        canvas, plot, result, plot._theme
    )
    var best_fit_annotation_requests = _draw_annotation_best_fit(
        canvas, plot, result, plot._theme
    )
    # One FontCache shared by every label this render draws; draw_text
    # otherwise resolves its font from scratch (twice, since it measures
    # then renders).
    var text_cache = FontCache()
    _replay_text_requests(canvas, label_requests, text_cache)
    _replay_text_requests(canvas, area_annotation_requests, text_cache)
    _replay_text_requests(canvas, band_annotation_requests, text_cache)
    _replay_text_requests(canvas, vline_annotation_requests, text_cache)
    _replay_text_requests(canvas, annotation_requests, text_cache)
    _replay_text_requests(canvas, point_annotation_requests, text_cache)
    _replay_text_requests(canvas, best_fit_annotation_requests, text_cache)
    _replay_text_requests(canvas, result.text_requests, text_cache)


def render_svg(plot: Plot) raises -> SvgCanvas:
    """Render `plot` into a fresh `SvgCanvas` sized `plot.width` x
    `plot.height` and return it; `render()`'s vector counterpart,
    wrapping `_render_svg_into`.
    """
    var svg = SvgCanvas(plot.width, plot.height)
    _render_svg_into(svg, plot)
    return svg^


def _render_svg_into(
    mut svg: SvgCanvas,
    plot: Plot,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
) raises:
    """`_render_into`'s counterpart for `SvgCanvas`: same bounds resolution,
    `_apply_labels`/`_render_generic` core, and annotation passes, with
    the `_TextRequest`s drawn via `SvgCanvas.draw_text`. `render_svg()`
    is its only caller.
    """
    var cx1 = ox1 if ox1 >= 0 else svg.width
    var cy1 = oy1 if oy1 >= 0 else svg.height
    svg.fill_rect(ox0, oy0, cx1 - ox0, cy1 - oy0, plot._theme.background)
    var frame = _apply_labels(plot, ox0, oy0, cx1, cy1)
    var result = _render_generic(
        svg, plot, frame.ox0, frame.oy0, frame.ox1, frame.oy1
    )
    var label_requests = _label_text_requests(
        plot, ox0, oy0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    var area_annotation_requests = _draw_annotation_areas(
        svg, plot, result, plot._theme
    )
    var band_annotation_requests = _draw_annotation_bands(
        svg, plot, result, plot._theme
    )
    var vline_annotation_requests = _draw_annotation_vlines(
        svg, plot, result, plot._theme
    )
    var annotation_requests = _draw_annotation_lines(
        svg, plot, result, plot._theme
    )
    var point_annotation_requests = _draw_annotation_points(
        svg, plot, result, plot._theme
    )
    var best_fit_annotation_requests = _draw_annotation_best_fit(
        svg, plot, result, plot._theme
    )
    _replay_text_requests_svg(svg, label_requests)
    _replay_text_requests_svg(svg, area_annotation_requests)
    _replay_text_requests_svg(svg, band_annotation_requests)
    _replay_text_requests_svg(svg, vline_annotation_requests)
    _replay_text_requests_svg(svg, annotation_requests)
    _replay_text_requests_svg(svg, point_annotation_requests)
    _replay_text_requests_svg(svg, best_fit_annotation_requests)
    _replay_text_requests_svg(svg, result.text_requests)


def _resolve_output_format(
    theme_format: OutputFormat, path: String
) -> OutputFormat:
    """The format `save()`/`save_layers()`/`save_facets()` use: `path`'s
    extension when it's `.svg`/`.png`/`.bmp` (case-insensitive),
    otherwise `theme_format` (`Theme.output_format`).
    """
    var lower = path.lower()
    if lower.endswith(".svg"):
        return OutputFormat.SVG
    elif lower.endswith(".png"):
        return OutputFormat.PNG
    elif lower.endswith(".bmp"):
        return OutputFormat.BMP
    return theme_format


def _resolve_description(labels: _LabelData) -> String:
    """`labels.description`, or `labels.subtitle` when that's empty (#212)
    -- the `<desc>` `_svg_output_string()` passes to
    `accessible_svg_string()`, so a title-and-subtitle chart gets a
    reasonable screen-reader description with no extra call needed.
    """
    return (
        labels.description if labels.description.byte_length()
        > 0 else labels.subtitle
    )


def _svg_output_string(svg: SvgCanvas, labels: _LabelData) raises -> String:
    """What `save()`/`save_layers()`/`save_facets()` write for SVG output
    (#212): `accessible_svg_string()`'s markup when `labels.title` is set
    (`_resolve_description()`'s `<desc>`), or plain `svg.to_string()`
    otherwise. A pure string decision, factored out of the file-writing
    `save*()` functions so it's directly testable with no disk I/O.
    """
    if labels.title.byte_length() > 0:
        return accessible_svg_string(
            svg, labels.title, _resolve_description(labels)
        )
    return svg.to_string()


def save(plot: Plot, path: String) raises:
    """Render `plot` and write it to `path` in one call (#112). The format
    comes from `_resolve_output_format()` (the path's extension, falling
    back to `plot._theme.output_format`); `PNG`/`BMP` both go through
    `render()` and differ only in the writer.

    `plot` is a plain borrow (#208): `save(scatter(x, y), path)` compiles
    inline, with no need to bind the temporary to a variable first. Call
    `render()`/`render_svg()` directly to get the `Canvas`/`SvgCanvas`
    itself. `save_layers()`/`save_facets()` are the `List[Plot]`
    counterparts; the `save(canvas: Canvas, path)` overload below writes
    an already-rendered `Canvas`.

    SVG output with a non-empty `.labels(title=...)` writes accessible
    markup automatically (#212), via `_svg_output_string()`/
    `accessible_svg_string()` with that title and `_resolve_description()`'s
    `<desc>` -- the same markup `write_accessible_svg()` adds explicitly,
    for callers who don't need a title that differs from the visible one.
    An untitled plot's SVG is unaffected.
    """
    var format = _resolve_output_format(plot._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        f.write(_svg_output_string(render_svg(plot), plot._labels))
        f.close()
    elif format == OutputFormat.PNG:
        write_png(render(plot), path)
    else:
        write_bmp(render(plot), path)


def save(canvas: Canvas, path: String) raises:
    """Write an already-rendered `Canvas` to `path`: BMP for a `.bmp`
    extension, PNG otherwise. A `.svg` path raises, since raster pixels
    can't become vector markup.
    """
    var lower = path.lower()
    if lower.endswith(".svg"):
        raise Error(
            "save(): a Canvas is already-rendered raster pixels -- write_svg"
            " can't produce real vector markup from it. Build the chart as a"
            " Plot and call save(plot, path) instead."
        )
    elif lower.endswith(".bmp"):
        write_bmp(canvas, path)
    else:
        write_png(canvas, path)


def save_layers(plots: List[Plot], path: String) raises:
    """`save()`'s `render_layers()`/`render_layers_svg()` counterpart. The
    format comes from `plots[0]`'s theme when the path's extension
    doesn't decide it. Raises on an empty `plots`.

    SVG output writes accessible markup automatically (#212) from
    `plots[0]`'s `.labels()`, the same one whose title/subtitle
    `render_layers()` itself draws (only the first layer's labels apply
    to a layered chart); see `save()`'s own docstring.
    """
    if len(plots) == 0:
        raise Error("save_layers(): plots must not be empty")
    var format = _resolve_output_format(plots[0]._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        f.write(_svg_output_string(render_layers_svg(plots), plots[0]._labels))
        f.close()
    elif format == OutputFormat.PNG:
        write_png(render_layers(plots), path)
    else:
        write_bmp(render_layers(plots), path)


def save_facets(
    plots: List[Plot], cols: Int, path: String, shared_y_scale: Bool = False
) raises:
    """`save()`'s `render_facets()`/`render_facets_svg()` counterpart; see
    `save_layers()` for the shared format/empty behavior.

    Each entry in `plots` is an independent `Plot` (its own data, labels,
    theme, mark), laid out into a grid of `cols` columns;
    `_require_uniform_size` requires every plot to have the same
    `.size()`. There is no `facet_by()`; build each cell's `Plot` and
    pass the list. `shared_y_scale` makes every cell share one y-domain
    (see `_render_facets_generic` for its `Mark.POINT`/`LINE`/
    `EFFECT_SCATTER`-only scope).

    See the Cookbook's "Facets" and "Shared Facet Scale" recipes
    (docs/src/cookbook_recipes/).

    SVG output writes accessible markup automatically (#212) from
    `plots[0]`'s `.labels()`, as a best-effort document title for the
    whole grid -- each cell can carry its own visible title, but the
    `<svg>` root needs exactly one `aria-label`/`<title>`. Give `plots[0]`
    a title that describes the grid as a whole (or call
    `write_accessible_svg()` directly) when that matters.
    """
    if len(plots) == 0:
        raise Error("save_facets(): plots must not be empty")
    var format = _resolve_output_format(plots[0]._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        f.write(
            _svg_output_string(
                render_facets_svg(plots, cols, shared_y_scale), plots[0]._labels
            )
        )
        f.close()
    elif format == OutputFormat.PNG:
        write_png(render_facets(plots, cols, shared_y_scale), path)
    else:
        write_bmp(render_facets(plots, cols, shared_y_scale), path)


def accessible_svg_string(
    svg: SvgCanvas, title: String, description: String = ""
) raises -> String:
    """`svg.to_string()` with SVG accessibility markup added: `role="img"`
    and `aria-label` on the root `<svg>` element, plus a `<title>` (and a
    `<desc>` when `description` is non-empty) as its first child
    elements, which is what screen readers that support SVG look for.

    `title` is required; the same string passed to `.labels(title=...)`
    is usually right. A post-processing wrapper around `to_string()`
    using canvas_mojo's `_escape_xml_text`/`_escape_xml_attr`, relying on
    `<svg ...>` being the literal start of the output so its first `>` is
    the opening tag's end; if `SvgCanvas.to_string` changes shape, this
    needs revisiting.

    This only helps where the SVG's accessible tree is walked: inline
    `<svg>` markup, a standalone `.svg`, or an `<object>`/`<iframe>`
    embed. A plain `<img src="chart.svg">` (how the docs site embeds
    examples) treats the SVG as an opaque image, and a screen reader
    reads the `<img>`'s `alt` text instead.
    """
    var s = svg.to_string()
    var tag_end = s.find(">")
    if tag_end == -1:
        raise Error(
            "accessible_svg_string: svg.to_string() produced no root element to"
            " attach accessibility markup to"
        )
    var opening_tag = String(s[byte=0:tag_end])
    var rest = String(s[byte=tag_end:])

    var escaped_title_attr = _escape_xml_attr(title)
    var accessible_tag = (
        opening_tag + ' role="img" aria-label="' + escaped_title_attr + '"'
    )

    var children = "<title>" + _escape_xml_text(title) + "</title>\n"
    if description.byte_length() > 0:
        children += "<desc>" + _escape_xml_text(description) + "</desc>\n"

    return (
        accessible_tag
        + String(rest[byte=0:1])
        + children
        + String(rest[byte=1:])
    )


def write_accessible_svg(
    svg: SvgCanvas, path: String, title: String, description: String = ""
) raises:
    """`accessible_svg_string()` written to `path`. See the Cookbook's "SVG
    Accessibility" recipe
    (docs/src/cookbook_recipes/svg_accessibility.mojo).
    """
    var f = open(path, "w")
    f.write(accessible_svg_string(svg, title, description))
    f.close()


struct _PointChannels(Movable):
    """Every derived value `Mark.POINT`'s optional data-driven channels
    (categorical color, continuous color, continuous size; see
    `Plot.encode`) need: which are encoded, the categorical domain and
    palette a discrete color column indexes into, and the `ColorScale`/
    `LinearScale` a continuous column maps through. Built
    unconditionally, with placeholder scales when a channel isn't
    encoded.

    A struct because these are needed at two points in one render:
    before the plot rect is finalized, to size the legend column
    (`_legend_reserve_for`), and after, to color/size each point and draw
    the legend (`_draw_point_layer`). Computing them once keeps the two
    consistent.
    """

    var has_color: Bool
    var has_color_categories: Bool
    var has_size: Bool
    # The categorical color column's domain and each row's index into it,
    # resolved once (`_categorical_indices`). Held as the whole
    # `_CategoricalIndex` since Mojo won't let a returned struct's fields
    # be moved out individually. Both halves are empty when the channel
    # isn't encoded.
    var cat: _CategoricalIndex
    # One color per `cat.domain` entry, sized to the domain exactly with
    # `Plot.encode()`'s `color_map` overrides folded in, so readers index
    # it directly by domain position.
    var palette: List[Color]
    # One shape per `cat.domain` entry, same indexing as `palette`; empty
    # unless both `has_color_categories` and `Theme.shape_by_category` are
    # true. `has_shapes` names that combination.
    var has_shapes: Bool
    var shapes: List[PointShape]
    var color_scale: ColorScale
    var size_mm: MinMax
    var size_scale: LinearScale

    def __init__(out self, plot: Plot, sc: _Scaled) raises:
        self.has_color = len(plot.color_data) > 0
        self.has_color_categories = len(plot.color_categories) > 0
        self.has_size = len(plot.size_data) > 0
        # Branch rather than resolving an empty column: `plot` is borrowed, so
        # a ternary would need a full copy of `color_categories`.
        if self.has_color_categories:
            self.cat = _categorical_indices(plot.color_categories)
        else:
            self.cat = _CategoricalIndex(List[String](), List[Int]())
        self.palette = List[Color]()
        if self.has_color_categories:
            var default_palette = default_categorical_palette()
            for i in range(len(self.cat.domain)):
                var name = self.cat.domain[i]
                if name in plot.color_map:
                    self.palette.append(plot.color_map[name])
                else:
                    self.palette.append(
                        default_palette[i % len(default_palette)]
                    )
        self.has_shapes = (
            self.has_color_categories and plot._theme.shape_by_category
        )
        self.shapes = List[PointShape]()
        if self.has_shapes:
            var default_shapes = default_marker_shapes()
            for i in range(len(self.cat.domain)):
                self.shapes.append(default_shapes[i % len(default_shapes)])
        var color_mm = _min_max(plot.color_data) if self.has_color else MinMax(
            0.0, 1.0
        )
        self.color_scale = ColorScale.from_theme(
            plot._theme, color_mm.min, color_mm.max
        )
        self.size_mm = _min_max(plot.size_data) if self.has_size else MinMax(
            0.0, 1.0
        )
        self.size_scale = LinearScale(
            self.size_mm.min,
            self.size_mm.max,
            sc.size_range_min,
            sc.size_range_max,
        )


def _require_non_empty(count: Int, context: String) raises:
    """Raise when a mark's own data is completely empty (`count == 0`),
    naming the encode method or mark that populated it. Every `_render_*`
    function used to silently return a blank `_RenderResult` (no axes, no
    title, no signal that anything was wrong) for an all-empty `Plot`
    (#206); this is called instead, since a blank image is the hardest
    failure to diagnose and the common cause (a filter upstream produced
    zero rows) is exactly the case where a loud failure saves the most
    time. Called either from `encode_*()` itself (immediately, for the
    handful of methods that already validate eagerly) or from the
    render-time shared validators/`_render_*` functions (deferred, like
    most other length checks in this package).
    """
    if count == 0:
        raise Error(
            context + ": there is no data to draw (every column is empty)"
        )


def _validate_categorical_encoding(plot: Plot) raises:
    """`Plot.encode_categorical()`'s length check plus its empty-data check
    (`_require_non_empty`, #206), shared by every mark reading a
    category/value pair. Also validates `y_err`/`y_err_lower`/`y_err_upper`
    (#216) when set, mirroring `_validate_continuous_encoding`'s rules for
    `encode()`'s same three channels but against `x_categories`' length and
    restricted to `Mark.BAR` -- the only categorical mark drawing them today.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_categorical(): x and y must have the same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )
    _require_non_empty(len(plot.x_categories), "Plot.encode_categorical()")

    var has_y_err = len(plot.y_err_data) > 0
    var has_y_err_lower = len(plot.y_err_lower_data) > 0
    var has_y_err_upper = len(plot.y_err_upper_data) > 0
    if not (has_y_err or has_y_err_lower or has_y_err_upper):
        return

    if has_y_err_lower != has_y_err_upper:
        raise Error(
            "Plot.encode_categorical(): y_err_lower and y_err_upper must be"
            " given together (got only one)"
        )
    if (has_y_err_lower or has_y_err_upper) and has_y_err:
        raise Error(
            "Plot.encode_categorical(): y_err and y_err_lower/y_err_upper are"
            " mutually exclusive -- pass one or the other, not both"
        )
    if not (plot._mark == Mark.BAR):
        raise Error(
            "Plot.encode_categorical(): y_err/y_err_lower/y_err_upper is only"
            " supported for Mark.BAR today"
        )
    if has_y_err and len(plot.y_err_data) != len(plot.x_categories):
        raise Error(
            "Plot.encode_categorical(): y_err must be the same length as"
            " x/y (got "
            + String(len(plot.y_err_data))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )
    if has_y_err:
        for v in plot.y_err_data:
            if v < 0.0:
                raise Error(
                    "Plot.encode_categorical(): y_err values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    if has_y_err_lower and len(plot.y_err_lower_data) != len(plot.x_categories):
        raise Error(
            "Plot.encode_categorical(): y_err_lower must be the same length"
            " as x/y (got "
            + String(len(plot.y_err_lower_data))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )
    if has_y_err_upper and len(plot.y_err_upper_data) != len(plot.x_categories):
        raise Error(
            "Plot.encode_categorical(): y_err_upper must be the same length"
            " as x/y (got "
            + String(len(plot.y_err_upper_data))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )
    if has_y_err_lower:
        for v in plot.y_err_lower_data:
            if v < 0.0:
                raise Error(
                    "Plot.encode_categorical(): y_err_lower values must be"
                    " >= 0 (got "
                    + String(v)
                    + ")"
                )
    if has_y_err_upper:
        for v in plot.y_err_upper_data:
            if v < 0.0:
                raise Error(
                    "Plot.encode_categorical(): y_err_upper values must be"
                    " >= 0 (got "
                    + String(v)
                    + ")"
                )


def _require_non_negative(values: List[Float64], mark_name: String) raises:
    """Every value non-negative, or raise naming `mark_name`; a negative
    value has no width/radius/area for the marks that call this.
    """
    for v in values:
        if v < 0.0:
            raise Error(
                "Plot: "
                + mark_name
                + " values must be non-negative (got "
                + String(v)
                + ")"
            )


def _require_some_positive(
    values: List[Float64], mark_name: String
) raises -> Float64:
    """The largest of `values`, having checked at least one is strictly
    positive; for the marks whose geometry divides by the maximum
    (`value / max`), where all-zero input has no layout. Returns the
    maximum since every caller needs it as the divisor.
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
    """Every check `Plot.encode()`'s channels need before a continuous-axis
    render starts, shared by `_render_generic` and
    `_render_layers_generic`. `context` prefixes each message
    (`"Plot.encode()"` or `"render_layers(): layer 2"`). The `Mark.POINT`/
    `LINE`/`AREA` allow-list `render_layers()` enforces is specific to
    layering and stays at its call site.
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
        plot._mark == Mark.POINT
        or plot._mark == Mark.SINGLE_AXIS
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": color/size encoding is only supported for"
            " Mark.POINT/SINGLE_AXIS/EFFECT_SCATTER today"
        )
    var has_y_err = len(plot.y_err_data) > 0
    if has_y_err and len(plot.y_err_data) != len(plot.x_data):
        raise Error(
            context
            + ": y_err must be the same length as x/y (got "
            + String(len(plot.y_err_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_y_err:
        for v in plot.y_err_data:
            if v < 0.0:
                raise Error(
                    context
                    + ": y_err values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    # No Mark.SINGLE_AXIS here: a single-axis plot has no y-domain for an
    # error bar. Mark.LINE is included, unlike color/size, since a
    # per-point confidence whisker on a line is common (see
    # _draw_line_layer).
    if has_y_err and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": y_err is only supported for Mark.POINT/LINE/EFFECT_SCATTER"
            " today"
        )

    var has_y_err_lower = len(plot.y_err_lower_data) > 0
    var has_y_err_upper = len(plot.y_err_upper_data) > 0
    if has_y_err_lower != has_y_err_upper:
        raise Error(
            context
            + ": y_err_lower and y_err_upper must be given together (got only"
            " one)"
        )
    if (has_y_err_lower or has_y_err_upper) and has_y_err:
        raise Error(
            context
            + ": y_err and y_err_lower/y_err_upper are mutually exclusive --"
            " pass one or the other, not both"
        )
    if has_y_err_lower and len(plot.y_err_lower_data) != len(plot.x_data):
        raise Error(
            context
            + ": y_err_lower must be the same length as x/y (got "
            + String(len(plot.y_err_lower_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_y_err_upper and len(plot.y_err_upper_data) != len(plot.x_data):
        raise Error(
            context
            + ": y_err_upper must be the same length as x/y (got "
            + String(len(plot.y_err_upper_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_y_err_lower:
        for v in plot.y_err_lower_data:
            if v < 0.0:
                raise Error(
                    context
                    + ": y_err_lower values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    if has_y_err_upper:
        for v in plot.y_err_upper_data:
            if v < 0.0:
                raise Error(
                    context
                    + ": y_err_upper values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    if (has_y_err_lower or has_y_err_upper) and not (
        plot._mark == Mark.POINT or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": y_err_lower/y_err_upper are only supported for"
            " Mark.POINT/EFFECT_SCATTER today"
        )

    if len(plot.color_map) > 0 and not has_color_categories:
        raise Error(
            context
            + ": color_map is only meaningful alongside color_categories --"
            " got a"
            " color_map with color_categories empty"
        )

    var has_labels = len(plot.point_labels) > 0
    if has_labels and len(plot.point_labels) != len(plot.x_data):
        raise Error(
            context
            + ": labels must be the same length as x/y (got "
            + String(len(plot.point_labels))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_labels and not (
        plot._mark == Mark.POINT or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": labels is only supported for Mark.POINT/EFFECT_SCATTER today"
        )


def _validate_log_scale_annotations(plot: Plot) raises:
    """Every `annotate_line()`/`annotate_area()`/`annotate_vline()`/
    `annotate_point()` value on a log-scaled axis must be strictly
    positive, the same requirement `_log_data_extent()` enforces for the
    data, since annotations go through the same `to_pixel()`. Checked up
    front here because `to_pixel()` isn't `raises`. A no-op when neither
    axis is log-scaled.
    """
    if plot._y_log:
        for v in plot._annotations.line_values:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_line(): value must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.area_y0:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_area(): y0 must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.area_y1:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_area(): y1 must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.point_y:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_point(): y must be > 0 when"
                    " Plot.scale_y_log() is set (got "
                    + String(v)
                    + ")"
                )
    if plot._x_log:
        for v in plot._annotations.vline_values:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_vline(): value must be > 0 when"
                    " Plot.scale_x_log() is set (got "
                    + String(v)
                    + ")"
                )
        for v in plot._annotations.point_x:
            if v <= 0.0:
                raise Error(
                    "Plot.annotate_point(): x must be > 0 when"
                    " Plot.scale_x_log() is set (got "
                    + String(v)
                    + ")"
                )


def _validate_domain_override(
    override: _DomainOverride, is_log: Bool, context: String
) raises:
    """`Plot.scale_x_domain()`/`scale_y_domain()`'s (#209) own value
    checks: `min < max` always, and (mirroring `_log_data_extent()`'s
    positivity requirement) `min > 0` when the matching axis is
    log-scaled. A no-op when `override.has` is `False`.
    """
    if not override.has:
        return
    if override.min >= override.max:
        raise Error(
            context
            + "(): min must be less than max (got min="
            + String(override.min)
            + ", max="
            + String(override.max)
            + ")"
        )
    if is_log and override.min <= 0.0:
        raise Error(
            context
            + "(): min must be > 0 for a log-scaled axis (log10(0) and"
            " log10(negative) are undefined) -- got "
            + String(override.min)
        )


def _domain_override_scale(
    override: _DomainOverride, is_log: Bool
) -> LinearScale:
    """`override` as a `LinearScale` with a `[0, 1]` placeholder range
    (the caller's frame-building step resolves the real pixel range, same
    as `_data_extent()`'s own return), in log10-space when `is_log` --
    already validated positive by `_validate_domain_override()`.
    """
    if is_log:
        return LinearScale(
            log10(override.min), log10(override.max), 0.0, 1.0, is_log=True
        )
    return LinearScale(override.min, override.max, 0.0, 1.0)


def _check_line_smoothing(theme: Theme) raises:
    """`Theme.line_smoothing`'s `[0.0, 1.0]` range check. Called by
    `_draw_line_layer`/`_draw_area_layer`, so it covers the layered
    render path too.
    """
    if theme.line_smoothing < 0.0 or theme.line_smoothing > 1.0:
        raise Error(
            "Theme.line_smoothing must be in [0.0, 1.0] (got "
            + String(theme.line_smoothing)
            + ")"
        )


def _legend_reserve_for(
    plot: Plot, ch: _PointChannels, sc: _Scaled
) raises -> Int:
    """How much width `plot`'s legend column needs, or `0` when it has no
    legend (`Theme.show_legend` off, not a point mark, or no data-driven
    channel). A plot combining continuous color and size stacks both
    sections vertically in one column, so the width is the larger of the
    two, not the sum. Called before the plot rect is finalized. Has a
    `cache=` overload for the same reason `_max_label_width` does.
    """
    var cache = FontCache()
    return _legend_reserve_for(plot, ch, sc, cache=cache)


def _legend_reserve_for(
    plot: Plot, ch: _PointChannels, sc: _Scaled, *, mut cache: FontCache
) raises -> Int:
    """`_legend_reserve_for` measuring through `cache`; see the overload
    above.
    """
    if not plot._theme.show_legend:
        return 0
    if not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.SINGLE_AXIS
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        return 0
    if not (ch.has_color_categories or ch.has_color or ch.has_size):
        return 0

    var reserve = 0
    if ch.has_color_categories:
        reserve = max(
            reserve,
            _dynamic_legend_width(
                ch.cat.domain, sc.legend_swatch_size, sc, cache=cache
            ),
        )
    elif ch.has_color:
        var color_labels = List[String]()
        color_labels.append(
            _format_tick(
                ch.color_scale.domain_max, 1, plot._theme.y_tick_format
            )
        )
        color_labels.append(
            _format_tick(
                ch.color_scale.domain_min, 1, plot._theme.y_tick_format
            )
        )
        reserve = max(
            reserve,
            _dynamic_legend_width(
                color_labels, sc.continuous_legend_bar_width, sc, cache=cache
            ),
        )
    if ch.has_size:
        var size_labels = List[String]()
        size_labels.append(
            _format_tick(ch.size_mm.max, 1, plot._theme.y_tick_format)
        )
        size_labels.append(
            _format_tick(
                (ch.size_mm.min + ch.size_mm.max) / 2.0,
                1,
                plot._theme.y_tick_format,
            )
        )
        size_labels.append(
            _format_tick(ch.size_mm.min, 1, plot._theme.y_tick_format)
        )
        var circle_content_width = 2 * _round_to_int(sc.size_range_max)
        reserve = max(
            reserve,
            _dynamic_legend_width(
                size_labels, circle_content_width, sc, cache=cache
            ),
        )
    return reserve


struct _ContinuousFrame(Movable):
    """`_draw_continuous_axis_frame`'s finished layout, the continuous-x
    counterpart to `_CategoricalFrame`, with a `LinearScale` on both
    axes. `px0`/`py0`/`px1`/`py1` are the inner plot rect.
    """

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
        """This frame as the `_RenderResult` its caller returns, mirroring
        `_CategoricalFrame.result`. Passes both `y_scale` and `x_scale`
        through: this is the one frame with a continuous x-axis, so it's the
        only one `annotate_vline()`/`annotate_point()` can support.
        """
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
    """The layout and axis-frame core every continuous-x render path shares
    (`_render_generic`'s continuous path and `_render_layers_generic`),
    `_draw_categorical_axis_frame`'s counterpart for a `LinearScale`
    x-axis: computes the dynamic left margin from `y_scale`'s ticks,
    resolves both scales' pixel ranges against the plot rect, and draws
    gridlines, both axis lines, and every tick mark plus label.

    Both scales' domains are decided by the caller (ranges are the
    `[0, 1]` placeholder `_data_extent`/`_zero_baseline_y_extent`
    return): one plot's data for a standalone render, every layer's data
    combined for a stack. `legend_reserve` is subtracted from the right
    edge before the rect is finalized.
    """
    var sc = _Scaled(theme)

    # y-domain ticks computed before plot_x0 is finalized: tick values
    # depend only on the domain, never the pixel range, so the left margin
    # can be sized to fit their labels, `max`'d against Theme's configured
    # minimum.
    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels(theme.y_tick_format)
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
    var x_labels = x_ticks.labels(theme.x_tick_format)

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(
                px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale
            )
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(out_y_scale, y_ticks.values[i])
            target.draw_line_aa(
                plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale
            )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )
    target.draw_line_aa(
        plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
        target.draw_line_aa(
            px,
            plot_y1,
            px,
            plot_y1 + sc.tick_length,
            theme.axis_color,
            width=sc.scale,
        )
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

    # Baseline offset so a label's glyphs sit roughly vertically centered
    # on its tick; draw_text's y is the text baseline.
    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(
            plot_x0 - sc.tick_length,
            py,
            plot_x0,
            py,
            theme.axis_color,
            width=sc.scale,
        )
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
        out_x_scale,
        out_y_scale,
        sc^,
        text_requests^,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
    )


def _lighten(color: Color, alpha: UInt8) -> Color:
    """`color` blended toward opaque white by `alpha`, for
    `Mark.EFFECT_SCATTER`'s halo (`Theme.halo_alpha`) and `Mark.RADAR`'s
    polygon fill (`mark_radar(fill_alpha=...)`). Built via
    `Color.with_alpha`/`Color.blend_over` (reduced alpha composited over
    white, kept fully opaque) rather than real alpha on the shape, so the
    tint is the same regardless of what's behind it.
    """
    return color.with_alpha(alpha).blend_over(Color(255, 255, 255))


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
    continuous axis frame, plus the legend sections its encoded channels
    call for; shared by the standalone path and by each `Mark.POINT`
    layer of a stack. Also `Mark.EFFECT_SCATTER`'s whole render with
    `draw_halo=True`.

    Legend sections stack top to bottom in one column, each returning the
    y just below it for the next: categorical or continuous color first
    (mutually exclusive), then size, the order `_legend_reserve_for`
    sized them in. `legend_y` in, the next free y out, so a layered
    caller threads the return value through as a cursor. `legend_x` is
    the caller's, since a layered render shares one column x from the
    combined rect. Row height, font size, colors, and point radius come
    from `plot`'s own `Theme`.

    `draw_halo` draws one extra circle under each point first,
    `_lighten`ed toward white at ~2.2x the radius, a static stand-in for
    ECharts' animated ripple.

    `Plot.encode()`'s `labels`, when set, draw each row's text centered
    `sc.label_gap` above its point; a row whose entry is `""` is skipped.
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
            # A plain lookup: _PointChannels resolved every row's domain index up
            # front.
            color = ch.palette[ch.cat.indices[i] % len(ch.palette)]
        else:
            color = theme.mark_color
        var radius = _round_to_int(
            ch.size_scale.to_pixel(plot.size_data[i])
        ) if ch.has_size else _round_to_int(sc.point_radius)
        # One group per point, covering its error bar, halo and marker
        # -- all one datum. The deferred label sits outside it, since
        # text is replayed after this pass (see _TextRequest).
        var tooltip = theme.svg_tooltips and plot._mark_style.point_tooltips
        if tooltip:
            target.begin_annotated_group(_point_tooltip_label(plot, i))
        if len(plot.y_err_data) > 0 or len(plot.y_err_lower_data) > 0:
            # Whisker first, point on top, in this point's own resolved `color`.
            # y_err and y_err_lower/y_err_upper are mutually exclusive, so exactly
            # one branch has data.
            var lo: Float64
            var hi: Float64
            if len(plot.y_err_data) > 0:
                var err = plot.y_err_data[i]
                lo = plot.y_data[i] - err
                hi = plot.y_data[i] + err
            else:
                lo = plot.y_data[i] - plot.y_err_lower_data[i]
                hi = plot.y_data[i] + plot.y_err_upper_data[i]
            var py_hi = _axis_pixel(y_scale, hi)
            var py_lo = _axis_pixel(y_scale, lo)
            var cap_half = _round_to_int(sc.error_bar_cap_width)
            target.draw_line_aa(px, py_hi, px, py_lo, color, width=sc.scale)
            target.draw_line_aa(
                px - cap_half,
                py_hi,
                px + cap_half,
                py_hi,
                color,
                width=sc.scale,
            )
            target.draw_line_aa(
                px - cap_half,
                py_lo,
                px + cap_half,
                py_lo,
                color,
                width=sc.scale,
            )
        if draw_halo:
            target.fill_circle_aa(
                px,
                py,
                _round_to_int(Float64(radius) * 2.2),
                _lighten(color, theme.halo_alpha),
            )
        if ch.has_shapes:
            # Same lookup as `color`'s categorical branch; ch.shapes is sized to
            # ch.cat.domain like ch.palette.
            _fill_shape_aa(
                target,
                px,
                py,
                radius,
                ch.shapes[ch.cat.indices[i] % len(ch.shapes)],
                color,
            )
        else:
            target.fill_circle_aa(px, py, radius, color)
        if tooltip:
            target.end_annotated_group()
        if len(plot.point_labels) > 0 and plot.point_labels[i] != "":
            # Baseline placed label_gap above the point's top edge (py - radius).
            text_requests.append(
                _TextRequest(
                    px,
                    py - radius - sc.label_gap,
                    plot.point_labels[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )

    if not theme.show_legend:
        return legend_y
    if not (ch.has_color_categories or ch.has_color or ch.has_size):
        return legend_y

    var next_y = legend_y
    if ch.has_color_categories:
        _draw_legend(
            target,
            text_requests,
            ch.cat.domain,
            ch.palette,
            legend_x,
            next_y,
            theme,
            shapes=ch.shapes,
        )
        next_y += len(ch.cat.domain) * (
            sc.legend_swatch_size + sc.legend_row_gap
        )
    elif ch.has_color:
        next_y = _draw_continuous_color_legend(
            target, text_requests, ch.color_scale, legend_x, next_y, theme
        )
    if ch.has_size:
        next_y = _draw_continuous_size_legend(
            target,
            text_requests,
            ch.size_mm,
            ch.size_scale,
            legend_x,
            next_y,
            theme,
        )
    return next_y


def _draw_line_layer[
    T: DrawTarget
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.LINE` plot's stroked path into an already-laid-out
    continuous axis frame, with `Theme.line_smoothing` via
    `_build_line_path`. Shared by the standalone and layered paths so
    both honor smoothing and its range check identically.

    `Plot.encode()`'s `y_err` whisker, when set, draws once per original
    data point before the line (whisker first, line on top), over the
    untouched `plot.x_data`/`y_data` rather than the decimated path, in
    `theme.mark_color` (`Mark.LINE` has no per-point color).
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    _check_line_smoothing(theme)
    if len(plot.y_err_data) > 0:
        var cap_half = _round_to_int(sc.error_bar_cap_width)
        for i in range(len(plot.x_data)):
            var px_i = _round_to_int(x_scale.to_pixel(plot.x_data[i]))
            var err = plot.y_err_data[i]
            var py_hi = _axis_pixel(y_scale, plot.y_data[i] + err)
            var py_lo = _axis_pixel(y_scale, plot.y_data[i] - err)
            target.draw_line_aa(
                px_i, py_hi, px_i, py_lo, theme.mark_color, width=sc.scale
            )
            target.draw_line_aa(
                px_i - cap_half,
                py_hi,
                px_i + cap_half,
                py_hi,
                theme.mark_color,
                width=sc.scale,
            )
            target.draw_line_aa(
                px_i - cap_half,
                py_lo,
                px_i + cap_half,
                py_lo,
                theme.mark_color,
                width=sc.scale,
            )
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
    """Draw one `Mark.AREA` plot's filled region into an already-laid-out
    continuous axis frame: the same curve `_draw_line_layer` strokes,
    closed down to the zero baseline (`y_scale`'s domain includes zero;
    see `_zero_baseline_y_extent`) and filled. Only the top edge smooths;
    the two closing segments to and along the baseline stay straight.
    The closing edge is pulled 1px off the bottom axis line when it lands
    there, the `_pull_off_axis_line` rule applied to a path.
    """
    var theme = plot._theme
    _check_line_smoothing(theme)
    var baseline_py = y_scale.to_pixel(0.0)
    if _round_to_int(baseline_py) == _round_to_int(y_scale.range_min):
        baseline_py -= 1.0
    var px = List[Float64](capacity=len(plot.x_data))
    var py = List[Float64](capacity=len(plot.x_data))
    for i in range(len(plot.x_data)):
        px.append(x_scale.to_pixel(plot.x_data[i]))
        py.append(y_scale.to_pixel(plot.y_data[i]))
    # Same sub-pixel thinning the stroked path gets; the fill's top edge is
    # that curve.
    var thinned = _decimate_to_pixel_columns(px, py)
    var path = _build_line_path(thinned.px, thinned.py, theme.line_smoothing)
    path.line_to(thinned.px[len(thinned.px) - 1], baseline_py)
    path.line_to(thinned.px[0], baseline_py)
    path.close()
    target.fill_path_aa(path, theme.mark_color, fill_rule=FillRule.NONZERO)


def _render_generic[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    has_shared_y_domain: Bool = False,
    shared_y_min: Float64 = 0.0,
    shared_y_max: Float64 = 0.0,
    shared_y_is_log: Bool = False,
) raises -> _RenderResult:
    """The dispatch, layout, and shape-drawing core `render()`/
    `render_svg()` (and the facet/layer variants) delegate to, generic
    over any `DrawTarget`, returning every axis/tick/legend label as
    `_TextRequest`s.

    Every mark other than `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER`
    dispatches to its own `_render_*` function immediately
    (`horizontal=True` variants included). What's left, the
    continuous-axis path, is the same assembly every categorical
    `_render_*` has: decide the two domains, size the legend column
    (`_legend_reserve_for`), draw the axis frame
    (`_draw_continuous_axis_frame`), then draw the mark
    (`_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`), all
    shared with `_render_layers_generic`.

    Raises up front for settings that can't apply to a standalone plot:
    `Plot.secondary_axis()`, a log scale on a non-continuous mark or on
    `Mark.AREA`'s y-axis, and `render_facets(shared_y_scale=True)`
    (`has_shared_y_domain`) on anything but `Mark.POINT`/`LINE`/
    `EFFECT_SCATTER`, or together with `y_err*`.

    `shared_y_is_log` (#217) is `_render_facets_generic`'s own decision,
    already validated there (every cell agrees, `shared_y_min`/
    `shared_y_max` already computed in log10-space via `_log_data_extent`)
    -- this only requires `plot._y_log` to match it, a defensive check
    against calling this directly with an inconsistent combination rather
    than a real per-cell decision point.
    """
    if plot._secondary_axis:
        raise Error(
            "Plot.secondary_axis() only applies inside render_layers()/"
            "render_layers_svg() -- a standalone plot has only one"
            " series, nothing for a second y-axis to pair against"
        )
    if (plot._y_log or plot._x_log) and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.AREA
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "Plot.scale_y_log()/scale_x_log() only apply to"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER -- a categorical-x-axis (or"
            " other non-continuous) mark has no continuous domain for a log"
            " scale to mean anything against"
        )
    if plot._y_log and plot._mark == Mark.AREA:
        raise Error(
            "Plot.scale_y_log(): not supported on Mark.AREA -- its y-domain is"
            " always forced through a zero baseline (see"
            " _zero_baseline_y_extent()'s docstring), and zero has no logarithm"
        )
    if (plot._x_domain.has or plot._y_domain.has) and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.AREA
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "Plot.scale_x_domain()/scale_y_domain() only apply to"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER today -- a categorical-x-axis"
            " (or other non-continuous) mark isn't wired up to an explicit"
            " domain override yet"
        )
    _validate_domain_override(
        plot._x_domain, plot._x_log, "Plot.scale_x_domain"
    )
    _validate_domain_override(
        plot._y_domain, plot._y_log, "Plot.scale_y_domain"
    )
    if has_shared_y_domain and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "render_facets(shared_y_scale=True): only"
            " Mark.POINT/LINE/EFFECT_SCATTER support a shared y-scale today"
            " (Mark.AREA's own forced zero baseline has no principled way to"
            " compose with an externally supplied shared domain)"
        )
    if has_shared_y_domain and plot._y_log != shared_y_is_log:
        raise Error(
            "render_facets(shared_y_scale=True): every cell must agree on"
            " Plot.scale_y_log() -- got a mix of log and linear cells"
        )
    if has_shared_y_domain and (
        len(plot.y_err_data) > 0
        or len(plot.y_err_lower_data) > 0
        or len(plot.y_err_upper_data) > 0
    ):
        # The shared union is computed over plain plot.y_data and isn't widened
        # for whisker endpoints, so a whisker could extend past the shared
        # axis.
        raise Error(
            "render_facets(shared_y_scale=True): not supported together with"
            " Plot.encode(y_err=...)/y_err_lower/y_err_upper -- the shared"
            " domain isn't widened for whisker endpoints yet"
        )
    _validate_log_scale_annotations(plot)
    if plot._mark == Mark.BAR:
        if plot._horizontal:
            return _render_horizontal_bar(target, plot, ox0, oy0, ox1, oy1)
        return _render_bar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.LOLLIPOP:
        if plot._horizontal:
            return _render_horizontal_lollipop(target, plot, ox0, oy0, ox1, oy1)
        return _render_lollipop(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.WATERFALL:
        return _render_waterfall(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.BOX:
        if plot._horizontal:
            return _render_horizontal_box(target, plot, ox0, oy0, ox1, oy1)
        return _render_box(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.CANDLESTICK:
        return _render_candlestick(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.BULLET:
        return _render_bullet(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.GROUPED_BAR:
        if plot._horizontal:
            return _render_horizontal_grouped_bar(
                target, plot, ox0, oy0, ox1, oy1
            )
        return _render_grouped_bar(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.STACKED_BAR:
        if plot._horizontal:
            return _render_horizontal_stacked_bar(
                target, plot, ox0, oy0, ox1, oy1
            )
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
    if plot._mark == Mark.BARBS:
        return _render_barbs(target, plot, ox0, oy0, ox1, oy1)
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
        if plot._horizontal:
            return _render_horizontal_beeswarm(target, plot, ox0, oy0, ox1, oy1)
        return _render_beeswarm(target, plot, ox0, oy0, ox1, oy1)
    if plot._mark == Mark.VIOLIN:
        if plot._horizontal:
            return _render_horizontal_violin(target, plot, ox0, oy0, ox1, oy1)
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
    _require_non_empty(len(plot.x_data), "Plot.encode()")

    var theme = plot._theme

    # Scaled once by theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Built once and handed to both _legend_reserve_for and
    # _draw_point_layer so the two agree; see _PointChannels.
    var ch = _PointChannels(plot, sc)

    # One FontCache for every measurement this render makes (legend sizing
    # and the axis frame's tick labels).
    var measure_cache = FontCache()
    var legend_reserve = _legend_reserve_for(plot, ch, sc, cache=measure_cache)

    # Mark.AREA forces a zero baseline into the y-domain; every other
    # continuous mark pads around its data. y_domain_data is plot.y_data,
    # or every whisker endpoint when y_err (or y_err_lower/y_err_upper) is
    # set, so the domain spans everything drawn. has_shared_y_domain
    # (render_facets(shared_y_scale=True)) short-circuits that with the
    # caller's precomputed domain.
    var y_domain_data = List[Float64]()
    if len(plot.y_err_data) > 0:
        for i in range(len(plot.y_data)):
            y_domain_data.append(plot.y_data[i] - plot.y_err_data[i])
            y_domain_data.append(plot.y_data[i] + plot.y_err_data[i])
    elif len(plot.y_err_lower_data) > 0:
        for i in range(len(plot.y_data)):
            y_domain_data.append(plot.y_data[i] - plot.y_err_lower_data[i])
            y_domain_data.append(plot.y_data[i] + plot.y_err_upper_data[i])
    else:
        for v in plot.y_data:
            y_domain_data.append(v)
    var y_scale = _domain_override_scale(
        plot._y_domain, plot._y_log
    ) if plot._y_domain.has else (
        LinearScale(
            shared_y_min, shared_y_max, 0.0, 1.0, is_log=shared_y_is_log
        ) if has_shared_y_domain else (
            _log_data_extent(y_domain_data) if plot._y_log else (
                _zero_baseline_y_extent(y_domain_data) if plot._mark
                == Mark.AREA else _data_extent(y_domain_data)
            )
        )
    )
    var x_scale = _domain_override_scale(
        plot._x_domain, plot._x_log
    ) if plot._x_domain.has else (
        _log_data_extent(plot.x_data) if plot._x_log else _data_extent(
            plot.x_data
        )
    )

    var frame = _draw_continuous_axis_frame(
        target,
        x_scale,
        y_scale,
        theme,
        legend_reserve,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=measure_cache,
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
    """The finished layout every vertical categorical mark draws its
    per-category shape into; see `_draw_categorical_axis_frame`. `px0`/
    `py0`/`px1`/`py1` are the inner plot rect (the same values the axis
    lines are drawn at), carried through so each caller builds its
    `_RenderResult` from them.
    """

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
        """This frame as the `_RenderResult` its caller returns. `text_requests`
        is copied rather than moved: Mojo rejects moving a single field out
        of a struct ("field destroyed out of the middle of a value") while
        the rest still needs its normal destruction. Passes `y_scale` through
        with `has_y_scale=True`, which is what gives every mark sharing this
        frame `Plot.annotate_line()`/`annotate_area()` support.
        """
        return _RenderResult(
            self.text_requests.copy(),
            self.px0,
            self.py0,
            self.px1,
            self.py1,
            self.y_scale,
            True,
        )


def _resolve_x_label_rotation(
    override: XAxisLabelRotation, max_label_width: Float64, step: Float64
) -> Float64:
    """The radians `_draw_categorical_axis_frame` rotates x-axis category
    labels by (#214): `0.0` (drawn horizontal, centered under the tick),
    or `pi / 4`/`pi / 2` (drawn right-aligned at the tick; see that
    function's own call site for why). `AUTO` escalates only as far as
    needed: horizontal if every label already fits its band
    (`OrdinalScale.step()`), 45 degrees if that alone clears it
    (measuring the rotated label's own narrower horizontal footprint,
    `max_label_width * cos(45deg)`, against `step`), 90 otherwise. An
    explicit override always wins, with no measurement needed.
    """
    if override == XAxisLabelRotation.DEG_0:
        return 0.0
    if override == XAxisLabelRotation.DEG_45:
        return pi / 4.0
    if override == XAxisLabelRotation.DEG_90:
        return pi / 2.0

    if max_label_width <= step:
        return 0.0
    if max_label_width * cos(pi / 4.0) <= step:
        return pi / 4.0
    return pi / 2.0


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
    *,
    mut cache: FontCache,
) raises -> _CategoricalFrame:
    """The layout and axis-frame core shared by every vertical categorical
    mark (`Mark.BAR`, `LOLLIPOP`, `WATERFALL`, `BOX`, `CANDLESTICK`,
    `BULLET`, `GROUPED_BAR`, `STACKED_BAR`, `STREAMGRAPH`, ...): computes
    the dynamic left margin from `y_scale`'s ticks, builds the
    `OrdinalScale` x-axis, draws gridlines, axis lines, y-tick marks and
    labels, and every category's x-tick mark and label. Returns the
    finished scales (pixel ranges resolved), the `_Scaled` theme, and the
    `_TextRequest`s so far; the caller draws its per-category shape.

    `y_scale`'s domain must already be decided (its range is the `[0, 1]`
    placeholder), since the marks differ there: `Mark.BAR`/`LOLLIPOP`/
    `WATERFALL` include a zero baseline, `Mark.BOX` fits the data spread.

    Long category labels rotate per `Theme.x_label_rotation` (#214,
    `_resolve_x_label_rotation`) once `x_scale` (and so its `step()`) is
    known, before `plot_y1` is finalized -- a rotated label needs extra
    bottom margin (`sin(rotation) * widest label`) reserved for it, the
    same "measure before finalizing the pixel range" pattern
    `dynamic_left_margin` already uses for the y-axis.
    """
    var sc = _Scaled(theme)

    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels(theme.y_tick_format)
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size, cache=cache))
        + sc.tick_length
        + sc.label_gap
        + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_x1 = ox1 - sc.margin_right

    var x_scale = OrdinalScale(
        categories.copy(), Float64(plot_x0), Float64(plot_x1)
    )

    var x_label_max_width = _max_label_width(
        categories, sc.font_size, cache=cache
    )
    var x_label_rotation = _resolve_x_label_rotation(
        theme.x_label_rotation, x_label_max_width, x_scale.step()
    )
    var x_label_extra_bottom = (
        _round_to_int(
            sin(x_label_rotation) * x_label_max_width
        ) if x_label_rotation
        > 0.0 else 0
    )

    var plot_y0 = oy0 + sc.margin_top
    var plot_y1 = oy1 - sc.margin_bottom - x_label_extra_bottom

    # y range is reversed: domain_min lands at the *bottom* of the
    # plot area (the larger pixel y), domain_max at the top -- see
    # LinearScale's docstring.
    var out_y_scale = y_scale
    out_y_scale.range_min = Float64(plot_y1)
    out_y_scale.range_max = Float64(plot_y0)

    if theme.show_gridlines:
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(out_y_scale, y_ticks.values[i])
            target.draw_line_aa(
                plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale
            )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )
    target.draw_line_aa(
        plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(
            plot_x0 - sc.tick_length,
            py,
            plot_x0,
            py,
            theme.axis_color,
            width=sc.scale,
        )
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
        target.draw_line_aa(
            center_px,
            plot_y1,
            center_px,
            plot_y1 + sc.tick_length,
            theme.axis_color,
            width=sc.scale,
        )
        if x_label_rotation > 0.0:
            # Right-aligned at the tick and rotated clockwise (screen y
            # increases downward): the anchor is the label's own last
            # character, so the label reads bottom-to-top running away
            # from the tick, the same convention ggplot2's `angle=45,
            # hjust=1` axis text produces.
            text_requests.append(
                _TextRequest(
                    center_px,
                    plot_y1 + sc.tick_length + sc.label_gap,
                    categories[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.RIGHT,
                    theme.font_family,
                    rotation=-x_label_rotation,
                )
            )
        else:
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

    return _CategoricalFrame(
        x_scale^,
        out_y_scale,
        sc^,
        text_requests^,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
    )


def _require_uniform_size(plots: List[Plot], caller: String) raises:
    """`render_facets()`/`render_facets_svg()`/`render_layers()`/
    `render_layers_svg()`'s shared precondition: every `Plot` in `plots`
    must have the same `.size()`, since the grid/shared canvas is derived
    from the plots. Raises naming `caller` on a mismatch or an empty
    list.
    """
    if len(plots) == 0:
        raise Error(caller + "(): plots must not be empty")
    var width = plots[0].width
    var height = plots[0].height
    for i in range(1, len(plots)):
        if plots[i].width != width or plots[i].height != height:
            raise Error(
                caller
                + "(): every Plot must share the same .size() -- plots[0] is "
                + String(width)
                + "x"
                + String(height)
                + ", plots["
                + String(i)
                + "] is "
                + String(plots[i].width)
                + "x"
                + String(plots[i].height)
            )


def render_facets(
    plots: List[Plot], cols: Int, shared_y_scale: Bool = False
) raises -> Canvas:
    """Render each of `plots` into its grid cell of a fresh `Canvas` sized
    from the plots (`_require_uniform_size`), supersampled by
    `plots[0]._theme.raster_supersample` like `render()` (`plots` is a
    plain borrow, #208 -- a copy is what actually gets the scale bump,
    so a temporary list literal binds fine). See `_render_facets_generic`
    for the cell-layout contract. `cols` is checked before anything
    else, since a non-positive value would divide by zero in the
    `rows`/canvas-size math.
    """
    if cols <= 0:
        raise Error(
            "render_facets(): cols must be positive (got " + String(cols) + ")"
        )
    _require_uniform_size(plots, "render_facets")
    var rows = (len(plots) + cols - 1) // cols
    var factor = plots[0]._theme.raster_supersample
    _require_positive_supersample(factor, "render_facets")
    var scaled_plots = _scaled_copy(plots, factor)
    var canvas = Canvas(
        cols * plots[0].width * factor, rows * plots[0].height * factor
    )
    var text_requests = _render_facets_generic(
        canvas, canvas.width, canvas.height, scaled_plots, cols, shared_y_scale
    )
    # One FontCache for every cell's labels -- see render()'s own.
    var text_cache = FontCache()
    _replay_text_requests(canvas, text_requests, text_cache)
    return downsample(canvas, factor)


def render_facets_svg(
    plots: List[Plot], cols: Int, shared_y_scale: Bool = False
) raises -> SvgCanvas:
    """`render_facets()`'s counterpart for `SvgCanvas`, with the same `cols`
    guard and `_render_facets_generic` core.
    """
    if cols <= 0:
        raise Error(
            "render_facets_svg(): cols must be positive (got "
            + String(cols)
            + ")"
        )
    _require_uniform_size(plots, "render_facets_svg")
    var rows = (len(plots) + cols - 1) // cols
    var svg = SvgCanvas(cols * plots[0].width, rows * plots[0].height)
    var text_requests = _render_facets_generic(
        svg, svg.width, svg.height, plots, cols, shared_y_scale
    )
    _replay_text_requests_svg(svg, text_requests)
    return svg^


def _render_facets_generic[
    T: DrawTarget
](
    mut target: T,
    width: Int,
    height: Int,
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
) raises -> List[_TextRequest]:
    """The shared cell-layout core `render_facets()`/`render_facets_svg()`
    delegate to. `width`/`height` are passed in because `DrawTarget` has
    no size accessor.

    `cols` columns, enough rows to fit `len(plots)`; a partial final row
    leaves cells blank. Each cell is laid out as a standalone render
    would lay out the whole target, with its own `Plot.labels()` titles
    and every `annotate_*()` kind (areas, bands, lines, vlines, points,
    best_fit), by pointing `_render_generic`'s bounds at the cell's
    label-shrunk rect. Cell boundaries are `width * col // cols`, so
    adjacent cells share the exact boundary pixel.

    `shared_y_scale` gives every cell one y-domain (`_data_extent` over
    the union of every cell's `y_data`, or `_log_data_extent` when every
    cell agrees on `Plot.scale_y_log()` -- #217). Only `Mark.POINT`/
    `LINE`/`EFFECT_SCATTER` support it, every cell must use one of those
    marks, and it doesn't combine with `y_err*` (the shared union isn't
    widened for whiskers); `_render_generic` raises for each case,
    including a log/linear mix.
    """
    var text_requests = List[_TextRequest]()
    if cols <= 0:
        raise Error(
            "render_facets(): cols must be positive (got " + String(cols) + ")"
        )
    if len(plots) == 0:
        return text_requests^

    # Computed once up front when asked for, so every cell reads the same
    # two numbers. shared_y_is_log follows plots[0]; a mix raises inside
    # _render_generic's own per-cell check rather than here, so the error
    # names which cell disagrees.
    var shared_y_min = 0.0
    var shared_y_max = 0.0
    var shared_y_is_log = shared_y_scale and plots[0]._y_log
    if shared_y_scale:
        var combined_y = List[Float64]()
        for i in range(len(plots)):
            for v in plots[i].y_data:
                combined_y.append(v)
        var domain = _log_data_extent(
            combined_y
        ) if shared_y_is_log else _data_extent(combined_y)
        shared_y_min = domain.domain_min
        shared_y_max = domain.domain_max

    var rows = (len(plots) + cols - 1) // cols
    for i in range(len(plots)):
        var row = i // cols
        var col = i % cols
        var cell_x0 = width * col // cols
        var cell_x1 = width * (col + 1) // cols
        var cell_y0 = height * row // rows
        var cell_y1 = height * (row + 1) // rows
        # Each cell's full rect is filled with that cell's background,
        # including the strip a title's margin reserves.
        target.fill_rect(
            cell_x0,
            cell_y0,
            cell_x1 - cell_x0,
            cell_y1 - cell_y0,
            plots[i]._theme.background,
        )
        var frame = _apply_labels(plots[i], cell_x0, cell_y0, cell_x1, cell_y1)
        var cell_result = _render_generic(
            target,
            plots[i],
            frame.ox0,
            frame.oy0,
            frame.ox1,
            frame.oy1,
            has_shared_y_domain=shared_y_scale,
            shared_y_min=shared_y_min,
            shared_y_max=shared_y_max,
            shared_y_is_log=shared_y_is_log,
        )
        var label_requests = _label_text_requests(
            plots[i],
            cell_x0,
            cell_y0,
            cell_x1,
            cell_y1,
            cell_result.px0,
            cell_result.py0,
            cell_result.px1,
            cell_result.py1,
        )
        # Each cell's annotations draw against that cell's own x/y scale, in
        # the same order a standalone render uses (areas and bands
        # underneath, then lines/vlines, points on top, best_fit last).
        # cell_result comes straight from _render_generic, so a continuous
        # mark's cell carries a real x_scale/y_scale and a categorical
        # mark's cell correctly has has_x_scale=False -- each pass below
        # raises its own "no continuous axis" error exactly as it would for
        # a standalone plot, with no extra branching needed here.
        var cell_area_requests = _draw_annotation_areas(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_band_requests = _draw_annotation_bands(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_vline_requests = _draw_annotation_vlines(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_line_requests = _draw_annotation_lines(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_point_requests = _draw_annotation_points(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_best_fit_requests = _draw_annotation_best_fit(
            target, plots[i], cell_result, plots[i]._theme
        )
        _extend_text_requests(text_requests, label_requests)
        _extend_text_requests(text_requests, cell_area_requests)
        _extend_text_requests(text_requests, cell_band_requests)
        _extend_text_requests(text_requests, cell_vline_requests)
        _extend_text_requests(text_requests, cell_line_requests)
        _extend_text_requests(text_requests, cell_point_requests)
        _extend_text_requests(text_requests, cell_best_fit_requests)
        _extend_text_requests(text_requests, cell_result.text_requests)

    return text_requests^


def _secondary_axis_y_title(plots: List[Plot]) -> String:
    """`render_layers()`'s secondary (right) y-axis caption: the first
    layer's `Plot.labels()` `y_title` where that layer also called
    `.secondary_axis()`, read per-layer rather than from `plots[0]`'s
    shared chrome. Empty when no secondary-axis layer set one.
    """
    for i in range(len(plots)):
        if (
            plots[i]._secondary_axis
            and plots[i]._labels.y_title.byte_length() > 0
        ):
            return plots[i]._labels.y_title
    return ""


def render_layers(plots: List[Plot]) raises -> Canvas:
    """Render every `Plot` in `plots` onto one shared coordinate system: one
    combined x/y domain across every layer, one set of axes/gridlines/
    ticks, each mark drawn over the last in the order given.

    Restricted to `Mark.POINT`/`LINE`/`AREA`, plus at most one `Mark.BAR`
    layer for a bar-plus-line combo chart (dispatched to
    `_render_bar_combo_layers`, which has a narrower scope). A
    `Plot.secondary_axis()` layer scales against its own y-domain on the
    right edge. A `Mark.POINT` layer may use `color`/`color_categories`/
    `size` encoding with its own scales and legend section; sections
    stack in one column in layer order. There is no per-series legend
    for flat-colored layers.

    Shared chrome (background, gridlines, axis colors, margins, font
    size, `Plot.labels()` titles) comes from `plots[0]`; every other
    layer's `Theme` governs only its own mark (`mark_color`,
    `point_radius`, `line_width`, `line_smoothing`, scaled by its own
    `Theme.scale`). A secondary-axis layer's `y_title` captions the right
    axis.

    Every `Plot` must share the same `.size()`; an empty list raises.
    Supersampled by `plots[0]._theme.raster_supersample` like `render()`,
    bumping every layer's scale together on a copy (`plots` is a plain
    borrow, #208).
    """
    _require_uniform_size(plots, "render_layers")
    var factor = plots[0]._theme.raster_supersample
    _require_positive_supersample(factor, "render_layers")
    var scaled_plots = _scaled_copy(plots, factor)
    var canvas = Canvas(
        scaled_plots[0].width * factor, scaled_plots[0].height * factor
    )
    var cx1 = canvas.width
    var cy1 = canvas.height
    canvas.fill_rect(0, 0, cx1, cy1, scaled_plots[0]._theme.background)
    var sc = _Scaled(scaled_plots[0]._theme)
    var y2_title = _secondary_axis_y_title(scaled_plots)
    var frame = _apply_labels(scaled_plots[0], 0, 0, cx1, cy1)
    if y2_title.byte_length() > 0:
        # Mirrors _apply_labels's extra_left reservation for the primary
        # y_title, on the right edge; _apply_labels only sees plots[0], not the
        # layer that owns the secondary caption.
        frame.ox1 -= Int(sc.axis_title_font_size) + sc.label_gap
    var result = _render_layers_generic(
        canvas, scaled_plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1
    )
    var label_requests = _label_text_requests(
        scaled_plots[0],
        0,
        0,
        cx1,
        cy1,
        result.px0,
        result.py0,
        result.px1,
        result.py1,
    )
    if y2_title.byte_length() > 0:
        # The mirror of _label_text_requests's primary y_title: rotated +pi/2
        # (reading top-to-bottom, the right-side convention) and anchored to
        # the outer right edge.
        label_requests.append(
            _TextRequest(
                cx1 - Int(sc.axis_title_font_size * 0.8),
                (result.py0 + result.py1) // 2,
                y2_title,
                scaled_plots[0]._theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                scaled_plots[0]._theme.font_family,
                rotation=pi / 2.0,
            )
        )
    # One FontCache for every layer's labels -- see render()'s own.
    var text_cache = FontCache()
    _replay_text_requests(canvas, label_requests, text_cache)
    _replay_text_requests(canvas, result.text_requests, text_cache)
    return downsample(canvas, factor)


def render_layers_svg(plots: List[Plot]) raises -> SvgCanvas:
    """`render_layers()`'s counterpart for `SvgCanvas`, with the same
    `_render_layers_generic` core and `_require_uniform_size`
    precondition.
    """
    _require_uniform_size(plots, "render_layers_svg")
    var svg = SvgCanvas(plots[0].width, plots[0].height)
    var cx1 = svg.width
    var cy1 = svg.height
    svg.fill_rect(0, 0, cx1, cy1, plots[0]._theme.background)
    var sc = _Scaled(plots[0]._theme)
    var y2_title = _secondary_axis_y_title(plots)
    var frame = _apply_labels(plots[0], 0, 0, cx1, cy1)
    if y2_title.byte_length() > 0:
        frame.ox1 -= Int(sc.axis_title_font_size) + sc.label_gap
    var result = _render_layers_generic(
        svg, plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1
    )
    var label_requests = _label_text_requests(
        plots[0], 0, 0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
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
    return svg^


def _render_bar_combo_layers[
    T: DrawTarget
](
    mut target: T,
    plots: List[Plot],
    bar_index: Int,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
) raises -> _RenderResult:
    """`_render_layers_generic`'s dispatch target when exactly one layer is
    `Mark.BAR`: a bar-plus-line combo chart sharing the bar layer's
    categorical x-axis instead of a continuous one.

    Every non-bar layer aligns to the categories by position:
    `plots[j].y_data[k]` plots at category `k`'s band center, and its
    `x_data` must have exactly `len(bar_categories)` entries (checked
    here) but its numeric content is never read; callers commonly pass
    `x=[0.0, 1.0, 2.0, ...]`.

    Scope: no `color`/`color_categories`/`size`/`y_err*`/`labels`
    encoding on non-bar layers, no `Plot.secondary_axis()`/
    `scale_y_log()`/`scale_x_log()`/`mark_bar(horizontal=True)`, and no
    `Plot.annotate_*()` on any layer; each raises. The bar layer keeps
    its own `Theme.color_by_sign`/`show_data_labels` through
    `_draw_bar_rects`.

    The bar layer always draws first, beneath every other layer,
    regardless of its position in `plots`; the others draw in order, each
    in its own `Theme`. The shared y-domain always includes a zero
    baseline (`_zero_baseline_y_extent`), as `Mark.BAR` requires.
    """
    var bar_categories = plots[bar_index].x_categories.copy()
    _validate_categorical_encoding(plots[bar_index])

    for i in range(len(plots)):
        if plots[i]._secondary_axis:
            raise Error(
                "render_layers(): Plot.secondary_axis() isn't supported yet on"
                " a Mark.BAR combo chart (layer "
                + String(i)
                + ")"
            )
        if plots[i]._y_log or plots[i]._x_log:
            raise Error(
                "render_layers(): Plot.scale_y_log()/scale_x_log() aren't"
                " supported yet on a Mark.BAR combo chart (layer "
                + String(i)
                + ")"
            )
        if plots[i]._horizontal:
            raise Error(
                "render_layers(): Plot.mark_bar(horizontal=True) isn't"
                " supported yet on a Mark.BAR combo chart (layer "
                + String(i)
                + ") -- a horizontal categorical axis alongside continuous"
                " line/point/area layers is a real, separate feature this"
                " doesn't attempt"
            )
        var has_annotations = (
            len(plots[i]._annotations.line_values) > 0
            or len(plots[i]._annotations.area_y0) > 0
            or len(plots[i]._annotations.vline_values) > 0
            or len(plots[i]._annotations.point_x) > 0
            or len(plots[i]._annotations.band_x) > 0
            or plots[i]._annotations.best_fit
        )
        if has_annotations:
            raise Error(
                "render_layers(): Plot.annotate_*() isn't supported yet on a"
                " Mark.BAR combo chart (layer "
                + String(i)
                + ")"
            )
        if i == bar_index:
            continue
        if not (
            plots[i]._mark == Mark.POINT
            or plots[i]._mark == Mark.LINE
            or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): alongside a Mark.BAR layer, every other layer"
                " must be Mark.POINT/LINE/AREA (layer "
                + String(i)
                + ")"
            )
        if len(plots[i].x_data) != len(bar_categories):
            raise Error(
                "render_layers(): with a Mark.BAR layer present, every other"
                " layer's own data must have one entry per bar category --"
                " layer "
                + String(i)
                + " has "
                + String(len(plots[i].x_data))
                + " points, the bar layer has "
                + String(len(bar_categories))
                + " categories"
            )
        if len(plots[i].y_data) != len(plots[i].x_data):
            raise Error(
                "render_layers(): layer "
                + String(i)
                + ": x and y must have the same length (got "
                + String(len(plots[i].x_data))
                + " and "
                + String(len(plots[i].y_data))
                + ")"
            )
        if (
            len(plots[i].color_data) > 0
            or len(plots[i].color_categories) > 0
            or len(plots[i].size_data) > 0
            or len(plots[i].y_err_data) > 0
            or len(plots[i].y_err_lower_data) > 0
            or len(plots[i].y_err_upper_data) > 0
            or len(plots[i].point_labels) > 0
        ):
            raise Error(
                "render_layers():"
                " color/color_categories/size/y_err/y_err_lower/y_err_upper/labels"
                " encoding isn't supported yet on a Mark.BAR combo chart's"
                " non-bar layers (layer "
                + String(i)
                + ")"
            )

    # The bar layer's own y_err/y_err_lower/y_err_upper (#216, allowed here
    # since _validate_categorical_encoding above already restricts them to
    # Mark.BAR) widens the shared domain to its whisker endpoints, same as
    # the standalone _render_bar does; every other layer's y_err* is
    # rejected above, so its own y_data is all it ever contributes.
    var combined_y = List[Float64]()
    for i in range(len(plots)):
        if i == bar_index:
            for v in _bar_y_domain_data(plots[i]):
                combined_y.append(v)
        else:
            for v in plots[i].y_data:
                combined_y.append(v)
    var y_scale = _zero_baseline_y_extent(combined_y)

    var theme = plots[0]._theme
    var sc = _Scaled(theme)

    # #215: one legend row per named layer (Plot.series_name()), the bar
    # layer included, each in that layer's own Theme.mark_color.
    var series_names = List[String]()
    var series_colors = List[Color]()
    for i in range(len(plots)):
        if plots[i]._labels.series_name.byte_length() > 0:
            series_names.append(plots[i]._labels.series_name)
            series_colors.append(plots[i]._theme.mark_color)
    var legend_reserve = (
        _dynamic_legend_width(series_names, sc.legend_swatch_size, sc) if len(
            series_names
        )
        > 0 else 0
    )

    var measure_cache = FontCache()
    var frame = _draw_categorical_axis_frame(
        target,
        bar_categories,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1 - legend_reserve,
        oy1,
        cache=measure_cache,
    )
    if len(series_names) > 0:
        _draw_legend(
            target,
            frame.text_requests,
            series_names,
            series_colors,
            frame.px1 + sc.margin_right,
            frame.py0,
            theme,
        )

    _draw_bar_rects(
        target,
        plots[bar_index],
        frame.x_scale,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        frame.text_requests,
    )

    for i in range(len(plots)):
        if i == bar_index:
            continue
        var layer_theme = plots[i]._theme
        _check_line_smoothing(layer_theme)
        var layer_sc = _Scaled(layer_theme)
        var px = List[Float64](capacity=len(plots[i].y_data))
        var py = List[Float64](capacity=len(plots[i].y_data))
        for k in range(len(plots[i].y_data)):
            px.append(frame.x_scale.center(k))
            py.append(frame.y_scale.to_pixel(plots[i].y_data[k]))
        if plots[i]._mark == Mark.POINT:
            var radius = _round_to_int(layer_sc.point_radius)
            for k in range(len(px)):
                target.fill_circle_aa(
                    _round_to_int(px[k]),
                    _round_to_int(py[k]),
                    radius,
                    layer_theme.mark_color,
                )
        elif plots[i]._mark == Mark.LINE:
            var path = _build_line_path(px, py, layer_theme.line_smoothing)
            target.stroke_path_aa(
                path, layer_theme.mark_color, width=layer_sc.line_width
            )
        else:
            # Mark.AREA -- same closed-down-to-baseline technique
            # _draw_area_layer uses, just against this frame's
            # categorical x positions instead of a continuous x_scale.
            var baseline_py = frame.y_scale.to_pixel(0.0)
            if _round_to_int(baseline_py) == _round_to_int(
                frame.y_scale.range_min
            ):
                baseline_py -= 1.0
            var path = _build_line_path(px, py, layer_theme.line_smoothing)
            path.line_to(px[len(px) - 1], baseline_py)
            path.line_to(px[0], baseline_py)
            path.close()
            target.fill_path_aa(
                path, layer_theme.mark_color, fill_rule=FillRule.NONZERO
            )

    return frame.result()


def _render_layers_generic[
    T: DrawTarget
](
    mut target: T, plots: List[Plot], ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """The shared-domain layout/draw core `render_layers()`/
    `render_layers_svg()` delegate to, built from the same pieces
    `_render_generic` uses (`_draw_continuous_axis_frame`,
    `_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`). What
    differs: domains computed across every layer's data, a legend column
    sized across every layer with a legend-y cursor threaded through in
    order, and an optional secondary axis. Exactly one `Mark.BAR` layer
    dispatches to `_render_bar_combo_layers` first.

    A `Plot.secondary_axis()` layer is excluded from the primary y-domain
    and gets its own (zero-baselined if any layer in its group is
    `Mark.AREA`, else `_data_extent`), drawn mirrored on the right edge
    (axis line, ticks, labels, no gridlines) with its width reserved
    between the plot rect and the legend column. Each layer's own
    `annotate_*()` (areas, bands, lines, vlines, points, best_fit) draw
    last against that layer's own y-scale and the one shared x-scale
    (there is no secondary x-axis). Returns a `_RenderResult` whose inner
    rect centers `plots[0]`'s titles.

    Not reached by a `Mark.BAR` combo chart (`_render_bar_combo_layers`,
    dispatched below before any of this runs): that path rejects every
    `annotate_*()` kind outright rather than drawing them against its
    categorical x-axis.
    """
    var text_requests = List[_TextRequest]()
    if len(plots) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Exactly one Mark.BAR layer dispatches to _render_bar_combo_layers (a
    # categorical x-axis is a different domain shape from this continuous
    # path). More than one has no shared-axis meaning and is rejected
    # first.
    var bar_layer_count = 0
    var bar_layer_index = -1
    for i in range(len(plots)):
        if plots[i]._mark == Mark.BAR:
            bar_layer_count += 1
            bar_layer_index = i
    if bar_layer_count > 1:
        raise Error(
            "render_layers(): at most one Mark.BAR layer is supported (got "
            + String(bar_layer_count)
            + ") -- combining several categorical bar layers has no principled"
            " shared-axis meaning yet"
        )
    if bar_layer_count == 1:
        return _render_bar_combo_layers(
            target, plots, bar_layer_index, ox0, oy0, ox1, oy1
        )

    # Log-ness (#217) is decided per axis -- x is shared by every layer
    # (there is no secondary x-axis), while y splits into the primary
    # group and the Plot.secondary_axis() group, each independently. Every
    # layer sharing an axis must agree; the first layer on each axis sets
    # that axis's value and every later one is checked against it, so the
    # raised message names the first layer that disagrees.
    var x_log_seen = False
    var x_log_value = False
    var y_log_seen = False
    var y_log_value = False
    var y2_log_seen = False
    var y2_log_value = False
    for i in range(len(plots)):
        # Layering-specific check: a standalone Mark.BAR is legal, a layered
        # one alongside these isn't. A lone Mark.BAR already dispatched above,
        # so this fires only for Mark.ARC and other unsupported marks.
        if not (
            plots[i]._mark == Mark.POINT
            or plots[i]._mark == Mark.LINE
            or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): only Mark.POINT/Mark.LINE/Mark.AREA can be"
                " layered here (got a different mark -- Mark.BAR is supported"
                " only as the lone categorical layer in a bar-combo chart, see"
                " _render_bar_combo_layers; Mark.ARC still isn't supported at"
                " all)"
            )
        if plots[i]._x_domain.has or plots[i]._y_domain.has:
            raise Error(
                "render_layers(): Plot.scale_x_domain()/scale_y_domain() aren't"
                " supported here yet (#209) -- layer "
                + String(i)
            )
        if not x_log_seen:
            x_log_seen = True
            x_log_value = plots[i]._x_log
        elif plots[i]._x_log != x_log_value:
            raise Error(
                "render_layers(): every layer must agree on"
                " Plot.scale_x_log() -- got a mix of log and linear x-axes"
                " (layer "
                + String(i)
                + ")"
            )
        if plots[i]._secondary_axis:
            if not y2_log_seen:
                y2_log_seen = True
                y2_log_value = plots[i]._y_log
            elif plots[i]._y_log != y2_log_value:
                raise Error(
                    "render_layers(): every Plot.secondary_axis() layer must"
                    " agree on Plot.scale_y_log() -- got a mix of log and"
                    " linear secondary y-axes (layer "
                    + String(i)
                    + ")"
                )
        else:
            if not y_log_seen:
                y_log_seen = True
                y_log_value = plots[i]._y_log
            elif plots[i]._y_log != y_log_value:
                raise Error(
                    "render_layers(): every primary-axis layer must agree on"
                    " Plot.scale_y_log() -- got a mix of log and linear"
                    " y-axes (layer "
                    + String(i)
                    + ")"
                )
        if plots[i]._y_log and plots[i]._mark == Mark.AREA:
            raise Error(
                "render_layers(): Plot.scale_y_log() isn't supported on a"
                " Mark.AREA layer -- its y-domain is always forced through a"
                " zero baseline, and zero has no logarithm (layer "
                + String(i)
                + ")"
            )
        _validate_continuous_encoding(
            plots[i], "render_layers(): layer " + String(i)
        )
        _validate_log_scale_annotations(plots[i])

    var has_secondary = False
    var has_primary = False
    for i in range(len(plots)):
        if plots[i]._secondary_axis:
            has_secondary = True
        else:
            has_primary = True
    if has_secondary and not has_primary:
        raise Error(
            "render_layers(): at least one layer must stay on the primary"
            " y-axis (every layer calling .secondary_axis() leaves nothing for"
            ' "secondary" to mean relative to)'
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
        # A layer's y_err/y_err_lower+y_err_upper widens its contribution to
        # the combined domain to each whisker's endpoints, as
        # _render_generic's y_domain_data does for a standalone plot.
        var has_y_err = len(plots[i].y_err_data) > 0
        var has_y_err_lower = len(plots[i].y_err_lower_data) > 0
        if plots[i]._secondary_axis:
            if has_y_err:
                for j in range(len(plots[i].y_data)):
                    combined_y2.append(
                        plots[i].y_data[j] - plots[i].y_err_data[j]
                    )
                    combined_y2.append(
                        plots[i].y_data[j] + plots[i].y_err_data[j]
                    )
            elif has_y_err_lower:
                for j in range(len(plots[i].y_data)):
                    combined_y2.append(
                        plots[i].y_data[j] - plots[i].y_err_lower_data[j]
                    )
                    combined_y2.append(
                        plots[i].y_data[j] + plots[i].y_err_upper_data[j]
                    )
            else:
                for v in plots[i].y_data:
                    combined_y2.append(v)
            if plots[i]._mark == Mark.AREA:
                any_area2 = True
        else:
            if has_y_err:
                for j in range(len(plots[i].y_data)):
                    combined_y.append(
                        plots[i].y_data[j] - plots[i].y_err_data[j]
                    )
                    combined_y.append(
                        plots[i].y_data[j] + plots[i].y_err_data[j]
                    )
            elif has_y_err_lower:
                for j in range(len(plots[i].y_data)):
                    combined_y.append(
                        plots[i].y_data[j] - plots[i].y_err_lower_data[j]
                    )
                    combined_y.append(
                        plots[i].y_data[j] + plots[i].y_err_upper_data[j]
                    )
            else:
                for v in plots[i].y_data:
                    combined_y.append(v)
            if plots[i]._mark == Mark.AREA:
                any_area = True

    if len(combined_x) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Scaled by the shared (plots[0]) theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Both domains span every primary-axis layer's data. A Mark.AREA layer
    # anywhere in a group forces the zero baseline for that group's axis
    # (already checked above to be incompatible with that group being log).
    # y_log_value/x_log_value default to False when no layer set them
    # (y_log_seen/x_log_seen stay False only when plots is empty, already
    # returned above).
    var y_scale = _log_data_extent(combined_y) if y_log_value else (
        _zero_baseline_y_extent(combined_y) if any_area else _data_extent(
            combined_y
        )
    )
    var x_scale = _log_data_extent(combined_x) if x_log_value else _data_extent(
        combined_x
    )

    var has_secondary_data = has_secondary and len(combined_y2) > 0
    var y_scale2 = LinearScale(0.0, 0.0, 0.0, 1.0)
    if has_secondary_data:
        y_scale2 = _log_data_extent(combined_y2) if y2_log_value else (
            _zero_baseline_y_extent(combined_y2) if any_area2 else _data_extent(
                combined_y2
            )
        )

    # secondary_axis_reserve is sized the way _draw_continuous_axis_frame
    # sizes the left margin: measure the secondary domain's tick labels,
    # then add tick_length + label_gap + margin_buffer. 0 with no secondary
    # axis. One FontCache serves every measurement in this render (the
    # secondary axis here, then one legend section per layer).
    var measure_cache = FontCache()

    var secondary_axis_reserve = 0
    if has_secondary_data:
        var y2_ticks_for_margin = y_scale2.ticks()
        var y2_labels_for_margin = y2_ticks_for_margin.labels(
            theme.y_tick_format
        )
        secondary_axis_reserve = (
            Int(
                _max_label_width(
                    y2_labels_for_margin, sc.font_size, cache=measure_cache
                )
            )
            + sc.tick_length
            + sc.label_gap
            + sc.margin_buffer
        )

    # #215: one legend row per named layer (Plot.series_name()), in that
    # layer's own Theme.mark_color -- a secondary-axis layer's row is
    # suffixed so the reader knows which axis it reads against. Collected
    # once here and reused both for legend_reserve's width measurement
    # and the actual draw below.
    var series_names = List[String]()
    var series_colors = List[Color]()
    for j in range(len(plots)):
        if plots[j]._labels.series_name.byte_length() > 0:
            var name = plots[j]._labels.series_name
            if plots[j]._secondary_axis:
                name += " (right axis)"
            series_names.append(name)
            series_colors.append(plots[j]._theme.mark_color)

    # legend_reserve is the widest legend section across every
    # encoding-using Mark.POINT layer, each measured with that layer's own
    # _Scaled; sections stack vertically, so the column width is a max,
    # not a sum.
    var legend_reserve = 0
    for j in range(len(plots)):
        var p_sc_j = _Scaled(plots[j]._theme)
        var ch_j = _PointChannels(plots[j], p_sc_j)
        legend_reserve = max(
            legend_reserve,
            _legend_reserve_for(plots[j], ch_j, p_sc_j, cache=measure_cache),
        )
    if len(series_names) > 0:
        legend_reserve = max(
            legend_reserve,
            _dynamic_legend_width(
                series_names, sc.legend_swatch_size, sc, cache=measure_cache
            ),
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

    # The secondary axis line/ticks/labels at the plot rect's right edge
    # (frame.px1), the mirror of the primary axis at frame.px0: ticks point
    # right, labels sit left-aligned past them. No gridlines.
    var out_y_scale2 = y_scale2
    out_y_scale2.range_min = Float64(frame.py1)
    out_y_scale2.range_max = Float64(frame.py0)
    if has_secondary_data:
        var y2_ticks = out_y_scale2.ticks()
        var y2_labels = y2_ticks.labels(theme.y_tick_format)
        var y2_label_baseline_offset = Int(sc.font_size * 0.35)
        target.draw_line_aa(
            frame.px1,
            frame.py0,
            frame.px1,
            frame.py1,
            theme.axis_color,
            width=sc.scale,
        )
        for i in range(len(y2_ticks.values)):
            var py = _axis_pixel(out_y_scale2, y2_ticks.values[i])
            target.draw_line_aa(
                frame.px1,
                py,
                frame.px1 + sc.tick_length,
                py,
                theme.axis_color,
                width=sc.scale,
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

    # The legend column's x is shared (past the secondary axis's reserve
    # when there is one); legend_y is a running cursor threaded through
    # each layer's section(s).
    var legend_x = frame.px1 + secondary_axis_reserve + sc.margin_right
    var legend_y = frame.py0
    if len(series_names) > 0:
        _draw_legend(
            target,
            text_requests,
            series_names,
            series_colors,
            legend_x,
            legend_y,
            theme,
        )
        legend_y += len(series_names) * (
            sc.legend_swatch_size + sc.legend_row_gap
        )
    for j in range(len(plots)):
        if len(plots[j].x_data) == 0:
            continue
        var layer_y_scale = out_y_scale2 if plots[
            j
        ]._secondary_axis else frame.y_scale
        if plots[j]._mark == Mark.POINT:
            var p_sc = _Scaled(plots[j]._theme)
            var ch_j = _PointChannels(plots[j], p_sc)
            legend_y = _draw_point_layer(
                target,
                text_requests,
                plots[j],
                ch_j,
                frame.x_scale,
                layer_y_scale,
                legend_x,
                legend_y,
            )
        elif plots[j]._mark == Mark.LINE:
            _draw_line_layer(target, plots[j], frame.x_scale, layer_y_scale)
        elif plots[j]._mark == Mark.AREA:
            _draw_area_layer(target, plots[j], frame.x_scale, layer_y_scale)

    # Each layer's annotate_*() draws last, against that layer's own
    # y_scale (primary or secondary) and the one shared x_scale (there is
    # no secondary x-axis). A throwaway _RenderResult per layer, built from
    # the shared rect plus that layer's y_scale and the frame's x_scale, is
    # enough to reuse every annotation function unmodified -- same order a
    # standalone render uses (areas and bands underneath, then lines/
    # vlines, points on top, best_fit last).
    for j in range(len(plots)):
        var layer_y_scale = out_y_scale2 if plots[
            j
        ]._secondary_axis else frame.y_scale
        var layer_result = _RenderResult(
            List[_TextRequest](),
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            layer_y_scale,
            True,
            frame.x_scale,
            True,
        )
        var layer_area_requests = _draw_annotation_areas(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_band_requests = _draw_annotation_bands(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_vline_requests = _draw_annotation_vlines(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_line_requests = _draw_annotation_lines(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_point_requests = _draw_annotation_points(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_best_fit_requests = _draw_annotation_best_fit(
            target, plots[j], layer_result, plots[j]._theme
        )
        _extend_text_requests(text_requests, layer_area_requests)
        _extend_text_requests(text_requests, layer_band_requests)
        _extend_text_requests(text_requests, layer_vline_requests)
        _extend_text_requests(text_requests, layer_line_requests)
        _extend_text_requests(text_requests, layer_point_requests)
        _extend_text_requests(text_requests, layer_best_fit_requests)

    return _RenderResult(
        text_requests^, frame.px0, frame.py0, frame.px1, frame.py1
    )


def _finished(
    var plot: Plot,
    theme: Theme,
    width: Int,
    height: Int,
    title: String,
    x_title: String,
    y_title: String,
    subtitle: String = "",
) -> Plot:
    """The shared tail of every one-call convenience function: apply
    `title`/`subtitle`/`x_title`/`y_title`, `theme`, and `width`/
    `height` to the half-built `plot` and return it unrendered, exactly
    what `Plot().mark_*().encode*(...).theme(theme).size(width,
    height).labels(...)` would build by hand (#112). Takes `plot` as
    `var` because `Plot`'s builder methods consume and return `Self` and
    `Plot` isn't `ImplicitlyCopyable`.
    """
    return plot^.labels(
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title
    ).theme(theme).size(width, height)


def scatter(
    x: List[Float64],
    y: List[Float64],
    tooltips: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A scatter plot: one point per (x, y) pair, the standard choice for
    showing the relationship between two continuous variables.

    `Mark.POINT` over continuous `x`/`y`.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
        tooltips: Whether each point carries an SVG `<title>` a browser
            shows on hover; defaults to `False`. Off by default because
            a title costs roughly as much as the point element itself,
            so a dense scatter's SVG about doubles -- see
            `Plot.mark_point()`'s own `tooltips` parameter.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import scatter
        from dataviz.plot import save

        def main() raises:
            var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
            var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

            var c = scatter(x, y)
            save(c, "docs/src/examples/out_scatter.svg")
        ```
    """
    var plot = Plot().mark_point(tooltips=tooltips).encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def scatter[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    tooltips: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`scatter()` generalized over numeric element type (`List[Int]`,
    `List[Float32]`, ...); see `Plot.encode()`'s `DType` overload and
    array_like.mojo. Delegates to the concrete overload above.
    """
    return scatter(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        tooltips=tooltips,
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )


def line(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A line chart: continuous x/y data connected in order, the standard
    choice for showing a trend over a continuous variable such as time.

    `Mark.LINE` over continuous `x`/`y`, connected in data order.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from std.math import sin

        from dataviz import line
        from dataviz.plot import save
        from dataviz.colors import BROWN
        from dataviz.theme import Theme

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            for i in range(40):
                var t = Float64(i) * 0.25
                x.append(t)
                y.append(sin(t) * 10.0 + t * 0.5)

            var c = line(
                x,
                y,
                theme=Theme(
                    mark_color=BROWN,
                    line_width=3.0,
                    show_gridlines=False,
                ),
            )
            save(c, "docs/src/examples/out_line.svg")
        ```

    Example (Slope Chart):
        ```mojo
        from dataviz import line
        from dataviz.plot import save
        from dataviz.theme import Theme
        from dataviz.colors import SEAGREEN

        def main() raises:
            # x=0.0 ("2023"), x=1.0 ("2024") -- revenue, in millions.
            var x: List[Float64] = [0.0, 1.0]
            var revenue: List[Float64] = [42.0, 61.0]

            var c = line(
                x,
                revenue,
                theme=Theme(
                    mark_color=SEAGREEN,
                    line_width=3.0,
                    show_gridlines=False,
                ),
                width=320,
                height=420,
            )
            save(c, "docs/src/examples/out_slope.svg")
        ```
    """
    var plot = Plot().mark_line().encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def line[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`line()` generalized over numeric element type; see `scatter()`'s
    `DType` overload above. Delegates to the concrete overload above.
    """
    return line(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )


def area(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """An area chart: a line chart with the region down to a zero
    baseline filled in, emphasizing a series' magnitude and cumulative
    feel over its exact trend line.

    `Mark.AREA` over continuous `x`/`y`, filled down to a zero baseline.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column; the filled area runs from each
            point down to zero.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from std.math import sin

        from dataviz import area
        from dataviz.plot import save
        from dataviz.colors import STEELBLUE
        from dataviz.theme import Theme

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            for i in range(30):
                var t = Float64(i) * 0.3
                x.append(t)
                y.append(sin(t) * 4.0 + 6.0)

            var c = area(x, y, theme=Theme(mark_color=STEELBLUE))
            save(c, "docs/src/examples/out_area.svg")
        ```
    """
    var plot = Plot().mark_area().encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title)


def area[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`area()` generalized over numeric element type; see `scatter()`'s
    `DType` overload above. Delegates to the concrete overload above.
    """
    return area(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        theme=theme,
        width=width,
        height=height,
        title=title,
        x_title=x_title,
        y_title=y_title,
    )
