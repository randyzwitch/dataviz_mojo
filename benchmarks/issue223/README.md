# One payload field on Plot (#223, option 2)

The measurement behind the `proto/mark-data-variant-223` prototype, in
which `Plot`'s 36 per-mark payload fields become one `Variant`. The
numbers and their reading are in `benchmarks/METHODOLOGY.md` under
"Plot's 36 payload fields as one Variant".

- `measure.py`: the #607 cold-compile harness with its tree guards
  changed (`BASELINE PROTOTYPE RESULTS`; each tree needs its own locked
  Pixi environment). Builds the six programs in `../issue607/`.
- `measure_runtime.py` and `runtime.mojo`: render-time samples for line,
  hexbin, scatter3d and heatmap, three alternating processes per tree.
- `plot_size.mojo`: `size_of[Plot]()` and the cost of copying a plot,
  run once per tree with `mojo run -I <tree> plot_size.mojo`.
- `results/`: every sample from the compile and runtime runs, with the
  commits, compiler version and host in `metadata.json`.
