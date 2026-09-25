from dataviz.core.plot_fields import (
    _CategoricalData,
    _ContinuousData,
    _ErrorBarData,
)
from dataviz.core.chart_settings import _ChartSettings
from std.math import pi, sqrt

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.mark import Mark
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.tooltip_labels import _tooltip_label
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.legend import _LegendLayout, _draw_legend_at, _legend_layout
from dataviz.core.validate import (
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz.core.scale import _format_tick, _label_decimals
from dataviz.radial.polar import _radial_value_label
from dataviz.core.theme import Theme


struct _NightingaleData(Copyable, Movable):
    """Which of ECharts' two `rose_type` radius formulas each wedge of a
    `Mark.NIGHTINGALE` uses. See `mark_nightingale()`. Stored on
    `Plot._nightingale`.

    The wedge values themselves are `_categorical.x`/`_continuous.y`, shared with
    the other categorical marks, so this struct holds only the setting.
    """

    var area: Bool
    """False scales a wedge's radius by `value / max` ("radius"); True
    scales its area instead, `sqrt(value / max)` ("area")."""

    def __init__(out self):
        self.area = False


def _render_nightingale[
    T: DrawTarget
](
    mut target: T,
    mark: Mark,
    nightingale: _NightingaleData,
    continuous: _ContinuousData,
    categorical: _CategoricalData,
    y_err: _ErrorBarData,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render equal-angle wedges whose radii encode non-negative values.

    Radius mode scales directly by value; area mode uses the square root so
    wedge area is proportional to value. Wedges begin at 12 o'clock.
    """
    _validate_categorical_encoding(categorical, continuous, y_err, mark)

    var theme = settings.theme
    var text_requests = List[_TextRequest]()

    _require_non_negative(continuous.y, "Mark.NIGHTINGALE")
    var max_v = _require_some_positive(continuous.y, "Mark.NIGHTINGALE")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend = _legend_layout(
        categorical.x,
        sc.legend_swatch_size,
        sc,
        theme,
        ox1 - ox0,
        cache=cache,
    ) if show_legend else _LegendLayout()

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )

    var palette = categorical_palette_for(theme)
    var n = len(categorical.x)
    var span = 2.0 * pi / Float64(n)
    var start = -pi / 2.0
    var tooltips_on = settings.tooltips_on(n)
    for i in range(n):
        var end = start + span
        var frac = continuous.y[i] / max_v
        var radius = max_radius * (sqrt(frac) if nightingale.area else frac)
        var color = palette[i % len(palette)]
        if tooltips_on:
            target.begin_annotated_group(
                _tooltip_label(categorical.x[i], continuous.y[i])
            )
        target.fill_arc_aa(cx, cy, radius, start, end, color)
        if tooltips_on:
            target.end_annotated_group()
        if theme.show_data_labels:
            _radial_value_label(
                cx,
                cy,
                (start + end) / 2.0,
                radius,
                continuous.y[i],
                theme,
                sc,
                text_requests,
            )
        start = end

    if show_legend:
        _draw_legend_at(
            target,
            text_requests,
            categorical.x,
            palette,
            legend,
            plot_x0,
            plot_y0,
            plot_x1,
            plot_y1,
            theme,
            cache=cache,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def _render_nightingale_plot[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """`_render_nightingale` on `plot`'s own columns and settings: the callback
    its `mark_*()` setter binds. This is the one place the mark's
    renderer meets a `Plot` (#826)."""
    return _render_nightingale(
        target,
        plot._mark,
        plot._nightingale,
        plot._continuous,
        plot._categorical,
        plot._y_err,
        plot._settings,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )


def nightingale(
    df: DataFrame,
    categories: String,
    values: String,
    area: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`nightingale()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values. The axis titles default to the `categories` and `values` column names.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: The string column for this channel.
        values: The numeric column for this channel.
        area: See the list overload.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.
        y_title: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var categories_values = _frame_strings(
        df,
        categories,
        "nightingale()",
        theme.missing,
        theme.missing_category_label,
    )
    var values_values = _frame_floats(
        df, values, "nightingale()", theme.missing
    )
    return nightingale(
        categories=categories_values,
        values=values_values,
        area=area,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else categories,
        y_title=y_title if y_title.byte_length() > 0 else values,
    )


def nightingale[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    area: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A rose/coxcomb chart, the polar-area format Florence Nightingale
    used in 1858 to show causes of mortality: wedges of equal angle but
    value-proportional radius, giving a categorical comparison a
    circular form.

    `Mark.NIGHTINGALE` over a categorical `x` and continuous `y` (the same
    shape `pie()`/`bar()` take; values must be non-negative, with at least
    one positive). Pass `area=True` for ECharts' `rose_type="area"` mode
    instead of the default `"radius"` mode; see `_render_nightingale` for
    what each means.

    Args:
        categories: One wedge per entry, in the given order.
        values: Each wedge's value; every value must be non-negative,
            and at least one positive.
        area: `False` (the default) scales each wedge's *radius* by
            `value`; `True` scales its *area* instead (ECharts'
            `rose_type="area"`).
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import nightingale
        from dataviz import save

        def main() raises:
            var months: List[String] = [
                "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
            ]
            # Illustrative monthly bicycle trips, in thousands.
            var trips: List[Int] = [18, 22, 35, 51, 68, 79, 84, 81, 65, 47, 29, 20]

            var c = nightingale(
                months,
                trips,
                area=True,
                title="Illustrative Monthly Bicycle Trips (thousands)",
            )
            save(c, "docs/src/examples/out_nightingale.svg")
        ```
    """
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_nightingale(area=area)
        .encode_categorical(x=categories, y=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
