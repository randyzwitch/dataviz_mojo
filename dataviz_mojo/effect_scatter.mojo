from canvas_mojo.buffer import Canvas

from dataviz_mojo.plot import Plot, _rendered
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
) raises -> Canvas:
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
        width: Pixel width of the returned `Canvas`.
        height: Pixel height of the returned `Canvas`.
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The rendered chart -- call `.write_png(path)`/`.write_bmp(path)` (both `canvas_mojo.io`) to save it.
    """
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
