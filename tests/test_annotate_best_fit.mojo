"""Tests for Plot.annotate_best_fit(): an ordinary-least-squares line
computed directly from the plot's own already-encoded x/y data --
hand-derived (cross-checked against a real render) slope/intercept/
R-squared and line/label placement, both raise paths (too few points,
a vertical scatter), the mark-support boundary, the all-y-identical
R-squared special case, and deferred computation (callable before
.encode() in the fluent chain).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme


def test_render_svg_annotate_best_fit_matches_hand_derived_fit_and_line() raises:
    # x=[1,2,3,4,5], y=[1,3,2,5,4] -- n=5, sum_x=15, sum_y=15,
    # sum_xy=1+6+6+20+20=53, sum_xx=1+4+9+16+25=55.
    # slope = (5*53 - 15*15) / (5*55 - 15*15) = 40/50 = 0.8
    # intercept = mean_y - slope*mean_x = 3 - 0.8*3 = 0.6
    # SS_tot = sum((y-3)^2) = 4+0+1+4+1 = 10
    # SS_res: predicted 1.4/2.2/3.0/3.8/4.6 -> residuals -0.4/0.8/-1/1.2/-0.6
    #   -> squares 0.16/0.64/1/1.44/0.36 -> sum 3.6
    # R^2 = 1 - 3.6/10 = 0.64
    # Every number independently re-derived via python3 and cross-checked
    # against the actual rendered SVG below (canvas 400x300, no
    # gridlines, plot rect x:[60,380] y:[20,250] -- the same frame every
    # other continuous-axis test in this package derives for this size).
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit(
        show_equation=True, show_r_squared=True, label="Fit"
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<line x1="60" y1="227" x2="380" y2="43" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the fitted line, spanning the full padded x-domain",
    )
    assert_true(
        '<text x="376" y="32" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">Fit</text>' in s,
        "the label heading, right-aligned near the plot's top-right corner",
    )
    assert_true(
        '<text x="376" y="48" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">y = 0.800x + 0.600</text>' in s,
        "the fitted equation, below the label",
    )
    assert_true(
        '<text x="376" y="64" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">R² = 0.640</text>' in s,
        "R-squared, below the equation",
    )


def test_render_svg_annotate_best_fit_draws_only_the_line_with_no_options_set() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit().theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="60" y1="227" x2="380" y2="43" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the line still draws",
    )
    assert_true("y = " not in s, "no equation text without show_equation=True")
    assert_true("R²" not in s, "no R-squared text without show_r_squared=True")


def test_render_svg_annotate_best_fit_all_y_identical_reports_r_squared_of_one() raises:
    # Every y value identical -- slope comes out to exactly 0.0 (see
    # this method's own docstring), and SS_tot is 0.0, which the
    # implementation defines as R^2 = 1.0 rather than a literal 0/0.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [5.0, 5.0, 5.0, 5.0]
    var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit(show_r_squared=True)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("R² = 1.000" in s, "an all-identical y column is a trivially perfect fit")


def test_render_svg_annotate_best_fit_works_when_called_before_encode() raises:
    # The fit is computed at render() time from whatever x_data/y_data
    # the plot ends up with -- calling this before .encode() in the
    # fluent chain must still see the real data, not an empty column.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var plot = Plot().annotate_best_fit(show_equation=True).mark_point().encode(x=x, y=y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("y = 0.800x + 0.600" in s, "the fit sees the data encoded after this call")


def test_render_raises_on_annotate_best_fit_with_fewer_than_two_points() raises:
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [2.0]
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit()
        _ = render_svg(plot)


def test_render_raises_on_annotate_best_fit_with_a_vertical_scatter() raises:
    var x: List[Float64] = [5.0, 5.0, 5.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit()
        _ = render_svg(plot)


def test_render_raises_on_annotate_best_fit_with_an_unsupported_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_best_fit()
        _ = render_svg(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
