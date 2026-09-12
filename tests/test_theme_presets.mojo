"""Render-level tests for the four built-in theme presets.

The tests detect partially applied presets by inspecting dominant fill
colors, brightness, grayscale ordering, and contrast. Expected luminance
thresholds are independent constants rather than values derived from the
preset under test.
"""

from _test_helpers import BG, _count_color, _runs_in_row
from canvas.buffer import Canvas
from canvas.color import Color
from std.testing import TestSuite, assert_equal, assert_true

from dataviz import (
    bar,
    bullet,
    effect_scatter,
    grouped_bar,
    heatmap,
    radar,
    radialbar,
    sunburst,
)
from dataviz.plot import Plot, render
from dataviz.core.color_scale import default_categorical_palette
from dataviz.core.theme import Theme
from dataviz.core.themes import dark, high_contrast, minimal, print_safe


# ---------------------------------------------------------------
# Color math. Rec.709 luma is what a grayscale reproduction keeps;
# WCAG relative luminance (gamma-decoded, then the 2.1 contrast
# formula) is what an accessibility threshold is written against.
# The two are different functions and the tests want both.


def _luma(c: Color) -> Float64:
    """Rec.709 luma of `c`, 0-255: what survives a grayscale print.

    Args:
        c: The color to measure.

    Returns:
        Luma in `[0, 255]`.
    """
    return (
        0.2126 * Float64(Int(c.r))
        + 0.7152 * Float64(Int(c.g))
        + 0.0722 * Float64(Int(c.b))
    )


def _channel_lin(v: UInt8) -> Float64:
    """One sRGB channel gamma-decoded to linear light.

    Args:
        v: The 0-255 channel value.

    Returns:
        Linear light in `[0, 1]`.
    """
    var f = Float64(Int(v)) / 255.0
    if f <= 0.04045:
        return f / 12.92
    return ((f + 0.055) / 1.055) ** 2.4


def _rel_luminance(c: Color) -> Float64:
    """WCAG 2.1 relative luminance of `c`.

    Args:
        c: The color to measure.

    Returns:
        Relative luminance in `[0, 1]`.
    """
    return (
        0.2126 * _channel_lin(c.r)
        + 0.7152 * _channel_lin(c.g)
        + 0.0722 * _channel_lin(c.b)
    )


def _contrast(a: Color, b: Color) -> Float64:
    """The WCAG 2.1 contrast ratio between `a` and `b`, 1.0 to 21.0.

    Args:
        a: One color.
        b: The other color.

    Returns:
        The ratio, always >= 1.0.
    """
    var la = _rel_luminance(a)
    var lb = _rel_luminance(b)
    var hi = la if la > lb else lb
    var lo = lb if la > lb else la
    return (hi + 0.05) / (lo + 0.05)


def _chroma(c: Color) -> Int:
    """`max(r, g, b) - min(r, g, b)`: 0 for any neutral gray.

    Args:
        c: The color to measure.

    Returns:
        The channel spread, 0-255.
    """
    var hi = Int(c.r)
    if Int(c.g) > hi:
        hi = Int(c.g)
    if Int(c.b) > hi:
        hi = Int(c.b)
    var lo = Int(c.r)
    if Int(c.g) < lo:
        lo = Int(c.g)
    if Int(c.b) < lo:
        lo = Int(c.b)
    return hi - lo


def _color_census(
    c: Canvas, skip_background: Bool
) -> Tuple[List[Color], List[Int]]:
    """Every distinct color in `c` and how many pixels it covers.

    The one primitive the render-derived assertions in this file are
    built on. Naming a color and looking for it is not enough: an
    anti-aliased edge lands on essentially arbitrary values, so
    `_bbox_of_color(c, Color(170, 170, 170))` can "find" a fill that the
    chart never drew and quietly turn a real regression into a pass.
    Counting instead means a mark's fill is identified by being large.

    Args:
        c: The rendered canvas.
        skip_background: Omit the color of the pixel at (1, 1).

    Returns:
        Parallel lists of color and pixel count, in first-seen order.
    """
    var bg = c.get_pixel(1, 1)
    var colors = List[Color]()
    var keys = List[Int]()
    var counts = List[Int]()
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if skip_background and p.r == bg.r and p.g == bg.g and p.b == bg.b:
                continue
            var key = Int(p.r) * 65536 + Int(p.g) * 256 + Int(p.b)
            var at = -1
            for i in range(len(keys)):
                if keys[i] == key:
                    at = i
                    break
            if at < 0:
                keys.append(key)
                colors.append(p)
                counts.append(1)
            else:
                counts[at] += 1
    return (colors^, counts^)


