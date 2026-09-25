"""Every mark as a type (#828), one struct per `Mark` constant, over
the renderers and encoders phase 2 left behind. A mark holds only the
columns its renderer and encoders touch; `Chart[M]` holds what every
mark shares. Generated from `Plot`'s setters, `encode_*()` methods and
the `_render_*_plot` adapters, which stay the source of truth until
`Plot` itself becomes `Chart`."""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from canvas.color import Color
from dataviz.binned.histogram import BinRule, HistogramBins
from dataviz.core.cluster import Dendrogram
from dataviz.core.delaunay import Triangulation
from dataviz.core.marker import PointShape
from morrow import Morrow
from dataviz.aggregation.pointplot import _render_pointplot_oriented
from dataviz.basic.arc import _render_arc
from dataviz.basic.bar import (
    _encode_binned_categories,
    _encode_categorical,
    _encode_time_bars,
    _render_bar_oriented,
)
from dataviz.basic.continuous import _encode, _encode_time
from dataviz.basic.single_axis import _encode_single_axis, _render_single_axis
from dataviz.binned.hexbin import _HexbinData, _encode_hexbin, _render_hexbin
from dataviz.binned.histogram import _HistogramData, _encode_histogram_bins
from dataviz.categorical.bullet import (
    _BulletData,
    _encode_bullet,
    _render_bullet_oriented,
)
from dataviz.categorical.bump import _render_bump
from dataviz.categorical.funnel import _render_funnel
from dataviz.categorical.gantt import (
    _GanttData,
    _encode_gantt,
    _encode_gantt_time,
    _render_gantt,
)
from dataviz.categorical.grouped_bar import (
    _GroupedBarData,
    _encode_grouped_bar,
    _render_grouped_bar_oriented,
)
from dataviz.categorical.lollipop import _render_lollipop_oriented
from dataviz.categorical.population_pyramid import (
    _PyramidData,
    _encode_population_pyramid,
    _render_population_pyramid,
)
from dataviz.categorical.span_chart import _render_span_chart
from dataviz.categorical.stacked_bar import _render_stacked_bar_oriented
from dataviz.categorical.streamgraph import _render_streamgraph
from dataviz.categorical.waterfall import (
    _WaterfallData,
    _encode_waterfall,
    _render_waterfall_oriented,
)
from dataviz.core.annotations import _AnnotationData
from dataviz.core.chart_settings import _ChartSettings
from dataviz.core.mark import Mark
from dataviz.core.plot_fields import (
    _CategoricalData,
    _ChannelData,
    _ContinuousData,
    _DistributionData,
    _ErrorBarData,
    _MarkStyle,
)
from dataviz.core.render_result import _RenderResult
from dataviz.distributions.beeswarm import _render_beeswarm_oriented
from dataviz.distributions.box import (
    _BoxData,
    _encode_boxplot,
    _render_box_oriented,
)
from dataviz.distributions.boxen import (
    _BoxenData,
    _encode_boxenplot,
    _render_boxenplot_oriented,
)
from dataviz.distributions.candlestick import (
    _CandleData,
    _encode_candlestick,
    _encode_candlestick_time,
    _render_candlestick,
)
from dataviz.distributions.ecdf import _render_ecdf
from dataviz.distributions.eventplot import _encode_eventplot, _render_eventplot
from dataviz.distributions.kde import _encode_kde, _render_kde, _render_rug
from dataviz.distributions.ridgeline import _render_ridgeline
from dataviz.distributions.violin import (
    _encode_distribution,
    _render_violin_oriented,
)
from dataviz.grid.calendar_heatmap import (
    _CalendarData,
    _encode_calendar,
    _render_calendar_heatmap,
)
from dataviz.grid.corrplot import (
    _CorrplotData,
    _encode_corrplot,
    _render_corrplot,
)
from dataviz.grid.heatmap import _HeatmapData, _encode_heatmap, _render_heatmap
from dataviz.grid.image import (
    _ImageData,
    _encode_hist2d,
    _encode_pcolormesh,
    _render_image,
)
from dataviz.grid.marimekko import (
    _MarimekkoData,
    _encode_marimekko,
    _render_marimekko,
)
from dataviz.grid.punchcard import (
    _PunchcardData,
    _encode_punchcard,
    _render_punchcard,
)
from dataviz.hierarchy_marks.dendrogram import (
    _DendrogramData,
    _encode_dendrogram,
    _render_dendrogram,
)
from dataviz.hierarchy_marks.hierarchy import _HierarchyData, _encode_hierarchy
from dataviz.hierarchy_marks.sunburst import _render_sunburst
from dataviz.hierarchy_marks.tree import _render_tree
from dataviz.hierarchy_marks.treemap import _render_treemap
from dataviz.mark_type import MarkType
from dataviz.multivariate.barbs import _BarbsData, _encode_barbs, _render_barbs
from dataviz.multivariate.contour import (
    _ContourData,
    _encode_contour,
    _render_contour,
    _render_contourf,
)
from dataviz.multivariate.parallel import (
    _ParallelData,
    _encode_parallel,
    _render_parallel,
)
from dataviz.multivariate.quiver import _render_quiver
from dataviz.multivariate.streamplot import (
    _StreamData,
    _encode_streamplot,
    _render_streamplot,
)
from dataviz.multivariate.tricontour import (
    _TriContourData,
    _encode_tricontour,
    _render_tricontour,
    _render_tricontourf,
)
from dataviz.multivariate.triplot import (
    _TriplotData,
    _encode_triplot,
    _render_tripcolor,
    _render_triplot,
)
from dataviz.radial.gauge import _GaugeData, _encode_gauge, _render_gauge
from dataviz.radial.nightingale import _NightingaleData, _render_nightingale
from dataviz.radial.polar import (
    _PolarData,
    _encode_polar,
    _encode_polar_series,
    _render_polar,
)
from dataviz.radial.polar_bar import _render_polar_bar
from dataviz.radial.radar import _RadarData, _encode_radar, _render_radar
from dataviz.radial.radialbar import _render_radialbar
from dataviz.relationships.arc_diagram import _render_arc_diagram
from dataviz.relationships.chord import _render_chord
from dataviz.relationships.edges import _EdgeData, _encode_chord
from dataviz.relationships.graph import _render_graph
from dataviz.relationships.sankey import _render_sankey
from dataviz.rendering import _check_render_settings, _render_continuous
from dataviz.spatial.bar3d import (
    _Bars3D,
    _Voxels,
    _encode_bars3d,
    _encode_voxels,
    _render_bar3d,
    _render_voxels,
)
from dataviz.spatial.scatter3d import (
    _Xyz,
    _encode_xyz,
    _render_plot3d,
    _render_scatter3d,
)
from dataviz.spatial.stem3d import (
    _Ribbon3D,
    _Vectors3D,
    _encode_ribbon3d,
    _encode_vectors3d,
    _render_fill_between3d,
    _render_quiver3d,
    _render_stem3d,
)
from dataviz.spatial.surface3d import (
    _Surface,
    _encode_surface,
    _render_surface3d,
    _render_trisurf3d,
    _render_wire3d,
)


