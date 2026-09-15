from dataviz import hexbin, render_pdf


def main() raises:
    var x: List[Float64] = [0, 1, 2]
    var y: List[Float64] = [1, 3, 2]
    var p = hexbin(x, y).size(400, 300)
    var doc = render_pdf(p)
    var data = doc.to_bytes()
    var digest: UInt64 = 14695981039346656037
    for b in data:
        digest = (digest ^ UInt64(b)) * 1099511628211
    print(len(data), digest)
