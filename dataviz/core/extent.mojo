"""The padded data extents marks lay out against: linear, log,
symlog, zero-baseline, and the x position extent a `Plot` resolves.
Split out of plot.mojo, which imports every name here back."""

from std.math import log10
from dataviz.core.scale import LinearScale, _min_max, _symlog_forward
from dataviz.plot import Plot


def _data_extent(data: List[Float64]) raises -> LinearScale:
    """Return `data`'s minimum and maximum padded 5% on each side.

    So that a point at the extreme is not drawn half-clipped on the
    frame.

    The consequence is worth stating because it surprises people (#133):
    **the axis line is not the origin.** For `x = [1, 10]` the domain
    becomes about `[0.55, 10.45]`, so the y-axis line stands at 0.55,
    and the first point is not halfway between the axis and the "2"
    tick. It is in the right place; the axis line just does not name a
    value, and only the tick marks do. `scale_x_domain()` is the way to
    an axis line that means something, and the zero-baseline marks below
    get one for free.

    The scale's placeholder unit range is replaced during rendering once the
    plot area is known. A zero-span column gets a fixed 1.0 padding.
    Spatial axes only; color/size domains use `_min_max` unpadded so a
    legend's extremes are the data's.
    """
    var mm = _min_max(data)
    var span = mm.max - mm.min
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(mm.min - pad, mm.max + pad, 0.0, 1.0)


def _zero_baseline_y_extent(data: List[Float64]) raises -> LinearScale:
    """The y-domain for a mark whose fill/height encodes magnitude from a
    baseline (`Mark.BAR`, `Mark.AREA`, ...): always includes zero. Pads
    only the end that isn't already zero, so zero stays an exact axis
    endpoint whenever every value sits on one side of it.
    """
    var mm = _min_max(data)
    var lo = min(0.0, mm.min)
    var hi = max(0.0, mm.max)
    var span = hi - lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    var padded_lo = lo - pad if lo < 0.0 else lo
    var padded_hi = hi + pad if hi > 0.0 else hi
    return LinearScale(padded_lo, padded_hi, 0.0, 1.0)


def _symlog_data_extent(
    data: List[Float64], linthresh: Float64
) raises -> LinearScale:
    """`_data_extent()`'s symlog counterpart for `Plot.scale_x_symlog()`/
    `scale_y_symlog()` (#368).

    Every value is allowed, including zero and negatives -- that is the
    whole point of the transform, and why this has no equivalent of
    `_log_data_extent`'s positivity check. The domain is computed and
    padded in symlog space, 5% of the transformed span, because that is
    the space the axis is linear in and so the space a constant margin
    means something in.

    The returned scale carries `is_symlog` and the threshold; values are
    still passed to `to_pixel()` in real units.

    Args:
        data: The column to size the axis from.
        linthresh: Half-width of the linear region, real units.

    Returns:
        The scale, ranged 0 to 1 for the frame to re-range.

    Raises:
        Error: `linthresh` is not positive, or `data` is empty or
            non-finite (via `_min_max`).
    """
    if linthresh <= 0.0:
        raise Error(
            "scale_x_symlog()/scale_y_symlog(): linthresh must be positive"
            " -- it is the half-width of the linear region around zero,"
            " and a zero or negative width leaves nowhere for zero to"
            " live (got "
            + String(linthresh)
            + ")"
        )
    var mm = _min_max(data)
    var lo = _symlog_forward(mm.min, linthresh)
    var hi = _symlog_forward(mm.max, linthresh)
    var span = hi - lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(
        lo - pad,
        hi + pad,
        0.0,
        1.0,
        is_symlog=True,
        symlog_linthresh=linthresh,
    )


def _position_x_extent(plot: Plot, values: List[Float64]) raises -> LinearScale:
    """The x domain for a mark that only places positions: log, symlog or
    linear, the same choice `_render_generic` makes for POINT (#687).

    RUG and ECDF use it. Neither computes anything from x's spacing, so
    once the domain is in the right space the scale does the rest:
    `to_pixel()` takes the log itself.

    Those marks have no y transform to honor, and `scale_y_symlog()` is
    gated by the same table entry as `scale_x_log()`, so it would pass
    validation and then change nothing. It raises here instead.

    Args:
        plot: The chart, for its scale flags.
        values: The observations.

    Returns:
        The x domain.

    Raises:
        Error: `scale_y_symlog()` was set, or a value is not positive
            under `scale_x_log()`.
    """
    if plot._y_symlog:
        raise Error(
            "Plot.scale_y_symlog(): "
            + plot._mark.name()
            + " has no y axis to transform. scale_x_log() and"
            " scale_x_symlog() apply to its x axis"
        )
    if plot._x_log:
        return _log_data_extent(values)
    if plot._x_symlog:
        return _symlog_data_extent(values, plot._x_symlog_linthresh)
    return _data_extent(values)


def _log_data_extent(data: List[Float64]) raises -> LinearScale:
    """`_data_extent()`'s log10 counterpart for `Plot.scale_y_log()`/
    `scale_x_log()`. Raises if any value isn't strictly positive. The
    domain is computed and padded in log10-space (5% of the log span, or
    a fixed 1.0-decade pad for a zero span), since a log axis's breathing
    room is multiplicative. The returned scale has `is_log=True`; values
    are still passed to `to_pixel()` in real units.
    """
    for v in data:
        if v <= 0.0:
            raise Error(
                "scale_y_log()/scale_x_log(): every value must be > 0 for a"
                " log-scaled axis (log10(0) and log10(negative) are undefined)"
                " -- got "
                + String(v)
            )
    var mm = _min_max(data)
    var log_lo = log10(mm.min)
    var log_hi = log10(mm.max)
    var span = log_hi - log_lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    return LinearScale(log_lo - pad, log_hi + pad, 0.0, 1.0, is_log=True)
