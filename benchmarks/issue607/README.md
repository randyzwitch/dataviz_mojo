# Issue #607: family renderer callback prototype

This worktree evaluates replacing `_render_generic`'s ten runtime family
probes with a callback selected when a mark is constructed. Baseline:
`059a676` (the starting checkout; neither checkout is switched during runs).

## Implementation

`Plot` carries two noncapturing (`thin`) function pointers, specialized for
`Canvas` and `SvgCanvas`. Each `mark_*()` method binds its family, so both
quickplot constructors and the fluent builder use the same mechanism.
Changing a mark rebinds both pointers. The default plot and continuous
marks bind a no-op callback and continue into the existing continuous path.

Each family supplies a positional adapter around its existing dispatcher.
The shared validation and continuous rendering code stay in place. The
backend is selected at compile time before invoking its stored callback.
The existing import cycles compile with this implementation.

This is deliberately a dispatch experiment, not a complete decoupling of
`Plot`: the payload fields, family imports in the builder, layer domain
switches, and within-family dispatch all remain. The internal generic
renderer now supports the two concrete public backends; it no longer offers
an arbitrary `DrawTarget` extension point. A public API using a third
backend would require extending the callback mechanism.

The plain `def(Int) -> Int` field type is rejected by Mojo 1.0 as a trait;
`def(Int) thin -> Int` is the concrete pointer type. `callback_probe.mojo`
is the minimal copy/move/List reproduction that runs successfully.

## Reproduce

Create two worktrees at the baseline commit, apply this prototype to one,
and run `pixi install --locked` separately in each. Then, from the prototype:

```bash
python3 benchmarks/issue607/measure.py /path/to/baseline /path/to/prototype /tmp/607-compile-results
python3 benchmarks/issue607/validate.py /path/to/baseline /path/to/prototype /tmp/607-validation-results
```

Run the scripts sequentially so correctness builds do not compete with
compile measurements. `measure.py` performs three alternating cold builds
per case and tree. It removes only each worktree's private Mojo cache,
checks source/lockfile hashes before every build, fails on compiler errors,
and records wall time, CPU time, peak memory, binary size, and stdout.
The four cases are line and hexbin, each with SVG alone and both backends.
Their stdout checks are only smoke checks; `validate.py` supplies the full
output comparison.

`validate.py` exports all 62 representative marks on both backends after
copying each plot, moving it into a heterogeneous list, and copying the
list. It also exports mixed facets, line/point layers, and changes from
hexbin to line and back. Every BMP and SVG file must match the baseline
byte for byte. It runs five existing test modules and takes 41 warmed
render samples per mark/backend, in three alternating process pairs.

## Cold compile results (2026-09-14)

Linux, AMD Ryzen Threadripper 3970X (32 cores / 64 threads), Mojo 1.0.0
(ed45d567), canvas_mojo 0.35.0, locked dependencies, default themes,
400 x 300 charts with three data points. The two installed canvas and
morrow precompiled packages were byte-identical. Builds ran serially;
observed machine load averages were approximately 2–3 on 64 logical CPUs.

Three builds per cell, with tree order alternated. Seconds are medians;
parentheses give the observed minimum–maximum. MB is decimal. Binary sizes
were identical across all three repetitions within each configuration.

| Program | Baseline wall s | Callback wall s | Wall reduction | Baseline CPU s | Callback CPU s | Binary MB, baseline → callback |
| --- | --- | --- | --- | --- | --- | --- |
| Line, raster + SVG | 56.18 (56.01–59.74) | 27.38 (26.80–31.10) | 51.3% | 145.60 | 81.45 | 3.725 → 1.614 |
| Line, SVG only | 38.52 (38.39–39.00) | 20.39 (20.02–20.39) | 47.1% | 103.49 | 62.83 | 2.218 → 1.031 |
| Hexbin, raster + SVG | 56.20 (56.08–56.22) | 27.50 (27.22–27.86) | 51.1% | 145.99 | 84.82 | 3.725 → 1.652 |
| Hexbin, SVG only | 38.61 (38.11–38.82) | 23.71 (23.50–23.79) | 38.6% | 102.13 | 72.96 | 2.218 → 1.303 |

