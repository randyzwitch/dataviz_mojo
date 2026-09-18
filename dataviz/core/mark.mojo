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
- `encode_dendrogram()` (dendrogram.mojo): DENDROGRAM.
- `encode_chord()` (edge list, edges.mojo): CHORD, ARC_DIAGRAM,
  GRAPH, SANKEY.

Vertical categorical marks share `_draw_categorical_axis_frame`
(frame.mojo), horizontal ones `_draw_horizontal_categorical_axis_frame`
(gantt.mojo; EVENTPLOT is one of these), and the two-categorical-axis marks
`_draw_grid_axis_frame` (heatmap.mojo). BAR/BOX/VIOLIN/BEESWARM/
LOLLIPOP/GROUPED_BAR/STACKED_BAR each have a `horizontal=True`
variant.

Adding a mark requires its constant and name, an updated `COUNT`, a
representative plot in `tests/_mark_registry.mojo`, and a reviewed output
digest. Its `Plot.mark_*()` setter must bind its family's Canvas, SVG,
PDF, and BoundsTarget callbacks; see the checklist in `plot.mojo`.
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
    comptime DENDROGRAM = Self(62)
    comptime SCATTER3D = Self(63)
    comptime PLOT3D = Self(64)
    comptime SURFACE3D = Self(65)
    comptime WIRE3D = Self(66)
    comptime TRISURF3D = Self(67)
    comptime BAR3D = Self(68)
    comptime VOXELS = Self(69)
    comptime STEM3D = Self(70)
    comptime QUIVER3D = Self(71)
    comptime FILL_BETWEEN3D = Self(72)
    comptime COUNT = 73
    """How many marks exist -- one past the largest value above.

    The layout, output-digest, and callback ownership sweeps read this.
    Each walks `Mark(0)` through `Mark(COUNT - 1)` and requires a
    representative dataset for each, so a mark *below* `COUNT` added
    without one fails loudly instead of silently going untested.

    That protection does not reach `COUNT` itself. A mark added at or
    past it is never visited, so every sweep skips it and nothing fails
    -- which is how #634 happened. Raise it in the same edit that adds
    the mark above. `test_count_is_one_past_the_last_named_mark` fails
    when it is not, by asking `name()` whether the value at `COUNT` has
    a constant.
    """

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def supports(self, feature: Feature) -> Bool:
        """Whether this mark honors `feature`, a `Theme` flag or `Plot`
        setting that only some marks do (#213). One table,
        `_marks_supporting()`, answers this, drives the validators'
        error messages and the docs' feature-support page, and is
        checked against every mark's rendered output by
        tests/test_feature_support.mojo.

        Args:
            feature: The flag or setting.

        Returns:
            True when this mark honors it.
        """
        for mark in _marks_supporting(feature):
            if mark == self:
                return True
        return False

    def name(self) -> String:
        """Return the qualified constant name used in error messages.

        Returns:
            The constant's qualified name, or `"Mark(<n>)"` for a value
            outside the constants above -- which is reachable, since
            `Mark(n)` is public and the sweep in
            tests/test_rendering.mojo constructs marks by
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
        if self == Self.DENDROGRAM:
            return "Mark.DENDROGRAM"
        if self == Self.SCATTER3D:
            return "Mark.SCATTER3D"
        if self == Self.PLOT3D:
            return "Mark.PLOT3D"
        if self == Self.SURFACE3D:
            return "Mark.SURFACE3D"
        if self == Self.WIRE3D:
            return "Mark.WIRE3D"
        if self == Self.TRISURF3D:
            return "Mark.TRISURF3D"
        if self == Self.BAR3D:
            return "Mark.BAR3D"
        if self == Self.VOXELS:
            return "Mark.VOXELS"
        if self == Self.STEM3D:
            return "Mark.STEM3D"
        if self == Self.QUIVER3D:
            return "Mark.QUIVER3D"
        if self == Self.FILL_BETWEEN3D:
            return "Mark.FILL_BETWEEN3D"
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


struct Feature(Copyable, ImplicitlyCopyable, Movable):
    """A `Theme` flag or `Plot` setting that only some marks honor, so
    that which ones is written down once (#213).

    `Mark.supports(feature)` reads `_marks_supporting()` below, and so
    do the validators' error messages, the docs' feature-support page
    (scripts/gen_example_docs.mojo) and tests/test_feature_support.mojo,
    which renders every mark with each feature turned on and checks the
    table against what the code does. Before this table the same lists
    were restated in five docstrings and error strings, and two of them
    had gone stale within a few PRs of being written.

    Same small-struct-with-comptime-constants-and-`__eq__` pattern as
    `Mark`.
    """

    var _value: Int

    comptime TOOLTIPS = Self(0)
    """`Theme.svg_tooltips`: each datum gets an SVG `<title>`. The
    point-per-datum marks also need their own function's
    `tooltips=True`, since a title roughly doubles a dense scatter's
    SVG."""
    comptime DATA_LABELS = Self(1)
    """`Theme.show_data_labels`: each value drawn as text."""
    comptime HORIZONTAL = Self(2)
    """`horizontal=True` on the mark's function or `mark_*()` setter,
    swapping the axes. GANTT, SPAN_CHART and EVENTPLOT are horizontal
    by construction and take no flag."""
    comptime ANNOTATIONS_Y = Self(3)
    """`annotate_line()` and `annotate_area()`: the mark has a
    continuous y axis to place a reference line or band against."""
    comptime ANNOTATIONS_X = Self(4)
    """`annotate_vline()`: the mark has a continuous x axis."""
    comptime ANNOTATIONS_XY = Self(5)
    """`annotate_band()`, `annotate_point()`, `annotate_arrow()` and
    `annotate_best_fit()`: the mark has continuous x and y axes, so
    the marks in both `ANNOTATIONS_X` and `ANNOTATIONS_Y`."""
    comptime LOG_X = Self(6)
    """`scale_x_log()`."""
    comptime LOG_Y = Self(7)
    """`scale_y_log()`. AREA and HISTOGRAM take `scale_x_log()` but not
    this: their y domain is forced through a zero baseline, and zero
    has no logarithm."""
    comptime COLOR_SIZE = Self(8)
    """`encode(color=, color_categories=, size=)` and
    `encode_single_axis()`'s same channels: a value or category per
    point drives its color or size."""
    comptime COUNT = 9

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def name(self) -> String:
        """The constant's qualified name, `"Feature.TOOLTIPS"`."""
        if self == Self.TOOLTIPS:
            return "Feature.TOOLTIPS"
        if self == Self.DATA_LABELS:
            return "Feature.DATA_LABELS"
        if self == Self.HORIZONTAL:
            return "Feature.HORIZONTAL"
        if self == Self.ANNOTATIONS_Y:
            return "Feature.ANNOTATIONS_Y"
        if self == Self.ANNOTATIONS_X:
            return "Feature.ANNOTATIONS_X"
        if self == Self.ANNOTATIONS_XY:
            return "Feature.ANNOTATIONS_XY"
        if self == Self.LOG_X:
            return "Feature.LOG_X"
        if self == Self.LOG_Y:
            return "Feature.LOG_Y"
        if self == Self.COLOR_SIZE:
            return "Feature.COLOR_SIZE"
        return "Feature(" + String(self._value) + ")"

    def label(self) -> String:
        """What a user sets: the column heading on the feature-support
        page, in Markdown."""
        if self == Self.TOOLTIPS:
            return "`Theme.svg_tooltips`"
        if self == Self.DATA_LABELS:
            return "`Theme.show_data_labels`"
        if self == Self.HORIZONTAL:
            return "`horizontal=True`"
        if self == Self.ANNOTATIONS_Y:
            return "`annotate_line()`, `annotate_area()`"
        if self == Self.ANNOTATIONS_X:
            return "`annotate_vline()`"
        if self == Self.ANNOTATIONS_XY:
            return "`annotate_band()`, `point`, `arrow`, `best_fit`"
        if self == Self.LOG_X:
            return "`scale_x_log()`"
        if self == Self.LOG_Y:
            return "`scale_y_log()`"
        if self == Self.COLOR_SIZE:
            return "`encode(color=, size=)`"
        return self.name()

    def summary(self) -> String:
        """One line for the feature-support page's notes: what the
        feature does, and what an unsupported mark does with it."""
        if self == Self.TOOLTIPS:
            return (
                "each datum gets an SVG `<title>`, shown as a hover tooltip;"
                " other marks ignore the flag. POINT, EFFECT_SCATTER and"
                " BEESWARM also need their own function's `tooltips=True`."
            )
        if self == Self.DATA_LABELS:
            return "each value is drawn as text; other marks ignore the flag."
        if self == Self.HORIZONTAL:
            return (
                "the axes swap; other marks ignore the flag. GANTT,"
                " SPAN_CHART and EVENTPLOT are horizontal by construction"
                " and take no flag."
            )
        if self == Self.ANNOTATIONS_Y:
            return (
                "a reference line or shaded band across a continuous y"
                " axis; the call raises on other marks."
            )
        if self == Self.ANNOTATIONS_X:
            return (
                "a reference line across a continuous x axis; the call"
                " raises on other marks."
            )
        if self == Self.ANNOTATIONS_XY:
            return (
                "overlays placed on continuous x and y axes; the call"
                " raises on other marks."
            )
        if self == Self.LOG_X:
            return "a logarithmic x axis; the call raises on other marks."
        if self == Self.LOG_Y:
            return (
                "a logarithmic y axis; the call raises on other marks."
                " AREA and HISTOGRAM force their y domain through zero,"
                " which has no logarithm."
            )
        if self == Self.COLOR_SIZE:
            return (
                "a value or category per point drives its color or size;"
                " the call raises on other marks."
            )
        return ""


def _marks_supporting(feature: Feature) -> List[Mark]:
    """The marks that honor `feature`, in `Mark` order: the one table
    behind `Mark.supports()`, the validators' messages and the docs.

    The annotation and log-scale rows are what the render's frame
    reports (`_RenderResult.has_x_scale`/`has_y_scale`) and what the
    scale validators accept; tests/test_feature_support.mojo fails if
    either side moves without this table.
    """
    var out = List[Mark]()
    if feature == Feature.TOOLTIPS:
        out = [
            Mark.POINT,
            Mark.BAR,
            Mark.LOLLIPOP,
            Mark.WATERFALL,
            Mark.BOX,
            Mark.CANDLESTICK,
            Mark.BULLET,
            Mark.GROUPED_BAR,
            Mark.STACKED_BAR,
            Mark.POPULATION_PYRAMID,
            Mark.EFFECT_SCATTER,
            Mark.FUNNEL,
            Mark.BEESWARM,
            Mark.VIOLIN,
            Mark.SPAN_CHART,
            # Opt-in, like POINT and EFFECT_SCATTER: each draws one
            # primitive per datum, so a group can wrap it (#683). The
            # mesh marks (BAR3D, VOXELS, SURFACE3D, TRISURF3D) cannot:
            # they depth-sort every face and emit one `fill_mesh`.
            Mark.SINGLE_AXIS,
            Mark.SCATTER3D,
            # One cell, one title, under the theme flag alone (#679):
            # a grid encodes its value as a color or a radius, so the
            # title is the only way to read the number back.
            Mark.HEATMAP,
            Mark.CALENDAR_HEATMAP,
            Mark.CORRPLOT,
            Mark.PUNCHCARD,
            Mark.MARIMEKKO,
            # The radial family (#680), under the theme flag alone:
            # one title per wedge, ring row or point. RADAR's unit is
            # the series, not the vertex -- the shape a reader points
            # at is the whole ring -- and GAUGE draws one value.
            Mark.NIGHTINGALE,
            Mark.POLAR_BAR,
            Mark.POLAR,
            Mark.RADAR,
            Mark.GAUGE,
            Mark.RADIALBAR,
            # The rest of the categorical family (#677). BUMP and
            # STREAMGRAPH are titled per series, not per step: the line
            # or band is the shape a reader points at, and its value
            # changes at every category it crosses.
            Mark.ARC,
            Mark.GANTT,
            Mark.BUMP,
            Mark.STREAMGRAPH,
        ]
    elif feature == Feature.DATA_LABELS:
        out = [
            Mark.BAR,
            Mark.LOLLIPOP,
            Mark.WATERFALL,
            Mark.BULLET,
            Mark.GROUPED_BAR,
            Mark.STACKED_BAR,
            Mark.POPULATION_PYRAMID,
            # The radial value marks (#685): the label sits just beyond
            # the wedge's outer edge, on the angle that bisects it.
            # GAUGE is absent on purpose -- it draws its value under
            # the hub unconditionally, which is the point of that
            # chart, not something this flag turns on.
            Mark.NIGHTINGALE,
            Mark.POLAR_BAR,
            Mark.RADIALBAR,
        ]
    elif feature == Feature.HORIZONTAL:
        out = [
            Mark.BAR,
            Mark.LOLLIPOP,
            Mark.BOX,
            Mark.GROUPED_BAR,
            Mark.STACKED_BAR,
            Mark.BEESWARM,
            Mark.VIOLIN,
            Mark.BOXENPLOT,
            Mark.HISTOGRAM,
        ]
    elif feature == Feature.ANNOTATIONS_Y:
        out = [
            Mark.POINT,
            Mark.LINE,
            Mark.BAR,
            Mark.AREA,
            Mark.LOLLIPOP,
            Mark.WATERFALL,
            Mark.BOX,
            Mark.CANDLESTICK,
            Mark.BULLET,
            Mark.GROUPED_BAR,
            Mark.STACKED_BAR,
            Mark.EFFECT_SCATTER,
            Mark.STREAMGRAPH,
            Mark.BEESWARM,
            Mark.VIOLIN,
            Mark.SPAN_CHART,
            Mark.BARBS,
            Mark.CONTOUR,
            Mark.CONTOURF,
            Mark.TRICONTOUR,
            Mark.TRICONTOURF,
            Mark.KDE,
            Mark.TRIPLOT,
            Mark.TRIPCOLOR,
            Mark.ECDF,
            Mark.IMSHOW,
            Mark.PCOLORMESH,
            Mark.POINTPLOT,
            Mark.BOXENPLOT,
            Mark.HIST2D,
            Mark.HEXBIN,
            Mark.QUIVER,
            Mark.HISTOGRAM,
            Mark.STREAMPLOT,
            Mark.DENDROGRAM,
        ]
    elif feature == Feature.ANNOTATIONS_X:
        out = [
            Mark.POINT,
            Mark.LINE,
            Mark.AREA,
            Mark.EFFECT_SCATTER,
            Mark.BARBS,
            Mark.CONTOUR,
            Mark.CONTOURF,
            Mark.TRICONTOUR,
            Mark.TRICONTOURF,
            Mark.KDE,
            Mark.RUG,
            Mark.TRIPLOT,
            Mark.TRIPCOLOR,
            Mark.ECDF,
            Mark.IMSHOW,
            Mark.PCOLORMESH,
            Mark.HIST2D,
            Mark.HEXBIN,
            Mark.QUIVER,
            Mark.HISTOGRAM,
            Mark.STREAMPLOT,
            # Drawn through `_draw_horizontal_categorical_axis_frame`,
            # whose continuous axis is x (#688). The marks that reach
            # that frame only under `horizontal=True` -- BAR, BOX,
            # VIOLIN and the rest of Feature.HORIZONTAL -- gain a vline
            # in that orientation too; this table describes each mark's
            # default orientation.
            Mark.GANTT,
            Mark.POPULATION_PYRAMID,
            Mark.RIDGELINE,
            Mark.EVENTPLOT,
        ]
    elif feature == Feature.ANNOTATIONS_XY:
        for mark in _marks_supporting(Feature.ANNOTATIONS_X):
            if mark.supports(Feature.ANNOTATIONS_Y):
                out.append(mark)
    elif feature == Feature.LOG_X:
        out = [
            Mark.POINT,
            Mark.LINE,
            Mark.AREA,
            Mark.EFFECT_SCATTER,
            Mark.HISTOGRAM,
        ]
    elif feature == Feature.LOG_Y:
        out = [Mark.POINT, Mark.LINE, Mark.EFFECT_SCATTER]
    elif feature == Feature.COLOR_SIZE:
        out = [Mark.POINT, Mark.SINGLE_AXIS, Mark.EFFECT_SCATTER]
    return out^


def _supporting_names(feature: Feature) -> String:
    """`"Mark.POINT, Mark.LINE or Mark.AREA"`: the supporting marks for
    an error message, so the message cannot disagree with the table."""
    var marks = _marks_supporting(feature)
    var names = String("")
    for i in range(len(marks)):
        if i > 0:
            names += " or " if i == len(marks) - 1 else ", "
        names += marks[i].name()
    return names
