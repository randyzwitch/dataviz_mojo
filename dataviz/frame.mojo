"""The axis frames: the plot rect, its ticks, gridlines and axis
labels, for both a continuous and a categorical axis.

Split out of `plot.mojo` (#222). A frame is what a mark draws into --
it resolves the plot rect out of the canvas minus margins and legend
reservation, draws the furniture, and hands back the scales.

`_Orientation` is the biggest thing here, and the reason a horizontal
variant of a mark is not a second code path: it flips the meaning of
"along the value axis" and "across the bands" so one implementation
serves both.

Tick and gridline positions round to whole pixels on purpose. They are
furniture, and a hairline is crisp only on a pixel center -- unlike the
marks, whose geometry stays in `Float64` (#312 and the PRs after it).
"""

from std.collections import Dict
from std.math import cos, pi, sin

from canvas.color import Color
from canvas.geometry import round_to_int
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign, draw_text
from canvas.vector.draw_target import DrawTarget

from dataviz.continuous import area, line
from dataviz.layers import _render_layers_generic
from dataviz.legend import _LegendLayout
from dataviz.mark import Mark
from dataviz.ordinal_scale import OrdinalScale
from dataviz.pixel_snap import _snap_pixel_center, _snap_pixel_edge
from dataviz.plot import (
    Plot,
    _RenderResult,
    _data_extent,
    _render_generic,
    _zero_baseline_y_extent,
    render,
)
from dataviz.scale import LinearScale
from dataviz.text import _Scaled, _TextRequest, _max_label_width
from dataviz.theme import Theme
from dataviz.x_label_rotation import XAxisLabelRotation


struct _CategoricalIndex(Movable):
    """`_categorical_indices`'s result: a categorical column's `domain` (its
    distinct values in first-seen order) plus `indices`, each row's
    position in that domain.
    """

    var domain: List[String]
    var indices: List[Int]

    def __init__(out self, var domain: List[String], var indices: List[Int]):
        self.domain = domain^
        self.indices = indices^


def _categorical_indices(data: List[String]) raises -> _CategoricalIndex:
    """A categorical column's domain and its per-row indices into that
    domain, resolved in one pass through a `Dict`, so every later lookup
    is an array read rather than a string search. First-seen order.
    """
    var seen = Dict[String, Int]()
    var domain = List[String]()
    var indices = List[Int](capacity=len(data))
    for v in data:
        if v in seen:
            indices.append(seen[v])
        else:
            var idx = len(domain)
            seen[v] = idx
            domain.append(v)
            indices.append(idx)
    return _CategoricalIndex(domain^, indices^)


def _axis_pixel(scale: LinearScale, value: Float64) -> Int:
    return round_to_int(scale.to_pixel(value))


def _axis_pixel_f(scale: LinearScale, value: Float64) -> Float64:
    """`_axis_pixel` without the rounding: the scale position as
    geometry, for a mark that hands coordinates to canvas as `Float64`
    and lets the primitive snap each edge.

    canvas_mojo v0.19.0's `Float64` overloads read a coordinate as a
    geometric edge under the pixel-centre convention, which is what a
    scale position actually is; `round_to_int` read it as a pixel
    index, which was the approximation. Measured against an
    antialiased path fill of the same box, snapping is closer to the
    truth at every sub-pixel offset and never further.

    Marks are being moved onto this one family at a time; when the last
    one lands, this replaces `_axis_pixel` and the `_f` suffix goes.
    """
    return scale.to_pixel(value)


struct _BaselineRect(Movable):
    """`_pull_off_axis_line`'s `(y, height)` result."""

    var y: Int
    var height: Int

    def __init__(out self, y: Int, height: Int):
        self.y = y
        self.height = height


struct _BaselineRectF(Movable):
    """`_pull_off_axis_line_f`'s `(y, height)`, in `Float64` geometry.

    The `Float64` counterpart of `_BaselineRect`, for marks migrated
    off `round_to_int`; the two merge once every mark is across.
    """

    var y: Float64
    var height: Float64

    def __init__(out self, y: Float64, height: Float64):
        self.y = y
        self.height = height


struct _BandLabelPoint(Copyable, ImplicitlyCopyable, Movable):
    """A label's baseline point in pixels; `_Orientation.band_label_point`'s
    result.
    """

    var x: Int
    var y: Int

    def __init__(out self, x: Int, y: Int):
        self.x = x
        self.y = y


