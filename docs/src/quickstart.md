---
title: Quickstart
type: docs
weight: 100
---

## Install

Add it to your workspace's `pixi.toml` as a git-source dependency:

```toml
[workspace]
preview = ["pixi-build"]  # git-source pixi dependencies are still a preview feature

[dependencies]
dataviz_mojo = { git = "https://github.com/randyzwitch/dataviz_mojo.git", branch = "main" }
```

`pixi install`/`pixi run` builds `dataviz_mojo` (and its `canvas_mojo` dependency) from that git ref and installs the resulting precompiled package into your workspace's pixi environment.

Run `pixi install` once after saving `pixi.toml`. The examples below can then
live in `main.mojo` and run with:

```sh
pixi run mojo main.mojo
```

The command writes `chart.svg` in the current directory. If the import fails,
first confirm that `pixi install` completed successfully and that the
dependency is under `[dependencies]`, not `[package.host-dependencies]`.

## A first chart using the `Plot()` builder

`Plot` is a fluent builder: each method returns the plot, so calls form one
chain. The steps below build the same scatter plot incrementally. Other chart
types use the same mark, encode, label, and theme pattern.

### Step 1: Basic Scatterplot

Every chart needs a **mark**, an **encoding** from data to visual channels, and
an output call.

<div class="dvm-chart-preview"><img src="../examples/quickstart/out_step1.svg" alt="A minimal scatter plot: five points, no axis titles" /></div>

```mojo
from dataviz import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = (
               Plot()
               .mark_point()
               .encode(x=x, y=y)
               )
    save(plot, "chart.svg")
```

`.mark_point()` draws one point per row. `.encode(x=x, y=y)` sets its position.
`save()` chooses SVG, PNG, or BMP from the filename extension.

### Step 2: Adding Axis Titles

`.labels()` adds chart and axis captions without changing the data.

<div class="dvm-chart-preview"><img src="../examples/quickstart/out_step2.svg" alt="The same scatter plot, now with axis titles: Day and Revenue ($k)" /></div>

```mojo
from dataviz import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = (
               Plot()
               .mark_point()
               .encode(x=x, y=y)
               .labels(x_title="Day", y_title="Revenue ($k)")
               )
    save(plot, "chart.svg")
```

The points and scales remain unchanged.

### Step 3: Adding a Chart Title

`.labels()` sets all captions together. A later call replaces values omitted
from that call, so pass the chart and axis titles together:

<div class="dvm-chart-preview"><img src="../examples/quickstart/out_step3.svg" alt="The same scatter plot, now with a Weekly Revenue title above it too" /></div>

```mojo
from dataviz import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = (
               Plot()
               .mark_point()
               .encode(x=x, y=y)
               .labels(title="Weekly Revenue", x_title="Day", y_title="Revenue ($k)")
               )
    save(plot, "chart.svg")
```

### Step 4: Changing Point Color and Size

Visual styling lives on `Theme`, applied with `.theme()`. See the
[`Theme` reference](../dataviz/theme/) for all options.

<div class="dvm-chart-preview"><img src="../examples/quickstart/out_step4.svg" alt="The same scatter plot, now colored seagreen with larger points" /></div>

```mojo
from dataviz import Plot, save
from dataviz.colors import SEAGREEN
from dataviz.theme import Theme

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = (
               Plot()
               .mark_point()
               .encode(x=x, y=y)
               .labels(title="Weekly Revenue", x_title="Day", y_title="Revenue ($k)")
               .theme(Theme(mark_color=SEAGREEN, point_radius=6.0))
               )
    save(plot, "chart.svg")
```

## Using `scatter()` instead of `Plot()`

Most mark types also have a one-call convenience function --
`scatter(x, y)`, `bar(categories, values)`, and so on -- built on top
of the exact same `Plot` builder, for whenever chaining four methods
by hand is more ceremony than the chart needs. Every customization
from steps 2-4 is available as a keyword argument:

<div class="dvm-chart-preview"><img src="../examples/quickstart/out_step5_quickplot.svg" alt="The exact same seagreen scatter plot as step 4, produced in one scatter() call instead" /></div>

```mojo
from dataviz import scatter, save
from dataviz.colors import SEAGREEN
from dataviz.theme import Theme

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = scatter(
        x,
        y,
        theme=Theme(mark_color=SEAGREEN, point_radius=6.0),
        title="Weekly Revenue",
        x_title="Day",
        y_title="Revenue ($k)",
    )
    save(plot, "chart.svg")
```

`scatter(x, y)` builds the same point plot and forwards styling and labels.
Use the full builder for layers, facets, and additional encodings.

## Choose an API and chart

Start with a convenience function when one call describes the chart. Use
`Plot()` when you need to compose layers, facets, or encodings beyond the
function's parameters. Both routes produce the same `Plot` value, so starting
simple does not lock you in.

| Your data or question | Start with | Example |
| --- | --- | --- |
| Two numeric variables | `scatter(x, y)` or `line(x, y)` | [Scatter](../examples/scatter/) · [Line](../examples/line/) |
| Categories and values | `bar(categories, values)` | [Bar](../examples/bar/) |
| Distribution of numeric values | `histogram(data)` or `box(categories, values)` | [Histogram](../examples/histogram/) · [Box](../examples/box/) |
| Values on a two-dimensional grid | `heatmap(x, y, value)` | [Heatmap](../examples/heatmap/) |
| Multiple layers or panels | `Plot()` | [Cookbook](../cookbook/) |

Each linked page includes runnable source beside its rendered output. The
[full examples gallery](../examples/) covers specialized statistical,
hierarchical, radial, financial, and network charts.

## Where to next

- **[Data shapes](../data-shapes/)** -- how to arrange columns, nested lists,
  grids, networks, hierarchies, NumPy, pandas, and custom containers.
- **[Examples](../examples/)** -- every chart type this package can
  produce, source code next to its actual rendered output.
- **[API reference](../dataviz/)** -- the full surface `Plot`
  and `Theme` expose, every scale, every mark.

## Contributing to dataviz_mojo

This project is [MIT licensed](https://github.com/randyzwitch/dataviz_mojo/blob/main/LICENSE), and contributions are welcome. Found a bug or unclear documentation? [Open a PR](https://github.com/randyzwitch/dataviz_mojo/pulls).

For a new chart type or large redesign, [open an issue](https://github.com/randyzwitch/dataviz_mojo/issues/new) before implementation. Small fixes and documentation changes can go directly to a PR.

There are several useful commands defined in the Pixi environment for development:

```sh
pixi run test      # tests/*.mojo
pixi run example   # every dataviz/*.mojo `Example:` docstring section, writes docs/src/examples/out_*.svg
pixi run docs      # regenerates this site -- run `example` first
```

## License

MIT -- see [`LICENSE`](https://github.com/randyzwitch/dataviz_mojo/blob/main/LICENSE).
