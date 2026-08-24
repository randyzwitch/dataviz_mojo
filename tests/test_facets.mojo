"""Tests for render_facets/render_facets_svg: independent per-cell layout,
titles, empty-grid/invalid-cols guards.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
    _index_of,
    _unique_categories,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo.colors import MAGENTA, RED

from _test_helpers import BG, _count_color, _assert_color


def test_render_facets_lays_out_independent_plots_side_by_side() raises:
    # Two cells, 400x300 each, side by side on an 800x300 canvas (cols=2,
    # so rows=1) -- cell 0 is x:[0,400], y:[0,300], the *exact* same
    # dimensions test_render_point_mark_centers_on_the_hand_derived_pixel
    # already hand-solved for a single (5.0, 5.0) point with Theme's
    # default margins: plot area x:[60,380], y:[20,250], point pixel
    # (220, 135). Cell 1 is x:[400,800], y:[0,300] -- identical geometry,
    # just shifted +400 in x (`render()`'s ox0 offsets everything,
    # including the margins, so the whole plot area shifts by the same
    # +400, not just its origin) -- plot area x:[460,780], point pixel
    # (620, 135) confirmed by the same offset, not re-solved from
    # scratch. Two different mark_colors (one per plot's Theme)
    # confirm each cell actually rendered its independent plot, not
    # one plot's output bleeding into or overwriting the other's cell.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=RED))
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var c = Canvas(800, 300, BG)
    render_facets(c, plots, cols=2)

    _assert_color(c, 220, 135, Theme.default().mark_color, "cell 0's point, unshifted")
    _assert_color(c, 620, 135, RED, "cell 1's point, +400px shifted")


def test_render_facets_leaves_trailing_cells_blank_when_plots_dont_fill_the_grid() raises:
    # 3 plots, cols=2 -> rows=ceil(3/2)=2, a 2x2 grid of 400x300 cells
    # on an 800x600 canvas (800/2=400, 600/2=300 -- divides evenly, no
    # rounding to reason about here). Plots fill row-major: (0,0),
    # (0,1), (1,0); (1,1) has no 4th plot and is never touched.
    #
    # Each filled cell reuses the same hand-solved single-(5.0,5.0)-point
    # geometry as the side-by-side test above, offset by its cell's
    # origin: (0,0) -> point at (220,135) [unshifted]; (0,1) -> (620,135)
    # [+400 in x]; (1,0) -> plot area y:[320,550] (cell_y0=300, so
    # +300 in y throughout), point at (220,435) [+300 in y].
    #
    # The canvas starts filled with a color no plot's Theme ever
    # produces (10,20,30, not white) specifically so a genuinely
    # untouched cell is distinguishable from one that was rendered with
    # a background matching the canvas's initial fill by
    # coincidence.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy)
    var plot2 = Plot().mark_point().encode(x=xy, y=xy)
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)
    plots.append(plot2^)

    var c = Canvas(800, 600, Color(10, 20, 30))
    render_facets(c, plots, cols=2)

    var mark_color = Theme.default().mark_color
    _assert_color(c, 220, 135, mark_color, "cell (0,0)'s point")
    _assert_color(c, 620, 135, mark_color, "cell (0,1)'s point")
    _assert_color(c, 220, 435, mark_color, "cell (1,0)'s point")
    _assert_color(c, 700, 450, Color(10, 20, 30), "cell (1,1) has no 4th plot -- never touched")


def test_render_facets_raises_on_non_positive_cols() raises:
    var plots = List[Plot]()
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_facets(c, plots, cols=0)
    with assert_raises():
        render_facets(c, plots, cols=-1)


def test_render_facets_with_empty_list_is_a_noop() raises:
    var plots = List[Plot]()
    var c = Canvas(50, 40, Color(10, 20, 30))
    render_facets(c, plots, cols=2)
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, 10)
            assert_equal(p.g, 20)
            assert_equal(p.b, 30)


def test_render_facets_svg_lays_out_independent_plots_side_by_side() raises:
    # The exact same setup test_render_facets_lays_out_independent_
    # plots_side_by_side already hand-solved for the raster path: two
    # 400x300 cells side by side on an 800x300 canvas (cols=2, rows=1),
    # each a single (5.0, 5.0) point -- cell 0's point at (220,
    # 135) [unshifted], cell 1's at (620, 135) [+400 in x, the same
    # cell-origin-offset reasoning that test's comment explains].
    # Two different mark_colors confirm each cell rendered its independent plot into the shared SvgCanvas, not one overwriting
    # the other.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=RED))
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = SvgCanvas(800, 300)
    render_facets_svg(svg, plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s,
        "cell 0's point, same coordinates render_facets()'s test finds",
    )
    assert_true(
        '<circle cx="620" cy="135" r="4" fill="#ff0000"/>' in s,
        "cell 1's point, +400px shifted, same as render_facets()'s test",
    )


def test_render_facets_svg_each_cell_gets_its_own_independent_title() raises:
    # Same two-cell 800x300 layout (cols=2) as the test just above, but
    # cell 0's Plot sets a title (via .labels()) and cell 1's
    # doesn't -- confirming render_facets()'s per-cell Plot.labels()
    # support (the wiki's Changelog, its "Plot.labels() reaches
    # render_facets/render_layers" entry): the title reserves space
    # *only* in cell 0 -- its point shifts from (220,135), the
    # no-title baseline the test above already established, down to
    # (220,146) (extra_top=Int(18.0)+4=22 pushes plot_y0 from 20 to 42,
    # moving the y=[4,6]-padded-domain midpoint pixel from
    # (20+250)/2=135 to (42+250)/2=146) -- while cell 1's point
    # stays exactly where it was (620,135), no title there to reserve
    # room for. The title itself centers at
    # ((60+380)//2, Int(18.0*0.8))=(220,14), cell 0's inner rect,
    # unaffected by cell 1's layout.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).labels(title="Left")
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=RED))
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = SvgCanvas(800, 300)
    render_facets_svg(svg, plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold" fill="#282828"'
        ' text-anchor="middle">Left</text>' in s,
        "cell 0's title, centered on its inner plot rect",
    )
    assert_true(
        '<circle cx="220" cy="146" r="4" fill="#1e64b4"/>' in s,
        "cell 0's point, shifted down to make room for its title",
    )
    assert_true(
        '<circle cx="620" cy="135" r="4" fill="#ff0000"/>' in s,
        "cell 1's point, unaffected -- it never set a title",
    )


def test_render_facets_svg_raises_on_non_positive_cols() raises:
    var plots = List[Plot]()
    var svg = SvgCanvas(400, 300)
    with assert_raises():
        render_facets_svg(svg, plots, cols=0)


def test_render_facets_paints_each_cells_full_rect_including_a_titles_margin() raises:
    # render_facets never filled a background of its own -- it relied on
    # _render_generic filling the cell rect it was handed, which is the
    # rect *after* _apply_labels already shrank it to reserve room for
    # a title. So a titled cell's top band was never painted, and
    # showed whatever the canvas happened to hold beforehand. render()
    # has always documented the opposite contract ("the whole original
    # rect is filled . so a title's reserved margin strip gets
    # painted too"); facets now fills each cell's full rect to match.
    #
    # One cell (cols=1) on a deliberately non-background canvas: with
    # title_font_size=18.0 and label_gap=4, extra_top is 22, so y=2 sits
    # inside the reserved strip and above the plot area entirely. Before
    # this fill existed that pixel stayed magenta.
    var xy: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_point().encode(x=xy, y=xy).labels(title="Titled"))

    var c = Canvas(400, 300, MAGENTA)
    render_facets(c, plots, 1)
    _assert_color(c, 2, 2, BG, "a titled cell's reserved title strip")

    # .and the same for an untitled cell, where the strip doesn't
    # exist but the corner is still outside the plot area -- confirming
    # the new fill covers the ordinary case too, not just the titled one.
    var untitled = List[Plot]()
    untitled.append(Plot().mark_point().encode(x=xy, y=xy))
    var c2 = Canvas(400, 300, MAGENTA)
    render_facets(c2, untitled, 1)
    _assert_color(c2, 2, 2, BG, "an untitled cell's top-left corner")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
