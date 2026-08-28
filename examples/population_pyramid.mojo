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
"""

from dataviz_mojo.plot import save
from dataviz_mojo import population_pyramid
from dataviz_mojo.theme import Theme


def main() raises:
    var age_bands: List[String] = ["0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70+"]
    var male: List[Float64] = [12.0, 13.0, 14.0, 12.5, 10.0, 8.5, 6.0, 4.0]
    var female: List[Float64] = [11.5, 12.5, 13.5, 12.0, 10.5, 9.0, 7.0, 5.5]

    var c = population_pyramid(age_bands, male, female, left_name="Male", right_name="Female")
    save(c, "examples/out_population_pyramid.svg")
    save(c, "examples/out_population_pyramid.bmp")
    save(c, "examples/out_population_pyramid.png")
