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
