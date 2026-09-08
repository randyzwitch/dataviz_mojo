# Benchmarking dataviz_mojo

Notes for whoever runs `pixi run bench` next. **Not a docs page** — it
lives outside `docs/src/` on purpose.

There used to be a published Benchmarks page carrying per-pin timing
tables. It was removed (#416): its tables stopped at canvas_mojo
v0.16.0 while the package moved on to v0.25.0, nothing linked to it,
and its own opening line described its purpose as keeping the effect of
a bump "on record rather than remembered" — a maintainer's changelog
rather than something an end user came looking for. Stale performance
numbers are worse than none, because a reader cannot tell they are
stale.

What survives here is the part that is still true and still useful: how
to measure, on what, and the one current measurement. The per-pin
tables are in git history if anyone wants them; find the commit that
removed the page with

    git log --diff-filter=D -- docs/src/benchmarks.md

and read it from that commit's parent.

If a published performance page is ever wanted, it should answer the
question a reader actually arrives with ("is this fast enough, and how
does it compare to matplotlib?"), be dated, and be regenerated on a
schedule someone has agreed to keep.

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

## The fixed floor per render, on canvas_mojo v0.24.0

The tables above measure how a mark scales with `n`. This section is
the other half: what a chart costs before it draws anything, which is
what decides the time of a small chart. Measured on 2026-09-07 on the
machine described above, canvas_mojo v0.24.0, median of three passes
of twelve renders each, spread under 1%.

Every `render()`, `render_svg()` and `save()` builds its own
`FontCache`, so each one pays that cache's cold cost:

| step, on a cache that has resolved nothing yet | ms |
|---|---:|
| `FontCache()` construction | 0.00003 |
| first `resolve()` -- reads canvas's persisted font database | 2.35 |
| first `resolve_face()` after it -- TTF parse + `set_pixel_size` | 0.18 |
| a later `resolve_face()` on the same cache | 0.02 |

2.5 ms, then, per render, whatever the chart draws. Against a
640x420 chart end to end, via `save()`:

| chart | default | with a shared, warm cache | difference |
|---|---:|---:|---:|
| scatter, n=2 (PNG) | 8.64 | 5.62 | -35% |
| scatter, n=2 (SVG) | 2.63 | 0.30 | -89% |
| bar, 20 categories (PNG) | 6.44 | 3.60 | -44% |
| line, n=10,000 (PNG) | 12.3 | 9.6 | -22% |
| scatter, n=1,000 (PNG) | 25.1 | 21.8 | -13% |

The SVG row is the one that shows what this cost is: that backend
measures text and rasterizes none, so nearly all of what it spends on
a small chart is resolving a font it will only name in an attribute.

**This is a floor, not a defect to fix here.** #324 opened against a
~18 ms version of this cost and proposed three fixes. A process-wide
cache, the one that would need no API change, is not expressible:
Mojo 1.0.0 rejects a module-scope `var` outright ("global variables
are not supported"). Making the cache lazier is already done -- a
render that measures no text never resolves a font, which
`test_a_render_that_measures_no_text_never_scans` asserts. Letting
callers pass a cache in was built and measured in #326 and closed
deliberately: canvas_mojo#272 persisted the font database to disk,
which took the cost from ~18 ms to the 2.5 ms above for every caller
with no API change, and what a caller-held cache could still win
after that did not justify permanent public API. The right place for
the remaining 2.35 ms is canvas, not here.

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
