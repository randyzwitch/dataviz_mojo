"""Tests for render_facets(shared_y_scale=True): every cell sharing one
y-domain computed from the union of all cells' own data, instead of
each computing its own independently. Hand-derived pixel positions
confirming the shared domain is actually used (not just accepted and
ignored), and every raise path (an incompatible mark, Mark.AREA
specifically, Plot.scale_y_log(), and Plot.encode(y_err=...)).
"""

from std.testing import assert_raises, assert_true, TestSuite

from dataviz_mojo.plot import Plot, render_facets_svg, render_facets


def test_render_facets_svg_shared_y_scale_matches_hand_derived_positions() raises:
    # Two cells, one point each: y=10 and y=110. Combined domain data
    # [10, 110] -- span 100, padded 5% (5.0) -> [5, 115]. Each cell is
    # 400x300 (rows=1, cols=2 -> cell height stays the full 300), default
    # theme -> plot_y0 = margin_top (20), plot_y1 = height - margin_bottom
    # (300-50=250) for *both* cells (same row).
    #
    # scale() = (20-250)/(115-5) = -230/110 = -2.0909...
    # translate() = 250 - 5*scale() = 260.4545...
    # to_pixel(10)  = 239.545... -> rounds to 240 (cell 0's own point)
    # to_pixel(110) = 30.454...  -> rounds to 30  (cell 1's own point)
    #
    # If each cell computed its own independent domain instead (the
    # shared_y_scale=False default), cell 0's lone y=10 point would be a
    # zero-span domain (pad=1.0 fallback -> domain [9,11]) landing at a
    # completely different pixel row -- so this also confirms the shared
    # domain is genuinely being used, not silently ignored.
    var x: List[Float64] = [1.0]
    var y0: List[Float64] = [10.0]
    var y1: List[Float64] = [110.0]
    var p0 = Plot().size(400, 300).mark_point().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2, shared_y_scale=True).to_string()
    assert_true('cy="240"' in s, "cell 0's own point (y=10) lands at the hand-derived shared-scale row")
    assert_true('cy="30"' in s, "cell 1's own point (y=110) lands at the hand-derived shared-scale row")


def test_render_facets_raises_on_an_incompatible_mark_with_shared_y_scale() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var p0 = Plot().size(300, 220).mark_bar().encode_categorical(x=cats, y=vals)
    var p1 = Plot().size(300, 220).mark_bar().encode_categorical(x=cats, y=vals)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_mark_area_with_shared_y_scale() raises:
    # Mark.AREA is deliberately excluded even though it's otherwise
    # part of the "continuous" family -- its own forced zero baseline
    # has no principled way to compose with an externally shared domain.
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = Plot().size(300, 220).mark_area().encode(x=x, y=y0)
    var p1 = Plot().size(300, 220).mark_area().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_scale_y_log_with_shared_y_scale() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = Plot().size(300, 220).mark_line().encode(x=x, y=y0).scale_y_log()
    var p1 = Plot().size(300, 220).mark_line().encode(x=x, y=y1).scale_y_log()
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_y_err_with_shared_y_scale() raises:
    # The shared union (_render_facets_generic's own combined_y) is
    # computed over plain plot.y_data, not widened for whisker
    # endpoints the way a standalone plot's own y_domain_data is --
    # so this combination raises rather than silently risking a
    # clipped whisker. Mark.POINT, not Mark.LINE (Mark.LINE doesn't
    # support y_err at all, a separate, pre-existing restriction).
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var err: List[Float64] = [1.0, 1.0]
    var p0 = Plot().size(300, 220).mark_point().encode(x=x, y=y0, y_err=err)
    var p1 = Plot().size(300, 220).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_svg_default_keeps_each_cells_independent_scale() raises:
    # shared_y_scale defaults to False -- confirms the existing,
    # already-tested independent-per-cell behavior is unchanged: two
    # single-point cells (zero-span domains) each get their own
    # domain_min/max +/- the 1.0 fallback pad, landing both points at
    # the exact same pixel row (each cell's own point sits dead center
    # of its own [y-1, y+1] domain), unlike the shared case above where
    # they land at very different rows.
    var x: List[Float64] = [1.0]
    var y0: List[Float64] = [10.0]
    var y1: List[Float64] = [110.0]
    var p0 = Plot().size(400, 300).mark_point().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2).to_string()
    # domain [9, 11], range [250, 20] -> to_pixel(10) = 135.0 exactly,
    # the same middle row for *both* cells independently.
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('cy="135"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_true(count == 2, "both cells' own independent domain centers their lone point at row 135")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
