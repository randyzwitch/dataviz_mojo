from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _Orientation,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _finished,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


def _beeswarm_offsets(y_pixels: List[Int], spacing: Int) -> List[Int]:
    """One x-offset per entry of `y_pixels` (same order in, same order
    out), spreading points that would otherwise overlap vertically out
    sideways -- the simplest real swarm layout: points within `spacing`
    pixels of their neighbor (sorted by `y_pixels`) join one
    "row," each row's points alternate `0, +spacing, -spacing,
    +2*spacing, -2*spacing, ...` outward from center in the order they
    fall into that row. Not a full physics-style swarm (which would
    consider every nearby point continuously, not just a chain of
    consecutive sorted neighbors) -- this is deterministic and cheap,
    which matters more here: a real swarm's point positions depend
    on placement order in ways that are hard to predict by hand, and
    this package's whole test methodology depends on hand-derivable
    output (see the wiki).

    O(n log n) overall: one sort of the point indices, then a single
    linear pass assigning each row's alternating offsets.

    A row never checks whether its alternating spread actually fits
    inside a category's band width -- not clipped here, a caller
    with an unusually dense category may see a swarm wider than its column. A real, documented scope limit, not an oversight.
    """
    var n = len(y_pixels)
    var order = List[Int](capacity=n)
    for i in range(n):
        order.append(i)

    # Ascending by pixel row, ties broken by the point's own original
    # index -- a total order over `order`'s entries, so the result is
    # identical whether or not the underlying sort is stable. That tie
    # rule is not cosmetic: it's what decides which of two points
    # sharing a pixel row gets the `0` offset and which gets pushed
    # `+spacing` sideways, so changing it would move real pixels and
    # break this file's hand-derived tests.
    @parameter
    def _before(a: Int, b: Int) -> Bool:
        if y_pixels[a] != y_pixels[b]:
            return y_pixels[a] < y_pixels[b]
        return a < b

    sort[_before](order)

    var offset = List[Int]()
    for _ in range(n):
        offset.append(0)

    var row_start = 0
    for i in range(1, n + 1):
        if i == n or (y_pixels[order[i]] - y_pixels[order[i - 1]]) > spacing:
            for k in range(i - row_start):
                var idx = order[row_start + k]
                if k == 0:
                    offset[idx] = 0
                else:
                    var m = (k + 1) // 2
                    offset[idx] = m * spacing if k % 2 == 1 else -m * spacing
            row_start = i

    return offset^


def _distribution_domain(plot: Plot) raises -> LinearScale:
    """The value-axis domain over every value across every category --
    orientation-independent, and the same choice `Mark.BOX` makes for
    this data shape."""
    var all_values = List[Float64]()
    for series in plot._distribution.values:
        for v in series:
            all_values.append(v)
    return _data_extent(all_values)


def _draw_beeswarm_points[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    orient: _Orientation,
    radius: Int,
) raises:
    """Every category's points, spread sideways within its band so
    overlapping values stay individually visible -- written once for
    both orientations, with `_Orientation.band_point` carrying the only
    difference.

    `_beeswarm_offsets` itself is orientation-agnostic already: it
    takes pixel positions along the *value* axis and returns offsets
    along the *band* axis, which is true whichever way those map onto
    x/y. Spacing is one point diameter, so neighbours in the same row
    just touch.
    """
    var theme = plot._theme
    var spacing = 2 * radius
    for i in range(len(plot.x_categories)):
        var center = _round_to_int(band_scale.center(i))
        var value_pixels = List[Int]()
        for v in plot._distribution.values[i]:
            value_pixels.append(_axis_pixel(value_scale, v))
        var offsets = _beeswarm_offsets(value_pixels, spacing)
        for j in range(len(value_pixels)):
            orient.band_point(
                target, value_pixels[j], center + offsets[j], radius, theme.mark_color
            )


