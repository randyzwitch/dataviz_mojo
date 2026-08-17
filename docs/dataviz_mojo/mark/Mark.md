Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/mark.mojo)

# `Mark`

```mojo
@memory_only
struct Mark
```

## Aliases

- `POINT = Mark(Int(0))`
- `LINE = Mark(Int(1))`
- `BAR = Mark(Int(2))`
- `AREA = Mark(Int(3))`
- `ARC = Mark(Int(4))`
- `LOLLIPOP = Mark(Int(5))`
- `WATERFALL = Mark(Int(6))`
- `BOX = Mark(Int(7))`
- `CANDLESTICK = Mark(Int(8))`
- `BULLET = Mark(Int(9))`
- `GANTT = Mark(Int(10))`
- `GROUPED_BAR = Mark(Int(11))`
- `STACKED_BAR = Mark(Int(12))`

## Implemented traits

`AnyType`, `Copyable`, `Deinitable`, `ImplicitlyCopyable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self, value: Int)
```

**Args:**

- **value** (`Int`)
- **self** (`Self`)

**Returns:**

`Self`

### `__eq__`

```mojo
fn def __eq__(self, other: Self) -> Bool
```

**Args:**

- **self** (`Self`)
- **other** (`Self`)

**Returns:**

`Bool`


