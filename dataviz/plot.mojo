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

This file holds the `Plot` struct -- whose methods must live with its
definition, so `encode_histogram()`/`encode_waterfall()` delegate to
free functions in their mark's file -- along with `_render_generic`'s
dispatch, the entry points (`render`/`render_svg`/`save`), the
data-extent helpers, and the tooltip labels. Every other mark's
`_render_*` lives in its own file, which imports from here and is
imported back, a circular import Mojo resolves within one package.

## Where the rest of it went

What every mark shares was split out along its own seams (#222), each
module importing from here and imported back the same way:

- `annotations.mojo` -- the `annotate_*()` overlays and their passes
- `text.mojo` -- `_TextRequest`, the replay, and `_Scaled`
- `legend.mojo` -- legend layout, reservation, and the four kinds
- `frame.mojo` -- the continuous and categorical axis frames, and
  `_Orientation`
- `continuous.mojo` -- the point/line/area layers and their one-call
  functions
- `layers.mojo` and `facets.mojo` -- `render_layers()` and
  `render_facets()`
- `validate.mojo` -- the encoding checks `render()` runs first

Every one of those names is imported back into this module, so where a
symbol lives is not something a caller has to know: `from dataviz.plot
import _Orientation` still resolves, as it did before the split.

## The one-call convenience functions

Each mark's file also holds its one-call function (`bar()` in
bar.mojo, `pie()` in arc.mojo, ...), with `scatter()`/`line()`/
`area()` in `continuous.mojo`. Import them from the package (`from
dataviz import bar, scatter`). Each is `Plot().mark_*().encode*(...)` plus `theme`,
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
from canvas.geometry import FPoint, round_to_int
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
from dataviz.pixel_snap import _snap_pixel_center, _snap_pixel_edge
from dataviz.continuous import (
    _Decimated,
    _PointChannels,
    _build_line_path,
    _decimate_to_pixel_columns,
    _draw_area_layer,
    _draw_line_layer,
    _draw_point_layer,
    _lighten,
    area,
    line,
    scatter,
)
from dataviz.facets import (
    _render_facets_generic,
    _require_uniform_size,
    render_facets,
    render_facets_svg,
    save_facets,
)
from dataviz.frame import (
    _BandLabel,
    _BandLabelPoint,
    _BaselineRect,
    _BaselineRectF,
    _CategoricalFrame,
    _CategoricalIndex,
    _ContinuousFrame,
    _Orientation,
    _axis_pixel,
    _axis_pixel_f,
    _categorical_indices,
    _draw_categorical_axis_frame,
    _draw_continuous_axis_frame,
    _pull_off_axis_line,
    _pull_off_axis_line_f,
    _resolve_x_label_rotation,
    _with_secondary_axis,
)
from dataviz.layers import (
    _render_bar_combo_layers,
    _render_layers_generic,
    _secondary_axis_y_title,
    render_layers,
    render_layers_svg,
    save_layers,
)
from dataviz.legend import (
    _LegendLayout,
    _continuous_legend_row_height,
    _draw_continuous_color_legend,
    _draw_continuous_color_legend_h,
    _draw_continuous_size_legend,
    _draw_continuous_size_legend_h,
    _draw_legend,
    _draw_legend_at,
    _dynamic_legend_width,
    _legend_column_x,
    _legend_layout,
    _legend_origin_x,
    _legend_origin_y,
    _legend_reserve_for,
)
from dataviz.text import (
    _LabelsFrame,
    _Scaled,
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _max_label_width,
    _replay_text_requests,
    _replay_text_requests_svg,
    _text_advance,
)
from dataviz.validate import (
    _check_line_smoothing,
    _domain_override_scale,
    _require_non_empty,
    _require_non_negative,
    _require_some_positive,
    _validate_categorical_encoding,
    _validate_continuous_encoding,
    _validate_domain_override,
)
from dataviz.annotations import (
    _AnnotationData,
    _draw_annotation_areas,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_points,
    _draw_annotation_vlines,
    _validate_log_scale_annotations,
)
from dataviz.legend_position import LegendPosition
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
from dataviz.contour import _ContourData
from dataviz.tricontour import _TriContourData
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
from dataviz.contour import _render_contour, _render_contourf
from dataviz.tricontour import _render_tricontour
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
    var _contour: _ContourData
    var _tricontour: _TriContourData
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
        self._contour = _ContourData()
        self._tricontour = _TriContourData()
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

    def mark_contour(var self, levels: Int = 8) -> Self:
        """Isolines over a regular grid: marching squares per level, each
        line stroked in its level's color. Encoded via `encode_contour()`;
        see `_render_contour` for the tracing and `contour()` for the
        one-call form.

        Args:
            levels: How many levels to place when `encode_contour()` is
                not given an explicit list -- spaced evenly strictly
                inside the grid's own range. Must be positive.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.CONTOUR
        self._contour.level_count = levels
        return self^

    def mark_contourf(var self, levels: Int = 8) -> Self:
        """Filled bands between consecutive levels: `mark_contour()`'s
        companion, shading each level's region instead of outlining it.
        Encoded via `encode_contour()`; see `_render_contourf` for the
        painting order and `contourf()` for the one-call form.

        Args:
            levels: How many band boundaries to place when
                `encode_contour()` is not given an explicit list --
                spaced evenly strictly inside the grid's own range. Must
                be positive.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.CONTOURF
        self._contour.level_count = levels
        return self^

    def mark_tricontour(var self, levels: Int = 8) -> Self:
        """Isolines over scattered samples: the points are Delaunay-
        triangulated and each level traced over the triangles. Encoded via
        `encode_tricontour()`; see `_render_tricontour` for the tracing and
        `tricontour()` for the one-call form.

        Args:
            levels: How many levels to place when `encode_tricontour()` is
                not given an explicit list -- spaced evenly strictly
                inside the samples' own range. Must be positive.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.TRICONTOUR
        self._tricontour.level_count = levels
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

    def encode_contour(
        var self,
        z: List[List[Float64]],
        levels: List[Float64] = List[Float64](),
    ) -> Self:
        """Map a rectangular grid of values onto `Mark.CONTOUR`'s shape.

        `z` is row-major (`z[row][col]`): rows are the y axis and columns
        the x axis, both in grid-index units, so a 10x20 grid spans x
        `[0, 19]` and y `[0, 9]` with row 0 at the bottom. Shape checking
        (rectangular, at least 2x2) is deferred to render() time, like
        every other encode method here.

        Args:
            z: The grid, row-major and rectangular, at least 2x2.
            levels: The values to trace. Left empty (the default), the
                count from `mark_contour(levels=n)` decides how many
                are placed inside the data's range.

        Returns:
            Self, for further chaining.
        """
        self._contour.z = z.copy()
        self._contour.levels = levels.copy()
        return self^

    def encode_tricontour(
        var self,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        levels: List[Float64] = List[Float64](),
    ) -> Self:
        """Map scattered `(x, y, z)` samples onto `Mark.TRICONTOUR`'s
        shape.

        The points need not lie on any lattice and need no ordering: the
        Delaunay triangulation built at render time supplies the
        connectivity that a grid would otherwise provide. Length checking
        is deferred to render() time, like every other encode method here.

        Args:
            x: Each sample's x position.
            y: Each sample's y position, one per `x` entry.
            z: Each sample's value, one per `x` entry.
            levels: The values to trace. Left empty (the default), the
                count from `mark_tricontour(levels=n)` decides how many
                are placed inside the data's range.

        Returns:
            Self, for further chaining.
        """
        self._tricontour.x = x.copy()
        self._tricontour.y = y.copy()
        self._tricontour.z = z.copy()
        self._tricontour.levels = levels.copy()
        return self^

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
        docs/cookbook_recipes/annotate_vline.mojo) for a full worked
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


def _span_tooltip_label(
    category: String, low: Float64, high: Float64
) -> String:
    """A span's hover text: `"Berlin: -4 to 23"`. Both ends, since a
    span mark encodes the interval rather than any single value.
    """
    return (
        category
        + ": "
        + _format_fixed(low, _label_decimals(low))
        + " to "
        + _format_fixed(high, _label_decimals(high))
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


def render(plot: Plot) raises -> Canvas:
    """Render `plot` into a fresh `Canvas` sized `plot.width` x `plot.height`
    and return it, supersampled by `plot._theme.raster_supersample`
    (default 3): the scratch canvas is that many times larger, its
    transform is scaled by the same factor, the layout is drawn at
    logical coordinates, and `downsample` shrinks the result.

    The factor reaches the drawing through the canvas transform rather
    than through the layout arithmetic. It used to be folded into
    `_theme.scale` on a copy, which meant every metric was rounded in
    supersampled space and the raster and SVG paths measured in
    different units. `Theme.scale` keeps its own meaning here -- it is
    the user-facing density knob and still multiplies the layout, which
    is why this only removes the supersample bump and not `_Scaled`.

    `plot` is a plain borrow (#208): copying instead of mutating in
    place means `render(scatter(x, y))` and `save(scatter(x, y), path)`
    both compile inline, with no need to bind a temporary to a variable
    first.
    """
    var factor = plot._theme.raster_supersample
    _require_positive_supersample(factor, "render")
    var scratch = Canvas(
        plot.width * factor, plot.height * factor, plot._theme.background
    )
    # The half-pixel that box-downsampling costs: downsample() averages
    # the device block f*p .. f*p+f-1 into output pixel p, whose centre
    # sits at user coordinate p + (f-1)/(2f). Scaling alone therefore
    # lands everything (f-1)/(2f) px early -- 0.25 at factor 2, 0.333 at
    # 3, 0.375 at 4 -- so the origin shifts by (f-1)/2 device px first.
    scratch.translate(Float64(factor - 1) / 2.0, Float64(factor - 1) / 2.0)
    scratch.scale(Float64(factor), Float64(factor))
    # Logical bounds, not the scratch canvas's own: every coordinate
    # below is in user space now, and the transform maps it up.
    _render_into(scratch, plot, 0, 0, plot.width, plot.height)
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
    # One FontCache for the whole render, built on first use: every
    # measurement the layout makes (tick labels, legend entries) and then
    # every label drawn afterwards resolve fonts and rasterize glyphs
    # through it once, and a render with no text never scans the fonts
    # (#255, FontCache).
    var cache = FontCache()
    var result = _render_generic(
        canvas, plot, frame.ox0, frame.oy0, frame.ox1, frame.oy1, cache=cache
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
    _replay_text_requests(canvas, label_requests, cache)
    _replay_text_requests(canvas, area_annotation_requests, cache)
    _replay_text_requests(canvas, band_annotation_requests, cache)
    _replay_text_requests(canvas, vline_annotation_requests, cache)
    _replay_text_requests(canvas, annotation_requests, cache)
    _replay_text_requests(canvas, point_annotation_requests, cache)
    _replay_text_requests(canvas, best_fit_annotation_requests, cache)
    _replay_text_requests(canvas, result.text_requests, cache)


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
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var result = _render_generic(
        svg, plot, frame.ox0, frame.oy0, frame.ox1, frame.oy1, cache=cache
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
    (docs/cookbook_recipes/svg_accessibility.mojo).
    """
    var f = open(path, "w")
    f.write(accessible_svg_string(svg, title, description))
    f.close()


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
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """The dispatch, layout, and shape-drawing core `render()`/
    `render_svg()` (and the facet/layer variants) delegate to, generic
    over any `DrawTarget`, returning every axis/tick/legend label as
    `_TextRequest`s.

    `cache` is the render's one `FontCache` (#255, `FontCache`):
    threaded into every `_render_*` for its label measurements, then
    used again by the caller to draw the requests this returns, so a
    glyph measured during layout is already rasterized by the time it is
    drawn, and the ~20 ms font scan is paid once per figure (and not at
    all by a render that draws no text) rather than once per measurement
    pass plus once per replay.

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
            return _render_horizontal_bar(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.LOLLIPOP:
        if plot._horizontal:
            return _render_horizontal_lollipop(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_lollipop(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.WATERFALL:
        return _render_waterfall(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.BOX:
        if plot._horizontal:
            return _render_horizontal_box(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_box(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.CANDLESTICK:
        return _render_candlestick(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.BULLET:
        return _render_bullet(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.GROUPED_BAR:
        if plot._horizontal:
            return _render_horizontal_grouped_bar(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_grouped_bar(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.STACKED_BAR:
        if plot._horizontal:
            return _render_horizontal_stacked_bar(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_stacked_bar(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.GANTT:
        return _render_gantt(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.SPAN_CHART:
        return _render_span_chart(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.POPULATION_PYRAMID:
        return _render_population_pyramid(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.HEATMAP:
        return _render_heatmap(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.CALENDAR_HEATMAP:
        return _render_calendar_heatmap(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.CORRPLOT:
        return _render_corrplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.PUNCHCARD:
        return _render_punchcard(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.BARBS:
        return _render_barbs(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.CONTOUR:
        return _render_contour(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.CONTOURF:
        return _render_contourf(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.TRICONTOUR:
        return _render_tricontour(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.MARIMEKKO:
        return _render_marimekko(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.SUNBURST:
        return _render_sunburst(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.TREE:
        return _render_tree(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.TREEMAP:
        return _render_treemap(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.CHORD:
        return _render_chord(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.ARC_DIAGRAM:
        return _render_arc_diagram(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.GRAPH:
        return _render_graph(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.SANKEY:
        return _render_sankey(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.SINGLE_AXIS:
        return _render_single_axis(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.FUNNEL:
        return _render_funnel(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.BUMP:
        return _render_bump(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.STREAMGRAPH:
        return _render_streamgraph(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.BEESWARM:
        if plot._horizontal:
            return _render_horizontal_beeswarm(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_beeswarm(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.VIOLIN:
        if plot._horizontal:
            return _render_horizontal_violin(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        return _render_violin(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.RIDGELINE:
        return _render_ridgeline(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.ARC:
        return _render_arc(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.NIGHTINGALE:
        return _render_nightingale(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    if plot._mark == Mark.POLAR_BAR:
        return _render_polar_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.RADIALBAR:
        return _render_radialbar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.POLAR:
        return _render_polar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.RADAR:
        return _render_radar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.GAUGE:
        return _render_gauge(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    if plot._mark == Mark.PARALLEL:
        return _render_parallel(target, plot, ox0, oy0, ox1, oy1, cache=cache)

    _validate_continuous_encoding(plot, "Plot.encode()")
    _require_non_empty(len(plot.x_data), "Plot.encode()")

    var theme = plot._theme

    # Scaled once by theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Built once and handed to both _legend_reserve_for and
    # _draw_point_layer so the two agree; see _PointChannels.
    var ch = _PointChannels(plot, sc)

    var legend_reserve = _legend_reserve_for(plot, ch, sc, cache=cache)

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
        cache=cache,
    )

    if plot._mark == Mark.POINT or plot._mark == Mark.EFFECT_SCATTER:
        _ = _draw_point_layer(
            target,
            frame.text_requests,
            plot,
            ch,
            frame.x_scale,
            frame.y_scale,
            _legend_origin_x(legend_reserve, frame.px0, frame.px1, sc),
            _legend_origin_y(legend_reserve, frame.py0, frame.py1, sc),
            draw_halo=plot._mark == Mark.EFFECT_SCATTER,
            legend_horizontal=legend_reserve.position.is_horizontal(),
        )
    elif plot._mark == Mark.LINE:
        _draw_line_layer(target, plot, frame.x_scale, frame.y_scale)
    elif plot._mark == Mark.AREA:
        _draw_area_layer(target, plot, frame.x_scale, frame.y_scale)

    return frame.result()


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
