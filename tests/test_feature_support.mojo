"""The feature-support table (`Mark.supports`, mark.mojo) against what
the code does, for every mark and every feature (#213).

The sweep turns each feature on for every mark's representative plot
and asks the output, not the source: a `<title>` appears or does not,
a label is drawn or is not, the picture changes or does not, a call
raises or does not. The table is the claim; the render is the oracle.
A mark gaining a feature without a table entry fails here, and so does
a table entry the code does not honor -- which is how the lists this
table replaced went stale twice. Its first run found four such
disagreements, one of them `effect_scatter()` dropping the tooltips
it documented.

One sweep rather than one test per feature, so each mark's plot is
built once and every mismatch is reported together rather than the
first one per feature.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from _mark_registry import _H, _W, _representative_plot
from dataviz.core.mark import Feature, Mark, _marks_supporting
from dataviz.core.theme import Theme
from dataviz.core.tooltips import Tooltips
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


def _check_raises_or_changes(
    mut mismatches: List[String],
    mark: Mark,
    feature: Feature,
    var turned_on: Plot,
    base: String,
    count_tag: String,
):
    """The oracle for a flag that raises where it is not honored.

    Supported: the plot with the flag on renders, and differs from
    `base` -- by more `count_tag` elements when one is given, otherwise
    in any way. Not supported: it raises. Rendering unchanged fails
    either way, since that is the silent no-op #676 removed.
    """
    var rendered = True
    var svg = String("")
    try:
        svg = _svg(turned_on^)
    except:
        rendered = False
    if not mark.supports(feature):
        if rendered:
            mismatches.append(
                mark.name()
                + " "
                + feature.name()
                + ": unsupported, but rendered instead of raising"
            )
        return
    if not rendered:
        mismatches.append(
            mark.name() + " " + feature.name() + ": supported, but raised"
        )
        return
    var changed = (
        _count(svg, count_tag)
        > _count(base, count_tag) if count_tag.byte_length()
        > 0 else svg
        != base
    )
    if not changed:
        mismatches.append(
            mark.name()
            + " "
            + feature.name()
            + ": supported, but the render did not change"
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


def test_auto_tooltips_switch_off_exactly_past_each_mark_s_own_count() raises:
    """Each renderer tells `Tooltips.AUTO` how many tooltips it would
    draw. That count has to be the number it does draw, or AUTO's limit
    means something different on every mark -- a treemap counting its
    inner nodes, say, or a hexbin counting cells it merges into one
    path. So for every mark with tooltips: find the number ON draws,
    then a limit of exactly that must draw them all and one less must
    draw none (#700)."""
    var mismatches = List[String]()
    for mark in _every_mark():
        if not mark.supports(Feature.TOOLTIPS):
            continue
        var plot = _representative_plot(mark)
        var drawn = _count(_svg(plot.copy().tooltips(Tooltips.ON)), "<title>")
        var at = plot.copy()
        at._theme.auto_tooltip_limit = drawn
        var below = plot.copy()
        below._theme.auto_tooltip_limit = drawn - 1
        var at_count = _count(_svg(at^), "<title>")
        var below_count = _count(_svg(below^), "<title>")
        if at_count != drawn or below_count != 0:
            mismatches.append(
                mark.name()
                + ": ON draws "
                + String(drawn)
                + "; a limit of that drew "
                + String(at_count)
                + " and one less drew "
                + String(below_count)
            )
    assert_equal(len(mismatches), 0, "\n".join(mismatches))


def test_every_mark_matches_the_table() raises:
    var mismatches = List[String]()
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [3.0, 1.0, 2.0]
    var c: List[Float64] = [0.1, 0.5, 0.9]
    for mark in _every_mark():
        var plot = _representative_plot(mark)
        var base = _svg(plot)

        # Tooltips.AUTO is the default and every representative plot is
        # far under its limit, so `base` carries titles exactly where the
        # mark supports them (#700). OFF removes them from every mark,
        # and ON is two-sided like data labels: titles added where
        # supported, a raise everywhere else.
        _check(mismatches, mark, Feature.TOOLTIPS, "<title>" in base)
        var off = _svg(plot.copy().tooltips(Tooltips.OFF))
        if "<title>" in off:
            mismatches.append(mark.name() + " Tooltips.OFF: still titled")
        _check_raises_or_changes(
            mismatches,
            mark,
            Feature.TOOLTIPS,
            plot.copy().tooltips(Tooltips.ON),
            off,
            "<title>",
        )

        # Data labels and horizontal raise on a mark that ignores them
        # (#676), so the oracle is two-sided: a supporting mark must
        # render and show the difference, and every other mark must
        # raise. Rendering unchanged is now a failure on both sides.
        _check_raises_or_changes(
            mismatches,
            mark,
            Feature.DATA_LABELS,
            plot.copy().theme(Theme(show_data_labels=True)),
            base,
            "<text",
        )

        var turned = plot.copy()
        if mark == Mark.HISTOGRAM:
            # Its own flag: the histogram encoder carries orientation.
            turned._histogram.horizontal = True
        elif mark == Mark.DENDROGRAM:
            # Likewise. Flipping Plot._horizontal alone could not see a
            # dendrogram turn, which is how the table came to say it
            # could not.
            turned._dendrogram.horizontal = True
        else:
            turned._horizontal = True
        _check_raises_or_changes(
            mismatches, mark, Feature.HORIZONTAL, turned^, base, ""
        )

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
        # A log axis must change the picture, not just be accepted. The
        # old oracle only asked whether scale_x_log() raised, which a
        # mark that took the flag and drew linearly would have passed
        # (#687).
        _check_raises_or_changes(
            mismatches, mark, Feature.LOG_X, plot.copy().scale_x_log(), base, ""
        )
        _check_raises_or_changes(
            mismatches, mark, Feature.LOG_Y, plot.copy().scale_y_log(), base, ""
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
