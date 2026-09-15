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

The comparison uses unmodified main at `5f29ae9` and the current
three-backend implementation, both with canvas_mojo 0.36.0 and Mojo 1.0.0.
The six small programs render line or hexbin using raster + SVG, SVG only,
or PDF only. Every chart is 400 x 300 with three data points and default
styling. PDF cases compare output length and a byte fingerprint.

Three cold builds per program and tree run in alternating order, with only
one build running at a time. The harness clears each tree's private Mojo
cache before every build, checks library/lockfile and benchmark hashes,
rejects failed builds, compares program stdout, and records wall time, CPU
time, peak memory, binary size, compiler versions, and source hashes.

Updated measurements are in progress; results will be recorded here before
this cleanup is published. The old two-backend figures are historical and
are not claims about the current implementation.

## Permanent validation

`tests/test_renderer_callbacks.mojo` exercises all enumerated marks through
copying, moving into a heterogeneous collection, and list copying on all
three backends. It also checks default construction, fluent changes between
families and back to continuous rendering, mixed facets, and mixed layers.
Comparisons use complete raster pixels, SVG strings, and PDF bytes.

Dendrogram now has a qualified name, is included in `Mark.COUNT`, and has a
representative fixture and committed raster/SVG digest. Its expected digest
was generated with the unmodified main renderer, not the callback branch.
The existing mark and composition digests otherwise remain unchanged.

## Reproduce

Create a detached worktree at `5f29ae9` and install its environment with
`pixi install --locked`. Install the PR's locked environment separately.
From the PR checkout, run:

```bash
python3 benchmarks/issue607/measure.py /path/to/main-baseline /path/to/pr /tmp/607-current-results
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
