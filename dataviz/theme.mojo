"""Visual defaults for a Plot (colors, sizes, margins) as one struct
with defaults, rather than optional parameters scattered across
Plot's builder methods. A theme changes how a mark looks, not what
it means. Every `Color` field takes a `dataviz.colors` constant as
readily as a `Color(r, g, b)`: `Theme(mark_color=CORNFLOWERBLUE)`.

`scale` (default 1.0) uniformly multiplies every other pixel-sized
quantity render() computes (font size, margins, point radius, line
width, tick length, legend layout). Pair `Theme(scale=2.0)` with a
canvas twice the width/height to render the same chart at higher
pixel density; the logical layout is identical at every scale.
Separate from `raster_supersample` (default 3), which controls how
much extra antialiasing work `render()`/`render_facets()`/
`render_layers()` do internally before downsampling back to that
logical size -- the two compose multiplicatively rather than
substituting for each other; see `raster_supersample`'s own docstring.

`color_by_sign` (default `False`) makes `Mark.BAR` color negative
bars `mark_color_negative`; `Mark.WATERFALL`/`CANDLESTICK` use that
color unconditionally.

`color_scale_low`/`color_scale_mid`/`color_scale_high` are the three
stops of the continuous color gradient (`ColorScale.from_theme`). The
middle stop exists because interpolating two saturated, hue-opposite
colors in RGB passes through a muddy grey that dominates a legend; a
light neutral grey at 0.5 is what diverging colormaps like
`coolwarm`/`RdBu` do.

`line_smoothing` (default `0.0`) controls how much `_build_line_path`
(plot.mojo) curves a `Mark.LINE`/`AREA` through its points via a
Catmull-Rom-derived cubic Bezier: `0.0` is straight segments, `1.0`
the full curve. Must be in `[0.0, 1.0]`. `Mark.AREA` smooths only
its top edge.

`font_family` (default `"sans-serif"`) is baked into each
`_TextRequest` where it is built, since `render_facets()`/
`render_layers()` combine independently themed `Plot`s into one draw
pass. `"sans-serif"` resolves as a fontconfig generic alias on the
raster path and as a CSS `font-family` value in SVG; a specific
installed font name works in both, but a CSS fallback stack only
means anything on the SVG side.

`title_bold` (default `True`) is the one default here that changes
pre-existing output; `Theme(title_bold=False)` restores the old look.
"""

from std.math import pi

from canvas.color import Color

from dataviz.colors import WHITE
from dataviz.output_format import OutputFormat


