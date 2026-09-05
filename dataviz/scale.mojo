"""LinearScale maps a continuous data domain onto a pixel range and
picks "nice" tick positions within that domain for axis labeling.
`scale()`/`translate()` compute the slope/intercept
`canvas.geometry.Transform2D`'s affine map takes, so `Plot` builds a
Transform2D from an x-scale and a y-scale (the y-scale's range
reversed, since pixel y increases downward).

`ticks()` implements Paul Heckbert's "nice numbers for graph labels"
(Graphics Gems, 1990), the approach d3/matplotlib use: round the
ideal step for a target tick count up to the nearest 1, 2, 5, or 10
times a power of ten, so labels read as 0.2/0.4/0.6 rather than
0.1934/0.3868/0.5802.
"""

from std.math import ceil, floor, log10, pow
from std.utils.numerics import isfinite

from canvas.geometry import round_to_int


struct MinMax(ImplicitlyCopyable, Movable):
    """A column's [min, max], the starting point for every domain this
    package computes: `Plot._data_extent` pads it for spatial axes;
    `ColorScale`/size encoding use it as-is, so a legend's extremes are
    exactly the data's.
    """

    var min: Float64
    """The column's smallest value."""
    var max: Float64
    """The column's largest value."""

    def __init__(out self, min: Float64, max: Float64):
        """Construct a `MinMax` from an already-known min and max.

        Args:
            min: The column's smallest value.
            max: The column's largest value.
        """
        self.min = min
        self.max = max


def _min_max(data: List[Float64]) raises -> MinMax:
    """`data`'s [min, max]. Raises on an empty list, and on any non-finite
    (`NaN`/`inf`) value.

    Every list this package computes a spatial or color/size domain from
    passes through here first (`_data_extent`, `_zero_baseline_y_extent`,
    `_log_data_extent`, and every mark's own color/size `MinMax`), and the
    same list is what later gets mapped point-by-point onto pixels -- so
    this is the single narrow chokepoint (#190) where a `NaN`/`inf` value
    can be caught before it reaches a scale at all. Left unchecked, a
    non-finite value either poisons the whole domain into `(NaN, NaN)`
    (comparisons against `NaN` are always false, so `lo`/`hi` never
    recover once seeded from one) or survives the comparisons (`inf` has a
    well-defined order) and produces a domain no tick generator can label
    -- and either way, `Int(nan_or_inf)` later hands the SVG output
    `Int64::MIN` as a literal pixel coordinate with no error raised.

    An empty list has no honest [min, max]; a silent `MinMax(0.0, 0.0)`
    would hand back a degenerate domain that renders as a real axis,
    which is exactly the "silently misrepresent the data" failure this
    package's encode/render checks exist to prevent. A clear error at the
    boundary beats a plausible-looking wrong chart -- the same reasoning
    applies to non-finite values.
    """
    if len(data) == 0:
        raise Error("_min_max(): can't take the min/max of an empty column")
    var lo = data[0]
    var hi = data[0]
    for i in range(len(data)):
        var v = data[i]
        if not isfinite(v):
            raise Error(
                "_min_max(): every value must be finite -- got "
                + String(v)
                + " at index "
                + String(i)
            )
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    return MinMax(lo, hi)


struct _NiceStep(ImplicitlyCopyable, Movable):
    """`_nice_step`'s result."""

    var step: Float64
    var exponent: Int

    def __init__(out self, step: Float64, exponent: Int):
        self.step = step
        self.exponent = exponent


