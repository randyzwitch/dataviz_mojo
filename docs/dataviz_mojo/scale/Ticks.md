Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/scale.mojo)

# `Ticks`

```mojo
@memory_only
struct Ticks
```

LinearScale.ticks()'s result: the tick positions themselves plus how many decimal places they need for display -- both returned together since the decimal count falls straight out of the same step computation _nice_step already did, not a separate thing to re-derive from a tick value afterward.

## Fields

- **values** (`List[Float64]`)
- **decimals** (`Int`)

## Implemented traits

`AnyType`, `Deinitable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, var values: List[Float64], decimals: Int)
```

**Args:**

- **values** (`List[Float64]`)
- **decimals** (`Int`)
- **self** (`Self`)

**Returns:**

`Self`

### `labels`

```mojo
fn def labels(self) -> List[String]
```

Each tick value formatted via _format_fixed at this Ticks' own `decimals` -- the convenience an axis-drawing caller actually wants, without needing to know _format_fixed exists.

**Args:**

- **self** (`Self`)

**Returns:**

`List[String]`


