"""A chart whose mark is a type (#828). `Chart[M]` holds one `M`, the
settings every mark shares, the mark style and the annotations; each
`encode_*()` forwards to the mark, which either accepts it or refuses
it at compile time. `Plot` is the entry point: settings only, until a
`mark_*()` picks the mark and the chain becomes a `Chart` of that
type. Beside `Plot` for now; it replaces it once every entry point is
generic over `M`."""

from canvas.bounds import BoundsTarget
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget
from canvas.vector.pdf import PdfCanvas, write_pdf
from canvas.vector.svg import SvgCanvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png

from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.vector.pdf import PdfCanvas
from canvas.vector.svg import SvgCanvas
from dataviz.basic.continuous import area
from dataviz.binned.histogram import (
    BinRule,
    HistStat,
    HistogramBins,
    bin_edges,
    histogram_bins,
)
from dataviz.core.array_like import (
    Float64Sequence,
    StringSequence,
    _materialize_floats,
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
    _materialize_strings,
)
from dataviz.core.axis_controls import _TickOverride
from dataviz.core.cluster import Dendrogram
from dataviz.core.delaunay import Triangulation
from dataviz.core.graph_layout import GraphLayout
from dataviz.core.line_style import LineStyle
from dataviz.core.marker import PointShape
from dataviz.core.numpy_interop import _materialize_python_floats
from dataviz.core.plot_fields import _DomainOverride
from dataviz.core.stack_baseline import StackBaseline
from dataviz.core.stats import SmoothMethod
from dataviz.core.step_style import StepStyle
from dataviz.core.validate import _require_non_empty
from morrow import Morrow
from std.math import pi
from std.python import PythonObject
from dataviz.core.annotations import (
    _AnnotationData,
    _draw_annotation_areas,
    _draw_annotation_arrows,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_points,
    _draw_annotation_smooth,
    _draw_annotation_vlines,
)
from dataviz.core.chart_settings import _ChartSettings
from dataframe import DataFrame
from dataviz.core.mark import Mark, _require_mark
from std.memory import Allocation, Layout, Pointer, alloc, dealloc
from dataviz.core.capabilities import _Capabilities
from dataviz.mark_type import MarkType, _capabilities_of_type
from dataviz.core.plot_fields import (
    _CategoricalData,
    _ChannelData,
    _ContinuousData,
    _DistributionData,
    _ErrorBarData,
    _MarkStyle,
)
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import (
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _replay_text_requests,
)
from dataviz.core.theme import Theme
from dataviz.core.tooltips import Tooltips
from dataviz.core.output_format import OutputFormat
from dataviz.rendering import (
    _filled_annotations_go_under,
    _resolve_output_format,
    _resolve_supersample,
)
from dataviz.marks import (
    _shared_categorical,
    _shared_channels,
    _shared_continuous,
    _shared_distribution,
    _shared_y_err,
    Point,
    Line,
    Bar,
    Area,
    Arc,
    Lollipop,
    Waterfall,
    Box,
    Candlestick,
    Bullet,
    Gantt,
    GroupedBar,
    StackedBar,
    PopulationPyramid,
    Heatmap,
    Chord,
    SingleAxis,
    EffectScatter,
    Funnel,
    Bump,
    Streamgraph,
    Beeswarm,
    Violin,
    Ridgeline,
    Nightingale,
    PolarBar,
    Polar,
    Radar,
    Gauge,
    Parallel,
    SpanChart,
    CalendarHeatmap,
    Corrplot,
    Punchcard,
    Marimekko,
    Sunburst,
    Tree,
    Treemap,
    ArcDiagram,
    Graph,
    Sankey,
    Radialbar,
    Barbs,
    Contour,
    Contourf,
    Tricontour,
    Tricontourf,
    Kde,
    Rug,
    Triplot,
    Tripcolor,
    Ecdf,
    Imshow,
    Pcolormesh,
    Eventplot,
    Pointplot,
    Boxenplot,
    Hist2d,
    Hexbin,
    Quiver,
    Histogram,
    Streamplot,
    DendrogramMark,
    Scatter3d,
    Plot3d,
    Surface3d,
    Wire3d,
    Trisurf3d,
    Bar3d,
    Voxels,
    Stem3d,
    Quiver3d,
    FillBetween3d,
)