def _nice_step(
    domain_min: Float64, domain_max: Float64, target_count: Int
) -> _NiceStep:
    """The step size and its base-10 exponent for `target_count`-ish ticks
    spanning [domain_min, domain_max]. The exponent tells `_format_fixed`
    how many decimal places a tick needs; it can't be re-derived from the
    step via log10 afterward (a step of exactly 5.0 needs 0 decimals, but
    log10(5.0) is positive), and must track `nice_m`'s possible bump to
    the next power of ten.

    Examples: domain [0,100], target 5 -> step 20.0; domain [3,27],
    target 5 -> step 5.0 (raw step 4.8 rounds up); domain [-50,50],
    target 5 -> step 20.0 (only the span and log10 of a positive raw step
    are ever computed, so negative domains need no special case).
    """
    var raw_step = (domain_max - domain_min) / Float64(target_count)
    var exponent = Int(floor(log10(raw_step)))
    var magnitude = pow(10.0, Float64(exponent))
    var normalized = raw_step / magnitude

    var nice_m = 10.0
    if normalized <= 1.0 + 1e-9:
        nice_m = 1.0
    elif normalized <= 2.0 + 1e-9:
        nice_m = 2.0
    elif normalized <= 5.0 + 1e-9:
        nice_m = 5.0

    if nice_m == 10.0:
        nice_m = 1.0
        exponent += 1

    return _NiceStep(nice_m * pow(10.0, Float64(exponent)), exponent)


comptime _FORMAT_FIXED_MAX_EXACT_MAGNITUDE = 9007199254740992.0
"""2^53, the largest magnitude at or below which every integer is
exactly representable in a `Float64` (a `Float64` has a 52-bit mantissa
plus an implicit leading bit; 2^53 itself is exact, 2^53+1 is the first
value that isn't). `_format_fixed`'s digit-by-digit path rounds `value
* 10^decimals` through `round_to_int`'s `Int(Float64)` cast, which is
exact only up to this bound and silently wraps to garbage past it
(`Int` overflow on a float-to-int conversion is not checked); well
before that, `Int`'s own range (~9.223e18) would overflow outright for
a large enough `value`/`decimals` combination. Since a `Float64` past
this magnitude already has no representable fractional bits, treating
it as more precise than its own `String(Float64)` conversion is false
in the first place, so `_format_fixed`/`_label_decimals` defer to
`_format_fixed_overflow`/return `0` rather than risk either failure
mode (#205).
"""


def _format_fixed_overflow(value: Float64) -> String:
    """`_format_fixed`'s fallback for `abs(value) * 10^decimals` past
    `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`: Mojo's own `String(Float64)`,
    which switches to scientific notation at exactly this kind of
    magnitude ("1e+19", "-3e+18") and never overflows, unlike the
    digit-by-digit `Int`-based path this replaces. `decimals` is ignored
    here -- a magnitude this large has no representable fractional
    digits for it to mean anything against. Plain fixed/scientific
    notation, not the SI-prefixed or significant-digit-limited form a
    real large-magnitude tick formatter would use (see #210); this
    exists only so `_format_fixed` never produces incorrect output,
    not to make it pretty.
    """
    return String(value)


def _format_fixed(value: Float64, decimals: Int) -> String:
    """Format `value` to exactly `decimals` decimal places. Plain
    `String(Float64)` isn't usable for tick labels (0.0 + 3*0.1 prints as
    "0.30000000000000004"). Rounds to the nearest representable value at
    `decimals` places first (round-half-away-from-zero via
    `round_to_int`), then builds the string from integer and fractional
    parts by hand. `decimals` of 0 skips the decimal point rather than
    printing "20.".

    Falls back to `_format_fixed_overflow` when `abs(value) *
    10^decimals` exceeds `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`: past that
    point the digit-by-digit path below silently produces wrong digits
    (or, past `Int`'s own range, outright garbage -- see
    `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`'s own docstring) rather than
    raising, so this must catch it before ever calling `round_to_int`.
    """
    if decimals <= 0:
        if abs(value) > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
            return _format_fixed_overflow(value)
        return String(round_to_int(value))

    var scale = pow(10.0, Float64(decimals))
    if abs(value) * scale > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
        return _format_fixed_overflow(value)
    var scaled = round_to_int(value * scale)
    var sign = "-" if scaled < 0 else ""
    var digits = scaled if scaled >= 0 else -scaled
    var int_part = digits // Int(scale + 0.5)
    var frac_part = digits % Int(scale + 0.5)

    var frac_str = String(frac_part)
    while frac_str.byte_length() < decimals:
        frac_str = "0" + frac_str

    return sign + String(int_part) + "." + frac_str


