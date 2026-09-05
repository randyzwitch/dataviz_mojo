from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.geometry import round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
from dataviz.plot import (
    Plot,
    _Orientation,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _pull_off_axis_line,
    _finished,
    _require_non_empty,
    _zero_baseline_y_extent,
)
from dataviz.scale import _format_fixed, _format_tick, _label_decimals
from dataviz.theme import Theme


struct _BulletData(Copyable, Movable):
    """One measure/target pair plus a list of ascending qualitative-range
    thresholds per category, for `Mark.BULLET`. See `encode_bullet()`.
    Stored on `Plot._bullet`.
    """

    var measure: List[Float64]
    var target: List[Float64]
    var ranges: List[List[Float64]]

    def __init__(out self):
        self.measure = List[Float64]()
        self.target = List[Float64]()
        self.ranges = List[List[Float64]]()


def _bullet_tooltip_label(
    category: String, measure: Float64, target: Float64
) -> String:
    """One row's hover text: `"Revenue: 72 (target 80)"`. Its own helper
    rather than `_tooltip_label` (plot.mojo) because a bullet row encodes
    two numbers against each other, the way `Mark.BOX`'s tooltip carries
    its whole five-number summary.
    """
    return (
        category
        + ": "
        + _format_fixed(measure, _label_decimals(measure))
        + " (target "
        + _format_fixed(target, _label_decimals(target))
        + ")"
    )


