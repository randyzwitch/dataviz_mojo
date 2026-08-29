from canvas_mojo.buffer import Canvas

from dataviz_mojo.plot import Plot, _finished
from dataviz_mojo.theme import Theme


def effect_scatter(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A scatter plot with a halo drawn under each point -- `Mark.
    EFFECT_SCATTER` over continuous `x`/`y`, the static equivalent of
    ECharts' animated-ripple effect scatter. `Mark.POINT`'s `encode()` unchanged (`color`/`color_categories`/`size` channels
    included) -- use `Plot().mark_effect_scatter().encode(...)`
    directly for those, the same relationship `scatter()`'s minimal signature has to `Mark.POINT`'s full one.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
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
        from dataviz_mojo import effect_scatter
        from dataviz_mojo.plot import save
        from dataviz_mojo.theme import Theme

        def main() raises:
            var longitude: List[Float64] = [10.0, 25.0, 40.0, 60.0, 80.0]
            var latitude: List[Float64] = [15.0, 40.0, 20.0, 55.0, 30.0]

            var c = effect_scatter(longitude, latitude)
            save(c, "docs/src/examples/out_effect_scatter.svg")
        ```
    """
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
