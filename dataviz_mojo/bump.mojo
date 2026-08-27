from canvas_mojo.geometry import _round_to_int
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.funnel import _descending_value_order
from dataviz_mojo.grouped_bar import _validate_grouped_bar_series
from canvas_mojo.text.font_cache import FontCache
from dataviz_mojo.mark import Mark
from dataviz_mojo.ordinal_scale import OrdinalScale
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _build_line_path,
    _check_line_smoothing,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _max_label_width,
    _rendered,
)
from dataviz_mojo.theme import Theme


def _bump_rank_pixel(rank: Int, n_series: Int, py0: Int, py1: Int) -> Int:
    """Rank 1 (best) at `py0` (the plot area's top), rank
    `n_series` (worst) at `py1` (the bottom), evenly spaced in between
    -- not a `LinearScale`: a reversed-domain `LinearScale` doesn't
    work here, since `ticks()` assumes `domain_min < domain_max`.
    `n_series == 1` (nothing to
    rank against) is the one degenerate case, floored to the plot
    area's vertical center rather than dividing by zero.
    """
    if n_series <= 1:
        return (py0 + py1) // 2
    return py0 + _round_to_int(Float64(rank - 1) / Float64(n_series - 1) * Float64(py1 - py0))


struct _BumpFrame(Movable):
    """`_draw_bump_axis_frame`'s finished layout: a categorical `x`
    (`OrdinalScale`, the same as every other vertical-categorical mark
    here) and an integer rank `y` -- `1`..`n_series`, rank 1 at the
    top -- with no `LinearScale` backing it at all (see `_bump_rank_
    pixel`'s docstring)."""

    var x_scale: OrdinalScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int
    var n_series: Int

    def __init__(
        out self,
        var x_scale: OrdinalScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
        n_series: Int,
    ):
        self.x_scale = x_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1
        self.n_series = n_series

    def result(self) -> _RenderResult:
        return _RenderResult(self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1)


