"""The file format `save()` (plot.mojo) writes: `SVG`, `PNG`, or `BMP`.
Same small-struct-with-comptime-constants-and-`__eq__` pattern as
`Mark` (mark.mojo).

Named after file formats rather than the `canvas` backends underneath:
`PNG` and `BMP` both render through the raster `Canvas` and differ only
in which `canvas.io` writer runs at the end. `SVG` is
`Theme.output_format`'s default.
"""


struct OutputFormat(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime SVG = Self(0)
    comptime PNG = Self(1)
    comptime BMP = Self(2)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
