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
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A scatter plot with a halo drawn under each point -- `Mark.
    EFFECT_SCATTER` over continuous `x`/`y`, the static equivalent of
    ECharts' own animated-ripple effect scatter. `Mark.POINT`'s own
    `encode()` unchanged (`color`/`color_categories`/`size` channels
    included) -- use `Plot().mark_effect_scatter().encode(...)`
    directly for those, the same relationship `scatter()`'s own
    minimal signature already has to `Mark.POINT`'s full one."""
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