struct _BandLabel(Copyable, ImplicitlyCopyable, Movable):
    """A label placed just past a band rect's far end -- position plus
    the `TextAlign` that goes with it, since which side the text hangs
    off depends on the same sign the position does."""

    var x: Int
    var y: Int
    var align: TextAlign

    def __init__(out self, x: Int, y: Int, align: TextAlign):
        self.x = x
        self.y = y
        self.align = align


struct _Orientation(Copyable, ImplicitlyCopyable, Movable):
    """Which way a categorical mark's bands run, and the places that differ
    because of it.

    Every categorical mark has a band axis (one slot per category, an
    `OrdinalScale`) and a value axis (the continuous `LinearScale`).
    Drawing is the same arithmetic either way until band and value become
    concrete x/y pixels: emitting a rect, placing a label, drawing a line
    or point. This holds those moments so a mark's drawing loop is
    written once.

    The axis frames themselves stay two functions
    (`_draw_categorical_axis_frame` and
    `_draw_horizontal_categorical_axis_frame`, gantt.mojo); which scale
    is which type, which axis reverses, and which margin grows differ
    there. Both frames name their fields `x_scale`/`y_scale` with the
    types swapped, so a caller unpacks its own frame into band/value and
    passes those.
    """

    var horizontal: Bool
    """`False`: categories run left-to-right, values upward (the
    default). `True`: categories run top-to-bottom, values rightward."""

    def __init__(out self, horizontal: Bool):
        """Construct an orientation.

        Args:
            horizontal: Whether categories run down the y-axis.
        """
        self.horizontal = horizontal

    def fill_band_rect[
        T: DrawTarget
    ](
        self,
        mut target: T,
        extent: _BaselineRect,
        band_pos: Int,
        band_size: Int,
        color: Color,
    ):
        """Fill one band's rect: `extent` spans the value axis (what
        `_pull_off_axis_line` returns), `band_pos`/`band_size` the band axis.
        """
        if self.horizontal:
            target.fill_rect(
                extent.y, band_pos, extent.height, band_size, color
            )
        else:
            target.fill_rect(
                band_pos, extent.y, band_size, extent.height, color
            )

    def fill_band_rect[
        T: DrawTarget
    ](
        self,
        mut target: T,
        extent: _BaselineRectF,
        band_pos: Float64,
        band_size: Float64,
        color: Color,
    ):
        """`fill_band_rect` in `Float64` geometry, with both edges
        snapped to whole pixels.

        Filled rectangles snap; nothing else here does. See
        `_snap_pixel_edge` for why, and for why the snap happens in
        logical space rather than being left to the primitive.

        Snapping the two edges independently and taking the width from
        them, rather than rounding a position and a size separately, is
        also what keeps the width honest: the old path rounded
        `band_start` and `bandwidth` apart from each other, so their
        errors accumulated.
        """
        var along0 = _snap_pixel_edge(extent.y)
        var along1 = _snap_pixel_edge(extent.y + extent.height)
        var across0 = _snap_pixel_edge(band_pos)
        var across1 = _snap_pixel_edge(band_pos + band_size)
        if self.horizontal:
            target.fill_rect(
                along0, across0, along1 - along0, across1 - across0, color
            )
        else:
            target.fill_rect(
                across0, along0, across1 - across0, along1 - along0, color
            )

    def value_line[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along_a: Int,
        along_b: Int,
        across: Int,
        color: Color,
        width: Float64,
    ):
        """A line running *along* the value axis at a fixed band
        position -- a box's whisker, a lollipop's stem."""
        if self.horizontal:
            target.draw_line_aa(
                along_a, across, along_b, across, color, width=width
            )
        else:
            target.draw_line_aa(
                across, along_a, across, along_b, color, width=width
            )

    def value_line[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along_a: Float64,
        along_b: Float64,
        across: Float64,
        color: Color,
        width: Float64,
    ):
        """`value_line` in `Float64` geometry, with the fixed cross-axis
        coordinate snapped to a pixel centre so a 1px line stays hard.
        See `_snap_pixel_center`; the two ends keep their exact
        positions.
        """
        var fixed = _snap_pixel_center(across)
        if self.horizontal:
            target.draw_line_aa(
                along_a, fixed, along_b, fixed, color, width=width
            )
        else:
            target.draw_line_aa(
                fixed, along_a, fixed, along_b, color, width=width
            )

    def band_line[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along: Int,
        across_a: Int,
        across_b: Int,
        color: Color,
        width: Float64,
    ):
        """A line running *across* the band at a fixed value -- a box's
        median line and whisker caps. The perpendicular of
        `value_line`."""
        if self.horizontal:
            target.draw_line_aa(
                along, across_a, along, across_b, color, width=width
            )
        else:
            target.draw_line_aa(
                across_a, along, across_b, along, color, width=width
            )

    def band_line[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along: Float64,
        across_a: Float64,
        across_b: Float64,
        color: Color,
        width: Float64,
    ):
        """`band_line` in `Float64` geometry, with the fixed value-axis
        coordinate snapped to a pixel centre so a 1px line stays hard.
        See `_snap_pixel_center`; the two ends keep their exact
        positions.
        """
        var fixed = _snap_pixel_center(along)
        if self.horizontal:
            target.draw_line_aa(
                fixed, across_a, fixed, across_b, color, width=width
            )
        else:
            target.draw_line_aa(
                across_a, fixed, across_b, fixed, color, width=width
            )

    def baseline_pull(self) -> Float64:
        """Which direction is into the plot area, away from the categorical
        axis line: `-1.0` vertically (that line is the frame's bottom) and
        `+1.0` horizontally (the frame's left edge). Used to nudge a stroked
        mark 1px clear of the axis line; `_pull_off_axis_line` does the same
        for filled rects.
        """
        return 1.0 if self.horizontal else -1.0

    def path_move_to(
        self, mut path: Path, along: Float64, across: Float64
    ) raises:
        """`Path.move_to` in band/value terms rather than x/y -- for a
        mark whose outline is built point by point (a violin's KDE
        silhouette) rather than from rects and lines."""
        if self.horizontal:
            path.move_to(along, across)
        else:
            path.move_to(across, along)

    def path_line_to(
        self, mut path: Path, along: Float64, across: Float64
    ) raises:
        """`Path.line_to` in band/value terms -- see `path_move_to`."""
        if self.horizontal:
            path.line_to(along, across)
        else:
            path.line_to(across, along)

    def value_stem_path(
        self, along_from: Float64, along_to: Float64, across: Float64
    ) raises -> Path:
        """A straight two-point `Path` running along the value axis at
        a fixed band position -- a lollipop's stem. A `Path` rather
        than `value_line` because it is stroked at `Theme.line_width`
        through `stroke_path_aa`, not drawn as a 1px `draw_line_aa`."""
        var stem = Path()
        if self.horizontal:
            stem.move_to(along_from, across)
            stem.line_to(along_to, across)
        else:
            stem.move_to(across, along_from)
            stem.line_to(across, along_to)
        return stem^

    def band_point[
        T: DrawTarget
    ](self, mut target: T, along: Int, across: Int, radius: Int, color: Color):
        """A filled circle at (value, band) -- a box's outlier, a
        beeswarm's point."""
        if self.horizontal:
            target.fill_circle_aa(along, across, radius, color)
        else:
            target.fill_circle_aa(across, along, radius, color)

    def band_point[
        T: DrawTarget
    ](
        self,
        mut target: T,
        along: Float64,
        across: Float64,
        radius: Float64,
        color: Color,
    ):
        """`band_point` in `Float64` geometry.

        Not snapped, unlike `fill_band_rect`: a circle is antialiased on
        every side already, so there is no hard edge to preserve, and
        rounding its centre would only move the dot off the value it
        marks.
        """
        if self.horizontal:
            target.fill_circle_aa(along, across, radius, color)
        else:
            target.fill_circle_aa(across, along, radius, color)

    def outside_band_label(
        self,
        extent: _BaselineRect,
        band_pos: Int,
        band_size: Int,
        negative: Bool,
        label_gap: Int,
        font_size: Float64,
    ) -> _BandLabel:
        """Where a label just past the bar's far end goes (`Mark.BAR`/
        `GROUPED_BAR`'s placement, as opposed to `band_label_point`'s
        centered-inside one). `negative` flips which end it hangs off, so a
        bar extending below or left of the baseline never collides with its
        label.

        Vertically the text sits above the bar's top edge and drops a full
        `font_size` when it moves below (the baseline is at the bottom of the
        glyph); horizontally it hangs off the end, vertically centered on the
        band with the `font_size * 0.35` nudge, and the `TextAlign` flips
        instead.
        """
        var across = band_pos + band_size // 2
        if self.horizontal:
            var x = (
                extent.y
                - label_gap if negative else extent.y
                + extent.height
                + label_gap
            )
            var align = TextAlign.RIGHT if negative else TextAlign.LEFT
            return _BandLabel(x, across + Int(font_size * 0.35), align)
        var y = (
            extent.y
            + extent.height
            + label_gap
            + Int(font_size) if negative else extent.y
            - label_gap
        )
        return _BandLabel(across, y, TextAlign.CENTER)

    def outside_band_label(
        self,
        extent: _BaselineRectF,
        band_pos: Float64,
        band_size: Float64,
        negative: Bool,
        label_gap: Int,
        font_size: Float64,
    ) -> _BandLabel:
        """`outside_band_label` for a mark laying out in `Float64`.

        The result is still `Int`: a `_TextRequest` anchors text at
        whole pixels on both backends, so this is a real pixel index and
        rounding here is the right place for it -- unlike the mark
        geometry, where rounding early was the thing being removed.
        """
        var across = band_pos + band_size / 2.0
        if self.horizontal:
            var x = (
                extent.y
                - Float64(label_gap) if negative else extent.y
                + extent.height
                + Float64(label_gap)
            )
            var align = TextAlign.RIGHT if negative else TextAlign.LEFT
            return _BandLabel(
                round_to_int(x),
                round_to_int(across + font_size * 0.35),
                align,
            )
        var y = (
            extent.y
            + extent.height
            + Float64(label_gap)
            + font_size if negative else extent.y
            - Float64(label_gap)
        )
        return _BandLabel(
            round_to_int(across), round_to_int(y), TextAlign.CENTER
        )

    def band_label_point(
        self,
        extent: _BaselineRect,
        band_pos: Int,
        band_size: Int,
        font_size: Float64,
    ) -> _BandLabelPoint:
        """Where a label centered inside `extent` x `band_pos` goes. `TextAlign`
        has no vertical option, so the returned `y` already carries the
        `font_size * 0.35` baseline-centering nudge; callers pass the point
        straight to `_TextRequest`.
        """
        var along = extent.y + extent.height // 2
        var across = band_pos + band_size // 2
        var nudge = Int(font_size * 0.35)
        if self.horizontal:
            return _BandLabelPoint(along, across + nudge)
        return _BandLabelPoint(across, along + nudge)

    def band_label_point(
        self,
        extent: _BaselineRectF,
        band_pos: Float64,
        band_size: Float64,
        font_size: Float64,
    ) -> _BandLabelPoint:
        """`band_label_point` for a mark laying out in `Float64`.

        The result is still `Int`, like `outside_band_label`'s: a
        `_TextRequest` anchors text at whole pixels on both backends, so
        this is a real pixel index and rounding belongs here.
        """
        var along = extent.y + extent.height / 2.0
        var across = band_pos + band_size / 2.0
        var nudge = font_size * 0.35
        if self.horizontal:
            return _BandLabelPoint(
                round_to_int(along), round_to_int(across + nudge)
            )
        return _BandLabelPoint(
            round_to_int(across), round_to_int(along + nudge)
        )


