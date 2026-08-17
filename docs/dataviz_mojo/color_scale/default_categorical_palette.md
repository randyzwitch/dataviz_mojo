Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/color_scale.mojo)

# `default_categorical_palette`

```mojo
fn def default_categorical_palette() -> List[Color]
```

A default qualitative (discrete, unordered) color palette for categorical color encoding -- 8 colors chosen to read as visually distinct from each other (the same well-known "tab10"-style set most charting libraries ship a version of), cycled via modulo if a column has more unique categories than this (see `Plot.encode`'s own docstring).

Deliberately a plain function, not a `Theme` field: adding a
`List` field to `Theme` would break its `ImplicitlyCopyable`
conformance (confirmed directly by probe -- Mojo can't synthesize
an implicit copy constructor once a struct holds a `List`), which
every existing `var theme = plot._theme`-style copy throughout
this package already depends on. The same reasoning
`canvas_mojo.Color`'s own history gives for keeping named palettes out
of the core `Color` type applies here: a fixed default is enough
until per-Theme palette customization is an actual, concrete need,
not a reason to change how `Theme` itself copies today.

**Returns:**

`List[Color]`

