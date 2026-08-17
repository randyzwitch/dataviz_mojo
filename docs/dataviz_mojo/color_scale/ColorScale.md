Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/color_scale.mojo)

# `ColorScale`

```mojo
@memory_only
struct ColorScale
```

A linear color gradient over [domain_min, domain_max] -- no "pixel range" the way LinearScale has, since a color has no spatial position to map onto; `color_at(value)` is the whole interface. A zero-span domain (every value identical) always projects to t=0.0 -- the lowest-offset stop's color (not necessarily whichever was added first; see _color_at_t's own bracketing-by-offset-value search), not a crash -- the same degenerate-domain handling LinearScale's own `scale()` gives (see that struct's own docstring).

## Fields

- **domain_min** (`Float64`)
- **domain_max** (`Float64`)
- **stops** (`List[_GradientStop]`)

## Implemented traits

`AnyType`, `Deinitable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, domain_min: Float64, domain_max: Float64)
```

**Args:**

- **domain_min** (`Float64`)
- **domain_max** (`Float64`)
- **self** (`Self`)

**Returns:**

`Self`

### `add_stop`

```mojo
fn def add_stop(mut self, offset: Float64, color: Color)
```

**Args:**

- **self** (`Self`)
- **offset** (`Float64`)
- **color** (`Color`)

### `color_at`

```mojo
fn def color_at(self, value: Float64) -> Color
```

**Args:**

- **self** (`Self`)
- **value** (`Float64`)

**Returns:**

`Color`


