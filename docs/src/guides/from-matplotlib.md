---
title: Coming from matplotlib
weight: 100
---

This page maps matplotlib's `Axes` methods to dataviz. For the `pyplot`
state-machine interface (`plt.plot`, `plt.savefig`, ...), start with
[Coming from pyplot](../../guides/from-pyplot/), then come back here for the
chart-by-chart table.

The one idea that changes everything else: **a chart is a value.** matplotlib
draws onto a figure as you call methods on it; dataviz builds a `Plot` that
describes the chart, draws nothing, and is rendered when you export it with
`save()`, `render()`, `render_svg()` or `render_pdf()`. Every method below
returns a new `Plot`, so calls chain.

## Charts

| matplotlib | dataviz |
|---|---|
| `ax.scatter(x, y)` | `scatter(x, y)`, or `Plot().mark_point().encode(x=x, y=y)` |
| `ax.plot(x, y)` | `line(x, y)` |
| `ax.plot(x, y, drawstyle="steps-post")` | `line(x, y, step=StepStyle.POST)` (also `PRE`, `MID`) |
| `ax.fill_between(x, y)` | `area(x, y)` |
| `ax.stackplot(x, ys)` | `stacked_area(...)`, or `streamgraph(...)` for a centered baseline |
| `ax.bar(cats, vals)` / `ax.barh(...)` | `bar(cats, vals)` / `bar(cats, vals, horizontal=True)` |
| `ax.errorbar(x, y, yerr=e)` | `Plot().mark_point().encode(x=x, y=y, y_err=e)`; asymmetric: `y_err_lower=`, `y_err_upper=` |
| `ax.hist(x, bins=20)` | `histogram(x, bins=20)` |
| `ax.hist(..., density=True)` | `histogram(..., stat=HistStat.DENSITY)` (also `PROBABILITY`, `PERCENT`, `FREQUENCY`) |
| `ax.hist(..., cumulative=True)` | `histogram(..., cumulative=True)` |
| `ax.hist(..., histtype="stepfilled")` | `stepped_histogram(...)` |
| `ax.hist(..., orientation="horizontal")` | `histogram(..., horizontal=True)` |
| `ax.hist2d(x, y)` | `hist2d(x, y)` |
| `ax.hexbin(x, y, gridsize=30)` | `hexbin(x, y, gridsize=30)` |
| `ax.boxplot(...)` / `ax.violinplot(...)` | `box(...)` / `violin(...)` |
| `ax.pie(vals, labels=cats)` | `pie(cats, vals)` |
| `ax.eventplot(positions)` | `eventplot(labels, positions)` |
| `ax.ecdf(x)` / `ax.ecdf(x, complementary=True)` | `ecdf(x)` / `ecdf(x, complementary=True)` |
| `ax.imshow(z)` | `imshow(z)` -- see [differences](#behavior-that-differs-on-purpose) |
| `ax.pcolormesh(X, Y, C)` (1D edges) | `pcolormesh(x_edges, y_edges, z)` |
| `ax.contour(x, y, z)` / `ax.contourf(...)` | `contour(z, x=x, y=y)` / `contourf(...)` -- **`z` comes first** |
| `ax.tricontour` / `tricontourf` / `triplot` / `tripcolor` | `tricontour` / `tricontourf` / `triplot` / `tripcolor` |
| `ax.quiver` / `ax.barbs` / `ax.streamplot` | `quiver` / `barbs` / `streamplot` |
| `ax.scatter3D`, `plot3D`, `plot_surface`, `plot_wireframe`, `plot_trisurf` | `scatter3d`, `plot3d`, `surface3d`, `wire3d`, `trisurf3d` |
| `ax.bar3d` / `ax.voxels` / `ax.quiver` (3D) / `ax.stem` (3D) | `bar3d` / `voxels` / `quiver3d` / `stem3d` |

## Axes, scales and labels

| matplotlib | dataviz |
|---|---|
| `ax.set_title("t")`, `set_xlabel`, `set_ylabel` | the `title=`, `x_title=`, `y_title=` arguments, or `.labels(title=..., x_title=..., y_title=...)` |
| `ax.set_xlim(a, b)` | `.scale_x_domain(a, b)` (`scale_y_domain` for y) |
| `ax.set_xscale("log")` | `.scale_x_log()` |
| `ax.set_xscale("symlog", linscale=1.0)` | `.scale_x_symlog()` |
| `ax.invert_xaxis()` | `.scale_x_reverse()` |
| `ax.set_xticks(...)` | `.scale_x_ticks(...)` |
| `ax.spines["bottom"].set_position("zero")` | `Theme(x_axis_position=AxisPosition.ZERO)` |
| `norm=LogNorm()` | `.scale_color_log()` |
| `norm=TwoSlopeNorm(vcenter=c)` | `.scale_color_center(c)` |
| `norm=BoundaryNorm(bounds, ...)` | `.scale_color_thresholds(bounds)` |

## Annotations

| matplotlib | dataviz |
|---|---|
| `ax.axhline(y)` / `ax.axvline(x)` | `.annotate_line(y)` / `.annotate_vline(x)` |
| `ax.axhspan(y0, y1)` | `.annotate_area(y0, y1)` |
| `ax.fill_between(x, lower, upper)` as an envelope | `.annotate_band(x, lower, upper)` |
| `ax.annotate(text, xy=, xytext=, arrowprops=...)` | `.annotate_arrow(x, y, text, text_x, text_y)` -- both ends in data coordinates |

See the [annotations guide](../../guides/annotations/) for what each one draws.

## Figures, layout and export

| matplotlib | dataviz |
|---|---|
| `fig, ax = plt.subplots()` | nothing: build a `Plot` |
| `fig.set_size_inches(w, h)` / `figsize=(w, h)` | `.size_inches(w, h)` (or `.size(w, h)` in points, `.size_mm(w, h)`) |
| several `plot()` calls on one `ax` | `render_layers(a, b, ...)`, one chart per layer |
| `ax.twinx()` | `.secondary_axis()` on a layer |
| `plt.subplots(r, c)` | `render_facets(plots, cols=c)` |
| `GridSpec` with spans and ratios | `render_grid(plots, cells, width, height, row_weights=, col_weights=)` with `GridCell(row, col, row_span=, col_span=)` |
| `fig.savefig("f.png", dpi=300)` | `save(plot, "f.png", dpi=300)` |
| `fig.savefig(..., bbox_inches="tight")` | `save(plot, path, tight=True)` |

The format comes from the path's extension -- `.png`, `.svg`, `.pdf` or
`.bmp`. See [raster and SVG output](../../guides/output-formats/) and
[layers and secondary axes](../../guides/layers-and-secondary-axes/).

## Behavior that differs on purpose

- **`imshow` fills the plot area.** matplotlib keeps square pixels by default
  (`aspect="equal"`) and letterboxes the image; here the grid stretches to the
  plot rect, so its cells are rectangles the shape of the chart. The first row
  is drawn at the top, as matplotlib's default `origin="upper"` does.
- **Both ends of an arrow are in data coordinates.** matplotlib's `xytext` can
  be in any of several coordinate systems; `annotate_arrow()` places the text
  end by data value too, so it moves with the data when the domain changes.
- **`triplot` shows its vertices.** The mesh's sample points are drawn as
  markers by default, not just the edges.
- **`contour` takes `z` first.** The grid is the one required argument; `x` and
  `y` are optional keywords that put it on your own coordinates.
- **`scale_x_symlog()`'s linear region is one decade wide**, matplotlib's
  `linscale=1.0`.
- **`tight=True` crops the finished figure.** It lays the figure out at its
  full size and then trims to the ink, so every element is where it would be
  untrimmed; and it crops SVG and PDF too, because the extent is measured from
  the drawing rather than from pixels.
- **Axes are padded by 5% of their range**, the same default margin matplotlib
  uses, but the padding is part of the domain here: `scale_x_domain(a, b)`
  replaces it entirely.
