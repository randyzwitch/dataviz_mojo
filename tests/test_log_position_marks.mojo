"""Log axes on the marks that only place positions (#687).

`scale_x_log()` used to be refused by every continuous-x mark but five.
The decision recorded in `_marks_supporting(Feature.LOG_X)` is yes where
the mark only places positions -- RUG, ECDF and PCOLORMESH -- and no
where something is computed in linear x first. The reasons for each no
are in that table.

The property worth asserting is not "a log axis was accepted", which is
all the feature-support sweep can see, but that it is a log axis: equal
ratios land at equal spacing. So every test here puts data at decades
and measures the spacing.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from dataviz.distributions.ecdf import ecdf
from dataviz.distributions.kde import rugplot
from dataviz.grid.image import pcolormesh
from dataviz.plot import Plot
from dataviz import render, render_svg, Theme


def _decades() -> List[Float64]:
    var v: List[Float64] = [1.0, 10.0, 100.0, 1000.0]
    return v^


def _attr(tag: String, name: String) raises -> Int:
    var key = name + '="'
    var at = tag.find(key)
    if at == -1:
        raise Error("no " + name + " in " + tag)
    var start = at + key.byte_length()
    var end = tag.find('"', start)
    return Int(Float64(String(tag[byte=start:end])))


def _rect_widths(svg: String, fill: String) raises -> List[Int]:
    """Widths of every `<rect>` filled `fill`, in document order."""
    var out = List[Int]()
    var rest = svg
    while True:
        var at = rest.find("<rect")
        if at == -1:
            break
        var end = rest.find("/>", at)
        var tag = String(rest[byte=at:end])
        if ('fill="' + fill + '"') in tag:
            out.append(_attr(tag, "width"))
        var tail = String(rest[byte = end + 2 :])
        rest = tail
    return out^


def _mesh_cell_widths(log: Bool) raises -> List[Int]:
    """Three cells between decade edges, each a different value so the
    rectilinear path cannot merge them into one run."""
    var ye: List[Float64] = [1.0, 2.0]
    var z = List[List[Float64]]()
    var row: List[Float64] = [1.0, 2.0, 3.0]
    z.append(row^)
    var plot = pcolormesh(
        _decades(), ye, z, theme=Theme(show_legend=False, show_gridlines=False)
    )
    if log:
        plot = plot^.scale_x_log()
    var svg = render_svg(plot).to_string()
    var widths = List[Int]()
    var rest = svg
    # The three cells are the three rects that span the plot's height;
    # the background rect spans the whole figure and is skipped.
    var first = True
    while True:
        var at = rest.find("<rect")
        if at == -1:
            break
        var end = rest.find("/>", at)
        var tag = String(rest[byte=at:end])
        if first:
            first = False
        elif 'height="' in tag and "fill=" in tag:
            widths.append(_attr(tag, "width"))
        var tail = String(rest[byte = end + 2 :])
        rest = tail
    return widths^


def test_decade_cells_are_equal_width_on_a_log_axis() raises:
    var w = _mesh_cell_widths(True)
    assert_true(len(w) >= 3, "expected three cells, found " + String(len(w)))
    # Rounding to whole pixels can move an edge by one.
    for i in range(1, 3):
        assert_true(
            abs(w[i] - w[0]) <= 1,
            (
                "decade cells should be equal width on a log axis, got "
                + String(w[0])
                + ", "
                + String(w[1])
                + ", "
                + String(w[2])
            ),
        )


def test_the_same_cells_are_9_to_90_to_900_on_a_linear_axis() raises:
    # The control. Without it the test above would also pass on a
    # renderer that ignored the edges and drew equal columns.
    var w = _mesh_cell_widths(False)
    assert_true(len(w) >= 3, "expected three cells, found " + String(len(w)))
    assert_true(
        w[2] > 8 * w[1] and w[1] > 8 * w[0],
        (
            "linear decade cells should grow tenfold, got "
            + String(w[0])
            + ", "
            + String(w[1])
            + ", "
            + String(w[2])
        ),
    )


def test_a_log_axis_accepts_a_log_y_too() raises:
    # A spectrogram's frequency axis is the usual case for log y.
    var xe: List[Float64] = [1.0, 2.0, 3.0]
    var z = List[List[Float64]]()
    for r in range(3):
        var row: List[Float64] = [Float64(r), Float64(r) + 1.0]
        z.append(row^)
    _ = render(pcolormesh(xe, _decades(), z).scale_y_log())


def test_a_mesh_edge_at_zero_raises_under_log() raises:
    var edges: List[Float64] = [0.0, 10.0, 100.0]
    var ye: List[Float64] = [1.0, 2.0]
    var z = List[List[Float64]]()
    var row: List[Float64] = [1.0, 2.0]
    z.append(row^)
    with assert_raises(contains="must be > 0 on a log axis"):
        _ = render(pcolormesh(edges, ye, z).scale_x_log())


def test_symlog_on_a_mesh_raises() raises:
    var ye: List[Float64] = [1.0, 2.0]
    var z = List[List[Float64]]()
    var row: List[Float64] = [1.0, 2.0, 3.0]
    z.append(row^)
    with assert_raises(contains="not symlog"):
        _ = render(pcolormesh(_decades(), ye, z).scale_x_symlog())


def _rug_tick_xs(log: Bool) raises -> List[Int]:
    """Where each rug tick sits: the vertical lines in the mark color."""
    var theme = Theme(show_gridlines=False)
    var plot = rugplot(_decades(), theme=theme)
    if log:
        plot = plot^.scale_x_log()
    var svg = render_svg(plot).to_string()
    var c = theme.mark_color
    var hexes = String("0123456789abcdef")
    var stroke = String("#")
    for ch in [c.r, c.g, c.b]:
        stroke += String(hexes[byte = Int(ch) // 16 : Int(ch) // 16 + 1])
        stroke += String(hexes[byte = Int(ch) % 16 : Int(ch) % 16 + 1])
    var out = List[Int]()
    var rest = svg
    while True:
        var at = rest.find("<line")
        if at == -1:
            break
        var end = rest.find("/>", at)
        var tag = String(rest[byte=at:end])
        if ('stroke="' + stroke + '"') in tag:
            out.append(_attr(tag, "x1"))
        var tail = String(rest[byte = end + 2 :])
        rest = tail
    return out^


def test_rug_ticks_at_decades_are_evenly_spaced_on_a_log_axis() raises:
    var xs = _rug_tick_xs(True)
    assert_equal(len(xs), 4, "one tick per observation")
    var step = xs[1] - xs[0]
    assert_true(step > 20, "the ticks are bunched, step " + String(step))
    for i in range(2, 4):
        assert_true(
            abs((xs[i] - xs[i - 1]) - step) <= 1,
            "log-axis rug ticks at decades are not evenly spaced",
        )


def test_rug_ticks_at_decades_bunch_on_a_linear_axis() raises:
    # The control: three of the four ticks crowd into the first tenth.
    var xs = _rug_tick_xs(False)
    assert_equal(len(xs), 4, "one tick per observation")
    assert_true(
        (xs[3] - xs[2]) > 8 * (xs[2] - xs[1]),
        "linear rug ticks at decades should grow tenfold",
    )


def test_ecdf_takes_a_log_x_axis() raises:
    var linear = render_svg(ecdf(_decades())).to_string()
    var logged = render_svg(ecdf(_decades()).scale_x_log()).to_string()
    assert_true(linear != logged, "scale_x_log() changed nothing on ECDF")


def test_symlog_y_on_a_position_mark_raises() raises:
    # scale_y_symlog() is gated by the same table entry as scale_x_log(),
    # so without this it would pass validation and do nothing.
    with assert_raises(contains="has no y axis to transform"):
        _ = render(rugplot(_decades()).scale_y_symlog())


def test_the_marks_decided_against_still_refuse_a_log_axis() raises:
    """The "no" half of the decision is as much a claim as the "yes".

    KDE was on this list until #718 estimated it in log space. What
    stays refused is where a log axis would misstate the data outright:
    a vector's direction and length are in data units, and a grid
    index has no logarithm.
    """
    from dataviz.core.mark import Mark
    from _mark_registry import _representative_plot

    var refused = List[Mark]()
    refused.append(Mark.QUIVER)
    refused.append(Mark.STREAMPLOT)
    refused.append(Mark.CONTOUR)
    refused.append(Mark.IMSHOW)
    for m in refused:
        with assert_raises(contains="only apply to"):
            _ = render(_representative_plot(m).scale_x_log())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
