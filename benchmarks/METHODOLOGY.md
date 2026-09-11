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

## Recorded measurements

### `Mark.IMSHOW` on the SVG backend: rects vs one `<image>` (2026-09-10)

AMD Threadripper 3970X, Linux, Mojo 1.0.0, canvas_mojo v0.30.0, 640x420,
default theme, `sin(c/9)*cos(r/7)` field, median of 5 renders. "Rects" is
one `fill_rect` per run of same-colored cells; "image" is one `draw_image`
of the cells, decimated to the plot rect when the grid is finer than it.

| grid      | cells     | rects SVG ms | rects SVG bytes | image SVG ms | image SVG bytes |
| --------- | --------- | ------------ | --------------- | ------------ | --------------- |
| 3x3       | 9         | 1.02         | 3,449           | 1.06         | 3,158           |
| 9x9       | 81        | 1.06         | 9,128           | 1.12         | 4,677           |
| 23x23     | 529       | 1.21         | 34,635          | 1.21         | 5,304           |
| 32x32     | 1,024     | 1.37         | 63,742          | –            | –               |
| 64x64     | 4,096     | 2.31         | 230,960         | 1.82         | 8,810           |
| 100x100   | 10,000    | 4.15         | 558,692         | 2.86         | 14,905          |
| 256x256   | 65,536    | 21.8         | 3,668,700       | 14.6         | 75,318          |
| 512x512   | 262,144   | 58.4         | 8,568,631       | 36.5         | 226,758         |
| 1024x1024 | 1,048,576 | 55.0         | 8,751,323       | 31.1         | 211,636         |

The image is smaller at every size; time is the same below about 65,000
cells. The rect path is kept below 1,024 cells only because each cell is
then an inspectable element. Without decimation the 1024x1024 image took
217 ms and 1.1 MB, the cost of encoding a megapixel PNG for a 430x350
rect.

On the raster backend the image path was measured slower (7.4 ms against
4.6 ms for a 3x3 grid, 22.8 against 13.8 for 1024x1024) and, under
supersampling, lands interior cell edges between logical pixels where the
rect path keeps them hard. The raster backend keeps the rect path.

### `Mark.IMSHOW` raster supersample 3 vs 1 (2026-09-10)

AMD Threadripper 3970X, Linux, Mojo 1.0.0, canvas_mojo v0.29.0, 800x600,
default theme except the factor, `sin(c/9)*cos(r/7)` field, median of 9
`render()` calls. `AUTO` resolved to 3 for `IMSHOW` and `PCOLORMESH` before
#507 and resolves to 1 after; the cells are identical either way.

| grid    | factor 3 | factor 1 |
| ------- | -------- | -------- |
| 8x8     | 8.4 ms   | 1.4 ms   |
| 64x64   | 12.7 ms  | 1.6 ms   |
| 512x512 | 17.7 ms  | 10.5 ms  |

### Supersampled region against the two-step recipe (2026-09-11)

> **These numbers are withdrawn.** They were taken while another session was
> benchmarking on the same machine (load average 3.8, a `mojo` process at
> 295% CPU), which this document's own guidance forbids. Re-running the
> scatter rows on the contended machine swung the same row from 1.005x to
> 0.749x between passes. Treat everything below as unmeasured until it is
> retaken on an idle machine.

AMD Threadripper 3970X, Linux, Mojo 1.0.0, canvas_mojo v0.33.2, 800x600,
default theme, median of 9 renders, both paths interleaved in one process.
Byte-identity checked first on every row: a speedup on different pixels is
not a speedup.

| mark | factor | two-step ms | region ms | speedup |
| --- | --- | --- | --- | --- |
| pie | 3 | 9.22 | 3.95 | **2.33x** |
| contourf | 3 | 13.51 | 7.90 | **1.71x** |
| scatter | 3 | 7.59 | 7.55 | 1.005x |
| line | 1 | 1.88 | 1.76 | 1.06x |
| bar | 1 | 1.77 | 1.73 | 1.02x |

Factor-1 marks have no enlarged buffer to avoid, so their ~1.0x is the
expected result rather than a disappointment.

Scatter is the interesting row. Anything a region cannot record forces it
to materialize the enlarged buffer and fall back to two-step cost, and
`fill_circles_aa` -- the bulk marker call a plain scatter uses -- is one of
those. Holding the scene fixed and varying the two candidates:

| plot-rect clip | bulk marker call | speedup |
| --- | --- | --- |
| on | on | 1.005x |
| on | off (per-marker `fill_circle_aa`) | **1.97x** |
| off | on | 1.03x |

So the bulk call alone accounts for it; the clip is not implicated.

The conclusion drawn from that -- that scatter would gain ~2x if
`fill_circles_aa` became recordable -- **does not follow, and is wrong**.
Turning the bulk call off changes *both* sides of the comparison: the
two-step baseline then also draws markers one at a time, which is far
slower, so the ratio flatters the region rather than measuring the
primitive. canvas_mojo built the recordable form and measured it slower
than materializing, because replaying one op per marker across every band
costs more than the buffer it avoids (canvas_mojo#414).

An earlier entry-free measurement of the two phases in isolation put
scatter's ceiling at 52% of its render. That ceiling was real but not
reachable, because measuring the phases alone cannot show which primitive
will force materialization.
