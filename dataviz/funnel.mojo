from canvas.color import Color
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _finished,
    _validate_categorical_encoding,
    _require_non_negative,
)
from dataviz.theme import Theme


def _descending_value_order(values: List[Float64]) -> List[Int]:
    """`values`' indices, sorted largest-first -- a plain selection
    sort (values are always `Mark.BAR`-sized, a handful to a few dozen
    stages, never large enough to need anything better; the same "a
    simple O(n^2) scan over a small n" tolerance `_unique_categories`
    already has). Ties keep their original relative order (a stable
    sort, picking the first not-yet-placed index whenever two values
    are equal) -- not load-bearing for anything, just avoids an
    arbitrary-looking swap a caller with equal-valued stages might
    notice.
    """
    var n = len(values)
    var order = List[Int]()
    var used = List[Bool]()
    for _ in range(n):
        used.append(False)
    for _ in range(n):
        var best = -1
        for i in range(n):
            if not used[i] and (best == -1 or values[i] > values[best]):
                best = i
        order.append(best)
        used[best] = True
    return order^


def _fill_trapezoid[
    T: DrawTarget
](
    mut target: T,
    top_left: Float64,
    top_right: Float64,
    bottom_left: Float64,
    bottom_right: Float64,
    y0: Int,
    y1: Int,
    color: Color,
) raises:
    var path = Path()
    path.move_to(top_left, Float64(y0))
    path.line_to(top_right, Float64(y0))
    path.line_to(bottom_right, Float64(y1))
    path.line_to(bottom_left, Float64(y1))
    path.close()
    target.fill_path_aa(path, color)


def _render_funnel[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.FUNNEL` plot: `encode_categorical()`'s category+value shape (the same data `Mark.BAR`/`ARC` already take),
    drawn largest-value-first top to bottom (`_descending_value_order`
    -- matching ECharts' "highest to lowest" default, not left to
    the caller's row order the way every other categorical mark
    here is) as one trapezoid per row, no axis frame at all -- like
    `_render_arc`, a funnel's whole point is the taper, not a value
    read off an axis.

    Equal row heights spanning the whole plot rect; each row's top
    width is `value / largest_value` of the available width (so the
    largest stage always spans edge to edge) and its *bottom*
    width equals the *next* row's top width -- a continuous taper
    from stage to stage, the standard funnel look. The last row's bottom width matches its top (a flat bottom, not tapering to a
    point) -- there's no "next" value to taper into.

    Colors cycle `default_categorical_palette()` by *display row*
    (post-sort position), not original category index -- unlike `Mark.
    ARC`'s palette-by-category-index, a funnel's row order is
    itself data-dependent (`_descending_value_order`), so coloring by
    final position keeps row 0 always the same color across different
    inputs, the same "the picture reads the same way every time" reason
    the legend below is drawn in that same sorted order, not the
    caller's original one.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    _require_non_negative(plot.y_data, "Mark.FUNNEL")

    var order = _descending_value_order(plot.y_data)
    var n = len(order)
    var largest = plot.y_data[order[0]]
    if largest <= 0.0:
        raise Error("Plot: Mark.FUNNEL requires at least one positive value")

    var sc = _Scaled(theme)
    var sorted_categories = List[String]()
    for i in range(n):
        sorted_categories.append(plot.x_categories[order[i]])

    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(sorted_categories, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var max_width = Float64(plot_x1 - plot_x0)
    var row_height = Float64(plot_y1 - plot_y0) / Float64(n)

    var palette = default_categorical_palette()

    var top_width = List[Float64]()
    for i in range(n):
        top_width.append((plot.y_data[order[i]] / largest) * max_width)

    for i in range(n):
        var bottom_width = top_width[i + 1] if i < n - 1 else top_width[i]
        var y0 = plot_y0 + Int(Float64(i) * row_height)
        var y1 = plot_y0 + Int(Float64(i + 1) * row_height)
        _fill_trapezoid(
            target,
            cx - top_width[i] / 2.0,
            cx + top_width[i] / 2.0,
            cx - bottom_width / 2.0,
            cx + bottom_width / 2.0,
            y0,
            y1,
            palette[i % len(palette)],
        )

    var text_requests = List[_TextRequest]()
    if show_legend:
        _draw_legend(target, text_requests, sorted_categories, palette, plot_x1 + sc.margin_right, plot_y0, theme)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def funnel(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A funnel chart -- `Mark.FUNNEL` over a categorical `x` and
    continuous `y` (the same shape `bar()`/`pie()` take), drawn
    largest-value-first as tapering trapezoids. See `_render_funnel`'s docstring for the taper/ordering rules. `x_title`/`y_title` are
    accepted for signature consistency with every other quickplot here
    but have no axis to label, the same as `pie()`'s two.

    Args:
        categories: One trapezoid per entry -- drawn largest-value-
            first regardless of the given order.
        values: Each category's value; every value must be
            non-negative, and at least one positive.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: Unused -- a funnel chart has no x-axis to label.
        y_title: Unused -- a funnel chart has no y-axis to label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import funnel
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var stages: List[String] = ["Impressions", "Clicks", "Add to Cart", "Orders"]
            var counts: List[Int] = [10000, 3200, 950, 400]

            var c = funnel(stages, counts)
            save(c, "docs/src/examples/out_funnel.svg")
        ```
    """
    var plot = Plot().mark_funnel().encode_categorical(x=categories, y=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def funnel[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`funnel()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `funnel()` above.
    """
    return funnel(
        categories, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
