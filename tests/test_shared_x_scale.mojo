"""`shared_x_scale` on facets and grids (#841): one x-domain across
every cell, the counterpart of `shared_y_scale`.

A shared domain is read off the output: two cells whose x ranges
differ show different tick labels without the flag and the same ones
with it. The refusals are checked by their messages.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from dataviz import (
    GridCell,
    render_facets,
    render_facets_pdf,
    render_facets_svg,
    render_grid,
    render_grid_pdf,
    render_grid_svg,
    save_facets,
    save_grid,
)
from dataviz.chart import AnyChart
from dataviz.plot import Plot


def _ticks(svg: String) -> List[String]:
    """Every `<text>` element's content, in document order."""
    var out = List[String]()
    var at = 0
    while True:
        var i = svg.find("<text", at)
        if i < 0:
            return out^
        var j = svg.find(">", i)
        var k = svg.find("</text>", j)
        out.append(String(svg[byte = j + 1 : k]))
        at = k


def _count(items: List[String], needle: String) -> Int:
    var n = 0
    for s in items:
        if s == needle:
            n += 1
    return n


def _narrow() raises -> AnyChart:
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [1.0, 2.0, 3.0]
    return AnyChart(Plot().mark_point().encode(xs, ys))


def _wide() raises -> AnyChart:
    var xs: List[Float64] = [0.0, 50.0, 100.0]
    var ys: List[Float64] = [1.0, 2.0, 3.0]
    return AnyChart(Plot().mark_line().encode(xs, ys))


def test_cells_keep_their_own_x_without_the_flag() raises:
    var plots: List[AnyChart] = [_narrow(), _wide()]
    var labels = _ticks(render_facets_svg(plots, cols=2).to_string())
    # The narrow cell ticks 1.0 on x and y, the wide cell on y.
    assert_equal(_count(labels, "1.0"), 3)
    assert_equal(_count(labels, "100"), 1)


def test_shared_x_scale_gives_every_cell_the_pooled_ticks() raises:
    var plots: List[AnyChart] = [_narrow(), _wide()]
    var labels = _ticks(
        render_facets_svg(plots, cols=2, shared_x_scale=True).to_string()
    )
    # Both cells now tick 0 to 100 on x; the narrow cell's own 1.0 to 3.0
    # x ticks are gone, and only its y axis still says 1.0.
    assert_equal(_count(labels, "100"), 2)
    assert_equal(_count(labels, "0"), 2)
    assert_equal(_count(labels, "1.0"), 2)  # both cells' y axes


def test_shared_x_scale_on_a_grid() raises:
    var plots: List[AnyChart] = [_narrow(), _wide()]
    var cells: List[GridCell] = [GridCell(0, 0), GridCell(0, 1)]
    var labels = _ticks(
        render_grid_svg(plots, cells, 640, 240, shared_x_scale=True).to_string()
    )
    assert_equal(_count(labels, "100"), 2)


def test_shared_x_and_y_together() raises:
    var plots: List[AnyChart] = [_narrow(), _wide()]
    _ = render_facets(plots, cols=2, shared_x_scale=True, shared_y_scale=True)


def test_matching_categorical_cells_are_accepted() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [1.0, 2.0, 3.0]
    var plots: List[AnyChart] = [
        AnyChart(Plot().mark_bar().encode_categorical(cats, vals)),
        AnyChart(Plot().mark_bar().encode_categorical(cats, vals)),
    ]
    _ = render_facets(plots, cols=2, shared_x_scale=True)


