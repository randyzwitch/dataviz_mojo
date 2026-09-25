"""`Plot`, the entry point of every chart: settings only, until a
`mark_*()` call picks the mark and the chain becomes a `Chart` of that
mark's type (#828). `Plot().mark_gantt()` is a `Chart[Gantt]`, and from
there `encode_gantt()` exists and `encode_categorical()` does not,
which the compiler says rather than `render()`.

Each `mark_*()` setter builds the mark struct, applies the setter's
own arguments to it or to the shared settings, and returns
`Chart[<mark>](mark, settings, style)`. The one-call functions
(`bar()`, `gantt()`, ...) go through the same setters and end in
`_finished()`, which applies the theme, size and titles.

Where the rest lives:

- `chart.mojo` -- `Chart[M]` and `AnyChart`, the type-erased chart that
  layers, facets and figures hold in one list
- `mark_type.mojo` -- the `MarkType` trait every mark implements
- `marks.mojo` -- one struct per mark, over the renderers and encoders
  in the mark packages
- `rendering.mojo` -- `render()`, `render_svg()`, `render_pdf()`,
  `save()` and the tight and accessible variants, generic over any chart
- `layers.mojo`, `facets.mojo`, `layout.mojo` -- composition over
  `List[AnyChart]`
- `core/chart_settings.mojo` -- `_ChartSettings`, what every mark shares

This module exports only what it defines, `Plot` and `_finished`
(#825); `scripts/check_import_direction.py` keeps it so.

## Adding a mark

1. Its `Mark` constant in `core/mark.mojo`, and `Mark.COUNT` one past
   it; the digest and backend sweeps walk every value.
2. Its struct in `marks.mojo`: the columns it owns, `render` over them,
   and an override of each `encode_*()` it accepts (the trait's default
   refuses at compile time).
3. Its `mark_*()` setter here, returning `Chart[<mark>]`.
4. Its one-call function in its package, exported from `dataviz/__init__.mojo`.
5. A representative chart in `tests/_mark_registry.mojo`, then
   `pixi run digest-update`.
6. An `ExamplePage` in `scripts/_example_docstrings.mojo` and its entry
   in `scripts/gen_example_docs.mojo`, then `pixi run example`.
"""

from dataviz.core.graph_layout import GraphLayout
from dataviz.core.line_style import LineStyle
from dataviz.core.stack_baseline import StackBaseline
from dataviz.core.step_style import StepStyle
from std.math import pi

from canvas.color import Color
from dataviz.core.axis_controls import _TickOverride
from dataviz.core.plot_fields import _DomainOverride
from dataviz.core.stats import SmoothMethod
from dataviz.core.tooltips import Tooltips
from dataviz.chart import Chart
from dataviz.core.annotations import _AnnotationData
from dataviz.core.chart_settings import _ChartSettings
from dataviz.core.marker import PointShape
from dataviz.core.plot_fields import _MarkStyle
from dataviz.core.theme import Theme
from dataviz.mark_type import MarkType
from dataviz.marks import (
    Arc,
    ArcDiagram,
    Area,
    Bar,
    Bar3d,
    Barbs,
    Beeswarm,
    Box,
    Boxenplot,
    Bullet,
    Bump,
    CalendarHeatmap,
    Candlestick,
    Chord,
    Contour,
    Contourf,
    Corrplot,
    DendrogramMark,
    Ecdf,
    EffectScatter,
    Eventplot,
    FillBetween3d,
    Funnel,
    Gantt,
    Gauge,
    Graph,
    GroupedBar,
    Heatmap,
    Hexbin,
    Hist2d,
    Histogram,
    Imshow,
    Kde,
    Line,
    Lollipop,
    Marimekko,
    Nightingale,
    Parallel,
    Pcolormesh,
    Plot3d,
    Point,
    Pointplot,
    Polar,
    PolarBar,
    PopulationPyramid,
    Punchcard,
    Quiver,
    Quiver3d,
    Radar,
    Radialbar,
    Ridgeline,
    Rug,
    Sankey,
    Scatter3d,
    SingleAxis,
    SpanChart,
    StackedBar,
    Stem3d,
    Streamgraph,
    Streamplot,
    Sunburst,
    Surface3d,
    Tree,
    Treemap,
    Tricontour,
    Tricontourf,
    Tripcolor,
    Triplot,
    Trisurf3d,
    Violin,
    Voxels,
    Waterfall,
    Wire3d,
)


