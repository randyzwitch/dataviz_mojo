"""The file format `save()` (this module's sibling `plot.mojo`) writes
when a caller hands it a `Plot` and a path, rather than picking a
`canvas` backend by hand. Follows the same small-struct-with-
comptime-constants-and-`__eq__` pattern `Mark` (mark.mojo) and
canvas's `FillRule`/`TextAlign` use, not a distinct enum
mechanism.

Named after the concrete file formats a caller actually asks for --
`SVG`/`PNG`/`BMP` -- rather than the two `canvas` backends
underneath (`SvgCanvas`/`Canvas`) that render() them: `PNG` and `BMP`
both route through the same raster `Canvas` render pass, differing
only in which `canvas.io` writer gets called at the end, so
naming this after backends instead of formats would expose exactly
the implementation detail `save()` exists to hide.

`SVG` is the default (`Theme.output_format`'s own default) -- the
higher-quality output for most charts, since nothing about a `Plot`'s
marks is resolution-dependent the way a raster export is.
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
