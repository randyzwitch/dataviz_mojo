"""`Theme.categorical_palette`'s type: a qualitative set of colors."""

from canvas.color import Color


comptime _PALETTE_CAPACITY = 64
"""The most colors a `ColorPalette` holds. Sets `_packed`'s SIMD width,
so it must stay a power of two."""


struct ColorPalette(ImplicitlyCopyable, Movable, Sized):
    """A qualitative palette -- one distinct color per category, cycled
    by index -- for `Theme.categorical_palette`. Empty means "unset",
    leaving `default_categorical_palette()` (color_scale.mojo) in
    charge, the same contract `Theme.color_ramp` has with the three
    scalar scale stops.

    Build one from a list of colors: `Theme(categorical_palette=[a, b,
    c])`, since the list constructor is `@implicit`.

    Packed into a fixed-width SIMD vector so `Theme` stays implicitly
    copyable, the same device as `ColorRamp`. It is a separate type
    because the semantics differ: a ramp is a continuous gradient that
    is interpolated across `[0, 1]`, and a palette is a list that is
    indexed. Interpolating between two categorical colors produces a
    color that means nothing, and a type whose docstring had to allow
    both would say two contradictory things. More than
    `_PALETTE_CAPACITY` entries are truncated rather than resampled: a
    palette's order is its meaning, and resampling would drop entries
    from the middle.
    """

    var _packed: SIMD[DType.uint32, _PALETTE_CAPACITY]
    """Each color as `0x00RRGGBB`; entries at and past `count` are zero."""
    var count: Int
    """How many colors the palette holds. `0` is an unset palette."""

    def __init__(out self):
        """An empty palette: `Theme` falls back to the package default."""
        self._packed = SIMD[DType.uint32, _PALETTE_CAPACITY](0)
        self.count = 0

    @implicit
    def __init__(out self, colors: List[Color]):
        """Pack `colors` in order, keeping at most `_PALETTE_CAPACITY`.

        Args:
            colors: The palette, first category first.
        """
        self._packed = SIMD[DType.uint32, _PALETTE_CAPACITY](0)
        var n = min(len(colors), _PALETTE_CAPACITY)
        self.count = n
        for i in range(n):
            self._packed[i] = Self._pack(colors[i])

    @staticmethod
    def _pack(color: Color) -> UInt32:
        """`color` as `0x00RRGGBB`. Alpha is dropped: a category's fill is
        opaque, and a partly transparent entry would make a mark's color
        depend on what happens to be underneath it.

        Args:
            color: The entry's color.

        Returns:
            Its three channels in one word.
        """
        return (
            (UInt32(color.r) << 16) | (UInt32(color.g) << 8) | UInt32(color.b)
        )

    def __len__(self) -> Int:
        """The number of colors; `0` for an unset palette.

        Returns:
            The entry count.
        """
        return self.count

    def __getitem__(self, index: Int) -> Color:
        """The color at `index`.

        Args:
            index: A position in `[0, len(self))`.

        Returns:
            That entry's color, unpacked.
        """
        var word = self._packed[index]
        return Color(
            UInt8((word >> 16) & 0xFF),
            UInt8((word >> 8) & 0xFF),
            UInt8(word & 0xFF),
        )

    def colors(self) -> List[Color]:
        """Every entry, in order, as a list -- the shape the mark files
        index with `palette[i % len(palette)]`.

        Returns:
            The palette as a `List[Color]`; empty when unset.
        """
        var out = List[Color](capacity=self.count)
        for i in range(self.count):
            out.append(self[i])
        return out^
