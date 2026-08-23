from std.math import pi, sqrt

from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _rendered,
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz_mojo.theme import Theme


def _render_nightingale[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.NIGHTINGALE` plot (a rose/coxcomb chart): one
    wedge per category (`encode_categorical`'s `x`), every wedge the
    *same* angular width (`2*pi / N`) -- unlike `Mark.ARC`'s own
    value-proportional angle, a nightingale wedge's magnitude is
    always encoded by its radius instead, so categories stay easy to
    compare by eye (equal angular slots) while their values still read
    as a real visual magnitude, not just an angle.

    `Plot.mark_nightingale(area=True)`'s own `plot._nightingale_area`
    switches which of ECharts' two `rose_type` modes each wedge's own
    radius uses, both scaled against the *largest* value in the data
    (not the total the way `Mark.ARC`'s own angle is -- there's no
    "share of a whole" reading here, a nightingale answers "how big is
    each category," not "what fraction of the total is each category"):
    `"radius"` (the default) scales radius linearly by `value / max`;
    `"area"` scales by `sqrt(value / max)` instead, so a wedge's own
    *area* -- not just its radius -- is proportional to its value.
    Plain radius scaling alone visually exaggerates large values (a
    circle's area grows with the *square* of its radius), which
    `"area"` mode corrects for at the cost of compressing small values
    together near the center.

    Reuses `Mark.ARC`'s own start-at-12-o'clock, sweep-clockwise wedge
    convention (see `_render_arc`'s own docstring for why that's
    clockwise here) and its identical non-negative/at-least-one-
    positive value validation, `default_categorical_palette()` for
    wedge colors by category index, and the same margin-box/legend
    layout `_render_arc` uses. No axis frame at all -- the same "a
    circle has no x/y axes" reasoning `_render_arc` already documents
    -- so this is its own fully separate render path, not a branch
    inside `_render_arc` itself: the per-wedge angle/radius formula
    genuinely differs, not just a flag flip.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.NIGHTINGALE")
    var max_v = _require_some_positive(plot.y_data, "Mark.NIGHTINGALE")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(plot.x_categories, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9

    var palette = default_categorical_palette()
    var n = len(plot.x_categories)
    var span = 2.0 * pi / Float64(n)
    var start = -pi / 2.0
    for i in range(n):
        var end = start + span
        var frac = plot.y_data[i] / max_v
        var radius = max_radius * (sqrt(frac) if plot._nightingale_area else frac)
        var color = palette[i % len(palette)]
        target.fill_arc_aa(cx, cy, radius, start, end, color)
        start = end

    if show_legend:
        _draw_legend(
            target, text_requests, plot.x_categories, palette, plot_x1 + sc.margin_right, plot_y0, theme
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def nightingale(
    categories: List[String],
    values: List[Float64],
    area: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A rose/coxcomb chart -- `Mark.NIGHTINGALE` over a categorical
    `x` and continuous `y` (the same shape `pie()`/`bar()` take; every
    value must be non-negative, and at least one positive). Pass
    `area=True` for ECharts' `rose_type="area"` mode instead of the
    default `"radius"` mode -- see `_render_nightingale`'s own
    docstring for what each mode means."""
    var plot = Plot().mark_nightingale(area=area).encode_categorical(x=categories, y=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
