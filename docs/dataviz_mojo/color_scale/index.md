Mojo module [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/color_scale.mojo)

# `color_scale`

ColorScale -- maps a continuous data domain onto a color gradient, for data-driven color encoding (`Plot.encode(color=...)`). Shares its stop-interpolation logic with `canvas_mojo.gradient`'s `LinearGradient`/ `RadialGradient` via that module's own `_color_at_t`/`_GradientStop` -- identical math (bracket the two nearest stops, linearly interpolate), only the projection differs: those two project a pixel position (an axis, or a radial distance) onto [0, 1]; this one projects a *data value* onto [0, 1] via a plain domain, the same domain-to-[0,1] idea `LinearScale` uses for position, generalized to color instead of a pixel coordinate.

## Structs

- [`ColorScale`](ColorScale.md): A linear color gradient over [domain_min, domain_max] -- no "pixel range" the way LinearScale has, since a color has no spatial position to map onto; `color_at(value)` is the whole interface. A zero-span domain (every value identical) always projects to t=0.0 -- the lowest-offset stop's color (not necessarily whichever was added first; see _color_at_t's own bracketing-by-offset-value search), not a crash -- the same degenerate-domain handling LinearScale's own `scale()` gives (see that struct's own docstring).

## Functions

- [`default_categorical_palette`](default_categorical_palette.md)