def _label_decimals(value: Float64, max_decimals: Int = 2) -> Int:
    """The fewest decimal places (up to `max_decimals`) that represent
    `value` with no visible rounding error, for `Theme.show_data_labels`.
    Not tied to the axis's `Ticks.decimals`: an axis stepping by whole
    10s still needs a data label to show `15.3` as `15.3`.

    Checked by re-scaling and rounding at each candidate count with a
    1e-9 tolerance rather than exact float equality. Returns
    `max_decimals` if no smaller count clears that tolerance.

    Returns `0` immediately for `abs(value) >
    _FORMAT_FIXED_MAX_EXACT_MAGNITUDE` rather than entering the loop: a
    `Float64` that large has no representable fractional part for any
    decimal count to expose, and the loop's own `round_to_int(value *
    scale)` would hit the same overflow `_format_fixed` guards against
    (#205).
    """
    if abs(value) > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
        return 0
    for d in range(max_decimals + 1):
        var scale = pow(10.0, Float64(d))
        var rounded = Float64(round_to_int(value * scale)) / scale
        if abs(value - rounded) < 1e-9:
            return d
    return max_decimals


comptime _TICK_FORMAT_AUTO = 0
comptime _TICK_FORMAT_PERCENT = 1
comptime _TICK_FORMAT_THOUSANDS = 2
comptime _TICK_FORMAT_SI = 3
comptime _TICK_FORMAT_SCIENTIFIC = 4
comptime _TICK_FORMAT_FIXED = 5


struct TickFormat(Copyable, ImplicitlyCopyable, Movable):
    """How `Theme.x_tick_format`/`y_tick_format` (#210) render a tick
    label, `Theme.show_data_labels`'s value label, or a continuous
    legend's endpoint labels -- everywhere `Ticks.labels()`/
    `_format_tick()` are the formatter. Same small-struct-with-comptime-
    constants-and-`__eq__` pattern as `Mark`/`OutputFormat`, except
    `FIXED()` is a `@staticmethod` rather than a fixed comptime instance,
    since it carries a caller-chosen decimal count.

    - `AUTO` (default): today's behavior, `_format_fixed` at the domain's
      own nice-step decimal count.
    - `PERCENT`: `value * 100`, suffixed `%` -- `0.25` -> `"25%"`.
    - `THOUSANDS`: comma-grouped -- `1500000` -> `"1,500,000"`.
    - `SI`: SI-prefixed at the nearest 1000-power tier -- `1500000` ->
      `"1.5M"`, `0.0025` -> `"2.5m"`.
    - `SCIENTIFIC`: `"1.5e+6"` -- a decimal mantissa plus a signed
      exponent, unlike `_format_fixed_overflow`'s bare `String(Float64)`
      fallback. Also the principled version of that same fallback: past
      `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE`, `_format_tick` defers to this
      shape regardless of the requested format, so an overflow never
      produces raw digit garbage.
    - `FIXED(n)`: always `n` decimal places, ignoring the domain's own
      nice-step count -- for currency (`FIXED(2)`) or a whole-number axis
      (`FIXED(0)`) regardless of what step size the data picks.

    `prefix`/`suffix` wrap the formatted number for every kind
    (`FIXED(2).with_affixes(prefix="$")` -> `"$19.99"`); set via
    `with_affixes()` since comptime constants can't take a per-call
    string.
    """

    var _kind: Int
    var _n: Int
    var prefix: String
    var suffix: String

    comptime AUTO = Self(_TICK_FORMAT_AUTO, 0, "", "")
    comptime PERCENT = Self(_TICK_FORMAT_PERCENT, 0, "", "")
    comptime THOUSANDS = Self(_TICK_FORMAT_THOUSANDS, 0, "", "")
    comptime SI = Self(_TICK_FORMAT_SI, 0, "", "")
    comptime SCIENTIFIC = Self(_TICK_FORMAT_SCIENTIFIC, 0, "", "")

    def __init__(out self, kind: Int, n: Int, prefix: String, suffix: String):
        self._kind = kind
        self._n = n
        self.prefix = prefix
        self.suffix = suffix

    def __eq__(self, other: Self) -> Bool:
        return self._kind == other._kind and self._n == other._n

    @staticmethod
    def FIXED(decimals: Int) -> Self:
        """Always `decimals` places, regardless of the axis's own
        nice-step decimal count.

        Args:
            decimals: How many decimal places to always show.
        """
        return Self(_TICK_FORMAT_FIXED, decimals, "", "")

    def with_affixes(self, prefix: String = "", suffix: String = "") -> Self:
        """This format with `prefix`/`suffix` wrapped around every
        formatted number (`"$"`/`"/mo"`, ...).

        Args:
            prefix: Text prepended to every formatted number.
            suffix: Text appended to every formatted number.

        Returns:
            A copy of this format with the given affixes.
        """
        return Self(self._kind, self._n, prefix, suffix)


