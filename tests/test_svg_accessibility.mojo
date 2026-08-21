"""Tests for accessible_svg_string()/write_accessible_svg(): the
role="img"/aria-label root attributes, the <title>/<desc> leading
child elements (and <desc>'s own omission when description is empty),
XML-escaping of special characters in both, and that the chart's own
already-rendered body is preserved unchanged underneath the new markup.
"""

from std.testing import assert_equal, assert_true, TestSuite

from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg, accessible_svg_string


def test_accessible_svg_string_adds_role_and_aria_label_to_root_element() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals)
    var svg = SvgCanvas(400, 300)
    render_svg(svg, plot)
    var s = accessible_svg_string(svg, "Widget Sales")
    assert_true(
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" viewBox="0 0 400 300"'
        ' role="img" aria-label="Widget Sales">' in s,
        "the root element gains role=\"img\" and aria-label, its own original attributes untouched",
    )


def test_accessible_svg_string_adds_title_and_desc_as_leading_children() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals)
    var svg = SvgCanvas(400, 300)
    render_svg(svg, plot)
    var s = accessible_svg_string(svg, "Widget Sales", "A bar chart of widget sales by category.")
    var title_idx = s.find("<title>Widget Sales</title>")
    var desc_idx = s.find("<desc>A bar chart of widget sales by category.</desc>")
    var first_rect_idx = s.find("<rect")
    assert_true(title_idx != -1, "the <title> element is present")
    assert_true(desc_idx != -1, "the <desc> element is present")
    assert_true(
        title_idx < desc_idx < first_rect_idx,
        "both come before the chart's own first drawn element, not scattered elsewhere",
    )


def test_accessible_svg_string_omits_desc_when_description_is_empty() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals)
    var svg = SvgCanvas(400, 300)
    render_svg(svg, plot)
    var s = accessible_svg_string(svg, "Widget Sales")
    assert_true("<desc>" not in s, "no description was given, so no <desc> element draws at all")


def test_accessible_svg_string_escapes_special_characters() raises:
    # Both the attribute (aria-label) and text-content (<title>)
    # contexts have different escaping rules -- '"' must escape inside
    # a double-quoted attribute but not inside element text, confirmed
    # against a real accessible_svg_string() run first.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals)
    var svg = SvgCanvas(400, 300)
    render_svg(svg, plot)
    var s = accessible_svg_string(svg, 'Sales & "Returns" <2024>')
    assert_true(
        'aria-label="Sales &amp; &quot;Returns&quot; &lt;2024>"' in s,
        "the attribute value escapes &, \", and < (the delimiter itself never needs escaping)",
    )
    assert_true(
        '<title>Sales &amp; "Returns" &lt;2024&gt;</title>' in s,
        "the element text escapes &, <, and > but not \" (a different context, different rules)",
    )


def test_accessible_svg_string_preserves_the_chart_body_unchanged() raises:
    # The actual chart markup underneath the new accessibility wrapper
    # must be byte-for-byte what render_svg() itself produced -- this
    # function only ever adds markup around it, never touches it.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals)
    var svg = SvgCanvas(400, 300)
    render_svg(svg, plot)
    var original = svg.to_string()
    var accessible = accessible_svg_string(svg, "Widget Sales")
    # Every line of the original body (everything after its own first
    # ">") still appears, unmodified, inside the accessible version.
    var body_start = original.find(">") + 1
    var body = String(original[byte=body_start:])
    assert_true(body in accessible, "the original chart body survives completely unchanged")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
