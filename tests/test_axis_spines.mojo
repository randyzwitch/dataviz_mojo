"""Tests for the axis spines (#346): the four `Theme.show_axis_*` flags
and `AxisPosition.ZERO`, asserted on exact SVG line endpoints."""

from std.testing import TestSuite, assert_equal, assert_true

from _test_helpers import _attr_values
from dataviz import AxisPosition, Theme, bar, rugplot, scatter
from dataviz.plot import Plot, render_svg


# Every chart here is 400x300 with gridlines off, so the plot rect is
# x:[60,380], y:[20,250] -- the rect every other pinned-pixel test in
# this suite uses.
comptime _X0 = 60
comptime _Y0 = 20
comptime _X1 = 380
comptime _Y1 = 250


def _theme(
    left: Bool = True,
    right: Bool = False,
    top: Bool = False,
    bottom: Bool = True,
    x_at: AxisPosition = AxisPosition.EDGE,
    y_at: AxisPosition = AxisPosition.EDGE,
) -> Theme:
    return Theme(
        show_gridlines=False,
        show_axis_left=left,
        show_axis_right=right,
        show_axis_top=top,
        show_axis_bottom=bottom,
        x_axis_position=x_at,
        y_axis_position=y_at,
    )


struct _Seg(Copyable, ImplicitlyCopyable, Movable):
    var x1: Int
    var y1: Int
    var x2: Int
    var y2: Int

    def __init__(out self, x1: Int, y1: Int, x2: Int, y2: Int):
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2


def _segments(svg: String) raises -> List[_Seg]:
    """Every `<line>` as integer endpoints, in document order."""
    var x1 = _attr_values(svg, "line", "x1")
    var y1 = _attr_values(svg, "line", "y1")
    var x2 = _attr_values(svg, "line", "x2")
    var y2 = _attr_values(svg, "line", "y2")
    var out = List[_Seg]()
    for i in range(len(x1)):
        out.append(
            _Seg(
                Int(Float64(x1[i])),
                Int(Float64(y1[i])),
                Int(Float64(x2[i])),
                Int(Float64(y2[i])),
            )
        )
    return out^


def _has(segs: List[_Seg], x1: Int, y1: Int, x2: Int, y2: Int) -> Bool:
    for s in segs:
        if s.x1 == x1 and s.y1 == y1 and s.x2 == x2 and s.y2 == y2:
            return True
    return False


def _spans_plot_width(s: _Seg) -> Bool:
    return s.y1 == s.y2 and s.x1 == _X0 and s.x2 == _X1


def _spans_plot_height(s: _Seg) -> Bool:
    return s.x1 == s.x2 and s.y1 == _Y0 and s.y2 == _Y1


def _full_span_count(segs: List[_Seg]) -> Int:
    """Lines that bound or cross the whole plot rect: the spines, since
    a tick is five pixels long and this chart has no gridlines."""
    var n = 0
    for s in segs:
        if _spans_plot_width(s) or _spans_plot_height(s):
            n += 1
    return n


def _plot(theme: Theme) raises -> Plot:
    # Symmetric about zero on both axes, so `_data_extent`'s 5% padding
    # keeps zero at the exact center of the plot rect: x = 220, y = 135.
    var xs: List[Float64] = [-4.0, 0.0, 4.0]
    var ys: List[Float64] = [-4.0, 1.0, 4.0]
    return scatter(xs, ys, theme=theme, width=400, height=300)


def test_the_default_frame_is_left_and_bottom_only() raises:
    var segs = _segments(render_svg(_plot(_theme())).to_string())
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")
    assert_true(not _has(segs, _X0, _Y0, _X1, _Y0), "no top line")
    assert_true(not _has(segs, _X1, _Y0, _X1, _Y1), "no right line")
    assert_equal(_full_span_count(segs), 2)


def test_all_four_flags_draw_a_full_box() raises:
    var segs = _segments(
        render_svg(_plot(_theme(right=True, top=True))).to_string()
    )
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom")
    assert_true(_has(segs, _X0, _Y0, _X1, _Y0), "top")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left")
    assert_true(_has(segs, _X1, _Y0, _X1, _Y1), "right")
    assert_equal(_full_span_count(segs), 4)


def test_a_frameless_chart_drops_the_lines_and_the_ticks_but_keeps_labels() raises:
    var s = render_svg(_plot(_theme(left=False, bottom=False))).to_string()
    var segs = _segments(s)
    assert_equal(_full_span_count(segs), 0, "no axis lines")
    assert_equal(len(segs), 0, "and no tick marks either")
    # The numbers stay: a frameless chart has less furniture, not less
    # information.
    assert_true(s.find(">0<") >= 0, "the tick labels are still drawn")


