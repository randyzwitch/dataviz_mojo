"""The trait a chart's mark type implements (#828): a runtime `Mark`
id for the tables and messages that still key on it, a renderer over
the mark's own columns, and every `encode_*()` the package has, each
with a default body that refuses at compile time. A mark overrides the
encoders it accepts, so `Chart[M].encode_x()` is a compile error on any
other `M`, which is what `_require_mark` checked at run time."""

from canvas.text.font_cache import FontCache
from dataframe import DataFrame
from canvas.vector.draw_target import DrawTarget
from canvas.color import Color
from dataviz.binned.histogram import BinRule, HistogramBins
from dataviz.core.cluster import Dendrogram
from dataviz.core.delaunay import Triangulation
from dataviz.core.marker import PointShape
from morrow import Morrow
from dataviz.core.annotations import _AnnotationData
from dataviz.core.capabilities import _Capabilities
from dataviz.core.chart_settings import _ChartSettings
from dataviz.core.mark import Mark
from dataviz.core.plot_fields import _MarkStyle
from dataviz.core.render_result import _RenderResult


trait MarkType(Copyable, Deinitable, Movable):
    """See the module docstring."""

    comptime id: Mark
    comptime supports_tooltips: Bool
    comptime supports_data_labels: Bool
    comptime supports_horizontal: Bool
    comptime supports_annotations_y: Bool
    comptime supports_annotations_x: Bool
    comptime supports_annotations_xy: Bool
    comptime supports_log_x: Bool
    comptime supports_log_y: Bool
    comptime supports_color_size: Bool

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
        ...

    def encode_dendrogram(
        mut self,
        mut settings: _ChartSettings,
        tree: Dendrogram,
        labels: List[String],
        horizontal: Bool = False,
    ):
        """Refused at compile time: this mark has no `encode_dendrogram()`."""
        comptime assert (
            False
        ), "encode_dendrogram(): not an encoder of this mark"

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
        """Refused at compile time: this mark has no `encode()`."""
        comptime assert False, "encode(): not an encoder of this mark"

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
        """Refused at compile time: this mark has no `encode_vectors3d()`."""
        comptime assert False, "encode_vectors3d(): not an encoder of this mark"

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
        """Refused at compile time: this mark has no `encode_ribbon3d()`."""
        comptime assert False, "encode_ribbon3d(): not an encoder of this mark"

    def encode_bars3d(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_bars3d()`."""
        comptime assert False, "encode_bars3d(): not an encoder of this mark"

    def encode_voxels(
        mut self,
        mut settings: _ChartSettings,
        filled: List[List[List[Bool]]],
    ) raises:
        """Refused at compile time: this mark has no `encode_voxels()`."""
        comptime assert False, "encode_voxels(): not an encoder of this mark"

    def encode_surface(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises:
        """Refused at compile time: this mark has no `encode_surface()`."""
        comptime assert False, "encode_surface(): not an encoder of this mark"

    def encode_xyz(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_xyz()`."""
        comptime assert False, "encode_xyz(): not an encoder of this mark"

    def encode_categorical(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        """Refused at compile time: this mark has no `encode_categorical()`."""
        comptime assert (
            False
        ), "encode_categorical(): not an encoder of this mark"

    def encode_time_bars(
        mut self,
        mut settings: _ChartSettings,
        dates: List[Morrow],
        values: List[Float64],
        y_err: List[Float64] = List[Float64](),
        y_err_lower: List[Float64] = List[Float64](),
        y_err_upper: List[Float64] = List[Float64](),
    ) raises:
        """Refused at compile time: this mark has no `encode_time_bars()`."""
        comptime assert False, "encode_time_bars(): not an encoder of this mark"

    def encode_binned_categories(
        mut self,
        mut settings: _ChartSettings,
        data: List[Float64],
        bins: Int = 10,
    ) raises:
        """Refused at compile time: this mark has no `encode_binned_categories()`.
        """
        comptime assert (
            False
        ), "encode_binned_categories(): not an encoder of this mark"

    def encode_binned_categories(
        mut self,
        mut settings: _ChartSettings,
        data: List[Float64],
        rule: BinRule,
    ) raises:
        """Refused at compile time: this mark has no `encode_binned_categories()`.
        """
        comptime assert (
            False
        ), "encode_binned_categories(): not an encoder of this mark"

    def encode_waterfall(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        deltas: List[Float64],
        is_total: List[Bool] = List[Bool](),
    ) raises:
        """Refused at compile time: this mark has no `encode_waterfall()`."""
        comptime assert False, "encode_waterfall(): not an encoder of this mark"

    def encode_boxenplot(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_boxenplot()`."""
        comptime assert False, "encode_boxenplot(): not an encoder of this mark"

    def encode_boxplot(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_boxplot()`."""
        comptime assert False, "encode_boxplot(): not an encoder of this mark"

    def encode_candlestick(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_candlestick()`."""
        comptime assert (
            False
        ), "encode_candlestick(): not an encoder of this mark"

    def encode_candlestick_time(
        mut self,
        mut settings: _ChartSettings,
        dates: List[Morrow],
        open: List[Float64],
        high: List[Float64],
        low: List[Float64],
        close: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_candlestick_time()`.
        """
        comptime assert (
            False
        ), "encode_candlestick_time(): not an encoder of this mark"

    def encode_bullet(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        measures: List[Float64],
        targets: List[Float64],
        ranges: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_bullet()`."""
        comptime assert False, "encode_bullet(): not an encoder of this mark"

    def encode_gantt(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_gantt()`."""
        comptime assert False, "encode_gantt(): not an encoder of this mark"

    def encode_gantt_time(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        start: List[Morrow],
        end: List[Morrow],
    ) raises:
        """Refused at compile time: this mark has no `encode_gantt_time()`."""
        comptime assert (
            False
        ), "encode_gantt_time(): not an encoder of this mark"

    def encode_grouped_bar(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        series_names: List[String],
        values: List[List[Float64]],
        errors: List[List[Float64]] = List[List[Float64]](),
    ) raises:
        """Refused at compile time: this mark has no `encode_grouped_bar()`."""
        comptime assert (
            False
        ), "encode_grouped_bar(): not an encoder of this mark"

    def encode_population_pyramid(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        left_values: List[Float64],
        right_values: List[Float64],
        left_name: String = "",
        right_name: String = "",
    ) raises:
        """Refused at compile time: this mark has no `encode_population_pyramid()`.
        """
        comptime assert (
            False
        ), "encode_population_pyramid(): not an encoder of this mark"

    def encode_heatmap(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[String],
        value: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_heatmap()`."""
        comptime assert False, "encode_heatmap(): not an encoder of this mark"

    def encode_calendar(
        mut self,
        mut settings: _ChartSettings,
        dates: List[String],
        values: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_calendar()`."""
        comptime assert False, "encode_calendar(): not an encoder of this mark"

    def encode_corrplot(
        mut self,
        mut settings: _ChartSettings,
        variables: List[String],
        matrix: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_corrplot()`."""
        comptime assert False, "encode_corrplot(): not an encoder of this mark"

    def encode_punchcard(
        mut self,
        mut settings: _ChartSettings,
        x: List[String],
        y: List[String],
        sizes: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_punchcard()`."""
        comptime assert False, "encode_punchcard(): not an encoder of this mark"

    def encode_barbs(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        u: List[Float64],
        v: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_barbs()`."""
        comptime assert False, "encode_barbs(): not an encoder of this mark"

    def encode_contour(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
        levels: List[Float64] = List[Float64](),
        x: List[Float64] = List[Float64](),
        y: List[Float64] = List[Float64](),
    ) raises:
        """Refused at compile time: this mark has no `encode_contour()`."""
        comptime assert False, "encode_contour(): not an encoder of this mark"

    def encode_pcolormesh(
        mut self,
        mut settings: _ChartSettings,
        x_edges: List[Float64],
        y_edges: List[Float64],
        z: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_pcolormesh()`."""
        comptime assert (
            False
        ), "encode_pcolormesh(): not an encoder of this mark"

    def encode_pcolormesh(
        mut self,
        mut settings: _ChartSettings,
        x_corners: List[List[Float64]],
        y_corners: List[List[Float64]],
        z: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_pcolormesh()`."""
        comptime assert (
            False
        ), "encode_pcolormesh(): not an encoder of this mark"

    def encode_time(
        mut self,
        mut settings: _ChartSettings,
        x: List[Morrow],
        y: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_time()`."""
        comptime assert False, "encode_time(): not an encoder of this mark"

    def encode_histogram_bins(
        mut self,
        mut settings: _ChartSettings,
        bins: HistogramBins,
    ) raises:
        """Refused at compile time: this mark has no `encode_histogram_bins()`.
        """
        comptime assert (
            False
        ), "encode_histogram_bins(): not an encoder of this mark"

    def encode_hist2d(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        x_edges: List[Float64],
        y_edges: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_hist2d()`."""
        comptime assert False, "encode_hist2d(): not an encoder of this mark"

    def encode_streamplot(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        u: List[List[Float64]],
        v: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_streamplot()`."""
        comptime assert (
            False
        ), "encode_streamplot(): not an encoder of this mark"

    def encode_hexbin(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        gridsize: Int = 30,
    ) raises:
        """Refused at compile time: this mark has no `encode_hexbin()`."""
        comptime assert False, "encode_hexbin(): not an encoder of this mark"

    def encode_tricontour(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        y: List[Float64],
        z: List[Float64],
        levels: List[Float64] = List[Float64](),
    ) raises:
        """Refused at compile time: this mark has no `encode_tricontour()`."""
        comptime assert (
            False
        ), "encode_tricontour(): not an encoder of this mark"

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
        """Refused at compile time: this mark has no `encode_triplot()`."""
        comptime assert False, "encode_triplot(): not an encoder of this mark"

    def encode_marimekko(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        subcategories: List[String],
        values: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_marimekko()`."""
        comptime assert False, "encode_marimekko(): not an encoder of this mark"

    def encode_hierarchy(
        mut self,
        mut settings: _ChartSettings,
        ids: List[String],
        parent_ids: List[String],
        values: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_hierarchy()`."""
        comptime assert False, "encode_hierarchy(): not an encoder of this mark"

    def encode_chord(
        mut self,
        mut settings: _ChartSettings,
        from_categories: List[String],
        to_categories: List[String],
        values: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_chord()`."""
        comptime assert False, "encode_chord(): not an encoder of this mark"

    def encode_polar(
        mut self,
        mut settings: _ChartSettings,
        angle: List[Float64],
        radius: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_polar()`."""
        comptime assert False, "encode_polar(): not an encoder of this mark"

    def encode_polar_series(
        mut self,
        mut settings: _ChartSettings,
        angle: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_polar_series()`."""
        comptime assert (
            False
        ), "encode_polar_series(): not an encoder of this mark"

    def encode_radar(
        mut self,
        mut settings: _ChartSettings,
        indicators: List[String],
        max_values: List[Float64],
        series_names: List[String],
        series_values: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_radar()`."""
        comptime assert False, "encode_radar(): not an encoder of this mark"

    def encode_gauge(
        mut self,
        mut settings: _ChartSettings,
        value: Float64,
        min_value: Float64 = 0.0,
        max_value: Float64 = 100.0,
        breakpoints: List[Float64] = List[Float64](),
        band_colors: List[Color] = List[Color](),
    ) raises:
        """Refused at compile time: this mark has no `encode_gauge()`."""
        comptime assert False, "encode_gauge(): not an encoder of this mark"

    def encode_parallel(
        mut self,
        mut settings: _ChartSettings,
        dims: List[String],
        row_names: List[String],
        data: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_parallel()`."""
        comptime assert False, "encode_parallel(): not an encoder of this mark"

    def encode_kde(
        mut self,
        mut settings: _ChartSettings,
        values: List[Float64],
    ) raises:
        """Refused at compile time: this mark has no `encode_kde()`."""
        comptime assert False, "encode_kde(): not an encoder of this mark"

    def encode_eventplot(
        mut self,
        mut settings: _ChartSettings,
        labels: List[String],
        positions: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_eventplot()`."""
        comptime assert False, "encode_eventplot(): not an encoder of this mark"

    def encode_distribution(
        mut self,
        mut settings: _ChartSettings,
        categories: List[String],
        values: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_distribution()`."""
        comptime assert (
            False
        ), "encode_distribution(): not an encoder of this mark"

    def encode_single_axis(
        mut self,
        mut settings: _ChartSettings,
        x: List[Float64],
        color: List[Float64] = List[Float64](),
        color_categories: List[String] = List[String](),
        size: List[Float64] = List[Float64](),
    ) raises:
        """Refused at compile time: this mark has no `encode_single_axis()`."""
        comptime assert (
            False
        ), "encode_single_axis(): not an encoder of this mark"

    def encode_imshow(
        mut self,
        mut settings: _ChartSettings,
        z: List[List[Float64]],
    ) raises:
        """Refused at compile time: this mark has no `encode_imshow()`."""
        comptime assert False, "encode_imshow(): not an encoder of this mark"

    def encode_frame(
        mut self,
        mut settings: _ChartSettings,
        df: DataFrame,
        x: String,
        y: String,
        color: String,
        size: String,
        labels: String,
    ) raises:
        """Refused at compile time: this mark reads no `DataFrame` by
        column name."""
        comptime assert False, "encode_frame(): not an encoder of this mark"


def _capabilities_of_type[M: MarkType]() -> _Capabilities:
    """`M`'s `supports_*` constants as one value."""
    var caps = _Capabilities()
    caps.tooltips = M.supports_tooltips
    caps.data_labels = M.supports_data_labels
    caps.horizontal = M.supports_horizontal
    caps.annotations_y = M.supports_annotations_y
    caps.annotations_x = M.supports_annotations_x
    caps.annotations_xy = M.supports_annotations_xy
    caps.log_x = M.supports_log_x
    caps.log_y = M.supports_log_y
    caps.color_size = M.supports_color_size
    return caps