The line case reproduces the issue's manually pruned renderer result:
roughly half the wall time and a 1.61 MB binary, while keeping the public
API and all families available. Hexbin demonstrates that the gain also
applies to an actual stored family renderer, not just the continuous
fallback. CPU reductions are 44.1%, 39.3%, 41.9%, and 28.6%, respectively.

These measurements do not establish a whole-suite speedup. Constructors
still instantiate their entire family, and callers using every family
retain that cost. Payload construction and shared infrastructure also
remain. Raw measurements and source hashes are in `results/`.

## Backend diagnostic

An SVG-only hexbin executable still contains raster drawing routines.
To establish the cause, `ablate_backend.py` copies the prototype's source
and changes exactly one binding: hexbin's raster callback becomes the
continuous no-op. The SVG callback is untouched. This diagnostic source
cannot render raster hexbin correctly and is not the proposed patch.

Three alternating cold builds per configuration, with complete SVG stdout
compared byte for byte. This diagnostic prints the full SVG rather than
its length, so its binary sizes differ slightly from the main table.

| Hexbin, SVG only | Wall s, median (range) | CPU s, median | Binary bytes |
| --- | --- | --- | --- |
| Both callbacks registered | 23.34 (23.29–24.00) | 71.91 | 1,302,336 |
| Only the SVG callback registered | 20.33 (20.19–20.33) | 61.89 | 1,049,520 |

The unused raster callback costs about **3.01 wall seconds, 10.02 CPU
seconds, and 252,816 bytes** in this diagnostic. Thus this approach solves
unused-family compilation while retaining some unused-backend compilation.
The two axes should not be described as fully independent once both
backend functions are bound during construction.

Reproduce this optional diagnostic between measurement and validation:

```bash
python3 benchmarks/issue607/ablate_backend.py /path/to/prototype /tmp/607-backend-results
```

## Correctness and runtime

**Exact output: 132 of 132 files match byte for byte.** This includes
all 62 marks on raster and SVG, a mixed-mark facet grid, line/point layers,
and changing a plot from hexbin to line and from line to hexbin. Every
mark also passed copy equality, move-into-list, and list-copy exercises.
SHA-256 hashes for all outputs are retained in `results/output_sha256.json`.

Runtime: 128 data points, constructor defaults (640 x 420), 41 warmed
renders per process and three alternating baseline/prototype process
pairs. Each entry below is the median of the three process medians; the
range covers those process medians, not the individual render samples.
Raw samples are in `results/runtime-*.txt`.

| Case | Baseline ms, median (range) | Callback ms, median (range) |
| --- | --- | --- |
| Line, raster | 1.666 (1.558–1.676) | 1.554 (1.545–1.589) |
| Line, SVG | 1.100 (1.084–1.114) | 1.083 (1.083–1.125) |
| Hexbin, raster | 4.905 (4.873–4.970) | 4.830 (4.724–5.090) |
| Hexbin, SVG | 1.339 (1.336–1.346) | 1.362 (1.348–1.374) |

SVG hexbin is about **1.7% slower** in these samples, with nonoverlapping
process-median ranges. Raster line is about 6.7% faster; the other two
cases have overlapping ranges. This is a small, two-mark runtime sample,
not evidence that every mark is runtime-neutral. The clear win is compile
time, with a small observed SVG hexbin runtime cost.

All **414 tests passed, with zero failures or skips**, across the five
selected existing modules:

- `test_output_digest`: 2 tests.
- `test_core_plot`: 109 tests.
- `test_layers_facets`: 88 tests.
- `test_marks_basic`: 185 tests.
- `test_binned`: 30 tests.

The full test suite was not run. `mojo precompile -I . dataviz` also
succeeded, and a separate consumer built from that precompiled package
(with no source directory on its import path) rendered hexbin on both
backends successfully.



## Assessment

The callback route is viable on Mojo 1.0.0 and merits a production change
for #607, with the small measured SVG hexbin runtime cost recorded. It provides the expected compile savings without replacing
`Plot` or changing the public constructor/render signatures. Existing
import cycles do not prevent compilation, and the concrete function
pointer type supports the existing `Copyable`/`Movable` model.

This is not a fix for #223. `Plot` still owns every payload, and the
builder still knows every family. It also does not finish backend
isolation. A production follow-up should preserve the tested ownership
and mark-switching behavior, document the binding invariant next to the
mark-adding checklist, and decide whether supporting additional draw
targets is a requirement before fixing the callback interface to two
concrete targets.