def _pull_off_axis_line(
    edge_a: Int, edge_b: Int, axis_line_py: Int
) -> _BaselineRect:
    """The `(y, height)` of a fill spanning `edge_a`..`edge_b` (in either
    order), with whichever edge sits exactly on `axis_line_py` nudged 1px
    toward the other edge.

    Every magnitude-from-baseline mark (`Mark.BAR`/`LOLLIPOP`/`WATERFALL`/
    `BULLET`/`GROUPED_BAR`/`STACKED_BAR`/`AREA`) has one edge at the zero
    baseline. When that baseline is the drawn axis-line row (every value
    non-negative, so `_zero_baseline_y_extent`'s domain is `[0, hi]`), a
    solid fill drawn after the axis frame paints over the line's
    antialiasing (issue #105). Pulling the edge 1px inward leaves a
    hairline of background between mark and line.

    A zero-height span is left alone rather than becoming a 1px sliver.
    A no-op when neither edge is `axis_line_py` (mixed-sign or
    all-negative domains).
    """
    var y = min(edge_a, edge_b)
    var height = max(edge_a, edge_b) - y
    if height <= 0:
        return _BaselineRect(y, height)
    if y == axis_line_py:
        return _BaselineRect(y + 1, height - 1)
    if y + height == axis_line_py:
        return _BaselineRect(y, height - 1)
    return _BaselineRect(y, height)