def _insert_thousands_separators(digits: String) -> String:
    """`digits` (an unsigned integer-part string, no sign or decimal
    point) with a comma inserted every 3 digits from the right --
    `"1500000"` -> `"1,500,000"`, `"999"` -> `"999"`.
    """
    var n = digits.byte_length()
    if n <= 3:
        return digits
    var out = List[String]()
    var first_group = n % 3
    if first_group == 0:
        first_group = 3
    out.append(String(digits[byte=0:first_group]))
    var i = first_group
    while i < n:
        out.append(String(digits[byte = i : i + 3]))
        i += 3
    return String(",").join(out)


def _format_thousands(value: Float64, decimals: Int) -> String:
    """`_format_fixed(value, decimals)` with comma group separators in
    the integer part (`TickFormat.THOUSANDS`).
    """
    var plain = _format_fixed(value, decimals)
    var sign = ""
    var rest = plain
    if plain.startswith("-"):
        sign = "-"
        rest = String(plain[byte=1:])
    var dot = rest.find(".")
    var int_part = rest if dot == -1 else String(rest[byte=0:dot])
    var frac_part = "" if dot == -1 else String(rest[byte=dot:])
    return sign + _insert_thousands_separators(int_part) + frac_part


def _si_tier(magnitude: Float64) -> _NiceStep:
    """The SI divisor (as `.step`) and its base-10 exponent (as
    `.exponent`, a multiple of 3) for `magnitude`'s tier -- reuses
    `_NiceStep` as a plain (divisor, tier) pair rather than adding a new
    struct. `magnitude` is `abs(value)`; `0.0` gets the `1.0`/no-suffix
    tier (`_si_suffix` returns `""` for exponent `0`).
    """
    if magnitude == 0.0:
        return _NiceStep(1.0, 0)
    var exponent = Int(floor(log10(magnitude) / 3.0)) * 3
    if exponent > 12:
        exponent = 12
    if exponent < -9:
        exponent = -9
    return _NiceStep(pow(10.0, Float64(exponent)), exponent)


def _si_suffix(exponent: Int) -> String:
    """The SI prefix letter for a `_si_tier()` exponent (a multiple of
    3, `-9`..`12`); `""` for `0` (no scaling needed).
    """
    if exponent == 12:
        return "T"
    if exponent == 9:
        return "G"
    if exponent == 6:
        return "M"
    if exponent == 3:
        return "k"
    if exponent == -3:
        return "m"
    if exponent == -6:
        return "µ"
    if exponent == -9:
        return "n"
    return ""


def _format_si(value: Float64) -> String:
    """`value` scaled to its nearest SI-prefix tier (`_si_tier`), with
    the fewest decimals (`_label_decimals`, up to 2) that represent the
    scaled value exactly -- `1500000.0` -> `"1.5M"`, `2000000.0` ->
    `"2M"`, `0.0` -> `"0"`.
    """
    if value == 0.0:
        return "0"
    var tier = _si_tier(abs(value))
    var scaled = value / tier.step
    return _format_fixed(scaled, _label_decimals(scaled)) + _si_suffix(
        tier.exponent
    )


