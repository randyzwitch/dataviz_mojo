from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import ColorScale
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _empty_result,
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
)
from dataviz_mojo.theme import Theme


struct _BulletData(Movable):
    """
    Mark.BULLET only -- one measure/target pair, plus a whole list of
    ascending qualitative-range thresholds, per category. See
    encode_bullet()'s docstring.

    Grouped onto `Plot._bullet` -- see `Plot`'s docstring.
    """

    var measure: List[Float64]
    var target: List[Float64]
    var ranges: List[List[Float64]]

    def __init__(out self):
        self.measure = List[Float64]()
        self.target = List[Float64]()
        self.ranges = List[List[Float64]]()



def _render_bullet[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.BULLET` plot (Stephen Few's bullet-chart design):
    `_draw_categorical_axis_frame`'s shared categorical x-axis, with a
    zero-baseline y-domain (`_zero_baseline_y_extent`, like `Mark.BAR`/
    `LOLLIPOP`/`WATERFALL` -- not `Mark.BOX`/`CANDLESTICK`'s padded-around-the-data domain: a bullet chart's whole premise is
    *progress toward a goal from zero*, the same "magnitude from a
    baseline" meaning a bar's height encodes, so zero has to stay in
    view the same way). The domain spans every value actually drawn per
    category -- `0.0`, the top of its `ranges` (the tallest
    background band), its `measure`, and its `target` -- the same
    domain-fits-everything approach `Mark.BOX`/`WATERFALL` take, since
    a measure or target can legitimately fall outside the qualitative
    ranges (e.g. exceeding the "good" threshold).

    Draws, per category, back to front (the same layering order `Mark.
    BOX`'s whisker-then-box-then-median gives, generalized: context
    underneath, the headline value over it, a reference mark on top of
    everything):
    1. Every qualitative range band, stacked from `0.0` up through each
       of `ranges`' ascending thresholds in turn (`fill_rect`, full
       band width, matching `Mark.BAR`/`BOX`'s "no extra narrowing"
       choice) -- shaded via a small `ColorScale` built once from
       `Theme.bullet_range_color_light`/`bullet_range_color_dark` (the
       *same* stop-interpolation machinery `Plot.encode(color=...)`'s continuous channel uses, projecting each band's index
       fraction onto `[0, 1]` instead of a data value), lightest at
       index 0 through darkest at the top -- Few's convention, and
       why these are dedicated grayscale `Theme` fields rather than
       reusing `mark_color`-derived shades (a background band should
       read as neutral context, not compete with the measure bar for
       "this is the colored one" attention).
    2. The measure bar (`fill_rect`, `theme.mark_color`, `theme.
       bullet_measure_width_fraction` of the full band width and
       centered within it -- narrower on purpose, so it reads as a distinct
       overlaid layer rather than just another, taller range band).
       Deliberately *never* colored by sign (no `mark_color_negative`
       involved at all, unlike `Mark.CANDLESTICK`/`WATERFALL`) -- a
       bullet chart's whole comparison is measure-against-target-and-
       ranges, conveyed by *position*, not by the measure bar's color; Few's design keeps that bar one solid, neutral color
       for exactly this reason, and this package follows it rather than
       reusing the sign-coloring convention just because the fields
       already exist. A `measure` of exactly `0.0` draws a genuine
       zero-height (so invisible) bar, and deliberately isn't floored
       to 1px the way `Mark.CANDLESTICK`'s doji case is -- a doji needs
       a visible mark because it's real, informative market data at a
       specific price; a zero measure means literally "no progress
       yet," which an absent bar already represents correctly.
    3. The target tick (`draw_line_aa`, `theme.axis_color` -- matching
       `Mark.BOX`'s whisker/median color, both being "the part of
       the shape that isn't the headline value" -- full band width,
       exactly `Mark.BOX`'s median-line convention), drawn last so
       it's never obscured by either the bands or the measure bar under
       it.
    """
    if (
        len(plot.x_categories) != len(plot._bullet.measure)
        or len(plot._bullet.target) != len(plot._bullet.measure)
        or len(plot._bullet.ranges) != len(plot._bullet.measure)
    ):
        raise Error(
            "Plot.encode_bullet(): categories, measures, targets, and"
            " ranges must all have the same length (got "
            + String(len(plot.x_categories))
            + " categories, "
            + String(len(plot._bullet.measure))
            + " measures, "
            + String(len(plot._bullet.target))
            + " targets, "
            + String(len(plot._bullet.ranges))
            + " ranges)"
        )
    for i in range(len(plot._bullet.ranges)):
        if len(plot._bullet.ranges[i]) == 0:
            raise Error(
                "Plot.encode_bullet(): category '"
                + plot.x_categories[i]
                + "' has no range thresholds -- a bullet chart needs at"
                " least one qualitative range"
            )
        for j in range(1, len(plot._bullet.ranges[i])):
            if plot._bullet.ranges[i][j] < plot._bullet.ranges[i][j - 1]:
                raise Error(
                    "Plot.encode_bullet(): category '"
                    + plot.x_categories[i]
                    + "' has non-ascending range thresholds -- each"
                    " threshold must be >= the one before it"
                )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var domain_data = List[Float64]()
    for i in range(len(plot.x_categories)):
        domain_data.append(0.0)
        domain_data.append(plot._bullet.ranges[i][len(plot._bullet.ranges[i]) - 1])
        domain_data.append(plot._bullet.measure[i])
        domain_data.append(plot._bullet.target[i])
    var y_scale = _zero_baseline_y_extent(domain_data)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var range_color_scale = ColorScale(0.0, 1.0)
    range_color_scale.add_stop(0.0, theme.bullet_range_color_light)
    range_color_scale.add_stop(1.0, theme.bullet_range_color_dark)

    # Every one of these depends only on the scale and theme, never on
    # the category index -- computed once here, not recomputed inside
    # the per-category loop below.
    var bandwidth = frame.x_scale.bandwidth()
    var band_width = _round_to_int(bandwidth)
    var measure_width = _round_to_int(bandwidth * theme.bullet_measure_width_fraction)
    var measure_inset = bandwidth * theme.bullet_measure_width_fraction / 2.0
    var baseline_py = _axis_pixel(frame.y_scale, 0.0)

    for i in range(len(plot.x_categories)):
        var band_x = _round_to_int(frame.x_scale.band_start(i))
        var band_count = len(plot._bullet.ranges[i])

        var prev_threshold = 0.0
        for j in range(band_count):
            var t = Float64(j) / Float64(band_count - 1) if band_count > 1 else 0.0
            var band_color = range_color_scale.color_at(t)
            var top_py = _axis_pixel(frame.y_scale, plot._bullet.ranges[i][j])
            var bottom_py = _axis_pixel(frame.y_scale, prev_threshold)
            var band_rect = _pull_off_axis_line(top_py, bottom_py, frame.py1)
            target.fill_rect(band_x, band_rect.y, band_width, band_rect.height, band_color)
            prev_threshold = plot._bullet.ranges[i][j]

        var measure_x = _round_to_int(frame.x_scale.center(i) - measure_inset)
        var measure_py = _axis_pixel(frame.y_scale, plot._bullet.measure[i])
        var measure_rect = _pull_off_axis_line(baseline_py, measure_py, frame.py1)
        target.fill_rect(measure_x, measure_rect.y, measure_width, measure_rect.height, theme.mark_color)

        var target_py = _axis_pixel(frame.y_scale, plot._bullet.target[i])
        var band_end = band_x + band_width
        target.draw_line_aa(band_x, target_py, band_end, target_py, theme.axis_color, width=theme.scale)

    return frame.result()


def bullet(
    categories: List[String],
    measures: List[Float64],
    targets: List[Float64],
    ranges: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A bullet chart -- `Mark.BULLET` (Stephen Few's design): a
    measure bar, a target tick, and shaded qualitative-range bands
    per category. See `Plot.encode_bullet()`'s docstring
    (plot.mojo) for what `measures`/`targets`/`ranges` mean.

    Args:
        categories: One row per entry, in the given order.
        measures: Each category's actual value, drawn as the narrow
            measure bar.
        targets: Each category's goal value, drawn as a tick mark
            across the full band width.
        ranges: Each category's own list of ascending qualitative-
            range thresholds (poor/satisfactory/good, ...), drawn as
            shaded background bands from lightest to darkest.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.
    """
    var plot = Plot().mark_bullet().encode_bullet(
        categories=categories, measures=measures, targets=targets, ranges=ranges
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
