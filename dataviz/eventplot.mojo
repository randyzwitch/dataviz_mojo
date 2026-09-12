"""`Mark.EVENTPLOT`: parallel rasters of event positions.

The chart for anything that *occurs* at times rather than having a
value at times -- neural spike trains (where it is called a raster
plot), request logs, error occurrences, seismic events, release dates.
This package could already plot a *count* of events per bucket
(`histogram`, `punchcard`, `calendar_heatmap`); bucketing is exactly the
information loss this avoids.

Geometrically it is `Mark.RUG` repeated: a continuous x-axis of pooled
positions, a categorical y-axis of rows, and one snapped hairline per
event. The ticks come from `_draw_snapped_ticks` (kde.mojo), the same
function the rug draws through, so the two marks cannot drift apart on
the one thing that makes a thin vertical line legible.
"""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.kde import _draw_snapped_ticks
from dataviz.plot import (
    Plot,
    _RenderResult,
    _data_extent,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


def _render_eventplot[
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
    """Render a `Mark.EVENTPLOT` plot: one row of ticks per series, each
    tick at the position of one event -- matplotlib's `ax.eventplot()`.

    Rows run top to bottom on the `OrdinalScale` y-axis that
    `_draw_horizontal_categorical_axis_frame` (gantt.mojo) builds, the
    same frame `Mark.GANTT` and every `horizontal=True` mark uses. That
    is the frame for "a category per row and a continuous quantity
    across", which is what this is; nothing here is a new layout.

    The x-domain is `_data_extent` over the *pooled* positions, so every
    row is read against one timeline. Per-row domains would put two rows'
    ticks at the same pixel for different times, which is the one thing a
    raster must not do.

    Each event is drawn, never decimated. A dropped event is a lie in a
    way a dropped line vertex is not: a polyline's missing vertex still
    leaves the line passing through where it was, while a missing tick
    says nothing happened. With thousands of events per row the ticks do
    overlap into a solid bar -- matplotlib does not solve this either --
    and `mark_eventplot(line_length=...)` is the honest lever, since a
    shorter tick relieves crowding between rows without touching what is
    drawn along one.

    One color for every row (`Theme.mark_color`), unlike the
    per-category palettes the grouped marks use. Rows are already told
    apart by position and by their axis labels, so coloring them would
    encode a dimension twice and add a legend that repeats the y-axis.

    Args:
        target: Where to draw.
        plot: The chart, whose `_categorical.x` (row labels) and
            `_distribution` values (each row's positions) this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: No rows, a row-count mismatch, no events at all, or a
            non-positive `line_length`.
    """
    var labels = plot._categorical.x.copy()
    var rows = plot._distribution.values.copy()
    _require_non_empty(len(labels), "Plot.encode_eventplot()")
    if len(rows) != len(labels):
        raise Error(
            "Plot.encode_eventplot(): labels and positions must have the"
            " same length (got "
            + String(len(labels))
            + " and "
            + String(len(rows))
            + ")"
        )

    var line_length = plot._mark_style.eventplot_line_length
    if line_length <= 0.0:
        raise Error(
            "Plot.mark_eventplot(): line_length must be > 0 (got "
            + String(line_length)
            + ") -- a tick with no height draws nothing"
        )

    # Pooled, so all rows share one timeline. A row may be empty (see
    # `encode_eventplot()`); every row being empty leaves no domain, and
    # `encode_eventplot()` has already refused that.
    var pooled = List[Float64]()
    for row in rows:
        for v in row:
            pooled.append(v)
    _require_non_empty(len(pooled), "Plot.encode_eventplot()")

    var theme = plot._theme
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        labels,
        _data_extent(pooled),
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var half = frame.y_scale.bandwidth() * line_length / 2.0
    for i in range(len(rows)):
        var center = frame.y_scale.center(i)
        _draw_snapped_ticks(
            target,
            rows[i],
            frame.x_scale,
            center - half,
            center + half,
            theme.mark_color,
            frame.sc.scale,
        )
    return frame.result()


def eventplot(
    labels: List[String],
    positions: List[List[Float64]],
    line_length: Float64 = 1.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """One row of tick marks per series, each tick at the position of one
    event: a raster plot.

    `Mark.EVENTPLOT`: matplotlib's `ax.eventplot()`.

    The chart for things that happen rather than things that have a
    value -- spike trains, request logs, error occurrences, release
    dates. Every event is drawn where it happened, so nothing is lost to
    a bucket the way it is in a histogram or a calendar heatmap; the
    cost is that a dense row saturates into a solid bar, which
    `line_length` can relieve between rows but not within one.

    A row may be empty. "This sensor recorded nothing" is a result, and
    an empty row keeps its label and its place in the ordering rather
    than disappearing.

    Args:
        labels: One row label per series, top to bottom.
        positions: Each row's event positions (`positions[i]`), in the
            same units as the shared x-axis. Any row may be empty; at
            least one event must exist overall.
        line_length: Each tick's height as a fraction of its row's band,
            defaulting to `1.0` (the full band). Below 1.0 opens a gap
            between rows, which is what makes two dense rows readable as
            two rows.
        theme: Colors, sizes and spacing.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Smaller line under the title.
        x_title: X-axis label.
        y_title: Y-axis label.

    Returns:
        The finished `Plot`.

    Raises:
        Error: `labels` is empty, lengths don't match, every row is
            empty, or `line_length` is not positive.

    Example:
        ```mojo
        from dataviz import eventplot
        from dataviz import save

        def main() raises:
            var neurons: List[String] = ["Unit 1", "Unit 2", "Unit 3"]
            var spikes: List[List[Float64]] = [
                [12.0, 18.0, 21.0, 22.0, 40.0, 55.0, 58.0, 61.0, 90.0],
                [5.0, 31.0, 33.0, 34.0, 36.0, 37.0, 39.0, 72.0, 95.0],
                [8.0, 9.0, 25.0, 48.0, 49.0, 50.0, 66.0, 80.0, 84.0],
            ]
            var c = eventplot(
                neurons,
                spikes,
                line_length=0.8,
                title="Spike times",
                x_title="ms",
            )
            save(c, "docs/src/examples/out_eventplot.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_eventplot(line_length=line_length)
        .encode_eventplot(labels=labels, positions=positions)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
