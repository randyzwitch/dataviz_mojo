# Family renderer callbacks (#607)

`Plot.mark_*()` binds its family's renderer for Canvas, SVG, and PDF.
`_render_generic` invokes the selected backend callback instead of probing
all ten families. Public constructors, mark changes, copying/moving, and
heterogeneous `List[Plot]` composition retain their existing interfaces.

Continuous marks bind a no-op and use the existing shared continuous path.
Family renderers use positional adapters around their existing dispatch.
The three noncapturing (`thin`) pointers follow Plot's ordinary value
semantics; there is no closure allocation or separate callback lifetime.
The registration checklist lives in `dataviz/plot.mojo` and is referenced
from `dataviz/core/mark.mojo` and each family dispatcher.

This change removes unused-family compilation. It does not remove the
per-mark payload fields (#223), family imports in the builder, or dispatch
within a selected family. Registering all three callbacks can retain work
for unused backends. Adding another draw target requires extending the
callback fields and the concrete-backend dispatch.

## Current evaluation

The comparison uses unmodified main at `a7271c8` and the current
three-backend implementation, both with canvas_mojo 0.37.1 and Mojo 1.0.0.
The six small programs render line or hexbin using raster + SVG, SVG only,
or PDF only. Every chart is 400 x 300 with three data points and default
styling. PDF cases compare output length and a byte fingerprint.

Three cold builds per program and tree run in alternating order, with only
one build running at a time. The harness clears each tree's private Mojo
cache before every build, checks library/lockfile and benchmark hashes,
rejects failed builds, compares program stdout, and records wall time, CPU
time, peak memory, binary size, compiler versions, and source hashes.

| Program | Main wall median [range], s | Callbacks wall median [range], s | Main / callbacks CPU median, s | Main / callbacks bytes |
| --- | ---: | ---: | ---: | ---: |
| line_both | 77.19 [60.13–78.92] | 28.06 [27.57–31.23] | 157.03 / 81.88 | 3,999,800 / 1,669,408 |
| line_svg | 43.43 [40.96–49.17] | 20.70 [20.59–28.16] | 104.71 / 61.61 | 2,378,416 / 1,066,144 |
| line_pdf | 44.15 [43.74–44.57] | 23.09 [22.80–24.94] | 105.28 / 66.55 | 2,604,872 / 1,210,416 |
| hexbin_both | 60.01 [59.97–61.61] | 29.44 [29.35–29.49] | 148.88 / 86.65 | 3,994,928 / 1,822,032 |
| hexbin_svg | 41.15 [40.52–41.59] | 25.81 [25.22–46.78] | 101.73 / 75.58 | 2,377,648 / 1,462,928 |
| hexbin_pdf | 48.31 [44.58–59.92] | 27.54 [27.47–27.69] | 106.04 / 80.40 | 2,604,104 / 1,617,472 |

Measured on Linux with an AMD Ryzen Threadripper 3970X (32 cores,
64 logical CPUs). Baseline: `a7271c84a77ffd182fd3a078a69ca7f7c6cf418d`;
callback source: `9e838b9` (the merged library source is unchanged by
this report). Both use Mojo 1.0.0 (ed45d567). This was not an isolated
machine: wall times varied substantially in some runs, and all samples
are retained. CPU medians corroborate reduced compiler work; these small
cases do not predict every application's compile time.

All 36 builds succeeded and their stdout matched within each case.
`results/compile-results.json` records every sample, including peak RSS;
`results/compile-metadata.json` records source and case hashes, revisions,
compiler versions, and host details. Per-build stdout is also committed.


## Runtime sample

128 data points, default 640 x 420 plots, one untimed warmup per backend,
then 41 renders per backend in each process. Three alternating process
pairs ran after all timing builds. Entries are medians of the three
process medians, with ranges across those medians, in milliseconds.
The sample times render calls, including normal renderer allocation and
font work; it excludes SVG/PDF serialization and disk output.

| Case | Main ms [range] | Callbacks ms [range] | Change |
| --- | ---: | ---: | ---: |
| line, raster | 1.572 [1.542–1.610] | 1.645 [1.616–1.646] | +4.6% |
| line, svg | 1.135 [1.084–1.138] | 1.122 [1.092–1.136] | -1.1% |
| line, pdf | 2.057 [1.994–2.110] | 2.079 [2.016–2.099] | +1.1% |
| hexbin, raster | 4.859 [4.745–4.933] | 5.289 [5.091–5.464] | +8.9% |
| hexbin, svg | 1.395 [1.383–1.416] | 1.448 [1.396–1.462] | +3.9% |
| hexbin, pdf | 2.286 [2.250–2.344] | 2.305 [2.303–2.348] | +0.9% |

The sample shows a runtime cost, most visibly raster hexbin (about 9%),
with nonoverlapping process-median ranges. Raster line also has
nonoverlapping ranges; the other four cases overlap. These are small
samples from one host, not an assertion of runtime neutrality or a
general slowdown for all marks. The tradeoff is lower compile cost and
smaller binaries. Raw samples and process medians are in `results/runtime-*`.

## Permanent validation

`tests/test_renderer_callbacks.mojo` exercises all enumerated marks through
copying, moving into a heterogeneous collection, and list copying on all
three backends. It also checks default construction, fluent changes between
families and back to continuous rendering, mixed facets, and mixed layers.
Comparisons use complete raster pixels, SVG strings, and PDF bytes.

Main's dendrogram registry fix is incorporated: all 63 marks participate,
including its four-row clustered fixture. The committed raster/SVG mark
and composition digests are identical to main's expected outputs.

## Reproduce

Create a detached worktree at `a7271c8` and install its environment with
`pixi install --locked`. Install the PR's locked environment separately.
From the PR checkout, run:

```bash
python3 benchmarks/issue607/measure.py /path/to/main-baseline /path/to/pr /tmp/607-current-results
python3 benchmarks/issue607/measure_runtime.py /path/to/main-baseline /path/to/pr /tmp/607-runtime-results
pixi run --as-is mojo run -I . -I tests tests/test_renderer_callbacks.mojo
pixi run --as-is mojo run -I . -I tests tests/test_output_digest.mojo
```

Run correctness builds after the compile measurements so they do not
compete for resources. `pixi run test` runs the full suite, including the
new permanent tests. The cold-compile harness requires Linux utilities
`lscpu` and GNU `/usr/bin/time`; the Mojo regression tests also run in the
macOS CI job.

## Earlier experiment

The original two-backend evaluation and its raw data are preserved in
commit `fa6b42e`, under this same directory. It measured the original
compile savings, byte-identical raster/SVG output, and a small SVG-hexbin
runtime cost. Its diagnostic disabled hexbin's unused raster callback;
that diagnostic does not model the current PDF callback. Check out that
commit to reproduce those historical results.
