Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/scale.mojo)

# `MinMax`

```mojo
@memory_only
struct MinMax
```

A column's [min, max] -- a small named struct rather than a positional tuple (see scale.mojo's sibling `Ticks`/`_NiceStep` for the same reasoning), and the shared starting point for every kind of domain this package computes: `Plot._data_extent` pads it for spatial (x/y) axes, `ColorScale`/size encoding use it exactly as- is (no padding -- a color/size legend's extremes should mean exactly the data's own extremes, not a padded approximation of them).

## Fields

- **min** (`Float64`)
- **max** (`Float64`)

## Implemented traits

`AnyType`, `Copyable`, `Deinitable`, `ImplicitlyCopyable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, min: Float64, max: Float64)
```

**Args:**

- **min** (`Float64`)
- **max** (`Float64`)
- **self** (`Self`)

**Returns:**

`Self`


