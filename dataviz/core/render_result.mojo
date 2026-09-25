"""What every `_render_*` function returns: the labels it deferred and
the inner rect and scales it laid the mark out against. Read by the
annotation passes and the label placement that run after the mark."""

from dataviz.core.scale import LinearScale
from dataviz.core.text import _TextRequest


struct _RenderResult(Movable):
    """Every `_render_*` function's return value: the axis/tick/legend
    `_TextRequest`s, plus the inner plot rect the mark was laid out in
    (`px0`/`py0`/`px1`/`py1`, with dynamic margins and legend column
    resolved). `_label_text_requests` centers `Plot.labels()`'s titles on
    that rect rather than the outer bounds, so a wide legend or long tick
    labels don't throw a title off-center. Every `_render_*` raises before
    reaching any layout when its own data is empty (`_require_non_empty`,
    ), so there is no "no data" `_RenderResult` shape to report here.

    `y_scale`/`has_y_scale` expose the real `LinearScale` the mark's
    y-axis used, so the annotation passes (`_draw_annotation_lines`/
    `_draw_annotation_areas`) place values with the same `to_pixel` the
    data went through. `has_y_scale` defaults `False` with an inert
    placeholder scale; only the frames that support annotations pass a
    real one. `x_scale`/`has_x_scale` mirror that for the x-axis, set by
    `_ContinuousFrame.result()` and by
    `_HorizontalCategoricalFrame.result()`, whose continuous axis is the
    x one (#688); a vertical categorical frame sets neither, since its
    x-axis has no numeric domain. Which marks that leaves is
    `MarkType.supports_annotations_x` and `supports_annotations_xy`
    (mark.mojo), not a list restated here.
    """

    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int
    var y_scale: LinearScale
    var has_y_scale: Bool
    var x_scale: LinearScale
    var has_x_scale: Bool

    def __init__(
        out self,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
        y_scale: LinearScale = LinearScale(0.0, 0.0, 0.0, 0.0),
        has_y_scale: Bool = False,
        x_scale: LinearScale = LinearScale(0.0, 0.0, 0.0, 0.0),
        has_x_scale: Bool = False,
    ):
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1
        self.y_scale = y_scale
        self.has_y_scale = has_y_scale
        self.x_scale = x_scale
        self.has_x_scale = has_x_scale
