---
title: Coming from pyplot
weight: 101
---

`pyplot` keeps a *current figure* and a *current axes* in hidden global state:
`plt.plot()` draws onto whichever figure is current, and `plt.savefig()` writes
it. dataviz has no current anything. A chart is a `Plot` value that you build,
pass around and export -- two charts built side by side never interfere, and
nothing is drawn until you export.

| pyplot | dataviz |
|---|---|
| `plt.figure(figsize=(8, 5))` | `.size_inches(8, 5)` on the chart |
| `plt.plot(x, y)` | `line(x, y)` |
| `plt.scatter(x, y)` | `scatter(x, y)` |
| `plt.title("t")`, `plt.xlabel`, `plt.ylabel` | `title=`, `x_title=`, `y_title=`, or `.labels(...)` |
| `plt.xlim(a, b)` | `.scale_x_domain(a, b)` |
| `plt.savefig("f.svg")` | `save(chart, "f.svg")` |
| `plt.show()` | `save()` to a file and open it |
| `plt.subplot(2, 2, i)` | `render_facets(plots, cols=2)` |
| `plt.rcParams[...] = ...` | a `Theme`, passed as `theme=` or with `.theme(...)` |
| `plt.style.use("dark_background")` | a preset from `dataviz.core.themes`: `dark()`, `minimal()`, `high_contrast()`, `print_safe()` |

Two consequences worth knowing:

- **Order does not matter.** Because the chart is a description, calling
  `.scale_x_domain()` before or after `.labels()` gives the same chart;
  there is no "draw, then adjust" sequence to get right.
- **Styling is per chart.** A `Theme` travels with its `Plot` instead of
  living in global state, so one program can export a light and a dark version
  of the same chart without resetting anything in between. See
  [themes and styling](../../guides/themes-and-styling/).

For the chart-by-chart mapping, see
[Coming from matplotlib](../../guides/from-matplotlib/).
