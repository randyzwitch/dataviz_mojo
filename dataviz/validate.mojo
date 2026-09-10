"""Shared encoding and render-time validation."""

from std.math import log10

from dataviz.continuous import _draw_area_layer, _draw_line_layer, area, line
from dataviz.layers import _render_layers_generic, render_layers
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _DomainOverride,
    _RenderResult,
    _data_extent,
    _log_data_extent,
    _render_generic,
    render,
)
from dataviz.scale import LinearScale
from dataviz.step_style import StepStyle
from dataviz.theme import Theme


def _require_non_empty(count: Int, context: String) raises:
    """Raise with `context` when a mark has no data."""
    if count == 0:
        raise Error(
            context + ": there is no data to draw (every column is empty)"
        )


def _validate_categorical_encoding(plot: Plot) raises:
    """`Plot.encode_categorical()`'s length check plus its empty-data check
       (`_require_non_empty`), shared by every mark reading a
       category/value pair. Also validates `y_err`/`y_err_lower`/`y_err_upper`
    when set, mirroring `_validate_continuous_encoding`'s rules for
       `encode()`'s same three channels but against `x_categories`' length and
       restricted to `Mark.BAR` -- the only categorical mark drawing them today.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_categorical(): x and y must have the same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )
    _require_non_empty(len(plot.x_categories), "Plot.encode_categorical()")

    var has_y_err = len(plot.y_err_data) > 0
    var has_y_err_lower = len(plot.y_err_lower_data) > 0
    var has_y_err_upper = len(plot.y_err_upper_data) > 0
    if not (has_y_err or has_y_err_lower or has_y_err_upper):
        return

    if has_y_err_lower != has_y_err_upper:
        raise Error(
            "Plot.encode_categorical(): y_err_lower and y_err_upper must be"
            " given together (got only one)"
        )
    if (has_y_err_lower or has_y_err_upper) and has_y_err:
        raise Error(
            "Plot.encode_categorical(): y_err and y_err_lower/y_err_upper are"
            " mutually exclusive -- pass one or the other, not both"
        )
    if not (plot._mark == Mark.BAR or plot._mark == Mark.POINTPLOT):
        raise Error(
            "Plot.encode_categorical(): y_err/y_err_lower/y_err_upper is only"
            " supported for Mark.BAR and Mark.POINTPLOT today"
        )
    if has_y_err and len(plot.y_err_data) != len(plot.x_categories):
        raise Error(
            "Plot.encode_categorical(): y_err must be the same length as"
            " x/y (got "
            + String(len(plot.y_err_data))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )
    if has_y_err:
        for v in plot.y_err_data:
            if v < 0.0:
                raise Error(
                    "Plot.encode_categorical(): y_err values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    if has_y_err_lower and len(plot.y_err_lower_data) != len(plot.x_categories):
        raise Error(
            "Plot.encode_categorical(): y_err_lower must be the same length"
            " as x/y (got "
            + String(len(plot.y_err_lower_data))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )
    if has_y_err_upper and len(plot.y_err_upper_data) != len(plot.x_categories):
        raise Error(
            "Plot.encode_categorical(): y_err_upper must be the same length"
            " as x/y (got "
            + String(len(plot.y_err_upper_data))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )
    if has_y_err_lower:
        for v in plot.y_err_lower_data:
            if v < 0.0:
                raise Error(
                    "Plot.encode_categorical(): y_err_lower values must be"
                    " >= 0 (got "
                    + String(v)
                    + ")"
                )
    if has_y_err_upper:
        for v in plot.y_err_upper_data:
            if v < 0.0:
                raise Error(
                    "Plot.encode_categorical(): y_err_upper values must be"
                    " >= 0 (got "
                    + String(v)
                    + ")"
                )


def _require_non_negative(values: List[Float64], mark_name: String) raises:
    """Every value non-negative, or raise naming `mark_name`; a negative
    value has no width/radius/area for the marks that call this.
    """
    for v in values:
        if v < 0.0:
            raise Error(
                "Plot: "
                + mark_name
                + " values must be non-negative (got "
                + String(v)
                + ")"
            )


def _require_some_positive(
    values: List[Float64], mark_name: String
) raises -> Float64:
    """The largest of `values`, having checked at least one is strictly
    positive; for the marks whose geometry divides by the maximum
    (`value / max`), where all-zero input has no layout. Returns the
    maximum since every caller needs it as the divisor.
    """
    var largest = 0.0
    for v in values:
        if v > largest:
            largest = v
    if largest <= 0.0:
        raise Error(
            "Plot: "
            + mark_name
            + " requires at least one positive value (largest value was "
            + String(largest)
            + ")"
        )
    return largest


def _validate_continuous_encoding(plot: Plot, context: String) raises:
    """Every check `Plot.encode()`'s channels need before a continuous-axis
    render starts, shared by `_render_generic` and
    `_render_layers_generic`. `context` prefixes each message
    (`"Plot.encode()"` or `"render_layers(): layer 2"`). The allow-list
    `render_layers()` enforces is specific to layering and stays at its
    call site (`_is_layerable_mark`, layers.mojo).
    """
    if len(plot.x_data) != len(plot.y_data):
        raise Error(
            context
            + ": x and y must have the same length (got "
            + String(len(plot.x_data))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )
    var has_color = len(plot.color_data) > 0
    var has_color_categories = len(plot.color_categories) > 0
    var has_size = len(plot.size_data) > 0
    if has_color and len(plot.color_data) != len(plot.x_data):
        raise Error(
            context
            + ": color must be the same length as x/y (got "
            + String(len(plot.color_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_color_categories and len(plot.color_categories) != len(plot.x_data):
        raise Error(
            context
            + ": color_categories must be the same length as x/y (got "
            + String(len(plot.color_categories))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_color and has_color_categories:
        raise Error(
            context
            + ": color and color_categories are mutually exclusive -- pass"
            " one or the other, not both"
        )
    if has_size and len(plot.size_data) != len(plot.x_data):
        raise Error(
            context
            + ": size must be the same length as x/y (got "
            + String(len(plot.size_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if (has_color or has_color_categories or has_size) and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.SINGLE_AXIS
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": color/size encoding is only supported for"
            " Mark.POINT/SINGLE_AXIS/EFFECT_SCATTER today"
        )
    var has_y_err = len(plot.y_err_data) > 0
    if has_y_err and len(plot.y_err_data) != len(plot.x_data):
        raise Error(
            context
            + ": y_err must be the same length as x/y (got "
            + String(len(plot.y_err_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_y_err:
        for v in plot.y_err_data:
            if v < 0.0:
                raise Error(
                    context
                    + ": y_err values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    # No Mark.SINGLE_AXIS here: a single-axis plot has no y-domain for an
    # error bar. Mark.LINE is included, unlike color/size, since a
    # per-point confidence whisker on a line is common (see
    # _draw_line_layer).
    if has_y_err and not (
        plot._mark == Mark.POINT
        or plot._mark == Mark.LINE
        or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": y_err is only supported for Mark.POINT/LINE/EFFECT_SCATTER"
            " today"
        )

    var has_y_err_lower = len(plot.y_err_lower_data) > 0
    var has_y_err_upper = len(plot.y_err_upper_data) > 0
    if has_y_err_lower != has_y_err_upper:
        raise Error(
            context
            + ": y_err_lower and y_err_upper must be given together (got only"
            " one)"
        )
    if (has_y_err_lower or has_y_err_upper) and has_y_err:
        raise Error(
            context
            + ": y_err and y_err_lower/y_err_upper are mutually exclusive --"
            " pass one or the other, not both"
        )
    if has_y_err_lower and len(plot.y_err_lower_data) != len(plot.x_data):
        raise Error(
            context
            + ": y_err_lower must be the same length as x/y (got "
            + String(len(plot.y_err_lower_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_y_err_upper and len(plot.y_err_upper_data) != len(plot.x_data):
        raise Error(
            context
            + ": y_err_upper must be the same length as x/y (got "
            + String(len(plot.y_err_upper_data))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_y_err_lower:
        for v in plot.y_err_lower_data:
            if v < 0.0:
                raise Error(
                    context
                    + ": y_err_lower values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    if has_y_err_upper:
        for v in plot.y_err_upper_data:
            if v < 0.0:
                raise Error(
                    context
                    + ": y_err_upper values must be >= 0 (got "
                    + String(v)
                    + ")"
                )
    if (has_y_err_lower or has_y_err_upper) and not (
        plot._mark == Mark.POINT or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": y_err_lower/y_err_upper are only supported for"
            " Mark.POINT/EFFECT_SCATTER today"
        )

    if len(plot.color_map) > 0 and not has_color_categories:
        raise Error(
            context
            + ": color_map is only meaningful alongside color_categories --"
            " got a"
            " color_map with color_categories empty"
        )

    var has_labels = len(plot.point_labels) > 0
    if has_labels and len(plot.point_labels) != len(plot.x_data):
        raise Error(
            context
            + ": labels must be the same length as x/y (got "
            + String(len(plot.point_labels))
            + " and "
            + String(len(plot.x_data))
            + ")"
        )
    if has_labels and not (
        plot._mark == Mark.POINT or plot._mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            context
            + ": labels is only supported for Mark.POINT/EFFECT_SCATTER today"
        )


def _validate_domain_override(
    override: _DomainOverride, is_log: Bool, context: String
) raises:
    """`Plot.scale_x_domain()`/`scale_y_domain()`'s own value
    checks: `min < max` always, and (mirroring `_log_data_extent()`'s
    positivity requirement) `min > 0` when the matching axis is
    log-scaled. A no-op when `override.has` is `False`.
    """
    if not override.has:
        return
    if override.min >= override.max:
        raise Error(
            context
            + "(): min must be less than max (got min="
            + String(override.min)
            + ", max="
            + String(override.max)
            + ")"
        )
    if is_log and override.min <= 0.0:
        raise Error(
            context
            + "(): min must be > 0 for a log-scaled axis (log10(0) and"
            " log10(negative) are undefined) -- got "
            + String(override.min)
        )


def _domain_override_scale(
    override: _DomainOverride, is_log: Bool
) -> LinearScale:
    """`override` as a `LinearScale` with a `[0, 1]` placeholder range
    (the caller's frame-building step resolves the real pixel range, same
    as `_data_extent()`'s own return), in log10-space when `is_log` --
    already validated positive by `_validate_domain_override()`.
    """
    if is_log:
        return LinearScale(
            log10(override.min), log10(override.max), 0.0, 1.0, is_log=True
        )
    return LinearScale(override.min, override.max, 0.0, 1.0)


def _check_line_smoothing(theme: Theme) raises:
    """`Theme.line_smoothing`'s `[0.0, 1.0]` range check. Called by
    `_draw_line_layer`/`_draw_area_layer`, so it covers the layered
    render path too.
    """
    if theme.line_smoothing < 0.0 or theme.line_smoothing > 1.0:
        raise Error(
            "Theme.line_smoothing must be in [0.0, 1.0] (got "
            + String(theme.line_smoothing)
            + ")"
        )


def _step_setter_name(mark: Mark) -> String:
    """The `Plot` builder whose `step=` argument a mark's step came from:
    `Mark.STREAMGRAPH` -> `"Plot.mark_streamgraph(step=...)"`.

    Derived from `Mark.name()` rather than looked up. Every
    builder in plot.mojo is `mark_` followed by its constant's
    lowercased name -- all 51 of them, `mark_polar_bar` and
    `mark_arc_diagram` included -- so the chain of `==` this replaced
    was a second copy of a mapping the constant names already carry, and
    it grew a branch every time a mark gained a `step`. Deriving it
    means a new stepped mark gets the right setter named with no edit
    here at all.

    A mark outside the constants (`Mark(n)` is public) has no builder
    name to derive, so it falls back to `Plot.mark_line(step=...)`,
    which is what the old chain returned for everything it did not
    list.

    Args:
        mark: The mark being drawn.

    Returns:
        The fully spelled builder call, ready to drop into a message.
    """
    var name = mark.name()
    if not name.startswith("Mark."):
        return "Plot.mark_line(step=...)"
    return "Plot.mark_" + String(name[byte=5:]).lower() + "(step=...)"


def _check_step_smoothing(
    theme: Theme, step: StepStyle, mark: Mark = Mark.LINE
) raises:
    """`Theme.line_smoothing` and `mark_line(step=...)`/
    `mark_area(step=...)` are mutually exclusive; raise when
    both are asked for.

    A smoothed staircase is not a compromise between the two, it is
    neither: the Catmull-Rom tangents `_build_line_path` fits round off
    the corners that are the whole point of a step, and a riser's two
    points share an x, so the tangent through them is horizontal and the
    curve bows sideways out past the samples. There is no sensible
    "smoothed step" to fall back to, and picking a winner silently would
    mean one of two explicit settings quietly doing nothing -- so this
    says which two settings conflict instead.

    `Mark.AREA` is not the milder case it might look like. Its fill only
    makes the bowing worse: a stroked line that bows sideways past a
    riser shows a thin overshoot, while a filled one hands that
    overshoot the whole column of pixels down to the baseline, so the
    chart claims area under an x the data never reached. It raises for
    the same reason and with the same wording, differing only in which
    method to go and change.

    `Mark.STREAMGRAPH` is the case where the conflict is most
    likely to be hit by accident, because `streamgraph()` sets
    `line_smoothing` to `0.6` itself: a stepped stream would raise on
    its own default. That is why only `stacked_area()`, whose default
    is `0.0`, exposes `step` as a one-call parameter -- and why the
    message has to name `Plot.mark_streamgraph(step=...)` rather than a
    line or area setter the caller never touched. `_step_setter_name`
    derives that from `mark`, so the next mark to gain a `step` is named
    correctly without an edit here.

    Called by `_draw_line_layer` and `_draw_area_layer` beside
    `_check_line_smoothing`, by `_render_bar_combo_layers`' two inline
    branches, and by `_render_streamgraph`, so every path that can
    honor a step also refuses to smooth one.

    Args:
        theme: The plot's theme, for `line_smoothing`.
        step: The mark's step style, from `_MarkStyle.step`.
        mark: Which mark is being drawn, so the message names the
            setter the caller actually reached for (`Mark.AREA` ->
            `Plot.mark_area(step=...)`, `Mark.STREAMGRAPH` ->
            `Plot.mark_streamgraph(step=...)`). Defaulted to `Mark.LINE`
            for the call sites that predate `Mark.AREA` having a step.

    Raises:
        Error: Both a non-`NONE` `step` and a non-zero `line_smoothing`.
    """
    if step != StepStyle.NONE and theme.line_smoothing > 0.0:
        raise Error(
            "Theme.line_smoothing and "
            + _step_setter_name(mark)
            + " are mutually"
            " exclusive -- a smoothed staircase rounds off the corners that"
            " carry its meaning (got line_smoothing="
            + String(theme.line_smoothing)
            + " with step=StepStyle."
            + step.name()
            + ")"
        )
