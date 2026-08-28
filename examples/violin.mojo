"""Demo: a violin plot -- Mark.VIOLIN, a symmetric kernel-density-
estimate silhouette per category (Plot.encode_distribution(), the same
category-plus-raw-values shape beeswarm()/ridgeline() take -- see
violin.mojo's docstring for the bandwidth/sampling/width-scaling
rules). Reuses the same vertical categorical axis frame Mark.BOX/
BEESWARM do. Built via dataviz_mojo.violin() -- see examples/scatter.
mojo's docstring for what that trades away.

Exam scores by class -- the same data examples/beeswarm.mojo uses, so
the two are directly comparable: a violin shows the smoothed shape of
each distribution, beeswarm shows every individual point.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import violin
from dataviz_mojo.theme import Theme


def main() raises:
    var classes: List[String] = ["Section A", "Section B", "Section C"]
    var scores: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0, 74.0, 76.0, 91.0],
        [65.0, 70.0, 72.0, 88.0, 90.0, 92.0, 95.0],
        [80.0, 82.0, 83.0, 84.0, 81.0, 79.0, 85.0],
    ]

    var c = violin(classes, scores)
    save(c, "examples/out_violin.svg")
    save(c, "examples/out_violin.bmp")
    save(c, "examples/out_violin.png")
