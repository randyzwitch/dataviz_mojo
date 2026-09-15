from dataviz import hexbin, render, render_svg


def main() raises:
    var x: List[Float64] = [0, 1, 2]
    var y: List[Float64] = [1, 3, 2]
    var p = hexbin(x, y).size(400, 300)
    var s = render_svg(p)
    print(s.to_string().byte_length())
