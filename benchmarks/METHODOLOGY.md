# Benchmarking dataviz_mojo

Run the benchmark suite with:

```bash
pixi run bench
pixi run bench --check  # also flag likely quadratic scaling
```

Each case measures one `render()` or `render_svg()` call at 800×600 after an
untimed warm-up. File encoding and disk writes are excluded.

For comparisons:

- Use an otherwise idle machine.
- Run each configuration at least three times in interleaved order.
- Report the median and spread, not a single run.
- Use detached worktrees for historical commits so another session cannot move
  the checkout during a run.
- Give each worktree its own Pixi environment so dependency versions stay tied
  to the commit being measured.
- Record the operating system, processor, Mojo version, dependency versions,
  chart size, theme, and benchmark command.

Small timing differences are often noise. Compare scaling across input sizes as
well as absolute time, and avoid publishing machine-specific measurements in API
docstrings.
