Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/ordinal_scale.mojo)

# `OrdinalScale`

```mojo
@memory_only
struct OrdinalScale
```

## Fields

- **domain** (`List[String]`)
- **range_min** (`Float64`)
- **range_max** (`Float64`)
- **padding** (`Float64`)

## Implemented traits

`AnyType`, `Deinitable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, var domain: List[String], range_min: Float64, range_max: Float64, padding: Float64 = 0.20000000000000001)
```

**Args:**

- **domain** (`List[String]`)
- **range_min** (`Float64`)
- **range_max** (`Float64`)
- **padding** (`Float64`)
- **self** (`Self`)

**Returns:**

`Self`

### `step`

```mojo
fn def step(self) -> Float64
```

The pixel width of one category's full slot, band plus its padding -- 0.0 for an empty domain rather than dividing by zero (an empty categorical axis is a real, if unusual, input: a bar chart with no data at all).

**Args:**

- **self** (`Self`)

**Returns:**

`Float64`

### `bandwidth`

```mojo
fn def bandwidth(self) -> Float64
```

The pixel width of the band itself (a bar's own width), `step()` minus the padding taken off both sides.

**Args:**

- **self** (`Self`)

**Returns:**

`Float64`

### `band_start`

```mojo
fn def band_start(self, index: Int) -> Float64
```

The left pixel edge of the band at `index` -- half the step's padding in from that index's own slot start, so the padding is split evenly between a band and each of its neighbors.

**Args:**

- **self** (`Self`)
- **index** (`Int`)

**Returns:**

`Float64`

### `center`

```mojo
fn def center(self, index: Int) -> Float64
```

**Args:**

- **self** (`Self`)
- **index** (`Int`)

**Returns:**

`Float64`


