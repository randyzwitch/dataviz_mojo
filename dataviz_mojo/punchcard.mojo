from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

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


def _render_punchcard[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.PUNCHCARD` plot: `encode_punchcard()`'s own `x`/
    `y` categorical grid (`Mark.HEATMAP`'s own `_draw_grid_axis_frame`
    and `_categorical_indices` domain derivation, both reused
    unchanged) with one bubble per row instead of `HEATMAP`'s own
    filled cell -- a "scatter plot on a categorical grid" (ECharts.jl's
    own description), the third-variable magnitude read from bubble
    *size*, not color, unlike every other grid mark in this package.

    Bubble radius is `sizes[i] / scale` -- a plain pixel-space divisor
    (`Plot.mark_punchcard(scale=10.0)`'s own default, matching
    ECharts.jl's own `scale` keyword exactly), *not* normalized
    against the cell's own dimensions the way `Mark.CORRPLOT`'s own
    bubble sizing is: a punchcard's own bubbles are meant to visually
    overflow a small cell when the underlying count is large (real
    activity-heatmap data commonly does), which is the whole point of
    reading magnitude from raw size rather than a bounded fraction.
    Still multiplied by `frame.sc.scale` (`_Scaled`'s own bare
    multiplier -- see that struct's own docstring) before use: unlike
    `Mark.CORRPLOT`'s own radius (derived from `frame.x_scale`/`y_
    scale`'s own already-scaled pixel ranges, so it tracks `Theme.
    scale` for free), this one starts from a caller-given raw number
    with no relationship to the plot's own pixel space at all -- a
    real bug this shipped with initially: an un-scaled radius rendered
    correctly at the SVG backend (no supersampling to interact with)
    but visibly too small through the raster quickplot path (which
    supersamples via a boosted internal `Theme.scale`, then
    downsamples), caught by checking a bubble's own edge pixel, not
    just its solid center.

    Multiple rows may share the same `(x, y)` cell -- each still draws
    its own independent bubble (not summed into one), the same
    "multiple bubbles can occupy the same grid intersection" behavior
    ECharts.jl's own `punchcard()` documents.

    No legend -- there's no categorical color channel to key one by
    (size is continuous and read directly off each bubble itself, the
    same reason `Mark.POLAR`'s own single series draws none), matching
    ECharts.jl's own `legend=false` default for this chart type too.
    """
    if (
        len(plot._punchcard_x) != len(plot._punchcard_y)
        or len(plot._punchcard_sizes) != len(plot._punchcard_x)
    ):
        raise Error(
            "Plot.encode_punchcard(): x, y, and sizes must all have the same"
            " length (got "
            + String(len(plot._punchcard_x))
            + " x values, "
            + String(len(plot._punchcard_y))
            + " y values, "
            + String(len(plot._punchcard_sizes))
            + " sizes)"
        )

    var theme = plot._theme
    if len(plot._punchcard_x) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for s in plot._punchcard_sizes:
        if s < 0.0:
            raise Error("Plot: Mark.PUNCHCARD sizes must be non-negative (got " + String(s) + ")")

    var x_idx = _categorical_indices(plot._punchcard_x)
    var y_idx = _categorical_indices(plot._punchcard_y)

    var frame = _draw_grid_axis_frame(target, x_idx.domain, y_idx.domain, theme, ox0, oy0, ox1, oy1)

    for i in range(len(plot._punchcard_x)):
        var cx = _round_to_int(frame.x_scale.center(x_idx.indices[i]))
        var cy = _round_to_int(frame.y_scale.center(y_idx.indices[i]))
        var radius = _round_to_int(plot._punchcard_sizes[i] / plot._punchcard_scale * frame.sc.scale)
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
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A punchcard -- `Mark.PUNCHCARD`, a scatter plot on a categorical
    grid where bubble size (`sizes[i] / scale`) encodes a third
    variable, GitHub-style. See `_render_punchcard`'s own docstring for
    the full reasoning."""
    var plot = Plot().mark_punchcard(scale=scale).encode_punchcard(x=x, y=y, sizes=sizes)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
