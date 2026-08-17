Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/scale.mojo)

# `LinearScale`

```mojo
@memory_only
struct LinearScale
```

A linear map from [domain_min, domain_max] to [range_min, range_max] -- `range_min`/`range_max` are the pixel positions `domain_min`/`domain_max` land on, not necessarily numerically increasing (a y-axis scale passes range_min=plot_bottom_pixel, range_max=plot_top_pixel, a *smaller* pixel value, since pixel y increases downward -- the map comes out with a negative slope automatically, no separate "flip" flag needed).

## Fields

- **domain_min** (`Float64`)
- **domain_max** (`Float64`)
- **range_min** (`Float64`)
- **range_max** (`Float64`)

## Implemented traits

`AnyType`, `Copyable`, `Deinitable`, `ImplicitlyCopyable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, domain_min: Float64, domain_max: Float64, range_min: Float64, range_max: Float64)
```

**Args:**

- **domain_min** (`Float64`)
- **domain_max** (`Float64`)
- **range_min** (`Float64`)
- **range_max** (`Float64`)
- **self** (`Self`)

**Returns:**

`Self`

### `scale`

```mojo
fn def scale(self) -> Float64
```

The slope for a Transform2D built from this axis -- (range_max - range_min) / (domain_max - domain_min). Zero domain span (a constant-valued column) returns 0.0 rather than dividing by zero; every input then maps to range_min via to_pixel's own translate term, a single point/line rather than a crash.

**Args:**

- **self** (`Self`)

**Returns:**

`Float64`

### `translate`

```mojo
fn def translate(self) -> Float64
```

The intercept for a Transform2D built from this axis -- derived from scale() so domain_min always maps to exactly range_min (to_pixel(domain_min) == range_min, not just approximately, confirmed directly in test_linear_scale_endpoints_map_to_range_exactly).

**Args:**

- **self** (`Self`)

**Returns:**

`Float64`

### `to_pixel`

```mojo
fn def to_pixel(self, value: Float64) -> Float64
```

**Args:**

- **self** (`Self`)
- **value** (`Float64`)

**Returns:**

`Float64`

### `ticks`

```mojo
fn def ticks(self, target_count: Int = Int(5)) -> Ticks
```

"Nice" tick positions within [domain_min, domain_max] (see _nice_step), generated *within* the domain, not extending it -- ceil(domain_min/step)*step up to floor(domain_max/step)*step -- so an axis's visible range always matches its scale's own domain exactly; a tick landing exactly on a boundary is included (matches this file's own hand-verified examples, e.g. domain [0,100] includes both the 0 and 100 ticks).

A zero-span domain (every data value identical) returns a
single tick at domain_min with 0 decimals rather than running
the nice-step math against a zero raw step (which would need
log10(0), undefined) -- a real, reachable case (e.g. a column
of constant values), not just a defensive check.

**Args:**

- **self** (`Self`)
- **target_count** (`Int`)

**Returns:**

`Ticks`


