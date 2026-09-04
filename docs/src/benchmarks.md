---
title: Benchmarks
type: docs
weight: 350
---

Render times from `pixi run bench` (`scripts/bench.mojo`) across the
three most recent canvas_mojo pins, so the effect of a pin bump is on
record rather than remembered, and so there is a baseline to measure
future changes (a matplotlib comparison, `FillRule.NONZERO` on closed
marks) against. The columns are the same dataviz code against a
different canvas: the only dataviz source change between the 0.13.0
and 0.14.0 columns is `ColorScale` following a renamed gradient helper
(not on any benchmarked path), and the only change between the 0.14.0
and 0.15.0 columns is the additive `Mark.BARBS`.

| Column | dataviz commit | canvas_mojo |
|---|---|---|
| 0.13.0 | `82d037a` (parent of the 0.14.0 bump) | v0.13.0 |
| 0.14.0 | `44f2100` (#263) | v0.14.0 |
| 0.15.0 | `3fd5a7e` (v0.8.0) | v0.15.0 |

## Machine

- AMD Ryzen Threadripper 3970X: 32 cores, 64 threads, 128 MiB L3, up
  to 4.55 GHz, `schedutil` governor. 125 GiB RAM.
- Ubuntu 24.04.4 LTS, Linux 7.0.0, Mojo 1.0.0, pixi 0.78.0.
- `Sans` resolves to Noto Sans Regular through fontconfig.
- canvas_mojo bands a fill, clip mask or downsample across
  `parallelism_level()` tasks (64 here) once its bounding box covers at
  least 40,000 pixels (`_MIN_PARALLEL_PIXELS` in `aa_crossing.mojo`,
  `resize.mojo` and `shapes/arcs.mojo`, the same value in all three
  pins). Every raster render here draws at the default
  `Theme.raster_supersample = 3`, so the internal canvas is 2400x1800
  and the final downsample, every axis-frame clip mask and any fill
  wider than about 200x200 supersampled pixels (a SANKEY ribbon, a
  CHORD band, a SUNBURST ring) takes that path. **A single-core or
  laptop number will differ most on exactly those marks**; the
  glyph-sized fills and strokes that dominate the other rows run
  inline on one core regardless.

## Method

- Each column is the median of three complete `pixi run bench` passes,
  run back to back in the order 0.13.0, 0.14.0, 0.15.0, three times
  over, each column from a detached worktree at its commit: the 0.13.0
  and 0.14.0 worktrees with their own `pixi install` (canvas_mojo built
  from its tag), the 0.15.0 worktree driven by the repository's own
  0.15.0 environment.
- Times are wall-clock milliseconds for one `render()` (raster) or
  `render_svg()` (svg) call at 800x600 with the default theme, after
  the script's own warm-up render on each backend. Neither includes
  PNG encoding or writing a file.
- The machine was otherwise idle for these passes. The `spread`
  column is the worst max/min ratio among the three passes of any one
  column in that row: 90% of cells are within 1.06x, the worst is
  1.21x (TREE raster n=1,000, 0.15.0).
  Treat differences under about 10% as noise.
- An earlier sweep of the same nine passes was taken while another
  session ran this repo's test suite on the same machine (load average
  18 to 37 on 64 threads). Its large-n rows agreed with these within a
  few points, but its small-n rows overstated the 0.13.0 to 0.15.0 gain
  by 10 to 30 points (0.13.0 happened to draw the worse share of the
  load), and the marks whose large fills band across cores (SANKEY,
  CHORD, SUNBURST) spread 2 to 3x between passes. Those numbers were
  discarded; a contended machine does not just add noise, it biases.
- Bench from a detached worktree at a known commit, never from the
  main checkout: during that earlier sweep the main checkout was
  switched to a feature branch mid-run by another session, and two of
  its passes silently measured that branch instead of `3fd5a7e`.

## Raster (`render()`)