def _top_fills(c: Canvas, n: Int) raises -> List[Color]:
    """The `n` largest non-background solid regions' colors, largest
    first.

    Args:
        c: The rendered canvas.
        n: How many to return.

    Returns:
        Up to `n` colors, ordered by area descending.
    """
    var census = _color_census(c, True)
    var colors = census[0].copy()
    var counts = census[1].copy()
    var out = List[Color]()
    for _ in range(n):
        var best = -1
        for i in range(len(counts)):
            if counts[i] > 0 and (best < 0 or counts[i] > counts[best]):
                best = i
        if best < 0:
            break
        out.append(colors[best])
        counts[best] = 0
    return out^


def _dominant_fill(c: Canvas) raises -> Color:
    """The single largest non-background solid region's color.

    Answers "what is this chart actually drawn in" from the render
    rather than from the theme, so a contrast assertion measures what a
    reader would see instead of what the preset claims.

    Args:
        c: The rendered canvas.

    Returns:
        The most common non-background color.
    """
    var top = _top_fills(c, 1)
    if len(top) == 0:
        return c.get_pixel(1, 1)
    return top[0]


def _longest_run_in_row(c: Canvas, color: Color) -> Int:
    """The longest contiguous horizontal run of `color` anywhere in `c`.

    Separates a legend swatch from the data points drawn in the same
    palette color without knowing where either one landed: the swatch is
    `legend_swatch_size` px wide, a point mark is `2 * point_radius`.

    Args:
        c: The rendered canvas.
        color: The color to measure.

    Returns:
        The longest run's length in pixels, 0 when the color is absent.
    """
    var best = 0
    for y in range(c.height):
        var cur = 0
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == color.r and p.g == color.g and p.b == color.b:
                cur += 1
                if cur > best:
                    best = cur
            else:
                cur = 0
    return best


# ---------------------------------------------------------------
# Fixtures. Each renders one mark under a caller-supplied theme, so a
# test can put the same chart through two themes and compare.


def _line_canvas(t: Theme) raises -> Canvas:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0, 70.0, 63.0]
    return render(
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .labels(title="Latency", subtitle="ms per hour", x_title="Hour")
        .annotate_area(50.0, 60.0, label="band")
        .annotate_line(65.0, label="SLO")
        .theme(t)
    )


def _scatter_canvas(t: Theme) raises -> Canvas:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [12.0, 9.0, 18.0, 15.0, 22.0, 20.0, 26.0, 24.0]
    var region: List[String] = [
        "North",
        "South",
        "East",
        "North",
        "South",
        "East",
        "North",
        "South",
    ]
    return render(
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=region)
        .labels(title="Readings")
        .theme(t)
    )


def _signed_bar_canvas(t: Theme) raises -> Canvas:
    var cats: List[String] = ["A", "B", "C", "D"]
    var vals: List[Float64] = [30.0, -20.0, 25.0, -15.0]
    var tt = t
    tt.color_by_sign = True
    return render(bar(cats, vals, theme=tt, title="Change"))


def _ramp_heatmap_canvas(t: Theme) raises -> Canvas:
    """Eight cells whose values increase strictly left-to-right,
    top-to-bottom, so the color scale is sampled evenly end to end."""
    var xs = List[String]()
    var ys = List[String]()
    var vals = List[Float64]()
    var cols: List[String] = ["Mon", "Tue", "Wed", "Thu"]
    var rows: List[String] = ["AM", "PM"]
    for r in range(len(rows)):
        for c in range(len(cols)):
            xs.append(cols[c])
            ys.append(rows[r])
            vals.append(Float64(r * len(cols) + c) * 8.0)
    return render(heatmap(xs, ys, vals, theme=t, title="Load"))