struct Theme(ImplicitlyCopyable, Movable):
    var background: Color
    """The canvas's fill color, drawn behind everything else."""
    var mark_color: Color
    """The default ink a mark draws in -- bar fill, line stroke,
    point fill, ... -- whenever no data-driven `color`/`color_categories`
    channel or per-mark override (`mark_color_negative`, a palette,
    ...) applies instead."""
    var axis_color: Color
    """The axis line/tick/frame color."""
    var gridline_color: Color
    """Gridline color, drawn when `show_gridlines` is `True`."""
    var text_color: Color
    """The default text color -- tick labels, the chart title, and
    anywhere else no more specific color field (`subtitle_color`,
    `annotation_color`, ...) applies."""
    var font_size: Float64
    """The base font size, in points, for tick/legend labels --
    scaled by `Theme.scale` the same as every other pixel-sized
    quantity (see `_Scaled`'s docstring, plot.mojo)."""
    var point_radius: Float64
    """The default pixel radius for `Mark.POINT`/`EFFECT_SCATTER`
    markers, before any data-driven `size` channel overrides it."""
    var line_width: Float64
    """The default stroke width, in pixels, for `Mark.LINE`/`AREA`
    and every other stroked mark."""
    var margin_left: Int
    """Reserved pixel space along the plot's left edge, before the
    y-axis's own tick-label width/`margin_buffer` are added on top."""
    var margin_right: Int
    """Reserved pixel space along the plot's right edge, before a
    legend's own reserved width (if any) is added on top."""
    var margin_top: Int
    """Reserved pixel space along the plot's top edge, before a
    title/subtitle's own reserved height (if any) is added on top."""
    var margin_bottom: Int
    """Reserved pixel space along the plot's bottom edge, before an
    x-axis title's own reserved height (if any) is added on top."""
    var show_gridlines: Bool
    """Whether to draw gridlines at all; defaults to `True`."""
    var color_scale_low: Color
    """The low end of the default continuous color gradient (`Plot.
    encode(color=...)`, `Mark.HEATMAP`/`CORRPLOT`/`CALENDAR_HEATMAP`)."""
    var color_scale_mid: Color
    """The midpoint of the default continuous color gradient, a deliberate
    third stop; see the module docstring.
    """
    var color_scale_high: Color
    """The high end of the default continuous color gradient."""
    var size_range_min: Float64
    """The smallest pixel radius a data-driven `size` channel maps
    its column's minimum value to."""
    var size_range_max: Float64
    """The largest pixel radius a data-driven `size` channel maps
    its column's maximum value to."""
    var show_legend: Bool
    """Whether to draw a legend at all, for every mark that has one;
    defaults to `True`."""
    var scale: Float64
    """Uniformly multiplies every other pixel-sized quantity
    `render()` computes (font size, margins, point radius, line
    width, tick length, legend layout, ...); see this struct's own
    module docstring for the full HiDPI-rendering reasoning."""
    var raster_supersample: Int
    """How many times larger than the requested size `render()`/
    `render_facets()`/`render_layers()` draw at internally before
    downsampling back down, for finer anti-aliasing at shape edges (a
    solid interior averages to the same color regardless). Defaults to
    3 (9x the pixel count), matching this package's raster output
    before this field existed. Composes multiplicatively with `scale`,
    not a substitute for it: `scale` changes the *logical* pixel size
    of everything drawn (fonts, margins, line widths, ...) for HiDPI
    output, while this only controls how much extra antialiasing work
    a raster render pays before shrinking back to that logical size --
    `render_svg()`/`render_facets_svg()`/`render_layers_svg()` ignore
    it entirely, since vector output has no downsample step. Lower it
    (1 disables supersampling outright) to trade edge quality for speed
    in batch rendering, or to get exact single-pixel raster output for
    a test. Must be `>= 1`; checked where it's read (`render()`/
    `render_facets()`/`render_layers()`), not eagerly here, matching
    `line_smoothing`'s deferred-to-render-time validation.
    """
    var color_by_sign: Bool
    """Whether `Mark.BAR` colors each bar by whether its value is
    negative (`mark_color_negative`) or not (`mark_color`); defaults
    to `False` (every bar stays `mark_color`)."""
    var mark_color_negative: Color
    """The ink for a negative value -- `Mark.BAR` when `color_by_sign`
    is `True`, and unconditionally for `Mark.WATERFALL`/`CANDLESTICK`,
    whose falling/down coloring isn't optional."""
    var bullet_range_color_light: Color
    """The lightest end of `Mark.BULLET`'s grayscale qualitative-range
    band gradient (lowest range index)."""
    var bullet_range_color_dark: Color
    """The darkest end of `Mark.BULLET`'s grayscale qualitative-range
    band gradient (highest range index)."""
    var waterfall_total_color: Color
    """`Mark.WATERFALL`'s color for a row `encode_waterfall()`'s `is_total`
    marks as a running-total checkpoint, distinct from `mark_color`/
    `mark_color_negative`.
    """
    var radialbar_track_color: Color
    """The unfilled background track `Mark.RADIALBAR` sweeps its
    rings over."""
    var treemap_label_color: Color
    """The label color drawn on a `Mark.TREEMAP` leaf rectangle."""
    var radar_fill_alpha: UInt8
    """The opacity `Mark.RADAR` blends each series' filled polygon at before
    flattening against white; a separate field from `halo_alpha`.
    """
    var shape_by_category: Bool
    """Whether `Mark.POINT`/`SINGLE_AXIS`/`EFFECT_SCATTER` draws each
    `color_categories` row with a distinct point shape (`PointShape`,
    marker.mojo) on top of its color, cycling `default_marker_shapes()`
    the same `% len` way the palette cycles. Defaults to `False`. A no-op
    without `color_categories`. Redundant coding for charts viewed
    without reliable color: a legend row's shape and color identify the
    same category.
    """
    var line_smoothing: Float64
    """How much `Mark.LINE`/`AREA` curves through its data points, via
    a Catmull-Rom-derived spline -- `0.0` (the default) draws plain
    straight segments; `1.0` the full curve; must be in `[0.0, 1.0]`."""
    var title_font_size: Float64
    """The chart title's font size, in points; 18.0 against `font_size`'s
    12.0 for tick/legend labels, scaled by `scale` like every other size.
    """
    var subtitle_font_size: Float64
    """The subtitle's font size, in points -- the same size an axis
    title uses, both reading as a subordinate label under the title."""
    var subtitle_color: Color
    """The subtitle's dedicated color, distinct from `text_color` so
    it recedes as supporting context rather than competing with the
    title."""
    var axis_title_font_size: Float64
    """The x/y-axis title's font size, in points."""
    var annotation_color: Color
    """`Plot.annotate_line()`/`annotate_vline()`/`annotate_point()`/
    `annotate_best_fit()`'s color, for the mark and its label. Distinct
    from `mark_color` (an annotation is not data) and from `axis_color`/
    `gridline_color` (it should read as more present than chrome).
    """
    var annotation_area_color: Color
    """`Plot.annotate_area()`/`annotate_band()`'s fill, with real alpha
    (`a=200`) so the mark underneath shows through; both canvas backends
    composite `Color.a`. Label text still uses `annotation_color`.
    """
    var font_family: String
    """Every `_TextRequest`'s typeface; defaults to `"sans-serif"`, a
    generic keyword both the raster (fontconfig) and SVG (CSS) text
    backends resolve consistently."""
    var title_bold: Bool
    """Whether the chart title draws bold; defaults to `True`. The one field
    whose default changes pre-existing renders; see the module docstring.
    """
    var halo_alpha: UInt8
    """The opacity `Mark.EFFECT_SCATTER` blends each point's halo at before
    flattening it against white (`_lighten`, plot.mojo).
    """
    var tick_length: Int
    """The pixel length of each axis tick mark."""
    var label_gap: Int
    """The pixel gap between a tick mark and its label."""
    var legend_width: Int
    """The reserved pixel width for a legend's swatch-plus-label
    column, when its dynamic width can't be computed some other way."""
    var legend_swatch_size: Int
    """The pixel size of each legend entry's color swatch."""
    var legend_row_gap: Int
    """The pixel gap between consecutive legend entries."""
    var continuous_legend_bar_width: Int
    """The pixel width of a continuous (gradient) legend's color bar."""
    var continuous_legend_bar_height: Int
    """The pixel height of a continuous (gradient) legend's color
    bar."""
    var margin_buffer: Int
    """Extra breathing-room padding, in pixels, added after a
    margin's own tick-label-width/tick-length/label-gap computation."""
    var error_bar_cap_width: Float64
    """Half the pixel width of the horizontal cap `Plot.encode()`'s `y_err`
    channel draws at each end of an error bar. `Mark.BOX`'s whisker caps
    are sized from the band width instead.
    """
    var output_format: OutputFormat
    """The file format `save()` (plot.mojo) writes when given a `Plot` and a
    path; defaults to `OutputFormat.SVG`. `render()`/`render_svg()`
    ignore this field.
    """
    var svg_tooltips: Bool
    """Whether each datum gets an SVG `<title>`, which a browser shows as a
    hover tooltip; `True` by default, and a no-op on the raster backend.

    Emitted through `DrawTarget.begin_annotated_group`/
    `end_annotated_group` (canvas_mojo >= 0.13.0), so one datum's
    primitives (a box plot's box, whiskers, caps and median) share one
    tooltip. `SvgCanvas` turns that into `<g><title>...</title>...</g>`;
    `Canvas` ignores both calls. Titles are XML-escaped by canvas_mojo.

    The category-grouped marks (`Mark.BAR`, `GROUPED_BAR`, `STACKED_BAR`,
    `BOX`, `LOLLIPOP`, `VIOLIN`) carry titles under this flag alone. The
    point-per-datum marks (`POINT`, `EFFECT_SCATTER`, `BEESWARM`) also
    need their mark's `tooltips=True`, since a title roughly doubles a
    dense scatter's SVG.
    """
    var show_data_labels: Bool
    """Whether `Mark.BAR`/`GROUPED_BAR`/`STACKED_BAR` draws each bar's value
    as text, in `text_color` at `font_size`; defaults to `False`.
    Formatted via `_label_decimals()` (scale.mojo), the fewest decimal
    places that represent the value exactly, rather than the y-axis's
    coarser `Ticks.decimals`. A `Theme` flag rather than an `encode()`
    channel, like `color_by_sign`.
    """

    def __init__(
        out self,
        background: Color = WHITE,
        mark_color: Color = Color(30, 100, 180),
        axis_color: Color = Color(80, 80, 80),
        gridline_color: Color = Color(225, 225, 225),
        text_color: Color = Color(40, 40, 40),
        font_size: Float64 = 12.0,
        point_radius: Float64 = 3.5,
        line_width: Float64 = 2.0,
        margin_left: Int = 60,
        margin_right: Int = 20,
        margin_top: Int = 20,
        margin_bottom: Int = 50,
        show_gridlines: Bool = True,
        color_scale_low: Color = Color(60, 110, 200),
        color_scale_mid: Color = Color(235, 235, 235),
        color_scale_high: Color = Color(220, 90, 40),
        size_range_min: Float64 = 3.0,
        size_range_max: Float64 = 15.0,
        show_legend: Bool = True,
        scale: Float64 = 1.0,
        raster_supersample: Int = 3,
        color_by_sign: Bool = False,
        mark_color_negative: Color = Color(200, 60, 60),
        bullet_range_color_light: Color = Color(224, 224, 224),
        bullet_range_color_dark: Color = Color(120, 120, 120),
        waterfall_total_color: Color = Color(100, 100, 100),
        radialbar_track_color: Color = Color(230, 230, 230),
        treemap_label_color: Color = Color(255, 255, 255),
        radar_fill_alpha: UInt8 = 90,
        shape_by_category: Bool = False,
        line_smoothing: Float64 = 0.0,
        title_font_size: Float64 = 18.0,
        subtitle_font_size: Float64 = 14.0,
        subtitle_color: Color = Color(110, 110, 110),
        axis_title_font_size: Float64 = 14.0,
        annotation_color: Color = Color(150, 150, 150),
        annotation_area_color: Color = Color(224, 236, 246, 200),
        font_family: String = "sans-serif",
        title_bold: Bool = True,
        halo_alpha: UInt8 = 90,
        tick_length: Int = 5,
        label_gap: Int = 4,
        legend_width: Int = 130,
        legend_swatch_size: Int = 14,
        legend_row_gap: Int = 8,
        continuous_legend_bar_width: Int = 14,
        continuous_legend_bar_height: Int = 100,
        margin_buffer: Int = 8,
        error_bar_cap_width: Float64 = 4.0,
        output_format: OutputFormat = OutputFormat.SVG,
        svg_tooltips: Bool = True,
        show_data_labels: Bool = False,
    ):
        """Construct a `Theme`, overriding any subset of its fields by keyword.
        Every parameter is one field with the same name and default; see
        each field's docstring.
        """
        self.background = background
        self.mark_color = mark_color
        self.axis_color = axis_color
        self.gridline_color = gridline_color
        self.text_color = text_color
        self.font_size = font_size
        self.point_radius = point_radius
        self.line_width = line_width
        self.margin_left = margin_left
        self.margin_right = margin_right
        self.margin_top = margin_top
        self.margin_bottom = margin_bottom
        self.show_gridlines = show_gridlines
        self.color_scale_low = color_scale_low
        self.color_scale_mid = color_scale_mid
        self.color_scale_high = color_scale_high
        self.size_range_min = size_range_min
        self.size_range_max = size_range_max
        self.show_legend = show_legend
        self.scale = scale
        self.raster_supersample = raster_supersample
        self.color_by_sign = color_by_sign
        self.mark_color_negative = mark_color_negative
        self.bullet_range_color_light = bullet_range_color_light
        self.bullet_range_color_dark = bullet_range_color_dark
        self.waterfall_total_color = waterfall_total_color
        self.radialbar_track_color = radialbar_track_color
        self.treemap_label_color = treemap_label_color
        self.radar_fill_alpha = radar_fill_alpha
        self.shape_by_category = shape_by_category
        self.line_smoothing = line_smoothing
        self.title_font_size = title_font_size
        self.subtitle_font_size = subtitle_font_size
        self.subtitle_color = subtitle_color
        self.axis_title_font_size = axis_title_font_size
        self.annotation_color = annotation_color
        self.annotation_area_color = annotation_area_color
        self.font_family = font_family
        self.title_bold = title_bold
        self.halo_alpha = halo_alpha
        self.tick_length = tick_length
        self.label_gap = label_gap
        self.legend_width = legend_width
        self.legend_swatch_size = legend_swatch_size
        self.legend_row_gap = legend_row_gap
        self.continuous_legend_bar_width = continuous_legend_bar_width
        self.continuous_legend_bar_height = continuous_legend_bar_height
        self.margin_buffer = margin_buffer
        self.error_bar_cap_width = error_bar_cap_width
        self.output_format = output_format
        self.svg_tooltips = svg_tooltips
        self.show_data_labels = show_data_labels

    @staticmethod
    def default() -> Self:
        """`Theme()` under a name that reads clearly at call sites like
        `.theme(Theme.default())`.
        """
        return Self()
