"""`Theme.color_ramp`'s type: a many-stop continuous gradient (#332)."""

from canvas.color import Color


comptime _RAMP_CAPACITY = 64
"""The most stops a `ColorRamp` holds. Sets `_packed`'s SIMD width, so it
must stay a power of two. The built-in maps in `dataviz.colormaps` are
exactly this long."""


struct ColorRamp(ImplicitlyCopyable, Movable, Sized):
    """A continuous gradient given as an arbitrary number of stops, for
    `Theme.color_ramp`. Empty means "unset", leaving
    `Theme.color_scale_low`/`mid`/`high` in charge.

    Build one from a list of colors -- `ColorRamp(viridis())`, or just
    `Theme(color_ramp=viridis())`, since the list constructor is
    `@implicit`.

    **Why the stops are packed into a SIMD vector rather than held in a
    `List`.** `Theme` is `ImplicitlyCopyable` and is copied implicitly
    throughout the package (`var theme = plot._theme`), so every one of
    its fields has to be implicitly copyable too. `List` is not, and
    neither is `InlineArray`; that is why `default_categorical_palette()`
    and `_gauge_band_colors()` are free functions instead of `Theme`
    fields. A SIMD vector is, so the stops are packed one color per
    `UInt32` (`0x00RRGGBB`) into a fixed-width one. The cost is 256 bytes
    on `Theme` and a hard cap of `_RAMP_CAPACITY` stops; the alternative
    was writing `Theme.__copyinit__` out across all of its fields by
    hand, which would silently drop any field added afterwards.

    A ramp longer than the cap is **resampled** to it, evenly, rather
    than truncated -- a gradient is a continuous object, so resampling is
    the meaningful operation on one, and it keeps the top end instead of
    cutting it off. Resampling matplotlib's full 256-entry tables down to
    64 and reading them back out costs at most 2 levels per channel out
    of 255, which is below a perceptible step; see `dataviz.colormaps`.
    """

    var _packed: SIMD[DType.uint32, _RAMP_CAPACITY]
    """Each stop as `0x00RRGGBB`; entries at and past `count` are zero."""
    var count: Int
    """How many stops the ramp holds. `0` is an unset ramp."""

    def __init__(out self):
        """An empty ramp: `Theme` falls back to its three scalar stops."""
        self._packed = SIMD[DType.uint32, _RAMP_CAPACITY](0)
        self.count = 0

    @implicit
    def __init__(out self, stops: List[Color]):
        """Pack `stops`, resampling evenly if there are more than
        `_RAMP_CAPACITY` of them.

        Args:
            stops: The gradient's stops, in order.
        """
        self._packed = SIMD[DType.uint32, _RAMP_CAPACITY](0)
        var n = len(stops)
        if n <= _RAMP_CAPACITY:
            self.count = n
            for i in range(n):
                self._packed[i] = Self._pack(stops[i])
            return

        # More stops than fit: keep both endpoints and take
        # `_RAMP_CAPACITY` evenly spaced samples between them.
        self.count = _RAMP_CAPACITY
        for i in range(_RAMP_CAPACITY):
            var t = Float64(i) / Float64(_RAMP_CAPACITY - 1)
            var src = Int(round(t * Float64(n - 1)))
            self._packed[i] = Self._pack(stops[src])

    @staticmethod
    def _pack(color: Color) -> UInt32:
        """`color` as `0x00RRGGBB`. Alpha is dropped: a color scale
        interpolates hue, and a partly transparent stop would make a
        mark's fill depend on what happens to be underneath it.

        Args:
            color: The stop's color.

        Returns:
            Its three channels in one word.
        """
        return (
            (UInt32(color.r) << 16) | (UInt32(color.g) << 8) | UInt32(color.b)
        )

    def __len__(self) -> Int:
        """The number of stops; `0` for an unset ramp.

        Returns:
            The stop count.
        """
        return self.count

    def __getitem__(self, index: Int) -> Color:
        """The stop at `index`.

        Args:
            index: A position in `[0, len(self))`.

        Returns:
            That stop's color, unpacked.
        """
        var word = self._packed[index]
        return Color(
            UInt8((word >> 16) & 0xFF),
            UInt8((word >> 8) & 0xFF),
            UInt8(word & 0xFF),
        )
