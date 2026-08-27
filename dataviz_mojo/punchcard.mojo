from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from canvas_mojo.text.font_cache import FontCache
from dataviz_mojo.heatmap import _draw_grid_axis_frame
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _categorical_indices,
    _empty_result,
    _rendered,
)
from dataviz_mojo.theme import Theme


struct _PunchcardData(Movable):
    """
    Mark.PUNCHCARD only -- one (x category, y category, bubble size) row
    per cell, plus the size->radius divisor. See encode_punchcard()'s docstring.

    Grouped onto `Plot._punchcard` -- see `Plot`'s docstring.
    """

    var x: List[String]
    var y: List[String]
    var sizes: List[Float64]
    var scale: Float64

    def __init__(out self):
        self.x = List[String]()
        self.y = List[String]()
        self.sizes = List[Float64]()
        self.scale = 0.0



def _render_punchcard[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.PUNCHCARD` plot: `encode_punchcard()`'s `x`/
    `y` categorical grid (`Mark.HEATMAP`'s `_draw_grid_axis_frame`
    and `_categorical_indices` domain derivation, both reused
    unchanged) with one bubble per row instead of `HEATMAP`'s filled cell -- a "scatter plot on a categorical grid" (ECharts.jl's description), the third-variable magnitude read from bubble
    *size*, not color, unlike every other grid mark in this package.

    Bubble radius is `sizes[i] / scale` -- a plain pixel-space divisor
    (`Plot.mark_punchcard(scale=10.0)`'s default, matching
    ECharts.jl's `scale` keyword exactly), *not* normalized
    against the cell's dimensions the way `Mark.CORRPLOT`'s bubble sizing is: a punchcard's bubbles are meant to visually
    overflow a small cell when the underlying count is large (real
    activity-heatmap data commonly does), which is the whole point of
    reading magnitude from raw size rather than a bounded fraction.
    Still multiplied by `frame.sc.scale` (`_Scaled`'s bare
    multiplier -- see that struct's docstring) before use: unlike
    `Mark.CORRPLOT`'s radius (derived from `frame.x_scale`/`y_
    scale`'s already-scaled pixel ranges, so it tracks `Theme.
    scale` for free), this one starts from a caller-given raw number
    with no relationship to the plot's pixel space at all -- without
    this multiplication, the radius would render too small whenever
    `Theme.scale` is anything other than its default (the raster
    quickplot path's internal supersampling boosts it beyond 1.0, so
    this is a real, reachable case, not just a defensive multiply).

    Multiple rows may share the same `(x, y)` cell -- each still draws
    its independent bubble (not summed into one), the same
    "multiple bubbles can occupy the same grid intersection" behavior
    ECharts.jl's `punchcard()` documents.

    No legend -- there's no categorical color channel to key one by
    (size is continuous and read directly off each bubble itself, the
    same reason `Mark.POLAR`'s single series draws none), matching
    ECharts.jl's `legend=false` default for this chart type too.
    """
    if (
        len(plot._punchcard.x) != len(plot._punchcard.y)
        or len(plot._punchcard.sizes) != len(plot._punchcard.x)
    ):
        raise Error(
            "Plot.encode_punchcard(): x, y, and sizes must all have the same"
            " length (got "
            + String(len(plot._punchcard.x))
            + " x values, "
            + String(len(plot._punchcard.y))
            + " y values, "
            + String(len(plot._punchcard.sizes))
            + " sizes)"
        )

    var theme = plot._theme
    if len(plot._punchcard.x) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for s in plot._punchcard.sizes:
        if s < 0.0:
            raise Error("Plot: Mark.PUNCHCARD sizes must be non-negative (got " + String(s) + ")")

    var x_idx = _categorical_indices(plot._punchcard.x)
    var y_idx = _categorical_indices(plot._punchcard.y)

    var measure_cache = FontCache()
    var frame = _draw_grid_axis_frame(
        target, x_idx.domain, y_idx.domain, theme, ox0, oy0, ox1, oy1, cache=measure_cache
    )

    for i in range(len(plot._punchcard.x)):
        var cx = _round_to_int(frame.x_scale.center(x_idx.indices[i]))
        var cy = _round_to_int(frame.y_scale.center(y_idx.indices[i]))
        var radius = _round_to_int(plot._punchcard.sizes[i] / plot._punchcard.scale * frame.sc.scale)
        target.fill_circle_aa(cx, cy, radius, theme.mark_color)

    return frame.result()


def punchcard(
    x: List[String],
    y: List[String],
    sizes: List[Float64],
    scale: Float64 = 10.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A punchcard -- `Mark.PUNCHCARD`, a scatter plot on a categorical
    grid where bubble size (`sizes[i] / scale`) encodes a third
    variable, GitHub-style. See `_render_punchcard`'s docstring for
    the full reasoning.

    Args:
        x: Each bubble's column category, one entry per row of data.
        y: Each bubble's row category, one entry per row of data.
        sizes: Each bubble's raw size value, divided by `scale`
            before drawing.
        scale: Divides `sizes` before drawing -- raise it to shrink
            bubbles that would otherwise overlap.
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
    var plot = Plot().mark_punchcard(scale=scale).encode_punchcard(x=x, y=y, sizes=sizes)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
