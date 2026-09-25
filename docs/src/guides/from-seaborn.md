---
title: Coming from seaborn
weight: 102
---

seaborn's statistical charts have direct counterparts here, with the same
vocabulary for what a group is reduced to and how its uncertainty is shown.
As with every chart in dataviz, each function returns an unrendered chart that
you export with `save()`.

## Charts

| seaborn | dataviz |
|---|---|
| `scatterplot(x=, y=)` | `scatter(x, y)` |
| `scatterplot(..., hue=g)` | `Plot().mark_point().encode(x=x, y=y, color_categories=g)` |
| `scatterplot(..., size=s)` | `encode(..., size=s)` |
| `stripplot(..., jitter=True)` | `Plot().mark_point(jitter_x=..., jitter_y=...)` |
| `swarmplot` | `beeswarm` |
| `lineplot` (with repeated x) | `lineplot` -- the per-x estimate with a band |
| `barplot` | `barplot` |
| `pointplot` | `pointplot` |
| `boxplot` / `violinplot` / `boxenplot` | `box` / `violin` / `boxenplot` |
| `histplot` | `histogram` |
| `kdeplot` / `rugplot` / `ecdfplot` | `kdeplot` / `rugplot` / `ecdf` |
| `heatmap` / `clustermap` | `heatmap` / `clustermap` |
| `pairplot` / `jointplot` | `pairplot` / `jointplot` |
| `residplot` | `residplot` |
| `regplot` | `scatter(x, y).annotate_best_fit()` -- the line and its confidence band |
| `FacetGrid` | `render_facets(a, b, cols=...)`, one chart per facet |
| `despine()` | nothing to do: the top and right axis lines are off by default |

## Estimates and error bars

`barplot`, `pointplot` and `lineplot` reduce each group with an `Estimator` and
size its uncertainty with an `ErrorBar`, as seaborn's `estimator=` and
`errorbar=` do:

| seaborn | dataviz |
|---|---|
| `estimator="mean"` (default) / `"median"` / `len` / `sum` | `Estimator.MEAN` / `MEDIAN` / `COUNT` / `SUM` |
| `errorbar=("ci", 95)` (default) | `ErrorBar.ci(0.95)` -- a bootstrap confidence interval with a fixed seed |
| `errorbar=("pi", 50)` | `ErrorBar.pi(0.5)` -- a percentile interval of the observations |
| `errorbar="se"` / `("se", 2)` | `ErrorBar.se()` / `ErrorBar.se(2.0)` |
| `errorbar="sd"` | `ErrorBar.sd()` |
| `errorbar=None` | `ErrorBar.none()` |

Levels are fractions here (`0.95`), not percentages.

## Behavior that differs on purpose

- **The estimator names the value axis.** When no axis title is given,
  `barplot()` and `pointplot()` label the value axis "Mean", "Median", "Count"
  or "Sum", so an estimate is never mistaken for raw data.
- **Bootstrap intervals are reproducible.** `ErrorBar.ci()` resamples with a
  fixed seed (the `seed=` argument), so the same data renders the same whisker
  every time.
- **A pair plot's diagonal is a true histogram** on the same numeric axis as
  the scatter panels in its column, so the bars line up with the points above
  and below them.
