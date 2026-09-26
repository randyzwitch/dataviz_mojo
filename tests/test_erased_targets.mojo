"""`AnyChart.bound[...]()` and `ChartLike.erased_with[...]()` (#838).

Erasing a chart names its mark's render for every draw target, four
render pipelines to compile per erased mark, and a program that only
calls `render_layers(bar, line)` used all four for nothing: layers
draw marks through their own layer renderers. The variadic
composition entries now erase each chart with only the render slots
they draw marks through. This checks that the variadic entries draw
exactly what a fully erased list draws, that an unbound slot refuses
rather than draws, and that erasing an already erased chart keeps
every target.
"""

from std.testing import TestSuite, assert_equal, assert_raises

from dataviz import (
    bar,
    line,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_pdf,
    render_layers_svg,
)
from dataviz.chart import AnyChart
from test_output_digest import _canvas_digest


def _cats() -> List[String]:
    return ["a", "b", "c"]


def _vals() -> List[Float64]:
    return [3.0, 1.0, 2.0]


def _xs() -> List[Float64]:
    return [0.0, 1.0, 2.0]


def test_variadic_layers_draw_what_the_erased_list_draws() raises:
    var typed = render_layers(bar(_cats(), _vals()), line(_xs(), _vals()))
    var plots: List[AnyChart] = [
        bar(_cats(), _vals()).erased(),
        line(_xs(), _vals()).erased(),
    ]
    assert_equal(_canvas_digest(typed), _canvas_digest(render_layers(plots)))


def test_variadic_layers_svg_draws_what_the_erased_list_draws() raises:
    var typed = render_layers_svg(bar(_cats(), _vals()), line(_xs(), _vals()))
    var plots: List[AnyChart] = [
        bar(_cats(), _vals()).erased(),
        line(_xs(), _vals()).erased(),
    ]
    assert_equal(typed.to_string(), render_layers_svg(plots).to_string())


def test_variadic_facets_draw_what_the_erased_list_draws() raises:
    var typed = render_facets(
        bar(_cats(), _vals()), line(_xs(), _vals()), cols=2
    )
    var plots: List[AnyChart] = [
        bar(_cats(), _vals()).erased(),
        line(_xs(), _vals()).erased(),
    ]
    assert_equal(
        _canvas_digest(typed), _canvas_digest(render_facets(plots, cols=2))
    )


def test_variadic_facets_svg_draw_what_the_erased_list_draws() raises:
    var typed = render_facets_svg(
        bar(_cats(), _vals()), line(_xs(), _vals()), cols=2
    )
    var plots: List[AnyChart] = [
        bar(_cats(), _vals()).erased(),
        line(_xs(), _vals()).erased(),
    ]
    assert_equal(
        typed.to_string(), render_facets_svg(plots, cols=2).to_string()
    )


def test_an_unbound_render_slot_refuses() raises:
    var canvas_only: List[AnyChart] = [
        bar(_cats(), _vals()).erased_with[canvas=True]()
    ]
    _ = render_facets(canvas_only, cols=1)
    with assert_raises(contains="erased without a render for this draw"):
        _ = render_facets_svg(canvas_only, cols=1)

    var svg_only: List[AnyChart] = [
        AnyChart.bound[canvas=False, svg=True, pdf=False, bounds=False](
            line(_xs(), _vals())
        )
    ]
    with assert_raises(contains="erased without a render for this draw"):
        _ = render_facets(svg_only, cols=1)

    var none: List[AnyChart] = [line(_xs(), _vals()).erased_with()]
    _ = render_layers(none)
    _ = render_layers_svg(none)
    with assert_raises(contains="erased without a render for this draw"):
        _ = render_facets(none, cols=1)


def test_erasing_an_erased_chart_keeps_every_target() raises:
    var plots: List[AnyChart] = [bar(_cats(), _vals()).erased().erased_with()]
    _ = render_facets(plots, cols=1)
    _ = render_facets_svg(plots, cols=1)
    _ = render_layers_pdf(plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