def _pull_off_axis_line_f(
    edge_a: Float64, edge_b: Float64, axis_line_py: Float64
) -> _BaselineRectF:
    """`_pull_off_axis_line` in `Float64` geometry.

    Same rule -- whichever edge sits on the drawn axis-line row is
    nudged 1px toward the other, so a solid fill does not paint over
    the line's antialiasing (#105) -- with the one translation the
    change of type forces: "sits on the axis line" was an exact `Int`
    equality and becomes "within half a pixel of it", which is the same
    question asked of a coordinate that has not been rounded yet. The
    nudge stays 1.0, a whole pixel, as before.
    """
    var y = min(edge_a, edge_b)
    var height = max(edge_a, edge_b) - y
    if height <= 0.0:
        return _BaselineRectF(y, height)
    if abs(y - axis_line_py) < 0.5:
        return _BaselineRectF(y + 0.5, height - 0.5)
    if abs(y + height - axis_line_py) < 0.5:
        return _BaselineRectF(y, height - 0.5)
    return _BaselineRectF(y, height)


def _with_secondary_axis(
    layout: _LegendLayout, secondary_axis_reserve: Int
) -> _LegendLayout:
    """`layout` with a secondary y-axis's own width added to the right
    inset, since that axis is drawn outside the plot rect on the same
    side a right-hand legend sits.

    Args:
        layout: The legend's own reserve.
        secondary_axis_reserve: Width the secondary axis needs, or 0.

    Returns:
        A copy with the extra width folded in.
    """
    var out = _LegendLayout()
    out.left = layout.left
    out.right = layout.right + secondary_axis_reserve
    out.top = layout.top
    out.bottom = layout.bottom
    out.position = layout.position
    out.active = layout.active
    out.entry_widths = layout.entry_widths.copy()
    out.row_of = layout.row_of.copy()
    out.rows = layout.rows
    return out^


