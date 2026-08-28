"""Demo: a shaded reference band -- Plot.annotate_area(), ECharts' markArea (a fixed (y0, y1) pair only, not its auto-computed-range
modes -- see that method's docstring). Draws a translucent filled band
across the full plot width, in Theme.annotation_area_color, with an
optional label near its top edge.

Response-time samples against an acceptable range -- Mark.LINE, drawn
after the band so its stroke stays on top; the band's real partial
opacity means the line still reads clearly through the shaded stretch
inside it, rather than that stretch being overwritten -- see
annotate_area()'s docstring for the full story.

Built by hand (not a one-call quickplot -- annotate_area() isn't
exposed on quickplot functions, the same deliberate scope cut
examples/annotate_line.mojo's docstring explains) via Plot() directly.
Writes all three formats from one `plot` via save() -- no
`canvas_mojo` import needed at all (see save()'s docstring); `save()`
never consumes `plot`, so the same value is reused for each call rather
than needing three near-identical `Plot()` chains.
"""

from dataviz_mojo.plot import Plot, save


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var latency: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0, 70.0, 63.0]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=latency)
        .labels(title="Response Time (ms)", subtitle="Against an acceptable range")
        .annotate_area(50.0, 60.0, label="acceptable range")
    )
    save(plot, "examples/out_annotate_area.svg")
    save(plot, "examples/out_annotate_area.bmp")
    save(plot, "examples/out_annotate_area.png")