def test_hiding_one_axis_leaves_the_others_ticks_alone() raises:
    var segs = _segments(render_svg(_plot(_theme(bottom=False))).to_string())
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "the left line stays")
    for s in segs:
        assert_true(
            not (s.y1 == _Y1 and s.y2 > _Y1),
            "no x tick hangs off the hidden bottom axis",
        )
    var y_ticks = 0
    for s in segs:
        if s.x1 == _X0 - 5 and s.x2 == _X0:
            y_ticks += 1
    assert_true(y_ticks > 0, "the y ticks are untouched")


def test_axes_at_zero_cross_the_data_and_take_their_ticks_along() raises:
    # Zero is the exact center of both padded domains (see `_plot`).
    var zero_x = (_X0 + _X1) // 2
    var zero_y = (_Y0 + _Y1) // 2
    var segs = _segments(
        render_svg(
            _plot(_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO))
        ).to_string()
    )
    assert_true(_has(segs, _X0, zero_y, _X1, zero_y), "x axis at y = 0")
    assert_true(_has(segs, zero_x, _Y0, zero_x, _Y1), "y axis at x = 0")
    assert_true(not _has(segs, _X0, _Y1, _X1, _Y1), "not at the bottom too")
    assert_true(not _has(segs, _X0, _Y0, _X0, _Y1), "nor at the left")
    # Ticks moved with their lines: an x tick now hangs off row 135, and
    # a y tick reaches leftward from column 220.
    var moved_x = 0
    var moved_y = 0
    for s in segs:
        if s.y1 == zero_y and s.y2 == zero_y + 5:
            moved_x += 1
        if s.x1 == zero_x - 5 and s.x2 == zero_x:
            moved_y += 1
    assert_true(moved_x > 0, "x ticks follow the x axis to zero")
    assert_true(moved_y > 0, "y ticks follow the y axis to zero")


def test_zero_falls_back_to_the_edge_when_the_domain_misses_zero() raises:
    # All-positive data: an axis at zero would be outside the plot rect,
    # so the documented fallback puts both lines back on the edges.
    var xs: List[Float64] = [10.0, 20.0, 30.0]
    var ys: List[Float64] = [5.0, 6.0, 9.0]
    var segs = _segments(
        render_svg(
            scatter(
                xs,
                ys,
                theme=_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO),
                width=400,
                height=300,
            )
        ).to_string()
    )
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")
    assert_equal(_full_span_count(segs), 2)


def test_zero_falls_back_on_a_log_axis() raises:
    # log10(0) is undefined, so a log axis can never carry the line.
    var xs: List[Float64] = [1.0, 10.0, 100.0]
    var ys: List[Float64] = [1.0, 10.0, 100.0]
    var p = scatter(
        xs,
        ys,
        theme=_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO),
        width=400,
        height=300,
    )
    var segs = _segments(render_svg(p^.scale_y_log().scale_x_log()).to_string())
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")


def test_the_flags_reach_a_categorical_frame_too() raises:
    # One helper draws every frame's spines, so a bar chart gets the
    # same box -- its plot rect is the same, since the y labels here are
    # no wider than the default margin.
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var segs = _segments(
        render_svg(
            bar(
                cats,
                vals,
                theme=_theme(right=True, top=True),
                width=400,
                height=300,
            )
        ).to_string()
    )
    assert_equal(_full_span_count(segs), 4, "a bar chart takes the full box")


def test_zero_is_ignored_where_an_axis_is_not_continuous() raises:
    # A bar chart's x-axis is ordinal: x = 0 has no position, so the
    # vertical line stays at the edge rather than guessing.
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var segs = _segments(
        render_svg(
            bar(
                cats,
                vals,
                theme=_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO),
                width=400,
                height=300,
            )
        ).to_string()
    )
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")
    assert_equal(_full_span_count(segs), 2)


def test_a_mark_with_no_y_axis_draws_no_vertical_line_whatever_the_flags_say() raises:
    # `Mark.RUG` suppresses the y-axis: a left or right line there would
    # claim a scale the chart does not have.
    var values: List[Float64] = [1.0, 2.0, 3.0, 5.0]
    var segs = _segments(
        render_svg(
            rugplot(
                values,
                theme=_theme(right=True, top=True),
                width=400,
                height=300,
            )
        ).to_string()
    )
    for s in segs:
        assert_true(
            not _spans_plot_height(s),
            "no vertical spine on a mark with no y-axis",
        )
    var horizontals = 0
    for s in segs:
        if _spans_plot_width(s):
            horizontals += 1
    assert_equal(horizontals, 2, "the top and bottom lines still draw")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