trait ChartLike(Copyable, Deinitable, Movable):
    """What the render pipeline needs from a chart, whether its mark is
    a type (`Chart[M]`) or erased (`AnyChart`): the shared settings by
    value, the mark id, the canvas size, the continuous columns the
    smooth and best-fit annotations regress over, and the mark's own
    draw. Trait methods cannot return references, so the settings come
    back as copies; the pipeline takes them once per render."""

    def id(self) -> Mark:
        ...

    def canvas_width(self) -> Int:
        ...

    def canvas_height(self) -> Int:
        ...

    def chart_settings(self) -> _ChartSettings:
        ...

    def mark_style(self) -> _MarkStyle:
        ...

    def chart_annotations(self) -> _AnnotationData:
        ...

    def x_data(self) -> List[Float64]:
        ...

    def y_data(self) -> List[Float64]:
        ...

    def scaled_by(self, factor: Float64) -> Self:
        """A copy sized for `save(dpi=...)`: the canvas and the theme's
        scale multiplied by `factor`."""
        ...

    def erased(self) -> AnyChart:
        """This chart with its mark type erased, for a `List[AnyChart]`."""
        ...

    def erased_with[
        canvas: Bool = False,
        svg: Bool = False,
        pdf: Bool = False,
        bounds: Bool = False,
    ](self) -> AnyChart:
        """`erased()` with only the named targets' renders bound, for a
        composition entry that knows which targets it draws marks into
        and never hands the chart on. Drawing the mark into an unbound
        target raises. See `AnyChart`."""
        ...

    def capabilities(self) -> _Capabilities:
        """What this chart's mark honors, from its type's constants."""
        ...

    def render_mark[
        T: DrawTarget
    ](
        self,
        mut target: T,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        has_shared_y_domain: Bool,
        shared_y_min: Float64,
        shared_y_max: Float64,
        shared_y_is_log: Bool,
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        ...


struct Chart[M: MarkType](ChartLike):
    """One chart of mark type `M`: the mark's own columns in `mark`, and
    everything every mark shares beside it. Built through `Plot`."""

    var mark: Self.M
    var settings: _ChartSettings
    var style: _MarkStyle
    var annotations: _AnnotationData
    var width: Int
    var height: Int

    def __init__(
        out self,
        var mark: Self.M,
        var settings: _ChartSettings,
        var style: _MarkStyle,
    ):
        self.mark = mark^
        self.settings = settings^
        self.style = style^
        self.annotations = _AnnotationData()
        self.width = 640
        self.height = 420

    def id(self) -> Mark:
        return Self.M.id

    def canvas_width(self) -> Int:
        return self.width

    def canvas_height(self) -> Int:
        return self.height

    def chart_settings(self) -> _ChartSettings:
        return self.settings.copy()

    def mark_style(self) -> _MarkStyle:
        return self.style.copy()

    def chart_annotations(self) -> _AnnotationData:
        return self.annotations.copy()

    def x_data(self) -> List[Float64]:
        return _shared_continuous(self.mark).x.copy()

    def y_data(self) -> List[Float64]:
        return _shared_continuous(self.mark).y.copy()

    def render_mark[
        T: DrawTarget
    ](
        self,
        mut target: T,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        has_shared_y_domain: Bool,
        shared_y_min: Float64,
        shared_y_max: Float64,
        shared_y_is_log: Bool,
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        return self.mark.render(
            target,
            self.style,
            self.annotations,
            self.settings,
            ox0,
            oy0,
            ox1,
            oy1,
            has_shared_y_domain,
            shared_y_min,
            shared_y_max,
            shared_y_is_log,
            cache=cache,
            vector_target=vector_target,
        )

    def scaled_by(self, factor: Float64) -> Self:
        var out = self.copy()
        out.width = Int(Float64(self.width) * factor + 0.5)
        out.height = Int(Float64(self.height) * factor + 0.5)
        out.settings.theme.scale = self.settings.theme.scale * factor
        return out^

    def erased(self) -> AnyChart:
        """This chart with its mark type erased, for a `List[AnyChart]`."""
        return AnyChart(self)

    def erased_with[
        canvas: Bool = False,
        svg: Bool = False,
        pdf: Bool = False,
        bounds: Bool = False,
    ](self) -> AnyChart:
        return AnyChart.bound[canvas, svg, pdf, bounds](self)

    def capabilities(self) -> _Capabilities:
        return _capabilities_of_type[Self.M]()

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
        self.settings.theme = t
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

    def annotate_line(
        var self, value: Float64, label: String = ""
    ) -> Self where Self.M.supports_annotations_y:
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
    ) -> Self where Self.M.supports_annotations_y:
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

    def annotate_vline(
        var self, value: Float64, label: String = ""
    ) -> Self where Self.M.supports_annotations_x:
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
    ) -> Self where Self.M.supports_annotations_xy:
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
    ) -> Self where Self.M.supports_annotations_xy:
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
    ) -> Self where Self.M.supports_annotations_xy:
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
    ) -> Self where Self.M.supports_annotations_xy:
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
    ) -> Self where Self.M.supports_annotations_xy:
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

    def scale_y_log(var self) -> Self where Self.M.supports_log_y:
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

    def scale_x_log(var self) -> Self where Self.M.supports_log_x:
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

    def scale_y_symlog(
        var self, linthresh: Float64 = 1.0
    ) -> Self where Self.M.supports_log_y:
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

    def scale_x_symlog(
        var self, linthresh: Float64 = 1.0
    ) -> Self where Self.M.supports_log_x:
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
        self.mark.encode_dendrogram(self.settings, tree, labels, horizontal)
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
        self.mark.encode(
            self.settings,
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
        self.mark.encode_vectors3d(self.settings, x, y, z, u, v, w)
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
        self.mark.encode_ribbon3d(self.settings, x1, y1, z1, x2, y2, z2)
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
        self.mark.encode_bars3d(self.settings, x, y, z)
        return self^

    def encode_voxels(
        var self,
        filled: List[List[List[Bool]]],
    ) raises -> Self:
        """Give `Mark.VOXELS` its occupancy grid (#345).

        Args:
            filled: `filled[layer][row][col]`, `True` where the cell is
                solid. Layers run up z, rows along y and columns along
                x -- `encode_surface()`'s order with a third index in
                front.

        Returns:
            Self, for further chaining.
        """
        self.mark.encode_voxels(self.settings, filled)
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
        self.mark.encode_surface(self.settings, z, x, y)
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
        self.mark.encode_xyz(self.settings, x, y, z)
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
        deduplicated or re-sorted; repeated categories raise with their
        first and second positions. Use `encode_grouped_bar()` for
        category-by-series values.

        `y_err`/`y_err_lower`/`y_err_upper` work exactly as they do on
        `encode()` -- see that method's own docstring for the shared rules
        (mutually exclusive forms, every value `>= 0`) -- except `Mark.BAR`
        is the only mark among `encode_categorical()`'s that draws them
        today; every other mark this method feeds (`LOLLIPOP`, `WATERFALL`,
        `NIGHTINGALE`, `FUNNEL`, `POLAR_BAR`, `RADIALBAR`, ...) raises if
        given one.

        Args:
            x: One category per entry, in the given order -- treated
                as already being the axis's category order; duplicates
                are rejected.
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
        self.mark.encode_categorical(
            self.settings, x, y, y_err, y_err_lower, y_err_upper
        )
        return self^

    def encode_time_bars(
        var self,
        dates: List[Morrow],
        values: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises -> Self:
        """Map bars to real timestamps on a continuous time x-axis.

        Each bar is centered on its timestamp and spans one observed
        interval. Dates must be distinct; the interval is inferred from
        their spacing at render time. The three error channels follow
        `encode_categorical()`'s rules. Only vertical bars have a time x-axis.
        """
        self.mark.encode_time_bars(
            self.settings, dates, values, y_err, y_err_lower, y_err_upper
        )
        return self^

    def encode_binned_categories(
        var self,
        data: List[Float64],
        bins: Int = 10,
    ) raises -> Self:
        """Bin raw observations into `bins` equal-width intervals for a
        categorical `Mark.BAR` chart: one bar per interval, labeled with
        its range, its height the count that landed in it. Named apart
        from `encode_histogram()` because it is a different chart -- the
        intervals become category labels, evenly spaced whatever their
        numeric width -- so `mark_histogram()` is what to reach for when
        the x-axis should be numeric (#698).

        Args:
            data: Raw observations to bin.
            bins: Number of equal-width intervals.

        Returns:
            Self, for further chaining.

        Raises:
            Error: The mark is not `Mark.BAR`, data is empty, bins is not
                positive, or a value is not finite.
        """
        self.mark.encode_binned_categories(self.settings, data, bins)
        return self^

    def encode_binned_categories(
        var self,
        data: List[Float64],
        rule: BinRule,
    ) raises -> Self:
        """`encode_binned_categories` with the bin count chosen by `rule`
        rather than named -- `BinRule.AUTO` for numpy's `bins="auto"`.

        Args:
            data: Raw observations to bin.
            rule: Which `BinRule` picks the bin count.

        Returns:
            Self, for further chaining.

        Raises:
            Error: The mark is not `Mark.BAR`, data is empty, or a value
                is not finite.
        """
        self.mark.encode_binned_categories(self.settings, data, rule)
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
        self.mark.encode_waterfall(self.settings, categories, deltas, is_total)
        return self^

    def encode_boxenplot(
        var self,
        categories: List[String],
        values: List[List[Float64]],
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
        self.mark.encode_boxenplot(self.settings, categories, values)
        return self^

    def encode_boxplot(
        var self,
        categories: List[String],
        values: List[List[Float64]],
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
        self.mark.encode_boxplot(self.settings, categories, values)
        return self^

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
        self.mark.encode_candlestick(
            self.settings, categories, open, high, low, close
        )
        return self^

    def encode_candlestick_time(
        var self,
        dates: List[Morrow],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) raises -> Self:
        """Map OHLC prices onto real timestamps for `Mark.CANDLESTICK`.

        Dates occupy their actual positions on a linear time axis, so
        weekends and other gaps are visible. The first date's zone sets
        the time tick labels, as with `encode_time()`. Length and spacing
        checks happen when the chart is rendered.
        """
        self.mark.encode_candlestick_time(
            self.settings, dates, open, high, low, close
        )
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
        self.mark.encode_bullet(
            self.settings, categories, measures, targets, ranges
        )
        return self^

    def encode_gantt(
        var self,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) raises -> Self:
        """Map a category column and two value columns (`start`/`end`) onto
        `Mark.GANTT`/`SPAN_CHART`'s span shape. This overload takes plain
        `Float64`; use `encode_gantt_time()` for `Morrow` dates on a dated
        Gantt axis. Numeric spans also serve generic span charts.
        Length checking is deferred to
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
        self.mark.encode_gantt(self.settings, categories, start, end)
        return self^

    def encode_gantt_time(
        var self,
        categories: List[String],
        start: List[Morrow],
        end: List[Morrow],
    ) raises -> Self:
        """Map Gantt task spans to a date-aware continuous x-axis.

        The first start's time zone sets tick labels. Mixed zones still
        place bars at their absolute instants. Length checks remain at
        render time, as with `encode_gantt()`.
        """
        self.mark.encode_gantt_time(self.settings, categories, start, end)
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
        self.mark.encode_grouped_bar(
            self.settings, categories, series_names, values, errors
        )
        return self^

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
        self.mark.encode_population_pyramid(
            self.settings,
            categories,
            left_values,
            right_values,
            left_name,
            right_name,
        )
        return self^

    def encode_heatmap(
        var self,
        x: List[String],
        y: List[String],
        value: List[Float64],
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
        self.mark.encode_heatmap(self.settings, x, y, value)
        return self^

    def encode_calendar(
        var self,
        dates: List[String],
        values: List[Float64],
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
        self.mark.encode_calendar(self.settings, dates, values)
        return self^

    def encode_corrplot(
        var self,
        variables: List[String],
        matrix: List[List[Float64]],
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
        self.mark.encode_corrplot(self.settings, variables, matrix)
        return self^

    def encode_punchcard(
        var self,
        x: List[String],
        y: List[String],
        sizes: List[Float64],
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
        self.mark.encode_punchcard(self.settings, x, y, sizes)
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
        self.mark.encode_barbs(self.settings, x, y, u, v)
        return self^

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
        self.mark.encode_contour(self.settings, z, levels, x, y)
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
        self.mark.encode_pcolormesh(self.settings, x_edges, y_edges, z)
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
        self.mark.encode_pcolormesh(self.settings, x_corners, y_corners, z)
        return self^

    def encode_time(
        var self,
        x: List[Morrow],
        y: List[Float64],
    ) raises -> Self:
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
        self.mark.encode_time(self.settings, x, y)
        return self^

    def encode_histogram_bins(
        var self,
        bins: HistogramBins,
    ) raises -> Self:
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
        self.mark.encode_histogram_bins(self.settings, bins)
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
        self.mark.encode_hist2d(self.settings, x, y, x_edges, y_edges)
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
        self.mark.encode_streamplot(self.settings, x, y, u, v)
        return self^

    def encode_hexbin(
        var self,
        x: List[Float64],
        y: List[Float64],
        gridsize: Int = 30,
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
        self.mark.encode_hexbin(self.settings, x, y, gridsize)
        return self^

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
        self.mark.encode_tricontour(self.settings, x, y, z, levels)
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
        self.mark.encode_triplot(
            self.settings, x, y, z, triangulation, facecolors, gouraud
        )
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
        self.mark.encode_marimekko(
            self.settings, categories, subcategories, values
        )
        return self^

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
        self.mark.encode_hierarchy(self.settings, ids, parent_ids, values)
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
        self.mark.encode_chord(
            self.settings, from_categories, to_categories, values
        )
        return self^

    def encode_polar(
        var self,
        angle: List[Float64],
        radius: List[Float64],
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
        self.mark.encode_polar(self.settings, angle, radius)
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
        self.mark.encode_polar_series(
            self.settings, angle, series_names, series_values
        )
        return self^

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
        self.mark.encode_radar(
            self.settings, indicators, max_values, series_names, series_values
        )
        return self^

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
        self.mark.encode_gauge(
            self.settings, value, min_value, max_value, breakpoints, band_colors
        )
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
        self.mark.encode_parallel(self.settings, dims, row_names, data)
        return self^

    def encode_kde(
        var self,
        values: List[Float64],
    ) raises -> Self:
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
        self.mark.encode_kde(self.settings, values)
        return self^

    def encode_eventplot(
        var self,
        labels: List[String],
        positions: List[List[Float64]],
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
        self.mark.encode_eventplot(self.settings, labels, positions)
        return self^

    def encode_distribution(
        var self,
        categories: List[String],
        values: List[List[Float64]],
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
        self.mark.encode_distribution(self.settings, categories, values)
        return self^

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
        self.mark.encode_single_axis(
            self.settings, x, color, color_categories, size
        )
        return self^

    def encode_imshow(
        var self,
        z: List[List[Float64]],
    ) raises -> Self:
        """Forwarded to the mark; refused at compile time on a mark without it.
        """
        self.mark.encode_imshow(self.settings, z)
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
        `Series`, a MAX Tensor/Buffer, or a plain Python list of numbers
        (see numpy_interop.mojo).
        Requires numpy in the caller's environment; raises numpy's own error
        if it's missing or `x`/`y` can't become a 1-D numeric array. `x`/`y`
        need not share a dtype. Materializes both via
        `_materialize_python_floats` and delegates to the concrete `encode()`.

        Args:
            x: The continuous x column, one entry per point -- a numpy
                `ndarray`, a pandas `Series`, a MAX Tensor/Buffer, or a plain
                Python list of numbers.
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
        _require_mark(Self.M.id, "encode", "mark_point()", _ok_encode^)
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
        `Series`/MAX Tensor or Buffer/plain Python number list, as
        `encode()`'s `PythonObject`
        overload is (see numpy_interop.mojo). `x` stays a concrete
        `List[String]`. Materializes `y` via `_materialize_python_floats` and
        delegates to the concrete overload.

        Args:
            x: One category per entry, in the given order.
            y: Each category's value -- a numpy `ndarray`, a pandas
                `Series`, a MAX Tensor/Buffer, or a plain Python list of
                numbers.
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
            Self.M.id,
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
        var self,
        data: List[Float64],
        bins: Int = 10,
        weights: List[Float64] = List[Float64](),
        stat: HistStat = HistStat.COUNT,
        cumulative: Bool = False,
    ) raises -> Self where Self.M == Histogram:
        """Bin raw observations into `bins` equal-width intervals for
        `Mark.HISTOGRAM`: exactly what `histogram()` draws for the same
        `data`, `bins`, `weights`, `stat` and `cumulative` --
        `bin_edges()`, then `histogram_bins()`, then
        `encode_histogram_bins()`, with the bin range pinned on the
        axis that carries the bins (#698). `encode_histogram_bins()` is
        the path for bins already computed; `encode_binned_categories()`
        is the categorical bar chart of labeled intervals.

        Args:
            data: Raw observations to bin.
            bins: Number of equal-width intervals.
            weights: One nonnegative weight per observation, or empty.
            stat: What a bin's height is; see `HistStat`.
            cumulative: Draw running totals instead of per-bin values.

        Returns:
            Self, for further chaining.

        Raises:
            Error: The mark is not `Mark.HISTOGRAM`, data is empty, bins
                is not positive, or a value is not finite.
        """
        return self^._encode_raw_histogram(
            histogram_bins(
                data,
                bin_edges(data, bins),
                weights=weights,
                stat=stat,
                cumulative=cumulative,
            )
        )

    def encode_histogram(
        var self,
        data: List[Float64],
        rule: BinRule,
        weights: List[Float64] = List[Float64](),
        stat: HistStat = HistStat.COUNT,
        cumulative: Bool = False,
    ) raises -> Self where Self.M == Histogram:
        """`encode_histogram` with the bin count chosen by `rule` rather
        than named -- `BinRule.AUTO` for numpy's `bins="auto"`, the
        overload `histogram()` and `bin_edges()` also have (#456).

        Args:
            data: Raw observations to bin.
            rule: Which `BinRule` picks the bin count.
            weights: One nonnegative weight per observation, or empty.
            stat: What a bin's height is; see `HistStat`.
            cumulative: Draw running totals instead of per-bin values.

        Returns:
            Self, for further chaining.

        Raises:
            Error: The mark is not `Mark.HISTOGRAM`, data is empty, or a
                value is not finite.
        """
        return self^._encode_raw_histogram(
            histogram_bins(
                data,
                bin_edges(data, rule),
                weights=weights,
                stat=stat,
                cumulative=cumulative,
            )
        )

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
        _require_mark(Self.M.id, "encode_quiver", "mark_quiver()", Mark.QUIVER)
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
        _require_mark(Self.M.id, "encode_ecdf", "mark_ecdf()", Mark.ECDF)
        _require_non_empty(len(values), "Plot.encode_ecdf()")
        return self^.encode_kde(values)

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

    def encode_frame(
        var self,
        df: DataFrame,
        x: String,
        y: String,
        color: String = "",
        size: String = "",
        labels: String = "",
    ) raises -> Self:
        """Encode from a `DataFrame` by column name: `x` and `y`, plus the
        optional `color`, `size` and `labels` columns. Continuous marks
        take a numeric `x`; categorical marks a string one. Refused at
        compile time on a mark that reads no frame."""
        self.mark.encode_frame(self.settings, df, x, y, color, size, labels)
        return self^

    def _encode_raw_histogram(
        var self, var binned: HistogramBins
    ) raises -> Self where Self.M == Histogram:
        var lo = binned.edges[0]
        var hi = binned.edges[len(binned.edges) - 1]
        var chart = self^.encode_histogram_bins(binned^)
        if rebind[Histogram](chart.mark).histogram.horizontal:
            if chart.settings.y_domain.has:
                return chart^
            return chart^.scale_y_domain(lo, hi)
        if chart.settings.x_domain.has:
            return chart^
        return chart^.scale_x_domain(lo, hi)


comptime _ErasedRender[T: DrawTarget] = def(
    Int,
    mut T,
    _MarkStyle,
    _AnnotationData,
    _ChartSettings,
    Int,
    Int,
    Int,
    Int,
    Bool,
    Float64,
    Float64,
    Bool,
    mut FontCache,
    Bool,
) raises thin -> _RenderResult


def _erased_render[
    M: MarkType, T: DrawTarget
](
    ptr: Int,
    mut target: T,
    style: _MarkStyle,
    annotations: _AnnotationData,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    has_shared_y_domain: Bool,
    shared_y_min: Float64,
    shared_y_max: Float64,
    shared_y_is_log: Bool,
    mut cache: FontCache,
    vector_target: Bool,
) raises -> _RenderResult:
    return Pointer[M, MutAnyOrigin](unsafe_from_address=ptr)[].render(
        target,
        style,
        annotations,
        settings,
        ox0,
        oy0,
        ox1,
        oy1,
        has_shared_y_domain,
        shared_y_min,
        shared_y_max,
        shared_y_is_log,
        cache=cache,
        vector_target=vector_target,
    )


def _erased_render_unbound[
    T: DrawTarget
](
    ptr: Int,
    mut target: T,
    style: _MarkStyle,
    annotations: _AnnotationData,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    has_shared_y_domain: Bool,
    shared_y_min: Float64,
    shared_y_max: Float64,
    shared_y_is_log: Bool,
    mut cache: FontCache,
    vector_target: Bool,
) raises -> _RenderResult:
    """The render slot of a target `AnyChart.bound[...]()` did not
    bind. Reaching it is a bug in a composition entry, which erases for
    the targets it draws marks into and must not hand the chart on."""
    raise Error(
        "AnyChart: this chart was erased without a render for this draw"
        " target; use erased() for a chart that has to render everywhere"
    )


def _erased_copy[M: MarkType](ptr: Int) -> Int:
    """A fresh heap copy of the mark at `ptr`, for `AnyChart.__copyinit__`."""
    var pointer = alloc(Layout[M](count=1)).unsafe_leak()
    pointer.unsafe_write(
        Pointer[M, MutAnyOrigin](unsafe_from_address=ptr)[].copy()
    )
    return Int(pointer)


def _erased_free[M: MarkType](ptr: Int):
    """Destroy the mark at `ptr` and free its memory, for `AnyChart.__del__`."""
    var pointer = Pointer[M, MutUntrackedOrigin](unsafe_from_address=ptr)
    _ = pointer.unsafe_take_pointee()
    dealloc(Allocation[M](unsafe_owned_ptr=pointer, layout=Layout[M](count=1)))


struct AnyChart(ChartLike):
    """A chart whose mark type has been erased, so charts of different
    marks can share a `List` for layers, facets and figures. It keeps
    everything a chart shares by value, copies of the shared channel
    structs the composition code reads (empty for a mark without them),
    the mark id, and the mark itself behind a pointer with the
    functions that draw, copy and free it, specialized when the chart
    is erased. Only the marks a program erases get instantiated.

    Erasing has to name the mark's render for every draw target it
    may meet, since the mark type is gone by the time a target is
    chosen, and each of those is a full render pipeline to compile:
    the three a `render_layers()` program never uses cost it about
    17 CPU-s (#838). `AnyChart(chart)` and `erased()` bind all four,
    which a `List[AnyChart]` needs because any entry may consume it.
    `bound[...]()` and `erased_with[...]()` bind only the targets named
    and leave the other slots on a stub that raises, for the variadic
    entries that erase inside a call that knows which targets it draws
    marks into and never hand the chart on. Layers draw every mark
    through their own layer renderers and bind none; facets draw each
    cell through the slot for their output target. (`render_grid()`'s
    `align_axes` probe draws through the `Canvas` slot whatever the
    output, which is fine: it takes a `List[AnyChart]`.)

    `mark[M]()` gives the mark back to code that has checked `id`.
    """

    var mark_id: Mark
    var caps: _Capabilities
    var settings: _ChartSettings
    var style: _MarkStyle
    var annotations: _AnnotationData
    var width: Int
    var height: Int
    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var distribution: _DistributionData
    var _ptr: Int
    var _render_canvas: _ErasedRender[Canvas]
    var _render_svg: _ErasedRender[SvgCanvas]
    var _render_pdf: _ErasedRender[PdfCanvas]
    var _render_bounds: _ErasedRender[BoundsTarget]
    var _copy: def(Int) thin -> Int
    var _free: def(Int) thin

    def __init__[M: MarkType](out self, chart: Chart[M]):
        self = Self(
            chart,
            canvas=_erased_render[M, Canvas],
            svg=_erased_render[M, SvgCanvas],
            pdf=_erased_render[M, PdfCanvas],
            bounds=_erased_render[M, BoundsTarget],
        )

    @staticmethod
    def bound[
        canvas: Bool, svg: Bool, pdf: Bool, bounds: Bool, M: MarkType
    ](chart: Chart[M]) -> AnyChart:
        """`chart` erased with only the named targets' renders bound;
        see the struct docstring. The other slots raise if drawn into."""
        var render_canvas: _ErasedRender[Canvas]
        var render_svg: _ErasedRender[SvgCanvas]
        var render_pdf: _ErasedRender[PdfCanvas]
        var render_bounds: _ErasedRender[BoundsTarget]

        comptime if canvas:
            render_canvas = _erased_render[M, Canvas]
        else:
            render_canvas = _erased_render_unbound[Canvas]

        comptime if svg:
            render_svg = _erased_render[M, SvgCanvas]
        else:
            render_svg = _erased_render_unbound[SvgCanvas]

        comptime if pdf:
            render_pdf = _erased_render[M, PdfCanvas]
        else:
            render_pdf = _erased_render_unbound[PdfCanvas]

        comptime if bounds:
            render_bounds = _erased_render[M, BoundsTarget]
        else:
            render_bounds = _erased_render_unbound[BoundsTarget]
        return Self(
            chart,
            canvas=render_canvas,
            svg=render_svg,
            pdf=render_pdf,
            bounds=render_bounds,
        )

    def __init__[
        M: MarkType
    ](
        out self,
        chart: Chart[M],
        *,
        canvas: _ErasedRender[Canvas],
        svg: _ErasedRender[SvgCanvas],
        pdf: _ErasedRender[PdfCanvas],
        bounds: _ErasedRender[BoundsTarget],
    ):
        self.mark_id = M.id
        self.caps = _capabilities_of_type[M]()
        self.settings = chart.settings.copy()
        self.style = chart.style.copy()
        self.annotations = chart.annotations.copy()
        self.width = chart.width
        self.height = chart.height
        self.continuous = _shared_continuous(chart.mark)
        self.categorical = _shared_categorical(chart.mark)
        self.channels = _shared_channels(chart.mark)
        self.y_err = _shared_y_err(chart.mark)
        self.distribution = _shared_distribution(chart.mark)
        var heap = alloc(Layout[M](count=1)).unsafe_leak()
        heap.unsafe_write(chart.mark.copy())
        self._ptr = Int(heap)
        self._render_canvas = canvas
        self._render_svg = svg
        self._render_pdf = pdf
        self._render_bounds = bounds
        self._copy = _erased_copy[M]
        self._free = _erased_free[M]

    def __init__(out self, *, copy: Self):
        self.mark_id = copy.mark_id
        self.caps = copy.caps
        self.settings = copy.settings.copy()
        self.style = copy.style.copy()
        self.annotations = copy.annotations.copy()
        self.width = copy.width
        self.height = copy.height
        self.continuous = copy.continuous.copy()
        self.categorical = copy.categorical.copy()
        self.channels = copy.channels.copy()
        self.y_err = copy.y_err.copy()
        self.distribution = copy.distribution.copy()
        self._ptr = copy._copy(copy._ptr)
        self._render_canvas = copy._render_canvas
        self._render_svg = copy._render_svg
        self._render_pdf = copy._render_pdf
        self._render_bounds = copy._render_bounds
        self._copy = copy._copy
        self._free = copy._free

    def __deinit__(deinit self):
        self._free(self._ptr)

    def mark[M: MarkType](self) raises -> ref[MutAnyOrigin] M:
        """The mark, for code that has checked `id`; raises otherwise
        rather than reinterpreting one mark's memory as another's."""
        if not (self.mark_id == M.id):
            raise Error(
                "AnyChart.mark["
                + M.id.name()
                + "](): this chart is a "
                + self.mark_id.name()
            )
        return Pointer[M, MutAnyOrigin](unsafe_from_address=self._ptr)[]

    def id(self) -> Mark:
        return self.mark_id

    def canvas_width(self) -> Int:
        return self.width

    def canvas_height(self) -> Int:
        return self.height

    def chart_settings(self) -> _ChartSettings:
        return self.settings.copy()

    def mark_style(self) -> _MarkStyle:
        return self.style.copy()

    def chart_annotations(self) -> _AnnotationData:
        return self.annotations.copy()

    def scaled_by(self, factor: Float64) -> Self:
        var out = self.copy()
        out.width = Int(Float64(self.width) * factor + 0.5)
        out.height = Int(Float64(self.height) * factor + 0.5)
        out.settings.theme.scale = self.settings.theme.scale * factor
        return out^

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
        self.settings.theme = t
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

    def erased(self) -> AnyChart:
        return self.copy()

    def erased_with[
        canvas: Bool = False,
        svg: Bool = False,
        pdf: Bool = False,
        bounds: Bool = False,
    ](self) -> AnyChart:
        return self.copy()

    def capabilities(self) -> _Capabilities:
        return self.caps

    def x_data(self) -> List[Float64]:
        return self.continuous.x.copy()

    def y_data(self) -> List[Float64]:
        return self.continuous.y.copy()

    def render_mark[
        T: DrawTarget
    ](
        self,
        mut target: T,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        has_shared_y_domain: Bool,
        shared_y_min: Float64,
        shared_y_max: Float64,
        shared_y_is_log: Bool,
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        comptime if T == Canvas:
            return self._render_canvas(
                self._ptr,
                rebind[Canvas](target),
                self.style,
                self.annotations,
                self.settings,
                ox0,
                oy0,
                ox1,
                oy1,
                has_shared_y_domain,
                shared_y_min,
                shared_y_max,
                shared_y_is_log,
                cache,
                vector_target,
            )
        elif T == SvgCanvas:
            return self._render_svg(
                self._ptr,
                rebind[SvgCanvas](target),
                self.style,
                self.annotations,
                self.settings,
                ox0,
                oy0,
                ox1,
                oy1,
                has_shared_y_domain,
                shared_y_min,
                shared_y_max,
                shared_y_is_log,
                cache,
                vector_target,
            )
        elif T == PdfCanvas:
            return self._render_pdf(
                self._ptr,
                rebind[PdfCanvas](target),
                self.style,
                self.annotations,
                self.settings,
                ox0,
                oy0,
                ox1,
                oy1,
                has_shared_y_domain,
                shared_y_min,
                shared_y_max,
                shared_y_is_log,
                cache,
                vector_target,
            )
        else:
            return self._render_bounds(
                self._ptr,
                rebind[BoundsTarget](target),
                self.style,
                self.annotations,
                self.settings,
                ox0,
                oy0,
                ox1,
                oy1,
                has_shared_y_domain,
                shared_y_min,
                shared_y_max,
                shared_y_is_log,
                cache,
                vector_target,
            )
