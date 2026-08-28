"""Demo: a rose/coxcomb chart -- Mark.NIGHTINGALE, one wedge per
category (Plot.encode_categorical(), the same category + value shape
pie()/bar() use), every wedge the same angular width, magnitude
encoded by radius instead of angle (see nightingale.mojo's _render_nightingale docstring). Built via dataviz_mojo.nightingale()
-- see examples/scatter.mojo's docstring for what that trades away.

Causes of mortality in the Crimean War -- the chart type's best-known historical example (Florence Nightingale's original 1858
"Diagram of the Causes of Mortality"), using rose_type="area" (the
mode her original diagram effectively used) so each cause's wedge
*area*, not just its radius, is proportional to its death toll.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import nightingale
from dataviz_mojo.theme import Theme


def main() raises:
    var causes: List[String] = ["Zymotic disease", "Wounds", "Other"]
    var deaths: List[Float64] = [1857.0, 202.0, 97.0]

    var c = nightingale(causes, deaths, area=True)
    save(c, "examples/out_nightingale.svg")
    save(c, "examples/out_nightingale.bmp")
    save(c, "examples/out_nightingale.png")
