from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame
from std.utils.numerics import isfinite

from dataviz.core.frame_input import _frame_floats, _frame_strings

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import ColorScale
from dataviz.plot import (
    Plot,
    _Orientation,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel_f,
    _draw_categorical_axis_frame,
    _pull_off_axis_line_f,
    snap_to_pixel_center,
    snap_to_pixel_edge,
    _finished,
    _require_non_empty,
    _zero_baseline_y_extent,
)
from dataviz.core.scale import (
    LinearScale,
    _format_fixed,
    _format_tick,
    _label_decimals,
)
from dataviz.categorical.gantt import (
    _draw_horizontal_categorical_axis_frame,
)
from dataviz.core.ordinal_scale import OrdinalScale
from dataviz.core.theme import Theme


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
    rather than `_tooltip_label` (core/tooltip_labels.mojo) because a bullet row encodes
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


def _validate_bullet_encoding(plot: Plot) raises:
    """The length and shape checks both bullet renders make
    before laying anything out (#686 split this out so the
    horizontal render makes the same ones, not a copy)."""
    if (
        len(plot._categorical.x) != len(plot._bullet.measure)
        or len(plot._bullet.target) != len(plot._bullet.measure)
        or len(plot._bullet.ranges) != len(plot._bullet.measure)
    ):
        raise Error(
            "Plot.encode_bullet(): categories, measures, targets, and"
            " ranges must all have the same length (got "
            + String(len(plot._categorical.x))
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
                + plot._categorical.x[i]
                + "' has no range thresholds -- a bullet chart needs at"
                " least one qualitative range"
            )
        for j in range(1, len(plot._bullet.ranges[i])):
            if plot._bullet.ranges[i][j] < plot._bullet.ranges[i][j - 1]:
                raise Error(
                    "Plot.encode_bullet(): category '"
                    + plot._categorical.x[i]
                    + "' has non-ascending range thresholds -- each"
                    " threshold must be >= the one before it"
                )

    _require_non_empty(len(plot._categorical.x), "Plot.encode_bullet()")


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
    _validate_bullet_encoding(plot)
    var theme = plot._theme
    var domain_data = List[Float64]()
    for i in range(len(plot._categorical.x)):
        domain_data.append(0.0)
        domain_data.append(
            plot._bullet.ranges[i][len(plot._bullet.ranges[i]) - 1]
        )
        domain_data.append(plot._bullet.measure[i])
        domain_data.append(plot._bullet.target[i])
    var y_scale = _zero_baseline_y_extent(domain_data)

    var frame = _draw_categorical_axis_frame(
        target,
        plot._categorical.x,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_bullet_rows(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        Float64(frame.py1),
        _Orientation(False),
        frame.text_requests,
    )
    return frame.result()


def _draw_bullet_rows[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    value_scale: LinearScale,
    band_scale: OrdinalScale,
    baseline: Float64,
    orient: _Orientation,
    mut text_requests: List[_TextRequest],
) raises:
    """Draw one bullet row per category -- its qualitative bands, its
    measure bar and its target marker -- in whichever orientation
    `orient` names (#686).

    Its own function, as `_draw_waterfall_bars` is, so the vertical and
    horizontal renders share the geometry. All three elements go
    through `_Orientation`: the bands and the measure through
    `fill_band_rect`, the target marker through `band_line`, which is
    the helper for a line running across the band at a fixed value.

    Args:
        target: Where to draw.
        plot: The chart.
        value_scale: The continuous scale for measures and thresholds.
        band_scale: The ordinal scale for categories.
        baseline: The zero line's pixel on the value axis.
        orient: Which way the bands run.
        text_requests: Collects the data labels.

    Raises:
        Error: Whatever the target's draw calls raise.
    """
    var theme = plot._theme
    var range_color_scale = ColorScale(0.0, 1.0)
    range_color_scale.add_stop(0.0, theme.bullet_range_color_light)
    range_color_scale.add_stop(1.0, theme.bullet_range_color_dark)

    # These depend only on the scale and theme, so they're computed once
    # outside the per-category loop.
    var bandwidth = band_scale.bandwidth()
    var measure_width = (
        bandwidth * plot._mark_style.bullet_measure_width_fraction
    )
    var measure_inset = (
        bandwidth * plot._mark_style.bullet_measure_width_fraction / 2.0
    )
    var baseline_py = _axis_pixel_f(value_scale, 0.0)
    var sc = _Scaled(theme)

    var tooltips_on = plot._tooltips_on(len(plot._categorical.x))
    for i in range(len(plot._categorical.x)):
        var band_x = band_scale.band_start(i)
        var band_x1 = band_x + bandwidth
        var band_count = len(plot._bullet.ranges[i])

        var prev_threshold = 0.0
        for j in range(band_count):
            var t = (
                Float64(j) / Float64(band_count - 1) if band_count > 1 else 0.0
            )
            var band_color = range_color_scale.color_at(t)
            var top_py = _axis_pixel_f(value_scale, plot._bullet.ranges[i][j])
            var bottom_py = _axis_pixel_f(value_scale, prev_threshold)
            var band_rect = _pull_off_axis_line_f(top_py, bottom_py, baseline)
            orient.fill_band_rect(
                target, band_rect, band_x, bandwidth, band_color
            )
            prev_threshold = plot._bullet.ranges[i][j]

        var measure_x = band_scale.center(i) - measure_inset
        var measure_py = _axis_pixel_f(value_scale, plot._bullet.measure[i])
        var measure_rect = _pull_off_axis_line_f(
            baseline_py, measure_py, baseline
        )
        if tooltips_on:
            # Measure and target together: a bullet chart's whole point is
            # the one against the other, so reading either alone off the
            # hover text would miss what the row is saying. The range
            # bands are background and stay outside the group.
            target.begin_annotated_group(
                _bullet_tooltip_label(
                    plot._categorical.x[i],
                    plot._bullet.measure[i],
                    plot._bullet.target[i],
                )
            )
        orient.fill_band_rect(
            target, measure_rect, measure_x, measure_width, theme.mark_color
        )
        if theme.show_data_labels:
            var measure = plot._bullet.measure[i]
            var at = orient.outside_band_label(
                measure_rect,
                band_x,
                bandwidth,
                measure < 0.0,
                sc.label_gap,
                sc.font_size,
            )
            text_requests.append(
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

        var target_py = _axis_pixel_f(value_scale, plot._bullet.target[i])
        orient.band_line(
            target,
            target_py,
            band_x,
            band_x1,
            theme.axis_color,
            theme.scale,
        )
        if tooltips_on:
            target.end_annotated_group()


def _render_horizontal_bullet[
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
    """`_render_bullet`'s mirror image for
    `Plot.mark_bullet(horizontal=True)` (#686): the categories run down
    the page and the measures rightward, on
    `_draw_horizontal_categorical_axis_frame` (gantt.mojo).

    This is the orientation a bullet chart usually wants -- the form
    reads as a row of progress bars against their targets, and the KPI
    names that label the rows are the long strings a vertical
    categorical axis crowds.
    """
    _validate_bullet_encoding(plot)
    var theme = plot._theme
    var domain_data = List[Float64]()
    for i in range(len(plot._categorical.x)):
        domain_data.append(0.0)
        domain_data.append(
            plot._bullet.ranges[i][len(plot._bullet.ranges[i]) - 1]
        )
        domain_data.append(plot._bullet.measure[i])
        domain_data.append(plot._bullet.target[i])
    var value_scale = _zero_baseline_y_extent(domain_data)
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
        value_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_bullet_rows(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        Float64(frame.px0),
        _Orientation(True),
        frame.text_requests,
    )
    return frame.result()


def bullet[
    dtype: DType
](
    categories: List[String],
    measures: List[Scalar[dtype]],
    targets: List[Scalar[dtype]],
    ranges: List[List[Float64]],
    measure_width_fraction: Float64 = 0.35,
    horizontal: Bool = False,
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
        horizontal: Whether the categories run down the page and the
            measures rightward; defaults to `False`. Usually the form
            you want: the rows read as progress bars against their
            targets, and KPI names are long.
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
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Every row shares one unit: percent of orders shipped on time.
            # Qualitative ranges mark needs-attention, acceptable, and strong.
            var regions: List[String] = [
                "Northeast", "Midwest", "South", "Mountain", "Pacific",
            ]
            var measures: List[Int] = [94, 87, 91, 82, 96]
            var targets: List[Int] = [95, 92, 93, 90, 95]
            var ranges: List[List[Float64]] = [
                [80.0, 90.0, 100.0],
                [80.0, 90.0, 100.0],
                [80.0, 90.0, 100.0],
                [80.0, 90.0, 100.0],
                [80.0, 90.0, 100.0],
            ]

            var c = bullet(
                regions,
                measures,
                targets,
                ranges,
                title="Illustrative On-Time Fulfillment by Region",
                x_title="Orders shipped on time (%)",
            )
            save(c, "docs/src/examples/out_bullet.svg")
        ```
    """
    var measures_f = _materialize_scalar_list(measures)
    var targets_f = _materialize_scalar_list(targets)
    var plot = (
        Plot()
        .mark_bullet(
            measure_width_fraction=measure_width_fraction,
            horizontal=horizontal,
        )
        .encode_bullet(
            categories=categories,
            measures=measures_f,
            targets=targets_f,
            ranges=ranges,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def _require_finite_bullet_frame_column(
    values: List[Float64], name: String
) raises:
    for row in range(len(values)):
        if not isfinite(values[row]):
            raise Error(
                'bullet(): column "'
                + name
                + '" has a non-finite value at row '
                + String(row)
            )


def bullet(
    df: DataFrame,
    categories: String,
    measures: String,
    targets: String,
    ranges: List[String],
    measure_width_fraction: Float64 = 0.35,
    horizontal: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Draw a bullet chart from named DataFrame columns.

    Each row is one category. `ranges` names numeric threshold columns
    in increasing order, so every row has its own qualitative bands.
    Numeric values must be present for each row.

    Args:
        df: The frame holding one row per category.
        categories: String column naming each category.
        measures: Numeric column of observed values.
        targets: Numeric column of goal values.
        ranges: Nonempty ordered list of numeric threshold columns.
        measure_width_fraction: See the list overload.
        horizontal: See the list overload.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.
        y_title: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A required column is missing, has the wrong dtype, has
            missing numeric values, or a range is out of order.
    """
    if len(ranges) == 0:
        raise Error("bullet(): ranges must name at least one column")
    var category_values = _frame_strings(
        df,
        categories,
        "bullet()",
        theme.missing,
        theme.missing_category_label,
    )
    var measure_values = _frame_floats(df, measures, "bullet()")
    var target_values = _frame_floats(df, targets, "bullet()")
    _require_finite_bullet_frame_column(measure_values, measures)
    _require_finite_bullet_frame_column(target_values, targets)
    var range_columns = List[List[Float64]](capacity=len(ranges))
    for name in ranges:
        var thresholds = _frame_floats(df, name, "bullet()")
        _require_finite_bullet_frame_column(thresholds, name)
        range_columns.append(thresholds^)
    var row_ranges = List[List[Float64]](capacity=len(category_values))
    for row in range(len(category_values)):
        var thresholds = List[Float64](capacity=len(range_columns))
        for col in range_columns:
            thresholds.append(col[row])
        row_ranges.append(thresholds^)
    return bullet(
        categories=category_values,
        measures=measure_values,
        targets=target_values,
        ranges=row_ranges,
        measure_width_fraction=measure_width_fraction,
        horizontal=horizontal,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else categories,
        y_title=y_title if y_title.byte_length() > 0 else measures,
    )
