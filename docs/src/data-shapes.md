---
title: Data shapes
type: docs
weight: 150
---

dataviz_mojo usually accepts data as columns: one list per variable, with the
same index identifying the same observation across lists. Specialized charts
use nested lists, grids, edge lists, or flattened hierarchy rows. This page is
the shared reference for those conventions.

## Numeric and categorical columns

Primary continuous x, y, and chart-value inputs accept `List[Float64]` and
lists of other Mojo numeric scalar types, including `List[Int]` and
`List[Float32]`. Numeric inputs are converted to `Float64` internally.

Categorical channels use `List[String]`. Parallel columns must have the same
length:

```mojo
from dataviz import bar

var day: List[String] = ["Mon", "Tue", "Wed"]
var revenue: List[Int] = [12, 19, 8]
var plot = bar(day, revenue)
```

Here `day[i]` and `revenue[i]` describe one row. The same rule applies to
`scatter(x, y)`, line data, labels, sizes, groups, and other paired channels.
See the [Bar](../examples/bar/) and [Scatter](../examples/scatter/) examples.

## Nested lists

The meaning of an inner list depends on the chart family. Check the inner
dimension before transposing data:

| Chart family | Outer list | Inner list |
| --- | --- | --- |
| Grouped and stacked bars | One list per series | One value per category |
| Box, beeswarm, violin, and ridgeline | One list per category or distribution | Raw observations for that distribution |
| Radar | One list per named series | One value per indicator |
| Parallel coordinates | One list per named observation | One value per dimension |
| Marimekko | One list per subcategory | One value per category |
| Correlation plot | One matrix row per variable | One value per variable; the matrix must be square |

For example, grouped bars use `values[series][category]`:

```mojo
from dataviz import grouped_bar

var categories: List[String] = ["Q1", "Q2", "Q3"]
var series: List[String] = ["North", "South"]
var values: List[List[Int]] = [
    [42, 48, 45],  # North across the three quarters
    [30, 35, 33],  # South across the three quarters
]
var plot = grouped_bar(categories, series, values)
```

Compare the [Grouped bar](../examples/grouped_bar/),
[Box plot](../examples/box/), [Radar](../examples/radar/), and
[Parallel coordinates](../examples/parallel/) pages for complete programs.

## Grids and matrices

Grid APIs use long-form columns or nested row-major matrices:

- `heatmap(x, y, value)` uses long-form columns. Each row identifies one
  categorical `(x, y)` cell and its value.
- `imshow(z)` uses `z[row][column]`. The grid must be non-empty and
  rectangular; a one-row or one-column grid is valid.
- `pcolormesh(x_edges, y_edges, z)` uses the same matrix orientation, with
  cell boundaries rather than centers. It requires `len(x_edges) == columns +
  1` and `len(y_edges) == rows + 1`; both edge lists must increase strictly.
- Contour charts use sampled x and y coordinates with a rectangular value
  grid. They require at least a 2-by-2 grid because contours run between
  samples.
- `corrplot(variables, matrix)` requires a square matrix with one row and
  column per variable.

See [Heatmap](../examples/heatmap/), [Image](../examples/imshow/),
[Pseudocolor mesh](../examples/pcolormesh/), and
[Contour](../examples/contour/).

## Edge lists

Network and flow charts accept three parallel columns:

```text
from_categories[i] -> to_categories[i], weighted by values[i]
```

Every referenced node is inferred from the source and destination columns.
Values must be non-negative. Sankey data must also form a directed acyclic
graph; cycles are rejected when layout is computed. See
[Graph](../examples/graph/), [Sankey](../examples/sankey/),
[Chord](../examples/chord/), and [Arc diagram](../examples/arc_diagram/).

## Hierarchy rows

Sunburst, tree, and treemap charts use a flattened hierarchy rather than
nested node objects. The three lists have one entry per node:

- `ids[i]` is a unique node identifier.
- `parent_ids[i]` names its parent, or is `""` for the single root.
- `values[i]` supplies a leaf value. Internal-node sizes are computed from
  their descendants.

Every non-root parent must appear in `ids`, and every node must be reachable
from the root. Duplicate IDs, missing parents, multiple roots, and cycles are
invalid. See [Sunburst](../examples/sunburst/), [Tree](../examples/tree/), and
[Treemap](../examples/treemap/).

## NumPy, pandas, and custom containers

`Plot.encode()` accepts NumPy arrays, pandas Series, and plain Python numeric
lists through its `PythonObject` overload. `Plot.encode_categorical()` accepts
the same numeric forms for `y`; categorical `x` remains a Mojo string list or
string sequence. NumPy must be installed in the caller's environment, but it
is not a dataviz_mojo runtime dependency. See the
[NumPy and pandas recipe](../cookbook/numpy_pandas_data/).

For a Mojo-native container, conform its type to `Float64Sequence` or
`StringSequence`. A conforming type supplies `__len__()` and integer-indexed
element access. Numeric `x` and `y` passed to the generic `Plot.encode()`
overload must share one conforming type. See the
[numeric container](../cookbook/array_like_data/) and
[categorical container](../cookbook/categorical_array_like/) recipes.

## Invalid and missing data

There is no implicit missing-value representation or row alignment. Prepare
the columns before plotting: remove a row from every parallel column, or
replace it with an explicit category or numeric value appropriate to the
analysis.

Before passing data, check that:

- Parallel columns have equal lengths.
- Nested inputs use the orientation required by that chart.
- Matrices are rectangular and meet their minimum dimensions.
- Numeric values used for geometry and scale domains are finite, not `NaN` or
  infinity.
- Values subject to a chart-specific domain are valid, such as correlations
  in `[-1, 1]` or non-negative flow magnitudes.

Some specialized encoders validate immediately, while shared length, mark,
and layout checks happen during `render()`, `render_svg()`, or `save()`.
Convenience functions return an unrendered `Plot`, so invalid data may not
raise until that plot is rendered or written. Keep the output call in a
`raises` context and use the resulting error message to locate the failing
column, row, or option.

[← Quickstart](../quickstart/) · [Choose a chart →](../chart-selection/)
