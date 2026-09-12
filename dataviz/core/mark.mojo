"""The geometric primitive a data row becomes: the grammar-of-graphics
`mark`. Same small-struct-with-comptime-constants-and-`__eq__`
pattern as canvas.FillRule/canvas.TextAlign.

Each mark renders in its own file (plot.mojo for POINT/LINE/AREA/
EFFECT_SCATTER, `<mark>.mojo` otherwise); its `_render_*` docstring
describes the drawing. By data shape:

- `encode()` (continuous x/y): POINT, LINE, AREA, EFFECT_SCATTER.
  HISTOGRAM takes `encode_histogram_bins()` (a `HistogramBins`) and
  draws one rectangle per bin at numeric x positions (histogram.mojo);
  it follows AREA's zero-baseline and layering rules.
  BARBS and QUIVER take `encode_barbs()`/`encode_quiver()` (position
  plus u/v components), the same field as barbs or as arrows.
  CONTOUR and CONTOURF take `encode_contour()` (a rectangular
  grid of values, in grid-index coordinates); TRICONTOUR and
  TRICONTOURF take
  `encode_tricontour()` (scattered x/y/z samples, triangulated).
  TRIPLOT and TRIPCOLOR take `encode_triplot()` (the same
  scattered samples, drawn as the triangulation itself).
  POLAR takes `encode_polar()`/`encode_polar_series()` (angle +
  radius); SINGLE_AXIS takes `encode_single_axis()` (x only).
- `encode_categorical()` (category + value): BAR, LOLLIPOP, POINTPLOT,
  ARC
  (pie/donut), FUNNEL, NIGHTINGALE, POLAR_BAR, RADIALBAR. WATERFALL
  takes `encode_waterfall()` (signed deltas); `histogram()` feeds BAR
  through `encode_histogram()`.
- Category + several values: BOX (`encode_boxplot()`), BEESWARM/
  VIOLIN/RIDGELINE (`encode_distribution()`), CANDLESTICK
  (`encode_candlestick()`), BULLET (`encode_bullet()`), GANTT and
  SPAN_CHART (`encode_gantt()`, horizontal and vertical),
  POPULATION_PYRAMID (`encode_population_pyramid()`).
- One flat ungrouped column of observations, drawn on a continuous
  frame: KDE and RUG (`encode_kde()`), ECDF (`encode_ecdf()`).
  POPULATION_PYRAMID (`encode_population_pyramid()`). EVENTPLOT takes
  `encode_eventplot()` (one list of event positions per row, any of
  which may be empty).
- `encode_grouped_bar()` (category x series): GROUPED_BAR,
  STACKED_BAR, BUMP (ranks), STREAMGRAPH. MARIMEKKO takes
  `encode_marimekko()`; RADAR `encode_radar()`; PARALLEL
  `encode_parallel()`; GAUGE `encode_gauge()` (one value).
- Two categorical axes: HEATMAP (`encode_heatmap()`), CORRPLOT
  (`encode_corrplot()`), PUNCHCARD (`encode_punchcard()`),
  CALENDAR_HEATMAP (`encode_calendar()`).
- A 2D array on *continuous* axes (image.mojo): IMSHOW
  (`encode_imshow()`, cell centers on the grid indices) and
  PCOLORMESH (`encode_pcolormesh()`, explicit cell boundaries), and
  HIST2D (`encode_hist2d()`, a grid of counts binned from points,
  hist2d.mojo).
- Points counted into a hexagonal lattice (hexbin.mojo): HEXBIN
  (`encode_hexbin()`).
- A vector field on a grid, integrated into streamlines
  (streamplot.mojo): STREAMPLOT (`encode_streamplot()`).
  Not HEATMAP, which needs one category label per row and column.
- `encode_hierarchy()` (hierarchy.mojo): SUNBURST, TREE, TREEMAP.
- `encode_chord()` (edge list, edges.mojo): CHORD, ARC_DIAGRAM,
  GRAPH, SANKEY.

Vertical categorical marks share `_draw_categorical_axis_frame`
(frame.mojo), horizontal ones `_draw_horizontal_categorical_axis_frame`
(gantt.mojo; EVENTPLOT is one of these), and the two-categorical-axis marks
`_draw_grid_axis_frame` (heatmap.mojo). BAR/BOX/VIOLIN/BEESWARM/
LOLLIPOP/GROUPED_BAR/STACKED_BAR each have a `horizontal=True`
variant.
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
    comptime BARBS = Self(42)
    comptime CONTOUR = Self(43)
    comptime CONTOURF = Self(44)
    comptime TRICONTOUR = Self(45)
    comptime TRICONTOURF = Self(46)
    comptime KDE = Self(47)
    comptime RUG = Self(48)
    comptime TRIPLOT = Self(49)
    comptime TRIPCOLOR = Self(50)
    comptime ECDF = Self(51)
    comptime IMSHOW = Self(52)
    comptime PCOLORMESH = Self(53)
    comptime EVENTPLOT = Self(54)

    comptime POINTPLOT = Self(55)
    comptime BOXENPLOT = Self(56)
    comptime HIST2D = Self(57)
    comptime HEXBIN = Self(58)
    comptime QUIVER = Self(59)
    comptime HISTOGRAM = Self(60)
    comptime STREAMPLOT = Self(61)
    comptime COUNT = 62
    """How many marks exist -- one past the largest value above.

    Only the raster/SVG layout-equivalence sweep reads this: it
    walks `Mark(0)` through `Mark(COUNT - 1)` and requires a
    representative dataset for each, so a mark added without one fails
    loudly instead of silently going untested. Bump it in the same edit
    that adds the mark above.
    """

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def name(self) -> String:
        """Return the qualified constant name used in error messages.

        Returns:
            The constant's qualified name, or `"Mark(<n>)"` for a value
            outside the constants above -- which is reachable, since
            `Mark(n)` is public and the sweep in
            tests/test_backend_equivalence.mojo constructs marks by
            number.
        """
        if self == Self.POINT:
            return "Mark.POINT"
        if self == Self.LINE:
            return "Mark.LINE"
        if self == Self.BAR:
            return "Mark.BAR"
        if self == Self.AREA:
            return "Mark.AREA"
        if self == Self.ARC:
            return "Mark.ARC"
        if self == Self.LOLLIPOP:
            return "Mark.LOLLIPOP"
        if self == Self.POINTPLOT:
            return "Mark.POINTPLOT"
        if self == Self.BOXENPLOT:
            return "Mark.BOXENPLOT"
        if self == Self.HIST2D:
            return "Mark.HIST2D"
        if self == Self.HEXBIN:
            return "Mark.HEXBIN"
        if self == Self.QUIVER:
            return "Mark.QUIVER"
        if self == Self.HISTOGRAM:
            return "Mark.HISTOGRAM"
        if self == Self.STREAMPLOT:
            return "Mark.STREAMPLOT"
        if self == Self.WATERFALL:
            return "Mark.WATERFALL"
        if self == Self.BOX:
            return "Mark.BOX"
        if self == Self.CANDLESTICK:
            return "Mark.CANDLESTICK"
        if self == Self.BULLET:
            return "Mark.BULLET"
        if self == Self.GANTT:
            return "Mark.GANTT"
        if self == Self.GROUPED_BAR:
            return "Mark.GROUPED_BAR"
        if self == Self.STACKED_BAR:
            return "Mark.STACKED_BAR"
        if self == Self.POPULATION_PYRAMID:
            return "Mark.POPULATION_PYRAMID"
        if self == Self.HEATMAP:
            return "Mark.HEATMAP"
        if self == Self.CHORD:
            return "Mark.CHORD"
        if self == Self.SINGLE_AXIS:
            return "Mark.SINGLE_AXIS"
        if self == Self.EFFECT_SCATTER:
            return "Mark.EFFECT_SCATTER"
        if self == Self.FUNNEL:
            return "Mark.FUNNEL"
        if self == Self.BUMP:
            return "Mark.BUMP"
        if self == Self.STREAMGRAPH:
            return "Mark.STREAMGRAPH"
        if self == Self.BEESWARM:
            return "Mark.BEESWARM"
        if self == Self.VIOLIN:
            return "Mark.VIOLIN"
        if self == Self.RIDGELINE:
            return "Mark.RIDGELINE"
        if self == Self.NIGHTINGALE:
            return "Mark.NIGHTINGALE"
        if self == Self.POLAR_BAR:
            return "Mark.POLAR_BAR"
        if self == Self.POLAR:
            return "Mark.POLAR"
        if self == Self.RADAR:
            return "Mark.RADAR"
        if self == Self.GAUGE:
            return "Mark.GAUGE"
        if self == Self.PARALLEL:
            return "Mark.PARALLEL"
        if self == Self.SPAN_CHART:
            return "Mark.SPAN_CHART"
        if self == Self.CALENDAR_HEATMAP:
            return "Mark.CALENDAR_HEATMAP"
        if self == Self.CORRPLOT:
            return "Mark.CORRPLOT"
        if self == Self.PUNCHCARD:
            return "Mark.PUNCHCARD"
        if self == Self.MARIMEKKO:
            return "Mark.MARIMEKKO"
        if self == Self.SUNBURST:
            return "Mark.SUNBURST"
        if self == Self.TREE:
            return "Mark.TREE"
        if self == Self.TREEMAP:
            return "Mark.TREEMAP"
        if self == Self.ARC_DIAGRAM:
            return "Mark.ARC_DIAGRAM"
        if self == Self.GRAPH:
            return "Mark.GRAPH"
        if self == Self.SANKEY:
            return "Mark.SANKEY"
        if self == Self.RADIALBAR:
            return "Mark.RADIALBAR"
        if self == Self.BARBS:
            return "Mark.BARBS"
        if self == Self.CONTOUR:
            return "Mark.CONTOUR"
        if self == Self.CONTOURF:
            return "Mark.CONTOURF"
        if self == Self.TRICONTOUR:
            return "Mark.TRICONTOUR"
        if self == Self.TRICONTOURF:
            return "Mark.TRICONTOURF"
        if self == Self.KDE:
            return "Mark.KDE"
        if self == Self.RUG:
            return "Mark.RUG"
        if self == Self.TRIPLOT:
            return "Mark.TRIPLOT"
        if self == Self.TRIPCOLOR:
            return "Mark.TRIPCOLOR"
        if self == Self.ECDF:
            return "Mark.ECDF"
        if self == Self.IMSHOW:
            return "Mark.IMSHOW"
        if self == Self.PCOLORMESH:
            return "Mark.PCOLORMESH"
        if self == Self.EVENTPLOT:
            return "Mark.EVENTPLOT"
        return "Mark(" + String(self._value) + ")"


def _require_mark(
    mark: Mark, encoder: String, builder: String, accepted: List[Mark]
) raises:
    """Raise unless `mark` is one of `accepted`, naming both sides (#538).

    `Plot` carries every mark's data on one struct with the mark as a
    runtime field, so `Plot().mark_line().encode_boxenplot(...)`
    compiles. Without this it fails later, in the render or as an empty
    chart, with an error naming neither the mark the caller chose nor
    the encoder they called. Mojo 1.0 has no way to make that a type
    error: a trait cannot be a collection's element type, and
    `render_layers()` takes `List[Plot]` (#522).

    The check is here rather than in `render()` on purpose. It costs
    the order `mark_*()` then `encode_*()`, which is now required, and
    buys an error at the call that is wrong rather than one
    reconstructed later from which payload structs are non-empty.

    Args:
        mark: The plot's current mark.
        encoder: The encoder's name, for the message.
        builder: The `mark_*()` call that would fix it.
        accepted: The marks this encoder writes data for.

    Raises:
        Error: `mark` is not in `accepted`.
    """
    for i in range(len(accepted)):
        if mark == accepted[i]:
            return
    var names = String("")
    for i in range(len(accepted)):
        if i > 0:
            names += " or " if i == len(accepted) - 1 else ", "
        names += accepted[i].name()
    raise Error(
        encoder
        + "() needs "
        + names
        + ", but this plot is "
        + mark.name()
        + ". Call "
        + builder
        + " before it."
    )


def _require_mark(
    mark: Mark, encoder: String, builder: String, accepted: Mark
) raises:
    """Single-mark form of `_require_mark`, which most encoders take.

    Args:
        mark: The plot's current mark.
        encoder: The encoder's name, for the message.
        builder: The `mark_*()` call that would fix it.
        accepted: The only mark this encoder writes data for.

    Raises:
        Error: `mark` is not `accepted`.
    """
    var one = List[Mark]()
    one.append(accepted)
    _require_mark(mark, encoder, builder, one)