def _format_scientific(value: Float64) -> String:
    """`value` as a decimal mantissa (1 <= |mantissa| < 10, the fewest
    decimals up to 2 that represent it exactly) times a signed power of
    ten -- `1500000.0` -> `"1.5e+6"`, `0.0025` -> `"2.5e-3"`, `0.0` ->
    `"0e+0"`.
    """
    if value == 0.0:
        return "0e+0"
    var exponent = Int(floor(log10(abs(value))))
    var mantissa = value / pow(10.0, Float64(exponent))
    # Rounding a mantissa like 9.9996 at 2 decimals can round up to
    # 10.00; renormalize rather than print a two-digit mantissa.
    if abs(mantissa) >= 9.995:
        mantissa /= 10.0
        exponent += 1
    var sign = "+" if exponent >= 0 else "-"
    return (
        _format_fixed(mantissa, _label_decimals(mantissa))
        + "e"
        + sign
        + String(abs(exponent))
    )


def _format_tick(value: Float64, decimals: Int, format: TickFormat) -> String:
    """`value` formatted per `format` (#210), the shared formatter
    `Ticks.labels()`, `Theme.show_data_labels`, and a continuous legend's
    endpoint labels all defer to. `decimals` is the axis's own nice-step
    decimal count, used as-is for `AUTO` and adjusted for `PERCENT`
    (`value * 100` needs 2 fewer decimal places for the same precision);
    `THOUSANDS`/`SI`/`SCIENTIFIC`/`FIXED` each pick their own decimal
    count instead.

    Falls back to `_format_scientific` regardless of `format` once
    `abs(value)` exceeds `_FORMAT_FIXED_MAX_EXACT_MAGNITUDE` -- the same
    boundary `_format_fixed`/`_format_fixed_overflow` guard against,
    since every kind here except `SCIENTIFIC` itself still routes through
    `_format_fixed` internally and would hit the identical overflow.
    """
    if abs(value) > _FORMAT_FIXED_MAX_EXACT_MAGNITUDE:
        return format.prefix + _format_scientific(value) + format.suffix
    if format == TickFormat.AUTO:
        return format.prefix + _format_fixed(value, decimals) + format.suffix
    if format == TickFormat.PERCENT:
        return (
            format.prefix
            + _format_fixed(value * 100.0, max(0, decimals - 2))
            + "%"
            + format.suffix
        )
    if format == TickFormat.THOUSANDS:
        return (
            format.prefix + _format_thousands(value, decimals) + format.suffix
        )
    if format == TickFormat.SI:
        return format.prefix + _format_si(value) + format.suffix
    if format == TickFormat.SCIENTIFIC:
        return format.prefix + _format_scientific(value) + format.suffix
    # FIXED(n): the only remaining _kind.
    return format.prefix + _format_fixed(value, format._n) + format.suffix


