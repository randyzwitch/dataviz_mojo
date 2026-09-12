"""Output formats supported by `save()`: SVG, PNG, and BMP."""


struct OutputFormat(Copyable, ImplicitlyCopyable, Movable):
    var _value: Int

    comptime SVG = Self(0)
    comptime PNG = Self(1)
    comptime BMP = Self(2)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value