struct Point(MarkType):
    """`Mark.POINT` as a type. Built by `Plot2.mark_point()`."""

    comptime id = Mark.POINT

    var continuous: _ContinuousData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var categorical: _CategoricalData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.channels = _ChannelData()
        self.y_err = _ErrorBarData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_continuous(
            target,
            Self.id,
            _HistogramData(),
            self.continuous,
            self.channels,
            self.y_err,
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
        )

    def encode(
        mut self,
        mut settings: _ChartSettings,
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
    ) raises:
        _encode(
            Self.id,
            self.continuous,
            self.categorical,
            self.channels,
            self.y_err,
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

    def encode_time(
        mut self,
        mut settings: _ChartSettings,
        x: List[Morrow],
        y: List[Float64],
    ) raises:
        _encode_time(Self.id, self.continuous, self.categorical, settings, x, y)


struct Line(MarkType):
    """`Mark.LINE` as a type. Built by `Plot2.mark_line()`."""

    comptime id = Mark.LINE

    var continuous: _ContinuousData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var categorical: _CategoricalData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.channels = _ChannelData()
        self.y_err = _ErrorBarData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_continuous(
            target,
            Self.id,
            _HistogramData(),
            self.continuous,
            self.channels,
            self.y_err,
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
        )

    def encode(
        mut self,
        mut settings: _ChartSettings,
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
    ) raises:
        _encode(
            Self.id,
            self.continuous,
            self.categorical,
            self.channels,
            self.y_err,
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

    def encode_time(
        mut self,
        mut settings: _ChartSettings,
        x: List[Morrow],
        y: List[Float64],
    ) raises:
        _encode_time(Self.id, self.continuous, self.categorical, settings, x, y)


struct Bar(MarkType):
    """`Mark.BAR` as a type. Built by `Plot2.mark_bar()`."""

    comptime id = Mark.BAR

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_bar_oriented(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )

    def encode_time_bars(
        mut self,
        mut settings: _ChartSettings,
        dates: List[Morrow],
        values: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_time_bars(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            dates,
            values,
            y_err,
            y_err_lower,
            y_err_upper,
        )

    def encode_binned_categories(
        mut self,
        mut settings: _ChartSettings,
        data: List[Float64],
        bins: Int = 10,
    ) raises:
        _encode_binned_categories(
            Self.id, self.continuous, self.categorical, data, bins
        )

    def encode_binned_categories(
        mut self,
        mut settings: _ChartSettings,
        data: List[Float64],
        rule: BinRule,
    ) raises:
        _encode_binned_categories(
            Self.id, self.continuous, self.categorical, data, rule
        )


struct Area(MarkType):
    """`Mark.AREA` as a type. Built by `Plot2.mark_area()`."""

    comptime id = Mark.AREA

    var continuous: _ContinuousData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var categorical: _CategoricalData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.channels = _ChannelData()
        self.y_err = _ErrorBarData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_continuous(
            target,
            Self.id,
            _HistogramData(),
            self.continuous,
            self.channels,
            self.y_err,
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
        )

    def encode(
        mut self,
        mut settings: _ChartSettings,
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
    ) raises:
        _encode(
            Self.id,
            self.continuous,
            self.categorical,
            self.channels,
            self.y_err,
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

    def encode_time(
        mut self,
        mut settings: _ChartSettings,
        x: List[Morrow],
        y: List[Float64],
    ) raises:
        _encode_time(Self.id, self.continuous, self.categorical, settings, x, y)


struct Arc(MarkType):
    """`Mark.ARC` as a type. Built by `Plot2.mark_arc()`."""

    comptime id = Mark.ARC

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_arc(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct Lollipop(MarkType):
    """`Mark.LOLLIPOP` as a type. Built by `Plot2.mark_lollipop()`."""

    comptime id = Mark.LOLLIPOP

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_lollipop_oriented(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct Waterfall(MarkType):
    """`Mark.WATERFALL` as a type. Built by `Plot2.mark_waterfall()`."""

    comptime id = Mark.WATERFALL

    var waterfall: _WaterfallData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.waterfall = _WaterfallData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_waterfall_oriented(
            target,
            self.waterfall,
            self.continuous,
            self.categorical,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_waterfall(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        deltas: List[Float64],
        is_total: List[Bool] = List[Bool](),
    ) raises:
        _encode_waterfall(
            Self.id,
            self.waterfall,
            self.continuous,
            self.categorical,
            categories,
            deltas,
            is_total,
        )


struct Box(MarkType):
    """`Mark.BOX` as a type. Built by `Plot2.mark_box()`."""

    comptime id = Mark.BOX

    var box: _BoxData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.box = _BoxData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_box_oriented(
            target,
            self.box,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_boxplot(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        _encode_boxplot(
            Self.id,
            self.box,
            self.continuous,
            self.categorical,
            categories,
            values,
        )


struct Candlestick(MarkType):
    """`Mark.CANDLESTICK` as a type. Built by `Plot2.mark_candlestick()`."""

    comptime id = Mark.CANDLESTICK

    var candle: _CandleData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.candle = _CandleData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_candlestick(
            target,
            self.candle,
            self.continuous,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_candlestick(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) raises:
        _encode_candlestick(
            Self.id,
            self.candle,
            self.continuous,
            self.categorical,
            settings,
            categories,
            open,
            high,
            low,
            close,
        )

    def encode_candlestick_time(
        mut self,
        mut settings: _ChartSettings,
        dates: List[Morrow],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) raises:
        _encode_candlestick_time(
            Self.id,
            self.candle,
            self.continuous,
            self.categorical,
            settings,
            dates,
            open,
            high,
            low,
            close,
        )


struct Bullet(MarkType):
    """`Mark.BULLET` as a type. Built by `Plot2.mark_bullet()`."""

    comptime id = Mark.BULLET

    var bullet: _BulletData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.bullet = _BulletData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_bullet_oriented(
            target,
            self.bullet,
            self.categorical,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_bullet(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        measures: List[Float64],
        targets: List[Float64],
        ranges: List[List[Float64]],
    ) raises:
        _encode_bullet(
            Self.id,
            self.bullet,
            self.continuous,
            self.categorical,
            categories,
            measures,
            targets,
            ranges,
        )


struct Gantt(MarkType):
    """`Mark.GANTT` as a type. Built by `Plot2.mark_gantt()`."""

    comptime id = Mark.GANTT

    var gantt: _GanttData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.gantt = _GanttData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_gantt(
            target,
            self.gantt,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_gantt(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) raises:
        _encode_gantt(
            Self.id,
            self.gantt,
            self.continuous,
            self.categorical,
            settings,
            categories,
            start,
            end,
        )

    def encode_gantt_time(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        start: List[Morrow],
        end: List[Morrow],
    ) raises:
        _encode_gantt_time(
            Self.id,
            self.gantt,
            self.continuous,
            self.categorical,
            settings,
            categories,
            start,
            end,
        )


struct GroupedBar(MarkType):
    """`Mark.GROUPED_BAR` as a type. Built by `Plot2.mark_grouped_bar()`."""

    comptime id = Mark.GROUPED_BAR

    var grouped_bar: _GroupedBarData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.grouped_bar = _GroupedBarData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_grouped_bar_oriented(
            target,
            Self.id,
            self.grouped_bar,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_grouped_bar(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) raises:
        _encode_grouped_bar(
            Self.id,
            self.grouped_bar,
            self.continuous,
            self.categorical,
            categories,
            series_names,
            values,
            errors,
        )


struct StackedBar(MarkType):
    """`Mark.STACKED_BAR` as a type. Built by `Plot2.mark_stacked_bar()`."""

    comptime id = Mark.STACKED_BAR

    var grouped_bar: _GroupedBarData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.grouped_bar = _GroupedBarData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_stacked_bar_oriented(
            target,
            Self.id,
            self.grouped_bar,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_grouped_bar(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) raises:
        _encode_grouped_bar(
            Self.id,
            self.grouped_bar,
            self.continuous,
            self.categorical,
            categories,
            series_names,
            values,
            errors,
        )


struct PopulationPyramid(MarkType):
    """`Mark.POPULATION_PYRAMID` as a type. Built by `Plot2.mark_population_pyramid()`.
    """

    comptime id = Mark.POPULATION_PYRAMID

    var pyramid: _PyramidData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.pyramid = _PyramidData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_population_pyramid(
            target,
            self.pyramid,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_population_pyramid(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        left_values: List[Float64],
        right_values: List[Float64],
        left_name: String = "",
        right_name: String = "",
    ) raises:
        _encode_population_pyramid(
            Self.id,
            self.pyramid,
            self.continuous,
            self.categorical,
            categories,
            left_values,
            right_values,
            left_name,
            right_name,
        )


struct Heatmap(MarkType):
    """`Mark.HEATMAP` as a type. Built by `Plot2.mark_heatmap()`."""

    comptime id = Mark.HEATMAP

    var heatmap: _HeatmapData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.heatmap = _HeatmapData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_heatmap(
            target, self.heatmap, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_heatmap(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[String],
        value: List[Float64],
    ) raises:
        _encode_heatmap(
            Self.id,
            self.heatmap,
            self.continuous,
            self.categorical,
            x,
            y,
            value,
        )


struct Chord(MarkType):
    """`Mark.CHORD` as a type. Built by `Plot2.mark_chord()`."""

    comptime id = Mark.CHORD

    var edge_data: _EdgeData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.edge_data = _EdgeData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_chord(
            target,
            self.edge_data,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_chord(
        mut self,
        mut settings: _ChartSettings,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) raises:
        _encode_chord(
            Self.id,
            self.edge_data,
            self.continuous,
            self.categorical,
            from_categories,
            to_categories,
            values,
        )


struct SingleAxis(MarkType):
    """`Mark.SINGLE_AXIS` as a type. Built by `Plot2.mark_single_axis()`."""

    comptime id = Mark.SINGLE_AXIS

    var continuous: _ContinuousData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var categorical: _CategoricalData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.channels = _ChannelData()
        self.y_err = _ErrorBarData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_single_axis(
            target,
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_single_axis(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
    ) raises:
        _encode_single_axis(
            Self.id,
            self.continuous,
            self.categorical,
            self.channels,
            x,
            color,
            color_categories,
            size,
        )


struct EffectScatter(MarkType):
    """`Mark.EFFECT_SCATTER` as a type. Built by `Plot2.mark_effect_scatter()`.
    """

    comptime id = Mark.EFFECT_SCATTER

    var continuous: _ContinuousData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var categorical: _CategoricalData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.channels = _ChannelData()
        self.y_err = _ErrorBarData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_continuous(
            target,
            Self.id,
            _HistogramData(),
            self.continuous,
            self.channels,
            self.y_err,
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
        )

    def encode(
        mut self,
        mut settings: _ChartSettings,
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
    ) raises:
        _encode(
            Self.id,
            self.continuous,
            self.categorical,
            self.channels,
            self.y_err,
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

    def encode_time(
        mut self,
        mut settings: _ChartSettings,
        x: List[Morrow],
        y: List[Float64],
    ) raises:
        _encode_time(Self.id, self.continuous, self.categorical, settings, x, y)


struct Funnel(MarkType):
    """`Mark.FUNNEL` as a type. Built by `Plot2.mark_funnel()`."""

    comptime id = Mark.FUNNEL

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_funnel(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct Bump(MarkType):
    """`Mark.BUMP` as a type. Built by `Plot2.mark_bump()`."""

    comptime id = Mark.BUMP

    var grouped_bar: _GroupedBarData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.grouped_bar = _GroupedBarData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_bump(
            target,
            Self.id,
            self.grouped_bar,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_grouped_bar(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) raises:
        _encode_grouped_bar(
            Self.id,
            self.grouped_bar,
            self.continuous,
            self.categorical,
            categories,
            series_names,
            values,
            errors,
        )


struct Streamgraph(MarkType):
    """`Mark.STREAMGRAPH` as a type. Built by `Plot2.mark_streamgraph()`."""

    comptime id = Mark.STREAMGRAPH

    var grouped_bar: _GroupedBarData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.grouped_bar = _GroupedBarData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_streamgraph(
            target,
            Self.id,
            self.grouped_bar,
            self.categorical,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_grouped_bar(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) raises:
        _encode_grouped_bar(
            Self.id,
            self.grouped_bar,
            self.continuous,
            self.categorical,
            categories,
            series_names,
            values,
            errors,
        )


struct Beeswarm(MarkType):
    """`Mark.BEESWARM` as a type. Built by `Plot2.mark_beeswarm()`."""

    comptime id = Mark.BEESWARM

    var categorical: _CategoricalData
    var distribution: _DistributionData
    var continuous: _ContinuousData

    def __init__(out self):
        self.categorical = _CategoricalData()
        self.distribution = _DistributionData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_beeswarm_oriented(
            target,
            self.categorical,
            self.distribution,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_distribution(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        _encode_distribution(
            Self.id,
            self.continuous,
            self.categorical,
            self.distribution,
            categories,
            values,
        )


struct Violin(MarkType):
    """`Mark.VIOLIN` as a type. Built by `Plot2.mark_violin()`."""

    comptime id = Mark.VIOLIN

    var categorical: _CategoricalData
    var distribution: _DistributionData
    var continuous: _ContinuousData

    def __init__(out self):
        self.categorical = _CategoricalData()
        self.distribution = _DistributionData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_violin_oriented(
            target,
            self.categorical,
            self.distribution,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_distribution(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        _encode_distribution(
            Self.id,
            self.continuous,
            self.categorical,
            self.distribution,
            categories,
            values,
        )


struct Ridgeline(MarkType):
    """`Mark.RIDGELINE` as a type. Built by `Plot2.mark_ridgeline()`."""

    comptime id = Mark.RIDGELINE

    var categorical: _CategoricalData
    var distribution: _DistributionData
    var continuous: _ContinuousData

    def __init__(out self):
        self.categorical = _CategoricalData()
        self.distribution = _DistributionData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_ridgeline(
            target,
            self.categorical,
            self.distribution,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_distribution(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        _encode_distribution(
            Self.id,
            self.continuous,
            self.categorical,
            self.distribution,
            categories,
            values,
        )


struct Nightingale(MarkType):
    """`Mark.NIGHTINGALE` as a type. Built by `Plot2.mark_nightingale()`."""

    comptime id = Mark.NIGHTINGALE

    var nightingale: _NightingaleData
    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.nightingale = _NightingaleData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_nightingale(
            target,
            Self.id,
            self.nightingale,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct PolarBar(MarkType):
    """`Mark.POLAR_BAR` as a type. Built by `Plot2.mark_polar_bar()`."""

    comptime id = Mark.POLAR_BAR

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_polar_bar(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct Polar(MarkType):
    """`Mark.POLAR` as a type. Built by `Plot2.mark_polar()`."""

    comptime id = Mark.POLAR

    var polar: _PolarData

    def __init__(out self):
        self.polar = _PolarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_polar(
            target, self.polar, style, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_polar(
        mut self,
        mut settings: _ChartSettings,
        angle: List[Float64],
        radius: List[Float64],
    ) raises:
        _encode_polar(Self.id, self.polar, angle, radius)

    def encode_polar_series(
        mut self,
        mut settings: _ChartSettings,
        angle: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises:
        _encode_polar_series(
            Self.id, self.polar, angle, series_names, series_values
        )


struct Radar(MarkType):
    """`Mark.RADAR` as a type. Built by `Plot2.mark_radar()`."""

    comptime id = Mark.RADAR

    var radar: _RadarData

    def __init__(out self):
        self.radar = _RadarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_radar(
            target, self.radar, style, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_radar(
        mut self,
        mut settings: _ChartSettings,
        indicators: List[String],
        max_values: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises:
        _encode_radar(
            Self.id,
            self.radar,
            indicators,
            max_values,
            series_names,
            series_values,
        )


struct Gauge(MarkType):
    """`Mark.GAUGE` as a type. Built by `Plot2.mark_gauge()`."""

    comptime id = Mark.GAUGE

    var gauge: _GaugeData

    def __init__(out self):
        self.gauge = _GaugeData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_gauge(
            target, self.gauge, style, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_gauge(
        mut self,
        mut settings: _ChartSettings,
        value: Float64,
        min_value: Float64 = 0.0,
        max_value: Float64 = 100.0,
        breakpoints: List[Float64] = List[Float64](),
        band_colors: List[Color] = List[Color](),
    ) raises:
        _encode_gauge(
            Self.id,
            self.gauge,
            value,
            min_value,
            max_value,
            breakpoints,
            band_colors,
        )


struct Parallel(MarkType):
    """`Mark.PARALLEL` as a type. Built by `Plot2.mark_parallel()`."""

    comptime id = Mark.PARALLEL

    var parallel: _ParallelData

    def __init__(out self):
        self.parallel = _ParallelData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_parallel(
            target, self.parallel, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_parallel(
        mut self,
        mut settings: _ChartSettings,
        dims: List[String],
        row_names: List[String],
        data: List[List[Float64]],
    ) raises:
        _encode_parallel(Self.id, self.parallel, dims, row_names, data)


struct SpanChart(MarkType):
    """`Mark.SPAN_CHART` as a type. Built by `Plot2.mark_span_chart()`."""

    comptime id = Mark.SPAN_CHART

    var gantt: _GanttData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.gantt = _GanttData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_span_chart(
            target,
            self.gantt,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_gantt(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) raises:
        _encode_gantt(
            Self.id,
            self.gantt,
            self.continuous,
            self.categorical,
            settings,
            categories,
            start,
            end,
        )


struct CalendarHeatmap(MarkType):
    """`Mark.CALENDAR_HEATMAP` as a type. Built by `Plot2.mark_calendar_heatmap()`.
    """

    comptime id = Mark.CALENDAR_HEATMAP

    var calendar: _CalendarData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.calendar = _CalendarData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_calendar_heatmap(
            target, self.calendar, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_calendar(
        mut self,
        mut settings: _ChartSettings,
        dates: List[String],
        values: List[Float64],
    ) raises:
        _encode_calendar(
            Self.id,
            self.calendar,
            self.continuous,
            self.categorical,
            dates,
            values,
        )


struct Corrplot(MarkType):
    """`Mark.CORRPLOT` as a type. Built by `Plot2.mark_corrplot()`."""

    comptime id = Mark.CORRPLOT

    var corrplot: _CorrplotData

    def __init__(out self):
        self.corrplot = _CorrplotData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_corrplot(
            target,
            self.corrplot,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_corrplot(
        mut self,
        mut settings: _ChartSettings,
        variables: List[String],
        matrix: List[List[Float64]],
    ) raises:
        _encode_corrplot(Self.id, self.corrplot, variables, matrix)


struct Punchcard(MarkType):
    """`Mark.PUNCHCARD` as a type. Built by `Plot2.mark_punchcard()`."""

    comptime id = Mark.PUNCHCARD

    var punchcard: _PunchcardData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.punchcard = _PunchcardData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_punchcard(
            target, self.punchcard, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_punchcard(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[String],
        sizes: List[Float64],
    ) raises:
        _encode_punchcard(
            Self.id,
            self.punchcard,
            self.continuous,
            self.categorical,
            x,
            y,
            sizes,
        )


struct Marimekko(MarkType):
    """`Mark.MARIMEKKO` as a type. Built by `Plot2.mark_marimekko()`."""

    comptime id = Mark.MARIMEKKO

    var marimekko: _MarimekkoData

    def __init__(out self):
        self.marimekko = _MarimekkoData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_marimekko(
            target, self.marimekko, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_marimekko(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        subcategories: List[String],
        values: List[List[Float64]],
    ) raises:
        _encode_marimekko(
            Self.id, self.marimekko, categories, subcategories, values
        )


struct Sunburst(MarkType):
    """`Mark.SUNBURST` as a type. Built by `Plot2.mark_sunburst()`."""

    comptime id = Mark.SUNBURST

    var hierarchy: _HierarchyData

    def __init__(out self):
        self.hierarchy = _HierarchyData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_sunburst(
            target, self.hierarchy, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_hierarchy(
        mut self,
        mut settings: _ChartSettings,
        ids: List[String],
        parent_ids: List[String],
        values: List[Float64],
    ) raises:
        _encode_hierarchy(Self.id, self.hierarchy, ids, parent_ids, values)


struct Tree(MarkType):
    """`Mark.TREE` as a type. Built by `Plot2.mark_tree()`."""

    comptime id = Mark.TREE

    var hierarchy: _HierarchyData

    def __init__(out self):
        self.hierarchy = _HierarchyData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_tree(
            target, self.hierarchy, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_hierarchy(
        mut self,
        mut settings: _ChartSettings,
        ids: List[String],
        parent_ids: List[String],
        values: List[Float64],
    ) raises:
        _encode_hierarchy(Self.id, self.hierarchy, ids, parent_ids, values)


struct Treemap(MarkType):
    """`Mark.TREEMAP` as a type. Built by `Plot2.mark_treemap()`."""

    comptime id = Mark.TREEMAP

    var hierarchy: _HierarchyData

    def __init__(out self):
        self.hierarchy = _HierarchyData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_treemap(
            target, self.hierarchy, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_hierarchy(
        mut self,
        mut settings: _ChartSettings,
        ids: List[String],
        parent_ids: List[String],
        values: List[Float64],
    ) raises:
        _encode_hierarchy(Self.id, self.hierarchy, ids, parent_ids, values)


struct ArcDiagram(MarkType):
    """`Mark.ARC_DIAGRAM` as a type. Built by `Plot2.mark_arc_diagram()`."""

    comptime id = Mark.ARC_DIAGRAM

    var edge_data: _EdgeData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.edge_data = _EdgeData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_arc_diagram(
            target, self.edge_data, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_chord(
        mut self,
        mut settings: _ChartSettings,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) raises:
        _encode_chord(
            Self.id,
            self.edge_data,
            self.continuous,
            self.categorical,
            from_categories,
            to_categories,
            values,
        )


struct Graph(MarkType):
    """`Mark.GRAPH` as a type. Built by `Plot2.mark_graph()`."""

    comptime id = Mark.GRAPH

    var edge_data: _EdgeData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.edge_data = _EdgeData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_graph(
            target,
            self.edge_data,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_chord(
        mut self,
        mut settings: _ChartSettings,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) raises:
        _encode_chord(
            Self.id,
            self.edge_data,
            self.continuous,
            self.categorical,
            from_categories,
            to_categories,
            values,
        )


struct Sankey(MarkType):
    """`Mark.SANKEY` as a type. Built by `Plot2.mark_sankey()`."""

    comptime id = Mark.SANKEY

    var edge_data: _EdgeData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.edge_data = _EdgeData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_sankey(
            target,
            self.edge_data,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_chord(
        mut self,
        mut settings: _ChartSettings,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) raises:
        _encode_chord(
            Self.id,
            self.edge_data,
            self.continuous,
            self.categorical,
            from_categories,
            to_categories,
            values,
        )


struct Radialbar(MarkType):
    """`Mark.RADIALBAR` as a type. Built by `Plot2.mark_radialbar()`."""

    comptime id = Mark.RADIALBAR

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_radialbar(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct Barbs(MarkType):
    """`Mark.BARBS` as a type. Built by `Plot2.mark_barbs()`."""

    comptime id = Mark.BARBS

    var barbs: _BarbsData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.barbs = _BarbsData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_barbs(
            target, self.barbs, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_barbs(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        u: List[Float64],
        v: List[Float64],
    ) raises:
        _encode_barbs(
            Self.id, self.barbs, self.continuous, self.categorical, x, y, u, v
        )


struct Contour(MarkType):
    """`Mark.CONTOUR` as a type. Built by `Plot2.mark_contour()`."""

    comptime id = Mark.CONTOUR

    var contour: _ContourData

    def __init__(out self):
        self.contour = _ContourData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_contour(
            target, self.contour, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_contour(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
        levels: List[Float64] = List[Float64](),
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises:
        _encode_contour(Self.id, self.contour, z, levels, x, y)


struct Contourf(MarkType):
    """`Mark.CONTOURF` as a type. Built by `Plot2.mark_contourf()`."""

    comptime id = Mark.CONTOURF

    var contour: _ContourData

    def __init__(out self):
        self.contour = _ContourData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_contourf(
            target, self.contour, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_contour(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
        levels: List[Float64] = List[Float64](),
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises:
        _encode_contour(Self.id, self.contour, z, levels, x, y)


struct Tricontour(MarkType):
    """`Mark.TRICONTOUR` as a type. Built by `Plot2.mark_tricontour()`."""

    comptime id = Mark.TRICONTOUR

    var tricontour: _TriContourData

    def __init__(out self):
        self.tricontour = _TriContourData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_tricontour(
            target, self.tricontour, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_tricontour(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        levels: List[Float64] = List[Float64](),
    ) raises:
        _encode_tricontour(Self.id, self.tricontour, x, y, z, levels)


struct Tricontourf(MarkType):
    """`Mark.TRICONTOURF` as a type. Built by `Plot2.mark_tricontourf()`."""

    comptime id = Mark.TRICONTOURF

    var tricontour: _TriContourData

    def __init__(out self):
        self.tricontour = _TriContourData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_tricontourf(
            target, self.tricontour, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_tricontour(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        levels: List[Float64] = List[Float64](),
    ) raises:
        _encode_tricontour(Self.id, self.tricontour, x, y, z, levels)


struct Kde(MarkType):
    """`Mark.KDE` as a type. Built by `Plot2.mark_kde()`."""

    comptime id = Mark.KDE

    var distribution: _DistributionData

    def __init__(out self):
        self.distribution = _DistributionData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_kde(
            target, self.distribution, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_kde(
        mut self,
        mut settings: _ChartSettings,
        values: List[Float64],
    ) raises:
        _encode_kde(Self.id, self.distribution, values)


struct Rug(MarkType):
    """`Mark.RUG` as a type. Built by `Plot2.mark_rug()`."""

    comptime id = Mark.RUG

    var distribution: _DistributionData

    def __init__(out self):
        self.distribution = _DistributionData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_rug(
            target,
            Self.id,
            self.distribution,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_kde(
        mut self,
        mut settings: _ChartSettings,
        values: List[Float64],
    ) raises:
        _encode_kde(Self.id, self.distribution, values)


struct Triplot(MarkType):
    """`Mark.TRIPLOT` as a type. Built by `Plot2.mark_triplot()`."""

    comptime id = Mark.TRIPLOT

    var triplot: _TriplotData

    def __init__(out self):
        self.triplot = _TriplotData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_triplot(
            target, self.triplot, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_triplot(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64] = List[Float64](),
        triangulation: Triangulation = Triangulation(),
        facecolors: List[Float64] = List[Float64](),
        gouraud: Bool = False,
    ) raises:
        _encode_triplot(
            Self.id, self.triplot, x, y, z, triangulation, facecolors, gouraud
        )


struct Tripcolor(MarkType):
    """`Mark.TRIPCOLOR` as a type. Built by `Plot2.mark_tripcolor()`."""

    comptime id = Mark.TRIPCOLOR

    var triplot: _TriplotData

    def __init__(out self):
        self.triplot = _TriplotData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_tripcolor(
            target, self.triplot, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_triplot(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64] = List[Float64](),
        triangulation: Triangulation = Triangulation(),
        facecolors: List[Float64] = List[Float64](),
        gouraud: Bool = False,
    ) raises:
        _encode_triplot(
            Self.id, self.triplot, x, y, z, triangulation, facecolors, gouraud
        )


struct Ecdf(MarkType):
    """`Mark.ECDF` as a type. Built by `Plot2.mark_ecdf()`."""

    comptime id = Mark.ECDF

    var distribution: _DistributionData

    def __init__(out self):
        self.distribution = _DistributionData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_ecdf(
            target,
            Self.id,
            self.distribution,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_kde(
        mut self,
        mut settings: _ChartSettings,
        values: List[Float64],
    ) raises:
        _encode_kde(Self.id, self.distribution, values)


struct Imshow(MarkType):
    """`Mark.IMSHOW` as a type. Built by `Plot2.mark_imshow()`."""

    comptime id = Mark.IMSHOW

    var image: _ImageData

    def __init__(out self):
        self.image = _ImageData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_image(
            target,
            Self.id,
            self.image,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
            vector_target=vector_target,
        )

    def encode_imshow(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
    ) raises:
        self.image.z = z.copy()


struct Pcolormesh(MarkType):
    """`Mark.PCOLORMESH` as a type. Built by `Plot2.mark_pcolormesh()`."""

    comptime id = Mark.PCOLORMESH

    var image: _ImageData

    def __init__(out self):
        self.image = _ImageData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_image(
            target,
            Self.id,
            self.image,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
            vector_target=vector_target,
        )

    def encode_pcolormesh(
        mut self,
        mut settings: _ChartSettings,
        x_edges: List[Float64],
        y_edges: List[Float64],
        z: List[List[Float64]],
    ) raises:
        _encode_pcolormesh(Self.id, self.image, x_edges, y_edges, z)

    def encode_pcolormesh(
        mut self,
        mut settings: _ChartSettings,
        x_corners: List[List[Float64]],
        y_corners: List[List[Float64]],
        z: List[List[Float64]],
    ) raises:
        _encode_pcolormesh(Self.id, self.image, x_corners, y_corners, z)


struct Eventplot(MarkType):
    """`Mark.EVENTPLOT` as a type. Built by `Plot2.mark_eventplot()`."""

    comptime id = Mark.EVENTPLOT

    var categorical: _CategoricalData
    var distribution: _DistributionData
    var continuous: _ContinuousData

    def __init__(out self):
        self.categorical = _CategoricalData()
        self.distribution = _DistributionData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_eventplot(
            target,
            self.categorical,
            self.distribution,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_eventplot(
        mut self,
        mut settings: _ChartSettings,
        labels: List[String],
        positions: List[List[Float64]],
    ) raises:
        _encode_eventplot(
            Self.id,
            self.continuous,
            self.categorical,
            self.distribution,
            labels,
            positions,
        )


struct Pointplot(MarkType):
    """`Mark.POINTPLOT` as a type. Built by `Plot2.mark_pointplot()`."""

    comptime id = Mark.POINTPLOT

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var y_err: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.y_err = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_pointplot_oriented(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        _encode_categorical(
            Self.id,
            self.continuous,
            self.categorical,
            self.y_err,
            settings,
            x,
            y,
            y_err,
            y_err_lower,
            y_err_upper,
        )


struct Boxenplot(MarkType):
    """`Mark.BOXENPLOT` as a type. Built by `Plot2.mark_boxenplot()`."""

    comptime id = Mark.BOXENPLOT

    var boxen: _BoxenData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.boxen = _BoxenData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_boxenplot_oriented(
            target,
            self.boxen,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )

    def encode_boxenplot(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        _encode_boxenplot(
            Self.id,
            self.boxen,
            self.continuous,
            self.categorical,
            categories,
            values,
        )


struct Hist2d(MarkType):
    """`Mark.HIST2D` as a type. Built by `Plot2.mark_hist2d()`."""

    comptime id = Mark.HIST2D

    var image: _ImageData

    def __init__(out self):
        self.image = _ImageData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_image(
            target,
            Self.id,
            self.image,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
            vector_target=vector_target,
        )

    def encode_hist2d(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        x_edges: List[Float64],
        y_edges: List[Float64],
    ) raises:
        _encode_hist2d(Self.id, self.image, x, y, x_edges, y_edges)


struct Hexbin(MarkType):
    """`Mark.HEXBIN` as a type. Built by `Plot2.mark_hexbin()`."""

    comptime id = Mark.HEXBIN

    var hexbin: _HexbinData

    def __init__(out self):
        self.hexbin = _HexbinData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_hexbin(
            target, self.hexbin, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_hexbin(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        gridsize: Int = 30,
    ) raises:
        _encode_hexbin(Self.id, self.hexbin, x, y, gridsize)


struct Quiver(MarkType):
    """`Mark.QUIVER` as a type. Built by `Plot2.mark_quiver()`."""

    comptime id = Mark.QUIVER

    var barbs: _BarbsData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.barbs = _BarbsData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_quiver(
            target, self.barbs, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_barbs(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        u: List[Float64],
        v: List[Float64],
    ) raises:
        _encode_barbs(
            Self.id, self.barbs, self.continuous, self.categorical, x, y, u, v
        )


struct Histogram(MarkType):
    """`Mark.HISTOGRAM` as a type. Built by `Plot2.mark_histogram()`."""

    comptime id = Mark.HISTOGRAM

    var continuous: _ContinuousData
    var channels: _ChannelData
    var y_err: _ErrorBarData
    var histogram: _HistogramData
    var categorical: _CategoricalData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.channels = _ChannelData()
        self.y_err = _ErrorBarData()
        self.histogram = _HistogramData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            self.channels,
            self.y_err,
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_continuous(
            target,
            Self.id,
            self.histogram,
            self.continuous,
            self.channels,
            self.y_err,
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
        )

    def encode_histogram_bins(
        mut self,
        mut settings: _ChartSettings,
        bins: HistogramBins,
    ) raises:
        _encode_histogram_bins(
            Self.id, self.histogram, self.continuous, self.categorical, bins
        )


struct Streamplot(MarkType):
    """`Mark.STREAMPLOT` as a type. Built by `Plot2.mark_streamplot()`."""

    comptime id = Mark.STREAMPLOT

    var stream: _StreamData
    var continuous: _ContinuousData
    var categorical: _CategoricalData

    def __init__(out self):
        self.stream = _StreamData()
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            self.continuous,
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_streamplot(
            target, self.stream, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_streamplot(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        u: List[List[Float64]],
        v: List[List[Float64]],
    ) raises:
        _encode_streamplot(
            Self.id, self.stream, self.continuous, self.categorical, x, y, u, v
        )


struct DendrogramMark(MarkType):
    """`Mark.DENDROGRAM` as a type. Built by `Plot2.mark_dendrogram()`."""

    comptime id = Mark.DENDROGRAM

    var dendrogram: _DendrogramData

    def __init__(out self):
        self.dendrogram = _DendrogramData()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_dendrogram(
            target, self.dendrogram, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_dendrogram(
        mut self,
        mut settings: _ChartSettings,
        tree: Dendrogram,
        labels: List[String],
        horizontal: Bool = False,
    ):
        _encode_dendrogram(self.dendrogram, tree, labels, horizontal)


struct Scatter3d(MarkType):
    """`Mark.SCATTER3D` as a type. Built by `Plot2.mark_scatter3d()`."""

    comptime id = Mark.SCATTER3D

    var xyz: _Xyz

    def __init__(out self):
        self.xyz = _Xyz()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_scatter3d(
            target, self.xyz, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_xyz(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        _encode_xyz(Self.id, self.xyz, x, y, z)


struct Plot3d(MarkType):
    """`Mark.PLOT3D` as a type. Built by `Plot2.mark_plot3d()`."""

    comptime id = Mark.PLOT3D

    var xyz: _Xyz

    def __init__(out self):
        self.xyz = _Xyz()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_plot3d(
            target, self.xyz, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_xyz(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        _encode_xyz(Self.id, self.xyz, x, y, z)


struct Surface3d(MarkType):
    """`Mark.SURFACE3D` as a type. Built by `Plot2.mark_surface3d()`."""

    comptime id = Mark.SURFACE3D

    var surface: _Surface

    def __init__(out self):
        self.surface = _Surface()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_surface3d(
            target, self.surface, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_surface(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises:
        _encode_surface(Self.id, self.surface, z, x, y)


struct Wire3d(MarkType):
    """`Mark.WIRE3D` as a type. Built by `Plot2.mark_wire3d()`."""

    comptime id = Mark.WIRE3D

    var surface: _Surface

    def __init__(out self):
        self.surface = _Surface()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_wire3d(
            target, self.surface, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_surface(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises:
        _encode_surface(Self.id, self.surface, z, x, y)


struct Trisurf3d(MarkType):
    """`Mark.TRISURF3D` as a type. Built by `Plot2.mark_trisurf3d()`."""

    comptime id = Mark.TRISURF3D

    var xyz: _Xyz

    def __init__(out self):
        self.xyz = _Xyz()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_trisurf3d(
            target, self.xyz, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_xyz(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        _encode_xyz(Self.id, self.xyz, x, y, z)


struct Bar3d(MarkType):
    """`Mark.BAR3D` as a type. Built by `Plot2.mark_bar3d()`."""

    comptime id = Mark.BAR3D

    var bars3d: _Bars3D

    def __init__(out self):
        self.bars3d = _Bars3D()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_bar3d(
            target, self.bars3d, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_bars3d(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        _encode_bars3d(Self.id, self.bars3d, x, y, z)


struct Voxels(MarkType):
    """`Mark.VOXELS` as a type. Built by `Plot2.mark_voxels()`."""

    comptime id = Mark.VOXELS

    var voxels: _Voxels

    def __init__(out self):
        self.voxels = _Voxels()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_voxels(
            target, self.voxels, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_voxels(
        mut self,
        mut settings: _ChartSettings,
        filled: List[List[List[Bool]]],
    ) raises:
        _encode_voxels(Self.id, self.voxels, filled)


struct Stem3d(MarkType):
    """`Mark.STEM3D` as a type. Built by `Plot2.mark_stem3d()`."""

    comptime id = Mark.STEM3D

    var xyz: _Xyz

    def __init__(out self):
        self.xyz = _Xyz()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_stem3d(
            target, self.xyz, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_xyz(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        _encode_xyz(Self.id, self.xyz, x, y, z)


struct Quiver3d(MarkType):
    """`Mark.QUIVER3D` as a type. Built by `Plot2.mark_quiver3d()`."""

    comptime id = Mark.QUIVER3D

    var vectors3d: _Vectors3D

    def __init__(out self):
        self.vectors3d = _Vectors3D()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_quiver3d(
            target, self.vectors3d, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_vectors3d(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        u: List[Float64],
        v: List[Float64],
        w: List[Float64],
    ) raises:
        _encode_vectors3d(Self.id, self.vectors3d, x, y, z, u, v, w)


struct FillBetween3d(MarkType):
    """`Mark.FILL_BETWEEN3D` as a type. Built by `Plot2.mark_fill_between3d()`.
    """

    comptime id = Mark.FILL_BETWEEN3D

    var ribbon3d: _Ribbon3D

    def __init__(out self):
        self.ribbon3d = _Ribbon3D()

    def render[
        T: DrawTarget
    ](
        self,
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
        *,
        mut cache: FontCache,
        vector_target: Bool,
    ) raises -> _RenderResult:
        _check_render_settings(
            Self.id,
            _ContinuousData(),
            _ChannelData(),
            _ErrorBarData(),
            annotations,
            settings,
            has_shared_y_domain,
            shared_y_is_log,
        )
        return _render_fill_between3d(
            target, self.ribbon3d, settings, ox0, oy0, ox1, oy1, cache=cache
        )

    def encode_ribbon3d(
        mut self,
        mut settings: _ChartSettings,
        x1: List[Float64],
        y1: List[Float64],
        z1: List[Float64],
        x2: List[Float64],
        y2: List[Float64],
        z2: List[Float64],
    ) raises:
        _encode_ribbon3d(Self.id, self.ribbon3d, x1, y1, z1, x2, y2, z2)
