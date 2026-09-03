from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from canvas.text.font_cache import FontCache
from dataviz.array_like import _materialize_scalar_list
from dataviz.heatmap import _draw_grid_axis_frame
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _categorical_indices,
    _empty_result,
    _finished,
)
from dataviz.theme import Theme


struct _PunchcardData(Movable):
    """One (x category, y category, bubble size) row per cell, plus the
    size-to-radius divisor, for `Mark.PUNCHCARD`. See
    `encode_punchcard()`. Stored on `Plot._punchcard`.
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
    """Render a `Mark.PUNCHCARD` plot: `encode_punchcard()`'s `x`/`y`
    categorical grid (`Mark.HEATMAP`'s `_draw_grid_axis_frame` and
    `_categorical_indices` domain derivation, reused unchanged) with one
    bubble per row instead of a filled cell, magnitude read from bubble
    size rather than color.

    Bubble radius is `sizes[i] / scale` (`Plot.mark_punchcard(scale=10.0)`
    's default, matching ECharts.jl's `scale` keyword), a plain
    pixel-space divisor not normalized against the cell the way
    `Mark.CORRPLOT`'s bubbles are, so large counts can overflow a small
    cell. Multiplied by `frame.sc.scale` so the radius tracks
    `Theme.scale` (a HiDPI export) like every other pixel quantity.

    Multiple rows may share the same `(x, y)` cell; each draws its own
    bubble. No legend: size is read directly off each bubble.
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
) raises -> Plot:
    """A punchcard.

    `Mark.PUNCHCARD`: a scatter plot on a categorical grid where bubble
    size (`sizes[i] / scale`) encodes a third variable, GitHub-style. See
    `_render_punchcard`.

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
        from dataviz import punchcard
        from dataviz.plot import save

        def main() raises:
            var days: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            var hours: List[String] = ["9am", "12pm", "3pm", "6pm", "9pm"]

            var x = List[String]()
            var y = List[String]()
            var counts = List[Int]()
            for day_i in range(len(days)):
                var is_weekend = day_i >= 5
                for hour in hours:
                    x.append(days[day_i])
                    y.append(hour)
                    counts.append(15 if is_weekend else 60)

            var c = punchcard(x, y, counts)
            save(c, "docs/src/examples/out_punchcard.svg")
        ```
    """
    var plot = Plot().mark_punchcard(scale=scale).encode_punchcard(x=x, y=y, sizes=sizes)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def punchcard[
    dtype: DType
](
    x: List[String],
    y: List[String],
    sizes: List[Scalar[dtype]],
    scale: Float64 = 10.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`punchcard()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return punchcard(
        x, y, _materialize_scalar_list(sizes), scale=scale, theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
