from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.core.theme import Theme


def effect_scatter(
    df: DataFrame,
    x: String,
    y: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`effect_scatter()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values. The axis titles default to the `x` and `y` column names.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        y: The numeric column for this channel.
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
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var x_values = _frame_floats(df, x, "effect_scatter()", theme.missing)
    var y_values = _frame_floats(df, y, "effect_scatter()", theme.missing)
    return effect_scatter(
        x=x_values,
        y=y_values,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else x,
        y_title=y_title if y_title.byte_length() > 0 else y,
    )


def effect_scatter[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A scatter plot with a halo drawn under each point, drawing the eye
    to it regardless of how dense its neighbors are. Useful when a
    handful of points (outliers, highlighted items) need to stand out
    from a busy scatter.

    `Mark.EFFECT_SCATTER` over continuous `x`/`y`, the static equivalent
    of ECharts' effect scatter. Accepts the same `encode()` channels as
    `Mark.POINT` (`color`/`color_categories`/`size`); use
    `Plot().mark_effect_scatter().encode(...)` directly
    for those.

    Args:
        x: The continuous x column, one entry per point.
        y: The continuous y column, one entry per point.
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
        from dataviz import effect_scatter
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Illustrative CI jobs selected after crossing both duration and
            # memory review thresholds; halos emphasize the flagged runs.
            var duration_minutes: List[Float64] = [
                18, 22, 27, 31, 35, 39, 44, 48, 53, 57, 63, 71,
            ]
            var peak_memory_gb: List[Float64] = [
                11.2, 14.8, 12.7, 18.3, 16.5, 22.1, 19.4, 25.8, 23.6, 29.2,
                27.5, 31.4,
            ]

            var c = effect_scatter(
                duration_minutes,
                peak_memory_gb,
                theme=Theme(halo_alpha=55),
                title="Illustrative Resource-Intensive CI Jobs",
                x_title="Build duration (minutes)",
                y_title="Peak memory (GB)",
            )
            save(c, "docs/src/examples/out_effect_scatter.svg")
        ```
    """
    var x_f = _materialize_scalar_list(x)
    var y_f = _materialize_scalar_list(y)
    var plot = Plot().mark_effect_scatter().encode(x=x_f, y=y_f)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
