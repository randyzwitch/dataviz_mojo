"""Plot, the fluent builder every chart goes through. Data is plain
columnar `List[Float64]`/`List[String]` passed to `encode()`/
`encode_categorical()`/the other `encode_*` methods; builder methods
consume and return `Self` (`var self` -> `return self^`) so calls
chain: `Plot().mark_point().encode(x=xs, y=ys).theme(t)`.

`render(plot)`, `render_svg(plot)`, and `render_pdf(plot)` create a
`Canvas`, `SvgCanvas`, or `PdfCanvas` sized `plot.width` x `plot.height`;
`save()` picks the backend from the file extension. Each wraps a core (`_render_into`/
`_render_svg_into`) that fills the background, reserves title margins
(`_apply_labels`), and hands off to `_render_generic`;
`render_facets()`/`render_layers()` have their own per-cell/
shared-canvas variants of that pattern.

Everything shares one `[T: DrawTarget]` rendering core. Labels are
collected as `_TextRequest`s during the generic pass and drawn
afterward by `_replay_text_requests`, itself generic, so they land on
top of every mark and annotation. Raster draws use the anti-aliased
`Canvas` variants throughout.

This file holds the `Plot` struct -- whose methods must live with its
definition, so `encode_histogram()`/`encode_waterfall()` delegate to
free functions in their mark's file -- along with `_render_generic`'s
dispatch, the entry points (`render`/`render_svg`/`save`), the
data-extent helpers, and the tooltip labels. Every other mark's
`_render_*` lives in its own file, which imports from here and is
imported back, a circular import Mojo resolves within one package.

## Where the rest of it went

What every mark shares was split out along its own seams, each
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

## Family callback registration

`Plot` stores four noncapturing function pointers, specialized for
Canvas, SVG, PDF, and BoundsTarget. Each `mark_*()` setter binds all four
to its own family adapter. `_render_generic` invokes only the callback for its
concrete backend; it does not probe every family. Default plots and
continuous marks bind `_callback_continuous` and continue through the
shared continuous path. Copies and moves carry these pointers with the
payloads. Mark changes must replace all four pointers, including changes
back to a continuous mark, so a previous renderer cannot remain attached.

Registering a family still references all four target specializations;
it avoids unused families, not unused backends. The builder still imports
the families and carries their payloads. Supporting another draw target
requires extending the stored callback interface explicitly.

## Mark-adding checklist

The eleven `dataviz/<family>/dispatch.mojo` modules point here. Every
step is needed, and three of them fail late or not at all when skipped,
which is why they are written down rather than left to the compiler:

1. **The value.** Add its `Mark` constant in `dataviz/core/mark.mojo`,
   its `name()` branch, and raise `Mark.COUNT` to one past the new
   value. Every sweep walks `Mark(0)` through `Mark(COUNT - 1)`, so a
   `COUNT` left behind silently skips the new mark (#634);
   `test_count_is_one_past_the_last_named_mark` is what fails for it.
2. **The data.** Its payload struct as a `Plot` field, initialized in
   `__init__`; the `mark_*()` setter; and an `encode_*()` that calls
   `_require_mark` with the marks it serves.
3. **The render.** The `_render_*` function, and its arm in the family's
   `_render_<family>_family` in `dataviz/<family>/dispatch.mojo`.
4. **The registration.** In the `mark_*()` setter, bind all four of the
   family's adapters: `_callback_<family>[Canvas]`, `[SvgCanvas]`,
   `[PdfCanvas]` and `[BoundsTarget]`. *Fails late*: a setter that binds
   nothing compiles, keeps the default `_callback_continuous`, and at
   render time falls through to the continuous path and raises
   `Plot.encode(): there is no data to draw` -- naming neither the mark
   nor the missing registration.
5. **The export.** Add the one-call function to `dataviz/__init__.mojo`.
6. **The registry.** A representative constructor in
   `tests/_mark_registry.mojo`, then `pixi run digest-update`, and check
   the diff of `tests/output_digest.txt` adds the new mark's lines and
   moves no others. The normal test suite checks the registry's marks
   through copying, moving, collections, and all three backends.
7. **The docs page.** An `ExamplePage` in
   `scripts/_example_docstrings.mojo` -- its second field is the module
   path such as `"spatial/stem3d"`, not the page name -- and a display
   name and category entry in `scripts/gen_example_docs.mojo`. Then run
   `pixi run example` and confirm the page's figure was written. *Fails
   not at all*: an unregistered page generates no program, so the
   pipeline reports every module clean with the figure simply absent.

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

from canvas.bounds import BoundsTarget
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.gradient import LinearGradient
from canvas.fill_rule import FillRule
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.vector.draw_target import DrawTarget
from canvas.geometry import FPoint, round_to_int
from canvas.path import Path
from canvas.vector.pdf import PdfCanvas, write_pdf
from canvas.vector.svg import SvgCanvas
from canvas.text.render import draw_text, measure_text, FontWeight, TextAlign
from canvas.text.font_cache import FontCache

from dataviz.core.array_like import (
    Float64Sequence,
    StringSequence,
    _materialize_floats,
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
    _materialize_strings,
)
from dataviz.core.numpy_interop import _materialize_python_floats
from std.python import PythonObject
from dataviz.core.color_scale import (
    ColorScale,
    _ColorDomainOverride,
    categorical_palette_for,
)

from canvas.geometry import snap_to_pixel_center, snap_to_pixel_edge
from dataviz.basic.continuous import (
    _PointChannels,
    _build_line_path,
    _decimate_to_pixel_columns,
    _draw_area_layer,
    _draw_line_layer,
    _draw_point_layer,
    area,
    line,
    scatter,
)
from dataviz.facets import (
    _render_facets_generic,
    render_facets,
    render_facets_pdf,
    render_facets_svg,
    save_facets,
)
from dataviz.core.frame import (
    _BaselineRectF,
    _CategoricalFrame,
    _ContinuousFrame,
    _Orientation,
    _axis_pixel,
    _axis_pixel_f,
    _categorical_indices,
    _draw_axis_spines,
    _draw_categorical_axis_frame,
    _draw_continuous_axis_frame,
    _push_plot_clip,
    _pull_off_axis_line_f,
    _resolve_x_label_rotation,
)
from dataviz.layers import (
    _render_bar_combo_layers,
    _render_layers_generic,
    _secondary_axis_y_title,
    render_layers,
    render_layers_pdf,
    render_layers_svg,
    save_layers,
)
from dataviz.core.legend import (
    _LegendLayout,
    _continuous_color_legend_layout,
    _continuous_legend_labels,
    _draw_continuous_color_legend,
    _draw_continuous_color_legend_at,
    _draw_legend,
    _levels_descending,
    _draw_legend_at,
    _dynamic_legend_width,
    _legend_layout,
    _legend_origin_x,
    _legend_origin_y,
    _legend_reserve_for,
)
from dataviz.core.text import (
    _Scaled,
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _max_label_width,
    _replay_text_requests,
)
from dataviz.core.validate import (
    _check_line_smoothing,
    _check_unsupported_flags,
    _domain_override_scale,
    _require_non_empty,
    _require_non_negative,
    _require_some_positive,
    _validate_categorical_encoding,
    _validate_continuous_encoding,
    _validate_color_domain,
    _validate_domain_override,
    _validate_tick_override,
)
from dataviz.core.axis_controls import _AxisControls, _TickOverride
from dataviz.core.annotations import (
    _AnnotationData,
    _draw_annotation_areas,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_arrows,
    _draw_annotation_points,
    _draw_annotation_vlines,
    _validate_log_scale_annotations,
)

from dataviz.core.line_style import LineStyle
from dataviz.core.stack_baseline import StackBaseline
from dataviz.core.step_style import StepStyle
from morrow import Morrow

from dataviz.core.delaunay import Triangulation, delaunay
from dataviz.core.mark import Feature, Mark, _require_mark, _supporting_names
from dataviz.core.marker import PointShape
from dataviz.basic.dispatch import _callback_basic
from dataviz.categorical.dispatch import _callback_categorical
from dataviz.distributions.dispatch import _callback_distributions
from dataviz.binned.dispatch import _callback_binned
from dataviz.aggregation.dispatch import _callback_aggregation
from dataviz.relationships.dispatch import _callback_relationships
from dataviz.radial.dispatch import _callback_radial
from dataviz.multivariate.dispatch import _callback_multivariate
from dataviz.spatial.dispatch import _callback_spatial
from dataviz.grid.dispatch import _callback_grid
from dataviz.hierarchy_marks.dispatch import _callback_hierarchy_marks

from dataviz.core.output_format import OutputFormat
from dataviz.core.scale import (
    LinearScale,
    _format_fixed,
    _label_decimals,
    _min_max,
    _symlog_forward,
)
from dataviz.core.theme import Theme

from dataviz.radial.nightingale import _render_nightingale
from dataviz.radial.polar import _render_polar

from dataviz.basic.bar import _render_horizontal_bar
from dataviz.distributions.beeswarm import _render_horizontal_beeswarm

from dataviz.distributions.violin import _render_horizontal_violin
from dataviz.categorical.waterfall import _WaterfallData
from dataviz.distributions.box import _BoxData
from dataviz.binned.hexbin import _HexbinData, _render_hexbin
from dataviz.multivariate.quiver import _render_quiver
from dataviz.multivariate.streamplot import _StreamData, _render_streamplot
from dataviz.spatial.scatter3d import _Xyz
from dataviz.spatial.bar3d import _Bars3D, _Voxels
from dataviz.spatial.stem3d import _Ribbon3D, _Vectors3D
from dataviz.spatial.surface3d import _Surface
from dataviz.binned.hist2d import _hist2d_counts
from dataviz.distributions.boxen import (
    _BoxenData,
    _letter_values,
    _render_boxenplot,
)
from dataviz.distributions.candlestick import _CandleData
from dataviz.categorical.bullet import _BulletData
from dataviz.categorical.population_pyramid import _PyramidData
from dataviz.grid.heatmap import _HeatmapData
from dataviz.radial.polar import _PolarData
from dataviz.radial.radar import _RadarData
from dataviz.radial.gauge import _GaugeData
from dataviz.multivariate.parallel import _ParallelData
from dataviz.grid.calendar_heatmap import _CalendarData
from dataviz.grid.corrplot import _CorrplotData
from dataviz.grid.punchcard import _PunchcardData
from dataviz.multivariate.barbs import _BarbsData
from dataviz.multivariate.contour import _ContourData
from dataviz.grid.image import _ImageData
from dataviz.multivariate.tricontour import _TriContourData
from dataviz.core.cluster import Dendrogram
from dataviz.hierarchy_marks.dendrogram import _DendrogramData
from dataviz.multivariate.triplot import _TriplotData
from dataviz.grid.marimekko import _MarimekkoData
from dataviz.relationships.edges import _EdgeData
from dataviz.hierarchy_marks.hierarchy import _HierarchyData
from dataviz.distributions.box import _box_stats, _render_horizontal_box

from dataviz.categorical.grouped_bar import _render_horizontal_grouped_bar

from dataviz.grid.corrplot import _render_corrplot
from dataviz.grid.punchcard import _render_punchcard
from dataviz.multivariate.barbs import _render_barbs
from dataviz.multivariate.contour import _render_contour, _render_contourf
from dataviz.grid.image import _render_image

from dataviz.multivariate.tricontour import (
    _render_tricontour,
    _render_tricontourf,
)
from dataviz.multivariate.triplot import _render_tripcolor, _render_triplot

from dataviz.binned.histogram import (
    BinRule,
    HistogramBins,
    _HistogramData,
    _bin_histogram,
    _draw_histogram_layer,
)
from dataviz.categorical.lollipop import _render_horizontal_lollipop
from dataviz.aggregation.pointplot import _render_pointplot
from dataviz.basic.single_axis import _render_single_axis

from dataviz.categorical.stacked_bar import _render_horizontal_stacked_bar
from dataviz.categorical.streamgraph import _render_streamgraph
from dataviz.categorical.waterfall import (
    _render_waterfall,
    _waterfall_running_totals,
)


struct _GanttData(Copyable, Movable):
    """One start/end span per category, for `Mark.GANTT`/`SPAN_CHART`. See
    `encode_gantt()`. Stored on `Plot._gantt`.
    """

    var start: List[Float64]
    var end: List[Float64]

    def __init__(out self):
        self.start = List[Float64]()
        self.end = List[Float64]()


struct _ContinuousData(Copyable, Movable):
    """The continuous position channels, `encode()`'s `x` and `y`. Stored
    on `Plot._continuous`.

    `y` is every mark's value channel, continuous whether or not the x
    axis is, so a categorical mark reads `_categorical.x` for its
    categories and `_continuous.y` for their values. `x` is empty for
    those marks.
    """

    var x: List[Float64]
    var y: List[Float64]

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()


struct _CategoricalData(Copyable, Movable):
    """The categorical position channel, `encode_categorical()`'s `x`.
    Stored on `Plot._categorical`.

    One string per slot, in the order they are drawn; `LinearScale`'s
    ordinal counterpart indexes this list position for position. Empty
    when the x axis is continuous.
    """

    var x: List[String]

    def __init__(out self):
        self.x = List[String]()


struct _ChannelData(Copyable, Movable):
    """The non-positional encoding channels: color, size and per-point
    labels. Stored on `Plot._channels`.

    Color arrives one of two ways and they are mutually exclusive.
    `color` is continuous and maps through the theme's ramp;
    `color_categories` is discrete and maps through the categorical
    palette, with `color_map` pinning chosen categories to chosen
    colors. Which a mark supports is listed in `encode()`.
    """

    var color: List[Float64]
    var color_categories: List[String]
    var color_map: Dict[String, Color]
    """Explicit category-to-color overrides for `color_categories`. A
    category absent here takes the palette color for its index."""

    var shape_map: Dict[String, PointShape]
    """Explicit category-to-shape overrides for `color_categories`, used
    only under `Theme.shape_by_category`. A category absent here takes
    the shape for its index, as before.

    `color_map`'s counterpart, and it exists for the same reason one
    figure's panels need `shared_shape_map()`: shapes were dealt by
    position in each panel's own category domain, so a category missing
    from one panel shifted the shapes of every panel after it, with no
    way to pin one (#365)."""

    var size: List[Float64]
    var point_labels: List[String]
    """Set only via `encode()`'s `labels`; `Mark.POINT`/`EFFECT_SCATTER`
    only. A point has no obvious default label, so this is a data
    channel rather than a `Theme` flag: providing it is the opt-in. A
    row's label may be "" to skip that one point."""

    def __init__(out self):
        self.color = List[Float64]()
        self.color_categories = List[String]()
        self.color_map = Dict[String, Color]()
        self.shape_map = Dict[String, PointShape]()
        self.size = List[Float64]()
        self.point_labels = List[String]()


struct _ErrorBarData(Copyable, Movable):
    """Error-bar half-widths on the y channel. Stored on `Plot._y_err`.

    `symmetric` is `encode()`'s `y_err`, one half-width per row drawn
    both ways. `lower`/`upper` are `y_err_lower`/`y_err_upper`, set
    together and mutually exclusive with `symmetric`; `_validate_*`
    rejects giving both.
    """

    var symmetric: List[Float64]
    var lower: List[Float64]
    var upper: List[Float64]

    def __init__(out self):
        self.symmetric = List[Float64]()
        self.lower = List[Float64]()
        self.upper = List[Float64]()


struct _NightingaleData(Copyable, Movable):
    """Which of ECharts' two `rose_type` radius formulas each wedge of a
    `Mark.NIGHTINGALE` uses. See `mark_nightingale()`. Stored on
    `Plot._nightingale`.

    The wedge values themselves are `_categorical.x`/`_continuous.y`, shared with
    the other categorical marks, so this struct holds only the setting.
    """

    var area: Bool
    """False scales a wedge's radius by `value / max` ("radius"); True
    scales its area instead, `sqrt(value / max)` ("area")."""

    def __init__(out self):
        self.area = False


struct _GroupedBarData(Copyable, Movable):
    """One name per series and one value per (series, category) pair, for
    `Mark.GROUPED_BAR`/`STACKED_BAR`/`BUMP`/`STREAMGRAPH`. See
    `encode_grouped_bar()`. Stored on `Plot._grouped_bar`.
    """

    var series_names: List[String]
    var values: List[List[Float64]]
    var errors: List[List[Float64]]
    """Optional per-(series, category) symmetric error-bar half-width
, shaped like `values`; empty when `encode_grouped_bar()`'s
    `errors` wasn't given. `Mark.GROUPED_BAR` only, checked in
    `_validate_grouped_bar_series`."""

    var percent: Bool
    """`Mark.STACKED_BAR` only: normalize each category's segments to
    sum to 100%. See `mark_stacked_bar()`."""

    def __init__(out self):
        self.series_names = List[String]()
        self.values = List[List[Float64]]()
        self.errors = List[List[Float64]]()
        self.percent = False


struct _DistributionData(Copyable, Movable):
    """One list of raw values per category, kept unsummarized, for
    `Mark.BEESWARM`/`VIOLIN`/`RIDGELINE`. See `encode_distribution()`.
    Stored on `Plot._distribution`.

    `kde_bandwidth_override` is a caller's kernel-density bandwidth,
    overriding each category's Silverman's-rule default; 0.0 means use
    the default. `kde_scale_by_count` scales each category's maximum
    width/rise by `sqrt(n_i / max(n))`. See `mark_violin()`/
    `mark_ridgeline()`.

    `ecdf_complementary` draws `Mark.ECDF` as `1 - F(x)` rather than
    `F(x)`. It lives here rather than on `_MarkStyle` because it is not
    a proportion or an angle: it selects which of two functions of the
    same observations the chart is, the way `kde_bandwidth_override`
    selects which estimate a violin draws. See `mark_ecdf()`.
    """

    var values: List[List[Float64]]
    var kde_bandwidth_override: Float64
    var kde_fill: Bool
    var kde_rug: Bool
    var kde_scale_by_count: Bool
    var ecdf_complementary: Bool

    def __init__(out self):
        self.values = List[List[Float64]]()
        self.kde_bandwidth_override = 0.0
        self.kde_fill = False
        self.kde_rug = False
        self.kde_scale_by_count = False
        self.ecdf_complementary = False


struct _MarkStyle(Copyable, Movable):
    """Per-mark appearance knobs, each read by exactly one mark's render
    function and set only through that mark's `mark_*()` parameters (or
    its one-call convenience function). Stored on `Plot._mark_style`.

    These are geometry (angles, ring counts, width fractions) describing
    one chart's proportions, so they live here rather than on `Theme`,
    which holds what a theme can restyle; per-mark colors stayed on
    `Theme` so a dark theme can fix contrast without every caller passing
    a color. `point_tooltips` is behavioral rather than geometric but
    belongs here for the same reason: whether a scatter can afford an SVG
    `<title>` per point depends on how many points this chart has (see
    `mark_point()`).

    Field names keep their mark prefix (`gauge_start_angle`) since several
    would otherwise collide (`polar_grid_rings`/`radar_grid_rings`); the
    parameters that set them drop it (`mark_gauge(start_angle=...)`).
    """

    var point_tooltips: Bool
    var point_jitter_x: Float64
    """`Mark.POINT`/`EFFECT_SCATTER` only: half-width of the deterministic
    offset applied to each point's x, **in pixels**. 0.0 is off, which is
    the default and leaves every point exactly where it was.

    Pixels rather than data units on purpose. #149's open question was
    what a continuous scatter jitters *within*: a categorical mark has its
    category's band, and a continuous axis has no such region. A pixel
    width sidesteps that by describing the visual separation the caller
    wants rather than a quantity in the data's own units, and it stays
    constant as the domain changes."""

    var point_jitter_y: Float64
    """The same for y. Independent of `point_jitter_x` so a caller can
    spread along one axis only, which is the common case when one axis is
    discrete-valued."""
    var donut_inner_radius_fraction: Float64
    var bullet_measure_width_fraction: Float64
    var waterfall_delta_width_fraction: Float64
    var chord_ring_fraction: Float64
    var radialbar_ring_gap_fraction: Float64
    var radar_grid_rings: Int
    var violin_width_fraction: Float64
    var line_style: LineStyle
    """How `Mark.LINE`'s stroke is broken up, from
    `mark_line(style=...)`. `SOLID` unless asked otherwise; distinct
    from `Theme.gridline_style`/`annotation_line_style`, which are
    furniture rather than data.
    """

    var step: StepStyle
    """Where the riser sits between two samples, from
    `mark_line(step=...)` or `mark_area(step=...)`.
    `NONE` (straight interpolation) unless asked otherwise. One field
    for both marks rather than one apiece: a stepped area is a stepped
    line with the region under it filled, so the two share `_step_points`
    and would only ever be set to the same values. The one field here
    that changes what the chart claims rather than how it looks, which
    is exactly why it is not on `Theme`: a theme may restyle a line, not
    reinterpret it.
    """

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
    var streamgraph_baseline: StackBaseline
    """Where `Mark.STREAMGRAPH` stacks from, via
    `mark_streamgraph(baseline=...)`. `WIGGLE` unless asked otherwise;
    `ZERO` is the ordinary stacked area chart -- see `StackBaseline`.
    """
    var eventplot_line_length: Float64
    """Each `Mark.EVENTPLOT` tick's height as a fraction of its row's
    band, from `mark_eventplot(line_length=...)`. `1.0` (the full
    band) unless asked otherwise. Geometry describing one chart's
    proportions, like `violin_width_fraction` above, so it lives here
    rather than on `Theme`.
    """

    def __init__(out self):
        self.point_tooltips = False
        self.point_jitter_x = 0.0
        self.point_jitter_y = 0.0
        self.donut_inner_radius_fraction = 0.0
        self.bullet_measure_width_fraction = 0.35
        self.waterfall_delta_width_fraction = 0.6
        self.chord_ring_fraction = 0.08
        self.radialbar_ring_gap_fraction = 0.25
        self.radar_grid_rings = 4
        self.violin_width_fraction = 0.4
        self.line_style = LineStyle.SOLID
        self.step = StepStyle.NONE
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
        self.streamgraph_baseline = StackBaseline.WIGGLE
        self.eventplot_line_length = 1.0


struct _DomainOverride(Copyable, Movable):
    """An explicit minimum and maximum axis domain set via `.scale_x_domain()`/
    `.scale_y_domain()`, overriding the padded/zero-baselined
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
    """A longer SVG `<desc>` than `subtitle` need be; see
    `Plot.labels()`'s own docstring. `save()`/`save_layers()`/
    `save_facets()` fall back to `subtitle` when this is empty."""
    var series_name: String
    """This layer's name in `render_layers()`'s per-layer legend;
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
    own columns. The channels many marks share are grouped by what they
    encode rather than by mark: `_continuous` (x/y), `_categorical`
    (the categorical x), `_channels` (color, size, point labels) and
    `_y_err`. What is left ungrouped is the settings every mark shares
    (`_mark`/`_theme`/`_secondary_axis`/`_horizontal`, ...). A setting
    only one mark reads belongs in that mark's struct, not here (#522).

    **Call `mark_*()` before `encode_*()`.** Each encoder writes the
    columns for a particular set of marks and raises if the plot is not
    one of them, naming the encoder, the marks it serves and the mark
    the plot actually has (#538). `Plot()` starts at `Mark.POINT`, so a
    plain `encode()` needs no builder call. The reverse order used to
    work and no longer does: the check has to run where the mistake is,
    and at that point only the mark already set can be inspected.

    `Copyable`, not `ImplicitlyCopyable`: every field is a plain
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

    # Each mark setter binds its family for all four draw targets (#607).
    var _render_bounds_family: def(
        mut BoundsTarget, Plot, Int, Int, Int, Int, mut FontCache, Bool
    ) raises thin -> Optional[_RenderResult]
    var _render_canvas_family: def(
        mut Canvas, Plot, Int, Int, Int, Int, mut FontCache, Bool
    ) raises thin -> Optional[_RenderResult]
    var _render_pdf_family: def(
        mut PdfCanvas, Plot, Int, Int, Int, Int, mut FontCache, Bool
    ) raises thin -> Optional[_RenderResult]
    var _render_svg_family: def(
        mut SvgCanvas, Plot, Int, Int, Int, Int, mut FontCache, Bool
    ) raises thin -> Optional[_RenderResult]
    var _continuous: _ContinuousData
    var _categorical: _CategoricalData
    var _channels: _ChannelData
    var _y_err: _ErrorBarData
    var _waterfall: _WaterfallData
    var _box: _BoxData
    var _boxen: _BoxenData
    var _hexbin: _HexbinData
    var _stream: _StreamData
    var _histogram: _HistogramData
    var _candle: _CandleData
    var _bullet: _BulletData
    var _gantt: _GanttData
    var _grouped_bar: _GroupedBarData
    var _pyramid: _PyramidData
    var _heatmap: _HeatmapData
    var _edges: _EdgeData
    var _distribution: _DistributionData
    var _nightingale: _NightingaleData
    var _polar: _PolarData
    var _radar: _RadarData
    var _gauge: _GaugeData
    var _parallel: _ParallelData
    var _calendar: _CalendarData
    var _corrplot: _CorrplotData
    var _punchcard: _PunchcardData
    var _barbs: _BarbsData
    var _contour: _ContourData
    var _xyz: _Xyz
    var _surface: _Surface
    var _bars3d: _Bars3D
    var _voxels: _Voxels
    var _vectors3d: _Vectors3D
    var _ribbon3d: _Ribbon3D
    var _image: _ImageData
    var _tricontour: _TriContourData
    var _triplot: _TriplotData
    var _dendrogram: _DendrogramData
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
    # Set via .scale_y_symlog()/.scale_x_symlog(). The threshold is only
    # meaningful when the flag is set; both are carried onto the frame's
    # `LinearScale.is_symlog`/`symlog_linthresh` (#368).
    var _y_symlog: Bool
    var _x_symlog: Bool
    var _y_symlog_linthresh: Float64
    var _x_symlog_linthresh: Float64
    var _x_time: Bool
    """Whether `_continuous.x` holds POSIX seconds that the axis should label as
    dates and times. Set by `encode_time()`; carried onto the frame's
    `LinearScale.is_time`, which is the only thing that reads it."""
    var _x_tz_offset: Int
    """The offset from UTC, in seconds, of the timestamps in `_continuous.x`, so
    ticks land on local boundaries and read in the caller's zone."""
    # Set via .scale_x_domain()/.scale_y_domain().
    var _x_domain: _DomainOverride
    var _y_domain: _DomainOverride
    # Set via .scale_x_ticks()/.scale_y_ticks()/.scale_x_reverse()/
    # .scale_y_reverse()/.equal_aspect() (#368). All five reach the
    # continuous frame together as one `_AxisControls`; nothing else
    # reads them.
    var _x_tick_override: _TickOverride
    var _y_tick_override: _TickOverride
    var _x_reversed: Bool
    var _y_reversed: Bool
    var _equal_aspect: Bool
    # Set via .scale_color_domain()/.scale_color_center(); read by every
    # continuous-color mark through `_color_scale_for()`.
    var _color_domain: _ColorDomainOverride
    # Set only via a mark_*(horizontal=True) parameter; there is no
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
        self._continuous = _ContinuousData()
        self._categorical = _CategoricalData()
        self._channels = _ChannelData()
        self._y_err = _ErrorBarData()
        self._waterfall = _WaterfallData()
        self._box = _BoxData()
        self._boxen = _BoxenData()
        self._hexbin = _HexbinData()
        self._stream = _StreamData()
        self._histogram = _HistogramData()
        self._candle = _CandleData()
        self._bullet = _BulletData()
        self._gantt = _GanttData()
        self._grouped_bar = _GroupedBarData()
        self._pyramid = _PyramidData()
        self._heatmap = _HeatmapData()
        self._edges = _EdgeData()
        self._distribution = _DistributionData()
        self._nightingale = _NightingaleData()
        self._polar = _PolarData()
        self._radar = _RadarData()
        self._gauge = _GaugeData()
        self._parallel = _ParallelData()
        self._calendar = _CalendarData()
        self._corrplot = _CorrplotData()
        self._punchcard = _PunchcardData()
        self._barbs = _BarbsData()
        self._contour = _ContourData()
        self._xyz = _Xyz()
        self._surface = _Surface()
        self._bars3d = _Bars3D()
        self._voxels = _Voxels()
        self._vectors3d = _Vectors3D()
        self._ribbon3d = _Ribbon3D()
        self._image = _ImageData()
        self._tricontour = _TriContourData()
        self._triplot = _TriplotData()
        self._dendrogram = _DendrogramData()
        self._marimekko = _MarimekkoData()
        self._hierarchy = _HierarchyData()
        self._labels = _LabelData()
        self._annotations = _AnnotationData()
        self._mark_style = _MarkStyle()
        self._secondary_axis = False
        self._y_log = False
        self._x_log = False
        self._y_symlog = False
        self._x_symlog = False
        self._y_symlog_linthresh = 1.0
        self._x_symlog_linthresh = 1.0
        self._x_time = False
        self._x_tz_offset = 0
        self._x_domain = _DomainOverride()
        self._y_domain = _DomainOverride()
        self._x_tick_override = _TickOverride()
        self._y_tick_override = _TickOverride()
        self._x_reversed = False
        self._y_reversed = False
        self._equal_aspect = False
        self._color_domain = _ColorDomainOverride()
        self._horizontal = False
        self._mark = Mark.POINT
        self._render_canvas_family = _callback_continuous[Canvas]
        self._render_svg_family = _callback_continuous[SvgCanvas]
        self._render_pdf_family = _callback_continuous[PdfCanvas]
        self._render_bounds_family = _callback_continuous[BoundsTarget]
        self._theme = Theme.default()
        self.width = 640
        self.height = 420

    def size(var self, width: Int, height: Int) -> Self:
        """Set the dimensions `render()`/`render_svg()`/`save()` construct
        their target at. Defaults to 640x420.

        **The unit is a point, 1/72 inch**, which is what makes a figure
        size mean something physical (#372). On the raster backends one
        point is one pixel at the default resolution, so nothing about
        the old reading changes; `save(..., dpi=300)` keeps the physical
        size and multiplies the pixels. In a PDF it is a point on the
        page. `size_inches()`/`size_mm()` say the same thing in the
        units a page is usually specified in.

        Args:
            width: Figure width in points.
            height: Figure height in points.

        Returns:
            Self, for further chaining.
        """
        self.width = width
        self.height = height
        return self^

    def size_inches(var self, width: Float64, height: Float64) -> Self:
        """`size()` in inches: 72 points to the inch, rounded to whole
        points (#372).

        A figure for a journal column or a slide is specified
        physically, and `size(468, 312)` does not read as "6.5 by 4.3
        inches" to anyone.

        Args:
            width: Figure width in inches.
            height: Figure height in inches.

        Returns:
            Self, for further chaining.
        """
        self.width = Int(width * 72.0 + 0.5)
        self.height = Int(height * 72.0 + 0.5)
        return self^

    def size_mm(var self, width: Float64, height: Float64) -> Self:
        """`size()` in millimeters: 25.4 mm to the inch and 72 points to
        the inch, rounded to whole points (#372).

        Args:
            width: Figure width in millimeters.
            height: Figure height in millimeters.

        Returns:
            Self, for further chaining.
        """
        self.width = Int(width * 72.0 / 25.4 + 0.5)
        self.height = Int(height * 72.0 / 25.4 + 0.5)
        return self^

    def mark_point(
        var self,
        tooltips: Bool = False,
        jitter_x: Float64 = 0.0,
        jitter_y: Float64 = 0.0,
    ) raises -> Self:
        """A scatter plot: one point per (x, y) pair.

        When `tooltips` and `Theme.svg_tooltips` are enabled, each SVG point
        includes a hover title using its encoded label or coordinates.

        `jitter_x`/`jitter_y` offset each point by up to that many pixels,
        to separate points that would otherwise overplot. Both default
        to 0.0, which leaves every point exactly where it was.

        The offset is **deterministic, not random**: point `i` moves by
        `(2 * frac(i * phi) - 1) * jitter`, where `phi` is the golden
        ratio's conjugate. That spreads successive points evenly rather
        than clumping the way sampling does, is hand-derivable in a test,
        and gives the same picture on every render, which a seeded
        generator would only give for a fixed seed. See
        `_jitter_offset()`.

        Jitter is a *visual* device. It moves points away from their data
        positions on purpose, so a reader cannot recover exact values from
        a jittered chart, and it should not be used where they need to.

        Args:
            tooltips: Whether each point carries a hover `<title>`.
            jitter_x: Half-width in pixels of the x offset; 0.0 is off.
            jitter_y: The same for y.

        Returns:
            Self, for further chaining.

        Raises:
            Error: Either jitter is negative.
        """
        if jitter_x < 0.0 or jitter_y < 0.0:
            raise Error(
                "Plot.mark_point(): jitter must not be negative -- got"
                " jitter_x="
                + String(jitter_x)
                + ", jitter_y="
                + String(jitter_y)
            )
        self._mark = Mark.POINT
        self._render_canvas_family = _callback_continuous[Canvas]
        self._render_svg_family = _callback_continuous[SvgCanvas]
        self._render_pdf_family = _callback_continuous[PdfCanvas]
        self._render_bounds_family = _callback_continuous[BoundsTarget]
        self._mark_style.point_tooltips = tooltips
        self._mark_style.point_jitter_x = jitter_x
        self._mark_style.point_jitter_y = jitter_y
        return self^

    def mark_line(
        var self,
        style: LineStyle = LineStyle.SOLID,
        step: StepStyle = StepStyle.NONE,
    ) -> Self:
        """A line plot: (x, y) pairs connected in data order, not sorted by x.
        Sort the data first if that isn't the order to draw.

        `step` holds each value flat before jumping to the next. It is
        mutually exclusive with `Theme.line_smoothing`.

        Args:
            style: How the stroke is broken up -- `SOLID` (the default),
                `DASHED`, `DOTTED` or `DASH_DOT`. Useful for telling
                series apart without relying on color, which matters in
                print and for readers who cannot separate the palette.
            step: Where the riser between two samples sits -- `NONE`
                (the default: a straight segment, no stepping), `PRE`
                (at the earlier x), `MID` (halfway) or `POST` (at the
                later x); see `StepStyle` for which one claims what.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.LINE
        self._render_canvas_family = _callback_continuous[Canvas]
        self._render_svg_family = _callback_continuous[SvgCanvas]
        self._render_pdf_family = _callback_continuous[PdfCanvas]
        self._render_bounds_family = _callback_continuous[BoundsTarget]
        self._mark_style.line_style = style
        self._mark_style.step = step
        return self^

    def mark_bar(var self, horizontal: Bool = False) -> Self:
        """A bar chart: one bar per category, encoded via `encode_categorical()`.

                `horizontal` (default `False`) draws categories top-to-bottom along
                the y-axis with each bar extending from a zero baseline to the right
        , via `_draw_horizontal_categorical_axis_frame` (gantt.mojo);
                see `_render_horizontal_bar` (bar.mojo).
        """
        self._mark = Mark.BAR
        self._render_canvas_family = _callback_basic[Canvas]
        self._render_svg_family = _callback_basic[SvgCanvas]
        self._render_pdf_family = _callback_basic[PdfCanvas]
        self._render_bounds_family = _callback_basic[BoundsTarget]
        self._horizontal = horizontal
        return self^

    def mark_area(var self, step: StepStyle = StepStyle.NONE) -> Self:
        """An area chart: `mark_line()`'s continuous (x, y) pairs, filled from
        each point down to a zero baseline. Encoded via `encode()`.

        `step` applies the same interpolation as `mark_line()` to the
        fill's top edge. The closing segments to and along the baseline
        remain straight. Stepping is mutually exclusive with
        `Theme.line_smoothing`.

        Args:
            step: Where the riser between two samples sits -- `NONE`
                (the default: a straight top edge, no stepping), `PRE`
                (at the earlier x), `MID` (halfway) or `POST` (at the
                later x); see `StepStyle` for which one claims what. Mutually
                exclusive with `Theme.line_smoothing`, which raises.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.AREA
        self._render_canvas_family = _callback_continuous[Canvas]
        self._render_svg_family = _callback_continuous[SvgCanvas]
        self._render_pdf_family = _callback_continuous[PdfCanvas]
        self._render_bounds_family = _callback_continuous[BoundsTarget]
        self._mark_style.step = step
        return self^

    def mark_histogram(var self, horizontal: Bool = False) -> Self:
        """A histogram drawn as one rectangle per bin at numeric x
        positions, with a separator between adjacent bins
        (`Theme.histogram_edge_color`); `horizontal` puts the bins up
        the y-axis and the values running right. Encoded via
        `encode_histogram_bins()`; see `_draw_histogram_layer`
        (histogram.mojo) for the drawing and `histogram()` for the
        one-call form. Follows `Mark.AREA`'s rules everywhere else: a
        zero-baselined y-domain, `render_layers()` and
        `render_facets(shared_y_scale=True)` support, no log y-axis.
        A horizontal histogram keeps the bins' range on y (pin it with
        `scale_y_domain()`) and zero-baselines x instead;
        `render_layers()` refuses it.

        Args:
            horizontal: Bins up the y-axis, values running right.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.HISTOGRAM
        self._render_canvas_family = _callback_continuous[Canvas]
        self._render_svg_family = _callback_continuous[SvgCanvas]
        self._render_pdf_family = _callback_continuous[PdfCanvas]
        self._render_bounds_family = _callback_continuous[BoundsTarget]
        self._histogram.horizontal = horizontal
        return self^

    def mark_arc(var self, inner_radius_fraction: Float64 = 0.0) -> Self:
        """A pie chart: one wedge per category, its angular span proportional to
        its value, encoded via `encode_categorical()`. Every value must be
        non-negative and at least one positive, checked at render() time.
        `inner_radius_fraction > 0.0` (in `[0.0, 1.0)`) makes a donut.
        """
        self._mark = Mark.ARC
        self._render_canvas_family = _callback_basic[Canvas]
        self._render_svg_family = _callback_basic[SvgCanvas]
        self._render_pdf_family = _callback_basic[PdfCanvas]
        self._render_bounds_family = _callback_basic[BoundsTarget]
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
        self._render_canvas_family = _callback_radial[Canvas]
        self._render_svg_family = _callback_radial[SvgCanvas]
        self._render_pdf_family = _callback_radial[PdfCanvas]
        self._render_bounds_family = _callback_radial[BoundsTarget]
        self._nightingale.area = area
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
        self._render_canvas_family = _callback_radial[Canvas]
        self._render_svg_family = _callback_radial[SvgCanvas]
        self._render_pdf_family = _callback_radial[PdfCanvas]
        self._render_bounds_family = _callback_radial[BoundsTarget]
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
        self._render_canvas_family = _callback_radial[Canvas]
        self._render_svg_family = _callback_radial[SvgCanvas]
        self._render_pdf_family = _callback_radial[PdfCanvas]
        self._render_bounds_family = _callback_radial[BoundsTarget]
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
        self._render_canvas_family = _callback_radial[Canvas]
        self._render_svg_family = _callback_radial[SvgCanvas]
        self._render_pdf_family = _callback_radial[PdfCanvas]
        self._render_bounds_family = _callback_radial[BoundsTarget]
        self._mark_style.polar_grid_rings = grid_rings
        self._mark_style.polar_grid_spokes = grid_spokes
        return self^

    def mark_radar(var self, grid_rings: Int = 4) -> Self:
        """A radar/spider chart: one spoke per named indicator, one polygon per
        named series, with `grid_rings` web rings. Encoded via
        `encode_radar()`.
        """
        self._mark = Mark.RADAR
        self._render_canvas_family = _callback_radial[Canvas]
        self._render_svg_family = _callback_radial[SvgCanvas]
        self._render_pdf_family = _callback_radial[PdfCanvas]
        self._render_bounds_family = _callback_radial[BoundsTarget]
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
        self._render_canvas_family = _callback_radial[Canvas]
        self._render_svg_family = _callback_radial[SvgCanvas]
        self._render_pdf_family = _callback_radial[PdfCanvas]
        self._render_bounds_family = _callback_radial[BoundsTarget]
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
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        return self^

    def mark_pointplot(var self, horizontal: Bool = False) -> Self:
        """Use `Mark.POINTPLOT`: one point per category at its value, with
        `encode_categorical()`'s `y_err_lower`/`y_err_upper` as a whisker
        and a line joining the points -- the glyph `pointplot()` draws
        for an estimate per category. The value axis follows the data
        rather than starting at zero; see `_pointplot_value_extent`.

        Args:
            horizontal: Run the categories down the page and the values
                rightward, for long category names.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.POINTPLOT
        self._horizontal = horizontal
        self._render_canvas_family = _callback_aggregation[Canvas]
        self._render_svg_family = _callback_aggregation[SvgCanvas]
        self._render_pdf_family = _callback_aggregation[PdfCanvas]
        self._render_bounds_family = _callback_aggregation[BoundsTarget]
        return self^

    def mark_lollipop(var self, horizontal: Bool = False) -> Self:
        """A lollipop chart: one stem-plus-point per category, encoded via
        `encode_categorical()` (the same data as `mark_bar()`). `horizontal`
        (default `False`) draws categories top-to-bottom with each stem
        extending to the right; see `_render_horizontal_lollipop`
        (lollipop.mojo).
        """
        self._mark = Mark.LOLLIPOP
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        self._horizontal = horizontal
        return self^

    def mark_waterfall(
        var self,
        delta_width_fraction: Float64 = 0.6,
        horizontal: Bool = False,
    ) -> Self:
        """A waterfall chart: one floating bar per category, each running from
        the previous running total to the next. Encoded via
        `encode_waterfall()` (a category plus a signed delta).
        `delta_width_fraction` is a delta bar's width as a fraction of the
        band, applied only when `is_total` rows are in use.
        """
        self._mark = Mark.WATERFALL
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        self._mark_style.waterfall_delta_width_fraction = delta_width_fraction
        self._horizontal = horizontal
        return self^

    def mark_boxenplot(var self, horizontal: Bool = False) -> Self:
        """Use `Mark.BOXENPLOT`: a letter-value plot -- `Mark.BOX` with
        nested boxes at successively finer quantiles instead of one box
        and two whiskers -- over `encode_boxenplot()`. `horizontal`
        draws categories top-to-bottom; see `_render_boxenplot`
        (boxen.mojo).

        Args:
            horizontal: Categories on the y-axis, values on the x-axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.BOXENPLOT
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        self._horizontal = horizontal
        return self^

    def mark_box(var self, horizontal: Bool = False) -> Self:
        """A box plot: one box-and-whiskers per category summarizing a
        distribution of raw values. Encoded via `encode_boxplot()`, which
        computes quartiles/whiskers/outliers immediately. `horizontal`
        (default `False`) draws categories top-to-bottom with each box
        left-to-right; see `_render_horizontal_box` (box.mojo).
        """
        self._mark = Mark.BOX
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        self._horizontal = horizontal
        return self^

    def mark_candlestick(var self) -> Self:
        """A candlestick chart: one open/high/low/close bar per category.
        Encoded via `encode_candlestick()`.
        """
        self._mark = Mark.CANDLESTICK
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        return self^

    def mark_bullet(
        var self,
        measure_width_fraction: Float64 = 0.35,
        horizontal: Bool = False,
    ) -> Self:
        """A bullet chart (Stephen Few's design): a measure bar, a target tick,
        and qualitative-range bands per category. Encoded via
        `encode_bullet()`. `measure_width_fraction` is the measure bar's
        width as a fraction of the band.
        """
        self._mark = Mark.BULLET
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        self._mark_style.bullet_measure_width_fraction = measure_width_fraction
        self._horizontal = horizontal
        return self^

    def mark_gantt(var self) -> Self:
        """A gantt chart: one horizontal bar per category from a start value to
        an end value, with categories along the y-axis. Encoded via
        `encode_gantt()`. See `mark_span_chart()` for the same data drawn
        vertically.
        """
        self._mark = Mark.GANTT
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        return self^

    def mark_span_chart(var self) -> Self:
        """A span chart: `mark_gantt()`'s mirror image, one floating vertical
        bar per category from a low value to a high value on the normal
        categorical x-axis. Encoded via `encode_gantt()`.
        """
        self._mark = Mark.SPAN_CHART
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        return self^

    def mark_calendar_heatmap(var self) -> Self:
        """A calendar heatmap: daily values in a GitHub-contributions-style
        grid, colored through a continuous gradient. Encoded via
        `encode_calendar()` (`"YYYY-MM-DD"` dates).
        """
        self._mark = Mark.CALENDAR_HEATMAP
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
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
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
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
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
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
                hemisphere convention.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.BARBS
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._barbs.length = length
        self._barbs.flip = flip
        return self^

    def mark_quiver(
        var self, scale: Float64 = 0.0, color_by_magnitude: Bool = False
    ) -> Self:
        """Select `Mark.QUIVER`: a vector field as arrows, one per point
        along `(u, v)` with length proportional to magnitude. Encoded via
        `encode_quiver()`; see `_render_quiver` (quiver.mojo) for the
        glyph and `quiver()` for the one-call form.

        Args:
            scale: Pixels per unit of magnitude before `Theme.scale`, or
                0 for the automatic rule (see `quiver()`).
            color_by_magnitude: Color each arrow by `hypot(u, v)`
                through the theme's ramp, with a color legend.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.QUIVER
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._barbs.scale = scale
        self._barbs.color_by_magnitude = color_by_magnitude
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
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
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
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._contour.level_count = levels
        return self^

    def mark_imshow(var self) -> Self:
        """A 2D array drawn as an image: one flat-colored cell per
        element, on continuous axes in row/column index units. Encoded
        via `encode_imshow()`; see `_render_image` for the drawing and
        `imshow()` (image.mojo) for the one-call form.

        Row 0 is at the *top* and the y-axis counts downward, which is
        the opposite of `mark_contour()` over the same grid -- see
        `imshow()`'s docstring for why an image and a sampled surface
        differ here.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.IMSHOW
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
        return self^

    def mark_pcolormesh(var self) -> Self:
        """`mark_imshow()` over cell boundaries the caller supplies, for a
        grid whose rows and columns are not evenly spaced. Encoded via
        `encode_pcolormesh()`; see `_render_image` for the drawing and
        `pcolormesh()` (image.mojo) for the one-call form.

        Row 0 is at the *bottom* here, unlike `mark_imshow()`: the edges
        are positions on a real axis rather than scanlines.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.PCOLORMESH
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
        return self^

    def mark_hist2d(var self) -> Self:
        """Select `Mark.HIST2D`: `(x, y)` points binned into a grid of
        counts and drawn as colored cells, empty cells left undrawn.
        Pair with `encode_hist2d()`; see `_render_image` for the
        drawing and `hist2d()` (hist2d.mojo) for the one-call form.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.HIST2D
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
        return self^

    def mark_hexbin(var self) -> Self:
        """Select `Mark.HEXBIN`: `(x, y)` points counted into a hexagonal
        lattice and drawn as colored hexagons, empty cells left undrawn.
        Pair with `encode_hexbin()`; see `_render_hexbin` (hexbin.mojo)
        for the drawing and `hexbin()` for the one-call form.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.HEXBIN
        self._render_canvas_family = _callback_binned[Canvas]
        self._render_svg_family = _callback_binned[SvgCanvas]
        self._render_pdf_family = _callback_binned[PdfCanvas]
        self._render_bounds_family = _callback_binned[BoundsTarget]
        return self^

    def mark_streamplot(
        var self,
        density: Float64 = 1.0,
        arrows: Bool = True,
        color_by_magnitude: Bool = False,
    ) -> Self:
        """Select `Mark.STREAMPLOT`: a vector field on a grid integrated
        into streamlines. Pair with `encode_streamplot()`; see
        `_render_streamplot` (streamplot.mojo) for the integrator and
        `streamplot()` for the one-call form.

        Args:
            density: Line spacing: the
                occupancy cells per axis over 30, so larger means more
                lines.
            arrows: Draw an arrowhead at the middle of each line.
            color_by_magnitude: Color each step by the local
                `hypot(u, v)` through the theme's ramp, with a legend.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.STREAMPLOT
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._stream.density = density
        self._stream.arrows = arrows
        self._stream.color_by_magnitude = color_by_magnitude
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
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._tricontour.level_count = levels
        return self^

    def mark_tricontourf(var self, levels: Int = 8) -> Self:
        """Filled bands over scattered samples: `mark_tricontour()`'s
        regions rather than its lines, over the same Delaunay
        triangulation and the same `encode_tricontour()` data. See
        `_render_tricontourf` for how they are painted and
        `tricontourf()` for the one-call form.

        Args:
            levels: How many levels to place when `encode_tricontour()` is
                not given an explicit list -- spaced evenly strictly
                inside the samples' own range. Must be positive.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.TRICONTOURF
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._tricontour.level_count = levels
        return self^

    def mark_dendrogram(var self, horizontal: Bool = False) -> Self:
        """Select `Mark.DENDROGRAM`: the merge tree agglomerative
        clustering produces, drawn as brackets. Encoded via
        `encode_dendrogram()`; see `dendrogram()` for the one-call form
        that clusters the rows for you (#355).

        Args:
            horizontal: Run the leaves down the y-axis with the brackets
                reaching right, for a tree that sits beside a matrix's
                rows rather than above its columns.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.DENDROGRAM
        self._render_canvas_family = _callback_hierarchy_marks[Canvas]
        self._render_svg_family = _callback_hierarchy_marks[SvgCanvas]
        self._render_pdf_family = _callback_hierarchy_marks[PdfCanvas]
        self._render_bounds_family = _callback_hierarchy_marks[BoundsTarget]
        self._dendrogram.horizontal = horizontal
        return self^

    def encode_dendrogram(
        var self,
        tree: Dendrogram,
        labels: List[String],
        horizontal: Bool = False,
    ) -> Self:
        """Give `Mark.DENDROGRAM` a merge tree from
        `dataviz.core.cluster.linkage()` and one label per leaf (#355).

        `labels` is in the tree's *leaf order*, not the caller's original
        row order, because that reordering is the whole point of
        clustering: `tree.leaf_order` says which original row each
        position holds.

        The tree is flattened here into three parallel lists, which is
        what the render walks. Ids are positions along the leaf axis for
        the leaves and `len(labels) + k` for merge `k`, and because
        `linkage()` returns its merges sorted so a node's children come
        first, one forward pass places every node.

        Args:
            tree: The merge tree.
            labels: One name per leaf, in leaf order.
            horizontal: Leaves down the y-axis rather than across the x.

        Returns:
            Self, for further chaining -- `render()` raises later if the
            tree and the labels disagree.
        """
        var left = List[Int](capacity=len(tree.merges))
        var right = List[Int](capacity=len(tree.merges))
        var height = List[Float64](capacity=len(tree.merges))
        # The tree names leaves by their original row index; the drawing
        # needs their position along the axis, which is where that row
        # sits in the leaf order.
        var position_of = List[Int](capacity=len(tree.leaf_order))
        for _ in range(len(tree.leaf_order)):
            position_of.append(0)
        for i in range(len(tree.leaf_order)):
            position_of[tree.leaf_order[i]] = i
        var n = len(tree.leaf_order)
        for m in tree.merges:
            left.append(position_of[m.left] if m.left < n else m.left)
            right.append(position_of[m.right] if m.right < n else m.right)
            height.append(m.height)
        self._dendrogram.left = left^
        self._dendrogram.right = right^
        self._dendrogram.height = height^
        self._dendrogram.labels = labels.copy()
        self._dendrogram.horizontal = horizontal
        return self^

    def mark_triplot(var self, show_points: Bool = True) -> Self:
        """The Delaunay triangulation of scattered points drawn as
        itself: every edge of the mesh, stroked once. Encoded via
        `encode_triplot()`; see `_render_triplot` (triplot.mojo) for the
        drawing and `triplot()` for the one-call form.

        Args:
            show_points: Draw a dot at every sample on top of the mesh.
                Defaults to `True`; `_render_triplot` says why.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.TRIPLOT
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        self._triplot.show_points = show_points
        return self^

    def mark_tripcolor(var self) -> Self:
        """Each triangle of the Delaunay mesh filled from the values at
        its three vertices -- `mark_triplot()`'s mesh painted rather than
        stroked, over the same `encode_triplot()` data, which must then
        carry `z`. See `_render_tripcolor` (triplot.mojo) for the flat
        shading and the seam handling, and `tripcolor()` for the one-call
        form.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.TRIPCOLOR
        self._render_canvas_family = _callback_multivariate[Canvas]
        self._render_svg_family = _callback_multivariate[SvgCanvas]
        self._render_pdf_family = _callback_multivariate[PdfCanvas]
        self._render_bounds_family = _callback_multivariate[BoundsTarget]
        return self^

    def mark_marimekko(var self) -> Self:
        """A Marimekko/mosaic chart: column widths proportional to each
        category's share of the grand total, stacked segment heights showing
        each column's subcategory composition. Encoded via
        `encode_marimekko()`.
        """
        self._mark = Mark.MARIMEKKO
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
        return self^

    def mark_sunburst(var self) -> Self:
        """A sunburst chart: a hierarchy as concentric rings, one ring per depth
        level, each node's angular span proportional to its share of its
        parent's total. Encoded via `encode_hierarchy()`.
        """
        self._mark = Mark.SUNBURST
        self._render_canvas_family = _callback_hierarchy_marks[Canvas]
        self._render_svg_family = _callback_hierarchy_marks[SvgCanvas]
        self._render_pdf_family = _callback_hierarchy_marks[PdfCanvas]
        self._render_bounds_family = _callback_hierarchy_marks[BoundsTarget]
        return self^

    def mark_tree(var self) -> Self:
        """A tree diagram: a hierarchy as a top-to-bottom node-link diagram.
        Encoded via `encode_hierarchy()`.
        """
        self._mark = Mark.TREE
        self._render_canvas_family = _callback_hierarchy_marks[Canvas]
        self._render_svg_family = _callback_hierarchy_marks[SvgCanvas]
        self._render_pdf_family = _callback_hierarchy_marks[PdfCanvas]
        self._render_bounds_family = _callback_hierarchy_marks[BoundsTarget]
        return self^

    def mark_treemap(var self) -> Self:
        """A treemap: a hierarchy as nested, area-proportional rectangles via
        slice-and-dice. Encoded via `encode_hierarchy()`.
        """
        self._mark = Mark.TREEMAP
        self._render_canvas_family = _callback_hierarchy_marks[Canvas]
        self._render_svg_family = _callback_hierarchy_marks[SvgCanvas]
        self._render_pdf_family = _callback_hierarchy_marks[PdfCanvas]
        self._render_bounds_family = _callback_hierarchy_marks[BoundsTarget]
        return self^

    def mark_grouped_bar(var self, horizontal: Bool = False) -> Self:
        """A grouped bar chart: several bars side by side per category, one per
        series. Encoded via `encode_grouped_bar()`. `horizontal` (default
        `False`) draws categories top-to-bottom with each row subdivided into
        equal-height sub-bars; see `_render_horizontal_grouped_bar`
        (grouped_bar.mojo).
        """
        self._mark = Mark.GROUPED_BAR
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        self._horizontal = horizontal
        return self^

    def mark_stacked_bar(
        var self, percent: Bool = False, horizontal: Bool = False
    ) -> Self:
        """A stacked bar chart: one bar per category, each series' value stacked
        as a segment on the previous running total. Encoded via
        `encode_grouped_bar()`, the same data as `mark_grouped_bar()`.

        `percent=True` normalizes each category's segments to sum to 100%,
        fixing the y-axis from 0 to 100.
        Every value must then be non-negative, checked at render() time; an
        all-zero category draws as an empty column.

        `horizontal` (default `False`) draws categories top-to-bottom with
        each category's segments stacked left-to-right; see
        `_render_horizontal_stacked_bar` (stacked_bar.mojo).

        Args:
            percent: `False` (the default) stacks raw values, an
                unchanged real-valued y-axis. `True` normalizes each
                category to 100% and fixes the y-axis from 0 to 100.
            horizontal: Draw categories running top-to-bottom with each
                category's segments stacked left-to-right instead of
                the default vertical layout.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.STACKED_BAR
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        self._grouped_bar.percent = percent
        self._horizontal = horizontal
        return self^

    def mark_population_pyramid(var self) -> Self:
        """A population pyramid: two magnitude bars per category growing outward
        left/right from a shared, centered zero baseline, on `Mark.GANTT`'s
        horizontal categorical frame. Encoded via
        `encode_population_pyramid()`.
        """
        self._mark = Mark.POPULATION_PYRAMID
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        return self^

    def mark_heatmap(var self) -> Self:
        """A heatmap: one colored grid cell per (x, y) category pair, on two
        categorical axes. Encoded via `encode_heatmap()`.
        """
        self._mark = Mark.HEATMAP
        self._render_canvas_family = _callback_grid[Canvas]
        self._render_svg_family = _callback_grid[SvgCanvas]
        self._render_pdf_family = _callback_grid[PdfCanvas]
        self._render_bounds_family = _callback_grid[BoundsTarget]
        return self^

    def mark_chord(var self, ring_fraction: Float64 = 0.08) -> Self:
        """A chord diagram: ring sectors for every distinct node across an edge
        list's `from`/`to` columns, connected by ribbons sized by each flow's
        value. Encoded via `encode_chord()`. `ring_fraction` is the rim's
        thickness as a fraction of the radius. No axis frame.
        """
        self._mark = Mark.CHORD
        self._render_canvas_family = _callback_relationships[Canvas]
        self._render_svg_family = _callback_relationships[SvgCanvas]
        self._render_pdf_family = _callback_relationships[PdfCanvas]
        self._render_bounds_family = _callback_relationships[BoundsTarget]
        self._mark_style.chord_ring_fraction = ring_fraction
        return self^

    def mark_arc_diagram(var self) -> Self:
        """An arc diagram: `mark_chord()`'s edge list drawn as nodes on one line
        connected by semicircular arcs. Encoded via `encode_chord()`.
        """
        self._mark = Mark.ARC_DIAGRAM
        self._render_canvas_family = _callback_relationships[Canvas]
        self._render_svg_family = _callback_relationships[SvgCanvas]
        self._render_pdf_family = _callback_relationships[PdfCanvas]
        self._render_bounds_family = _callback_relationships[BoundsTarget]
        return self^

    def mark_graph(var self) -> Self:
        """A network graph: `mark_chord()`'s edge list drawn as nodes evenly
        spaced around a circle connected by straight lines. Encoded via
        `encode_chord()`.
        """
        self._mark = Mark.GRAPH
        self._render_canvas_family = _callback_relationships[Canvas]
        self._render_svg_family = _callback_relationships[SvgCanvas]
        self._render_pdf_family = _callback_relationships[PdfCanvas]
        self._render_bounds_family = _callback_relationships[BoundsTarget]
        return self^

    def mark_sankey(var self, node_width: Float64 = 12.0) -> Self:
        """A Sankey diagram: `mark_chord()`'s edge list laid out left-to-right by
        column as proportionally sized flow ribbons between node bars
        `node_width` pixels wide (before `Theme.scale`). Encoded via
        `encode_chord()`; the edges must form a DAG.
        """
        self._mark = Mark.SANKEY
        self._render_canvas_family = _callback_relationships[Canvas]
        self._render_svg_family = _callback_relationships[SvgCanvas]
        self._render_pdf_family = _callback_relationships[PdfCanvas]
        self._render_bounds_family = _callback_relationships[BoundsTarget]
        self._mark_style.sankey_node_width = node_width
        return self^

    def mark_single_axis(var self, tooltips: Bool = False) -> Self:
        """A single-axis chart: every value plotted along one horizontal axis
        with no y-axis. Encoded via `encode_single_axis()`, with the same
        optional `color`/`color_categories`/`size` channels as `Mark.POINT`.

        `tooltips` works as in `mark_point()`, and for the same reason:
        this mark draws through `_draw_point_layer`, so a title per
        point doubles a dense chart's SVG and is opt-in (#683).

        Args:
            tooltips: Whether each point carries a hover `<title>`.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.SINGLE_AXIS
        self._mark_style.point_tooltips = tooltips
        self._render_canvas_family = _callback_basic[Canvas]
        self._render_svg_family = _callback_basic[SvgCanvas]
        self._render_pdf_family = _callback_basic[PdfCanvas]
        self._render_bounds_family = _callback_basic[BoundsTarget]
        return self^

    def mark_effect_scatter(var self, tooltips: Bool = False) -> Self:
        """A scatter plot with a halo drawn under each point, the static
        equivalent of ECharts' effect scatter (see `_draw_point_layer`'s
        `draw_halo`). Encoded like `Mark.POINT`, via `encode()`. `tooltips`
        works as in `mark_point()`.
        """
        self._mark = Mark.EFFECT_SCATTER
        self._render_canvas_family = _callback_continuous[Canvas]
        self._render_svg_family = _callback_continuous[SvgCanvas]
        self._render_pdf_family = _callback_continuous[PdfCanvas]
        self._render_bounds_family = _callback_continuous[BoundsTarget]
        self._mark_style.point_tooltips = tooltips
        return self^

    def mark_funnel(var self) -> Self:
        """A funnel chart: one tapering trapezoid per category, largest value
        first, with no axis frame. Encoded via `encode_categorical()`.
        """
        self._mark = Mark.FUNNEL
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        return self^

    def mark_bump(var self) -> Self:
        """A bump chart: one line per series tracking its rank (1 = highest
        value) among every series at each category. Encoded via
        `encode_grouped_bar()`.
        """
        self._mark = Mark.BUMP
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        return self^

    def mark_streamgraph(
        var self,
        baseline: StackBaseline = StackBaseline.WIGGLE,
        step: StepStyle = StepStyle.NONE,
    ) -> Self:
        """A streamgraph: `mark_stacked_bar()`'s running-total stack drawn
        as flowing bands rather than rects. Encoded via
        `encode_grouped_bar()`.

        `baseline` chooses where each category's stack starts.
        `WIGGLE` (the default) centers it on zero, the streamgraph
        proper. `ZERO` starts it at a flat zero, which is the ordinary
        stacked area chart -- `stacked_area()` is the name to reach for
        there. See `StackBaseline`.

        `step` is the same stairs interpolation `mark_line()` and
        `mark_area()` takes, applied to every band's top
        and bottom edge: the composition holds flat and then
        jumps, instead of sliding from one category to the next. It is
        the shape for a stacked quantity that is constant between
        readings -- capacity by source, headcount by team, inventory by
        warehouse.

        Both edges of a band step, in the same style, or the stack
        stops tiling: band `j`'s bottom edge *is* band `j - 1`'s top
        edge, and two edges that disagree about where the riser goes
        leave a wedge of background between the bands. See
        `_render_streamgraph` for how the reversed bottom edge is kept
        in step with the forward top one.

        Args:
            baseline: Where each category's stack starts -- `WIGGLE`
                (centered on zero) or `ZERO` (a flat baseline).
            step: Where the riser between two categories sits --
                `NONE` (the default: straight segments), `PRE` (at the
                earlier category), `MID` (halfway) or `POST` (at the
                later one). Mutually exclusive with
                `Theme.line_smoothing`, which raises. `streamgraph()`
                defaults that to `0.6`, so a stepped stream would raise
                on its own default; `stacked_area()` is the one-call
                function that exposes this.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.STREAMGRAPH
        self._render_canvas_family = _callback_categorical[Canvas]
        self._render_svg_family = _callback_categorical[SvgCanvas]
        self._render_pdf_family = _callback_categorical[PdfCanvas]
        self._render_bounds_family = _callback_categorical[BoundsTarget]
        self._mark_style.streamgraph_baseline = baseline
        self._mark_style.step = step
        return self^

    def mark_beeswarm(
        var self, horizontal: Bool = False, tooltips: Bool = False
    ) -> Self:
        """A beeswarm plot: one point per raw value, jittered sideways within
        its category's band. Encoded via `encode_distribution()`.
        `horizontal` (default `False`) draws categories top-to-bottom with
        each swarm jittered vertically; see
        `_render_horizontal_beeswarm` (beeswarm.mojo). `tooltips` works as in
        `mark_point()`.
        """
        self._mark = Mark.BEESWARM
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
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
        `sqrt(n_i / max(n))` instead of giving every category the same
        maximum width.

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
                `mark_bar(horizontal=True)`'s own flip -- draws
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
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        self._distribution.kde_bandwidth_override = bandwidth
        self._distribution.kde_scale_by_count = scale_by_count
        self._horizontal = horizontal
        self._mark_style.violin_width_fraction = width_fraction
        return self^

    def mark_kde(
        var self,
        bandwidth: Float64 = 0.0,
        fill: Bool = False,
        rug: Bool = False,
    ) -> Self:
        """A kernel-density curve over raw observations: `mark_violin()`'s
        estimate drawn on a continuous frame -- value across, density up
        -- rather than mirrored inside a category band. Encoded via
        `encode_kde()`; see `kdeplot()` for the one-call form.

        Comparing several distributions on one frame is
        `render_layers()` over a `Mark.KDE` layer each: they
        share one density axis, so the peak heights are comparable.
        `rug=True` adds this layer's own observations underneath, and a
        separate `mark_rug()` layer draws the same ticks.

        Args:
            bandwidth: The kernel bandwidth. Not positive (the default)
                uses Silverman's rule. This is the parameter that
                changes the conclusion -- the same sample can show one
                mode or three depending on it -- so it is worth setting
                deliberately rather than trusting the default.
            fill: Shade the curve down to zero as well as stroking it.
            rug: Draw each observation as a short tick along the
                baseline. A density curve is smooth everywhere, including
                where nothing was observed, so the rug is what shows
                where the sample actually is.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.KDE
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        self._distribution.kde_bandwidth_override = bandwidth
        self._distribution.kde_fill = fill
        self._distribution.kde_rug = rug
        return self^

    def mark_rug(var self) -> Self:
        """One short tick per observation along the x axis. Encoded via
        `encode_kde()`; see `rugplot()` for the one-call form.

        The same ticks `mark_kde(rug=True)` draws under its curve, as a
        chart of their own -- or as a `render_layers()` layer under a
        `mark_kde()` one, which draws the same thing.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.RUG
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        return self^

    def mark_ecdf(var self, complementary: Bool = False) -> Self:
        """An empirical cumulative distribution: the fraction of
        observations at or below each x, as a staircase rising from 0 to
        1. Encoded via `encode_ecdf()`; see `ecdf()` for the one-call
        form.

        The one distribution chart with no parameter that can change the
        conclusion -- no bin width (`histogram()`), no bandwidth
        (`mark_kde()`). Ties share a single step of `k/n`, and the curve
        is drawn over the data's own range rather than out to the axis
        edges; both are `_ecdf_points()`'s doing (ecdf.mojo), which
        documents why.

        Comparing two distributions on one frame is the main reason to
        draw an ECDF, and `render_layers()` takes this mark: two ECDF
        layers share one frame with the proportion axis pinned to `[0, 1]`.

        Args:
            complementary: Draw `1 - F(x)` (the survival function,
                falling from 1 to 0) instead of `F(x)`. What
                reliability and survival work reads: "what fraction
                lasted longer than this".

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.ECDF
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        self._distribution.ecdf_complementary = complementary
        return self^

    def mark_eventplot(var self, line_length: Float64 = 1.0) -> Self:
        """A raster plot: one row of tick marks per series, each tick at
        the position of one event. Encoded via `encode_eventplot()`; see
        `eventplot()` for the one-call form.

        `Mark.RUG` drawn once per row, against a categorical y-axis --
        the chart for things that *happen* rather than things that have
        a value. Every event is drawn where it happened; nothing is
        bucketed the way `histogram()`/`punchcard()`/
        `calendar_heatmap()` bucket it.

        Args:
            line_length: Each tick's height as a fraction of its row's
                band, defaulting to `1.0` (the full band). Below 1.0
                opens a gap between rows, which is the one lever
                against crowding that does not drop an event -- checked
                at render() time, and must be positive.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.EVENTPLOT
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
        self._mark_style.eventplot_line_length = line_length
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
        self._render_canvas_family = _callback_distributions[Canvas]
        self._render_svg_family = _callback_distributions[SvgCanvas]
        self._render_pdf_family = _callback_distributions[PdfCanvas]
        self._render_bounds_family = _callback_distributions[BoundsTarget]
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
        shape_map: Dict[String, PointShape] = Dict[String, PointShape](),
        labels: List[String] = List[String](),
    ) raises -> Self:
        """Map data columns onto channels. `x`/`y` are required; the optional
        channels must match their length, checked at render() time (a
        builder method can't raise mid-chain).

        `color` (continuous, through a `ColorScale` over the column's
        its minimum and maximum) and `color_categories` (discrete, through
        `categorical_palette_for(theme)` by first-seen order of the unique
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
                `ColorScale` spanning the column's minimum and maximum;
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
            shape_map: Optional explicit category-to-shape overrides,
                used only under `Theme.shape_by_category`. A category
                absent here takes the shape for its index.
                `shared_shape_map()` builds one covering a whole figure
                so a category missing from one panel does not shift the
                shapes of the others (#365).
            labels: Optional per-point text, drawn above each point;
                an entry of `""` skips that one point's label.
                `Mark.POINT`/`EFFECT_SCATTER` only.

        Returns:
            Self, for further chaining.

        See the Cookbook's own "Error Bars" recipe (docs/src/
        cookbook_recipes/error_bars.mojo) for a full worked example.
        """
        var _ok_encode = List[Mark]()
        _ok_encode.append(Mark.POINT)
        _ok_encode.append(Mark.LINE)
        _ok_encode.append(Mark.AREA)
        _ok_encode.append(Mark.EFFECT_SCATTER)
        _require_mark(self._mark, "encode", "mark_point()", _ok_encode^)
        self._continuous.x = x.copy()
        self._continuous.y = y.copy()
        self._categorical.x = List[String]()
        self._channels.color = color.copy()
        self._channels.color_categories = color_categories.copy()
        self._channels.size = size.copy()
        self._y_err.symmetric = y_err.copy()
        self._y_err.lower = y_err_lower.copy()
        self._y_err.upper = y_err_upper.copy()
        self._channels.color_map = color_map.copy()
        self._channels.shape_map = shape_map.copy()
        self._channels.point_labels = labels.copy()
        return self^

    def encode[
        TX: Float64Sequence, TY: Float64Sequence
    ](
        var self,
        x: TX,
        y: TY,
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
        color_map: Dict[String, Color] = Dict[String, Color](),
        shape_map: Dict[String, PointShape] = Dict[String, PointShape](),
        labels: List[String] = List[String](),
    ) raises -> Self:
        """`encode()`'s `x`/`y` generalized to anything conforming to
        `Float64Sequence` (array_like.mojo), for data in a custom buffer
        wrapper or a dataframe column type. A type's author has to declare
        the conformance; `List` itself and numpy arrays can't be retrofitted,
        which is why the concrete overload above still exists. `x` and `y`
        each take their own type parameter, so they need not be the same
        container type (#699). Materializes both via `_materialize_floats`
        and delegates to the concrete `encode()`.

        Args:
            x: The continuous x column, one entry per point --
                anything conforming to `Float64Sequence`.
            y: The continuous y column, one entry per point --
                anything conforming to `Float64Sequence`, not necessarily
                `x`'s type.
            color: See `encode()`'s own docstring -- unchanged here,
                still a concrete `List[Float64]`.
            color_categories: See `encode()`'s own docstring.
            size: See `encode()`'s own docstring.
            y_err: See `encode()`'s own docstring.
            y_err_lower: See `encode()`'s own docstring.
            y_err_upper: See `encode()`'s own docstring.
            color_map: See `encode()`'s own docstring.
            shape_map: See `encode()`'s own docstring.
            labels: See `encode()`'s own docstring.

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
            shape_map=shape_map,
            labels=labels,
        )

    def encode[
        x_dtype: DType, y_dtype: DType
    ](
        var self,
        x: List[Scalar[x_dtype]],
        y: List[Scalar[y_dtype]],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
        color_map: Dict[String, Color] = Dict[String, Color](),
        shape_map: Dict[String, PointShape] = Dict[String, PointShape](),
        labels: List[String] = List[String](),
    ) raises -> Self:
        """`encode()`'s `x`/`y` generalized over numeric element type
        (`List[Int]`, `List[Float32]`, any `List[Scalar[dtype]]`), a
        different axis from the `Float64Sequence` overload (element type
        rather than container type; see array_like.mojo for why this uses
        `DType` genericity rather than a trait). `x` and `y` each take their
        own element type, so `List[Int]` x against `List[Float64]` y works
        (#699). Materializes both via `_materialize_scalar_list` and
        delegates to the concrete `encode()`, which Mojo still picks
        directly when both are `List[Float64]`.

        Args:
            x: The continuous x column, one entry per point -- any
                numeric `List[Scalar[dtype]]`.
            y: The continuous y column, one entry per point -- any
                numeric `List[Scalar[dtype]]`, not necessarily `x`'s.
            color: See `encode()`'s own docstring -- unchanged here,
                still a concrete `List[Float64]`.
            color_categories: See `encode()`'s own docstring.
            size: See `encode()`'s own docstring.
            y_err: See `encode()`'s own docstring.
            y_err_lower: See `encode()`'s own docstring.
            y_err_upper: See `encode()`'s own docstring.
            color_map: See `encode()`'s own docstring.
            shape_map: See `encode()`'s own docstring.
            labels: See `encode()`'s own docstring.

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
            shape_map=shape_map,
            labels=labels,
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
        shape_map: Dict[String, PointShape] = Dict[String, PointShape](),
        labels: List[String] = List[String](),
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
            shape_map: See `encode()`'s own docstring.
            labels: See `encode()`'s own docstring.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode = List[Mark]()
        _ok_encode.append(Mark.POINT)
        _ok_encode.append(Mark.LINE)
        _ok_encode.append(Mark.AREA)
        _ok_encode.append(Mark.EFFECT_SCATTER)
        _require_mark(self._mark, "encode", "mark_point()", _ok_encode^)
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
            shape_map=shape_map,
            labels=labels,
        )

    def mark_scatter3d(
        var self,
        elev: Float64 = 30.0,
        azim: Float64 = -60.0,
        tooltips: Bool = False,
    ) -> Self:
        """Select `Mark.SCATTER3D`: one marker per (x, y, z), drawn in
        an orthographic projection of a viewing cube (#345).

        `elev` and `azim` are the view in degrees. They live on the
        mark rather than on `Theme` because a view angle belongs to
        this chart's data the way a domain override does, not to a
        house style.

        Encoded via `encode_xyz()`.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.SCATTER3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._xyz.elev = elev
        self._xyz.azim = azim
        self._mark_style.point_tooltips = tooltips
        return self^

    def mark_plot3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.PLOT3D`: the points joined in data order as one
        polyline through the cube (#345).

        Not depth sorted, and it cannot be: a polyline is one connected
        path, so reordering its segments by depth would reorder the
        line. A segment passing behind another is drawn over it when it
        comes later in the series.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.PLOT3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._xyz.elev = elev
        self._xyz.azim = azim
        return self^

    def mark_surface3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.SURFACE3D`: a height field over a regular grid,
        drawn as filled faces shaded by height (#345).

        Encoded via `encode_surface()`. `elev`/`azim` are the view in
        degrees, as on `mark_scatter3d()`.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.SURFACE3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._surface.elev = elev
        self._surface.azim = azim
        return self^

    def mark_wire3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.WIRE3D`: the same height field as
        `mark_surface3d()`, drawn as the lattice's lines with no fill
        (#345).

        Nothing is opaque, so nothing occludes anything and there is no
        depth sort to get wrong. The far side of the surface stays
        visible, which is the reason to pick this over a surface and
        also why a dense lattice reads as a thicket.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.WIRE3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._surface.elev = elev
        self._surface.azim = azim
        return self^

    def mark_trisurf3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.TRISURF3D`: a surface over scattered points,
        triangulated in the x-y plane and lifted to z (#345).

        Encoded via `encode_xyz()`, not `encode_surface()`: the input is
        three loose columns, not a grid.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.TRISURF3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._xyz.elev = elev
        self._xyz.azim = azim
        return self^

    def mark_stem3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.STEM3D`: a line from the base plane to each
        point, with a marker on the end (#345).

        Encoded via `encode_xyz()`. The tether is what a plain 3D
        scatter lacks: a floating marker's height cannot be read,
        because nothing says where under it the plane is.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.STEM3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._xyz.elev = elev
        self._xyz.azim = azim
        return self^

    def mark_quiver3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.QUIVER3D`: an arrow at each point, along its
        own components (#345).

        Encoded via `encode_vectors3d()`. The box is fitted to the
        tips as well as the tails, since an arrow leaving it would read
        as pointing at something outside the data.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.QUIVER3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._vectors3d.elev = elev
        self._vectors3d.azim = azim
        return self^

    def mark_fill_between3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.FILL_BETWEEN3D`: the ribbon joining two curves
        through space (#345).

        Encoded via `encode_ribbon3d()`. Sample `i` of one curve joins
        sample `i` of the other, so the pairing is the caller's rather
        than inferred.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.FILL_BETWEEN3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._ribbon3d.elev = elev
        self._ribbon3d.azim = azim
        return self^

    def mark_bar3d(
        var self,
        bar_width: Float64 = 0.8,
        bar_depth: Float64 = 0.8,
        elev: Float64 = 30.0,
        azim: Float64 = -60.0,
    ) -> Self:
        """Select `Mark.BAR3D`: one shaded box per sample, standing on
        the base plane (#345).

        Encoded via `encode_bars3d()`. The footprints are fractions of
        the closest spacing between two bars rather than absolute
        sizes, so a lattice of bars leaves a gap without the caller
        measuring their own grid.

        Args:
            bar_width: The bar's footprint along x, as a fraction of
                the closest spacing between two bars.
            bar_depth: The same along y.
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.BAR3D
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._bars3d.bar_width = bar_width
        self._bars3d.bar_depth = bar_depth
        self._bars3d.elev = elev
        self._bars3d.azim = azim
        return self^

    def mark_voxels(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Self:
        """Select `Mark.VOXELS`: a unit cube per filled cell of a solid
        occupancy grid (#345).

        Encoded via `encode_voxels()`. Faces between two filled cells
        are not drawn: they are inside the solid, so nothing outside it
        can see them.

        Args:
            elev: Degrees to look down on the scene from, above the
                x-y plane.
            azim: Degrees to turn the scene through, about the z axis.

        Returns:
            Self, for further chaining.
        """
        self._mark = Mark.VOXELS
        self._render_canvas_family = _callback_spatial[Canvas]
        self._render_svg_family = _callback_spatial[SvgCanvas]
        self._render_pdf_family = _callback_spatial[PdfCanvas]
        self._render_bounds_family = _callback_spatial[BoundsTarget]
        self._voxels.elev = elev
        self._voxels.azim = azim
        return self^

    def encode_vectors3d(
        var self,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        u: List[Float64],
        v: List[Float64],
        w: List[Float64],
    ) raises -> Self:
        """Give `Mark.QUIVER3D` its arrow tails and components (#345).

        The components are in the data's own units on each axis, so an
        arrow's length is read against the axes rather than against a
        separate legend.

        Length agreement is checked at render time, like every other
        encode method here.

        Args:
            x: The x coordinate of each arrow's tail.
            y: The y coordinate of each tail, the same length.
            z: The z coordinate of each tail, the same length.
            u: The x component of each arrow, the same length.
            v: The y component, the same length.
            w: The z component, the same length.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_vectors3d = List[Mark]()
        _ok_encode_vectors3d.append(Mark.QUIVER3D)
        _require_mark(
            self._mark,
            "encode_vectors3d",
            "mark_quiver3d()",
            _ok_encode_vectors3d^,
        )
        self._vectors3d.x = x.copy()
        self._vectors3d.y = y.copy()
        self._vectors3d.z = z.copy()
        self._vectors3d.u = u.copy()
        self._vectors3d.v = v.copy()
        self._vectors3d.w = w.copy()
        return self^

    def encode_ribbon3d(
        var self,
        x1: List[Float64],
        y1: List[Float64],
        z1: List[Float64],
        x2: List[Float64],
        y2: List[Float64],
        z2: List[Float64],
    ) raises -> Self:
        """Give `Mark.FILL_BETWEEN3D` the two curves it fills between
        (#345).

        Args:
            x1: The first curve's x column.
            y1: The first curve's y column, the same length.
            z1: The first curve's z column, the same length.
            x2: The second curve's x column, the same length.
            y2: The second curve's y column, the same length.
            z2: The second curve's z column, the same length.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_ribbon3d = List[Mark]()
        _ok_encode_ribbon3d.append(Mark.FILL_BETWEEN3D)
        _require_mark(
            self._mark,
            "encode_ribbon3d",
            "mark_fill_between3d()",
            _ok_encode_ribbon3d^,
        )
        self._ribbon3d.x1 = x1.copy()
        self._ribbon3d.y1 = y1.copy()
        self._ribbon3d.z1 = z1.copy()
        self._ribbon3d.x2 = x2.copy()
        self._ribbon3d.y2 = y2.copy()
        self._ribbon3d.z2 = z2.copy()
        return self^

    def encode_bars3d(
        var self,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises -> Self:
        """Give `Mark.BAR3D` its bar centers and heights (#345).

        `x` and `y` are each bar's center on the base plane, not a
        corner: a bar is read as a column over a position, and centers
        are what a lattice of positions gives you.

        Length agreement is checked at render time, like every other
        encode method here.

        Args:
            x: Each bar's center along x.
            y: Each bar's center along y, the same length.
            z: Each bar's height from the base plane, the same length.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_bars3d = List[Mark]()
        _ok_encode_bars3d.append(Mark.BAR3D)
        _require_mark(
            self._mark, "encode_bars3d", "mark_bar3d()", _ok_encode_bars3d^
        )
        self._bars3d.x = x.copy()
        self._bars3d.y = y.copy()
        self._bars3d.z = z.copy()
        return self^

    def encode_voxels(var self, filled: List[List[List[Bool]]]) raises -> Self:
        """Give `Mark.VOXELS` its occupancy grid (#345).

        Args:
            filled: `filled[layer][row][col]`, `True` where the cell is
                solid. Layers run up z, rows along y and columns along
                x -- `encode_surface()`'s order with a third index in
                front.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_voxels = List[Mark]()
        _ok_encode_voxels.append(Mark.VOXELS)
        _require_mark(
            self._mark, "encode_voxels", "mark_voxels()", _ok_encode_voxels^
        )
        self._voxels.filled = filled.copy()
        return self^

    def encode_surface(
        var self,
        z: List[List[Float64]],
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises -> Self:
        """Give a surface mark its height grid (#345).

        The grid is row-major (`z[row][col]`), rows along y and columns
        along x -- the same shape and the same optional coordinate
        columns as `encode_contour()`, so a field can be drawn either
        way without reshaping it.

        Shape is checked at render time, like every other encode method
        here.

        Args:
            z: The grid, rectangular and at least 2x2.
            x: One x coordinate per column. Empty leaves the axis in
                grid-index units.
            y: One y coordinate per row. Empty leaves the axis in
                grid-index units.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_surface = List[Mark]()
        _ok_encode_surface.append(Mark.SURFACE3D)
        _ok_encode_surface.append(Mark.WIRE3D)
        _require_mark(
            self._mark,
            "encode_surface",
            "mark_surface3d()",
            _ok_encode_surface^,
        )
        self._surface.z = z.copy()
        self._surface.x = x.copy()
        self._surface.y = y.copy()
        return self^

    def encode_xyz(
        var self,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises -> Self:
        """Give a 3D mark its three equal-length columns (#345).

        Each axis is normalised to the viewing cube independently, so
        one axis spanning nanometres and another kilometres come out the
        same size. A 3D box is a viewing volume rather than a shared
        unit, and scaling them together would collapse every axis but
        the largest.

        Length agreement is checked at render time, like every other
        encode method here.

        Args:
            x: The x column.
            y: The y column, the same length.
            z: The z column, the same length.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_xyz = List[Mark]()
        _ok_encode_xyz.append(Mark.SCATTER3D)
        _ok_encode_xyz.append(Mark.PLOT3D)
        _ok_encode_xyz.append(Mark.TRISURF3D)
        _ok_encode_xyz.append(Mark.STEM3D)
        _require_mark(
            self._mark, "encode_xyz", "mark_scatter3d()", _ok_encode_xyz^
        )
        self._xyz.x = x.copy()
        self._xyz.y = y.copy()
        self._xyz.z = z.copy()
        return self^

    def encode_categorical(
        var self,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises -> Self:
        """Map a categorical x column and a continuous y column onto the x/y
        channels, for `Mark.BAR` and the other category-plus-value marks.
        `x` is treated as the axis's category order as given, not
        deduplicated or re-sorted; repeated categories go through
        `encode_grouped_bar()`.

        `y_err`/`y_err_lower`/`y_err_upper` work exactly as they do on
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
        var _ok_encode_categorical = List[Mark]()
        _ok_encode_categorical.append(Mark.BAR)
        _ok_encode_categorical.append(Mark.LOLLIPOP)
        _ok_encode_categorical.append(Mark.POINTPLOT)
        _ok_encode_categorical.append(Mark.ARC)
        _ok_encode_categorical.append(Mark.FUNNEL)
        _ok_encode_categorical.append(Mark.NIGHTINGALE)
        _ok_encode_categorical.append(Mark.POLAR_BAR)
        _ok_encode_categorical.append(Mark.RADIALBAR)
        _require_mark(
            self._mark,
            "encode_categorical",
            "mark_bar()",
            _ok_encode_categorical^,
        )
        self._categorical.x = x.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = y.copy()
        self._y_err.symmetric = y_err.copy()
        self._y_err.lower = y_err_lower.copy()
        self._y_err.upper = y_err_upper.copy()
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
    ) raises -> Self:
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
    ) raises -> Self:
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
        var _ok_encode_categorical = List[Mark]()
        _ok_encode_categorical.append(Mark.BAR)
        _ok_encode_categorical.append(Mark.LOLLIPOP)
        _ok_encode_categorical.append(Mark.POINTPLOT)
        _ok_encode_categorical.append(Mark.ARC)
        _ok_encode_categorical.append(Mark.FUNNEL)
        _ok_encode_categorical.append(Mark.NIGHTINGALE)
        _ok_encode_categorical.append(Mark.POLAR_BAR)
        _ok_encode_categorical.append(Mark.RADIALBAR)
        _require_mark(
            self._mark,
            "encode_categorical",
            "mark_bar()",
            _ok_encode_categorical^,
        )
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
        """Bin values into equal-width intervals for a categorical bar chart.

        Args:
            data: Raw observations to bin.
            bins: Number of equal-width intervals.

        Returns:
            Self, for further chaining.

        Raises:
            Error: If data is empty, bins is not positive, or a value is not
                finite.
        """
        _require_mark(self._mark, "encode_histogram", "mark_bar()", Mark.BAR)
        var binned = _bin_histogram(data, bins)
        self._categorical.x = binned.labels.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = binned.counts.copy()
        return self^

    def encode_histogram(
        var self, data: List[Float64], rule: BinRule
    ) raises -> Self:
        """`encode_histogram` with the bin count chosen by `rule` rather
        than named -- `BinRule.AUTO` for numpy's `bins="auto"`. The
        overload `histogram()` and `bin_edges()` already have, so both
        histogram paths accept the same request (#456).

        Args:
            data: Raw observations to bin.
            rule: Which `BinRule` picks the bin count.

        Returns:
            Self, for further chaining.

        Raises:
            Error: If data is empty or a value is not finite.
        """
        _require_mark(self._mark, "encode_histogram", "mark_bar()", Mark.BAR)
        var binned = _bin_histogram(data, rule)
        self._categorical.x = binned.labels.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = binned.counts.copy()
        return self^

    def encode_waterfall(
        var self,
        categories: List[String],
        deltas: List[Float64],
        is_total: List[Bool] = List[Bool](),
    ) raises -> Self:
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
        non-empty) is checked at render() time. `deltas` is kept as `_continuous.y`
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
        _require_mark(
            self._mark, "encode_waterfall", "mark_waterfall()", Mark.WATERFALL
        )
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = deltas.copy()
        self._waterfall.is_total = is_total.copy()
        var bars = _waterfall_running_totals(deltas, is_total)
        self._waterfall.y0 = bars.y0.copy()
        self._waterfall.y1 = bars.y1.copy()
        return self^

    def encode_boxenplot(
        var self, categories: List[String], values: List[List[Float64]]
    ) raises -> Self:
        """Map a category column and, per category, a list of raw values
        onto `Mark.BOXENPLOT`'s nested boxes: the letter values are
        computed here, immediately, via `_letter_values()` (boxen.mojo)
        -- median, then quantile pairs at the quartiles, eighths,
        sixteenths and on, as many levels as the sample size supports,
        with every observation beyond the deepest pair as an outlier.

        Args:
            categories: One label per group.
            values: `values[i]` is every raw observation in
                `categories[i]`; each must be non-empty.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `categories` and `values` differ in length, or a
                group is empty.
        """
        _require_mark(
            self._mark, "encode_boxenplot", "mark_boxenplot()", Mark.BOXENPLOT
        )
        if len(categories) != len(values):
            raise Error(
                "Plot.encode_boxenplot(): categories and values must have"
                " the same length (got "
                + String(len(categories))
                + " and "
                + String(len(values))
                + ")"
            )
        var data = _BoxenData()
        for i in range(len(values)):
            if len(values[i]) == 0:
                raise Error(
                    "Plot.encode_boxenplot(): category "
                    + categories[i]
                    + " has no values -- a letter-value plot needs at least"
                    " one observation per category"
                )
            var lv = _letter_values(values[i])
            data.median.append(lv.median)
            data.lower.append(lv.lower.copy())
            data.upper.append(lv.upper.copy())
            for v in lv.outliers:
                data.outlier_cat.append(i)
                data.outlier_value.append(v)
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._boxen = data^
        return self^

    def encode_boxenplot[
        dtype: DType
    ](
        var self, categories: List[String], values: List[List[Scalar[dtype]]]
    ) raises -> Self:
        """`encode_boxenplot()`'s `values` generalized over numeric element
        type; see `encode_boxplot()`'s `DType` overload."""
        return self^.encode_boxenplot(
            categories, _materialize_nested_scalar_list(values)
        )

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
        _require_mark(self._mark, "encode_boxplot", "mark_box()", Mark.BOX)
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

        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
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
    ) raises -> Self:
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
        _require_mark(
            self._mark,
            "encode_candlestick",
            "mark_candlestick()",
            Mark.CANDLESTICK,
        )
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
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
    ) raises -> Self:
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
        _require_mark(self._mark, "encode_bullet", "mark_bullet()", Mark.BULLET)
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._bullet.measure = measures.copy()
        self._bullet.target = targets.copy()
        self._bullet.ranges = ranges.copy()
        return self^

    def encode_gantt(
        var self,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) raises -> Self:
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
        var _ok_encode_gantt = List[Mark]()
        _ok_encode_gantt.append(Mark.GANTT)
        _ok_encode_gantt.append(Mark.SPAN_CHART)
        _require_mark(
            self._mark, "encode_gantt", "mark_gantt()", _ok_encode_gantt^
        )
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._gantt.start = start.copy()
        self._gantt.end = end.copy()
        return self^

    def encode_grouped_bar(
        var self,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) raises -> Self:
        """Map a category column plus several value series onto
        `Mark.GROUPED_BAR`'s shape (also used by `STACKED_BAR`/`BUMP`/
        `STREAMGRAPH`): `values[j][i]` is series `series_names[j]`'s value
        for `categories[i]`. Length checking (`series_names`/`values`, and
        every `values[j]` against `categories`) is deferred to render() time.

        `errors`, left empty by default, is `values`' per-(series,
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
        var _ok_encode_grouped_bar = List[Mark]()
        _ok_encode_grouped_bar.append(Mark.GROUPED_BAR)
        _ok_encode_grouped_bar.append(Mark.STACKED_BAR)
        _ok_encode_grouped_bar.append(Mark.BUMP)
        _ok_encode_grouped_bar.append(Mark.STREAMGRAPH)
        _require_mark(
            self._mark,
            "encode_grouped_bar",
            "mark_grouped_bar()",
            _ok_encode_grouped_bar^,
        )
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
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
    ) raises -> Self:
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
    ) raises -> Self:
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
    ) raises -> Self:
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
        _require_mark(
            self._mark,
            "encode_population_pyramid",
            "mark_population_pyramid()",
            Mark.POPULATION_PYRAMID,
        )
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._pyramid.left = left_values.copy()
        self._pyramid.right = right_values.copy()
        self._pyramid.left_name = left_name
        self._pyramid.right_name = right_name
        return self^

    def encode_heatmap(
        var self, x: List[String], y: List[String], value: List[Float64]
    ) raises -> Self:
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
        _require_mark(
            self._mark, "encode_heatmap", "mark_heatmap()", Mark.HEATMAP
        )
        self._categorical.x = List[String]()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._heatmap.x = x.copy()
        self._heatmap.y = y.copy()
        self._heatmap.value = value.copy()
        return self^

    def encode_calendar(
        var self, dates: List[String], values: List[Float64]
    ) raises -> Self:
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
        _require_mark(
            self._mark,
            "encode_calendar",
            "mark_calendar_heatmap()",
            Mark.CALENDAR_HEATMAP,
        )
        self._categorical.x = List[String]()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._calendar.dates = dates.copy()
        self._calendar.values = values.copy()
        return self^

    def encode_corrplot(
        var self, variables: List[String], matrix: List[List[Float64]]
    ) raises -> Self:
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
        _require_mark(
            self._mark, "encode_corrplot", "mark_corrplot()", Mark.CORRPLOT
        )
        self._corrplot.variables = variables.copy()
        self._corrplot.matrix = matrix.copy()
        return self^

    def encode_corrplot[
        dtype: DType
    ](
        var self, variables: List[String], matrix: List[List[Scalar[dtype]]]
    ) raises -> Self:
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
    ) raises -> Self:
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
        _require_mark(
            self._mark, "encode_punchcard", "mark_punchcard()", Mark.PUNCHCARD
        )
        self._categorical.x = List[String]()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
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
    ) raises -> Self:
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
        # QUIVER is here because `encode_quiver()` delegates to this;
        # both marks read `_barbs`, differing only in the glyph drawn.
        var _ok_encode_barbs = List[Mark]()
        _ok_encode_barbs.append(Mark.BARBS)
        _ok_encode_barbs.append(Mark.QUIVER)
        _require_mark(
            self._mark, "encode_barbs", "mark_barbs()", _ok_encode_barbs^
        )
        self._categorical.x = List[String]()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
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
    ) raises -> Self:
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
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises -> Self:
        """Map a rectangular grid of values onto `Mark.CONTOUR`'s shape.

        `z` is row-major (`z[row][col]`): rows are the y axis and
        columns the x axis, with row 0 at the bottom.

        Without `x`/`y` the axes are in **grid-index units**, so a 10x20
        grid spans x from 0 to 19 and y from 0 to 9, unpadded, and the
        grid meets the plot rect's edges. With them the axes are in the
        caller's own units and get the same 5% padding every other
        continuous mark has, so a contour can share a frame with a
        scatter and mean the same thing by its x (#423). They are one
        value per column and per row, strictly increasing, and need not
        be evenly spaced.

        Shape checking (rectangular, at least 2x2) and the coordinate
        checks are deferred to render() time, like every other encode
        method here.

        Args:
            z: The grid, row-major and rectangular, at least 2x2.
            levels: The values to trace. Left empty (the default), the
                count from `mark_contour(levels=n)` decides how many
                are placed inside the data's range.
            x: One x coordinate per column of `z`, strictly increasing.
                Empty (the default) keeps grid-index units.
            y: One y coordinate per row of `z`, strictly increasing.
                Empty (the default) keeps grid-index units.

        Returns:
            Self, for further chaining.
        """
        var _ok_encode_contour = List[Mark]()
        _ok_encode_contour.append(Mark.CONTOUR)
        _ok_encode_contour.append(Mark.CONTOURF)
        _require_mark(
            self._mark, "encode_contour", "mark_contour()", _ok_encode_contour^
        )
        self._contour.z = z.copy()
        self._contour.levels = levels.copy()
        self._contour.x = x.copy()
        self._contour.y = y.copy()
        return self^

    def encode_imshow(var self, z: List[List[Float64]]) raises -> Self:
        """Map a 2D array onto `Mark.IMSHOW`'s shape.

        `z` is row-major (`z[row][col]`): rows are the y axis and columns
        the x axis. Cell centers sit on the integers, so an RxC array
        spans x `[-0.5, C - 0.5]` and y `[-0.5, R - 0.5]` -- the same
        grid-index units `encode_contour()` uses, extended by half a cell
        at each end because here a sample *is* a cell rather than a
        corner between cells.

        Row 0 is at the top; see `mark_imshow()`.

        Shape checking (rectangular, non-empty, all finite) is deferred
        to render() time, like every other encode method here.

        Args:
            z: The array, row-major and rectangular, non-empty.

        Returns:
            Self, for further chaining.
        """
        _require_mark(self._mark, "encode_imshow", "mark_imshow()", Mark.IMSHOW)
        self._image.z = z.copy()
        return self^

    def encode_pcolormesh(
        var self,
        x_edges: List[Float64],
        y_edges: List[Float64],
        z: List[List[Float64]],
    ) raises -> Self:
        """Map a 2D array plus its cell boundaries onto
        `Mark.PCOLORMESH`'s shape.

        `z` is row-major as in `encode_imshow()`. `x_edges`/`y_edges`
        *bound* the cells rather than sit at their centers, so there is
        one more of each than the array has columns and rows. Both must
        be strictly increasing.

        Length and ordering checks are deferred to render() time, like
        every other encode method here.

        Args:
            x_edges: Column boundaries, `cols + 1` of them, strictly
                increasing.
            y_edges: Row boundaries, `rows + 1` of them, strictly
                increasing.
            z: The array, row-major and rectangular, non-empty.

        Returns:
            Self, for further chaining.
        """
        _require_mark(
            self._mark,
            "encode_pcolormesh",
            "mark_pcolormesh()",
            Mark.PCOLORMESH,
        )
        self._image.z = z.copy()
        self._image.x_edges = x_edges.copy()
        self._image.y_edges = y_edges.copy()
        # The two forms are exclusive; see the curvilinear overload.
        self._image.x_corners = List[List[Float64]]()
        self._image.y_corners = List[List[Float64]]()
        return self^

    def encode_pcolormesh(
        var self,
        x_corners: List[List[Float64]],
        y_corners: List[List[Float64]],
        z: List[List[Float64]],
    ) raises -> Self:
        """Map a 2D array onto a *curvilinear* mesh: one coordinate per
        grid vertex rather than one boundary per row and column (#424).

        `x_corners`/`y_corners` are both `(rows + 1) x (cols + 1)`, so
        cell `(r, c)` is the quadrilateral through vertices `(r, c)`,
        `(r, c + 1)`, `(r + 1, c + 1)` and `(r + 1, c)`. That is what a
        rotated,
        sheared, polar or model-output grid needs: the 1D overload can
        only describe axis-aligned rectangles, because it sets column
        widths and row heights independently.

        Nothing is required of the shape beyond the vertex count. Cells
        may be non-convex or self-overlapping; they are drawn in row
        order and a later cell paints over an earlier one.

        Cell boundaries are antialiased rather than snapped to whole
        pixels, which the 1D form does. A quad has no rectangular
        outline to snap to, and neighbouring cells share an edge rather
        than a rectangle, so the run-merging the rectilinear path uses
        does not apply either. The visible effect is slightly softer
        cell edges; cell interiors are identical between the two forms
        for a mesh that could be described either way.

        Length checks are deferred to render() time, like every other
        encode method here.

        Args:
            x_corners: Vertex x coordinates, `(rows + 1) x (cols + 1)`.
            y_corners: Vertex y coordinates, the same shape.
            z: The array, row-major and rectangular, non-empty.

        Returns:
            Self, for further chaining.
        """
        _require_mark(
            self._mark,
            "encode_pcolormesh",
            "mark_pcolormesh()",
            Mark.PCOLORMESH,
        )
        self._image.z = z.copy()
        self._image.x_corners = x_corners.copy()
        self._image.y_corners = y_corners.copy()
        # Exclusive with the rectilinear form: a plot carrying both would
        # leave the renderer to guess which the caller meant.
        self._image.x_edges = List[Float64]()
        self._image.y_edges = List[Float64]()
        return self^

    def encode_time(var self, x: List[Morrow], y: List[Float64]) raises -> Self:
        """Map a time series: `x` as dates or timestamps, `y` as the
        continuous value at each.

        The axis is a `LinearScale` over POSIX seconds, so every
        continuous mark draws against it unchanged -- a time axis is a
        labeling problem, not a projection one. What changes is the
        ticks: they land on local midnights, month starts or year
        starts rather than on multiples of 50 days, and they read as
        dates (#195). See `_time_ticks` in scale.mojo.

        The zone is taken from the first value, and every tick is
        placed and labeled in it. Supplying a mix of zones is allowed --
        the positions are absolute instants either way -- but the axis
        will read in the first one's.

        Args:
            x: The timestamps, one per point.
            y: The value at each, one per `x`.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `morrow` could not convert a value to a timestamp.
        """
        var _ok_encode_time = List[Mark]()
        _ok_encode_time.append(Mark.POINT)
        _ok_encode_time.append(Mark.LINE)
        _ok_encode_time.append(Mark.AREA)
        _ok_encode_time.append(Mark.EFFECT_SCATTER)
        _require_mark(
            self._mark, "encode_time", "mark_line()", _ok_encode_time^
        )
        var seconds = List[Float64](capacity=len(x))
        for i in range(len(x)):
            seconds.append(x[i].timestamp())
        self._categorical.x = List[String]()
        self._continuous.x = seconds^
        self._continuous.y = y.copy()
        self._x_time = True
        if len(x) > 0:
            self._x_tz_offset = x[0].tz.offset
        return self^

    def encode_histogram_bins(var self, bins: HistogramBins) raises -> Self:
        """Map already-binned data onto `Mark.HISTOGRAM`'s shape: the
        bin edges and one value per bin, drawn as a rectangle each.

        The bins also go into `_continuous.x`/`_continuous.y` as the `step_x()`/
        `step_y()` staircase `Mark.AREA` would draw (swapped when the
        mark is horizontal, so call `mark_histogram()` first), so every rule that
        reads those columns -- the x/y domains, `render_layers()`'s
        combined domain, a facet grid's shared baseline -- works
        unchanged; only the drawing reads the edges and values.

        Args:
            bins: The binned sample, from `histogram_bins()` or built
                directly from edges and values.

        Returns:
            Self, for further chaining.
        """
        _require_mark(
            self._mark,
            "encode_histogram_bins",
            "mark_histogram()",
            Mark.HISTOGRAM,
        )
        self._categorical.x = List[String]()
        if self._histogram.horizontal:
            self._continuous.x = bins.step_y()
            self._continuous.y = bins.step_x()
        else:
            self._continuous.x = bins.step_x()
            self._continuous.y = bins.step_y()
        self._histogram.edges = bins.edges.copy()
        self._histogram.values = bins.values.copy()
        return self^

    def encode_hist2d(
        var self,
        x: List[Float64],
        y: List[Float64],
        x_edges: List[Float64],
        y_edges: List[Float64],
    ) raises -> Self:
        """Count `(x, y)` points into the grid `x_edges` by `y_edges`
        bound and map the counts onto `Mark.HIST2D`'s shape:
        `encode_pcolormesh()`'s cells, with empty ones left undrawn.

        The edges are yours, so the two axes can be binned differently
        or unevenly; `hist2d()` derives equal-width edges from the data
        for the common case. Binning is `_hist2d_counts`'s: a point on
        a shared boundary goes to the upper bin, the sample maximum to
        the last.

        Args:
            x: The horizontal coordinates.
            y: The vertical coordinates, one per `x`.
            x_edges: Column boundaries, strictly increasing, at least 2.
            y_edges: Row boundaries, strictly increasing, at least 2.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `x` and `y` differ in length, or an edge list is
                shorter than 2.
        """
        _require_mark(self._mark, "encode_hist2d", "mark_hist2d()", Mark.HIST2D)
        self._image.z = _hist2d_counts(x, y, x_edges, y_edges)
        self._image.x_edges = x_edges.copy()
        self._image.y_edges = y_edges.copy()
        self._image.blank_zero = True
        return self^

    def encode_streamplot(
        var self,
        x: List[Float64],
        y: List[Float64],
        u: List[List[Float64]],
        v: List[List[Float64]],
    ) raises -> Self:
        """Map a gridded vector field onto `Mark.STREAMPLOT`'s shape:
        `len(x)` column coordinates, `len(y)` row coordinates, and the
        two components at each node as `u[j][i]`/`v[j][i]`.

        The grid shape rather than `encode_barbs()`'s four flat columns,
        for the reason `_StreamData`'s docstring gives: a glyph reads
        the field only where it was sampled, an integrator reads it
        everywhere between. Checking is deferred to render time, like
        every other encoder here.

        Args:
            x: Column coordinates, ascending and evenly spaced.
            y: Row coordinates, ascending and evenly spaced.
            u: The x-component at each node.
            v: The y-component at each node, positive up the page.

        Returns:
            Self, for further chaining.
        """
        _require_mark(
            self._mark,
            "encode_streamplot",
            "mark_streamplot()",
            Mark.STREAMPLOT,
        )
        self._categorical.x = List[String]()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._stream.x = x.copy()
        self._stream.y = y.copy()
        self._stream.u = u.copy()
        self._stream.v = v.copy()
        return self^

    def encode_hexbin(
        var self, x: List[Float64], y: List[Float64], gridsize: Int = 30
    ) raises -> Self:
        """Map `(x, y)` points onto `Mark.HEXBIN`'s shape: the points
        themselves and the lattice width in cells. Binning happens at
        render time (`_hexbin_bins`), over the data's own bounding box.

        Args:
            x: The horizontal coordinates.
            y: The vertical coordinates, one per `x`.
            gridsize: Hexagons across the x range, at least 1.

        Returns:
            Self, for further chaining.
        """
        _require_mark(self._mark, "encode_hexbin", "mark_hexbin()", Mark.HEXBIN)
        self._hexbin.x = x.copy()
        self._hexbin.y = y.copy()
        self._hexbin.gridsize = gridsize
        return self^

    def encode_quiver(
        var self,
        x: List[Float64],
        y: List[Float64],
        u: List[Float64],
        v: List[Float64],
    ) raises -> Self:
        """Map `Mark.QUIVER`'s four channels: continuous `x`/`y` positions
        plus the `u`/`v` components of the vector at each, `v` positive
        up the page. The same shape as `encode_barbs()`, stored in the
        same place, since the two marks draw one field two ways.

        Args:
            x: The continuous x position of each arrow's tail.
            y: The continuous y position of each arrow's tail.
            u: Each vector's x-component, in the same unit as `v`.
            v: Each vector's y-component, positive pointing up the page.

        Returns:
            Self, for further chaining.
        """
        _require_mark(self._mark, "encode_quiver", "mark_quiver()", Mark.QUIVER)
        return self^.encode_barbs(x, y, u, v)

    def encode_quiver[
        dtype: DType
    ](
        var self,
        x: List[Scalar[dtype]],
        y: List[Scalar[dtype]],
        u: List[Scalar[dtype]],
        v: List[Scalar[dtype]],
    ) raises -> Self:
        """`encode_quiver()` generalized over numeric element type via
        `_materialize_scalar_list` (array_like.mojo). Delegates to the
        concrete overload.

        Args:
            x: The continuous x position of each arrow's tail.
            y: The continuous y position of each arrow's tail.
            u: Each vector's x-component -- any numeric `List[Scalar[dtype]]`.
            v: Each vector's y-component -- any numeric `List[Scalar[dtype]]`.

        Returns:
            Self, for further chaining.
        """
        return self^.encode_quiver(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(u),
            _materialize_scalar_list(v),
        )

    def encode_tricontour(
        var self,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        levels: List[Float64] = List[Float64](),
    ) raises -> Self:
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
        var _ok_encode_tricontour = List[Mark]()
        _ok_encode_tricontour.append(Mark.TRICONTOUR)
        _ok_encode_tricontour.append(Mark.TRICONTOURF)
        _require_mark(
            self._mark,
            "encode_tricontour",
            "mark_tricontour()",
            _ok_encode_tricontour^,
        )
        self._tricontour.x = x.copy()
        self._tricontour.y = y.copy()
        self._tricontour.z = z.copy()
        self._tricontour.levels = levels.copy()
        return self^

    def encode_triplot(
        var self,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64] = List[Float64](),
        triangulation: Triangulation = Triangulation(),
        facecolors: List[Float64] = List[Float64](),
        gouraud: Bool = False,
    ) raises -> Self:
        """Map scattered `(x, y)` positions -- and, for
        `Mark.TRIPCOLOR`, a value at each -- onto the triangulation
        marks' shape.

        `encode_tricontour()`'s columns without the level list. `z` is
        optional because `Mark.TRIPLOT` draws connectivity and nothing
        else, so requiring a value column there would mean inventing one;
        `Mark.TRIPCOLOR` needs it and says so at render time, like every
        other length check in this package.

        Args:
            x: Each sample's x position.
            y: Each sample's y position, one per `x` entry.
            z: The value at each sample, one per `x` entry. Left empty
                (the default) for `Mark.TRIPLOT`.
            triangulation: A `Triangulation` to draw instead of
                computing one from `x`/`y`. Empty (the default)
                triangulates internally, as before.
            facecolors: One value per *triangle*. Empty (the default)
                colors
                each triangle by the mean of its vertices' `z`.
            gouraud: Interpolate each face's color across it from its
                three vertices instead of filling it flat (#398).
                `Mark.TRIPCOLOR` only.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `facecolors` without a `triangulation`, or `gouraud`
                together with `facecolors`.
        """
        if gouraud and len(facecolors) > 0:
            raise Error(
                "Plot.encode_triplot(): facecolors is one value per triangle,"
                " so gouraud=True has nothing to interpolate between. Pass"
                " one or the other"
            )
        if len(facecolors) > 0 and triangulation.count() == 0:
            raise Error(
                "Plot.encode_triplot(facecolors=...): needs a triangulation"
                " to index against. Without one this package computes the"
                " triangles itself, in an order that is an artifact of the"
                " insertion sequence and not predictable from outside, so"
                " a per-triangle column would be assigned arbitrarily."
                " Pass triangulation=delaunay(x, y), or build a"
                " Triangulation from your own triangle list (#397)"
            )
        var _ok_encode_triplot = List[Mark]()
        _ok_encode_triplot.append(Mark.TRIPLOT)
        _ok_encode_triplot.append(Mark.TRIPCOLOR)
        _require_mark(
            self._mark, "encode_triplot", "mark_triplot()", _ok_encode_triplot^
        )
        self._triplot.x = x.copy()
        self._triplot.y = y.copy()
        self._triplot.z = z.copy()
        self._triplot.triangulation = triangulation.copy()
        self._triplot.facecolors = facecolors.copy()
        self._triplot.gouraud = gouraud
        return self^

    def encode_marimekko(
        var self,
        categories: List[String],
        subcategories: List[String],
        values: List[List[Float64]],
    ) raises -> Self:
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
        _require_mark(
            self._mark, "encode_marimekko", "mark_marimekko()", Mark.MARIMEKKO
        )
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
    ) raises -> Self:
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
    ) raises -> Self:
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
        var _ok_encode_hierarchy = List[Mark]()
        _ok_encode_hierarchy.append(Mark.TREEMAP)
        _ok_encode_hierarchy.append(Mark.TREE)
        _ok_encode_hierarchy.append(Mark.SUNBURST)
        _require_mark(
            self._mark,
            "encode_hierarchy",
            "mark_treemap()",
            _ok_encode_hierarchy^,
        )
        self._hierarchy.ids = ids.copy()
        self._hierarchy.parent_ids = parent_ids.copy()
        self._hierarchy.values = values.copy()
        return self^

    def encode_chord(
        var self,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) raises -> Self:
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
        var _ok_encode_chord = List[Mark]()
        _ok_encode_chord.append(Mark.CHORD)
        _ok_encode_chord.append(Mark.ARC_DIAGRAM)
        _ok_encode_chord.append(Mark.GRAPH)
        _ok_encode_chord.append(Mark.SANKEY)
        _require_mark(
            self._mark, "encode_chord", "mark_chord()", _ok_encode_chord^
        )
        self._categorical.x = List[String]()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._edges.from_categories = from_categories.copy()
        self._edges.to_categories = to_categories.copy()
        self._edges.values = values.copy()
        return self^

    def encode_polar(
        var self, angle: List[Float64], radius: List[Float64]
    ) raises -> Self:
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
        _require_mark(self._mark, "encode_polar", "mark_polar()", Mark.POLAR)
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
    ) raises -> Self:
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
        _require_mark(
            self._mark, "encode_polar_series", "mark_polar()", Mark.POLAR
        )
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
    ) raises -> Self:
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
        _require_mark(self._mark, "encode_radar", "mark_radar()", Mark.RADAR)
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
    ) raises -> Self:
        """Map a single reading onto `Mark.GAUGE`'s dial: `value` against
        the configured range (default 0 to 100), clamped at render()
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
                the configured minimum and maximum.
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
        _require_mark(self._mark, "encode_gauge", "mark_gauge()", Mark.GAUGE)
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
        name, each scaled to its column's minimum and maximum), `row_names` (one
        polyline per name), and `data` (one list per row, one value per
        dimension). Raises immediately on a `row_names`/`data` length
        mismatch or a row whose value count doesn't match `dims`.

        Args:
            dims: One vertical axis per entry, each independently
                scaled to its own column's minimum and maximum across `data`.
            row_names: One polyline per entry.
            data: `data[row]` is `row_names[row]`'s polyline, one
                value per `dims` entry.

        Returns:
            Self, for further chaining.

        Raises:
            If `row_names`/`data` lengths don't match, or any row's
            value count doesn't match `dims`'s count.
        """
        _require_mark(
            self._mark, "encode_parallel", "mark_parallel()", Mark.PARALLEL
        )
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
                scaled to its own column's minimum and maximum across `data`.
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

    def encode_kde(var self, values: List[Float64]) raises -> Self:
        """Map one flat column of raw observations onto `Mark.KDE`/
        `Mark.RUG`.

        A single ungrouped column, unlike `encode_distribution()`'s
        list-per-category: these marks draw one distribution on a
        continuous axis, and several are compared by layering rather
        than by sharing a categorical axis.

        Args:
            values: The observations.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `values` is empty.
        """
        # ECDF is here because `encode_ecdf()` delegates to this, so
        # the inner encoder must accept every mark its callers do.
        var _ok_encode_kde = List[Mark]()
        _ok_encode_kde.append(Mark.KDE)
        _ok_encode_kde.append(Mark.RUG)
        _ok_encode_kde.append(Mark.ECDF)
        _require_mark(self._mark, "encode_kde", "mark_kde()", _ok_encode_kde^)
        _require_non_empty(len(values), "Plot.encode_kde()")
        # One ungrouped column, stored in `_DistributionData`'s
        # list-per-category shape as a single entry -- these marks share
        # the estimator with VIOLIN/RIDGELINE but not the categorical
        # axis, so there is no category to name.
        var one = List[List[Float64]]()
        one.append(values.copy())
        self._distribution.values = one^
        return self^

    def encode_eventplot(
        var self, labels: List[String], positions: List[List[Float64]]
    ) raises -> Self:
        """Map one row label per series and, per row, that row's event
        positions onto `Mark.EVENTPLOT`.

        The same outer-list-per-category shape `encode_distribution()`
        takes, into the same storage -- but with one rule deliberately
        relaxed, which is why it is its own method rather than a call to
        that one. **An individual row may be empty.**
        `encode_distribution()` refuses an empty category, and rightly:
        there is no distribution to estimate from no values. "This
        sensor recorded nothing over the window" is a result, though,
        and a row that vanished for having none would silently renumber
        every row below it.

        What is still refused is *every* row being empty: the x-axis is
        built from the pooled positions, so with no event anywhere there
        is no timeline to draw and nothing to draw on it. That check is
        here rather than at render time so the message names this
        method.

        `labels` comes first, matching `encode_distribution()`,
        `encode_boxplot()` and every other category-plus-values encoder
        in this package --  sketched it the other way round, but a
        single encoder disagreeing about argument order is a worse trap
        than the sketch is a promise.

        Args:
            labels: One row label per series, in the order they should
                be drawn top to bottom.
            positions: Each row's event positions (`positions[i]`),
                in the shared x-axis' units. Individual rows may be
                empty.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `labels` is empty, `labels`/`positions` lengths
                don't match, or every row is empty.
        """
        _require_mark(
            self._mark, "encode_eventplot", "mark_eventplot()", Mark.EVENTPLOT
        )
        if len(labels) != len(positions):
            raise Error(
                "Plot.encode_eventplot(): labels and positions must have"
                " the same length (got "
                + String(len(labels))
                + " and "
                + String(len(positions))
                + ")"
            )
        _require_non_empty(len(labels), "Plot.encode_eventplot()")
        var total = 0
        for row in positions:
            total += len(row)
        if total == 0:
            raise Error(
                "Plot.encode_eventplot(): every row is empty -- an"
                " individual row with no events is fine, but with no"
                " event anywhere there is no x-axis to draw them on"
            )
        self._categorical.x = labels.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
        self._distribution.values = positions.copy()
        return self^

    def encode_eventplot[
        dtype: DType
    ](
        var self, labels: List[String], positions: List[List[Scalar[dtype]]]
    ) raises -> Self:
        """`encode_eventplot()`'s `positions` generalized over numeric
        element type via `_materialize_nested_scalar_list`
        (array_like.mojo), exactly as `encode_distribution()` is.
        `labels` stays concrete. Delegates to the concrete overload.

        Args:
            labels: One row label per series, top to bottom.
            positions: Each row's event positions -- any numeric
                `List[List[Scalar[dtype]]]`.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `labels` is empty, lengths don't match, or every row
                is empty.
        """
        return self^.encode_eventplot(
            labels, _materialize_nested_scalar_list(positions)
        )

    def encode_ecdf(var self, values: List[Float64]) raises -> Self:
        """Map one flat column of raw observations onto `Mark.ECDF`.

        The same single ungrouped column `encode_kde()` takes, into the
        same slot, so the two are interchangeable at the storage level.
        It exists under its own name because the call site is where a
        reader learns what the chart is: `.mark_ecdf().encode_kde(...)`
        reads as a mistake even though it works.

        Args:
            values: The observations, in any order.

        Returns:
            Self, for further chaining.

        Raises:
            Error: `values` is empty.
        """
        _require_mark(self._mark, "encode_ecdf", "mark_ecdf()", Mark.ECDF)
        _require_non_empty(len(values), "Plot.encode_ecdf()")
        return self^.encode_kde(values)

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
        var _ok_encode_distribution = List[Mark]()
        _ok_encode_distribution.append(Mark.VIOLIN)
        _ok_encode_distribution.append(Mark.BEESWARM)
        _ok_encode_distribution.append(Mark.RIDGELINE)
        _require_mark(
            self._mark,
            "encode_distribution",
            "mark_violin()",
            _ok_encode_distribution^,
        )
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
        self._categorical.x = categories.copy()
        self._continuous.x = List[Float64]()
        self._continuous.y = List[Float64]()
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
    ) raises -> Self:
        """Map one continuous column plus the optional `color`/
        `color_categories`/`size` channels onto `Mark.SINGLE_AXIS`'s one-axis
        shape: `encode()` without a `y`. `_continuous.y` is filled with one
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
        _require_mark(
            self._mark,
            "encode_single_axis",
            "mark_single_axis()",
            Mark.SINGLE_AXIS,
        )
        self._continuous.x = x.copy()
        self._categorical.x = List[String]()
        self._continuous.y = List[Float64]()
        for _ in range(len(x)):
            self._continuous.y.append(0.0)
        self._channels.color = color.copy()
        self._channels.color_categories = color_categories.copy()
        self._channels.size = size.copy()
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

        `description` is an SVG `<desc>` -- longer, screen-reader-only
        context `subtitle` alone can't carry since it's drawn on the chart
        itself. `save()`/`save_layers()`/`save_facets()` write it (falling
        back to `subtitle` when empty) automatically whenever `title` is set;
        see `accessible_svg_string()`'s own docstring for the full markup.

        Any of the four drawn labels may hold mathematics between `$`
        signs: `"$\\sigma^2$"`, `"Rate $\\frac{\\Delta y}{\\Delta x}$"`.
        Inside the dollars, Latin letters and lowercase Greek are italic
        variables and everything else upright; `^` and `_` attach
        scripts, `\\frac{}{}` stacks a fraction, `\\sqrt{}` draws a
        radical, `\\mathrm{}` forces upright text, and
        `\\alpha`...`\\Omega` and operators such as `\\times`, `\\leq`
        and `\\sum` name symbols -- the full list is in
        `dataviz/core/mathtext.mojo`. A lone `$` is a price and stays
        plain; write `\\$` for a literal one beside math. The space an
        expression needs above and below the line is measured and
        reserved. A label that does not parse raises at render time,
        naming the label and the character, rather than drawing a
        guess.

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
        per-layer legend: a swatch (this layer's own
        `Theme.mark_color`) plus `name`, one row per named layer, drawn
        before any per-point `color`/`color_categories` legend a `Mark.
        POINT` layer has of its own. A `Plot.secondary_axis()` layer's row
        gets `" (right axis)"` appended, so the reader knows which axis it
        reads against.

        `render_layers()`/`render_layers_svg()` and
        `_render_bar_combo_layers` (the `Mark.BAR`-combo path) only;
        `render()`/`render_svg()` ignore it, since a standalone plot has
        only one series, nothing for a legend entry to distinguish.
        Layers with no name draw no row.

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

    def annotate_arrow(
        var self,
        x: Float64,
        y: Float64,
        text: String,
        text_x: Float64,
        text_y: Float64,
    ) -> Self:
        """Point at `(x, y)` with an arrow, labeled `text` placed at
        `(text_x, text_y)`.
        Each call adds an arrow.

        This is the only annotation that can be placed in empty space,
        which is what makes it usable on a crowded chart where every
        other overlay lands on data -- `annotate_point()`'s label sits a
        fixed gap above its marker and cannot be moved. An arrow is
        often the whole point of a chart going into a document: it is
        what turns a plot into an argument.

        **Both ends are in data coordinates.** Everything else in this API is in data space, and a second
        convention would need explaining every time it appeared. The
        cost is that a label position has to be chosen against the
        data's own range; the benefit is that it stays put when the
        chart is resized.

        Straight arrows only. Curved connectors, head styles and shrink
        factors are refinements on top of a feature that did not exist;
        the straight case carries most of the value.

        Needs a continuous coordinate on both axes, so only `Mark.POINT`/
        `LINE`/`AREA`/`EFFECT_SCATTER` support it; raises otherwise. An
        arrow with either end outside the padded domain is skipped
        whole rather than clipped -- half an arrow points at nothing.

        Args:
            x: The target's x-coordinate, where the head lands.
            y: The target's y-coordinate.
            text: The label, drawn centered at `(text_x, text_y)`.
                Empty draws the arrow alone.
            text_x: The label's x-coordinate, in data space.
            text_y: The label's y-coordinate, in data space.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark has no genuine continuous x/y-axis.
        """
        self._annotations.arrow_x.append(x)
        self._annotations.arrow_y.append(y)
        self._annotations.arrow_text_x.append(text_x)
        self._annotations.arrow_text_y.append(text_y)
        self._annotations.arrow_labels.append(text)
        return self^

    def annotate_band(
        var self,
        x: List[Float64],
        y_lower: List[Float64],
        y_upper: List[Float64],
        label: String = "",
    ) -> Self:
        """Shade the region between two curves that vary with `x`: a confidence
        band around a trend line, or a min/max envelope. `annotate_area()`'s
        band is
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
        ci: Float64 = 0.95,
    ) -> Self:
        """Overlay an ordinary-least-squares best-fit line computed from this
        plot's own `_continuous.x`/`_continuous.y` at render() time, so it works whether
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
            ci: Two-sided confidence level for a band around the fitted
                line. `0.95` (the default) shades the 95% confidence
                interval of the fitted *mean* at each x; pass `0.0` for
                the bare line. The band
                is narrowest at the mean of `x` and flares toward the
                ends, which is the point of drawing it: a line without
                one invites the reader to trust the slope more than the
                data supports (#352). Levels carried: 0.90, 0.95, 0.99.
                A band needs three points -- with two, the line passes
                through both and there is no residual error to size it
                from -- so with fewer the line draws alone. Drawn in
                `Theme.annotation_area_color`, under the line.
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
        self._annotations.best_fit_ci = ci
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

    def scale_y_symlog(var self, linthresh: Float64 = 1.0) -> Self:
        """Scale the y-axis symmetrically logarithmically: linear within
        `[-linthresh, linthresh]`, logarithmic beyond it, continuous
        where they meet (#368).

        What `scale_y_log()` cannot do. A log axis needs strictly
        positive values, so a series that crosses zero -- a temperature
        anomaly, a profit and loss, a residual -- cannot go on one at
        all; and a linear axis collapses every small value against the
        largest. Symlog keeps zero, keeps the sign, and still resolves
        several orders of magnitude on each side.

        `linthresh` is the half-width of the linear region in data
        units, and must be positive. It sets what counts as "near
        zero": values inside it are laid out linearly, so the noise
        floor of the measurement is usually the right choice. The
        linear region takes exactly as much axis as one decade of the
        logarithmic region, which is the only ratio that makes the two
        halves comparable without a second knob.

        `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER`, standalone
        `render()`/`render_svg()` only, the same scope
        `scale_y_log()` has. Mutually exclusive with `scale_y_log()`;
        setting both raises at render time rather than silently
        preferring one.

        Args:
            linthresh: Half-width of the linear region around zero, in
                data units. Must be positive.

        Returns:
            Self, for further chaining.
        """
        self._y_symlog = True
        self._y_symlog_linthresh = linthresh
        return self^

    def scale_x_symlog(var self, linthresh: Float64 = 1.0) -> Self:
        """`scale_y_symlog()`'s x-axis mirror, with the same scope and
        the same `linthresh` meaning (#368).

        Args:
            linthresh: Half-width of the linear region around zero, in
                data units. Must be positive.

        Returns:
            Self, for further chaining.
        """
        self._x_symlog = True
        self._x_symlog_linthresh = linthresh
        return self^

    def scale_x_domain(var self, min: Float64, max: Float64) -> Self:
        """Pin the x-axis domain to the given minimum and maximum, replacing
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
        supported. `render_facets()` applies this per cell, so every cell
        sharing the same override reads as one shared domain -- the
        facets counterpart to `shared_y_scale=True` for the x-axis (which
        has no `shared_y_scale` equivalent otherwise).

        A point outside the domain still computes a real (off-plot)
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
        The explicit domain is used exactly, zero baseline or not.

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

    def scale_x_ticks(
        var self,
        values: List[Float64],
        labels: List[String] = List[String](),
    ) -> Self:
        """Put the x-axis major ticks exactly at `values`, instead of at the
        1-2-5 positions the axis would choose (#368).

        For an axis whose meaningful positions are not round numbers: a
        threshold, a target, the two dates a study ran between. The
        gridline, the tick mark and the label all move together, because
        they are one tick.

        `labels` replaces the formatted numbers when given, one per
        position, which is how an axis reads `Q1 Q2 Q3 Q4` over values
        that are really `1 2 3 4`. Left empty, the positions are
        formatted the way computed ticks are, at one decimal count for
        the whole set.

        A position outside the axis domain is dropped rather than drawn:
        its pixel would fall outside the plot rect and its label would
        print in the margin beside nothing. `scale_x_domain()` is what
        moves the domain; this only says where the ticks go inside it.

        Minor ticks are not derived from an explicit set, since the
        caller said where the ticks belong and a subdivision of an
        irregular set has no meaning.

        Args:
            values: Tick positions, in the axis's own units.
            labels: One label per position, or empty to format the
                positions.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the list is empty, a label count does not
            match, a position is not finite, a position is not positive
            on a log axis, or the mark does not support this.
        """
        self._x_tick_override = _TickOverride(values.copy(), labels.copy())
        return self^

    def scale_y_ticks(
        var self,
        values: List[Float64],
        labels: List[String] = List[String](),
    ) -> Self:
        """`scale_x_ticks()`'s y-axis mirror -- see that method's docstring
        for the shared rules.

        The y labels are what the left margin is measured from, so an
        explicit set widens or narrows the plot rect to fit itself,
        exactly as computed labels do.

        Args:
            values: Tick positions, in the axis's own units.
            labels: One label per position, or empty to format the
                positions.

        Returns:
            Self, for further chaining -- see `scale_x_ticks()`.
        """
        self._y_tick_override = _TickOverride(values.copy(), labels.copy())
        return self^

    def scale_x_reverse(var self) -> Self:
        """Run the x-axis right to left: the domain's low end lands on the
        plot rect's right edge (#368).

        For a quantity that reads better descending -- a rank where 1 is
        best, a countdown, a depth below a surface. Only the two pixel
        positions swap. The domain stays ascending, so the ticks are the
        same ticks in the same order and every mark keeps handing the
        scale the same values; what changes is where they land.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later if the mark does not support this.
        """
        self._x_reversed = True
        return self^

    def scale_y_reverse(var self) -> Self:
        """Run the y-axis top to bottom: the domain's low end lands on the
        plot rect's top edge (#368).

        `scale_x_reverse()`'s mirror. On `Mark.IMSHOW`, whose y-axis
        already counts downward so that row 0 is at the top, this
        composes rather than competes: it puts row 0 back at the bottom.

        Returns:
            Self, for further chaining -- see `scale_x_reverse()`.
        """
        self._y_reversed = True
        return self^

    def equal_aspect(var self) -> Self:
        """Give one data unit the same pixel length on both axes (#368).

        For anything whose two axes are the same kind of quantity, where
        the shape of what is drawn is part of what it says: a map, a
        circle that has to look round, a residual plot read against the
        45-degree line.

        **The plot rect shrinks; the domains do not grow.** With equal
        aspect something has to give, and the two choices are showing a
        wider range than the caller asked for or leaving part of the
        figure empty. This leaves space: the rect keeps the aspect the
        data implies and centers itself in the room it had. Nothing is
        drawn outside the data's own range, and the axis labels, ticks
        and margins are the ones measured for the domains as given.

        Not available on a log or time axis, where a "data unit" is not
        a constant length: raises at `render()` time rather than
        claiming a guarantee it cannot keep.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()`
            raise later on a log or time axis, or if the mark does not
            support this.
        """
        self._equal_aspect = True
        return self^

    def scale_color_domain(var self, min: Float64, max: Float64) -> Self:
        """Pin the continuous color domain to the given minimum and maximum,
        replacing the `[min, max]` this mark would otherwise take from its
        own colored values. `scale_x_domain()`'s color counterpart, and
        the thing that makes two color-encoded charts comparable.

        Without it every continuous-color mark derives its own limits, so
        two panels of the same quantity are drawn against two different
        scales and look identical while meaning different things -- the
        reader has no way to see the difference, because the only place
        it shows is in two legends whose numbers nobody cross-checks.
        `shared_color_domain()` computes one domain across several
        charts' data to pass here; it is the counterpart to
        `shared_bin_edges()`.

        Applies to every mark that colors by a continuous value:
        `Mark.HEATMAP`, `CALENDAR_HEATMAP`, `CORRPLOT`, `IMSHOW`,
        `PCOLORMESH`, `HIST2D`, `HEXBIN`, `CONTOUR`, `CONTOURF`,
        `TRICONTOUR`, `TRICONTOURF`, `TRIPCOLOR`, `QUIVER`,
        `STREAMPLOT`, and `Plot.encode(color=...)`'s continuous channel
        on `Mark.POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER`. Anything else
        raises rather than accepting a setting it would ignore.
        `Mark.BOXENPLOT` is not on the list even though it builds a
        `ColorScale`: its ramp runs over the *depth* of the letter-value
        nest, not over a data value, so an explicit data domain has
        nothing to say about it.

        Values outside the domain are not dropped; they clamp to the
        ramp's end color, because `GradientStops.color_at()` clamps `t`
        outside `[0, 1]`. A separate under/over color would say more,
        and is left for its own change (see the module note on
        `_color_scale_for`).

        The color legend follows automatically: every mark hands the
        legend the same `ColorScale` it colored with, so the labels read
        the overridden domain, not the data's.

        Args:
            min: The value the ramp's low end means.
            max: The value the ramp's high end means; must be `> min`.

        Returns:
            Self, for further chaining -- the render raises later if
            `min >= max` or the mark has no continuous color channel.
        """
        self._color_domain.has = True
        self._color_domain.min = min
        self._color_domain.max = max
        return self^

    def scale_color_thresholds(
        var self, boundaries: List[Float64]
    ) raises -> Self:
        """Color in discrete bands instead of a continuous ramp (#370).

        `n` boundaries make `n - 1` bands, and every value in a band
        gets one flat color. That is what a reader needs when the
        question is "which category is this" rather than "how much":
        soil pH bands, risk tiers, a legend with named ranges.

        Intervals are **lower-inclusive**, `[b[i], b[i+1])`, with the
        last closed at the top so the domain maximum has somewhere to
        go. A value exactly on an interior boundary belongs to the band
        above it. That is the one place this is easy to get wrong, so it
        is stated here and
        tested.

        Values below the first boundary take the lowest band and values
        above the last take the highest, rather than raising. Clipping
        rather than rejecting keeps a shared threshold list usable
        across facets whose data ranges differ.

        Boundaries must be strictly increasing, checked at render time
        along with the rest of the color domain.

        Not combinable with `scale_color_log()` or
        `scale_color_center()`: thresholds already say where every band
        starts, so there is nothing left for either to place.

        Args:
            boundaries: The band edges, at least two, strictly
                increasing.

        Returns:
            Self, for further chaining.
        """
        self._color_domain.thresholds = boundaries.copy()
        return self^

    def scale_color_under(var self, color: Color) -> Self:
        """Color values below the color domain with `color` instead of the
        ramp's low end (#370).

        Without it an out-of-range value clamps: a reading of -40 on a
        domain starting at 0 is painted the same as a reading of 0, and
        the chart says the two are alike. A distinct color says "this is
        off the scale", which is a different statement and usually the
        one that matters -- a sensor out of range, a region with no
        data of its own, a value the domain was deliberately narrowed to
        exclude.

        Applies to every mark `scale_color_domain()` applies to, and to
        every form of the ramp: continuous, logarithmic and banded. With
        `scale_color_thresholds()` the band edges are the range, so
        "below" means below the first boundary.

        The color legend shows it, as a block at the low end of the bar
        inside the bar's own footprint, so the legend costs exactly the
        room it did before and its end labels stay attached to the ends
        of the ramp, where those numbers are true.

        Args:
            color: The color for a value below the domain.

        Returns:
            Self, for further chaining.
        """
        self._color_domain.has_under = True
        self._color_domain.under = color
        return self^

    def scale_color_over(var self, color: Color) -> Self:
        """Color values above the color domain with `color` instead of the
        ramp's high end -- `scale_color_under()`'s mirror, and see that
        method's docstring for the shared rules (#370).

        Values exactly at the domain maximum belong to the ramp, not to
        the over color: the top end is part of the range, which is the
        rule the last threshold band already follows.

        Args:
            color: The color for a value above the domain.

        Returns:
            Self, for further chaining.
        """
        self._color_domain.has_over = True
        self._color_domain.over = color
        return self^

    def scale_color_log(var self) raises -> Self:
        """Normalize color by `log10` instead of linearly (#370).

        A linear ramp cannot resolve values spread over several orders
        of magnitude: on a 1-to-10,000 domain everything below 1,000
        lands in the first tenth of the ramp and reads as one color.
        With this, equal *ratios* get equal color distance, so 1 to 10
        spans as much of the ramp as 1,000 to 10,000.

        The domain must be strictly positive, whether it came from the
        data or from `scale_color_domain()`. That is checked at render
        time, because until then the mark's own limits are not known.

        Not combinable with `scale_color_center()`: centering places the
        neutral color by linear distance from each end, which a log
        domain does not preserve.

        Returns:
            Self, for further chaining.
        """
        self._color_domain.log = True
        return self^

    def scale_color_center(var self, center: Float64) -> Self:
        """Pin the *middle* of the color ramp to `center`, so a diverging
        ramp's neutral color lands on a value that means something --
        zero, a baseline, a target -- instead of on the numeric midpoint
        of whatever the data happened to span.

        A diverging ramp's whole claim is that its middle is neutral and
        its two ends are opposite. Placed at the data's midpoint that
        claim is simply false: over values from -2 to +10 the neutral
        color sits at +4, so half the positive range is painted in the
        color that is supposed to mean "negative". Centering fixes the
        mapping rather than the data, and the two arms are then free to
        be different sizes -- which is the honest picture when the data
        is not symmetric.

        Separate from `scale_color_domain()` on purpose. Centering is
        about where the ramp's middle goes, not about what its ends
        mean, and the two are wanted independently: a center on its own
        re-places the middle inside the data's own limits, which is the
        common case, while a domain on its own leaves the ramp
        symmetric. Folding both into one call would have forced every
        caller who wants a centered ramp to also state limits they had
        no opinion about.

        `center` must lie strictly inside the resolved color domain. It
        is not quietly widened to fit: widening would move the ramp's
        ends, so a chart asking only "center this at zero" would get
        different end colors than the one beside it, which is the silent
        disagreement the whole feature exists to remove. The render
        raises and names the domain instead, so the fix is an explicit
        `scale_color_domain()`.

        This is reached by moving the ramp's stops instead of bending
        the value projection; see
        `ColorScale.from_theme_centered()` for why that route is the one
        that keeps the legend honest.

        Defined for any ramp, not only a three-stop diverging one -- it
        means "the color at offset 0.5 lands on `center`" whatever the
        stops are. On a sequential ramp like `colormaps.viridis()` that
        is legal but rarely useful.

        Args:
            center: The value the ramp's middle color sits on. Must be
                strictly between the color domain's min and max.

        Returns:
            Self, for further chaining -- the render raises later if
            `center` is not strictly inside the domain, or the mark has
            no continuous color channel.
        """
        self._color_domain.has_center = True
        self._color_domain.center = center
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
    """Return `data`'s minimum and maximum padded 5% on each side.

    So that a point at the extreme is not drawn half-clipped on the
    frame.

    The consequence is worth stating because it surprises people (#133):
    **the axis line is not the origin.** For `x = [1, 10]` the domain
    becomes about `[0.55, 10.45]`, so the y-axis line stands at 0.55,
    and the first point is not halfway between the axis and the "2"
    tick. It is in the right place; the axis line just does not name a
    value, and only the tick marks do. `scale_x_domain()` is the way to
    an axis line that means something, and the zero-baseline marks below
    get one for free.

    The scale's placeholder unit range is replaced during rendering once the
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


def _symlog_data_extent(
    data: List[Float64], linthresh: Float64
) raises -> LinearScale:
    """`_data_extent()`'s symlog counterpart for `Plot.scale_x_symlog()`/
    `scale_y_symlog()` (#368).

    Every value is allowed, including zero and negatives -- that is the
    whole point of the transform, and why this has no equivalent of
    `_log_data_extent`'s positivity check. The domain is computed and
    padded in symlog space, 5% of the transformed span, because that is
    the space the axis is linear in and so the space a constant margin
    means something in.

    The returned scale carries `is_symlog` and the threshold; values are
    still passed to `to_pixel()` in real units.

    Args:
        data: The column to size the axis from.
        linthresh: Half-width of the linear region, real units.

    Returns:
        The scale, ranged 0 to 1 for the frame to re-range.

    Raises:
        Error: `linthresh` is not positive, or `data` is empty or
            non-finite (via `_min_max`).
    """
    if linthresh <= 0.0:
        raise Error(
            "scale_x_symlog()/scale_y_symlog(): linthresh must be positive"
            " -- it is the half-width of the linear region around zero,"
            " and a zero or negative width leaves nowhere for zero to"
            " live (got "
            + String(linthresh)
            + ")"
        )
    var mm = _min_max(data)
    var lo = _symlog_forward(mm.min, linthresh)
    var hi = _symlog_forward(mm.max, linthresh)
    var span = hi - lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(
        lo - pad,
        hi + pad,
        0.0,
        1.0,
        is_symlog=True,
        symlog_linthresh=linthresh,
    )


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
    ), so there is no "no data" `_RenderResult` shape to report here.

    `y_scale`/`has_y_scale` expose the real `LinearScale` the mark's
    y-axis used, so the annotation passes (`_draw_annotation_lines`/
    `_draw_annotation_areas`) place values with the same `to_pixel` the
    data went through. `has_y_scale` defaults `False` with an inert
    placeholder scale; only the frames that support annotations pass a
    real one. `x_scale`/`has_x_scale` mirror that for the x-axis, set by
    `_ContinuousFrame.result()` and by
    `_HorizontalCategoricalFrame.result()`, whose continuous axis is the
    x one (#688); a vertical categorical frame sets neither, since its
    x-axis has no numeric domain. Which marks that leaves is
    `Mark.supports(Feature.ANNOTATIONS_X)` and `ANNOTATIONS_XY`
    (mark.mojo), not a list restated here.
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


def _point_tooltip_label(plot: Plot, i: Int) -> String:
    """One scatter point's hover text: the row's `encode(labels=...)` entry
    when it has one, otherwise its coordinates, `"3.5, 12"`.

    `Mark.SINGLE_AXIS` gets the value alone. It draws through this same
    layer but has no y channel -- `encode_single_axis()` leaves that
    column zero -- so the pair form read `"3.5, 0"` and reported a
    coordinate the chart does not have (#683).
    """
    if (
        len(plot._channels.point_labels) > 0
        and plot._channels.point_labels[i] != ""
    ):
        return plot._channels.point_labels[i]
    var x = _format_fixed(
        plot._continuous.x[i], _label_decimals(plot._continuous.x[i])
    )
    if plot._mark == Mark.SINGLE_AXIS:
        return x
    return (
        x
        + ", "
        + _format_fixed(
            plot._continuous.y[i], _label_decimals(plot._continuous.y[i])
        )
    )


def _xyz_tooltip_label(x: Float64, y: Float64, z: Float64) -> String:
    """One 3D datum's hover text, `"1, 2, 3"`: the same shape as
    `_point_tooltip_label`'s coordinate fallback with the third axis
    added (#683). A projected point is the case that needs a tooltip
    most -- two points that look adjacent on the page can be far apart
    along the view direction, and the title is the only way to tell.
    """
    return (
        _format_fixed(x, _label_decimals(x))
        + ", "
        + _format_fixed(y, _label_decimals(y))
        + ", "
        + _format_fixed(z, _label_decimals(z))
    )


def _cell_tooltip_label(
    first: String, second: String, value: Float64
) -> String:
    """One grid cell's hover text, `"Mon / 09:00: 42"`: both keys and
    the value, formatted like `_tooltip_label`'s single key (#679).

    A grid mark encodes its value as a color or a radius, so the cell
    is the one shape in the library a reader cannot get a number out of
    by looking. The title is what makes it readable, which is why these
    marks carry one under `Theme.svg_tooltips` alone rather than an
    opt-in flag: there is one title per cell, not one per data point in
    a dense scatter.
    """
    return (
        first
        + " / "
        + second
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )


def _span_tooltip_label(
    category: String, start: Float64, end: Float64
) -> String:
    """A bar that spans two values rather than reaching one, as a
    Gantt row does: `"deploy: 3 to 7"` (#677). `_tooltip_label`'s
    single number cannot say what this bar encodes -- its length is
    the datum, and either end alone loses half of it.
    """
    return (
        category
        + ": "
        + _format_fixed(start, _label_decimals(start))
        + " to "
        + _format_fixed(end, _label_decimals(end))
    )


def _edge_tooltip_label(
    source: String, target_name: String, value: Float64
) -> String:
    """One edge's hover text, `"Coal -> Power: 42"` (#682).

    The relationship marks draw every node's name as visible text
    already; what no edge shows is its weight, and the weight is the
    whole of what the ribbon's thickness encodes. So the title goes on
    the edges rather than repeating a name that is on the page a
    centimetre away.

    An ASCII arrow, matching the plain-text style the rest of the
    package writes in.
    """
    return (
        source
        + " -> "
        + target_name
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )


def _require_positive_supersample(factor: Int, context: String) raises:
    """Raise unless `factor >= 1`, naming the caller (`context`). Guards
    `Theme.raster_supersample` at each of its three read sites
    (`render()`/`render_facets()`/`render_layers()`) rather than in
    `Theme`'s own constructor, matching `line_smoothing`'s deferred-to-
    render-time validation (`_check_line_smoothing`, elsewhere in this
    file) -- a `Theme` value isn't wrong to construct, only to render
    with.
    """
    if factor < 1:
        raise Error(
            context
            + "(): Theme.raster_supersample must be >= 1 (got "
            + String(factor)
            + ")"
        )


comptime _AUTO_SUPERSAMPLE = 0
"""`Theme.raster_supersample`'s "let the mark decide" value, and its
default. An explicit 1 or more always wins; this only picks a factor
for a caller who has not expressed one.
"""

comptime _CURVED_SUPERSAMPLE = 3
"""Supersample factor for circles, arcs, and curved strokes."""


def _auto_supersample(plot: Plot) -> Int:
    """Return the mark-specific supersample factor for `AUTO`."""
    # A smoothed line or area is a curve whatever its mark says, so it
    # is classified by what it draws rather than by its name.
    if plot._theme.line_smoothing > 0.0:
        return _CURVED_SUPERSAMPLE

    var m = plot._mark
    if (
        m == Mark.BAR
        or m == Mark.GROUPED_BAR
        or m == Mark.STACKED_BAR
        or m == Mark.WATERFALL
        or m == Mark.BULLET
        or m == Mark.GANTT
        or m == Mark.SPAN_CHART
        or m == Mark.BOX
        or m == Mark.CANDLESTICK
        or m == Mark.HEATMAP
        or m == Mark.IMSHOW
        or m == Mark.PCOLORMESH
        or m == Mark.HIST2D
        or m == Mark.MARIMEKKO
        or m == Mark.TREEMAP
        or m == Mark.SANKEY
        or m == Mark.LINE
        or m == Mark.AREA
        or m == Mark.HISTOGRAM
        or m == Mark.VIOLIN
        or m == Mark.PARALLEL
        or m == Mark.RADAR
        or m == Mark.TRICONTOUR
    ):
        return 1
    return _CURVED_SUPERSAMPLE


def _resolve_supersample(plot: Plot, context: String) raises -> Int:
    """`Theme.raster_supersample` if the caller set one, else the mark's
    own factor. Validated here so every entry point gets the same check.

    Args:
        plot: The chart being rendered.
        context: The caller's name, for the error message.

    Returns:
        The factor to supersample by.

    Raises:
        Error: The theme's factor is negative.
    """
    var configured = plot._theme.raster_supersample
    if configured == _AUTO_SUPERSAMPLE:
        return _auto_supersample(plot)
    _require_positive_supersample(configured, context)
    return configured


def render(plot: Plot) raises -> Canvas:
    """Render `plot` into a fresh `Canvas` sized `plot.width` x `plot.height`
    and return it, supersampled by `plot._theme.raster_supersample`
    (default automatic, resolved per mark by `_auto_supersample()`):
    the drawing is recorded once at logical coordinates and replayed
    into the canvas one output band at a time, each band rendered at
    that many times the size and averaged down. The enlarged buffer
    never exists whole.

    Supersampling uses the canvas transform; `Theme.scale` independently
    controls layout density.

    `plot` is a plain borrow: copying instead of mutating in
    place means `render(scatter(x, y))` and `save(scatter(x, y), path)`
    both compile inline, with no need to bind a temporary to a variable
    first.
    """
    var factor = _resolve_supersample(plot, "render")
    var out = Canvas(plot.width, plot.height, plot._theme.background)
    # `begin_supersampled` owns the half-pixel shift box downsampling
    # costs and the scale, and replays the recorded shapes one output
    # band at a time, so the enlarged buffer never exists whole. Byte
    # identical to the two-step recipe it replaces (canvas_mojo#391).
    #
    # Every mark takes this path. A bulk marker call used to force the
    # region to materialize, so a plain scatter was faster on the old
    # two-step recipe and `render()` chose per plot; canvas_mojo v0.33.3
    # records the whole call as one op and that was the last primitive
    # that did so (benchmarks/METHODOLOGY.md).
    out.begin_supersampled(factor, plot._theme.background)
    _ = _render_into(out, plot, 0, 0, plot.width, plot.height)
    out.end_supersampled()
    return out^


struct _DrawnFigure(Movable):
    """What `_draw_figure_into` drew: the inner plot rect, and every
    label the pass collected, already in replay order.

    The labels are handed back rather than drawn so that they go on
    after every mark and annotation pass, on top; the caller hands
    them to `_replay_text_requests`. What the struct buys is that the
    *drawing* -- the background, the labels' margins, the mark, and
    the seven annotation passes -- is written once instead of once per
    backend.
    """

    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int
    var text: List[_TextRequest]

    def __init__(
        out self,
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
        var text: List[_TextRequest],
    ):
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1
        self.text = text^


def _draw_figure_into[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    fill_background: Bool,
    vector_target: Bool,
    mut cache: FontCache,
) raises -> _DrawnFigure:
    """Draw everything of `plot` except its text into `target`, and
    return the inner plot rect with the labels the pass collected.

    The shared body of `_render_into`, `_render_svg_into` and
    `_render_pdf_into`, which were three near-identical copies differing
    only in the target's type and `vector_target`. Every piece they
    called was already generic over `T: DrawTarget`, and since #578 so
    is the replay.

    It is also what lets a figure be *measured* rather than drawn:
    `_tight_box` runs this into a `BoundsTarget`, which keeps the union
    of what it was asked to draw and paints nothing (#372). A fourth
    copy of sixty lines would have been the alternative, and copies of
    this particular body have drifted before.

    Args:
        target: Where to draw.
        plot: The chart.
        ox0: Outer left bound.
        oy0: Outer top bound.
        ox1: Outer right bound.
        oy1: Outer bottom bound.
        fill_background: Whether to fill the outer rect first;
            `render_inset()` passes False so its labels sit over the
            base rather than on a blank panel.
        vector_target: Passed to `_render_generic`, which draws some
            marks differently when the output is markup rather than
            pixels.
        cache: The render's shared font cache.

    Returns:
        The inner plot rect and the collected labels.

    Raises:
        Error: Whatever the mark's render raises.
    """
    if fill_background:
        target.fill_rect(ox0, oy0, ox1 - ox0, oy1 - oy0, plot._theme.background)
    var frame = _apply_labels(plot, ox0, oy0, ox1, oy1, cache=cache)
    var result = _render_generic(
        target,
        plot,
        frame.ox0,
        frame.oy0,
        frame.ox1,
        frame.oy1,
        cache=cache,
        vector_target=vector_target,
    )
    var text = _label_text_requests(
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        result.px0,
        result.py0,
        result.px1,
        result.py1,
        cache=cache,
    )
    var under_mark = _filled_annotations_go_under(plot._mark)
    if not under_mark:
        _extend_text_requests(
            text,
            _draw_annotation_areas(
                target, plot, result, plot._theme, cache=cache
            ),
        )
        _extend_text_requests(
            text,
            _draw_annotation_bands(
                target, plot, result, plot._theme, cache=cache
            ),
        )
    _extend_text_requests(
        text,
        _draw_annotation_vlines(target, plot, result, plot._theme, cache=cache),
    )
    _extend_text_requests(
        text,
        _draw_annotation_lines(target, plot, result, plot._theme, cache=cache),
    )
    _extend_text_requests(
        text,
        _draw_annotation_points(target, plot, result, plot._theme, cache=cache),
    )
    _extend_text_requests(
        text,
        _draw_annotation_arrows(target, plot, result, plot._theme, cache=cache),
    )
    _extend_text_requests(
        text,
        _draw_annotation_best_fit(
            target, plot, result, plot._theme, cache=cache
        ),
    )
    _extend_text_requests(text, result.text_requests)
    return _DrawnFigure(result.px0, result.py0, result.px1, result.py1, text^)


def render_tight(plot: Plot) raises -> Canvas:
    """`render()` cropped to the figure's ink: the whitespace a fixed
    figure size reserves for a longer title or a legend that is not
    there is trimmed away (#372).

    The figure is laid out at its full `size()` and then cropped, rather
    than being laid out smaller -- laying out smaller would change where
    everything goes, and the crop would chase a moving target instead of
    framing the figure the caller asked for.

    The ink is measured with `_tight_box`, which draws the figure into a
    `BoundsTarget` that paints nothing and keeps the union of the
    extents. Text counts: a title's box is the box of the glyphs the
    same layout would draw.

    A figure with no ink keeps its full size, since a zero-sized canvas
    is not usable.

    Args:
        plot: The chart to render.

    Returns:
        A canvas the size of the figure's ink.

    Raises:
        Error: Whatever `render()` raises.
    """
    var box = _tight_box(plot, False)
    var factor = _resolve_supersample(plot, "render_tight")
    var out = Canvas(box[2], box[3], plot._theme.background)
    out.begin_supersampled(factor, plot._theme.background)
    # Draw the figure at its full size into a smaller canvas, shifted so
    # the ink's top-left lands at the origin. Everything outside the
    # canvas is clipped, which is exactly the crop.
    out.translate(-Float64(box[0]), -Float64(box[1]))
    _ = _render_into(out, plot, 0, 0, plot.width, plot.height)
    out.end_supersampled()
    return out^


def render_tight_svg(plot: Plot) raises -> SvgCanvas:
    """`render_svg()` cropped to the figure's ink; `render_tight()`'s
    vector counterpart (#372).

    The same three steps -- measure, size, redraw -- and the reason the
    measuring target was worth asking canvas for: an `SvgCanvas` has no
    pixels to scan for ink, so nothing else could have answered this.

    Args:
        plot: The chart to render.

    Returns:
        An `SvgCanvas` the size of the figure's ink.

    Raises:
        Error: Whatever `render_svg()` raises.
    """
    var box = _tight_box(plot, True)
    var svg = SvgCanvas(box[2], box[3])
    svg.translate(-Float64(box[0]), -Float64(box[1]))
    _ = _render_svg_into(svg, plot, 0, 0, plot.width, plot.height)
    return svg^


def render_tight_pdf(plot: Plot) raises -> PdfCanvas:
    """`render_pdf()` cropped to the figure's ink, so the page is the
    figure rather than the figure plus its margins (#372).

    The page shrinks with the crop, and one layout unit is still one
    point, so a cropped export is still physically specified -- it is
    simply a smaller page.

    Args:
        plot: The chart to render.

    Returns:
        A one-page `PdfCanvas` the size of the figure's ink.

    Raises:
        Error: Whatever `render_pdf()` raises.
    """
    var box = _tight_box(plot, True)
    var pdf = PdfCanvas(box[2], box[3])
    pdf.translate(-Float64(box[0]), -Float64(box[1]))
    _ = _render_pdf_into(pdf, plot, 0, 0, plot.width, plot.height)
    return pdf^


def _tight_box(
    plot: Plot, vector_target: Bool
) raises -> Tuple[Int, Int, Int, Int]:
    """The whole-pixel box around everything `plot` would draw, as
    `(x, y, width, height)` in the figure's own coordinates (#372).

    Measured by drawing the figure into a `BoundsTarget`, which keeps
    the union of the extents it is asked to draw and paints nothing.
    That is the only way to get this for a vector backend: a raster
    canvas could be scanned for non-background pixels, but an
    `SvgCanvas` or a `PdfCanvas` has no pixels to scan, and a figure
    that cropped only for PNG would be the wrong shape for a feature
    whose point is publication output.

    The background fill is deliberately skipped while measuring. It
    covers the whole page by construction, so counting it would make
    every box the full page and the crop a no-op.

    A figure with no ink at all -- no marks, no labels -- keeps its
    full size rather than collapsing to nothing, since a zero-sized
    canvas is not a thing a caller can use.

    Args:
        plot: The chart to measure.
        vector_target: Whether the real draw will be to a vector
            backend; passed through so the measured geometry is the
            geometry that will be drawn.

    Returns:
        `(x, y, width, height)`.

    Raises:
        Error: Whatever the mark's render raises.
    """
    var probe = BoundsTarget(plot.width, plot.height)
    var cache = FontCache()
    var drawn = _draw_figure_into(
        probe, plot, 0, 0, plot.width, plot.height, False, vector_target, cache
    )
    _replay_text_requests(probe, drawn.text, cache)
    if not probe.has_ink():
        return (0, 0, plot.width, plot.height)
    return probe.ink_pixels()


def _render_into(
    mut canvas: Canvas,
    plot: Plot,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
    fill_background: Bool = True,
) raises -> Tuple[Int, Int, Int, Int]:
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

    `fill_background=False` skips the outer fill, for `render_inset()`,
    which paints only the inset's plot rect so its labels sit over the
    base rather than on a blank panel.

    Returns:
        The inner plot rect as `(px0, py0, px1, py1)`, the area the mark
        was drawn in after margins and labels; `render_inset()` places an
        inset against it.
    """
    var cx1 = ox1 if ox1 >= 0 else canvas.width
    var cy1 = oy1 if oy1 >= 0 else canvas.height
    # One FontCache for the whole render, built on first use: every
    # measurement the layout makes (tick labels, legend entries) and
    # then every label drawn afterwards resolve fonts and rasterize
    # glyphs through it once.
    var cache = FontCache()
    var drawn = _draw_figure_into(
        canvas, plot, ox0, oy0, cx1, cy1, fill_background, False, cache
    )
    _replay_text_requests(canvas, drawn.text, cache)
    return (drawn.px0, drawn.py0, drawn.px1, drawn.py1)


def render_svg(plot: Plot) raises -> SvgCanvas:
    """Render `plot` into a fresh `SvgCanvas` sized `plot.width` x
    `plot.height` and return it; `render()`'s vector counterpart,
    wrapping `_render_svg_into`.
    """
    var svg = SvgCanvas(plot.width, plot.height)
    _ = _render_svg_into(svg, plot)
    return svg^


def _render_svg_into(
    mut svg: SvgCanvas,
    plot: Plot,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
    fill_background: Bool = True,
) raises -> Tuple[Int, Int, Int, Int]:
    """`_render_into`'s counterpart for `SvgCanvas`: same bounds resolution,
    `_apply_labels`/`_render_generic` core, and annotation passes, with
    the `_TextRequest`s drawn via `SvgCanvas.draw_text`. `render_svg()`
    is its only caller.

    `fill_background=False` skips the outer fill, for `render_inset()`,
    which paints only the inset's plot rect so its labels sit over the
    base rather than on a blank panel.

    Returns:
        The inner plot rect as `(px0, py0, px1, py1)`, the area the mark
        was drawn in after margins and labels; `render_inset()` places an
        inset against it.
    """
    var cx1 = ox1 if ox1 >= 0 else svg.width
    var cy1 = oy1 if oy1 >= 0 else svg.height
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var drawn = _draw_figure_into(
        svg, plot, ox0, oy0, cx1, cy1, fill_background, True, cache
    )
    _replay_text_requests(svg, drawn.text, cache)
    return (drawn.px0, drawn.py0, drawn.px1, drawn.py1)


def _resolve_output_format(
    theme_format: OutputFormat, path: String
) -> OutputFormat:
    """The format `save()`/`save_layers()`/`save_facets()` use: `path`'s
    extension when it's `.svg`/`.png`/`.bmp`/`.pdf` (case-insensitive),
    otherwise `theme_format` (`Theme.output_format`).
    """
    var lower = path.lower()
    if lower.endswith(".svg"):
        return OutputFormat.SVG
    elif lower.endswith(".png"):
        return OutputFormat.PNG
    elif lower.endswith(".bmp"):
        return OutputFormat.BMP
    elif lower.endswith(".pdf"):
        return OutputFormat.PDF
    return theme_format


def _resolve_description(labels: _LabelData) -> String:
    """`labels.description`, or `labels.subtitle` when that's empty
    -- the `<desc>` `_svg_output_string()` passes to
    `accessible_svg_string()`, so a title-and-subtitle chart gets a
    reasonable screen-reader description with no extra call needed.
    """
    return (
        labels.description if labels.description.byte_length()
        > 0 else labels.subtitle
    )


def _svg_output_string(var svg: SvgCanvas, labels: _LabelData) raises -> String:
    """What `save()`/`save_layers()`/`save_facets()` write for SVG output
    : `accessible_svg_string()`'s markup when `labels.title` is set
        (`_resolve_description()`'s `<desc>`), or plain `svg.to_string()`
        otherwise. A pure string decision, factored out of the file-writing
        `save*()` functions so it's directly testable with no disk I/O.

    Takes the canvas by value, for the reason `accessible_svg_string()`
    does; every caller here passes a freshly rendered one.
    """
    if labels.title.byte_length() > 0:
        return accessible_svg_string(
            svg^, labels.title, _resolve_description(labels)
        )
    return svg.to_string()


def render_pdf(plot: Plot) raises -> PdfCanvas:
    """Render `plot` into a one-page `PdfCanvas` sized `plot.width` by
    `plot.height` points and return it; `render_svg()`'s counterpart for
    a print-ready document (#372).

    **One layout unit is one PDF point, 1/72 inch**, which is the whole
    physical-size contract: a 640 by 420 chart is a 640 by 420 point
    page, 8.89 by 5.83 inches. `size_inches()`/`size_mm()` say it the
    other way round. Nothing is resampled on the way out, because
    nothing is a pixel: paths stay paths and text stays text, embedded
    as a font subset so a label is selectable and searchable rather
    than a picture of itself.

    **What an export promises is the same glyphs, not the same bytes**
    (#631). The subset embedded here is cut from whichever copy of the
    family the machine has, and two packagings of one family -- DejaVu
    from `apt` and from `brew`, say -- agree on every outline while
    differing in the hinting programs they carry. So the same chart
    exported on two machines draws identically and compares
    byte-for-byte unequal, and a build that diffs or caches PDFs should
    compare the rendering rather than the file.

    Byte-identity would mean shipping a font rather than resolving one,
    which is a packaging decision and not one this contract makes. The
    font is most of a small document -- a two-word label embeds roughly
    12 KB of a 14 KB file -- so a byte comparison is mostly a
    comparison of the machine's font anyway.

    A family the machine does not have raises rather than substituting
    silently, so a wrong font is never quietly embedded.

    `Theme.scale` still multiplies every font size, margin and stroke
    width as it does on the other backends, so it changes how large the
    furniture is *on the page* rather than how many pixels it gets. The
    raster supersample factor has no meaning here and is ignored.

    Args:
        plot: The chart to render.

    Returns:
        The finished document, ready for `canvas.vector.pdf.write_pdf`
        or the `save()` path that wraps it.

    Raises:
        Error: Whatever rendering the plot raises.
    """
    var pdf = PdfCanvas(plot.width, plot.height)
    _ = _render_pdf_into(pdf, plot, 0, 0, plot.width, plot.height)
    return pdf^


def _render_pdf_into(
    mut pdf: PdfCanvas,
    plot: Plot,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
    fill_background: Bool = True,
) raises -> Tuple[Int, Int, Int, Int]:
    """`_render_svg_into`'s counterpart for `PdfCanvas`: same bounds
    resolution, `_apply_labels`/`_render_generic` core and annotation
    passes, with the `_TextRequest`s drawn through
    `_replay_text_requests`.

    Args:
        pdf: The document to draw into.
        plot: The chart.
        ox0: Left edge of the bounds to lay out in.
        oy0: Top edge.
        ox1: Right edge; -1 means the page width.
        oy1: Bottom edge; -1 means the page height.
        fill_background: Whether to paint the theme's background over
            the bounds first.

    Returns:
        The inner plot rect as `(px0, py0, px1, py1)`.

    Raises:
        Error: Whatever rendering the plot raises.
    """
    var cx1 = ox1 if ox1 >= 0 else pdf.width
    var cy1 = oy1 if oy1 >= 0 else pdf.height
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var drawn = _draw_figure_into(
        pdf, plot, ox0, oy0, cx1, cy1, fill_background, True, cache
    )
    _replay_text_requests(pdf, drawn.text, cache)
    return (drawn.px0, drawn.py0, drawn.px1, drawn.py1)


def _at_dpi(plot: Plot, dpi: Float64) raises -> Plot:
    """`plot` laid out for a raster export at `dpi` (#372).

    The figure's size is in points, 1/72 inch, so a raster at `dpi`
    wants `dpi / 72` pixels per point. Multiplying the target's size
    alone would spread the same furniture over more pixels and print
    the text at a third of its physical size; multiplying `Theme.scale`
    by the same factor keeps every font size, margin and stroke width
    the same fraction of the page. So the output is the same figure at
    a finer resolution, which is what asking for a resolution means.

    Args:
        plot: The chart, sized in points.
        dpi: Pixels per inch for the export.

    Returns:
        A copy sized and scaled for that resolution; `plot` itself at
        72, where the factor is 1.

    Raises:
        Error: `dpi` is not positive.
    """
    if dpi <= 0.0:
        raise Error("save(): dpi must be positive (got " + String(dpi) + ")")
    var factor = dpi / 72.0
    var out = plot.copy()
    if factor == 1.0:
        return out^
    out.width = Int(Float64(plot.width) * factor + 0.5)
    out.height = Int(Float64(plot.height) * factor + 0.5)
    out._theme.scale = plot._theme.scale * factor
    return out^


def save(
    plot: Plot, path: String, dpi: Float64 = 72.0, tight: Bool = False
) raises:
    """Render `plot` and write it to `path` in one call. The format
    comes from `_resolve_output_format()` (the path's extension, falling
    back to `plot._theme.output_format`); `PNG`/`BMP` both go through
    `render()` and differ only in the writer.

    `plot` is a plain borrow: `save(scatter(x, y), path)` compiles
    inline, with no need to bind the temporary to a variable first. Call
    `render()`/`render_svg()` directly to get the `Canvas`/`SvgCanvas`
    itself. `save_layers()`/`save_facets()` are the `List[Plot]`
    counterparts; the `save(canvas: Canvas, path)` overload below writes
    an already-rendered `Canvas`.

    `tight=True` crops the output to the figure's ink, trimming the
    whitespace a fixed `size()` reserves for a longer title or an
    absent legend (#372). It applies to every format, because the
    measurement is taken from the drawing rather than from pixels; see
    `render_tight()`.

    `dpi` applies to the raster formats and says how many pixels one
    inch of the figure gets. The figure's own size is in points, 1/72
    inch (`Plot.size()`), so the default of 72 is one pixel per point
    and every existing call renders exactly as before; 300 gives the
    same figure at print resolution, with the text and strokes the same
    fraction of the page rather than a third the size. The vector
    formats ignore it, having no pixels to count. A `.pdf` path writes a
    one-page document through `render_pdf()`.

    SVG output with a non-empty `.labels(title=...)` writes accessible
    markup automatically, via `_svg_output_string()`/
    `accessible_svg_string()` with that title and `_resolve_description()`'s
    `<desc>` -- the same markup `write_accessible_svg()` adds explicitly,
    for callers who don't need a title that differs from the visible one.
    An untitled plot's SVG is unaffected.
    """
    var format = _resolve_output_format(plot._theme.output_format, path)
    # Each arm binds its canvas with `^` rather than through a ternary:
    # none of the three canvas types is `ImplicitlyCopyable`, so a
    # ternary would have to copy one to choose between the branches.
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        if tight:
            var vector = render_tight_svg(plot)
            f.write(_svg_output_string(vector^, plot._labels))
        else:
            var vector = render_svg(plot)
            f.write(_svg_output_string(vector^, plot._labels))
        f.close()
    elif format == OutputFormat.PDF:
        if tight:
            var doc = render_tight_pdf(plot)
            write_pdf(doc, path)
        else:
            var doc = render_pdf(plot)
            write_pdf(doc, path)
    elif format == OutputFormat.PNG:
        var scaled = _at_dpi(plot, dpi)
        if tight:
            write_png(render_tight(scaled), path)
        else:
            write_png(render(scaled), path)
    else:
        var bmp_scaled = _at_dpi(plot, dpi)
        if tight:
            write_bmp(render_tight(bmp_scaled), path)
        else:
            write_bmp(render(bmp_scaled), path)


def _reject_mismatched_extension(
    path: String,
    because: String,
    accepted: String,
    wrong: List[String],
) raises:
    """Raise before opening `path` when its extension names a format
    this canvas cannot produce (#696).

    Before this, `save(canvas, "chart.pdf")` wrote PNG bytes and
    `save(svg, "chart.pdf")` wrote markup: each overload rejected only
    the extensions someone had thought of, and everything else fell
    through to the default writer. A file that says `.pdf` and holds a
    PNG is worse than a failed save, because nothing reports it.

    Checked before the file is opened, so a rejected path is left
    untouched rather than created and truncated. An unrecognized or
    absent extension is allowed through to the caller's chosen writer,
    which is what lets `save(canvas, "out")` still work.

    `because` is the canvas's own explanation of why it cannot, kept
    per-canvas rather than generated, so a caller gets the same
    sentence that told them something useful before this was
    centralized.

    Args:
        path: The destination.
        because: Why this canvas cannot write that format.
        accepted: The extension this canvas writes.
        wrong: The recognized extensions it cannot.

    Raises:
        Error: `path` ends in one of `wrong`.
    """
    var lower = path.lower()
    for ext in wrong:
        if lower.endswith(ext):
            raise Error(
                "save(): cannot write a "
                + ext
                + " file here -- "
                + because
                + " Save it as "
                + accepted
                + ", or build the chart as a Plot and call"
                + " save(plot, path), which renders whatever format the"
                + " extension asks for."
            )


def save(svg: SvgCanvas, path: String) raises:
    """Write an already-rendered `SvgCanvas` to `path` (#620).

    The vector counterpart of the `Canvas` overload below, so a
    composite figure that renders to vector -- `jointplot_svg()`,
    `pairplot_svg()` -- is saved the same way every other chart is
    rather than reaching for canvas's own writer. A raster extension
    raises: this is markup, and turning it into pixels is `render()`'s
    job from the `Plot` it came from, at whatever size and resolution
    that caller wants.

    Args:
        svg: The rendered document.
        path: Where to write it; the extension must be `.svg`, or
            absent.

    Raises:
        Error: A `.png` or `.bmp` path, or the write fails.
    """
    var wrong: List[String] = [".png", ".bmp", ".pdf"]
    _reject_mismatched_extension(
        path,
        "an SvgCanvas is vector markup, not pixels.",
        ".svg",
        wrong,
    )
    var f = open(path, "w")
    f.write(svg.to_string())
    f.close()


def save(canvas: Canvas, path: String) raises:
    """Write an already-rendered `Canvas` to `path`: BMP for a `.bmp`
    extension, PNG otherwise. A `.svg` path raises, since raster pixels
    can't become vector markup.
    """
    var wrong: List[String] = [".svg", ".pdf"]
    _reject_mismatched_extension(
        path,
        "a Canvas is already-rendered raster pixels.",
        ".png or .bmp",
        wrong,
    )
    if path.lower().endswith(".bmp"):
        write_bmp(canvas, path)
    else:
        write_png(canvas, path)


def save(var pdf: PdfCanvas, path: String) raises:
    """Write an already-rendered `PdfCanvas` to `path` (#696).

    The third rendered-canvas overload, completing the set: before it,
    a caller holding a `PdfCanvas` had no `save()` at all and had to
    reach for `canvas.vector.pdf.write_pdf` while every other canvas
    type saved through this function.

    Takes the document by value rather than by `mut`, so
    `save(render_pdf(plot), path)` compiles inline the way
    `save(scatter(x, y), path)` does; `write_pdf` needs a mutable
    document because writing finalizes it, and an owned parameter is
    mutable without forcing the caller to bind a temporary first.

    Args:
        pdf: The rendered document.
        path: Where to write it; the extension must be `.pdf`, or
            absent.

    Raises:
        Error: A `.png`, `.bmp` or `.svg` path, or the write fails.
    """
    var wrong: List[String] = [".png", ".bmp", ".svg"]
    _reject_mismatched_extension(
        path,
        "a PdfCanvas is a finished PDF document.",
        ".pdf",
        wrong,
    )
    write_pdf(pdf, path)


def accessible_svg_string(
    var svg: SvgCanvas, title: String, description: String = ""
) raises -> String:
    """`svg.to_string()` with SVG accessibility markup added: `role="img"`
    and `aria-label` on the root `<svg>` element, plus a `<title>` (and a
    `<desc>` when `description` is non-empty) as its first child
    elements, which is what screen readers that support SVG look for.

    `title` is required; the same string passed to `.labels(title=...)`
    is usually right.

    `SvgCanvas.set_title()` does the work. This was once a
    post-processing wrapper that spliced the attributes and children into
    `to_string()`'s output as text, which meant depending on `<svg ...>`
    being the literal start of that output and on two of canvas_mojo's
    private escaping helpers. Nothing upstream owed us either (#572).

    This only helps where the SVG's accessible tree is walked: inline
    `<svg>` markup, a standalone `.svg`, or an `<object>`/`<iframe>`
    embed. A plain `<img src="chart.svg">` (how the docs site embeds
    examples) treats the SVG as an opaque image, and a screen reader
    reads the `<img>`'s `alt` text instead.

    Taking the canvas by value is the one visible change: `set_title()`
    is a mutation and `SvgCanvas` is movable but not copyable, so a
    caller holding one passes `svg^` rather than `svg`. Every call here
    passes a freshly rendered canvas, which moves on its own.

    Args:
        svg: The rendered chart, consumed.
        title: The accessible name. Required.
        description: A longer description, omitted when empty.

    Returns:
        The SVG document, titled.

    Raises:
        Error: Whatever `set_title()` raises.
    """
    svg.set_title(title, description)
    return svg.to_string()


def write_accessible_svg(
    var svg: SvgCanvas, path: String, title: String, description: String = ""
) raises:
    """`accessible_svg_string()` written to `path`. See the Cookbook's "SVG
    Accessibility" recipe
    (docs/cookbook_recipes/svg_accessibility.mojo).

    Consumes the canvas, as `accessible_svg_string()` does.
    """
    var f = open(path, "w")
    f.write(accessible_svg_string(svg^, title, description))
    f.close()


def _filled_annotations_go_under(mark: Mark) raises -> Bool:
    """Whether `mark` draws its filled annotations -- `annotate_area()`
    bands and `annotate_band()` ribbons -- *under* its geometry. True
    for the continuous-frame marks, where a ribbon is a region the mark
    is meant to be read through, and drawing it last painted
    `Theme.annotation_area_color` over the line it annotates (#501).
    Those marks draw the fills between frame and mark inside
    `_render_generic`; every other mark still draws them after, from
    `_render_into`/`render_svg`, where a band over solid bars was the
    order it always had.
    """
    return (
        mark == Mark.POINT
        or mark == Mark.LINE
        or mark == Mark.AREA
        or mark == Mark.HISTOGRAM
        or mark == Mark.EFFECT_SCATTER
    )


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
    vector_target: Bool = False,
) raises -> _RenderResult:
    """The dispatch, layout, and shape-drawing core `render()`/
    `render_svg()` (and the facet/layer variants) delegate to, generic
    over any `DrawTarget`, returning every axis/tick/legend label as
    `_TextRequest`s.

    `cache` is shared by label measurement and drawing throughout the
    render. `vector_target` is True when `target` keeps what it is given
    as elements rather than pixels (the SVG backend); the one mark that
    cares is `Mark.IMSHOW`, which draws a large grid as an image there
    (see `_draw_cells_as_image`).

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
    (`has_shared_y_domain`) on anything but `Mark.POINT`/`LINE`/`AREA`/
    `EFFECT_SCATTER`, or together with `y_err*`.

    `shared_y_is_log` is `_render_facets_generic`'s own decision,
    already validated there (every cell agrees, `shared_y_min`/
    `shared_y_max` already computed in log10-space via `_log_data_extent`)
    -- this only requires `plot._y_log` to match it, a defensive check
    against calling this directly with an inconsistent combination rather
    than a real per-cell decision point.
    """
    _check_unsupported_flags(plot)
    if plot._secondary_axis:
        raise Error(
            "Plot.secondary_axis() only applies inside render_layers()/"
            "render_layers_svg() -- a standalone plot has only one"
            " series, nothing for a second y-axis to pair against"
        )
    if plot._y_log and plot._y_symlog:
        raise Error(
            "Plot.scale_y_log()/scale_y_symlog(): an axis cannot be both."
            " A log axis has no zero to be linear around, which is the"
            " whole of what symlog adds -- choose one"
        )
    if plot._x_log and plot._x_symlog:
        raise Error(
            "Plot.scale_x_log()/scale_x_symlog(): an axis cannot be both."
            " A log axis has no zero to be linear around, which is the"
            " whole of what symlog adds -- choose one"
        )
    if (
        plot._y_log or plot._x_log or plot._y_symlog or plot._x_symlog
    ) and not plot._mark.supports(Feature.LOG_X):
        raise Error(
            "Plot.scale_y_log()/scale_x_log() only apply to "
            + _supporting_names(Feature.LOG_X)
            + " -- a categorical-x-axis (or other non-continuous) mark has"
            " no continuous domain for a log scale to mean anything against"
        )
    if plot._y_log and not plot._mark.supports(Feature.LOG_Y):
        raise Error(
            "Plot.scale_y_log(): only "
            + _supporting_names(Feature.LOG_Y)
            + " -- the other marks with a continuous x axis force their"
            " y-domain through a zero baseline (see"
            " _zero_baseline_y_extent()'s docstring), and zero has no logarithm"
        )
    if (plot._x_domain.has or plot._y_domain.has) and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.AREA
        or plot._mark == Mark.HISTOGRAM
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
    if (
        plot._x_tick_override.has
        or plot._y_tick_override.has
        or plot._x_reversed
        or plot._y_reversed
        or plot._equal_aspect
    ) and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.AREA
        or plot._mark == Mark.HISTOGRAM
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "Plot.scale_x_ticks()/scale_y_ticks()/scale_x_reverse()/"
            "scale_y_reverse()/equal_aspect() only apply to"
            " Mark.POINT/LINE/AREA/HISTOGRAM/EFFECT_SCATTER today -- the"
            " other marks reach the continuous frame through their own"
            " renders, which do not carry these yet (#368)"
        )
    _validate_tick_override(
        plot._x_tick_override, plot._x_log, "Plot.scale_x_ticks"
    )
    _validate_tick_override(
        plot._y_tick_override, plot._y_log, "Plot.scale_y_ticks"
    )
    if plot._equal_aspect and (plot._x_log or plot._y_log):
        raise Error(
            "Plot.equal_aspect(): not supported on a log-scaled axis -- a"
            " data unit is a different length at each end of a log axis,"
            " so equal pixel lengths for equal data distances is not a"
            " property it can have"
        )
    if plot._equal_aspect and plot._x_time:
        raise Error(
            "Plot.equal_aspect(): not supported on a time axis -- a second"
            " and a unit of y are not comparable lengths, so there is no"
            " aspect to equalize"
        )
    _validate_color_domain(plot)
    if has_shared_y_domain and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.AREA
        or plot._mark == Mark.HISTOGRAM
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "render_facets(shared_y_scale=True): only"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER support a shared y-scale"
            " today -- a categorical or polar mark has no continuous"
            " y-domain for a shared range to mean anything against"
        )
    if has_shared_y_domain and plot._y_log != shared_y_is_log:
        raise Error(
            "render_facets(shared_y_scale=True): every cell must agree on"
            " Plot.scale_y_log() -- got a mix of log and linear cells"
        )
    if has_shared_y_domain and (
        len(plot._y_err.symmetric) > 0
        or len(plot._y_err.lower) > 0
        or len(plot._y_err.upper) > 0
    ):
        # The shared union is computed over plain plot._continuous.y and isn't widened
        # for whisker endpoints, so a whisker could extend past the shared
        # axis.
        raise Error(
            "render_facets(shared_y_scale=True): not supported together with"
            " Plot.encode(y_err=...)/y_err_lower/y_err_upper -- the shared"
            " domain isn't widened for whisker endpoints yet"
        )
    _validate_log_scale_annotations(plot)
    var selected = _call_selected_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache,
        vector_target,
    )
    if selected:
        return selected.take()

    _validate_continuous_encoding(plot, "Plot.encode()")
    _require_non_empty(len(plot._continuous.x), "Plot.encode()")

    var theme = plot._theme

    # Scaled once by theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Built once and handed to both _legend_reserve_for and
    # _draw_point_layer so the two agree; see _PointChannels.
    var ch = _PointChannels(plot, sc)

    var legend_reserve = _legend_reserve_for(plot, ch, sc, cache=cache)

    # Mark.AREA forces a zero baseline into the y-domain; every other
    # continuous mark pads around its data. y_domain_data is plot._continuous.y,
    # or every whisker endpoint when y_err (or y_err_lower/y_err_upper) is
    # set, so the domain spans everything drawn. has_shared_y_domain
    # (render_facets(shared_y_scale=True)) short-circuits that with the
    # caller's precomputed domain.
    var y_domain_data = List[Float64]()
    if len(plot._y_err.symmetric) > 0:
        for i in range(len(plot._continuous.y)):
            y_domain_data.append(
                plot._continuous.y[i] - plot._y_err.symmetric[i]
            )
            y_domain_data.append(
                plot._continuous.y[i] + plot._y_err.symmetric[i]
            )
    elif len(plot._y_err.lower) > 0:
        for i in range(len(plot._continuous.y)):
            y_domain_data.append(plot._continuous.y[i] - plot._y_err.lower[i])
            y_domain_data.append(plot._continuous.y[i] + plot._y_err.upper[i])
    else:
        for v in plot._continuous.y:
            y_domain_data.append(v)
    var y_scale = _domain_override_scale(
        plot._y_domain, plot._y_log
    ) if plot._y_domain.has else (
        LinearScale(
            shared_y_min, shared_y_max, 0.0, 1.0, is_log=shared_y_is_log
        ) if has_shared_y_domain else (
            _log_data_extent(y_domain_data) if plot._y_log else (
                _symlog_data_extent(
                    y_domain_data, plot._y_symlog_linthresh
                ) if plot._y_symlog else (
                    _zero_baseline_y_extent(y_domain_data) if (
                        plot._mark == Mark.AREA
                        or (
                            plot._mark == Mark.HISTOGRAM
                            and not plot._histogram.horizontal
                        )
                    ) else _data_extent(y_domain_data)
                )
            )
        )
    )
    # A horizontal histogram's values run along x, so x takes the zero
    # baseline its y would have had.
    var x_scale = _domain_override_scale(
        plot._x_domain, plot._x_log
    ) if plot._x_domain.has else (
        _log_data_extent(plot._continuous.x) if plot._x_log else (
            _symlog_data_extent(
                plot._continuous.x, plot._x_symlog_linthresh
            ) if plot._x_symlog else (
                _zero_baseline_y_extent(plot._continuous.x) if (
                    plot._mark == Mark.HISTOGRAM and plot._histogram.horizontal
                ) else _data_extent(plot._continuous.x)
            )
        )
    )
    # A time axis is linear in seconds; only its labels differ, so the
    # domain is whatever the branches above computed and the flag simply
    # rides along to `LinearScale.ticks()`.
    if plot._x_time:
        x_scale.is_time = True
        x_scale.tz_offset = plot._x_tz_offset

    var controls = _AxisControls()
    controls.x_ticks = plot._x_tick_override.copy()
    controls.y_ticks = plot._y_tick_override.copy()
    controls.x_reversed = plot._x_reversed
    controls.y_reversed = plot._y_reversed
    controls.equal_aspect = plot._equal_aspect
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
        controls=controls,
        cache=cache,
    )

    # Filled annotations go under the mark (#501): the area bands and
    # ribbons are drawn now, against the finished frame, so the mark is
    # read through them rather than painted over by them. Their labels
    # join the frame's text requests and are replayed with the rest.
    # Stroked and text annotations still draw after the mark.
    var under = frame.result()
    var under_areas = _draw_annotation_areas(
        target, plot, under, theme, cache=cache
    )
    for k in range(len(under_areas)):
        frame.text_requests.append(under_areas[k].copy())
    var under_bands = _draw_annotation_bands(
        target, plot, under, theme, cache=cache
    )
    for k in range(len(under_bands)):
        frame.text_requests.append(under_bands[k].copy())

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
            cache=cache,
        )
    elif plot._mark == Mark.LINE:
        _draw_line_layer(target, plot, frame.x_scale, frame.y_scale)
    elif plot._mark == Mark.AREA:
        _draw_area_layer(target, plot, frame.x_scale, frame.y_scale)
    elif plot._mark == Mark.HISTOGRAM:
        _draw_histogram_layer(
            target, plot, frame.x_scale, frame.y_scale, frame.text_requests
        )

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
    height).labels(...)` would build by hand. Takes `plot` as
    `var` because `Plot`'s builder methods consume and return `Self` and
    `Plot` isn't `ImplicitlyCopyable`.
    """
    return plot^.labels(
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title
    ).theme(theme).size(width, height)


def _callback_continuous[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    mut cache: FontCache,
    vector_target: Bool,
) raises -> Optional[_RenderResult]:
    """Continue through the shared continuous path."""
    return None


def _call_selected_family[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    mut cache: FontCache,
    vector_target: Bool,
) raises -> Optional[_RenderResult]:
    """Invoke the selected callback for this concrete backend."""
    comptime if T == Canvas:
        return plot._render_canvas_family(
            rebind[Canvas](target),
            plot,
            ox0,
            oy0,
            ox1,
            oy1,
            cache,
            vector_target,
        )
    elif T == SvgCanvas:
        return plot._render_svg_family(
            rebind[SvgCanvas](target),
            plot,
            ox0,
            oy0,
            ox1,
            oy1,
            cache,
            vector_target,
        )
    elif T == PdfCanvas:
        return plot._render_pdf_family(
            rebind[PdfCanvas](target),
            plot,
            ox0,
            oy0,
            ox1,
            oy1,
            cache,
            vector_target,
        )
    else:
        comptime assert T == BoundsTarget, "Unsupported family callback target"
        return plot._render_bounds_family(
            rebind[BoundsTarget](target),
            plot,
            ox0,
            oy0,
            ox1,
            oy1,
            cache,
            vector_target,
        )
