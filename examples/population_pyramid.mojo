"""Demo: a population pyramid -- Mark.POPULATION_PYRAMID, two mirrored
horizontal bars per category (age band) growing outward from a shared,
always-centered zero baseline (Plot.encode_population_pyramid(), a
category plus two magnitudes -- see that method's docstring). Mark.
GANTT's horizontal categorical axis frame, reused unchanged; only
the bars themselves differ. Built via dataviz_mojo.population_pyramid()
-- see examples/scatter.mojo's docstring for what that trades away.

Age-band population counts by sex (male on the left, female on the
right -- the classic use of this chart, though the mark itself is
generic to any two magnitudes worth comparing side by side per
category; see population_pyramid.mojo's docstring).

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import population_pyramid
from dataviz_mojo.theme import Theme


def main() raises:
    var age_bands: List[String] = ["0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70+"]
    var male: List[Float64] = [12.0, 13.0, 14.0, 12.5, 10.0, 8.5, 6.0, 4.0]
    var female: List[Float64] = [11.5, 12.5, 13.5, 12.0, 10.5, 9.0, 7.0, 5.5]

    var c = population_pyramid(age_bands, male, female, left_name="Male", right_name="Female")
    write_bmp(c, "examples/out_population_pyramid.bmp")
    write_png(c, "examples/out_population_pyramid.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=age_bands, left_values=male, right_values=female, left_name="Male", right_name="Female"
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_population_pyramid.svg")

    print("wrote examples/out_population_pyramid.bmp, .png, and .svg")
