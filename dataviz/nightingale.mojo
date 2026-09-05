from std.math import pi, sqrt

from canvas.vector.draw_target import DrawTarget
from dataviz.plot import _LazyFontCache

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz.theme import Theme


def _render_nightingale[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """Render a `Mark.NIGHTINGALE` plot (a rose/coxcomb chart): one wedge per
    category (`encode_categorical`'s `x`), every wedge the same angular
    width (`2*pi / N`), with each value encoded by the wedge's radius
    rather than its angle.

    `plot._nightingale_area` (`Plot.mark_nightingale(area=True)`) picks
    between ECharts' two `rose_type` modes, both scaled against the
    largest value: `"radius"` (the default) sets radius to `value / max`;
    `"area"` uses `sqrt(value / max)` so wedge area, not radius, is
    proportional to value. Radius scaling visually exaggerates large
    values since area grows with the square of radius; area scaling
    corrects that at the cost of compressing small values near the center.

    Reuses `Mark.ARC`'s start-at-12-o'clock clockwise sweep, its
    non-negative/at-least-one-positive validation,
    `default_categorical_palette()` by category index, and the same
    margin-box/legend layout. No axis frame.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.NIGHTINGALE")
    var max_v = _require_some_positive(plot.y_data, "Mark.NIGHTINGALE")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend = _legend_layout(
        plot.x_categories,
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

    var palette = default_categorical_palette()
    var n = len(plot.x_categories)
    var span = 2.0 * pi / Float64(n)
    var start = -pi / 2.0
    for i in range(n):
        var end = start + span
        var frac = plot.y_data[i] / max_v
        var radius = max_radius * (
            sqrt(frac) if plot._nightingale_area else frac
        )
        var color = palette[i % len(palette)]
        target.fill_arc_aa(cx, cy, radius, start, end, color)
        start = end

    if show_legend:
        _draw_legend_at(
            target,
            text_requests,
            plot.x_categories,
            palette,
            legend,
            plot_x0,
            plot_y0,
            plot_x1,
            plot_y1,
            theme,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def nightingale(
    categories: List[String],
    values: List[Float64],
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
        from dataviz.plot import save

        def main() raises:
            var causes: List[String] = ["Zymotic disease", "Wounds", "Other"]
            var deaths: List[Int] = [1857, 202, 97]

            var c = nightingale(causes, deaths, area=True)
            save(c, "docs/src/examples/out_nightingale.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_nightingale(area=area)
        .encode_categorical(x=categories, y=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
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
    """`nightingale()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (plot.mojo). Delegates to the concrete
    overload above.
    """
    return nightingale(
        categories,
        _materialize_scalar_list(values),
        area=area,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
