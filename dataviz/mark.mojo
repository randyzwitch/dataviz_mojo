"""The geometric primitive a data row becomes: the grammar-of-graphics
`mark`. Same small-struct-with-comptime-constants-and-`__eq__`
pattern as canvas.FillRule/canvas.TextAlign.

Each mark renders in its own file (plot.mojo for POINT/LINE/AREA/
EFFECT_SCATTER, `<mark>.mojo` otherwise); its `_render_*` docstring
describes the drawing. By data shape:

- `encode()` (continuous x/y): POINT, LINE, AREA, EFFECT_SCATTER.
  BARBS takes `encode_barbs()` (position plus u/v components).
  CONTOUR and CONTOURF take `encode_contour()` (a rectangular
  grid of values, in grid-index coordinates); TRICONTOUR and
  TRICONTOURF take
  `encode_tricontour()` (scattered x/y/z samples, triangulated).
  TRIPLOT and TRIPCOLOR take `encode_triplot()` (the same
  scattered samples, drawn as the triangulation itself).
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
(frame.mojo), horizontal ones `_draw_horizontal_categorical_axis_frame`
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
    comptime CONTOUR = Self(43)
    comptime CONTOURF = Self(44)
    comptime TRICONTOUR = Self(45)
    comptime TRICONTOURF = Self(46)
    comptime KDE = Self(47)
    comptime RUG = Self(48)
    comptime TRIPLOT = Self(49)
    comptime TRIPCOLOR = Self(50)

    comptime COUNT = 51
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

    def name(self) -> String:
        """This mark's constant name, spelled the way a caller writes it:
        `Mark.POINT`, `Mark.TRICONTOURF`, and so on.

        Exists for error messages. Every other value a raise here needs
        to name already has this -- `StepStyle.name()`, and
        `_check_step_smoothing`'s own message calls it -- so a mark being
        the one thing an error could not name was the asymmetry (#415).
        Two messages were visibly worse for it: `render_layers()`'s
        allow-list could only say "layer 1 is a different mark" and then
        list marks the caller had not used, and
        `_check_step_smoothing` picked its setter name from a chain of
        `==` that grew a branch per mark gaining a `step`.

        Returns the qualified spelling rather than the bare constant
        (`"Mark.BAR"`, not `"BAR"`) because that is what the reader has
        to go type. `StepStyle.name()` returns the bare form, but its
        messages already supply the `StepStyle.` around it; a mark name
        is dropped into prose where nothing else says which type it is.

        Rejected: a positional `List[String]` indexed by `_value`, which
        is half the lines but ties each name to a number nothing checks
        -- inserting a mark mid-list would silently rename every mark
        after it. The chain below names each constant twice on adjacent
        lines instead, and compares against the constant rather than
        against a literal integer, so a wrong pairing is visible at the
        edit and a wrong *number* is impossible.
        `Stringable`/`__str__` was rejected too: `String(mark)` reads as
        "this mark's value as text", and conforming would let a mark
        interpolate into user-facing output that was never meant to
        carry an internal constant's spelling.

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
        return "Mark(" + String(self._value) + ")"
