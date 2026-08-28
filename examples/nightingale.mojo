"""Demo: a rose/coxcomb chart -- Mark.NIGHTINGALE, one wedge per
category (Plot.encode_categorical(), the same category + value shape
pie()/bar() use), every wedge the same angular width, magnitude
encoded by radius instead of angle (see nightingale.mojo's _render_nightingale docstring). Built via dataviz_mojo.nightingale()
-- see examples/scatter.mojo's docstring for what that trades away.

Causes of mortality in the Crimean War -- the chart type's best-known historical example (Florence Nightingale's original 1858
"Diagram of the Causes of Mortality"), using rose_type="area" (the
mode her original diagram effectively used) so each cause's wedge
*area*, not just its radius, is proportional to its death toll.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import nightingale
from dataviz_mojo.theme import Theme


def main() raises:
    var causes: List[String] = ["Zymotic disease", "Wounds", "Other"]
    var deaths: List[Float64] = [1857.0, 202.0, 97.0]

    var c = nightingale(causes, deaths, area=True)
    write_bmp(c, "examples/out_nightingale.bmp")
    write_png(c, "examples/out_nightingale.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_nightingale(area=True).encode_categorical(x=causes, y=deaths).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_nightingale.svg")

    print("wrote examples/out_nightingale.bmp, .png, and .svg")