def _render_beeswarm[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.BEESWARM` plot: `encode_distribution()`'s per-category raw values, one point per value, jittered sideways
    within its category's band via `_beeswarm_offsets` so points
    at similar values don't sit directly on top of each other -- the
    same "see every individual point, not a summary" reading `Mark.
    BOX` gives up in exchange for its five-number-summary shape.

    Reuses `_draw_categorical_axis_frame` (the same vertical-
    categorical-x/continuous-y core `Mark.BAR`/`BOX`/... share), with
    `_data_extent` (not `_zero_baseline_y_extent`) over every value
    across every category: this data encodes where something falls
    within a range, not magnitude from a baseline, the same reasoning
    `Mark.BOX` uses for its shape.
    """
    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var value_scale = _distribution_domain(plot)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, value_scale, theme, ox0, oy0, ox1, oy1)

    var sc = _Scaled(theme)
    _draw_beeswarm_points(
        target, plot, frame.x_scale, frame.y_scale, _Orientation(False), _round_to_int(sc.point_radius)
    )

    return frame.result()


def _render_horizontal_beeswarm[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """`_render_beeswarm`'s mirror image for `Plot.mark_beeswarm(
    horizontal=True)` (#121) -- exactly `_render_horizontal_bar`'s own
    categorical y-axis / continuous x-axis (`_draw_horizontal_
    categorical_axis_frame`, gantt.mojo, shared -- see that function's
    docstring), with each category's raw values placed along the
    continuous `x_scale` and jittered *vertically* within their own
    row via `_beeswarm_offsets` instead of horizontally within their
    own column -- `_beeswarm_offsets` itself is unchanged, since it
    only ever reasons about one continuous pixel axis (the one values
    are placed along) and one perpendicular jitter axis, never which
    is which.

    Deliberately its own function, not an orientation flag threaded
    through `_render_beeswarm` -- see `_render_horizontal_bar`'s own
    docstring (bar.mojo) for the full reasoning, identical here.
    """
    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var value_scale = _distribution_domain(plot)

    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, value_scale, theme, ox0, oy0, ox1, oy1
    )

    var sc = _Scaled(theme)
    _draw_beeswarm_points(
        target, plot, frame.y_scale, frame.x_scale, _Orientation(True), _round_to_int(sc.point_radius)
    )

    return frame.result()


def beeswarm(
    categories: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """A beeswarm plot -- `Mark.BEESWARM`, one point per raw value,
    jittered sideways to avoid overlap, one swarm per category. See
    `Plot.encode_distribution()`'s docstring (plot.mojo) for the
    exact shape (the same one `violin()`/`ridgeline()` take).

    Args:
        categories: One swarm per entry, in the given order.
        values: Each category's raw values (`values[i]`, not a
            summary statistic) -- one point drawn per value.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.
        horizontal: Draw categories running top-to-bottom with each
            swarm jittered vertically within its own row instead of
            the default vertical layout -- see `Plot.mark_beeswarm()`'s
            own docstring (#121).

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import beeswarm
        from dataviz.plot import save

        def main() raises:
            var classes: List[String] = ["Section A", "Section B", "Section C"]
            var scores: List[List[Int]] = [
                [72, 75, 78, 80, 74, 76, 91],
                [65, 70, 72, 88, 90, 92, 95],
                [80, 82, 83, 84, 81, 79, 85],
            ]

            var c = beeswarm(classes, scores)
            save(c, "docs/src/examples/out_beeswarm.svg")
        ```
    """
    var plot = Plot().mark_beeswarm(horizontal=horizontal).encode_distribution(categories=categories, values=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def beeswarm[
    dtype: DType
](
    categories: List[String],
    values: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`beeswarm()`, generalized over numeric element type for
    `values` -- the nested-list counterpart to `scatter()`'s own
    `DType`-generic overload (plot.mojo), using `_materialize_nested_
    scalar_list` (array_like.mojo). Delegates to the concrete
    `beeswarm()` above.
    """
    return beeswarm(
        categories, _materialize_nested_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title, horizontal=horizontal,
    )