def test_shared_x_scale_refusals_name_the_cell() raises:
    var cats: List[String] = ["a", "b", "c"]
    var other: List[String] = ["a", "c", "b"]
    var vals: List[Float64] = [1.0, 2.0, 3.0]
    var differ: List[AnyChart] = [
        AnyChart(Plot().mark_bar().encode_categorical(cats, vals)),
        AnyChart(Plot().mark_bar().encode_categorical(other, vals)),
    ]
    with assert_raises(contains="cell 1 names different categories"):
        _ = render_facets(differ, cols=2, shared_x_scale=True)

    var mixed: List[AnyChart] = [
        _narrow(),
        AnyChart(Plot().mark_bar().encode_categorical(cats, vals)),
    ]
    with assert_raises(contains="cell 1 mixes a categorical x axis"):
        _ = render_facets(mixed, cols=2, shared_x_scale=True)

    var pinned: List[AnyChart] = [
        _narrow(),
        AnyChart(
            Plot()
            .mark_line()
            .encode([0.0, 1.0], [0.0, 1.0])
            .scale_x_domain(0.0, 2.0)
        ),
    ]
    with assert_raises(contains="cell 1 sets its own scale_x_domain()"):
        _ = render_facets(pinned, cols=2, shared_x_scale=True)

    var log_mix: List[AnyChart] = [
        _narrow(),
        AnyChart(
            Plot().mark_point().encode([1.0, 10.0], [1.0, 2.0]).scale_x_log()
        ),
    ]
    with assert_raises(
        contains="cell 1 disagrees with cell 0 on scale_x_log()"
    ):
        _ = render_facets(log_mix, cols=2, shared_x_scale=True)

    var labels: List[String] = ["x", "y"]
    var weights: List[Float64] = [1.0, 2.0]
    var pie: List[AnyChart] = [
        _narrow(),
        AnyChart(Plot().mark_arc().encode_categorical(labels, weights)),
    ]
    with assert_raises(contains="cell 1 mixes a categorical x axis"):
        _ = render_facets(pie, cols=2, shared_x_scale=True)


def test_every_entry_takes_the_flag() raises:
    # Mojo elaborates a function only when something calls it, so a
    # signature that dropped the flag compiles until its first caller.
    # Every public entry is called here, variadic spellings included,
    # plus the tight exports that route through the private helpers.
    var plots: List[AnyChart] = [_narrow(), _wide()]
    var cells: List[GridCell] = [GridCell(0, 0), GridCell(0, 1)]
    _ = render_facets(plots, cols=2, shared_x_scale=True)
    _ = render_facets_pdf(plots, cols=2, shared_x_scale=True)
    _ = render_facets(
        Plot().mark_point().encode([1.0, 2.0], [1.0, 2.0]),
        Plot().mark_line().encode([0.0, 9.0], [1.0, 2.0]),
        cols=2,
        shared_x_scale=True,
    )
    _ = render_facets_svg(
        Plot().mark_point().encode([1.0, 2.0], [1.0, 2.0]),
        Plot().mark_line().encode([0.0, 9.0], [1.0, 2.0]),
        cols=2,
        shared_x_scale=True,
    )
    _ = render_grid(plots, cells, 640, 240, shared_x_scale=True)
    _ = render_grid_pdf(plots, cells, 640, 240, shared_x_scale=True)
    var dir = String("/tmp/dataviz_test_shared_x_scale_")
    save_facets(plots, 2, dir + "f.png", shared_x_scale=True, tight=True)
    save_facets(plots, 2, dir + "f.svg", shared_x_scale=True, tight=True)
    save_facets(plots, 2, dir + "f.pdf", shared_x_scale=True, tight=True)
    save_facets(
        Plot().mark_point().encode([1.0, 2.0], [1.0, 2.0]),
        Plot().mark_line().encode([0.0, 9.0], [1.0, 2.0]),
        cols=2,
        path=dir + "v.svg",
        shared_x_scale=True,
    )
    save_grid(
        plots, cells, 640, 240, dir + "g.png", shared_x_scale=True, tight=True
    )
    save_grid(
        plots, cells, 640, 240, dir + "g.svg", shared_x_scale=True, tight=True
    )
    save_grid(
        plots, cells, 640, 240, dir + "g.pdf", shared_x_scale=True, tight=True
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