| Mark | n | 0.13.0 (ms) | 0.14.0 (ms) | 0.15.0 (ms) | 0.15.0 vs 0.13.0 | spread |
|---|---:|---:|---:|---:|---:|---:|
| POINT | 100 | 56.0 | 54.7 | 54.3 | -3% | 1.17x |
| LINE | 100 | 54.7 | 52.9 | 52.3 | -4% | 1.04x |
| POINT | 1,000 | 61.3 | 53.8 | 53.1 | -13% | 1.04x |
| LINE | 1,000 | 54.1 | 52.1 | 50.8 | -6% | 1.05x |
| POINT | 10,000 | 96.5 | 76.8 | 74.9 | -22% | 1.02x |
| LINE | 10,000 | 66.5 | 57.1 | 54.7 | -18% | 1.07x |
| POINT | 100,000 | 504.7 | 316.5 | 313.4 | -38% | 1.03x |
| LINE | 100,000 | 108.4 | 69.0 | 63.7 | -41% | 1.05x |
| BAR | 100 | 81.7 | 80.0 | 72.0 | -12% | 1.09x |
| BAR | 1,000 | 230.2 | 121.2 | 120.1 | -48% | 1.03x |
| BAR | 10,000 | 1976.8 | 669.4 | 667.1 | -66% | 1.09x |
| BEESWARM | 100 | 65.7 | 66.9 | 65.8 | +0% | 1.03x |
| VIOLIN | 100 | 70.2 | 71.1 | 68.5 | -2% | 1.04x |
| BEESWARM | 1,000 | 69.9 | 69.3 | 68.2 | -2% | 1.03x |
| VIOLIN | 1,000 | 69.7 | 71.1 | 68.5 | -2% | 1.05x |
| BEESWARM | 10,000 | 94.2 | 91.4 | 90.7 | -4% | 1.03x |
| VIOLIN | 10,000 | 72.7 | 73.0 | 71.1 | -2% | 1.04x |
| CHORD | 100 | 105.8 | 89.5 | 88.3 | -17% | 1.06x |
| ARC_DIAGRAM | 100 | 93.6 | 67.4 | 66.6 | -29% | 1.06x |
| GRAPH | 100 | 42.2 | 33.6 | 33.5 | -21% | 1.01x |
| SANKEY | 100 | 122.4 | 123.9 | 123.6 | +1% | 1.06x |
| CHORD | 1,000 | 506.4 | 324.9 | 319.9 | -37% | 1.04x |
| ARC_DIAGRAM | 1,000 | 217.9 | 95.8 | 95.6 | -56% | 1.02x |
| GRAPH | 1,000 | 174.2 | 69.0 | 68.9 | -60% | 1.04x |
| SANKEY | 1,000 | 450.9 | 364.4 | 350.9 | -22% | 1.09x |
| CHORD | 10,000 | 4484.0 | 2380.4 | 2357.7 | -47% | 1.02x |
| ARC_DIAGRAM | 10,000 | 2182.0 | 686.5 | 698.2 | -68% | 1.01x |
| GRAPH | 10,000 | 1680.7 | 379.1 | 382.5 | -77% | 1.02x |
| SANKEY | 10,000 | 4372.3 | 3021.6 | 3007.2 | -31% | 1.05x |
| TREE | 100 | 109.6 | 80.7 | 83.7 | -24% | 1.06x |
| TREEMAP | 100 | 80.2 | 52.2 | 51.3 | -36% | 1.13x |
| SUNBURST | 100 | 152.1 | 135.1 | 138.9 | -9% | 1.13x |
| TREE | 1,000 | 652.1 | 316.8 | 325.6 | -50% | 1.21x |
| TREEMAP | 1,000 | 395.2 | 77.6 | 77.5 | -80% | 1.01x |
| SUNBURST | 1,000 | 888.0 | 703.7 | 682.7 | -23% | 1.06x |
| TREE | 10,000 | 6566.3 | 2535.6 | 2638.0 | -60% | 1.04x |
| TREEMAP | 10,000 | 4032.8 | 344.5 | 350.5 | -91% | 1.01x |
| SUNBURST | 10,000 | 8243.9 | 6124.7 | 6278.7 | -24% | 1.03x |
| HEATMAP | 100 | 48.8 | 47.9 | 48.0 | -2% | 1.03x |
| HEATMAP | 1,000 | 56.0 | 50.8 | 50.0 | -11% | 1.02x |
| HEATMAP | 10,000 | 68.0 | 53.1 | 53.0 | -22% | 1.03x |

**What `FillRule.NONZERO` will do (preview).** The issue behind this
page predicted that nonzero fills would move once marks switch to them
(0.14.0's exact-area rasterizer serves only `FillRule.NONZERO` and
text; every mark above still fills even-odd). #256 makes that switch
for closed marks. Its commit `c8a3abb` (one commit on `3fd5a7e`, same
canvas 0.15.0 environment, same idle machine, same fixture, four
`render()` calls in one process) gives SANKEY at 10,000 edges
1.42 s against 3.01 s here (-53%) and CHORD 1.68 s
against 2.36 s (-29%): the ribbons and bands are the
large closed fills that leave the 4x4-supersampled even-odd sweep for
the area accumulator. The next full sweep after #256 lands is where
the rest of that column gets measured.

