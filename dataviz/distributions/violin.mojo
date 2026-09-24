from dataviz.core.plot_fields import (
    _CategoricalData,
    _DistributionData,
    _MarkStyle,
    _ContinuousData,
)
from dataviz.core.chart_settings import _ChartSettings
from std.math import exp, pi, sqrt

from canvas.text.font_cache import FontCache
from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_groups
from dataviz.core.array_like import _materialize_nested_scalar_list
from dataviz.categorical.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.distributions.kde import _KDE_SAMPLES, _kde_bandwidth, _kde_density
from dataviz.core.ordinal_scale import OrdinalScale
from dataviz.plot import Plot, _finished
from dataviz.core.frame import (
    _Orientation,
    _axis_pixel_f,
    _draw_categorical_axis_frame,
)
from dataviz.core.render_result import _RenderResult
from dataviz.core.extent import _data_extent
from dataviz.core.scale import (
    _min_max,
    LinearScale,
    _format_fixed,
    _label_decimals,
)
from dataviz.core.theme import Theme
from dataviz.core.validate import _require_non_empty
from dataviz.core.mark import Mark, _require_mark


def _draw_violin_silhouettes[
    T: DrawTarget
](
    mut target: T,
    categorical: _CategoricalData,
    distribution: _DistributionData,
    style: _MarkStyle,
    settings: _ChartSettings,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    orient: _Orientation,
) raises:
    """Every category's KDE silhouette, written once for both orientations;
    `_Orientation.path_move_to`/`path_line_to` carry the only difference
    (which coordinate is x and which is y).

    Each silhouette is one closed `Path`: `_KDE_SAMPLES` points up one
    side at `center + density * scale`, then the same samples back down
    the other at `center - density * scale`, symmetric about the band's
    center.

    Each violin is scaled independently: its own peak density maps to
    `mark_violin(width_fraction=...)` of its band. `scale_by_count=True`
    multiplies that maximum by
    `sqrt(n_i / max(n))` (`scale = "area"`).

    An all-identical category (`span == 0`) samples the same value
    `_KDE_SAMPLES` times; a zero `max_density` collapses `scale` to `0.0`
    rather than producing NaN.
    """
    var theme = settings.theme
    var max_n = 0
    for series in distribution.values:
        if len(series) > max_n:
            max_n = len(series)
    var half_extent = band_scale.bandwidth() * style.violin_width_fraction

    var tooltips_on = settings.tooltips_on(len(categorical.x))
    for i in range(len(categorical.x)):
        var values = distribution.values[i].copy()
        var center = band_scale.center(i)
        var count_factor = sqrt(Float64(len(values)) / Float64(max_n)) if (
            distribution.kde_scale_by_count and max_n > 0
        ) else 1.0
        var bandwidth = (
            distribution.kde_bandwidth_override if distribution.kde_bandwidth_override
            > 0.0 else _kde_bandwidth(values)
        )
        var mm = _min_max(values)

        var densities = List[Float64](capacity=_KDE_SAMPLES)
        var sample_values = List[Float64](capacity=_KDE_SAMPLES)
        var max_density = 0.0
        var span = mm.max - mm.min
        for s in range(_KDE_SAMPLES):
            var v = mm.min if span == 0.0 else mm.min + span * Float64(
                s
            ) / Float64(_KDE_SAMPLES - 1)
            var d = _kde_density(values, bandwidth, v)
            sample_values.append(v)
            densities.append(d)
            max_density = max(max_density, d)

        if tooltips_on:
            # A silhouette encodes a distribution, not a value, so the hover text
            # is what shaped it: how many points and over what range.
            target.begin_annotated_group(
                categorical.x[i]
                + ": n="
                + String(len(values))
                + ", range "
                + _format_fixed(mm.min, _label_decimals(mm.min))
                + "-"
                + _format_fixed(mm.max, _label_decimals(mm.max))
            )
        var path = Path()
        var scale = (
            half_extent * count_factor
        ) / max_density if max_density > 0.0 else 0.0
        orient.path_move_to(
            path,
            _axis_pixel_f(value_scale, sample_values[0]),
            center + densities[0] * scale,
        )
        for s in range(1, _KDE_SAMPLES):
            orient.path_line_to(
                path,
                _axis_pixel_f(value_scale, sample_values[s]),
                center + densities[s] * scale,
            )
        for s in range(_KDE_SAMPLES - 1, -1, -1):
            orient.path_line_to(
                path,
                _axis_pixel_f(value_scale, sample_values[s]),
                center - densities[s] * scale,
            )
        path.close()
        target.fill_path_aa(path, theme.mark_color, fill_rule=FillRule.NONZERO)
        if tooltips_on:
            target.end_annotated_group()


