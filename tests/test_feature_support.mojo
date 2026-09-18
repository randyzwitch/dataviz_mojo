"""The feature-support table (`Mark.supports`, mark.mojo) against what
the code does, for every mark and every feature (#213).

The sweep turns each feature on for every mark's representative plot
and asks the output, not the source: a `<title>` appears or does not,
a label is drawn or is not, the picture changes or does not, a call
raises or does not. The table is the claim; the render is the oracle.
A mark gaining a feature without a table entry fails here, and so does
a table entry the code does not honor -- which is how the lists this
table replaced went stale twice. Its first run found four such
disagreements, one of them `effect_scatter()` dropping the `tooltips`
it documents.

One sweep rather than one test per feature, so each mark's plot is
built once and every mismatch is reported together rather than the
first one per feature.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from _mark_registry import _H, _W, _representative_plot
from dataviz import (
    beeswarm,
    effect_scatter,
    scatter,
    scatter3d,
    single_axis,
)
from dataviz.core.mark import Feature, Mark, _marks_supporting
from dataviz.core.theme import Theme
from dataviz.plot import Plot, render_svg


def _count(s: String, needle: String) -> Int:
    var n = 0
    var at = 0
    while True:
        var i = s.find(needle, at)
        if i < 0:
            return n
        n += 1
        at = i + needle.byte_length()


def _svg(plot: Plot) raises -> String:
    return render_svg(plot).to_string()


def _every_mark() -> List[Mark]:
    var out = List[Mark]()
    for value in range(Mark.COUNT):
        out.append(Mark(value))
    return out^


def _with_tooltips_opt_in(mark: Mark) raises -> Plot:
    """The point-per-datum marks, built with their own `tooltips=True`;
    `_representative_plot` builds them without it."""
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [3.0, 1.0, 2.0]
    var zs: List[Float64] = [2.0, 3.0, 1.0]
    if mark == Mark.POINT:
        return scatter(xs, ys, tooltips=True, width=_W, height=_H)
    if mark == Mark.EFFECT_SCATTER:
        return effect_scatter(xs, ys, tooltips=True, width=_W, height=_H)
    if mark == Mark.SINGLE_AXIS:
        return single_axis(xs, tooltips=True, width=_W, height=_H)
    if mark == Mark.SCATTER3D:
        return scatter3d(xs, ys, zs, tooltips=True, width=_W, height=_H)
    var cats: List[String] = ["a", "b"]
    var values = List[List[Float64]]()
    var a: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var b: List[Float64] = [2.0, 3.0, 4.0, 5.0]
    values.append(a^)
    values.append(b^)
    return beeswarm(cats, values, tooltips=True, width=_W, height=_H)


def _renders(plot: Plot) -> Bool:
    """Whether the plot renders at all: the oracle for the features
    whose unsupported case is a raise."""
    try:
        _ = render_svg(plot)
        return True
    except:
        return False


def test_table_lists_every_mark_once_per_feature() raises:
    for f in range(Feature.COUNT):
        var marks = _marks_supporting(Feature(f))
        for i in range(len(marks)):
            for j in range(i + 1, len(marks)):
                assert_false(
                    marks[i] == marks[j],
                    Feature(f).name() + " lists " + marks[i].name() + " twice",
                )
            assert_true(
                marks[i]._value < Mark.COUNT,
                Feature(f).name() + " lists a mark past Mark.COUNT",
            )


def test_supports_agrees_with_the_table() raises:
    for f in range(Feature.COUNT):
        var feature = Feature(f)
        var marks = _marks_supporting(feature)
        for mark in _every_mark():
            var listed = False
            for m in marks:
                if m == mark:
                    listed = True
            assert_equal(
                mark.supports(feature),
                listed,
                mark.name() + ".supports(" + feature.name() + ")",
            )


def _check(
    mut mismatches: List[String], mark: Mark, feature: Feature, found: Bool
):
    """Record a disagreement between the table and the render."""
    if found != mark.supports(feature):
        mismatches.append(
            mark.name()
            + " "
            + feature.name()
            + ": table says "
            + String(mark.supports(feature))
            + ", the render says "
            + String(found)
        )


def test_every_mark_matches_the_table() raises:
    var mismatches = List[String]()
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [3.0, 1.0, 2.0]
    var c: List[Float64] = [0.1, 0.5, 0.9]
    for mark in _every_mark():
        var plot = _representative_plot(mark)
        var base = _svg(plot)

        # Theme.svg_tooltips defaults to True, so `base` already carries
        # titles wherever the mark honors the flag; the three opt-in marks
        # are asked again with their own flag on.
        var has_title = "<title>" in base
        var opt_in = (
            mark == Mark.POINT
            or mark == Mark.EFFECT_SCATTER
            or mark == Mark.BEESWARM
            or mark == Mark.SINGLE_AXIS
            or mark == Mark.SCATTER3D
        )
        if opt_in:
            if has_title:
                mismatches.append(
                    mark.name()
                    + " carries titles without its own tooltips=True"
                )
            has_title = "<title>" in _svg(_with_tooltips_opt_in(mark))
        _check(mismatches, mark, Feature.TOOLTIPS, has_title)

        var labeled = _svg(plot.copy().theme(Theme(show_data_labels=True)))
        _check(
            mismatches,
            mark,
            Feature.DATA_LABELS,
            _count(labeled, "<text") > _count(base, "<text"),
        )

        var turned = plot.copy()
        if mark == Mark.HISTOGRAM:
            # Its own flag: the histogram encoder carries orientation.
            turned._histogram.horizontal = True
        else:
            turned._horizontal = True
        _check(mismatches, mark, Feature.HORIZONTAL, _svg(turned) != base)

        _check(
            mismatches,
            mark,
            Feature.ANNOTATIONS_Y,
            _renders(plot.copy().annotate_line(1.5, label="ref")),
        )
        _check(
            mismatches,
            mark,
            Feature.ANNOTATIONS_X,
            _renders(plot.copy().annotate_vline(1.5, label="ref")),
        )
        _check(
            mismatches,
            mark,
            Feature.ANNOTATIONS_XY,
            _renders(plot.copy().annotate_point(1.5, 1.5, label="ref")),
        )
        _check(
            mismatches, mark, Feature.LOG_X, _renders(plot.copy().scale_x_log())
        )
        _check(
            mismatches, mark, Feature.LOG_Y, _renders(plot.copy().scale_y_log())
        )

        var colored: Bool
        try:
            if mark == Mark.SINGLE_AXIS:
                # Its own encoder carries the same channels.
                _ = render_svg(plot.copy().encode_single_axis(xs, color=c))
            else:
                _ = render_svg(plot.copy().encode(x=xs, y=ys, color=c))
            colored = True
        except:
            colored = False
        _check(mismatches, mark, Feature.COLOR_SIZE, colored)

    var report = String("")
    for m in mismatches:
        report += "\n  " + m
    assert_equal(
        len(mismatches),
        0,
        "the feature-support table disagrees with the render:" + report,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