def _log_ticks(domain_min: Float64, domain_max: Float64) -> Ticks:
    """Tick positions for a log10-scaled `LinearScale`. `domain_min`/
    `domain_max` are in log10-space (per `LinearScale.to_pixel()`), so
    `10.0**domain_min`/`10.0**domain_max` are the real-unit bounds.
    Returns real-unit values (1, 10, 100, ...), since `to_pixel()` takes
    `log10()` of its input itself when `is_log` is set.

    Major ticks only (`1 * 10^k`) when the visible span covers more than
    2 decades (matplotlib's `LogLocator` convention); `1`/`2`/`5 * 10^k`
    per decade otherwise. Domain `[0, 3]` (real `[1, 1000]`) gives
    `[1, 10, 100, 1000]`; domain `[0, 1]` (real `[1, 10]`) gives
    `[1, 2, 5, 10]`.

    A zero-span domain returns a single tick at the one real value. A
    domain too narrow to contain any `1`/`2`/`5` multiple (e.g.
    `[35, 40]`) falls back to its two real endpoints.
    """
    if domain_min == domain_max:
        var v = pow(10.0, domain_min)
        var single: List[Float64] = [v]
        var single_label: List[String] = [
            _format_fixed(v, max(0, -Int(floor(domain_min))))
        ]
        return Ticks(single^, 0, single_label^)

    var start_exp = Int(floor(domain_min))
    var end_exp = Int(ceil(domain_max))
    var lo = pow(10.0, domain_min)
    var hi = pow(10.0, domain_max)
    var wide = (end_exp - start_exp) > 2

    var values = List[Float64]()
    var labels = List[String]()
    for e in range(start_exp, end_exp + 1):
        var decade = pow(10.0, Float64(e))
        var mults: List[Float64] = [1.0] if wide else [1.0, 2.0, 5.0]
        for m in mults:
            var v = m * decade
            # A tiny relative tolerance against the real bounds, so a tick that
            # should land exactly on a padded boundary (computed through
            # pow()/floor()/ceil()) isn't dropped by floating-point rounding.
            if v >= lo * (1.0 - 1e-9) and v <= hi * (1.0 + 1e-9):
                values.append(v)
                labels.append(_format_fixed(v, max(0, -e)))

    if len(values) == 0:
        values = [lo, hi]
        labels = [
            _format_fixed(lo, max(0, -start_exp)),
            _format_fixed(hi, max(0, -end_exp)),
        ]

    return Ticks(values^, 0, labels^)


struct Ticks(Movable):
    """`LinearScale.ticks()`'s result: the tick positions plus how many
    decimal places they need for display, both from the same
    `_nice_step` computation.
    """

    var values: List[Float64]
    """The tick positions themselves, in the scale's data domain."""
    var decimals: Int
    """How many decimal places every tick value needs for display, from
    `_nice_step`. Unused when `override_labels` is non-empty.
    """
    var override_labels: List[String]
    """Pre-formatted labels, one per `values` entry; empty (the default)
    when every tick shares one `decimals` count. Non-empty only for
    `_log_ticks()`, where each tick needs its own decimal count (0.01
    needs 2 places, 100 needs 0).
    """

    def __init__(
        out self,
        var values: List[Float64],
        decimals: Int,
        var override_labels: List[String] = List[String](),
    ):
        """Construct a `Ticks` from already-computed positions and a decimal
        count; normally built by `LinearScale.ticks()`.

        Args:
            values: The tick positions, in the scale's data domain.
            decimals: How many decimal places every tick value needs
                for display. Ignored if `override_labels` is given.
            override_labels: Pre-formatted labels, one per `values`
                entry; left empty (the default) to format every tick
                via `decimals` instead.
        """
        self.values = values^
        self.decimals = decimals
        self.override_labels = override_labels^

    def labels(self, format: TickFormat = TickFormat.AUTO) -> List[String]:
        """Each tick value formatted via `_format_tick()` at this `Ticks`'
        `decimals` (#210), or `override_labels` unchanged when set --
        `format` doesn't apply to `override_labels` (only `_log_ticks()`
        sets it today, and each of its labels already carries its own
        per-tick decimal count; log-axis tick formatting is a follow-up).

        Args:
            format: How to render each value; `AUTO` (the default)
                matches this method's pre-#210 behavior exactly.

        Returns:
            One formatted string per `values` entry, same order.
        """
        if len(self.override_labels) > 0:
            return self.override_labels.copy()
        var result = List[String](capacity=len(self.values))
        for v in self.values:
            result.append(_format_tick(v, self.decimals, format))
        return result^