def _render_violin[
    T: DrawTarget
](
    mut target: T,
    categorical: _CategoricalData,
    distribution: _DistributionData,
    style: _MarkStyle,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.VIOLIN` plot: `encode_distribution()`'s raw
    per-category values (the same data `Mark.BEESWARM` takes), each
    category drawn as a symmetric density-estimate silhouette.

    Each violin is sampled at `_KDE_SAMPLES` evenly spaced points across
    its category's own `[min(values), max(values)]`, not the shared axis
    domain, so the shape spans exactly the observed range. Width scaling
    and the `bandwidth`/`scale_by_count` overrides are described in
    `_draw_violin_silhouettes`. `bandwidth` must be positive when given.

    Reuses `_draw_categorical_axis_frame` with `_data_extent` over every
    value across every category, the same domain choice `Mark.BOX`/
    `BEESWARM` make.
    """
    var theme = settings.theme
    if distribution.kde_bandwidth_override < 0.0:
        raise Error(
            "Plot.mark_violin(): bandwidth must be positive (got "
            + String(distribution.kde_bandwidth_override)
            + ")"
        )

    var all_values = List[Float64]()
    for series in distribution.values:
        for v in series:
            all_values.append(v)
    var value_scale = _data_extent(all_values)

    var frame = _draw_categorical_axis_frame(
        target,
        categorical.x,
        value_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_violin_silhouettes(
        target,
        categorical,
        distribution,
        style,
        settings,
        frame.x_scale,
        frame.y_scale,
        _Orientation(False),
    )

    return frame.result()


def _render_horizontal_violin[
    T: DrawTarget
](
    mut target: T,
    categorical: _CategoricalData,
    distribution: _DistributionData,
    style: _MarkStyle,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """`_render_violin`'s mirror image for
    `Plot.mark_violin(horizontal=True)`: `_render_horizontal_bar`'s
    categorical y-axis / continuous x-axis
    (`_draw_horizontal_categorical_axis_frame`, gantt.mojo), each
    silhouette sampled along `x_scale` and bulging vertically around its
    row's center. The KDE computation is identical. Its own function
    rather than an orientation flag, for the reasons in
    `_render_horizontal_bar`'s docstring (bar.mojo).
    """
    var theme = settings.theme
    if distribution.kde_bandwidth_override < 0.0:
        raise Error(
            "Plot.mark_violin(): bandwidth must be positive (got "
            + String(distribution.kde_bandwidth_override)
            + ")"
        )

    var all_values = List[Float64]()
    for series in distribution.values:
        for v in series:
            all_values.append(v)
    var value_scale = _data_extent(all_values)

    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        categorical.x,
        value_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_violin_silhouettes(
        target,
        categorical,
        distribution,
        style,
        settings,
        frame.y_scale,
        frame.x_scale,
        _Orientation(True),
    )

    return frame.result()


def violin(
    df: DataFrame,
    category: String,
    value: String,
    bandwidth: Float64 = 0.0,
    scale_by_count: Bool = False,
    width_fraction: Float64 = 0.4,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`violin()` over a long-form `dataframe_mojo` `DataFrame` (#743):
    one row per observation, with `category` naming each row's group and
    `value` holding the number.

    A frame stores these long while the mark wants one list per
    category, so the rows are bucketed by `category`, in first-appearance
    order. The axis titles default to the two column names.

    Args:
        df: The frame to read.
        category: The string column naming each observation's group.
        value: The numeric column holding the observations.
        bandwidth: Kernel bandwidth; see the list overload.
        scale_by_count: Scale each violin by its sample count.
        width_fraction: Each violin's share of its band.
        theme: Full styling knobs beyond this function's own parameters.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A line under the title.
        x_title: The x-axis caption; defaults to `category`.
        y_title: The y-axis caption; defaults to `value`.
        horizontal: Draw the categories down the y axis instead.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for its
            channel, or has missing values.
    """
    var groups = _frame_groups(
        df,
        category,
        value,
        "violin()",
        theme.missing,
        theme.missing_category_label,
    )
    return violin(
        groups[0],
        groups[1],
        bandwidth=bandwidth,
        scale_by_count=scale_by_count,
        width_fraction=width_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else category,
        y_title=y_title if y_title.byte_length() > 0 else value,
        horizontal=horizontal,
    )


def violin[
    dtype: DType
](
    categories: List[String],
    values: List[List[Scalar[dtype]]],
    bandwidth: Float64 = 0.0,
    scale_by_count: Bool = False,
    width_fraction: Float64 = 0.4,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """A violin plot: a box plot's summary combined with a mirrored
    kernel-density-estimate silhouette per category, for seeing a
    distribution's actual shape (multiple modes, skew) that a box plot
    alone would hide.

    `Mark.VIOLIN`: a symmetric kernel-density-estimate silhouette per
    category. `bandwidth` (when positive) overrides every category's
    Silverman's-rule bandwidth with one shared value; `scale_by_count=True`
    scales each category by its count (see `Plot.mark_violin()`). See `Plot.encode_distribution()` (plot.mojo)
    for the data shape, shared with `beeswarm()`/`ridgeline()`.

    Args:
        categories: One silhouette per entry, in the given order.
        values: Each category's raw values (`values[i]`) -- the
            density estimate is computed from these, not passed in
            directly.
        bandwidth: Overrides every category's Silverman's-rule
            kernel-density bandwidth with one shared value; must be
            positive if given. Left at its default `0.0`, each
            category gets its own Silverman's-rule bandwidth.
        scale_by_count: `False` (the default) gives every category's peak
            the same maximum width; `True` additionally scales a
            category's maximum width by `sqrt(n_i / max(n))`, so one
            built from fewer raw values draws visibly narrower.
        width_fraction: Each violin's maximum half-width as a fraction of its band
            width; defaults to `0.4`.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.
        horizontal: Draw categories running top-to-bottom with each
            silhouette bulging up-down around its own row instead of
            the default vertical layout -- see `Plot.mark_violin()`'s
            own docstring.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import violin
        from dataviz import save

        def main() raises:
            var regions: List[String] = ["US East", "EU West", "Asia Pacific"]
            # The same illustrative latency sample used by box() and
            # beeswarm(), here emphasizing each region's distribution shape.
            var latency_ms: List[List[Int]] = [
                [68, 72, 75, 71, 69, 74, 78, 73, 70, 76, 82, 77, 71, 69, 80, 74, 72, 75, 118, 67],
                [96, 102, 108, 99, 104, 111, 106, 101, 98, 115, 109, 103, 107, 100, 113, 105, 97, 110, 146, 102],
                [154, 162, 171, 158, 166, 179, 173, 160, 168, 181, 176, 164, 170, 157, 184, 169, 161, 175, 238, 165],
            ]

            var c = violin(
                regions,
                latency_ms,
                title="Illustrative API Latency by Region",
                x_title="Region",
                y_title="Latency (ms)",
            )
            save(c, "docs/src/examples/out_violin.svg")
        ```
    """
    var values_f = _materialize_nested_scalar_list(values)
    var plot = (
        Plot()
        .mark_violin(
            bandwidth=bandwidth,
            scale_by_count=scale_by_count,
            horizontal=horizontal,
            width_fraction=width_fraction,
        )
        .encode_distribution(categories=categories, values=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def _encode_distribution(
    mark: Mark,
    mut continuous: _ContinuousData,
    mut categorical: _CategoricalData,
    mut distribution: _DistributionData,
    categories: List[String],
    values: List[List[Float64]],
) raises:
    """`Plot.encode_distribution()`'s body, which forwards here with
    every argument; see that method for the contract."""
    var _ok_encode_distribution = List[Mark]()
    _ok_encode_distribution.append(Mark.VIOLIN)
    _ok_encode_distribution.append(Mark.BEESWARM)
    _ok_encode_distribution.append(Mark.RIDGELINE)
    _require_mark(
        mark,
        "encode_distribution",
        "mark_violin()",
        _ok_encode_distribution^,
    )
    if len(categories) != len(values):
        raise Error(
            "Plot.encode_distribution(): categories and values must"
            " have the same length (got "
            + String(len(categories))
            + " and "
            + String(len(values))
            + ")"
        )
    _require_non_empty(len(categories), "Plot.encode_distribution()")
    for i in range(len(values)):
        if len(values[i]) == 0:
            raise Error(
                "Plot.encode_distribution(): category '"
                + categories[i]
                + "' has no values -- can't draw a distribution for"
                " an empty one"
            )
    categorical.x = categories.copy()
    continuous.x = List[Float64]()
    continuous.y = List[Float64]()
    distribution.values = values.copy()


def _render_violin_oriented[
    T: DrawTarget
](
    mut target: T,
    categorical: _CategoricalData,
    distribution: _DistributionData,
    style: _MarkStyle,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """`Mark.VIOLIN`'s renderer, the one its setter binds: `_render_horizontal_violin`
    when the plot is horizontal, `_render_violin` otherwise."""
    if settings.horizontal:
        return _render_horizontal_violin(
            target,
            categorical,
            distribution,
            style,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )
    return _render_violin(
        target,
        categorical,
        distribution,
        style,
        settings,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )


def _render_violin_oriented_plot[
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
    """`_render_violin_oriented` on `plot`'s own columns and settings: the callback
    its `mark_*()` setter binds. This is the one place the mark's
    renderer meets a `Plot` (#826)."""
    return _render_violin_oriented(
        target,
        plot._categorical,
        plot._distribution,
        plot._mark_style,
        plot._settings,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