## SVG (`render_svg()`)

| Mark | n | 0.13.0 (ms) | 0.14.0 (ms) | 0.15.0 (ms) | 0.15.0 vs 0.13.0 | spread |
|---|---:|---:|---:|---:|---:|---:|
| POINT | 100 | 19.8 | 19.8 | 19.3 | -3% | 1.06x |
| LINE | 100 | 19.7 | 19.4 | 19.2 | -3% | 1.06x |
| POINT | 1,000 | 20.4 | 20.3 | 20.5 | +0% | 1.04x |
| LINE | 1,000 | 19.7 | 19.7 | 19.6 | -1% | 1.05x |
| POINT | 10,000 | 26.9 | 27.1 | 27.4 | +2% | 1.02x |
| LINE | 10,000 | 19.9 | 20.2 | 19.7 | -1% | 1.02x |
| POINT | 100,000 | 98.1 | 98.8 | 104.1 | +6% | 1.05x |
| LINE | 100,000 | 21.5 | 22.0 | 21.3 | -1% | 1.20x |
| BAR | 100 | 39.8 | 39.6 | 38.6 | -3% | 1.03x |
| BAR | 1,000 | 48.5 | 45.9 | 45.2 | -7% | 1.13x |
| BAR | 10,000 | 148.5 | 106.0 | 107.8 | -27% | 1.04x |
| BEESWARM | 100 | 38.3 | 38.3 | 38.0 | -1% | 1.04x |
| VIOLIN | 100 | 38.3 | 38.3 | 37.8 | -1% | 1.07x |
| BEESWARM | 1,000 | 39.2 | 39.2 | 39.0 | -1% | 1.03x |
| VIOLIN | 1,000 | 38.5 | 38.5 | 38.1 | -1% | 1.05x |
| BEESWARM | 10,000 | 47.0 | 46.8 | 47.4 | +1% | 1.06x |
| VIOLIN | 10,000 | 41.3 | 41.0 | 40.9 | -1% | 1.03x |
| CHORD | 100 | 20.7 | 20.4 | 20.4 | -1% | 1.03x |
| ARC_DIAGRAM | 100 | 0.5 | 0.5 | 0.5 | +14% | 1.02x |
| GRAPH | 100 | 0.4 | 0.4 | 0.4 | +5% | 1.16x |
| SANKEY | 100 | 0.5 | 0.5 | 0.5 | +5% | 1.01x |
| CHORD | 1,000 | 33.1 | 30.7 | 30.9 | -7% | 1.02x |
| ARC_DIAGRAM | 1,000 | 4.3 | 4.4 | 4.8 | +11% | 1.03x |
| GRAPH | 1,000 | 3.5 | 3.5 | 3.8 | +10% | 1.02x |
| SANKEY | 1,000 | 4.7 | 4.7 | 5.0 | +6% | 1.02x |
| CHORD | 10,000 | 164.7 | 138.6 | 143.8 | -13% | 1.02x |
| ARC_DIAGRAM | 10,000 | 46.3 | 44.4 | 50.1 | +8% | 1.05x |
| GRAPH | 10,000 | 36.9 | 34.7 | 38.7 | +5% | 1.06x |
| SANKEY | 10,000 | 48.6 | 49.0 | 52.0 | +7% | 1.04x |
| TREE | 100 | 20.6 | 20.4 | 20.2 | -2% | 1.04x |
| TREEMAP | 100 | 20.6 | 20.4 | 20.2 | -2% | 1.06x |
| SUNBURST | 100 | 20.5 | 20.3 | 20.3 | -1% | 1.01x |
| TREE | 1,000 | 32.2 | 28.7 | 28.2 | -12% | 1.03x |
| TREEMAP | 1,000 | 31.1 | 27.0 | 27.0 | -13% | 1.02x |
| SUNBURST | 1,000 | 30.6 | 26.9 | 27.0 | -12% | 1.07x |
| TREE | 10,000 | 149.8 | 108.5 | 111.5 | -26% | 1.12x |
| TREEMAP | 10,000 | 139.6 | 95.0 | 97.8 | -30% | 1.04x |
| SUNBURST | 10,000 | 139.0 | 92.4 | 95.7 | -31% | 1.05x |
| HEATMAP | 100 | 20.0 | 19.9 | 19.6 | -2% | 1.03x |
| HEATMAP | 1,000 | 20.9 | 20.9 | 20.7 | -1% | 1.07x |
| HEATMAP | 10,000 | 29.9 | 29.6 | 30.1 | +1% | 1.04x |

