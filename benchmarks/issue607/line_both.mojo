from dataviz import line, render, render_svg


def main() raises:
    var x: List[Float64] = [0, 1, 2]
    var y: List[Float64] = [1, 3, 2]
    var p = line(x, y).size(400, 300)
    var c = render(p)
    var s = render_svg(p)
    print(c.width, s.to_string().byte_length())
