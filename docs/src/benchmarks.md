---
title: Benchmarks
type: docs
weight: 350
---

Render times from `pixi run bench` (`scripts/bench.mojo`) at each
canvas_mojo pin bump, so the effect of a bump is on record rather than
remembered, and so there is a baseline to measure future changes (a
matplotlib comparison, the next pin) against. Every column is the
commit that made that pin, measured in one sitting on 2026-09-05 with
the same script.

| Column | dataviz commit | canvas_mojo | dataviz changes since the previous column |
|---|---|---|---|
| 0.13.0 | `82d037a` (parent of the 0.14.0 bump) | v0.13.0 | |
| 0.14.0 | `44f2100` (#263) | v0.14.0 | `ColorScale` follows a renamed gradient helper; not on any benchmarked path |
| 0.15.0 | `3fd5a7e` (v0.8.0) | v0.15.0 | the additive `Mark.BARBS` |
| 0.16.0 | `2434b00` (#281) | v0.16.0 | **many**: closed marks fill `FillRule.NONZERO` (#267), one `FontCache` per figure (#272), SVG tooltips on six marks (#269), `Mark.CONTOUR`/`CONTOURF` (#273, #278), legend positions (#275, #280), and more |

The first three columns are therefore the same dataviz code against a
different canvas, and the 0.16.0 column is not: about half of what
moves between the 0.15.0 and 0.16.0 columns is dataviz's own work. To
separate the two, the sweep also measured `a8e7bc9`, the commit
immediately before the 0.16.0 bump (same dataviz as the 0.16.0 column,
still on canvas 0.15.0); the section [The 0.16.0 bump alone](#the-0160-bump-alone)
is that pair. Current main (`39473c7`) differs from the 0.16.0 column
only by #282 (polar grid rings through the trait) and #283 (dropping
the `_LazyFontCache` wrapper), neither on a benchmarked path.

## Machine

- AMD Ryzen Threadripper 3970X: 32 cores, 64 threads, 128 MiB L3, up
  to 4.55 GHz, `schedutil` governor. 125 GiB RAM.
- Ubuntu 24.04.4 LTS, Linux 7.0.0, Mojo 1.0.0, pixi 0.78.0.
- `Sans` resolves to Noto Sans Regular through fontconfig.
- canvas_mojo bands a fill, clip mask or downsample across
  `parallelism_level()` tasks (64 here) once its bounding box covers at
  least 40,000 pixels (`_MIN_PARALLEL_PIXELS` in `aa_crossing.mojo`,
  `resize.mojo` and `shapes/arcs.mojo`, the same value in every pin
  here). Every raster render draws at the default
  `Theme.raster_supersample = 3`, so the internal canvas is 2400x1800
  and the final downsample, every axis-frame clip mask and any fill
  wider than about 200x200 supersampled pixels (a SANKEY ribbon, a
  CHORD band, a SUNBURST ring) takes that path. **A single-core or
  laptop number will differ most on exactly those marks**; the
  glyph-sized fills and strokes that dominate the other rows run
  inline on one core regardless.

## Method

- Each column is the median of three complete `pixi run bench` passes,
  run back to back in the order 0.13.0, 0.14.0, 0.15.0, `a8e7bc9`,
  0.16.0, three times over, each configuration from a detached
  worktree at its commit with its own `pixi install` (canvas_mojo
  built from its tag) so nothing shares an environment with a
  checkout another session might move.
- Times are wall-clock milliseconds for one `render()` (raster) or
  `render_svg()` (svg) call at 800x600 with the default theme, after
  the script's own warm-up render on each backend. Neither includes
  PNG encoding or writing a file.
- The machine was otherwise idle (an agreed quiet window with the
  other sessions on it). The `spread` column is the worst max/min
  ratio among the three passes of any one configuration in that row:
  90% of cells are within 1.07x, the worst is 1.25x
  (ARC_DIAGRAM raster n=100, 0.16.0). Treat differences under about
  10% as noise.
- Two earlier attempts at this page went wrong in ways worth keeping
  on record. A sweep taken while another session ran the test suite
  on the same machine (load average 18 to 37 on 64 threads) overstated
  the 0.13.0 to 0.15.0 gain on small-n rows by 10 to 30 points and
  spread the banded marks 2 to 3x between passes: contention biases,
  it does not just blur. And a "current main" column run from the
  main checkout silently measured a feature branch for two of its
  passes, because another session had switched that checkout mid-run;
  every column here comes from a detached worktree at a recorded sha.

## Raster (`render()`)

| Mark | n | 0.13.0 (ms) | 0.14.0 (ms) | 0.15.0 (ms) | 0.16.0 (ms) | 0.16.0 vs 0.13.0 | spread |
|---|---:|---:|---:|---:|---:|---:|---:|
| POINT | 100 | 55.7 | 55.3 | 54.8 | 32.9 | -41% | 1.04x |
| LINE | 100 | 53.2 | 52.9 | 52.6 | 30.6 | -42% | 1.09x |
| POINT | 1,000 | 59.7 | 53.4 | 52.8 | 36.9 | -38% | 1.12x |
| LINE | 1,000 | 53.7 | 52.3 | 50.6 | 29.9 | -44% | 1.07x |
| POINT | 10,000 | 95.8 | 76.3 | 75.1 | 61.1 | -36% | 1.13x |
| LINE | 10,000 | 64.9 | 56.1 | 55.3 | 34.1 | -48% | 1.07x |
| POINT | 100,000 | 504.3 | 316.8 | 308.8 | 285.3 | -43% | 1.04x |
| LINE | 100,000 | 109.5 | 66.9 | 66.8 | 42.3 | -61% | 1.06x |
| BAR | 100 | 82.8 | 73.0 | 71.6 | 31.1 | -63% | 1.10x |
| BAR | 1,000 | 233.4 | 120.4 | 119.5 | 71.4 | -69% | 1.02x |
| BAR | 10,000 | 1989.4 | 664.4 | 661.7 | 540.7 | -73% | 1.03x |
| BEESWARM | 100 | 65.8 | 66.3 | 65.4 | 25.9 | -61% | 1.02x |
| VIOLIN | 100 | 71.1 | 70.7 | 68.9 | 27.7 | -61% | 1.05x |
| BEESWARM | 1,000 | 69.9 | 69.9 | 68.4 | 29.8 | -57% | 1.25x |
| VIOLIN | 1,000 | 70.9 | 70.9 | 68.9 | 27.6 | -61% | 1.04x |
| BEESWARM | 10,000 | 95.6 | 92.0 | 90.3 | 51.4 | -46% | 1.13x |
| VIOLIN | 10,000 | 73.0 | 72.2 | 71.0 | 29.7 | -59% | 1.04x |
| CHORD | 100 | 106.7 | 89.1 | 88.0 | 55.4 | -48% | 1.15x |
| ARC_DIAGRAM | 100 | 93.9 | 67.1 | 66.5 | 36.5 | -61% | 1.25x |
| GRAPH | 100 | 42.4 | 34.0 | 33.7 | 29.6 | -30% | 1.02x |
| SANKEY | 100 | 125.1 | 123.4 | 122.0 | 45.3 | -64% | 1.11x |
| CHORD | 1,000 | 499.9 | 322.6 | 315.8 | 219.8 | -56% | 1.07x |
| ARC_DIAGRAM | 1,000 | 218.1 | 96.0 | 95.6 | 96.9 | -56% | 1.02x |
| GRAPH | 1,000 | 174.8 | 69.4 | 69.1 | 48.7 | -72% | 1.01x |
| SANKEY | 1,000 | 450.7 | 354.4 | 360.4 | 183.7 | -59% | 1.07x |
| CHORD | 10,000 | 4404.1 | 2352.9 | 2357.7 | 1629.6 | -63% | 1.03x |
| ARC_DIAGRAM | 10,000 | 2185.1 | 693.1 | 691.1 | 687.9 | -69% | 1.04x |
| GRAPH | 10,000 | 1691.3 | 379.3 | 380.0 | 248.8 | -85% | 1.03x |
| SANKEY | 10,000 | 4246.3 | 3098.7 | 3066.3 | 1432.4 | -66% | 1.08x |
| TREE | 100 | 112.6 | 81.7 | 79.9 | 51.8 | -54% | 1.14x |
| TREEMAP | 100 | 81.7 | 55.3 | 52.3 | 38.1 | -53% | 1.19x |
| SUNBURST | 100 | 153.6 | 136.8 | 137.2 | 117.9 | -23% | 1.10x |
| TREE | 1,000 | 652.8 | 321.5 | 322.9 | 180.1 | -72% | 1.13x |
| TREEMAP | 1,000 | 393.3 | 77.3 | 77.5 | 63.0 | -84% | 1.13x |
| SUNBURST | 1,000 | 875.9 | 683.7 | 686.6 | 649.0 | -26% | 1.08x |
| TREE | 10,000 | 6623.2 | 2509.0 | 2660.0 | 1437.3 | -78% | 1.17x |
| TREEMAP | 10,000 | 4018.5 | 347.2 | 346.2 | 325.9 | -92% | 1.04x |
| SUNBURST | 10,000 | 8363.2 | 6284.4 | 6125.2 | 6122.1 | -27% | 1.12x |
| HEATMAP | 100 | 48.8 | 48.7 | 47.9 | 27.4 | -44% | 1.03x |
| HEATMAP | 1,000 | 55.9 | 51.2 | 50.8 | 30.0 | -46% | 1.03x |
| HEATMAP | 10,000 | 67.8 | 53.5 | 53.4 | 31.7 | -53% | 1.03x |

**Closed marks fill nonzero since #267.** The 0.16.0 column is the
first with `FillRule.NONZERO` on closed marks, which routes their large
fills through the exact-area rasterizer instead of the 4x4-supersampled
even-odd sweep: SANKEY at 10,000 edges 3.07 s to 1.43 s
(-53%) and CHORD 2.36 s to 1.63 s (-31%). That
is dataviz's change, not the canvas bump's: between `a8e7bc9` and
`2434b00`, where only the canvas differs, CHORD is -0% and SANKEY
+11%, the one real regression in that pair (see below).

**The fixed cost of a chart fell in the 0.16.0 column, also from
dataviz.** A 100-point POINT or LINE chart was 53, 53 and
53 ms across the first three columns and is 31 ms in the fourth. The
median raster row that draws any text is 26 ms cheaper in the 0.16.0
column than in the 0.15.0 column, but only 2 ms cheaper between
`a8e7bc9` and `2434b00`. The difference is #272: one `FontCache` per
figure instead of one per measurement pass plus one for drawing, and
constructing a `FontCache` on canvas 0.15.0 was an eager ~19 ms
installed-font scan. canvas 0.16.0 makes that construction lazy
(#204), which is what let #283 drop dataviz's wrapper, but by then no
render was constructing a second one.

## SVG (`render_svg()`)

| Mark | n | 0.13.0 (ms) | 0.14.0 (ms) | 0.15.0 (ms) | 0.16.0 (ms) | 0.16.0 vs 0.13.0 | spread |
|---|---:|---:|---:|---:|---:|---:|---:|
| POINT | 100 | 19.7 | 19.5 | 19.2 | 19.7 | +0% | 1.04x |
| LINE | 100 | 19.3 | 19.6 | 19.0 | 19.5 | +1% | 1.06x |
| POINT | 1,000 | 20.0 | 20.2 | 20.0 | 19.9 | -1% | 1.04x |
| LINE | 1,000 | 19.6 | 19.7 | 19.4 | 19.8 | +1% | 1.03x |
| POINT | 10,000 | 26.7 | 26.9 | 27.3 | 22.6 | -15% | 1.10x |
| LINE | 10,000 | 20.3 | 20.2 | 19.6 | 19.9 | -2% | 1.12x |
| POINT | 100,000 | 100.9 | 99.2 | 105.9 | 53.3 | -47% | 1.06x |
| LINE | 100,000 | 21.9 | 21.9 | 21.2 | 21.8 | -1% | 1.14x |
| BAR | 100 | 39.8 | 39.6 | 38.5 | 20.0 | -50% | 1.05x |
| BAR | 1,000 | 48.9 | 44.2 | 44.5 | 23.2 | -53% | 1.04x |
| BAR | 10,000 | 148.1 | 105.7 | 107.2 | 60.1 | -59% | 1.07x |
| BEESWARM | 100 | 38.4 | 38.8 | 37.7 | 19.2 | -50% | 1.06x |
| VIOLIN | 100 | 38.7 | 38.7 | 37.6 | 19.3 | -50% | 1.03x |
| BEESWARM | 1,000 | 39.2 | 39.6 | 38.5 | 19.8 | -50% | 1.04x |
| VIOLIN | 1,000 | 38.8 | 39.0 | 37.8 | 19.6 | -49% | 1.04x |
| BEESWARM | 10,000 | 47.6 | 47.2 | 46.8 | 23.1 | -51% | 1.03x |
| VIOLIN | 10,000 | 41.4 | 41.3 | 40.4 | 22.1 | -47% | 1.04x |
| CHORD | 100 | 21.0 | 20.5 | 20.4 | 20.8 | -1% | 1.05x |
| ARC_DIAGRAM | 100 | 0.5 | 0.5 | 0.5 | 0.2 | -51% | 1.07x |
| GRAPH | 100 | 0.4 | 0.4 | 0.4 | 0.2 | -55% | 1.04x |
| SANKEY | 100 | 0.5 | 0.5 | 0.5 | 0.3 | -49% | 1.09x |
| CHORD | 1,000 | 33.2 | 30.9 | 30.9 | 25.4 | -23% | 1.02x |
| ARC_DIAGRAM | 1,000 | 4.3 | 4.4 | 4.9 | 2.1 | -52% | 1.04x |
| GRAPH | 1,000 | 3.5 | 3.5 | 3.7 | 1.5 | -56% | 1.02x |
| SANKEY | 1,000 | 4.7 | 4.7 | 5.0 | 2.3 | -51% | 1.02x |
| CHORD | 10,000 | 164.2 | 140.5 | 142.6 | 79.9 | -51% | 1.19x |
| ARC_DIAGRAM | 10,000 | 45.2 | 44.9 | 50.1 | 23.1 | -49% | 1.21x |
| GRAPH | 10,000 | 36.1 | 35.9 | 38.8 | 16.3 | -55% | 1.19x |
| SANKEY | 10,000 | 48.8 | 49.5 | 51.8 | 24.5 | -50% | 1.06x |
| TREE | 100 | 20.7 | 20.4 | 20.1 | 21.2 | +2% | 1.07x |
| TREEMAP | 100 | 20.7 | 20.9 | 20.0 | 21.0 | +1% | 1.06x |
| SUNBURST | 100 | 20.5 | 20.4 | 20.0 | 20.8 | +2% | 1.07x |
| TREE | 1,000 | 32.3 | 27.9 | 27.9 | 25.6 | -21% | 1.05x |
| TREEMAP | 1,000 | 31.5 | 26.9 | 26.7 | 24.9 | -21% | 1.05x |
| SUNBURST | 1,000 | 31.5 | 26.5 | 26.6 | 24.9 | -21% | 1.04x |
| TREE | 10,000 | 151.7 | 107.4 | 111.8 | 78.4 | -48% | 1.04x |
| TREEMAP | 10,000 | 139.6 | 95.4 | 97.5 | 68.6 | -51% | 1.02x |
| SUNBURST | 10,000 | 137.0 | 91.0 | 95.6 | 66.8 | -51% | 1.04x |
| HEATMAP | 100 | 19.9 | 19.8 | 19.7 | 20.7 | +4% | 1.02x |
| HEATMAP | 1,000 | 20.8 | 20.6 | 20.9 | 21.0 | +1% | 1.08x |
| HEATMAP | 10,000 | 29.6 | 29.2 | 30.2 | 24.6 | -17% | 1.03x |

## The 0.16.0 bump alone

`a8e7bc9` (the commit before the bump, canvas 0.15.0) against
`2434b00` (the bump, canvas 0.16.0), identical dataviz code, same
sweep. Of 82 rows, the 36 that moved by 10% or more:

| Mark | backend | n | `a8e7bc9` on 0.15.0 (ms) | `2434b00` on 0.16.0 (ms) | change |
|---|---|---:|---:|---:|---:|
| POINT | svg | 10,000 | 27.6 | 22.6 | -18% |
| POINT | svg | 100,000 | 101.6 | 53.3 | -48% |
| LINE | raster | 100,000 | 48.4 | 42.3 | -13% |
| BAR | raster | 100 | 34.9 | 31.1 | -11% |
| BAR | raster | 1,000 | 81.5 | 71.4 | -12% |
| BAR | svg | 1,000 | 26.2 | 23.2 | -11% |
| BAR | raster | 10,000 | 627.6 | 540.7 | -14% |
| BAR | svg | 10,000 | 89.9 | 60.1 | -33% |
| BEESWARM | raster | 1,000 | 37.3 | 29.8 | -20% |
| BEESWARM | svg | 10,000 | 28.7 | 23.1 | -19% |
| ARC_DIAGRAM | raster | 100 | 73.6 | 36.5 | -50% |
| ARC_DIAGRAM | svg | 100 | 0.5 | 0.2 | -55% |
| GRAPH | raster | 100 | 33.4 | 29.6 | -12% |
| GRAPH | svg | 100 | 0.4 | 0.2 | -56% |
| SANKEY | svg | 100 | 0.5 | 0.3 | -51% |
| CHORD | svg | 1,000 | 30.9 | 25.4 | -18% |
| ARC_DIAGRAM | svg | 1,000 | 4.8 | 2.1 | -57% |
| GRAPH | raster | 1,000 | 68.7 | 48.7 | -29% |
| GRAPH | svg | 1,000 | 3.8 | 1.5 | -59% |
| SANKEY | svg | 1,000 | 4.9 | 2.3 | -53% |
| CHORD | svg | 10,000 | 137.7 | 79.9 | -42% |
| ARC_DIAGRAM | svg | 10,000 | 48.9 | 23.1 | -53% |
| GRAPH | raster | 10,000 | 381.8 | 248.8 | -35% |
| GRAPH | svg | 10,000 | 36.9 | 16.3 | -56% |
| SANKEY | raster | 10,000 | 1289.1 | 1432.4 | +11% |
| SANKEY | svg | 10,000 | 51.1 | 24.5 | -52% |
| TREE | raster | 100 | 60.7 | 51.8 | -15% |
| TREEMAP | raster | 100 | 32.2 | 38.1 | +18% |
| TREE | raster | 1,000 | 287.4 | 180.1 | -37% |
| TREE | svg | 1,000 | 28.7 | 25.6 | -11% |
| TREEMAP | raster | 1,000 | 56.9 | 63.0 | +11% |
| TREE | raster | 10,000 | 2452.7 | 1437.3 | -41% |
| TREE | svg | 10,000 | 111.5 | 78.4 | -30% |
| TREEMAP | svg | 10,000 | 96.8 | 68.6 | -29% |
| SUNBURST | svg | 10,000 | 95.1 | 66.8 | -30% |
| HEATMAP | svg | 10,000 | 30.7 | 24.6 | -20% |

The rest are within noise. What the canvas_mojo
[v0.16.0](https://github.com/randyzwitch/canvas_mojo/releases/tag/v0.16.0)
notes predict, and where each lands:

- **SVG elements 2.4 to 3.2x cheaper (canvas #198).** Every element
  used to be built as one `a + b + ...` `String` chain, each `+`
  allocating and copying the prefix, with `_format_svg_float` alone
  making four to six strings per number. Elements are now written
  into the body with `String.write` runs; the bytes are identical.
  Every SVG row with many elements moves: the label-free edge marks
  halve at every size (ARC_DIAGRAM at n=10,000 49 to 23 ms, GRAPH
  37 to 16, SANKEY 51 to 24; at n=100 they go from half a millisecond
  to a quarter), and the label-bearing rows lose the same per-element
  cost under their ~20 ms of layout: BAR at 10,000 categories
  -33%, CHORD -42%, TREE -30%, HEATMAP -20%, POINT at 100,000 markers
  -48%. This is the reversal of the 0.15.0 regression the first
  version of this page documented, and more: every one of those rows
  is now below its 0.13.0 value.
- **Strokes use exact-area anti-aliasing (canvas #192)** where the
  outline is simple, falling back to the 4x4 sweep at a hairpin. On
  raster this is the second-largest effect in the pair, on the marks
  whose ink is mostly strokes: TREE at 10,000 nodes (one link per
  node) 2453 to 1437 ms (-41%), GRAPH at 10,000 edges 382 to 249 ms
  (-35%), ARC_DIAGRAM at 100 edges, whose arcs are the widest
  strokes in the sweep, 74 to 36 ms (-50%; at 1,000 and 10,000 the
  arcs are a few pixels wide and the row does not move), and LINE at
  100,000 points -13% after dataviz's own pixel-column decimation.
  BEESWARM at 1,000 (-20%) is filled-circle markers under the plot
  clip, which no 0.16.0 note names; that row is unattributed.
- **`FontCache()` construction 18 ms to 20 ns (canvas #204).** No
  effect in this pair, by design: `a8e7bc9` already carried dataviz's
  own lazy wrapper from #272, so neither side constructed a cache it
  did not use. The floor itself moves a little from the strokes and
  circles in an axis frame (POINT at n=100 36 to 33 ms, -9%).
- **Text is kerned and ligated by default (canvas #202, #208).** Label
  widths change by a pixel or two; the layout passes measure the same
  strings, and no row moves from it.
- **Three rows read slower, one of them really.** SANKEY at 10,000
  edges on raster is 1289 to 1432 ms (+11%) with non-overlapping
  passes (1255, 1289, 1357 against 1401, 1432, 1433). The ribbons are plain
  `fill_path_aa` nonzero fills, nothing stroked, and no 0.16.0 note
  names that path; which change costs them is not identified here. TREEMAP at 100 and 1,000 leaves
  (+18%, +11%) and POINT at 10,000 (+9%) are bimodal instead: one of
  the three 0.16.0 passes sits at the `a8e7bc9` value and two sit
  higher (TREEMAP n=100: 32, 32, 33 against 32, 38, 38), which is what a
  descheduled band looks like, not a code change.

## What moved across the four pins, and why

The canvas_mojo release notes for
[v0.14.0](https://github.com/randyzwitch/canvas_mojo/releases/tag/v0.14.0),
[v0.15.0](https://github.com/randyzwitch/canvas_mojo/releases/tag/v0.15.0) and
[v0.16.0](https://github.com/randyzwitch/canvas_mojo/releases/tag/v0.16.0)
name the mechanisms; this is where each one shows up in a dataviz
chart, reading the 0.13.0 column against the 0.16.0 column.

- **Anything with many labels.** 0.14.0's `FontCache` rasterizes each
  glyph once (about 8x on cached text) and its text-measurement path
  got faster with it. dataviz measures every category tick label to
  lay out the axis frame and then draws them, so label count is what
  BAR (one label per category), TREE and TREEMAP (one per node) and
  CHORD (one per node around the ring) scale with. BAR at 10,000
  categories is -73% on raster and -59% on SVG; the SVG backend
  rasterizes nothing, but the layout pass still measures every label,
  and 0.16.0's cheaper elements take the SVG row the rest of the way.
- **Many small marks or clip paths.** 0.14.0 stopped copying the
  `Canvas` struct into every `set_pixel`-bound call (about 40% per
  primitive, more under a clip path). TREEMAP at 10,000 leaves is the
  extreme case, 4.02 s to 0.33 s (-92%), because every leaf is a
  small fill clipped to its own rectangle; GRAPH at 10,000 nodes
  (-85%) and ARC_DIAGRAM (-69%) are the same effect on markers and
  thin arcs, and TREE (-78%) combines it with the label cost above and
  0.16.0's strokes.
- **Strokes and sweeps.** 0.14.0's edge sort, single clip test per row
  and pre-reserved edge tables, then 0.16.0's exact-area strokes. LINE
  at 100,000 points is -61% and POINT at 100,000 markers -43%, the
  latter mostly the `set_pixel` fix on the markers.
- **SVG element building.** Flat from 0.13.0 to 0.14.0, 5 to 13%
  slower at 0.15.0 on the rows with nothing else in them, then 2.4 to
  3.2x cheaper per element at 0.16.0: ARC_DIAGRAM on SVG at 10,000
  edges is 45.2 / 44.9 / 50.1 / 23.1 ms across the four columns. See the
  correction below for what the 0.15.0 step actually was.
- **One font scan per figure, not three.** The ~19 ms floor drop in
  the 0.16.0 column, explained under the raster table: dataviz #272
  on a canvas whose `FontCache` construction was the scan. A 100-point
  chart on raster is -41% / -42% (POINT / LINE) across the four pins; on
  SVG, which never constructed a second cache, +0% / +1%.
- **Large closed fills.** The exact-area rasterizer 0.14.0 introduced
  for `FillRule.NONZERO` reaches dataviz's marks with #267 in the
  0.16.0 column: SANKEY at 10,000 edges -66%, CHORD -63% across the four
  pins, nearly all of it in that last step and none of it canvas
  0.16.0's own doing.

## What did not move

- **HEATMAP's cells.** Hard-edged axis-aligned rectangles with no
  per-cell text, so neither the glyph cache, the anti-aliased sweep
  nor the exact-area strokes touch them. Its raster rows are -44% to
  -53% across the four pins, all of it the `set_pixel` fix on the cell
  fills plus the font scan every raster render stopped paying twice;
  its SVG rows are flat through 0.15.0 and -20% at 10,000 cells in
  0.16.0 from the cheaper elements, nothing from the cells themselves.
- **The SVG floor.** A 100-point chart on SVG is 19.7 ms on 0.13.0 and
  19.7 ms on 0.16.0: axis-frame layout and label measurement, which no
  release has changed, and the one font scan every SVG render with
  text has always paid exactly once.
- **The banded marks' machine dependence.** SUNBURST at 10,000
  (6122.1 ms) and SANKEY at 10,000 (1432.4 ms) are still the rows whose
  fills span enough pixels to band across all 64 threads, still the
  rows that spread most between passes, and still the rows a laptop
  will disagree with.

### Correction

The first version of this page (#268) attributed the 0.15.0 SVG
slowdown on the label-free edge marks to the `dashes: List[Float64] =
List[Float64]()` default that 0.15.0 added to the stroke trait
methods, "one empty-list construction per stroked element". That was
wrong, and it was wrong in a specific way: the mechanism was inferred
from reading the 0.15.0 diff (a new default-valued `List` parameter,
therefore "an allocation per call") and never timed. When the
canvas_mojo side isolated it, an empty Mojo `List` turned out not to
allocate at all, a caller-supplied empty `dashes` list changed
nothing, and removing `_transform_attr()` and `_stroke_attrs(...)`
from the element string one at a time each recovered a chunk of the
time. The cost was the `+` chain each SVG element was built from:
0.15.0 appended those two terms per element, and every `+` allocated
a new `String` and copied the prefix. That is canvas #193, fixed in
#198, which is what the 0.16.0 column reverses. The lesson for this
page is the one from the Method section: a mechanism read off a diff
is a hypothesis until someone times it in isolation.

## Reproducing

```bash
pixi run bench            # one pass, prints every row above
pixi run bench --check    # adds the quadratic-scaling detector
```

To get the numbers for an older pin, check out the commit named in the
table above into a detached worktree and run `pixi install` there (it
builds canvas_mojo from its tag), then `pixi run bench` from that
worktree. Run each configuration at least three times, interleaved,
take the median, and report the spread; and run on an otherwise idle
machine, or the banded marks will not be comparable between passes,
let alone between pins. To isolate a canvas bump from the dataviz
changes that landed around it, measure the bump commit's parent in
the same sweep.
