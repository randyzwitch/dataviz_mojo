"""The geometric primitive a data row becomes: the grammar-of-graphics
`mark`. Same small-struct-with-comptime-constants-and-`__eq__`
pattern as canvas.FillRule/canvas.TextAlign.

Each mark renders in its own file (rendering.mojo for POINT/LINE/AREA/
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
  takes `encode_waterfall()` (signed deltas); `encode_binned_categories()`
  bins raw values into BAR's labeled categories.
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
- `encode_dendrogram()` (dendrogram.mojo): DENDROGRAM.
- `encode_chord()` (edge list, edges.mojo): CHORD, ARC_DIAGRAM,
  GRAPH, SANKEY.

Vertical categorical marks share `_draw_categorical_axis_frame`
(frame.mojo), horizontal ones `_draw_horizontal_categorical_axis_frame`
(gantt.mojo; EVENTPLOT is one of these), and the two-categorical-axis marks
`_draw_grid_axis_frame` (heatmap.mojo). BAR/BOX/VIOLIN/BEESWARM/
LOLLIPOP/GROUPED_BAR/STACKED_BAR each have a `horizontal=True`
variant.

Adding a mark requires its constant (value and name), an updated
`COUNT`, an entry in `_every_mark()` and a representative plot in
`tests/_mark_registry.mojo`, and a reviewed output digest, and a `Plot.mark_*()` setter that binds its renderer with
`Plot._bind`; see the checklist in `plot.mojo`.
"""


struct Mark(Copyable, ImplicitlyCopyable, Movable):
    """A mark's runtime identity: its value, and its name, which the
    constant states itself so no table maps one to the other (#854)."""

    var _value: Int
    var _name: StaticString

    comptime POINT = Self(0, "POINT")
    comptime LINE = Self(1, "LINE")
    comptime BAR = Self(2, "BAR")
    comptime AREA = Self(3, "AREA")
    comptime ARC = Self(4, "ARC")
    comptime LOLLIPOP = Self(5, "LOLLIPOP")
    comptime WATERFALL = Self(6, "WATERFALL")
    comptime BOX = Self(7, "BOX")
    comptime CANDLESTICK = Self(8, "CANDLESTICK")
    comptime BULLET = Self(9, "BULLET")
    comptime GANTT = Self(10, "GANTT")
    comptime GROUPED_BAR = Self(11, "GROUPED_BAR")
    comptime STACKED_BAR = Self(12, "STACKED_BAR")
    comptime POPULATION_PYRAMID = Self(13, "POPULATION_PYRAMID")
    comptime HEATMAP = Self(14, "HEATMAP")
    comptime CHORD = Self(15, "CHORD")
    comptime SINGLE_AXIS = Self(16, "SINGLE_AXIS")
    comptime EFFECT_SCATTER = Self(17, "EFFECT_SCATTER")
    comptime FUNNEL = Self(18, "FUNNEL")
    comptime BUMP = Self(19, "BUMP")
    comptime STREAMGRAPH = Self(20, "STREAMGRAPH")
    comptime BEESWARM = Self(21, "BEESWARM")
    comptime VIOLIN = Self(22, "VIOLIN")
    comptime RIDGELINE = Self(23, "RIDGELINE")
    comptime NIGHTINGALE = Self(24, "NIGHTINGALE")
    comptime POLAR_BAR = Self(25, "POLAR_BAR")
    comptime POLAR = Self(26, "POLAR")
    comptime RADAR = Self(27, "RADAR")
    comptime GAUGE = Self(28, "GAUGE")
    comptime PARALLEL = Self(29, "PARALLEL")
    comptime SPAN_CHART = Self(30, "SPAN_CHART")
    comptime CALENDAR_HEATMAP = Self(31, "CALENDAR_HEATMAP")
    comptime CORRPLOT = Self(32, "CORRPLOT")
    comptime PUNCHCARD = Self(33, "PUNCHCARD")
    comptime MARIMEKKO = Self(34, "MARIMEKKO")
    comptime SUNBURST = Self(35, "SUNBURST")
    comptime TREE = Self(36, "TREE")
    comptime TREEMAP = Self(37, "TREEMAP")
    comptime ARC_DIAGRAM = Self(38, "ARC_DIAGRAM")
    comptime GRAPH = Self(39, "GRAPH")
    comptime SANKEY = Self(40, "SANKEY")
    comptime RADIALBAR = Self(41, "RADIALBAR")
    comptime BARBS = Self(42, "BARBS")
    comptime CONTOUR = Self(43, "CONTOUR")
    comptime CONTOURF = Self(44, "CONTOURF")
    comptime TRICONTOUR = Self(45, "TRICONTOUR")
    comptime TRICONTOURF = Self(46, "TRICONTOURF")
    comptime KDE = Self(47, "KDE")
    comptime RUG = Self(48, "RUG")
    comptime TRIPLOT = Self(49, "TRIPLOT")
    comptime TRIPCOLOR = Self(50, "TRIPCOLOR")
    comptime ECDF = Self(51, "ECDF")
    comptime IMSHOW = Self(52, "IMSHOW")
    comptime PCOLORMESH = Self(53, "PCOLORMESH")
    comptime EVENTPLOT = Self(54, "EVENTPLOT")

    comptime POINTPLOT = Self(55, "POINTPLOT")
    comptime BOXENPLOT = Self(56, "BOXENPLOT")
    comptime HIST2D = Self(57, "HIST2D")
    comptime HEXBIN = Self(58, "HEXBIN")
    comptime QUIVER = Self(59, "QUIVER")
    comptime HISTOGRAM = Self(60, "HISTOGRAM")
    comptime STREAMPLOT = Self(61, "STREAMPLOT")
    comptime DENDROGRAM = Self(62, "DENDROGRAM")
    comptime SCATTER3D = Self(63, "SCATTER3D")
    comptime PLOT3D = Self(64, "PLOT3D")
    comptime SURFACE3D = Self(65, "SURFACE3D")
    comptime WIRE3D = Self(66, "WIRE3D")
    comptime TRISURF3D = Self(67, "TRISURF3D")
    comptime BAR3D = Self(68, "BAR3D")
    comptime VOXELS = Self(69, "VOXELS")
    comptime STEM3D = Self(70, "STEM3D")
    comptime QUIVER3D = Self(71, "QUIVER3D")
    comptime FILL_BETWEEN3D = Self(72, "FILL_BETWEEN3D")
    comptime COUNT = 73
    """How many marks exist -- one past the largest value above.

    The sweeps walk `_every_mark()` (tests/_mark_registry.mojo), a list
    of the constants above, and require a representative dataset for
    each, so a mark in the list without one fails loudly instead of
    silently going untested.

    `COUNT` is the second record that makes a mark left out of that
    list visible: `test_every_mark_is_listed_once_in_value_order` fails
    unless the list holds exactly `COUNT` marks, valued `0` to
    `COUNT - 1` in order. Raise it in the same edit that adds a mark
    above -- #634 was a mark past `COUNT` that every sweep skipped.
    """

    def __init__(out self, value: Int, name: StaticString):
        """For the constants above, which state both halves; there is no
        `Mark(n)` to build an unnamed mark from a bare number.

        Args:
            value: The mark's value, `0` to `COUNT - 1`.
            name: The constant's own name, without the `Mark.` prefix.
        """
        self._value = value
        self._name = name

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def name(self) -> String:
        """Return the qualified constant name used in error messages:
        `Mark.POINT` for `Mark.POINT`."""
        return "Mark." + String(self._name)
