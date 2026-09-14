"""Output formats supported by `save()`: SVG, PNG, BMP and PDF."""


struct OutputFormat(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime SVG = Self(0)
    comptime PNG = Self(1)
    comptime BMP = Self(2)
    comptime PDF = Self(3)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
