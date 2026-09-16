"""Rendering remains stable across Plot ownership and mark changes (#607).

These tests exercise public constructors and rendering results, so a missing
or stale backend callback fails without comparing callback addresses.
"""
from std.testing import TestSuite, assert_equal, assert_true
from canvas.vector.pdf import PdfCanvas
from _mark_registry import _representative_plot
from _test_helpers import _assert_same_canvas
from dataviz import (
    Plot,
    line,
    hexbin,
    render,
    render_svg,
    render_pdf,
    render_facets,
    render_facets_svg,
    render_facets_pdf,
    render_layers,
    render_layers_svg,
    render_layers_pdf,
)
from dataviz.core.mark import Mark
from dataviz.plot import render_tight, render_tight_svg, render_tight_pdf


def _pdf_bytes(var doc: PdfCanvas) raises -> List[UInt8]:
    return doc.to_bytes()


def _assert_same_bytes(a: List[UInt8], b: List[UInt8]) raises:
    assert_equal(len(a), len(b))
    for i in range(len(a)):
        if a[i] != b[i]:
            assert_equal(a[i], b[i], "PDF byte " + String(i))


def _assert_same_plot(a: Plot, b: Plot) raises:
    _assert_same_canvas(render(a), render(b), a._mark.name())
    assert_equal(render_svg(a).to_string(), render_svg(b).to_string())
    _assert_same_bytes(_pdf_bytes(render_pdf(a)), _pdf_bytes(render_pdf(b)))
    _assert_same_canvas(render_tight(a), render_tight(b), a._mark.name())
    assert_equal(
        render_tight_svg(a).to_string(), render_tight_svg(b).to_string()
    )
    _assert_same_bytes(
        _pdf_bytes(render_tight_pdf(a)), _pdf_bytes(render_tight_pdf(b))
    )


def test_every_mark_survives_copy_move_and_a_heterogeneous_list() raises:
    var expected = List[Plot]()
    var moved = List[Plot]()
    for value in range(Mark.COUNT):
        var original = _representative_plot(Mark(value))
        var copied = original.copy()
        expected.append(original^)
        moved.append(copied^)
    var copied_list = moved.copy()
    for i in range(Mark.COUNT):
        _assert_same_plot(expected[i], copied_list[i])


def test_default_and_fluent_mark_changes_match_fresh_constructors() raises:
    var x: List[Float64] = [0, 1, 2]
    var y: List[Float64] = [1, 3, 2]
    var base = line(x, y).size(400, 300)
    var binned = hexbin(x, y).size(400, 300)
    var changed = base.copy().mark_hexbin().encode_hexbin(x, y)
    _assert_same_plot(binned, changed)
    var back = changed.copy().mark_line().encode(x=x, y=y)
    _assert_same_plot(base, back)
    _assert_same_plot(
        Plot().encode(x=x, y=y).size(400, 300),
        base.copy().mark_point(),
    )


def test_copied_mixed_facets_keep_each_marks_renderer() raises:
    var plots = List[Plot]()
    plots.append(_representative_plot(Mark.LINE))
    plots.append(_representative_plot(Mark.HEXBIN))
    plots.append(_representative_plot(Mark.DENDROGRAM))
    var copied = plots.copy()
    _assert_same_canvas(
        render_facets(plots, cols=2), render_facets(copied, cols=2), "facets"
    )
    assert_equal(
        render_facets_svg(plots, cols=2).to_string(),
        render_facets_svg(copied, cols=2).to_string(),
    )
    _assert_same_bytes(
        _pdf_bytes(render_facets_pdf(plots, cols=2)),
        _pdf_bytes(render_facets_pdf(copied, cols=2)),
    )


def test_copied_mixed_layers_keep_their_marks() raises:
    var plots = List[Plot]()
    plots.append(_representative_plot(Mark.LINE))
    plots.append(_representative_plot(Mark.POINT))
    var copied = plots.copy()
    _assert_same_canvas(render_layers(plots), render_layers(copied), "layers")
    assert_equal(
        render_layers_svg(plots).to_string(),
        render_layers_svg(copied).to_string(),
    )
    _assert_same_bytes(
        _pdf_bytes(render_layers_pdf(plots)),
        _pdf_bytes(render_layers_pdf(copied)),
    )


def test_count_is_one_past_the_last_named_mark() raises:
    # `name()` answers `"Mark(<n>)"` for a value with no constant. So
    # the value at `COUNT` must have no name -- a constant added there
    # without raising `COUNT` is exactly the skip #634 was, and every
    # sweep walks `range(COUNT)`, so nothing else fails for it -- and the
    # value one below must have one, or `COUNT` was raised past the end.
    # Relies on the values being contiguous and every constant having a
    # `name()` branch, which the mark-adding checklist requires.
    assert_true(
        Mark(Mark.COUNT).name().startswith("Mark("),
        "a mark is named at Mark.COUNT -- raise COUNT to cover it (#648)",
    )
    assert_true(
        not Mark(Mark.COUNT - 1).name().startswith("Mark("),
        "Mark.COUNT is past the last named mark",
    )


def test_dendrogram_is_in_the_enumerated_registry() raises:
    assert_true(Mark.DENDROGRAM._value < Mark.COUNT)
    assert_equal(Mark.DENDROGRAM.name(), "Mark.DENDROGRAM")
    var plot = _representative_plot(Mark.DENDROGRAM)
    assert_true(plot._mark == Mark.DENDROGRAM)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
