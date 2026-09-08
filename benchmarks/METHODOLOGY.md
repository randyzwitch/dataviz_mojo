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

## The fixed floor per render, on canvas_mojo v0.25.0

The tables above measure how a mark scales with `n`. This section is
the other half: what a chart costs before it draws anything, which is
what decides the time of a small chart.

Measured 2026-09-08 on the machine described above, canvas_mojo v0.24.0
against v0.25.0, from two detached worktrees whose commits differ only
in `pixi.toml`/`pixi.lock` so the dataviz code is byte-identical. Three
passes each, interleaved, after one untimed warm-up per configuration;
starting one-minute load 1.16.

An 800x600 two-point scatter, which draws almost nothing, so the time
is the floor:

| | v0.24.0 | v0.25.0 | |
|---|---:|---:|---|
| `render_svg()` | 2.51 ms | **1.03 ms** | 2.44x |
| `render()` (raster, supersample 3) | 9.72 ms | **8.27 ms** | 1.18x |

The same ~1.47 ms leaves both, which is the signature of a constant
being removed rather than work getting faster. A five-label
`_max_label_width` against a cold cache moved 2.69 ms -> 1.20 ms over
the same pins; warm it is ~0.006 ms on both.

Across the whole `pixi run bench` sweep (88 cases) that constant shows
up only where it is a large share of the total:

| case size | svg | raster |
|---|---:|---:|
| under 5 ms | 1.79x | 1.63x |
| 5-50 ms | 1.08x | 1.07x |
| over 50 ms | 1.03x | 1.00x |

Whole-sweep total is 1.013x -- essentially unchanged -- because the
large raster cases dominate the sum. Quoting that single number, or
the 1.85x median-of-ratios, would both mislead: the honest statement
is that v0.25.0 removes a fixed per-render cost, which is most of a
small SVG chart and none of a large raster one.

**This is a floor, not a defect to fix here.** #324 opened against a
~18 ms version of this cost and proposed three fixes. A process-wide
cache, the one that would need no API change, is not expressible:
Mojo 1.0.0 rejects a module-scope `var` outright ("global variables
are not supported"). Making the cache lazier is already done -- a
render that measures no text never resolves a font, which
`test_a_render_that_measures_no_text_never_scans` asserts. Letting
callers pass a cache in was built and measured in #326 and closed
deliberately: canvas_mojo#272 persisted the font database to disk,
which removed most of the cost for every caller with no API change,
and v0.25.0 has now taken well over half of what remained. What a
caller-held cache could still win does not justify permanent public
API. The right place for the rest is canvas, not here.

## Why no timing figure lives in a docstring

They rot, silently, and a reader cannot tell. `dataviz/text.mojo` once
carried "a five-label call costs 2.52 ms cold and 0.028 ms warm -- a
ratio of 90". One canvas pin later the same measurement on the same
machine gave **1.20 ms cold, 0.0059 ms warm, a ratio of 200**: every
number in the sentence wrong, including the ratio, which had not
reproduced at 90 on the pin it was written for either.

They are also machine-specific, so a figure measured on the Threadripper
above tells a reader on a laptop nothing, and it invites the maintenance
of re-measuring every docstring on every bump -- which nobody signed up
for and nobody does.

A docstring's job is the contract: what the function does, its
arguments, what it returns and raises. The *shape* of a performance
argument can stay there when it justifies the API ("a fresh cache
re-pays the font database read, which is why there is no overload
without one"); the numbers belong here, dated, with the machine stated.

The one exception kept in the source is in `dataviz/image.mojo`: that a
512x512 `imshow` produces an 8.5 MB `<svg>` and should be saved as
`.png`. That is a property of the output format rather than of the
processor, it does not change when the machine does, and it directly
changes how a caller uses the function.

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