## What moved, and why

The canvas_mojo release notes for
[v0.14.0](https://github.com/randyzwitch/canvas_mojo/releases/tag/v0.14.0)
and
[v0.15.0](https://github.com/randyzwitch/canvas_mojo/releases/tag/v0.15.0)
name the mechanisms; this is where each one shows up in a dataviz
chart.

- **Anything with many labels.** 0.14.0's `FontCache` rasterizes each
  glyph once (about 8x on cached text) and its text-measurement path
  got faster with it. dataviz measures every category tick label to
  lay out the axis frame and then draws them, so label count is what
  BAR (one label per category), TREE and TREEMAP (one per node) and
  CHORD (one per node around the ring) scale with. BAR at 10,000
  categories is -66% on raster and -27% on SVG: the SVG backend
  rasterizes nothing, but the layout pass still measures every label.
- **Many small marks or clip paths.** 0.14.0 stopped copying the
  `Canvas` struct into every `set_pixel`-bound call (about 40% per
  primitive, more under a clip path). TREEMAP at 10,000 leaves is the
  extreme case, 4.03 s to 0.35 s (-91%), because every leaf is a
  small fill clipped to its own rectangle; GRAPH at 10,000 nodes
  (-77%) and ARC_DIAGRAM (-68%) are the same effect on markers and
  thin arcs, and TREE (-60%) combines it with the label cost above.
- **Strokes and sweeps.** The edge sort, single clip test per row and
  pre-reserved edge tables are 0.14.0's 15 to 25% on strokes. LINE at
  100,000 points (-41%, after dataviz's own pixel-column decimation has
  already reduced it) and POINT at 100,000 markers (-38%) are that,
  plus the `set_pixel` fix on the markers.
- **The fixed cost of a chart did not move.** A 100-point POINT or
  LINE chart is -3% / -4% on raster and -3% / -3% on SVG, noise.
  The floor is about 52 ms raster and 19 ms SVG for any chart at
  800x600 with the default supersample on all three pins: at n=100 the
  axis frame, a handful of tick labels, the plot-area clip mask and the
  2400x1800 downsample are the whole render, and the glyph cache has
  too few glyphs to repay. The gains above are all per-element costs,
  so they need elements to show.
- **0.14.0 to 0.15.0 is flat on raster.** 0.15.0 is a correctness
  release (the half-pixel offset in nonzero fills and text) plus SVG
  transform and stroke-style attributes; no raster cell moves more
  than 10% between those two columns.

## What did not move

- **HEATMAP: -2% to -22% raster, flat on SVG.** Its cells are
  hard-edged axis-aligned rectangles with no per-cell text, so neither
  the glyph cache nor the anti-aliased sweep touches them; the raster
  gain at 10,000 cells is the `set_pixel` fix on the cell fills, and
  the 100-cell chart is entirely fixed cost.
- **Even-odd fills.** 0.14.0's exact-area rasterizer (256 coverage
  levels, about 4x faster on glyph-sized shapes) applies only to
  `FillRule.NONZERO` fills and text. Every dataviz mark still fills
  even-odd, the trait's default, so none of that 4x is in these
  tables; #256 (switch closed marks to NONZERO) is where it would
  appear, and this page is the baseline to measure it against.
- **SVG edge marks without tick labels got slightly slower, in
  0.15.0.** ARC_DIAGRAM, GRAPH and SANKEY on SVG have no axis frame and
  so almost no text: under a millisecond at n=100, and +8% /
  +5% / +7% at n=10,000 against 0.13.0. All of it arrives at 0.15.0
  (0.13.0 to 0.14.0 is flat for them), and it is the same few
  milliseconds on each: 0.15.0's `DrawTarget.draw_line_aa` and
  `stroke_path_aa` take the full stroke style, and their
  `dashes: List[Float64] = List[Float64]()` default constructs an empty
  list per call, roughly half a microsecond on every stroked edge or
  arc. The raster rows for the same marks move by the same few
  milliseconds, hidden inside the percentage. Nothing else in these
  renders exists to hide it on SVG.

## Reproducing

```bash
pixi run bench            # one pass, prints every row above
pixi run bench --check    # adds the quadratic-scaling detector
```

To get the numbers for an older pin, check out the commit named in the
table above into a worktree and run `pixi install` there (it builds
canvas_mojo from its tag), then `pixi run bench` from that worktree.
Run each pin at least three times, take the median, and report the
spread; and run on an otherwise idle machine, or the banded marks will
not be comparable between passes, let alone between pins.
