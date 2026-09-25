---
title: Layers and secondary axes
weight: 40
---

Layers place several plots in one coordinate frame. For continuous marks, they
share the x-domain; primary layers also share one y-domain. Drawing order
follows list order.

```mojo
from dataviz import Plot, Theme, save_layers
from dataviz.core.colors import CORNFLOWERBLUE, TOMATO

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var revenue = (
        Plot().mark_line().encode(x=x, y=[80.0, 95.0, 110.0, 125.0])
        .series_name("Revenue").theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var growth = (
        Plot().mark_line().encode(x=x, y=[4.0, 7.0, 10.0, 8.0])
        .secondary_axis().series_name("Growth %")
        .labels(y_title="Growth (%)").theme(Theme(mark_color=TOMATO))
    )
    save_layers(revenue, growth, path="layers.svg")
```

Bar layers with identical categories in the same order share a categorical
axis. Each bar layer takes one adjacent slot within its category; optional
point, line, and area layers align to the center of the whole category. Name
and color each bar layer to make the groups readable:

```mojo
from dataviz import Plot, Theme, save_layers
from dataviz.core.colors import CORNFLOWERBLUE, TOMATO

def main() raises:
    var categories: List[String] = ["North", "South", "West"]
    var actual: List[Float64] = [18.0, 24.0, 20.0]
    var plan: List[Float64] = [20.0, 22.0, 21.0]
    var a = (
        Plot().mark_bar().encode_categorical(x=categories, y=actual)
        .series_name("Actual").theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var b = (
        Plot().mark_bar().encode_categorical(x=categories, y=plan)
        .series_name("Plan").theme(Theme(mark_color=TOMATO))
    )
    save_layers(a, b, path="bar-layers.svg")
```

A grouped or stacked bar plot can also own the categorical frame, with one
point, line, or area value at each category center. Keep the same category
order across the plots. A grouped or stacked plot uses the whole category
band, so combine it with continuous overlays rather than another bar layer:

```mojo
from dataviz import Plot, save_layers

def main() raises:
    var categories: List[String] = ["North", "South", "West"]
    var series: List[String] = ["Product A", "Product B"]
    var sales: List[List[Float64]] = [[10.0, 12.0, 9.0], [7.0, 6.0, 8.0]]
    var total: List[Float64] = [17.0, 18.0, 17.0]
    var bars = Plot().mark_stacked_bar().encode_grouped_bar(categories, series, sales)
    var line = Plot().mark_line().encode(x=[0.0, 1.0, 2.0], y=total)
    save_layers(bars, line, path="stacked-total.svg")
```

Pies use a separate concentric layout: pass two or more `pie()` plots to
`save_layers()` with the default `inner_radius_fraction=0`. The first plot
is the outer ring, each ring keeps its own proportions, and the legend names
its ring number and category.

```mojo
from dataviz import pie, save_layers

def main() raises:
    var outer_names: List[String] = ["A", "B"]
    var inner_names: List[String] = ["C", "D"]
    var outer_values: List[Float64] = [3.0, 1.0]
    var inner_values: List[Float64] = [2.0, 2.0]
    var outer = pie(outer_names, outer_values, title="Two breakdowns")
    var inner = pie(inner_names, inner_values)
    save_layers(outer, inner, path="concentric.svg")
```

Use a secondary axis only when the layers have different units, and label the
right axis. At least one layer must remain primary. Layers must share size, and
categorical, other polar, hierarchy, and network marks generally cannot share
the continuous frame. Use facets when plots do not share compatible coordinates.

See [Shared-axis layers](../../cookbook/combo_chart/),
[Dual y-axis](../../cookbook/dual_axis/), and
[layer rendering](../../dataviz/layers/).