def _midpoint_heatmap_canvas(t: Theme) raises -> Canvas:
    """Nine cells with values 0..8, so the color domain's midpoint (4)
    falls exactly on a cell and `Theme.color_scale_mid` is drawn as a
    solid region rather than only passed through in the gradient.

    Without this, a preset that forgets `color_scale_mid` renders it
    nowhere large enough to see: an even number of cells straddles the
    midpoint, and the continuous legend's color bar passes through it
    for about 14 px.
    """
    var xs = List[String]()
    var ys = List[String]()
    var vals = List[Float64]()
    var cols: List[String] = ["A", "B", "C"]
    var rows: List[String] = ["P", "Q", "R"]
    for r in range(len(rows)):
        for c in range(len(cols)):
            xs.append(cols[c])
            ys.append(rows[r])
            vals.append(Float64(r * len(cols) + c))
    return render(heatmap(xs, ys, vals, theme=t, title="Grid"))


def _heatmap_cell_lumas(c: Canvas) raises -> List[Float64]:
    """The eight `_ramp_heatmap_canvas` cells' luma, in value order.

    Locates the grid from the drawn cells themselves rather than from
    hard-coded margins: the union of every non-background pixel in the
    lower two thirds of the canvas is the plot area, and the eight cells
    divide it 4 x 2.
    """
    var x0 = c.width
    var x1 = -1
    var y0 = c.height
    var y1 = -1
    var bg = c.get_pixel(1, 1)
    for y in range(c.height // 6, c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == bg.r and p.g == bg.g and p.b == bg.b:
                continue
            if x < x0:
                x0 = x
            if x > x1:
                x1 = x
            if y < y0:
                y0 = y
            if y > y1:
                y1 = y
    var out = List[Float64]()
    for r in range(2):
        for col in range(4):
            var px = x0 + Int(Float64(x1 - x0) * (Float64(col) + 0.5) / 4.0)
            var py = y0 + Int(Float64(y1 - y0) * (Float64(r) + 0.5) / 2.0)
            out.append(_luma(c.get_pixel(px, py)))
    return out^


# ---------------------------------------------------------------
# The partial-application sweep.


def _max_luma(c: Canvas) -> Float64:
    """The brightest pixel on `c`, as Rec.709 luma."""
    var top = 0.0
    for y in range(c.height):
        for x in range(c.width):
            var l = _luma(c.get_pixel(x, y))
            if l > top:
                top = l
    return top


def _marks_only(t: Theme) -> Theme:
    """`t` with every non-mark ink painted in its own background, so the
    brightest pixel left is a mark or something drawn from one."""
    var out = t
    out.text_color = t.background
    out.axis_color = t.background
    out.gridline_color = t.background
    out.minor_gridline_color = t.background
    out.show_gridlines = False
    out.show_legend = False
    return out


def test_dark_tints_flatten_against_the_dark_ground_not_white() raises:
    """`Mark.EFFECT_SCATTER`'s halo and `Mark.SUNBURST`'s depth fade are
    flattened tints: a color at reduced alpha composited over the
    background, kept opaque. Flattened over the `dark()` ground, a tint
    is darker than the color it came from. Flattened over a hardcoded
    white -- which is what happened (#427) -- it is brighter than the
    color, and the halo becomes the brightest thing on a dark chart.

    So with all chrome painted in the background color, nothing on the
    canvas may be brighter than the mark it was derived from: the mark
    color for the halo, the brightest palette entry for the sunburst.
    """
    var t = _marks_only(dark())

    var ex: List[Float64] = [1.0, 1.6, 2.3, 3.0, 3.8]
    var ey: List[Float64] = [12.0, 12.8, 14.2, 15.8, 16.2]
    var halo = render(effect_scatter(ex, ey, theme=t))
    var halo_top = _max_luma(halo)
    var mark = _luma(t.mark_color)
    assert_true(
        halo_top <= mark + 1.0,
        "effect_scatter under dark(): brightest pixel has luma "
        + String(halo_top)
        + " but the mark color is only "
        + String(mark)
        + " -- the halo is flattened against white, not the background",
    )

    var ids: List[String] = ["root", "a", "b", "a1", "a2", "b1"]
    var parents: List[String] = ["", "root", "root", "a", "a", "b"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 3.0, 2.0, 4.0]
    var burst = render(sunburst(ids, parents, values, theme=t))
    var palette_top = 0.0
    for c in default_categorical_palette():
        var l = _luma(c)
        if l > palette_top:
            palette_top = l
    var burst_top = _max_luma(burst)
    assert_true(
        burst_top <= palette_top + 1.0,
        "sunburst under dark(): brightest pixel has luma "
        + String(burst_top)
        + " but the brightest palette color is only "
        + String(palette_top)
        + " -- the depth fade is flattened against white, not the background",
    )


def test_print_safe_palette_is_ordered_by_lightness() raises:
    """`print_safe()` sets `Theme.categorical_palette` to grays that a
    grayscale reproduction keeps apart: strictly increasing luma with a
    gap a photocopy can resolve (#426). The default tab10 set has two
    pairs of entries within 1.3 luma of each other, which is why a
    preset needed a palette of its own.
    """
    var p = print_safe().categorical_palette
    assert_equal(len(p), 8)
    for i in range(1, len(p)):
        var gap = _luma(p[i]) - _luma(p[i - 1])
        assert_true(
            gap >= 20.0,
            "print_safe palette entries "
            + String(i - 1)
            + " and "
            + String(i)
            + " are only "
            + String(gap)
            + " luma apart",
        )


def test_theme_categorical_palette_colors_a_multi_series_chart() raises:
    """A `Theme.categorical_palette` reaches the marks that cycle
    categories: a two-series grouped bar drawn with a two-color palette
    uses those two colors and none of the default tab10 set.
    """
    var custom: List[Color] = [Color(200, 0, 0), Color(0, 0, 200)]
    var t = Theme(categorical_palette=custom)
    var cats: List[String] = ["Q1", "Q2", "Q3"]
    var names: List[String] = ["a", "b"]
    var values: List[List[Float64]] = [[3.0, 5.0, 4.0], [2.0, 6.0, 3.0]]
    var c = render(grouped_bar(cats, names, values, theme=t))
    assert_true(_count_color(c, Color(200, 0, 0)) > 0, "series a uses entry 0")
    assert_true(_count_color(c, Color(0, 0, 200)) > 0, "series b uses entry 1")
    assert_equal(
        _count_color(c, Color(31, 119, 180)),
        0,
        "the default tab10 blue must not appear when a palette is set",
    )


def test_dark_preset_leaves_no_light_theme_default_anywhere() raises:
    """Nine marks under `dark()`, none of which may draw a solid region
    in one of the light theme's own field colors.

    This is the test the whole module exists for. `Theme()`'s neutrals
    are near-white by design -- `minor_gridline_color` (240, 240, 240),
    `radialbar_track_color` (230, 230, 230), `color_scale_mid`
    (235, 235, 235), `bullet_range_color_light` (224, 224, 224) -- so a
    dark preset that misses one paints a near-white ring, band or
    midpoint onto a dark chart, and only the mark that draws that field
    shows it. Each mark below is here because it draws a field the other
    eight do not.

    The threshold is 200 pixels so an anti-aliased edge that happens to
    average to a default's exact value cannot trip it; every real
    leftover is a solid region orders of magnitude larger than that (the
    radial bar track alone is ~8000 px).
    """
    var d = Theme()
    var t = dark()

    var names = List[String]()
    var canvases = List[Canvas]()

    names.append("line")
    canvases.append(_line_canvas(t))
    names.append("scatter")
    canvases.append(_scatter_canvas(t))
    names.append("signed bar")
    canvases.append(_signed_bar_canvas(t))
    names.append("heatmap")
    canvases.append(_ramp_heatmap_canvas(t))
    names.append("heatmap, midpoint on a cell")
    canvases.append(_midpoint_heatmap_canvas(t))

    var goals: List[String] = ["Move", "Exercise", "Stand"]
    var pct: List[Float64] = [92.0, 68.0, 100.0]
    names.append("radialbar")
    canvases.append(render(radialbar(goals, pct, theme=t, title="Activity")))

    var bcats: List[String] = ["Revenue", "Margin"]
    var measures: List[Float64] = [275.0, 18.0]
    var targets: List[Float64] = [300.0, 20.0]
    var ranges: List[List[Float64]] = [
        [200.0, 260.0, 340.0],
        [10.0, 16.0, 24.0],
    ]
    names.append("bullet")
    canvases.append(
        render(bullet(bcats, measures, targets, ranges, theme=t, title="KPI"))
    )

    var indicators: List[String] = ["Speed", "Power", "Defense", "Stamina"]
    var maxes: List[Float64] = [100.0, 100.0, 100.0, 100.0]
    var series_names: List[String] = ["A", "B"]
    var series: List[List[Float64]] = [
        [85.0, 70.0, 60.0, 75.0],
        [65.0, 90.0, 80.0, 60.0],
    ]
    names.append("radar")
    canvases.append(
        render(radar(indicators, maxes, series_names, series, theme=t))
    )

    var ex: List[Float64] = [1.0, 1.6, 2.3, 3.0, 3.8]
    var ey: List[Float64] = [12.0, 12.8, 14.2, 15.8, 16.2]
    names.append("effect scatter")
    canvases.append(render(effect_scatter(ex, ey, theme=t)))

    names.append("line, no annotations")
    var px: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var py: List[Float64] = [3.0, 1.0, 4.0, 2.0]
    canvases.append(render(Plot().mark_line().encode(x=px, y=py).theme(t)))

    # Every light-theme field a dark preset has to re-derive. Read off
    # `Theme()` rather than transcribed, so a change to a default cannot
    # leave this list quietly checking the wrong color -- but the list
    # of *which* fields, and the claim that none may survive, is written
    # here by hand.
    var field_names = List[String]()
    var field_colors = List[Color]()
    field_names.append("background")
    field_colors.append(d.background)
    field_names.append("mark_color")
    field_colors.append(d.mark_color)
    field_names.append("axis_color")
    field_colors.append(d.axis_color)
    field_names.append("gridline_color")
    field_colors.append(d.gridline_color)
    field_names.append("text_color")
    field_colors.append(d.text_color)
    field_names.append("minor_gridline_color")
    field_colors.append(d.minor_gridline_color)
    field_names.append("color_scale_low")
    field_colors.append(d.color_scale_low)
    field_names.append("color_scale_mid")
    field_colors.append(d.color_scale_mid)
    field_names.append("color_scale_high")
    field_colors.append(d.color_scale_high)
    field_names.append("mark_color_negative")
    field_colors.append(d.mark_color_negative)
    field_names.append("bullet_range_color_light")
    field_colors.append(d.bullet_range_color_light)
    field_names.append("bullet_range_color_dark")
    field_colors.append(d.bullet_range_color_dark)
    field_names.append("waterfall_total_color")
    field_colors.append(d.waterfall_total_color)
    field_names.append("radialbar_track_color")
    field_colors.append(d.radialbar_track_color)
    field_names.append("subtitle_color")
    field_colors.append(d.subtitle_color)
    field_names.append("annotation_color")
    field_colors.append(d.annotation_color)

    for i in range(len(canvases)):
        for f in range(len(field_names)):
            var n = _count_color(canvases[i], field_colors[f])
            assert_true(
                n <= 200,
                String(
                    "dark() left a light-theme default in the "
                    + names[i]
                    + " render: "
                    + String(n)
                    + " px of Theme()."
                    + field_names[f]
                ),
            )

    # An exact-color sweep can only see a field that is drawn *as* its
    # own value. Two kinds of leftover escape it: a stop that is only
    # interpolated through (`color_scale_mid` on an even cell count) and
    # one composited with alpha before it hits the canvas
    # (`annotation_area_color`, whose default lands at luma 190 over this
    # background rather than at its own RGB). So also assert the weaker
    # but broader property: on a dark ground, nothing large is bright.
    #
    # Measured headroom: across these charts the brightest region of 800
    # px or more is dark()'s own `mark_color` at luma 155.6, and the
    # brightest thing a *forgotten* field would put there is 190. The
    # effect-scatter render is in the sweep: its halos are `_lighten()`
    # flattened against `Theme.background`, so on this ground they are
    # darker than the mark color, not brighter (#427).
    for i in range(len(canvases)):
        var census = _color_census(canvases[i], False)
        var colors = census[0].copy()
        var counts = census[1].copy()
        for k in range(len(colors)):
            if counts[k] < 800:
                continue
            assert_true(
                _luma(colors[k]) < 170.0,
                String(
                    "dark() rendered a bright region in the "
                    + names[i]
                    + " chart: "
                    + String(counts[k])
                    + " px at luma "
                    + String(_luma(colors[k]))
                    + ", which is a light-theme color surviving into a"
                    " dark chart"
                ),
            )


# ---------------------------------------------------------------
# print_safe(): the grayscale claims, measured off the render.


def test_print_safe_separates_the_sign_pair_in_grayscale() raises:
    """A `color_by_sign` bar chart's positive and negative fills have to
    be far apart in Rec.709 luma, which is all a grayscale print keeps.

    The default theme's pair is (30, 100, 180) at luma 90.9 and
    (200, 60, 60) at 89.8 -- 1.1 levels out of 255, one flat shade on
    paper. The bar here is 100 rather than something merely above that,
    because the realistic half-application (this preset's `mark_color`
    with the default `mark_color_negative`) still measures 64.8.
    """
    var c = _signed_bar_canvas(print_safe())
    # The two largest non-background regions are the positive bars and
    # the negative bars, whatever colors the theme gave them. Naming the
    # two expected colors instead would let this pass while the preset
    # was broken: an anti-aliased edge somewhere in the chart happens to
    # land on (170, 170, 170), so searching for that color finds it even
    # when the negative bars are drawn in the default red.
    var fills = _top_fills(c, 2)
    assert_equal(len(fills), 2, "the signed bar chart drew fewer than 2 fills")
    var gap = _luma(fills[0]) - _luma(fills[1])
    if gap < 0.0:
        gap = -gap
    assert_true(
        gap >= 100.0,
        String(
            "print_safe() positive/negative bars are only "
            + String(gap)
            + " luma levels apart in grayscale; need >= 100"
        ),
    )


def test_print_safe_color_scale_is_monotonic_in_grayscale() raises:
    """Eight heatmap cells of strictly increasing value must be strictly
    increasing in luma, and span most of the range.

    The default theme fails both halves, which is the point: its
    diverging scale takes the same eight cells 105.9 -> 216.5 -> 114.0,
    so the lowest and highest values print as the same gray. A
    monotonic-lightness sequential map (`viridis()`, via
    `Theme.color_ramp`) is the only thing that survives the conversion.
    """
    var lumas = _heatmap_cell_lumas(_ramp_heatmap_canvas(print_safe()))
    assert_equal(len(lumas), 8, "expected 8 sampled heatmap cells")
    for i in range(len(lumas) - 1):
        assert_true(
            lumas[i + 1] > lumas[i] + 5.0,
            String(
                "print_safe() heatmap luma is not strictly increasing at cell "
                + String(i)
                + ": "
                + String(lumas[i])
                + " -> "
                + String(lumas[i + 1])
            ),
        )
    var span = lumas[len(lumas) - 1] - lumas[0]
    assert_true(
        span >= 150.0,
        String(
            "print_safe() heatmap spans only "
            + String(span)
            + " luma levels; need >= 150"
        ),
    )

    # Monotonic lightness alone would also be satisfied by a plain gray
    # ramp, which throws away everything a reader who *does* have color
    # could use. The preset is supposed to be grayscale-*safe*, not
    # grayscale: assert a real hue is still present, which is what
    # `color_ramp=viridis()` supplies and the scalar fallback does not.
    var c = _ramp_heatmap_canvas(print_safe())
    var hue = _chroma(_dominant_fill(c))
    assert_true(
        hue >= 40,
        String(
            "print_safe() drew its color scale as neutral gray (chroma "
            + String(hue)
            + "): the monotonic-lightness colormap is not being used"
        ),
    )


def test_print_safe_gridlines_are_broken_not_solid() raises:
    """Once hue is gone, a solid gray gridline and a solid gray series
    are the same object to the reader; `gridline_style=DOTTED` is what
    keeps them apart. A dotted rule crosses the plot as many short runs,
    a solid one as a single run.
    """
    var c = _line_canvas(print_safe())
    var grid = Color(206, 206, 206)
    var best = 0
    for y in range(c.height):
        var runs = _runs_in_row(c, y, grid)
        if runs > best:
            best = runs
    assert_true(
        best >= 8,
        String(
            "print_safe() gridlines look solid: the busiest row has only "
            + String(best)
            + " runs of the gridline color; a dotted rule gives many"
        ),
    )


# ---------------------------------------------------------------
# high_contrast(): the contrast claims, measured off the render.


def test_high_contrast_mark_and_gridlines_clear_their_ratios() raises:
    """The mark ink against the ground at >= 7:1 (WCAG AAA for normal
    text) and the gridlines at >= 3:1.

    Both discriminate against leaving the field alone: the default
    `mark_color` measures 5.94:1 against white and the default
    `gridline_color` 1.31:1, so a preset that raised the type sizes and
    forgot the colors fails here rather than looking merely bolder.
    """
    var c = _signed_bar_canvas(high_contrast())
    var ground = c.get_pixel(1, 1)
    # Read the ink off the render rather than naming it, so this measures
    # what a reader sees rather than what the preset claims: the bars are
    # the largest non-background area, so the mode of the render is their
    # fill.
    var ink = _dominant_fill(c)
    var ratio = _contrast(ink, ground)
    assert_true(
        ratio >= 7.0,
        String(
            "high_contrast() mark ink is only "
            + String(ratio)
            + ":1 against the background; need >= 7.0"
        ),
    )

    var line_c = _line_canvas(high_contrast())
    var grid = Color(120, 120, 120)
    assert_true(
        _count_color(line_c, grid) > 200,
        "high_contrast() drew no gridlines in its own gridline color",
    )
    var g_ratio = _contrast(grid, ground)
    assert_true(
        g_ratio >= 3.0,
        String(
            "high_contrast() gridlines are only "
            + String(g_ratio)
            + ":1 against the background; need >= 3.0"
        ),
    )


def test_high_contrast_dashes_its_reference_lines() raises:
    """A reference line at (64, 64, 64) and this preset's mark ink at
    (0, 84, 166) are 8.1 Rec.709 luma levels apart -- obviously
    different in color, and the same line to anyone reading the chart by
    lightness rather than by hue. `annotation_line_style=DASHED` is what
    keeps "threshold" and "measurement" apart for that reader.

    A dashed rule crosses the plot as many separated runs; a solid one
    as a single run.
    """
    var c = _line_canvas(high_contrast())
    var ink = Color(64, 64, 64)
    var best = 0
    for y in range(c.height):
        var runs = _runs_in_row(c, y, ink)
        if runs > best:
            best = runs
    assert_true(
        best >= 8,
        String(
            "high_contrast() drew its reference line solid: the busiest row"
            " has only "
            + String(best)
            + " runs of the annotation color"
        ),
    )


def test_high_contrast_codes_categories_by_shape_as_well_as_hue() raises:
    """`shape_by_category` has to be on: a reader who cannot separate the
    palette's hues needs the marker outline to carry the same
    information. A circle and a square of equal nominal size cover
    different pixel counts, so the two categories' fills differ in area
    even though both are drawn at one `point_radius`.
    """
    var c = _scatter_canvas(high_contrast())
    # `_scatter_canvas` draws three marks in each of the first two
    # palette colors. `default_marker_shapes()` gives the first category
    # a circle and the second a square, and a square of side `2r` covers
    # `4/pi` (1.27x) the area of a circle of radius `r`, so equal-ish
    # counts mean one shape was used for both.
    var circles = _count_color(c, Color(31, 119, 180))
    var squares = _count_color(c, Color(255, 127, 14))
    assert_true(circles > 0, "no first-category marks drawn")
    assert_true(squares > 0, "no second-category marks drawn")
    assert_true(
        Float64(squares) > 1.2 * Float64(circles),
        String(
            "high_contrast() drew both categories as the same shape ("
            + String(circles)
            + " px against "
            + String(squares)
            + "): shape_by_category is not on"
        ),
    )


# ---------------------------------------------------------------
# minimal(): what it removes, and what it must not.


def test_minimal_removes_gridlines() raises:
    """The same chart under both themes: the default draws ~2350 px of
    gridline, `minimal()` draws none.

    The bar is 50 rather than 0 because a handful of pixels elsewhere in
    the chart (the annotation band's edge over the faded axis) average
    to the default gridline gray by coincidence -- 13 of them here. A
    real gridline is two orders of magnitude above that, so the
    threshold discriminates while staying immune to a layout nudge.
    """
    var c_default = _line_canvas(Theme())
    var c_minimal = _line_canvas(minimal())
    var grid = Theme().gridline_color
    var n_default = _count_color(c_default, grid)
    assert_true(
        n_default > 1000,
        String(
            "fixture no longer draws default gridlines ("
            + String(n_default)
            + " px); the assertion below would be vacuous"
        ),
    )
    var n_minimal = _count_color(c_minimal, grid)
    assert_true(
        n_minimal < 50,
        String(
            "minimal() still drew gridlines: "
            + String(n_minimal)
            + " px of the default gridline color, against "
            + String(n_default)
            + " for the default theme"
        ),
    )


def test_minimal_keeps_the_legend() raises:
    """The obvious "minimal" move is to drop the legend too, and it is
    the wrong one: it deletes the mapping from color to category.

    A category's palette color is drawn twice -- as data points and as a
    legend swatch -- so counting pixels cannot tell the two apart. The
    swatch is `legend_swatch_size` (14) px on a side and a point mark is
    `2 * point_radius` (7), so the longest horizontal run of that color
    separates them without depending on where either landed. Measured:
    14 with the legend on.
    """
    var c = _scatter_canvas(minimal())
    var run = _longest_run_in_row(c, Color(44, 160, 44))
    assert_true(
        run >= 10,
        String(
            "minimal() drew no legend swatch: the longest run of the third"
            " category's color is "
            + String(run)
            + " px, which is a data point, not a 14 px swatch"
        ),
    )


def test_minimal_keeps_tick_labels_at_full_strength() raises:
    """Fading the axis is the point; fading the numbers on it is not.
    With the gridlines gone the tick labels are the only remaining way
    to read a value, so `text_color` has to stay dark while
    `axis_color` goes light.
    """
    var c = _line_canvas(minimal())
    var text = Color(55, 55, 55)
    var axis = Color(170, 170, 170)
    assert_true(
        _count_color(c, text) > 50,
        "minimal() drew no tick/label text in its own text color",
    )
    assert_true(
        _contrast(text, BG) > 3.0 * _contrast(axis, BG),
        String(
            "minimal() faded its text along with its axis: text is "
            + String(_contrast(text, BG))
            + ":1 and the axis "
            + String(_contrast(axis, BG))
            + ":1"
        ),
    )


# ---------------------------------------------------------------
# The API contract: a preset is a starting point, not a mode.


def test_a_preset_can_be_overridden_after_construction() raises:
    """`Theme`'s fields are plain `var`s, so overriding a preset is
    assignment. Both halves matter: the override has to take, *and* the
    other 55 fields have to survive it -- a `with_*` shape that returned
    a fresh default-constructed `Theme` would pass the first assertion
    and fail the second.
    """
    var t = dark()
    t.mark_color = Color(255, 0, 128)
    t.show_gridlines = False

    var c = _line_canvas(t)
    assert_true(
        _count_color(c, Color(255, 0, 128)) > 50,
        "the mark_color override did not reach the render",
    )
    assert_equal(
        _count_color(c, Color(52, 56, 64)),
        0,
        "show_gridlines=False did not reach the render",
    )
    assert_equal(
        c.get_pixel(1, 1).r,
        UInt8(24),
        "overriding one field reset dark()'s background",
    )
    assert_equal(
        t.subtitle_color.r,
        UInt8(158),
        "overriding one field reset dark()'s subtitle_color",
    )


def test_every_preset_changes_the_render() raises:
    """The cheap end of the sweep: each preset must differ from the
    default theme's render of the same chart, which catches a preset
    that returns `Theme()` or that is never wired into `.theme()`.
    """
    var base = _line_canvas(Theme())
    var names: List[String] = ["dark", "minimal", "high_contrast", "print_safe"]
    var others = List[Canvas]()
    others.append(_line_canvas(dark()))
    others.append(_line_canvas(minimal()))
    others.append(_line_canvas(high_contrast()))
    others.append(_line_canvas(print_safe()))

    for i in range(len(others)):
        var differs = False
        for y in range(0, base.height, 3):
            for x in range(0, base.width, 3):
                var a = base.get_pixel(x, y)
                var b = others[i].get_pixel(x, y)
                if a.r != b.r or a.g != b.g or a.b != b.b:
                    differs = True
                    break
            if differs:
                break
        assert_true(
            differs, names[i] + "() renders identically to the default theme"
        )


def test_dark_is_the_only_preset_that_moves_the_ground() raises:
    """A sanity check on the four as a set: `dark()` is defined by its
    background and the other three are defined against a light one, so a
    preset that accidentally inherited `dark()`'s background (a
    copy-paste this file is otherwise blind to) shows up here.
    """
    assert_true(
        _luma(dark().background) < 60.0,
        "dark() is not dark",
    )
    var light: List[Theme] = [minimal(), high_contrast(), print_safe()]
    var names: List[String] = ["minimal", "high_contrast", "print_safe"]
    for i in range(len(light)):
        assert_true(
            _luma(light[i].background) > 200.0,
            names[i] + "() is built on a dark ground; only dark() should be",
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
