# title: Multi-Format Export
"""Write the same Plot to SVG, PNG, and BMP -- save() picks the format
from each path's own extension.
"""
from dataviz_mojo import scatter
from dataviz_mojo.plot import save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var c = scatter(x, y)
    # save() picks the format from each path's own extension --
    # one Plot, three real output files, no separate export step
    # per format.
    save(c, "docs/src/examples/out_export_formats.svg")
    save(c, "docs/src/examples/out_export_formats.png")
    save(c, "docs/src/examples/out_export_formats.bmp")
