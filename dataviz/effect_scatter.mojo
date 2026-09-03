from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.theme import Theme


def effect_scatter(
    x: List[Float64],
    y: List[Float64],
    tooltips: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A scatter plot with a halo drawn under each point.

    `Mark.EFFECT_SCATTER` over continuous `x`/`y`, the static equivalent
    of ECharts' effect scatter. Accepts the same `encode()` channels as
    `Mark.POINT` (`color`/`color_categories`/`size`); use
    `Plot().mark_effect_scatter(tooltips=tooltips).encode(...)` directly
    for those.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
        tooltips: Whether each point carries an SVG `<title>` a browser
            shows on hover; defaults to `False`. Off by default because
            a title costs roughly as much as the point element itself,
            so a dense scatter's SVG about doubles -- see
            `Plot.mark_point()`'s own `tooltips` parameter.
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
        from dataviz import effect_scatter
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var longitude: List[Int] = [10, 25, 40, 60, 80]
            var latitude: List[Int] = [15, 40, 20, 55, 30]

            var c = effect_scatter(longitude, latitude)
            save(c, "docs/src/examples/out_effect_scatter.svg")
        ```
    """
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def effect_scatter[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    tooltips: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`effect_scatter()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (plot.mojo). Delegates to the concrete
    overload above.
    """
    return effect_scatter(
        _materialize_scalar_list(x), _materialize_scalar_list(y), tooltips=tooltips, theme=theme, width=width,
        height=height, title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