def _draw_bump_axis_frame[
    T: DrawTarget
](
    mut target: T,
    categories: List[String],
    n_series: Int,
    theme: Theme,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _BumpFrame:
    """`Mark.BUMP`'s axis frame: `_draw_categorical_axis_frame`'s
    familiar vertical-categorical-`x`-plus-continuous-`y` shape, but the
    `y` side is hand-rolled instead of a real `LinearScale` -- rank 1
    has to land at the *top* of the plot area, and every other
    categorical mark's y-axis gets that "larger value is higher"
    reading by feeding `LinearScale.ticks()` a domain where `domain_min
    < domain_max` and letting the frame's range-reversal handle the
    rest. A rank axis needs the opposite mapping (small number = top),
    and simply swapping `domain_min`/`domain_max` to get that breaks
    `ticks()`, which assumes an increasing domain throughout (`_nice_
    step`'s step/log10 math goes through a negative span).
    Since a rank axis only ever needs exactly `n_series` integer ticks
    (never `LinearScale.ticks()`'s "nice round numbers" treatment),
    hand-rolling one tick per rank via `_bump_rank_pixel` sidesteps the
    whole problem rather than working around it.
    """
    var sc = _Scaled(theme)

    var rank_labels = List[String]()
    for r in range(1, n_series + 1):
        rank_labels.append(String(r))
    var dynamic_left_margin = (
        Int(_max_label_width(rank_labels, sc.font_size, cache=cache)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var x_scale = OrdinalScale(categories.copy(), Float64(plot_x0), Float64(plot_x1))

    if theme.show_gridlines:
        for r in range(1, n_series + 1):
            var py = _bump_rank_pixel(r, n_series, plot_y0, plot_y1)
            target.draw_line_aa(plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale)

    target.draw_line_aa(plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale)
    target.draw_line_aa(plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale)

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for r in range(1, n_series + 1):
        var py = _bump_rank_pixel(r, n_series, plot_y0, plot_y1)
        target.draw_line_aa(plot_x0 - sc.tick_length, py, plot_x0, py, theme.axis_color, width=sc.scale)
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                py + y_label_baseline_offset,
                String(r),
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )

    for i in range(len(categories)):
        var center_px = _round_to_int(x_scale.center(i))
        target.draw_line_aa(center_px, plot_y1, center_px, plot_y1 + sc.tick_length, theme.axis_color, width=sc.scale)
        text_requests.append(
            _TextRequest(
                center_px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                categories[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    return _BumpFrame(x_scale^, sc^, text_requests^, plot_x0, plot_y0, plot_x1, plot_y1, n_series)


def _render_bump[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.BUMP` plot: `encode_grouped_bar()`'s data,
    unchanged (categories, one name and one value per series) -- but
    each series' *rank* among every series at that same category
    (`_descending_value_order`, one sort per category, reused from
    funnel.mojo) is what gets plotted, not its raw value, one line per
    series (`_build_line_path`, the same `Theme.line_smoothing`-aware
    path builder `Mark.LINE` itself uses) connecting that series' rank position at each category in turn.

    Ranks are precomputed for every (series, category) pair in one pass
    before any line is drawn (one sort per category, not one per (series,
    category) pair) -- see the loop's comment.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0 or len(plot._grouped_bar.series_names) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    _check_line_smoothing(theme)

    var n_series = len(plot._grouped_bar.series_names)
    var n_categories = len(plot.x_categories)

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend

    # One FontCache for both measurements -- the legend's series names
    # here, then the rank-axis labels inside _draw_bump_axis_frame.
    var measure_cache = FontCache()

    var legend_reserve = (
        _dynamic_legend_width(
            plot._grouped_bar.series_names, sc.legend_swatch_size, sc, cache=measure_cache
        )
        if show_legend
        else 0
    )

    var frame = _draw_bump_axis_frame(
        target, plot.x_categories, n_series, theme, ox0, oy0, ox1 - legend_reserve, oy1,
        cache=measure_cache
    )

    # rank[j][i]: series j's rank (1 = highest value) at category i.
    var rank = List[List[Int]]()
    for _ in range(n_series):
        rank.append(List[Int]())
    for i in range(n_categories):
        var values_at_i = List[Float64]()
        for j in range(n_series):
            values_at_i.append(plot._grouped_bar.values[j][i])
        var order = _descending_value_order(values_at_i)
        var rank_at_i = List[Int]()
        for _ in range(n_series):
            rank_at_i.append(0)
        for pos in range(n_series):
            rank_at_i[order[pos]] = pos + 1
        for j in range(n_series):
            rank[j].append(rank_at_i[j])

    var palette = default_categorical_palette()
    for j in range(n_series):
        var px = List[Float64](capacity=n_categories)
        var py = List[Float64](capacity=n_categories)
        for i in range(n_categories):
            px.append(frame.x_scale.center(i))
            py.append(Float64(_bump_rank_pixel(rank[j][i], n_series, frame.py0, frame.py1)))
        var path = _build_line_path(px, py, theme.line_smoothing)
        target.stroke_path_aa(path, palette[j % len(palette)], width=sc.line_width)

    if show_legend:
        _draw_legend(
            target, frame.text_requests, plot._grouped_bar.series_names, palette,
            frame.px1 + sc.margin_right, frame.py0, theme,
        )

    return frame.result()


def bump(
    categories: List[String],
    series_names: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
) raises -> Canvas:
    """A bump chart -- `Mark.BUMP`, one line per series tracking its *rank* (1 = highest value) among every series at each category, not
    its raw value. Same data shape `grouped_bar()`/`stacked_bar()` take
    (`values[j]` is series `series_names[j]`'s value per category)."""
    var plot = Plot().mark_bump().encode_grouped_bar(
        categories=categories, series_names=series_names, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, "Rank", subtitle=subtitle)
