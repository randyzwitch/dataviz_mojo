"""Tests for the secondary y-axis caption: a layer with .secondary_
axis() set captions that axis via its own .labels(y_title=...), read
by render_layers()/render_layers_svg() from that specific layer (not
plots[0]), mirrored onto the plot's right edge with the opposite
rotation the primary y_title uses. Absent entirely when no secondary-
axis layer sets one -- the pre-existing, still-default behavior.
"""

from std.testing import assert_true, TestSuite

from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_layers_svg
from dataviz_mojo.theme import Theme


def test_render_layers_svg_secondary_axis_caption_matches_hand_derived_position() raises:
    # Primary layer (y:[10,20]) with no caption, secondary layer
    # (y:[50,10]) captioned "Growth" via its own .labels(y_title=...) --
    # confirmed against a real render_layers_svg() run first, canvas
    # 400x300, no gridlines: the secondary axis's own line shrinks
    # further left (to x=332, from the no-caption case's own x=350) to
    # make room, and the caption itself draws rotated +90 degrees
    # (the opposite of the primary y_title's own -90), centered at
    # (389, 135) -- the vertical midpoint of the shared plot rect.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).theme(Theme(show_gridlines=False))
    var secondary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .secondary_axis()
        .labels(y_title="Growth")
        .theme(Theme(show_gridlines=False))
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = SvgCanvas(400, 300)
    render_layers_svg(svg, plots, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true(
        '<text x="389" y="135" font-size="14.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle" transform="rotate(90.000 389 135)">Growth</text>' in s,
        "the secondary axis's own caption, rotated the opposite way from the primary y_title",
    )
    assert_true(
        '<line x1="332" y1="20" x2="332" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's own line, shrunk further left to also make room for its caption",
    )


def test_render_layers_svg_no_caption_when_secondary_axis_has_no_y_title() raises:
    # The pre-existing, still-default case: a secondary-axis layer with
    # no .labels(y_title=...) draws no caption at all, and the
    # secondary axis's own line lands at its own no-caption position
    # (x=350, not x=332 -- confirmed against tests/test_secondary_axis.
    # mojo's own already-established geometry for this exact setup).
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).theme(Theme(show_gridlines=False))
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().theme(Theme(show_gridlines=False))
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = SvgCanvas(400, 300)
    render_layers_svg(svg, plots, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true("rotate(90" not in s, "no secondary-axis caption text draws when y_title is unset")
    assert_true(
        '<line x1="350" y1="20" x2="350" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's own line lands at its own no-caption position, unaffected",
    )


def test_render_layers_svg_primary_layers_own_y_title_is_not_mistaken_for_a_caption() raises:
    # plots[0] (the primary layer) setting its own y_title must still
    # draw on the *left* the normal way -- only a layer that actually
    # called .secondary_axis() triggers the right-side caption logic.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).labels(y_title="Primary").theme(
        Theme(show_gridlines=False)
    )
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().theme(Theme(show_gridlines=False))
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = SvgCanvas(400, 300)
    render_layers_svg(svg, plots, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true("rotate(-90" in s, "the primary layer's own y_title still draws, rotated the usual way")
    assert_true("rotate(90.000" not in s, "no right-side caption draws just because plots[0] set a y_title")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