struct _ContinuousFrame(Movable):
    """`_draw_continuous_axis_frame`'s finished layout, the continuous-x
    counterpart to `_CategoricalFrame`, with a `LinearScale` on both
    axes. `px0`/`py0`/`px1`/`py1` are the inner plot rect.
    """

    var x_scale: LinearScale
    var y_scale: LinearScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: LinearScale,
        var y_scale: LinearScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.y_scale = y_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        """This frame as the `_RenderResult` its caller returns, mirroring
        `_CategoricalFrame.result`. Passes both `y_scale` and `x_scale`
        through: this is the one frame with a continuous x-axis, so it's the
        only one `annotate_vline()`/`annotate_point()` can support.
        """
        return _RenderResult(
            self.text_requests.copy(),
            self.px0,
            self.py0,
            self.px1,
            self.py1,
            self.y_scale,
            True,
            self.x_scale,
            True,
        )


def _draw_continuous_axis_frame[
    T: DrawTarget
](
    mut target: T,
    x_scale: LinearScale,
    y_scale: LinearScale,
    theme: Theme,
    legend: _LegendLayout,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _ContinuousFrame:
    """The layout and axis-frame core every continuous-x render path shares
    (`_render_generic`'s continuous path and `_render_layers_generic`),
    `_draw_categorical_axis_frame`'s counterpart for a `LinearScale`
    x-axis: computes the dynamic left margin from `y_scale`'s ticks,
    resolves both scales' pixel ranges against the plot rect, and draws
    gridlines, both axis lines, and every tick mark plus label.

    Both scales' domains are decided by the caller (ranges are the
    `[0, 1]` placeholder `_data_extent`/`_zero_baseline_y_extent`
    return): one plot's data for a standalone render, every layer's data
    combined for a stack. `legend` insets whichever edge it reserved (the
    right column by default), subtracted from the right
    edge before the rect is finalized.
    """
    var sc = _Scaled(theme)

    # y-domain ticks computed before plot_x0 is finalized: tick values
    # depend only on the domain, never the pixel range, so the left margin
    # can be sized to fit their labels, `max`'d against Theme's configured
    # minimum.
    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels(theme.y_tick_format)
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size, cache=cache))
        + sc.tick_length
        + sc.label_gap
        + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin) + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom

    var out_x_scale = x_scale
    out_x_scale.range_min = Float64(plot_x0)
    out_x_scale.range_max = Float64(plot_x1)

    # y range is reversed: domain_min (smallest data value) lands at
    # the *bottom* of the plot area (the larger pixel y), domain_max
    # at the top -- see LinearScale's docstring.
    var out_y_scale = y_scale
    out_y_scale.range_min = Float64(plot_y1)
    out_y_scale.range_max = Float64(plot_y0)

    var x_ticks = out_x_scale.ticks()
    var x_labels = x_ticks.labels(theme.x_tick_format)

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(
                px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale
            )
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(out_y_scale, y_ticks.values[i])
            target.draw_line_aa(
                plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale
            )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )
    target.draw_line_aa(
        plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
        target.draw_line_aa(
            px,
            plot_y1,
            px,
            plot_y1 + sc.tick_length,
            theme.axis_color,
            width=sc.scale,
        )
        text_requests.append(
            _TextRequest(
                px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                x_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    # Baseline offset so a label's glyphs sit roughly vertically centered
    # on its tick; draw_text's y is the text baseline.
    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(
            plot_x0 - sc.tick_length,
            py,
            plot_x0,
            py,
            theme.axis_color,
            width=sc.scale,
        )
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                py + y_label_baseline_offset,
                y_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )

    return _ContinuousFrame(
        out_x_scale,
        out_y_scale,
        sc^,
        text_requests^,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
    )


struct _CategoricalFrame(Movable):
    """The finished layout every vertical categorical mark draws its
    per-category shape into; see `_draw_categorical_axis_frame`. `px0`/
    `py0`/`px1`/`py1` are the inner plot rect (the same values the axis
    lines are drawn at), carried through so each caller builds its
    `_RenderResult` from them.
    """

    var x_scale: OrdinalScale
    var y_scale: LinearScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: OrdinalScale,
        var y_scale: LinearScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.y_scale = y_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        """This frame as the `_RenderResult` its caller returns. `text_requests`
        is copied rather than moved: Mojo rejects moving a single field out
        of a struct ("field destroyed out of the middle of a value") while
        the rest still needs its normal destruction. Passes `y_scale` through
        with `has_y_scale=True`, which is what gives every mark sharing this
        frame `Plot.annotate_line()`/`annotate_area()` support.
        """
        return _RenderResult(
            self.text_requests.copy(),
            self.px0,
            self.py0,
            self.px1,
            self.py1,
            self.y_scale,
            True,
        )


def _resolve_x_label_rotation(
    override: XAxisLabelRotation, max_label_width: Float64, step: Float64
) -> Float64:
    """The radians `_draw_categorical_axis_frame` rotates x-axis category
    labels by (#214): `0.0` (drawn horizontal, centered under the tick),
    or `pi / 4`/`pi / 2` (drawn right-aligned at the tick; see that
    function's own call site for why). `AUTO` escalates only as far as
    needed: horizontal if every label already fits its band
    (`OrdinalScale.step()`), 45 degrees if that alone clears it
    (measuring the rotated label's own narrower horizontal footprint,
    `max_label_width * cos(45deg)`, against `step`), 90 otherwise. An
    explicit override always wins, with no measurement needed.
    """
    if override == XAxisLabelRotation.DEG_0:
        return 0.0
    if override == XAxisLabelRotation.DEG_45:
        return pi / 4.0
    if override == XAxisLabelRotation.DEG_90:
        return pi / 2.0

    if max_label_width <= step:
        return 0.0
    if max_label_width * cos(pi / 4.0) <= step:
        return pi / 4.0
    return pi / 2.0


def _draw_categorical_axis_frame[
    T: DrawTarget
](
    mut target: T,
    categories: List[String],
    y_scale: LinearScale,
    theme: Theme,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _CategoricalFrame:
    """The layout and axis-frame core shared by every vertical categorical
    mark (`Mark.BAR`, `LOLLIPOP`, `WATERFALL`, `BOX`, `CANDLESTICK`,
    `BULLET`, `GROUPED_BAR`, `STACKED_BAR`, `STREAMGRAPH`, ...): computes
    the dynamic left margin from `y_scale`'s ticks, builds the
    `OrdinalScale` x-axis, draws gridlines, axis lines, y-tick marks and
    labels, and every category's x-tick mark and label. Returns the
    finished scales (pixel ranges resolved), the `_Scaled` theme, and the
    `_TextRequest`s so far; the caller draws its per-category shape.

    `y_scale`'s domain must already be decided (its range is the `[0, 1]`
    placeholder), since the marks differ there: `Mark.BAR`/`LOLLIPOP`/
    `WATERFALL` include a zero baseline, `Mark.BOX` fits the data spread.

    Long category labels rotate per `Theme.x_label_rotation` (#214,
    `_resolve_x_label_rotation`) once `x_scale` (and so its `step()`) is
    known, before `plot_y1` is finalized -- a rotated label needs extra
    bottom margin (`sin(rotation) * widest label`) reserved for it, the
    same "measure before finalizing the pixel range" pattern
    `dynamic_left_margin` already uses for the y-axis.
    """
    var sc = _Scaled(theme)

    var y_ticks = y_scale.ticks()
    var y_labels = y_ticks.labels(theme.y_tick_format)
    var dynamic_left_margin = (
        Int(_max_label_width(y_labels, sc.font_size, cache=cache))
        + sc.tick_length
        + sc.label_gap
        + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_x1 = ox1 - sc.margin_right

    var x_scale = OrdinalScale(
        categories.copy(), Float64(plot_x0), Float64(plot_x1)
    )

    var x_label_max_width = _max_label_width(
        categories, sc.font_size, cache=cache
    )
    var x_label_rotation = _resolve_x_label_rotation(
        theme.x_label_rotation, x_label_max_width, x_scale.step()
    )
    var x_label_extra_bottom = (
        round_to_int(
            sin(x_label_rotation) * x_label_max_width
        ) if x_label_rotation
        > 0.0 else 0
    )

    var plot_y0 = oy0 + sc.margin_top
    var plot_y1 = oy1 - sc.margin_bottom - x_label_extra_bottom

    # y range is reversed: domain_min lands at the *bottom* of the
    # plot area (the larger pixel y), domain_max at the top -- see
    # LinearScale's docstring.
    var out_y_scale = y_scale
    out_y_scale.range_min = Float64(plot_y1)
    out_y_scale.range_max = Float64(plot_y0)

    if theme.show_gridlines:
        for i in range(len(y_ticks.values)):
            var py = _axis_pixel(out_y_scale, y_ticks.values[i])
            target.draw_line_aa(
                plot_x0, py, plot_x1, py, theme.gridline_color, width=sc.scale
            )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )
    target.draw_line_aa(
        plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(y_ticks.values)):
        var py = _axis_pixel(out_y_scale, y_ticks.values[i])
        target.draw_line_aa(
            plot_x0 - sc.tick_length,
            py,
            plot_x0,
            py,
            theme.axis_color,
            width=sc.scale,
        )
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                py + y_label_baseline_offset,
                y_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )

    for i in range(len(categories)):
        var center_px = round_to_int(x_scale.center(i))
        target.draw_line_aa(
            center_px,
            plot_y1,
            center_px,
            plot_y1 + sc.tick_length,
            theme.axis_color,
            width=sc.scale,
        )
        if x_label_rotation > 0.0:
            # Right-aligned at the tick and rotated clockwise (screen y
            # increases downward): the anchor is the label's own last
            # character, so the label reads bottom-to-top running away
            # from the tick, the same convention ggplot2's `angle=45,
            # hjust=1` axis text produces.
            text_requests.append(
                _TextRequest(
                    center_px,
                    plot_y1 + sc.tick_length + sc.label_gap,
                    categories[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.RIGHT,
                    theme.font_family,
                    rotation=-x_label_rotation,
                )
            )
        else:
            text_requests.append(
                _TextRequest(
                    center_px,
                    plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                    categories[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )

    return _CategoricalFrame(
        x_scale^,
        out_y_scale,
        sc^,
        text_requests^,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
    )