struct Plot(Copyable, Movable):
    """The entry point: what a chart is before its mark is chosen."""

    var settings: _ChartSettings
    var style: _MarkStyle
    var annotations: _AnnotationData
    var width: Int
    var height: Int

    def __init__(out self):
        self.settings = _ChartSettings()
        self.style = _MarkStyle()
        self.annotations = _AnnotationData()
        self.width = 640
        self.height = 420

    def theme(var self, t: Theme) -> Self:
        self.settings.theme = t
        return self^

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

    def tooltips(var self, policy: Tooltips) -> Self:
        """Set whether this chart's data get SVG hover tooltips,
        overriding `Theme.tooltips` for this plot only. `Tooltips.ON`
        titles every datum, `Tooltips.OFF` none, and `Tooltips.AUTO`
        titles them when there are at most `Theme.auto_tooltip_limit`
        (tooltips.mojo). Precedence is this call, then the theme.

        `Tooltips.ON` on a mark without tooltips raises when the chart
        renders; which marks have them is
        `MarkType.supports_tooltips`.

        Args:
            policy: `Tooltips.ON`, `Tooltips.OFF` or `Tooltips.AUTO`.

        Returns:
            Self, for further chaining.
        """
        self.settings.tooltips = policy
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
        self.settings.labels.title = title
        self.settings.labels.subtitle = subtitle
        self.settings.labels.x_title = x_title
        self.settings.labels.y_title = y_title
        self.settings.labels.description = description
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
        self.settings.labels.series_name = name
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
        self.annotations.line_values.append(value)
        self.annotations.line_labels.append(label)
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
        self.annotations.area_y0.append(y0)
        self.annotations.area_y1.append(y1)
        self.annotations.area_labels.append(label)
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
        self.annotations.vline_values.append(value)
        self.annotations.vline_labels.append(label)
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
        self.annotations.point_x.append(x)
        self.annotations.point_y.append(y)
        self.annotations.point_labels.append(label)
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
        self.annotations.arrow_x.append(x)
        self.annotations.arrow_y.append(y)
        self.annotations.arrow_text_x.append(text_x)
        self.annotations.arrow_text_y.append(text_y)
        self.annotations.arrow_labels.append(text)
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
        self.annotations.band_x.append(x.copy())
        self.annotations.band_y_lower.append(y_lower.copy())
        self.annotations.band_y_upper.append(y_upper.copy())
        self.annotations.band_labels.append(label)
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
        self.annotations.best_fit = True
        self.annotations.best_fit_show_equation = show_equation
        self.annotations.best_fit_show_r_squared = show_r_squared
        self.annotations.best_fit_label = label
        self.annotations.best_fit_ci = ci
        return self^

    def annotate_smooth(
        var self,
        method: SmoothMethod = SmoothMethod.LOESS,
        span: Float64 = 0.75,
        degree: Int = 2,
    ) -> Self:
        """Overlay a curved trend line fitted to this plot's own x/y
        data (#147) -- `annotate_best_fit()`'s straight line, for data a
        straight line does not describe.

        - `SmoothMethod.LOESS` (the default): locally weighted
          regression. At each x, a polynomial of `degree` (1 or 2) is
          fitted to the nearest `span` share of the points, weighted by
          the tricube of their distance, and evaluated there. `span`
          sets how smooth: smaller follows the data more closely. The
          defaults, `span=0.75` and `degree=2`, are the conventional
          ones for local regression.
        - `SmoothMethod.POLYNOMIAL`: one least-squares polynomial of
          `degree` over every point; `span` is unused.

        Drawn across the data's own x range, in `annotate_best_fit()`'s
        color and line style, clipped to the plot area. Unlike
        `annotate_best_fit()` there is no confidence band, equation or
        R-squared: those are defined for the straight-line fit.

        Args:
            method: `SmoothMethod.LOESS` or `SmoothMethod.POLYNOMIAL`.
            span: LOESS's window as a share of the points, in `(0, 1]`.
            degree: LOESS's local degree (1 or 2), or the polynomial's.

        Returns:
            Self, for further chaining -- `render()`/`render_svg()` raise
            later if the mark has no continuous x/y axes, or the data
            cannot support the fit (too few points or distinct x values
            for the degree, or a span outside `(0, 1]`).
        """
        self.annotations.smooth = True
        self.annotations.smooth_method = method
        self.annotations.smooth_span = span
        self.annotations.smooth_degree = degree
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
        self.settings.y_log = True
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
        self.settings.x_log = True
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
        self.settings.y_symlog = True
        self.settings.y_symlog_linthresh = linthresh
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
        self.settings.x_symlog = True
        self.settings.x_symlog_linthresh = linthresh
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
        self.settings.x_domain = _DomainOverride(min, max)
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
        self.settings.y_domain = _DomainOverride(min, max)
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
        self.settings.x_tick_override = _TickOverride(
            values.copy(), labels.copy()
        )
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
        self.settings.y_tick_override = _TickOverride(
            values.copy(), labels.copy()
        )
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
        self.settings.x_reversed = True
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
        self.settings.y_reversed = True
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
        self.settings.equal_aspect = True
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
        self.settings.color_domain.has = True
        self.settings.color_domain.min = min
        self.settings.color_domain.max = max
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
        self.settings.color_domain.thresholds = boundaries.copy()
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
        self.settings.color_domain.has_under = True
        self.settings.color_domain.under = color
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
        self.settings.color_domain.has_over = True
        self.settings.color_domain.over = color
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
        self.settings.color_domain.log = True
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
        self.settings.color_domain.has_center = True
        self.settings.color_domain.center = center
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
        self.settings.secondary_axis = True
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
    ) raises -> Chart[Point]:
        """`encode()` with the default mark: a point chart. The same as
        `Plot().mark_point().encode(...)`."""
        return self^.mark_point().encode(
            x,
            y,
            color,
            color_categories,
            size,
            y_err,
            y_err_lower,
            y_err_upper,
            color_map,
            shape_map,
            labels,
        )

    def mark_point(
        var self, jitter_x: Float64 = 0.0, jitter_y: Float64 = 0.0
    ) raises -> Chart[Point]:
        """A scatter plot: one point per (x, y) pair.

        Each SVG point's hover title, when tooltips are on (see
        `tooltips()`), is its encoded label or its coordinates.

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
        var m = Point()
        self.style.point_jitter_x = jitter_x
        self.style.point_jitter_y = jitter_y
        return _chart_from[Point](m^, self)

    def mark_line(
        var self,
        style: LineStyle = LineStyle.SOLID,
        step: StepStyle = StepStyle.NONE,
    ) -> Chart[Line]:
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
        var m = Line()
        self.style.line_style = style
        self.style.step = step
        return _chart_from[Line](m^, self)

    def mark_bar(var self, horizontal: Bool = False) -> Chart[Bar]:
        """A bar chart: one bar per category, encoded via `encode_categorical()`.

                `horizontal` (default `False`) draws categories top-to-bottom along
                the y-axis with each bar extending from a zero baseline to the right
        , via `_draw_horizontal_categorical_axis_frame` (gantt.mojo);
                see `_render_horizontal_bar` (bar.mojo).
        """
        var m = Bar()
        self.settings.horizontal = horizontal
        return _chart_from[Bar](m^, self)

    def mark_area(var self, step: StepStyle = StepStyle.NONE) -> Chart[Area]:
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
        var m = Area()
        self.style.step = step
        return _chart_from[Area](m^, self)

    def mark_histogram(var self, horizontal: Bool = False) -> Chart[Histogram]:
        """A histogram drawn as one rectangle per bin at numeric x
        positions, with a separator between adjacent bins
        (`Theme.histogram_edge_color`); `horizontal` puts the bins up
        the y-axis and the values running right. Encoded from raw
        observations via `encode_histogram()` -- the same binning
        `histogram()` does -- or from bins already computed via
        `encode_histogram_bins()` (#698); see `_draw_histogram_layer`
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
        var m = Histogram()
        m.histogram.horizontal = horizontal
        return _chart_from[Histogram](m^, self)

    def mark_arc(var self, inner_radius_fraction: Float64 = 0.0) -> Chart[Arc]:
        """A pie chart: one wedge per category, its angular span proportional to
        its value, encoded via `encode_categorical()`. Every value must be
        non-negative and at least one positive, checked at render() time.
        `inner_radius_fraction > 0.0` (in `[0.0, 1.0)`) makes a donut.
        """
        var m = Arc()
        self.style.donut_inner_radius_fraction = inner_radius_fraction
        return _chart_from[Arc](m^, self)

    def mark_nightingale(var self, area: Bool = False) -> Chart[Nightingale]:
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
        var m = Nightingale()
        m.nightingale.area = area
        return _chart_from[Nightingale](m^, self)

    def mark_polar_bar(var self, padding: Float64 = 0.2) -> Chart[PolarBar]:
        """A circular column chart: bars radiate outward from the center, one
        equal-width angular slot per category with a gap of `padding` (a
        fraction of the slot) between bars. Encoded via
        `encode_categorical()`. Bar length scales linearly by
        `value / max(values)`; there is no `area` mode. Every value must be
        non-negative and at least one positive, checked at render() time.
        """
        var m = PolarBar()
        self.style.polar_bar_padding = padding
        return _chart_from[PolarBar](m^, self)

    def mark_radialbar(
        var self, ring_gap_fraction: Float64 = 0.25
    ) -> Chart[Radialbar]:
        """A radial (multi-ring) progress chart: one concentric ring per
        category, swept clockwise from 12 o'clock over a track to
        `value / max(values)` of the way around, with the first category
        outermost. `ring_gap_fraction` is the gap between rings as a fraction
        of each ring's slot. Encoded via `encode_categorical()`. Every value
        must be non-negative and at least one positive, checked at render()
        time.
        """
        var m = Radialbar()
        self.style.radialbar_ring_gap_fraction = ring_gap_fraction
        return _chart_from[Radialbar](m^, self)

    def mark_polar(
        var self, grid_rings: Int = 4, grid_spokes: Int = 12
    ) -> Chart[Polar]:
        """A polar-coordinate line plot: (angle, radius) pairs connected in row
        order over a polar grid of `grid_rings` circles and `grid_spokes`
        radial lines. Encoded via `encode_polar()` (one unnamed series) or
        `encode_polar_series()` (several named series sharing one angle
        domain). See `_render_polar`.
        """
        var m = Polar()
        self.style.polar_grid_rings = grid_rings
        self.style.polar_grid_spokes = grid_spokes
        return _chart_from[Polar](m^, self)

    def mark_radar(var self, grid_rings: Int = 4) -> Chart[Radar]:
        """A radar/spider chart: one spoke per named indicator, one polygon per
        named series, with `grid_rings` web rings. Encoded via
        `encode_radar()`.
        """
        var m = Radar()
        self.style.radar_grid_rings = grid_rings
        return _chart_from[Radar](m^, self)

    def mark_gauge(
        var self,
        band_inner_fraction: Float64 = 0.7,
        needle_fraction: Float64 = 0.9,
        start_angle: Float64 = 3.0 * pi / 4.0,
        sweep_angle: Float64 = 3.0 * pi / 2.0,
    ) -> Chart[Gauge]:
        """A gauge chart: a single value shown as a needle over a color-banded
        dial. Encoded via `encode_gauge()`, which also takes the bands'
        `breakpoints`/`band_colors`. `band_inner_fraction`/`needle_fraction`
        are fractions of the dial radius; `start_angle`/`sweep_angle` are
        radians (the defaults give a 270-degree dial opening downward).
        """
        var m = Gauge()
        self.style.gauge_band_inner_fraction = band_inner_fraction
        self.style.gauge_needle_fraction = needle_fraction
        self.style.gauge_start_angle = start_angle
        self.style.gauge_sweep_angle = sweep_angle
        return _chart_from[Gauge](m^, self)

    def mark_parallel(var self) -> Chart[Parallel]:
        """A parallel-coordinates chart: one row drawn as a polyline across
        evenly spaced, independently scaled vertical axes, one per dimension.
        Encoded via `encode_parallel()`.
        """
        var m = Parallel()
        return _chart_from[Parallel](m^, self)

    def mark_pointplot(var self, horizontal: Bool = False) -> Chart[Pointplot]:
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
        var m = Pointplot()
        self.settings.horizontal = horizontal
        return _chart_from[Pointplot](m^, self)

    def mark_lollipop(var self, horizontal: Bool = False) -> Chart[Lollipop]:
        """A lollipop chart: one stem-plus-point per category, encoded via
        `encode_categorical()` (the same data as `mark_bar()`). `horizontal`
        (default `False`) draws categories top-to-bottom with each stem
        extending to the right; see `_render_horizontal_lollipop`
        (lollipop.mojo).
        """
        var m = Lollipop()
        self.settings.horizontal = horizontal
        return _chart_from[Lollipop](m^, self)

    def mark_waterfall(
        var self, delta_width_fraction: Float64 = 0.6, horizontal: Bool = False
    ) -> Chart[Waterfall]:
        """A waterfall chart: one floating bar per category, each running from
        the previous running total to the next. Encoded via
        `encode_waterfall()` (a category plus a signed delta).
        `delta_width_fraction` is a delta bar's width as a fraction of the
        band, applied only when `is_total` rows are in use.
        """
        var m = Waterfall()
        self.style.waterfall_delta_width_fraction = delta_width_fraction
        self.settings.horizontal = horizontal
        return _chart_from[Waterfall](m^, self)

    def mark_boxenplot(var self, horizontal: Bool = False) -> Chart[Boxenplot]:
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
        var m = Boxenplot()
        self.settings.horizontal = horizontal
        return _chart_from[Boxenplot](m^, self)

    def mark_box(var self, horizontal: Bool = False) -> Chart[Box]:
        """A box plot: one box-and-whiskers per category summarizing a
        distribution of raw values. Encoded via `encode_boxplot()`, which
        computes quartiles/whiskers/outliers immediately. `horizontal`
        (default `False`) draws categories top-to-bottom with each box
        left-to-right; see `_render_horizontal_box` (box.mojo).
        """
        var m = Box()
        self.settings.horizontal = horizontal
        return _chart_from[Box](m^, self)

    def mark_candlestick(var self) -> Chart[Candlestick]:
        """A candlestick chart: one open/high/low/close bar per category.
        Encoded via `encode_candlestick()`.
        """
        var m = Candlestick()
        return _chart_from[Candlestick](m^, self)

    def mark_bullet(
        var self,
        measure_width_fraction: Float64 = 0.35,
        horizontal: Bool = False,
    ) -> Chart[Bullet]:
        """A bullet chart (Stephen Few's design): a measure bar, a target tick,
        and qualitative-range bands per category. Encoded via
        `encode_bullet()`. `measure_width_fraction` is the measure bar's
        width as a fraction of the band.
        """
        var m = Bullet()
        self.style.bullet_measure_width_fraction = measure_width_fraction
        self.settings.horizontal = horizontal
        return _chart_from[Bullet](m^, self)

    def mark_gantt(var self) -> Chart[Gantt]:
        """A gantt chart: one horizontal bar per category from a start value to
        an end value, with categories along the y-axis. Encoded via
        `encode_gantt()`. See `mark_span_chart()` for the same data drawn
        vertically.
        """
        var m = Gantt()
        return _chart_from[Gantt](m^, self)

    def mark_span_chart(var self) -> Chart[SpanChart]:
        """A span chart: `mark_gantt()`'s mirror image, one floating vertical
        bar per category from a low value to a high value on the normal
        categorical x-axis. Encoded via `encode_gantt()`.
        """
        var m = SpanChart()
        return _chart_from[SpanChart](m^, self)

    def mark_calendar_heatmap(var self) -> Chart[CalendarHeatmap]:
        """A calendar heatmap: daily values in a GitHub-contributions-style
        grid, colored through a continuous gradient. Encoded via
        `encode_calendar()` (`"YYYY-MM-DD"` dates).
        """
        var m = CalendarHeatmap()
        return Chart[CalendarHeatmap](
            m^, self.settings.copy(), self.style.copy()
        )

    def mark_corrplot(
        var self,
        layout: String = "full",
        diag: Bool = True,
        labels: Bool = True,
        bubble_fraction: Float64 = 0.42,
    ) -> Chart[Corrplot]:
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
        var m = Corrplot()
        m.corrplot.layout = layout
        m.corrplot.diag = diag
        m.corrplot.labels = labels
        self.style.corrplot_bubble_fraction = bubble_fraction
        return _chart_from[Corrplot](m^, self)

    def mark_punchcard(var self, scale: Float64 = 10.0) -> Chart[Punchcard]:
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
        var m = Punchcard()
        m.punchcard.scale = scale
        return _chart_from[Punchcard](m^, self)

    def mark_barbs(
        var self, length: Float64 = 28.0, flip: Bool = False
    ) -> Chart[Barbs]:
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
        var m = Barbs()
        m.barbs.length = length
        m.barbs.flip = flip
        return _chart_from[Barbs](m^, self)

    def mark_quiver(
        var self, scale: Float64 = 0.0, color_by_magnitude: Bool = False
    ) -> Chart[Quiver]:
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
        var m = Quiver()
        m.barbs.scale = scale
        m.barbs.color_by_magnitude = color_by_magnitude
        return _chart_from[Quiver](m^, self)

    def mark_contour(var self, levels: Int = 8) -> Chart[Contour]:
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
        var m = Contour()
        m.contour.level_count = levels
        return _chart_from[Contour](m^, self)

    def mark_contourf(var self, levels: Int = 8) -> Chart[Contourf]:
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
        var m = Contourf()
        m.contour.level_count = levels
        return _chart_from[Contourf](m^, self)

    def mark_imshow(var self) -> Chart[Imshow]:
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
        var m = Imshow()
        return _chart_from[Imshow](m^, self)

    def mark_pcolormesh(var self) -> Chart[Pcolormesh]:
        """`mark_imshow()` over cell boundaries the caller supplies, for a
        grid whose rows and columns are not evenly spaced. Encoded via
        `encode_pcolormesh()`; see `_render_image` for the drawing and
        `pcolormesh()` (image.mojo) for the one-call form.

        Row 0 is at the *bottom* here, unlike `mark_imshow()`: the edges
        are positions on a real axis rather than scanlines.

        Returns:
            Self, for further chaining.
        """
        var m = Pcolormesh()
        return _chart_from[Pcolormesh](m^, self)

    def mark_hist2d(var self) -> Chart[Hist2d]:
        """Select `Mark.HIST2D`: `(x, y)` points binned into a grid of
        counts and drawn as colored cells, empty cells left undrawn.
        Pair with `encode_hist2d()`; see `_render_image` for the
        drawing and `hist2d()` (hist2d.mojo) for the one-call form.

        Returns:
            Self, for further chaining.
        """
        var m = Hist2d()
        return _chart_from[Hist2d](m^, self)

    def mark_hexbin(var self) -> Chart[Hexbin]:
        """Select `Mark.HEXBIN`: `(x, y)` points counted into a hexagonal
        lattice and drawn as colored hexagons, empty cells left undrawn.
        Pair with `encode_hexbin()`; see `_render_hexbin` (hexbin.mojo)
        for the drawing and `hexbin()` for the one-call form.

        Returns:
            Self, for further chaining.
        """
        var m = Hexbin()
        return _chart_from[Hexbin](m^, self)

    def mark_streamplot(
        var self,
        density: Float64 = 1.0,
        arrows: Bool = True,
        color_by_magnitude: Bool = False,
    ) -> Chart[Streamplot]:
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
        var m = Streamplot()
        m.stream.density = density
        m.stream.arrows = arrows
        m.stream.color_by_magnitude = color_by_magnitude
        return _chart_from[Streamplot](m^, self)

    def mark_tricontour(var self, levels: Int = 8) -> Chart[Tricontour]:
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
        var m = Tricontour()
        m.tricontour.level_count = levels
        return _chart_from[Tricontour](m^, self)

    def mark_tricontourf(var self, levels: Int = 8) -> Chart[Tricontourf]:
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
        var m = Tricontourf()
        m.tricontour.level_count = levels
        return _chart_from[Tricontourf](m^, self)

    def mark_dendrogram(
        var self, horizontal: Bool = False
    ) -> Chart[DendrogramMark]:
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
        var m = DendrogramMark()
        m.dendrogram.horizontal = horizontal
        return Chart[DendrogramMark](
            m^, self.settings.copy(), self.style.copy()
        )

    def mark_triplot(var self, show_points: Bool = True) -> Chart[Triplot]:
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
        var m = Triplot()
        m.triplot.show_points = show_points
        return _chart_from[Triplot](m^, self)

    def mark_tripcolor(var self) -> Chart[Tripcolor]:
        """Each triangle of the Delaunay mesh filled from the values at
        its three vertices -- `mark_triplot()`'s mesh painted rather than
        stroked, over the same `encode_triplot()` data, which must then
        carry `z`. See `_render_tripcolor` (triplot.mojo) for the flat
        shading and the seam handling, and `tripcolor()` for the one-call
        form.

        Returns:
            Self, for further chaining.
        """
        var m = Tripcolor()
        return _chart_from[Tripcolor](m^, self)

    def mark_marimekko(var self) -> Chart[Marimekko]:
        """A Marimekko/mosaic chart: column widths proportional to each
        category's share of the grand total, stacked segment heights showing
        each column's subcategory composition. Encoded via
        `encode_marimekko()`.
        """
        var m = Marimekko()
        return _chart_from[Marimekko](m^, self)

    def mark_sunburst(var self) -> Chart[Sunburst]:
        """A sunburst chart: a hierarchy as concentric rings, one ring per depth
        level, each node's angular span proportional to its share of its
        parent's total. Encoded via `encode_hierarchy()`.
        """
        var m = Sunburst()
        return _chart_from[Sunburst](m^, self)

    def mark_tree(var self) -> Chart[Tree]:
        """A tree diagram: a hierarchy as a top-to-bottom node-link diagram.
        Encoded via `encode_hierarchy()`.
        """
        var m = Tree()
        return _chart_from[Tree](m^, self)

    def mark_treemap(var self) -> Chart[Treemap]:
        """A treemap: a hierarchy as nested, area-proportional rectangles via
        slice-and-dice. Encoded via `encode_hierarchy()`.
        """
        var m = Treemap()
        return _chart_from[Treemap](m^, self)

    def mark_grouped_bar(
        var self, horizontal: Bool = False
    ) -> Chart[GroupedBar]:
        """A grouped bar chart: several bars side by side per category, one per
        series. Encoded via `encode_grouped_bar()`. `horizontal` (default
        `False`) draws categories top-to-bottom with each row subdivided into
        equal-height sub-bars; see `_render_horizontal_grouped_bar`
        (grouped_bar.mojo).
        """
        var m = GroupedBar()
        self.settings.horizontal = horizontal
        return _chart_from[GroupedBar](m^, self)

    def mark_stacked_bar(
        var self, percent: Bool = False, horizontal: Bool = False
    ) -> Chart[StackedBar]:
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
        var m = StackedBar()
        m.grouped_bar.percent = percent
        self.settings.horizontal = horizontal
        return _chart_from[StackedBar](m^, self)

    def mark_population_pyramid(var self) -> Chart[PopulationPyramid]:
        """A population pyramid: two magnitude bars per category growing outward
        left/right from a shared, centered zero baseline, on `Mark.GANTT`'s
        horizontal categorical frame. Encoded via
        `encode_population_pyramid()`.
        """
        var m = PopulationPyramid()
        return Chart[PopulationPyramid](
            m^, self.settings.copy(), self.style.copy()
        )

    def mark_heatmap(var self) -> Chart[Heatmap]:
        """A heatmap: one colored grid cell per (x, y) category pair, on two
        categorical axes. Encoded via `encode_heatmap()`.
        """
        var m = Heatmap()
        return _chart_from[Heatmap](m^, self)

    def mark_chord(var self, ring_fraction: Float64 = 0.08) -> Chart[Chord]:
        """A chord diagram: ring sectors for every distinct node across an edge
        list's `from`/`to` columns, connected by ribbons sized by each flow's
        value. Encoded via `encode_chord()`. `ring_fraction` is the rim's
        thickness as a fraction of the radius. No axis frame.
        """
        var m = Chord()
        self.style.chord_ring_fraction = ring_fraction
        return _chart_from[Chord](m^, self)

    def mark_arc_diagram(var self) -> Chart[ArcDiagram]:
        """An arc diagram: `mark_chord()`'s edge list drawn as nodes on one line
        connected by semicircular arcs. Encoded via `encode_chord()`.
        """
        var m = ArcDiagram()
        return _chart_from[ArcDiagram](m^, self)

    def mark_graph(
        var self, layout: GraphLayout = GraphLayout.CIRCLE
    ) -> Chart[Graph]:
        """A network graph: `mark_chord()`'s edge list drawn as nodes
        connected by straight lines, placed around a circle or by a
        force-directed layout (see `GraphLayout`). Encoded via
        `encode_chord()`.

        Args:
            layout: `GraphLayout.CIRCLE` (the default) or
                `GraphLayout.FORCE` (#157).

        Returns:
            Self, for further chaining.
        """
        var m = Graph()
        self.style.graph_layout = layout
        return _chart_from[Graph](m^, self)

    def mark_sankey(var self, node_width: Float64 = 12.0) -> Chart[Sankey]:
        """A Sankey diagram: `mark_chord()`'s edge list laid out left-to-right by
        column as proportionally sized flow ribbons between node bars
        `node_width` pixels wide (before `Theme.scale`). Encoded via
        `encode_chord()`; the edges must form a DAG.
        """
        var m = Sankey()
        self.style.sankey_node_width = node_width
        return _chart_from[Sankey](m^, self)

    def mark_single_axis(var self) -> Chart[SingleAxis]:
        """A single-axis chart: every value plotted along one horizontal axis
        with no y-axis. Encoded via `encode_single_axis()`, with the same
        optional `color`/`color_categories`/`size` channels as `Mark.POINT`.

        Returns:
            Self, for further chaining.
        """
        var m = SingleAxis()
        return _chart_from[SingleAxis](m^, self)

    def mark_effect_scatter(var self) -> Chart[EffectScatter]:
        """A scatter plot with a halo drawn under each point, the static
        equivalent of ECharts' effect scatter (see `_draw_point_layer`'s
        `draw_halo`). Encoded like `Mark.POINT`, via `encode()`.
        """
        var m = EffectScatter()
        return _chart_from[EffectScatter](m^, self)

    def mark_funnel(var self) -> Chart[Funnel]:
        """A funnel chart: one tapering trapezoid per category, largest value
        first, with no axis frame. Encoded via `encode_categorical()`.
        """
        var m = Funnel()
        return _chart_from[Funnel](m^, self)

    def mark_bump(var self) -> Chart[Bump]:
        """A bump chart: one line per series tracking its rank (1 = highest
        value) among every series at each category. Encoded via
        `encode_grouped_bar()`.
        """
        var m = Bump()
        return _chart_from[Bump](m^, self)

    def mark_streamgraph(
        var self,
        baseline: StackBaseline = StackBaseline.WIGGLE,
        step: StepStyle = StepStyle.NONE,
    ) -> Chart[Streamgraph]:
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
        var m = Streamgraph()
        self.style.streamgraph_baseline = baseline
        self.style.step = step
        return _chart_from[Streamgraph](m^, self)

    def mark_beeswarm(var self, horizontal: Bool = False) -> Chart[Beeswarm]:
        """A beeswarm plot: one point per raw value, jittered sideways within
        its category's band. Encoded via `encode_distribution()`.
        `horizontal` (default `False`) draws categories top-to-bottom with
        each swarm jittered vertically; see
        `_render_horizontal_beeswarm` (beeswarm.mojo).
        """
        var m = Beeswarm()
        self.settings.horizontal = horizontal
        return _chart_from[Beeswarm](m^, self)

    def mark_violin(
        var self,
        bandwidth: Float64 = 0.0,
        scale_by_count: Bool = False,
        horizontal: Bool = False,
        width_fraction: Float64 = 0.4,
    ) -> Chart[Violin]:
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
        var m = Violin()
        m.distribution.kde_bandwidth_override = bandwidth
        m.distribution.kde_scale_by_count = scale_by_count
        self.settings.horizontal = horizontal
        self.style.violin_width_fraction = width_fraction
        return _chart_from[Violin](m^, self)

    def mark_kde(
        var self,
        bandwidth: Float64 = 0.0,
        fill: Bool = False,
        rug: Bool = False,
    ) -> Chart[Kde]:
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
        var m = Kde()
        m.distribution.kde_bandwidth_override = bandwidth
        m.distribution.kde_fill = fill
        m.distribution.kde_rug = rug
        return _chart_from[Kde](m^, self)

    def mark_rug(var self) -> Chart[Rug]:
        """One short tick per observation along the x axis. Encoded via
        `encode_kde()`; see `rugplot()` for the one-call form.

        The same ticks `mark_kde(rug=True)` draws under its curve, as a
        chart of their own -- or as a `render_layers()` layer under a
        `mark_kde()` one, which draws the same thing.

        Returns:
            Self, for further chaining.
        """
        var m = Rug()
        return _chart_from[Rug](m^, self)

    def mark_ecdf(var self, complementary: Bool = False) -> Chart[Ecdf]:
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
        var m = Ecdf()
        m.distribution.ecdf_complementary = complementary
        return _chart_from[Ecdf](m^, self)

    def mark_eventplot(
        var self, line_length: Float64 = 1.0
    ) -> Chart[Eventplot]:
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
        var m = Eventplot()
        self.style.eventplot_line_length = line_length
        return _chart_from[Eventplot](m^, self)

    def mark_ridgeline(
        var self,
        bandwidth: Float64 = 0.0,
        scale_by_count: Bool = False,
        overlap: Float64 = 1.3,
    ) -> Chart[Ridgeline]:
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
        var m = Ridgeline()
        m.distribution.kde_bandwidth_override = bandwidth
        m.distribution.kde_scale_by_count = scale_by_count
        self.style.ridgeline_overlap = overlap
        return _chart_from[Ridgeline](m^, self)

    def mark_scatter3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Scatter3d]:
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
        var m = Scatter3d()
        m.xyz.elev = elev
        m.xyz.azim = azim
        return _chart_from[Scatter3d](m^, self)

    def mark_plot3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Plot3d]:
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
        var m = Plot3d()
        m.xyz.elev = elev
        m.xyz.azim = azim
        return _chart_from[Plot3d](m^, self)

    def mark_surface3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Surface3d]:
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
        var m = Surface3d()
        m.surface.elev = elev
        m.surface.azim = azim
        return _chart_from[Surface3d](m^, self)

    def mark_wire3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Wire3d]:
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
        var m = Wire3d()
        m.surface.elev = elev
        m.surface.azim = azim
        return _chart_from[Wire3d](m^, self)

    def mark_trisurf3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Trisurf3d]:
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
        var m = Trisurf3d()
        m.xyz.elev = elev
        m.xyz.azim = azim
        return _chart_from[Trisurf3d](m^, self)

    def mark_stem3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Stem3d]:
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
        var m = Stem3d()
        m.xyz.elev = elev
        m.xyz.azim = azim
        return _chart_from[Stem3d](m^, self)

    def mark_quiver3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Quiver3d]:
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
        var m = Quiver3d()
        m.vectors3d.elev = elev
        m.vectors3d.azim = azim
        return _chart_from[Quiver3d](m^, self)

    def mark_fill_between3d(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[FillBetween3d]:
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
        var m = FillBetween3d()
        m.ribbon3d.elev = elev
        m.ribbon3d.azim = azim
        return _chart_from[FillBetween3d](m^, self)

    def mark_bar3d(
        var self,
        bar_width: Float64 = 0.8,
        bar_depth: Float64 = 0.8,
        elev: Float64 = 30.0,
        azim: Float64 = -60.0,
    ) -> Chart[Bar3d]:
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
        var m = Bar3d()
        m.bars3d.bar_width = bar_width
        m.bars3d.bar_depth = bar_depth
        m.bars3d.elev = elev
        m.bars3d.azim = azim
        return _chart_from[Bar3d](m^, self)

    def mark_voxels(
        var self, elev: Float64 = 30.0, azim: Float64 = -60.0
    ) -> Chart[Voxels]:
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
        var m = Voxels()
        m.voxels.elev = elev
        m.voxels.azim = azim
        return _chart_from[Voxels](m^, self)


def _chart_from[M: MarkType](var mark: M, entry: Plot) -> Chart[M]:
    """The chart a `mark_*()` setter returns: `mark` plus everything the
    entry point collected before the mark was chosen."""
    var chart = Chart[M](mark^, entry.settings.copy(), entry.style.copy())
    chart.annotations = entry.annotations.copy()
    chart.width = entry.width
    chart.height = entry.height
    return chart^


def _finished[
    M: MarkType
](
    var plot: Chart[M],
    theme: Theme,
    width: Int,
    height: Int,
    title: String,
    x_title: String,
    y_title: String,
    subtitle: String = "",
) -> Chart[M]:
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