def _render_bullet[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.BULLET` plot (Stephen Few's bullet chart) on
    `_draw_categorical_axis_frame` with a zero-baseline y-domain
    (`_zero_baseline_y_extent`) spanning `0.0`, each category's top range
    threshold, its `measure`, and its `target`.

    Per category, back to front:
    1. The qualitative range bands, stacked from `0.0` through `ranges`'
       ascending thresholds at full band width, shaded by a two-stop
       `ColorScale` from `theme.bullet_range_color_light` to
       `theme.bullet_range_color_dark`.
    2. The measure bar (`theme.mark_color`,
       `plot._mark_style.bullet_measure_width_fraction` of the band,
       centered). Never colored by sign; a `measure` of `0.0` draws a
       zero-height bar.
    3. The target tick (`theme.axis_color`, full band width), drawn last.
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

    _require_non_empty(len(plot.x_categories), "Plot.encode_bullet()")
    var theme = plot._theme
    var domain_data = List[Float64]()
    for i in range(len(plot.x_categories)):
        domain_data.append(0.0)
        domain_data.append(
            plot._bullet.ranges[i][len(plot._bullet.ranges[i]) - 1]
        )
        domain_data.append(plot._bullet.measure[i])
        domain_data.append(plot._bullet.target[i])
    var y_scale = _zero_baseline_y_extent(domain_data)

    var frame = _draw_categorical_axis_frame(
        target,
        plot.x_categories,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var range_color_scale = ColorScale(0.0, 1.0)
    range_color_scale.add_stop(0.0, theme.bullet_range_color_light)
    range_color_scale.add_stop(1.0, theme.bullet_range_color_dark)

    # These depend only on the scale and theme, so they're computed once
    # outside the per-category loop.
    var bandwidth = frame.x_scale.bandwidth()
    var band_width = round_to_int(bandwidth)
    var measure_width = round_to_int(
        bandwidth * plot._mark_style.bullet_measure_width_fraction
    )
    var measure_inset = (
        bandwidth * plot._mark_style.bullet_measure_width_fraction / 2.0
    )
    var baseline_py = _axis_pixel(frame.y_scale, 0.0)
    var sc = _Scaled(theme)
    var orient = _Orientation(False)  # Mark.BULLET has no horizontal variant

    for i in range(len(plot.x_categories)):
        var band_x = round_to_int(frame.x_scale.band_start(i))
        var band_count = len(plot._bullet.ranges[i])

        var prev_threshold = 0.0
        for j in range(band_count):
            var t = (
                Float64(j) / Float64(band_count - 1) if band_count > 1 else 0.0
            )
            var band_color = range_color_scale.color_at(t)
            var top_py = _axis_pixel(frame.y_scale, plot._bullet.ranges[i][j])
            var bottom_py = _axis_pixel(frame.y_scale, prev_threshold)
            var band_rect = _pull_off_axis_line(top_py, bottom_py, frame.py1)
            target.fill_rect(
                band_x, band_rect.y, band_width, band_rect.height, band_color
            )
            prev_threshold = plot._bullet.ranges[i][j]

        var measure_x = round_to_int(frame.x_scale.center(i) - measure_inset)
        var measure_py = _axis_pixel(frame.y_scale, plot._bullet.measure[i])
        var measure_rect = _pull_off_axis_line(
            baseline_py, measure_py, frame.py1
        )
        if theme.svg_tooltips:
            # Measure and target together: a bullet chart's whole point is
            # the one against the other, so reading either alone off the
            # hover text would miss what the row is saying. The range
            # bands are background and stay outside the group.
            target.begin_annotated_group(
                _bullet_tooltip_label(
                    plot.x_categories[i],
                    plot._bullet.measure[i],
                    plot._bullet.target[i],
                )
            )
        target.fill_rect(
            measure_x,
            measure_rect.y,
            measure_width,
            measure_rect.height,
            theme.mark_color,
        )
        if theme.show_data_labels:
            var measure = plot._bullet.measure[i]
            var at = orient.outside_band_label(
                measure_rect,
                band_x,
                band_width,
                measure < 0.0,
                sc.label_gap,
                sc.font_size,
            )
            frame.text_requests.append(
                _TextRequest(
                    at.x,
                    at.y,
                    _format_tick(
                        measure, _label_decimals(measure), theme.y_tick_format
                    ),
                    theme.text_color,
                    sc.font_size,
                    at.align,
                    theme.font_family,
                )
            )

        var target_py = _axis_pixel(frame.y_scale, plot._bullet.target[i])
        var band_end = band_x + band_width
        target.draw_line_aa(
            band_x,
            target_py,
            band_end,
            target_py,
            theme.axis_color,
            width=theme.scale,
        )
        if theme.svg_tooltips:
            target.end_annotated_group()

    return frame.result()


def bullet(
    categories: List[String],
    measures: List[Float64],
    targets: List[Float64],
    ranges: List[List[Float64]],
    measure_width_fraction: Float64 = 0.35,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A bullet chart, Stephen Few's compact alternative to a dashboard
    gauge: a single measure bar against qualitative range bands and a
    target tick, for tracking a KPI against a goal without a
    speedometer's wasted space.

    `Mark.BULLET` (Stephen Few's design): a measure bar, a target tick,
    and shaded qualitative-range bands per category. See
    `Plot.encode_bullet()` (plot.mojo) for what `measures`/`targets`/
    `ranges` mean.

    Args:
        categories: One row per entry, in the given order.
        measures: Each category's actual value, drawn as the narrow
            measure bar.
        targets: Each category's goal value, drawn as a tick mark
            across the full band width.
        ranges: Each category's own list of ascending qualitative-
            range thresholds (poor/satisfactory/good, ...), drawn as
            shaded background bands from lightest to darkest.
        measure_width_fraction: The measure bar's thickness as a fraction of the band
            width; defaults to `0.35`.
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

    Example:
        ```mojo
        from dataviz import bullet
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var kpis: List[String] = ["Revenue", "Profit", "New Customers", "Satisfaction"]
            var measures: List[Int] = [72, 58, 85, 78]
            var targets: List[Int] = [80, 65, 70, 90]
            var ranges: List[List[Float64]] = [
                [50.0, 75.0, 100.0],
                [40.0, 70.0, 100.0],
                [30.0, 60.0, 100.0],
                [60.0, 85.0, 100.0],
            ]

            var c = bullet(kpis, measures, targets, ranges)
            save(c, "docs/src/examples/out_bullet.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_bullet(
            measure_width_fraction=measure_width_fraction,
        )
        .encode_bullet(
            categories=categories,
            measures=measures,
            targets=targets,
            ranges=ranges,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def bullet[
    dtype: DType
](
    categories: List[String],
    measures: List[Scalar[dtype]],
    targets: List[Scalar[dtype]],
    ranges: List[List[Float64]],
    measure_width_fraction: Float64 = 0.35,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`bullet()` generalized over numeric element type for `measures`/
    `targets` (sharing one dtype); see `scatter()`'s `DType` overload
    (plot.mojo). `ranges` stays a concrete `List[List[Float64]]` (#158).
    Delegates to the concrete overload above.
    """
    return bullet(
        categories,
        _materialize_scalar_list(measures),
        _materialize_scalar_list(targets),
        ranges,
        measure_width_fraction=measure_width_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
