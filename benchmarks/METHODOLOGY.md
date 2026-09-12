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

AMD Threadripper 3970X, Linux, Mojo 1.0.0, canvas_mojo v0.33.2, 800x600,
default theme, median of 9 renders per pass, both paths interleaved in one
process. **Three passes on an idle machine**, reported as a range: an
earlier attempt at this table was taken while another session was
benchmarking, and re-running one row under that contention swung it from
1.005x to 0.749x. Byte-identity was checked on every row of every pass
before anything was timed.

| mark | factor | speedup, 3 passes |
| --- | --- | --- |
| pie | 3 | 2.36 - 2.60x |
| contourf | 3 | 1.79 - 1.89x |
| line | 1 | 1.06 - 1.10x |
| bar | 1 | 1.02 - 1.03x |
| scatter | 3 | **0.80 - 0.88x** |

Scatter is a regression, which is why `render()` keeps the two-step recipe
for plots that batch their markers (`_draws_bulk_markers`). `fill_circles_aa`
is one of the primitives a region cannot record, so a region containing one
materializes the enlarged buffer and pays for banding it never gets. Pie is
the mirror image and the best row here: an arc has no bulk entry point, so
every wedge records and replays per band.

The factor-1 rows are not the region earning anything. At factor 1
`begin_supersampled` returns immediately and `end_supersampled` does
nothing, so there is no region at all; the gain is skipping the scratch
allocation and the `downsample(c, 1)` full-canvas copy the two-step did
regardless.

Two wrong turns worth recording, since both looked like results.

A ceiling for scatter, taken by timing the allocate-and-clear and
downsample phases in isolation, read 52% of its render. Real, but
unreachable: timing the phases alone cannot show which primitive will force
materialization.

Disabling the bulk call and re-measuring then showed 1.97x, which looked
like the gain waiting behind a recordable `fill_circles_aa`. It is not.
Turning the bulk call off changes *both* sides of the comparison, since the
two-step baseline then also draws markers one at a time, so the ratio
flatters the region rather than measuring the primitive. canvas_mojo built
the recordable per-marker form on that suggestion and measured it slower
than materializing; canvas_mojo#414 now proposes recording the whole call
as a single op instead.
### Grouping Plot's data columns, compile-time effect (2026-09-11)

AMD Threadripper 3970X, Linux, Mojo 1.0.0, canvas_mojo v0.32.0. #522 warned
that grouping `Plot`'s eleven shared data columns into four structs touches
the monomorphization hot spot `pixi.toml` describes, so it should be
measured rather than assumed neutral.

A build target that pulls in `render()` and `render_svg()` for five marks,
forcing `_render_generic` to monomorphize over both `DrawTarget`
implementations. Three passes per side, alternating, same directory and
environment with only the checkout swapped.

| pass | main | branch |
| --- | --- | --- |
| 1 | 52.92 s | 53.33 s |
| 2 | 53.28 s | 52.06 s |
| 3 | 53.26 s | 51.76 s |

**No measurable difference.** The ranges overlap, and the produced binary
is 3,442,880 bytes on both sides in all six builds, which is the stronger
evidence: the same code is being generated, not merely generated in the
same time.

Two notes on method, because the first attempt measured nothing.

The cache must be cleared before each build. A warm build returns cached
artifacts in 9.1 seconds and, on the second and third passes, was identical
to three decimal places across both trees. That is a cache lookup being
timed, not a compile, and it would have read as "no difference" for the
wrong reason. The cache is `$MODULAR_HOME/cache/.mojo_cache`, inside the
worktree's own pixi environment.

The harness checks which tree is checked out before each timed build, by
grepping for a declaration that exists only on the branch, and refuses to
record a time if the build failed or produced no binary. A failed build is
fast, and a fast failure reads as a speedup.

### Deleting the bulk-marker gate, on canvas_mojo v0.33.3 (2026-09-12)

AMD Threadripper 3970X, Linux, Mojo 1.0.0, 800x600, default theme, median
of 9 renders per pass, three passes, **each side in its own process**.
Byte-identity asserted on every mark before anything was timed, with
timings withheld for any mismatch; none mismatched.

Separate processes on purpose. The two-step allocates a canvas `factor`
times larger every iteration and the region does not, so interleaving them
lets each side shape the allocator state the other sees. canvas_mojo
measured that inflating the same ratio from 1.20x to 1.41x.

Region against the two-step recipe it replaces:

| mark | factor | speedup, 3 passes |
| --- | --- | --- |
| scatter, 24 points | 3 | 1.91 - 1.95x |
| pie | 3 | 1.87 - 2.06x |
| contourf | 3 | 1.69 - 1.84x |
| scatter, 2000 points | 3 | 1.50 - 1.63x |
| line | 1 | 0.98 - 1.08x |
| bar | 1 | 1.00 - 1.06x |

**What actually changed for callers** is narrower than that table, because
every mark except scatter already took the region before this. Comparing
what `render()` did on v0.33.2 against what it does now, same harness, same
night:

| mark | v0.33.2 | v0.33.3 |
| --- | --- | --- |
| scatter, 24 points | 6.05 - 6.68 ms | 3.20 - 3.23 ms |
| scatter, 2000 points | 7.28 - 7.71 ms | 4.77 - 4.83 ms |
| pie | 3.26 - 3.46 ms | 3.44 - 3.53 ms |
| contourf | 6.47 - 7.55 ms | 7.03 - 7.12 ms |
| line | 1.59 - 1.67 ms | 1.60 - 1.70 ms |
| bar | 1.64 - 1.69 ms | 1.65 - 1.72 ms |

So a scatter got roughly twice as fast and nothing else moved measurably.

#### Two predictions of mine that were wrong

**I expected the end-to-end figure to come in below canvas_mojo's 1.20x**,
reasoning that their scene is markers under a clip with no axis frame,
ticks, labels or legend, so the fixed work a real chart does either way
would dilute the gain. It came in higher, 1.91x.

Density is part of it, tested rather than assumed: a 2000-point scatter
falls to 1.50 - 1.63x. With few markers the fixed
allocate-and-downsample cost dominates, so avoiding it wins by more; with
many, marker drawing dominates and the saving is proportionally smaller.
That is the right direction but does not close the gap to 1.20x, and the
remainder is not explained by anything measured here.

**A first look said pie had regressed on v0.33.3**, 3.255 ms against
3.44 - 3.53. That was one control sample against three. Three control
passes give 3.26 - 3.46 ms, which overlaps, and the regression
disappeared.

#### Why the earlier table is not comparable

The v0.33.2 entry above records pie at 2.36 - 2.60x where this one records
1.87 - 2.06x. That is not a change in the library. Both sides were slower
the night that table was taken (pie two-step 9.22 ms there against
6.6 - 7.2 ms here), so the machine was in a different state. Ratios from
different sessions should not be compared; only rows taken under one
harness on one night are.
