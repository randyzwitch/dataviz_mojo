from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _rendered,
)
from dataviz_mojo.theme import Theme


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

    A row never checks whether its alternating spread actually fits
    inside a category's band width -- not clipped here, a caller
    with an unusually dense category may see a swarm wider than its column. A real, documented v1 scope limit, not an oversight.
    """
    var n = len(y_pixels)
    var order = List[Int]()
    var used = List[Bool]()
    for _ in range(n):
        used.append(False)
    for _ in range(n):
        var best = -1
        for i in range(n):
            if not used[i] and (best == -1 or y_pixels[i] < y_pixels[best]):
                best = i
        order.append(best)
        used[best] = True

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
    across every category -- the same "encodes where something falls
    within a range, not magnitude from a baseline" reasoning `Mark.BOX`
    already established for exactly this data shape.
    """
    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var all_values = List[Float64]()
    for series in plot._distribution.values:
        for v in series:
            all_values.append(v)
    var y_scale = _data_extent(all_values)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var sc = _Scaled(theme)
    var radius = _round_to_int(sc.point_radius)
    var spacing = 2 * radius

    for i in range(len(plot.x_categories)):
        var center_x = _round_to_int(frame.x_scale.center(i))
        var y_pixels = List[Int]()
        for v in plot._distribution.values[i]:
            y_pixels.append(_axis_pixel(frame.y_scale, v))
        var offsets = _beeswarm_offsets(y_pixels, spacing)
        for j in range(len(y_pixels)):
            target.fill_circle_aa(center_x + offsets[j], y_pixels[j], radius, theme.mark_color)

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
) raises -> Canvas:
    """A beeswarm plot -- `Mark.BEESWARM`, one point per raw value,
    jittered sideways to avoid overlap, one swarm per category. See
    `Plot.encode_distribution()`'s docstring (plot.mojo) for the
    exact shape (the same one `violin()`/`ridgeline()` take)."""
    var plot = Plot().mark_beeswarm().encode_distribution(categories=categories, values=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
