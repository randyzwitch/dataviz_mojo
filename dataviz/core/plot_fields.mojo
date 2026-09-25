"""The channel and settings structs every mark shares, which `Plot`
holds as fields: the continuous and categorical positions, the color,
size and label channels, error bars, raw distributions, per-mark style
settings, domain overrides and the title/axis labels. A struct only one
mark family reads lives in that family's file instead.

Split out of plot.mojo."""

from std.collections import Dict
from std.math import pi
from canvas.color import Color
from dataviz.core.line_style import LineStyle
from dataviz.core.stack_baseline import StackBaseline
from dataviz.core.step_style import StepStyle
from dataviz.core.marker import PointShape
from dataviz.core.graph_layout import GraphLayout


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
    a color.

    Field names keep their mark prefix (`gauge_start_angle`) since several
    would otherwise collide (`polar_grid_rings`/`radar_grid_rings`); the
    parameters that set them drop it (`mark_gauge(start_angle=...)`).
    """

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
    var graph_layout: GraphLayout
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
        self.graph_layout = GraphLayout.CIRCLE
        self.streamgraph_baseline = StackBaseline.WIGGLE
        self.eventplot_line_length = 1.0


struct _DomainOverride(Copyable, Movable):
    """An explicit minimum and maximum axis domain set via `.scale_x_domain()`/
    `.scale_y_domain()`, overriding the padded/zero-baselined
    domain `_data_extent()`/`_zero_baseline_y_extent()` would otherwise
    compute. `has` is `False` (the default -- no override) until one of
    those builder methods sets it. Stored on `Plot._settings.x_domain`/`_y_domain`.
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
    set. Stored on `Plot._settings.labels`.
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
