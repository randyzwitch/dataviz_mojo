"""Export exact outputs for cross-tree comparison and exercise Plot ownership."""
from std.sys import argv
from std.testing import assert_equal
from canvas.buffer import Canvas
from canvas.vector.svg import SvgCanvas
from dataviz import Plot, line, hexbin, render, render_svg, save
from dataviz import (
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
)
from dataviz.core.mark import Mark
from _mark_registry import _representative_plot


def write_pair(prefix: String, canvas: Canvas, svg: SvgCanvas) raises:
    save(canvas, prefix + ".bmp")
    var f = open(prefix + ".svg", "w")
    f.write(svg.to_string())
    f.close()


def main() raises:
    var outdir = argv()[1]
    var plots = List[Plot]()
    for value in range(Mark.COUNT):
        var original = _representative_plot(Mark(value))
        var copied = original.copy()
        assert_equal(
            render_svg(original).to_string(), render_svg(copied).to_string()
        )
        plots.append(copied^)
    var copied_list = plots.copy()
    for value in range(Mark.COUNT):
        write_pair(
            outdir + "/" + String(value),
            render(copied_list[value]),
            render_svg(copied_list[value]),
        )
    write_pair(
        outdir + "/facets",
        render_facets(copied_list, cols=8),
        render_facets_svg(copied_list, cols=8),
    )

    var x: List[Float64] = [0, 1, 2]
    var y: List[Float64] = [1, 3, 2]
    var original_line = line(x, y).size(400, 300)
    var original_hex = hexbin(x, y).size(400, 300)
    var switched_line = original_hex.copy().mark_line().encode(x=x, y=y)
    var switched_hex = original_line.copy().mark_hexbin().encode_hexbin(x, y)
    assert_equal(
        render_svg(original_line).to_string(),
        render_svg(switched_line).to_string(),
    )
    assert_equal(
        render_svg(original_hex).to_string(),
        render_svg(switched_hex).to_string(),
    )
    write_pair(
        outdir + "/switched_line",
        render(switched_line),
        render_svg(switched_line),
    )
    write_pair(
        outdir + "/switched_hex", render(switched_hex), render_svg(switched_hex)
    )
    var layers = List[Plot]()
    layers.append(original_line.copy())
    layers.append(original_line.copy().mark_point())
    write_pair(
        outdir + "/layers", render_layers(layers), render_layers_svg(layers)
    )
    print(
        "Verified copies and moves for",
        Mark.COUNT,
        "marks; exported both backends, facets, layers, and mark switches",
    )
