from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.heatmap import _draw_grid_axis_frame
from dataviz.core.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _categorical_indices,
    _finished,
    _require_non_empty,
)
from dataviz.core.theme import Theme


struct _PunchcardData(Copyable, Movable):
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
    """Render non-negative sizes as bubbles on a categorical grid.

    Radius is `size / scale` in theme-scaled pixels. Duplicate coordinates
    draw multiple bubbles, and large bubbles may exceed their cells.
    """
    if len(plot._punchcard.x) != len(plot._punchcard.y) or len(
        plot._punchcard.sizes
    ) != len(plot._punchcard.x):
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
    _require_non_empty(len(plot._punchcard.x), "Plot.encode_punchcard()")
    for s in plot._punchcard.sizes:
        if s < 0.0:
            raise Error(
                "Plot: Mark.PUNCHCARD sizes must be non-negative (got "
                + String(s)
                + ")"
            )

    var x_idx = _categorical_indices(plot._punchcard.x)
    var y_idx = _categorical_indices(plot._punchcard.y)

    var frame = _draw_grid_axis_frame(
        target,
        x_idx.domain,
        y_idx.domain,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    for i in range(len(plot._punchcard.x)):
        # Same rule as corrplot: a disk has no crisp position to snap
        # to, and the radius is the encoding -- rounding it to whole
        # pixels collapsed a continuous size scale into as many steps as
        # the largest punch is wide, so two counts a fifth apart could
        # draw the same circle.
        var cx = frame.x_scale.center(x_idx.indices[i])
        var cy = frame.y_scale.center(y_idx.indices[i])
        var radius = (
            plot._punchcard.sizes[i] / plot._punchcard.scale * frame.sc.scale
        )
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
    """A punchcard, in the style of GitHub's old commit-activity graph: a
    scatter plot on a categorical grid where bubble size encodes a value
    at each (x, y) cell, for spotting when activity clusters across two
    categorical dimensions such as day and hour.

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
        from dataviz import save

        def main() raises:
            var day_names: List[String] = [
                "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
            ]
            var hour_names: List[String] = [
                "6am", "9am", "12pm", "3pm", "6pm", "9pm",
            ]
            # Illustrative station entries (thousands): commute peaks dominate
            # weekdays, while weekend travel shifts toward midday and evening.
            var entries_by_day: List[List[Int]] = [
                [38, 72, 31, 35, 68, 24],
                [41, 78, 33, 37, 73, 25],
                [43, 81, 35, 39, 76, 27],
                [42, 79, 34, 38, 74, 28],
                [39, 70, 36, 42, 71, 39],
                [14, 25, 43, 51, 57, 45],
                [11, 21, 38, 47, 52, 34],
            ]

            var x = List[String]()
            var y = List[String]()
            var counts = List[Int]()
            for day_i in range(len(day_names)):
                for hour_i in range(len(hour_names)):
                    x.append(day_names[day_i])
                    y.append(hour_names[hour_i])
                    counts.append(entries_by_day[day_i][hour_i])

            var c = punchcard(
                x,
                y,
                counts,
                title="Illustrative Transit Entries by Day and Hour",
                x_title="Day",
                y_title="Hour",
            )
            save(c, "docs/src/examples/out_punchcard.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_punchcard(scale=scale)
        .encode_punchcard(x=x, y=y, sizes=sizes)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


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
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.
    """
    return punchcard(
        x,
        y,
        _materialize_scalar_list(sizes),
        scale=scale,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
