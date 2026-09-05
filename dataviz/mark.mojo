"""The geometric primitive a data row becomes: the grammar-of-graphics
`mark`. Same small-struct-with-comptime-constants-and-`__eq__`
pattern as canvas.FillRule/canvas.TextAlign.

Each mark renders in its own file (plot.mojo for POINT/LINE/AREA/
EFFECT_SCATTER, `<mark>.mojo` otherwise); its `_render_*` docstring
describes the drawing. By data shape:

- `encode()` (continuous x/y): POINT, LINE, AREA, EFFECT_SCATTER.
  BARBS takes `encode_barbs()` (position plus u/v components).
  POLAR takes `encode_polar()`/`encode_polar_series()` (angle +
  radius); SINGLE_AXIS takes `encode_single_axis()` (x only).
- `encode_categorical()` (category + value): BAR, LOLLIPOP, ARC
  (pie/donut), FUNNEL, NIGHTINGALE, POLAR_BAR, RADIALBAR. WATERFALL
  takes `encode_waterfall()` (signed deltas); `histogram()` feeds BAR
  through `encode_histogram()`.
- Category + several values: BOX (`encode_boxplot()`), BEESWARM/
  VIOLIN/RIDGELINE (`encode_distribution()`), CANDLESTICK
  (`encode_candlestick()`), BULLET (`encode_bullet()`), GANTT and
  SPAN_CHART (`encode_gantt()`, horizontal and vertical),
  POPULATION_PYRAMID (`encode_population_pyramid()`).
- `encode_grouped_bar()` (category x series): GROUPED_BAR,
  STACKED_BAR, BUMP (ranks), STREAMGRAPH. MARIMEKKO takes
  `encode_marimekko()`; RADAR `encode_radar()`; PARALLEL
  `encode_parallel()`; GAUGE `encode_gauge()` (one value).
- Two categorical axes: HEATMAP (`encode_heatmap()`), CORRPLOT
  (`encode_corrplot()`), PUNCHCARD (`encode_punchcard()`),
  CALENDAR_HEATMAP (`encode_calendar()`).
- `encode_hierarchy()` (hierarchy.mojo): SUNBURST, TREE, TREEMAP.
- `encode_chord()` (edge list, edges.mojo): CHORD, ARC_DIAGRAM,
  GRAPH, SANKEY.

Vertical categorical marks share `_draw_categorical_axis_frame`
(plot.mojo), horizontal ones `_draw_horizontal_categorical_axis_frame`
(gantt.mojo), and the two-categorical-axis marks
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

    comptime COUNT = 43
    """How many marks exist -- one past the largest value above.

    Only the raster/SVG layout-equivalence sweep reads this (#221): it
    walks `Mark(0)` through `Mark(COUNT - 1)` and requires a
    representative dataset for each, so a mark added without one fails
    loudly instead of silently going untested. Bump it in the same edit
    that adds the mark above.
    """

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