struct LinearScale(ImplicitlyCopyable, Movable):
    """A linear map from [domain_min, domain_max] to [range_min, range_max].
    `range_min`/`range_max` are the pixel positions `domain_min`/
    `domain_max` land on, not necessarily increasing: a y-axis scale
    passes range_min=plot_bottom_pixel and range_max=plot_top_pixel, and
    the map comes out with a negative slope.
    """

    var domain_min: Float64
    """The low end of the data domain this scale maps from."""
    var domain_max: Float64
    """The high end of the data domain this scale maps from."""
    var range_min: Float64
    """The pixel position `domain_min` maps to."""
    var range_max: Float64
    """The pixel position `domain_max` maps to; not necessarily greater
    than `range_min` (a y-axis scale passes a smaller pixel value here).
    """
    var is_log: Bool
    """`False` (the default) for a plain linear scale. `True` for a
    log10-scaled axis (`Plot.scale_y_log()`/`scale_x_log()`):
    `domain_min`/`domain_max` are then in log10-space (see
    `_log_data_extent()`, plot.mojo) and `to_pixel()` takes `log10()` of
    the real-unit value it's given before applying the affine map, so
    every caller keeps passing real-unit values.
    """

    def __init__(
        out self,
        domain_min: Float64,
        domain_max: Float64,
        range_min: Float64,
        range_max: Float64,
        is_log: Bool = False,
    ):
        """Construct a `LinearScale` from an already-known domain and
        pixel range.

        Args:
            domain_min: The low end of the data domain.
            domain_max: The high end of the data domain.
            range_min: The pixel position `domain_min` maps to.
            range_max: The pixel position `domain_max` maps to.
            is_log: Whether `domain_min`/`domain_max` are in log10-
                space and `to_pixel()` should log-transform its input
                first; see this field's own docstring.
        """
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.range_min = range_min
        self.range_max = range_max
        self.is_log = is_log

    def scale(self) -> Float64:
        """The slope for a Transform2D built from this axis:
        (range_max - range_min) / (domain_max - domain_min). A zero domain
        span returns 0.0 rather than dividing by zero; every input then maps
        to range_min.
        """
        var span = self.domain_max - self.domain_min
        if span == 0.0:
            return 0.0
        return (self.range_max - self.range_min) / span

    def translate(self) -> Float64:
        """The intercept for a Transform2D built from this axis, derived from
        scale() so `to_pixel(domain_min) == range_min` exactly.
        """
        return self.range_min - self.domain_min * self.scale()

    def to_pixel(self, value: Float64) -> Float64:
        """Map a data value onto its pixel position: `scale()` times `value`
        plus `translate()`. Takes `log10(value)` first when `is_log` is set;
        `value` is always the real, untransformed data value.

        Args:
            value: The data value to map, in real units (never
                pre-logged, even when `is_log` is set).

        Returns:
            The pixel position `value` lands on.
        """
        var v = log10(value) if self.is_log else value
        return v * self.scale() + self.translate()

    def ticks(self, target_count: Int = 5) -> Ticks:
        """ "Nice" tick positions within [domain_min, domain_max] (see
        `_nice_step`), from ceil(domain_min/step)*step to
        floor(domain_max/step)*step, so ticks never extend past the domain; a
        tick landing exactly on a boundary is included (domain [0,100]
        includes both 0 and 100).

        A zero-span domain returns a single tick at domain_min with 0
        decimals, since the nice-step math would need log10(0).

        Args:
            target_count: Roughly how many ticks to aim for; the
                actual count depends on which "nice" step size the
                domain rounds to. Defaults to `5`.

        Returns:
            The computed tick positions and their shared decimal
            count.
        """
        if self.is_log:
            return _log_ticks(self.domain_min, self.domain_max)
        if self.domain_min == self.domain_max:
            var single: List[Float64] = [self.domain_min]
            return Ticks(single^, 0)

        var nice = _nice_step(self.domain_min, self.domain_max, target_count)
        var decimals = max(0, -nice.exponent)

        var start = ceil(self.domain_min / nice.step) * nice.step
        var stop = floor(self.domain_max / nice.step) * nice.step
        var count = round_to_int((stop - start) / nice.step) + 1

        var result = List[Float64](capacity=count)
        for i in range(count):
            result.append(start + Float64(i) * nice.step)

        return Ticks(result^, decimals)
