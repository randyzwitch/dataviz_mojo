"""Shared source for `gen_example_docs.mojo` and `extract_docstring_
examples.mojo` -- the master list of which function's docstring backs
each docs page (`_pages()`), and the extraction primitives both
scripts need (`_quickplot_hook()`, `_extract_args_lines()`,
`_extract_example_blocks()`). Kept in its own module (not a *.mojo
file with its own `main()`) so both callers can import it -- the same
reason tests/_test_helpers.mojo isn't a real dataviz_mojo sub-package
either; a directory containing a file with `main()` can't be `mojo
package`d/`precompile`d. Callers need an extra `-I scripts` alongside
the usual `-I .` to resolve `from _example_docstrings import ...` --
see pixi.toml's own docs-build/example tasks.

Every example page's content -- the hook, the runnable snippet, and
the `Args:` reference -- comes from exactly one place: the backing
quickplot function's (or, for the handful with no quickplot function,
a `Plot` method's) own docstring in `dataviz_mojo/*.mojo`. There is no
separate `examples/*.mojo` file to keep in sync by hand any more: the
`Example:` section (a peer of `Args:`/`Returns:`) *is* the shown
snippet, verbatim -- a complete, standalone, runnable program (real
imports, `def main() raises:`, a real `save()` call), not a fragment
reconstructed from a bigger file.

`_pages()` is the master list: one entry per docs page, naming which
function's docstring backs it (`file`/`fn_name`/`is_method`), and, for
the rare case where a function's docstring holds more than one
`Example:` block but a page wants only one of them (`slope` wants only
`line()`'s "Slope Chart" variant, not its primary one), which block by
name. Adding a new example: add its function's own `Example:` section,
then add it to `_pages()`, `_titles()`, and exactly one category in
`_categories()` (gen_example_docs.mojo) -- that script's own `main()`
assertions catch a missing entry either way.
"""

from std.collections import Dict


struct ExamplePage(Copyable, Movable):
    """One docs page's own source: `fn_name` (`is_method`'s own struct
    method, or a free function) in `dataviz_mojo/<file>.mojo`. `block`
    is "" for the common case (show/run every `Example:` section that
    function's docstring has -- one page section per block, `bar()`/
    `pie()`'s own diverging-bars/donut variants included); non-empty
    picks out exactly one named block by its own heading (`slope`
    wants only `line()`'s "Slope Chart" variant, not its primary
    one)."""
    var name: String
    var file: String
    var fn_name: String
    var is_method: Bool
    var block: String

    def __init__(out self, name: String, file: String, fn_name: String, is_method: Bool = False, block: String = ""):
        self.name = name
        self.file = file
        self.fn_name = fn_name
        self.is_method = is_method
        self.block = block


def _pages() -> List[ExamplePage]:
    return [
        ExamplePage("scatter", "plot", "scatter"),
        ExamplePage("line", "plot", "line"),
        ExamplePage("slope", "plot", "line", block="Slope Chart"),
        ExamplePage("area", "plot", "area"),
        ExamplePage("bar", "bar", "bar"),
        ExamplePage("pie", "arc", "pie"),
        ExamplePage("lollipop", "lollipop", "lollipop"),
        ExamplePage("waterfall", "waterfall", "waterfall"),
        ExamplePage("box", "box", "box"),
        ExamplePage("candlestick", "candlestick", "candlestick"),
        ExamplePage("bullet", "bullet", "bullet"),
        ExamplePage("gantt", "gantt", "gantt"),
        ExamplePage("population_pyramid", "population_pyramid", "population_pyramid"),
        ExamplePage("heatmap", "heatmap", "heatmap"),
        ExamplePage("chord", "chord", "chord"),
        ExamplePage("single_axis", "single_axis", "single_axis"),
        ExamplePage("effect_scatter", "effect_scatter", "effect_scatter"),
        ExamplePage("funnel", "funnel", "funnel"),
        ExamplePage("bump", "bump", "bump"),
        ExamplePage("streamgraph", "streamgraph", "streamgraph"),
        ExamplePage("beeswarm", "beeswarm", "beeswarm"),
        ExamplePage("violin", "violin", "violin"),
        ExamplePage("ridgeline", "ridgeline", "ridgeline"),
        ExamplePage("nightingale", "nightingale", "nightingale"),
        ExamplePage("polarbar", "polar_bar", "polarbar"),
        ExamplePage("radialbar", "radialbar", "radialbar"),
        ExamplePage("polar", "polar", "polar"),
        ExamplePage("polar_series", "polar", "polar_series"),
        ExamplePage("radar", "radar", "radar"),
        ExamplePage("gauge", "gauge", "gauge"),
        ExamplePage("parallel", "parallel", "parallel"),
        ExamplePage("span_chart", "span_chart", "span_chart"),
        ExamplePage("calendar_heatmap", "calendar_heatmap", "calendar_heatmap"),
        ExamplePage("corrplot", "corrplot", "corrplot"),
        ExamplePage("punchcard", "punchcard", "punchcard"),
        ExamplePage("marimekko", "marimekko", "marimekko"),
        ExamplePage("sunburst", "sunburst", "sunburst"),
        ExamplePage("tree", "tree", "tree"),
        ExamplePage("treemap", "treemap", "treemap"),
        ExamplePage("arc_diagram", "arc_diagram", "arc_diagram"),
        ExamplePage("graph", "graph", "graph"),
        ExamplePage("sankey", "sankey", "sankey"),
        ExamplePage("histogram", "histogram", "histogram"),
        ExamplePage("grouped_bar", "grouped_bar", "grouped_bar"),
        ExamplePage("stacked_bar", "stacked_bar", "stacked_bar"),
        # The six with no quickplot function -- Plot methods (or, for
        # write_accessible_svg, a free function), all in plot.mojo.
        ExamplePage("annotate_area", "plot", "annotate_area", is_method=True),
        ExamplePage("annotate_line", "plot", "annotate_line", is_method=True),
        ExamplePage("annotate_vline", "plot", "annotate_vline", is_method=True),
        ExamplePage("annotate_point", "plot", "annotate_point", is_method=True),
        ExamplePage("dual_axis", "plot", "secondary_axis", is_method=True),
        ExamplePage("svg_accessibility", "plot", "write_accessible_svg"),
        ExamplePage("facets", "plot", "save_facets"),
        ExamplePage("log_scale_y", "plot", "scale_y_log", is_method=True),
        ExamplePage("log_scale_x", "plot", "scale_x_log", is_method=True),
    ]


def _hook_overrides() -> Dict[String, String]:
    """Page-level hooks that shouldn't come from their backing
    function's own docstring (`_build_page()`'s usual default) -- an
    explicit, hand-maintained exception list, the same shape `_titles()`/
    `_categories()` (gen_example_docs.mojo) already are. `slope` is the
    one entry: it calls the general-purpose `line()`, but reads as its
    own chart type, not a variant of "Line" -- line()'s own docstring
    has no reason to say "slope chart" anywhere in its main
    description. `facets` is the other: save_facets()'s own first
    sentence is comparative ("save()'s render_facets()/
    render_facets_svg() counterpart"), assuming a reader who already
    knows what render_facets() is -- fine inside plot.mojo read
    alongside it, not as a standalone page's opening line."""
    var d = Dict[String, String]()
    d["slope"] = "A slope chart."
    d["facets"] = "Lay out several independent Plots in an evenly sized grid."
    d["log_scale_x"] = "Scale the x-axis logarithmically (base 10) instead of linearly."
    return d^


def _read_file(path: String) raises -> String:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    return content


def _write_file(path: String, content: String) raises:
    var f = open(path, "w")
    f.write(content)
    f.close()


def _extract_docstring(source: String) -> String:
    var start = source.find('"""')
    if start == -1:
        return ""
    var content_start = start + 3
    var end = source.find('"""', content_start)
    if end == -1:
        return ""
    var raw = String(source[byte=content_start:end])
    return String(raw.strip())


def _first_sentence(docstring: String) -> String:
    # Collapse hand-wrapped newlines within the first paragraph into a
    # single flowing line, then cut at the first " -- " boundary (the
    # hook) if there is one, else keep the whole first sentence.
    var para_end = docstring.find("\n\n")
    var first_para = String(docstring[byte=0:para_end]) if para_end != -1 else docstring

    var words = List[String]()
    for line in first_para.split("\n"):
        var stripped = String(line.strip())
        if stripped:
            words.append(stripped)
    var flat = String(" ").join(words)

    var idx = flat.find(" -- ")
    var sentence = String(flat[byte=0:idx]) if idx != -1 else flat
    var trimmed = String(sentence.strip())
    sentence = trimmed
    if sentence.endswith("."):
        var without_dot = String(sentence[byte=0 : sentence.byte_length() - 1])
        sentence = without_dot
    sentence = sentence + "."

    var first_char = String(sentence[byte=0:1]).upper()
    return first_char + String(sentence[byte=1:])


def _def_index(lines: List[String], fn_name: String, want_indent: Int) raises -> Int:
    """The line index of `fn_name`'s own `def` line, at exactly
    `want_indent` leading spaces (0 for a free function, 4 for a `Plot`
    method) -- disambiguates a file with more than one `def <fn_name>(`
    at different nesting (plot.mojo has both a free `line()` and, at a
    different indent, unrelated methods that could share a short
    name). A line starting with more leading spaces than `want_indent`
    can't match this exact prefix either (its own character right at
    that position is still a space, not `d`), so a plain `startswith`
    already disambiguates both directions without per-character
    indexing."""
    var prefix = " " * want_indent + "def " + fn_name + "("
    for i in range(len(lines)):
        if lines[i].startswith(prefix):
            return i
    raise Error("gen_example_docs: no `def " + fn_name + "(` at indent " + String(want_indent) + " found")


def _lines_of(file: String) raises -> List[String]:
    """dataviz_mojo/<file>.mojo's own lines, as real `List[String]` --
    `String.split()` itself returns lifetime-bound `StringSpan`s tied
    to the source string's own storage, which doesn't survive being
    passed across a function boundary the way every caller here needs
    (`_def_index()` chief among them), so this copies each line into
    its own owned `String` once, right after reading."""
    var raw = _read_file("dataviz_mojo/" + file + ".mojo").split("\n")
    var lines = List[String](capacity=len(raw))
    for l in raw:
        lines.append(String(l))
    return lines^


def _quickplot_hook(fn_name: String, file: String, is_method: Bool) raises -> String:
    """The one-line "what is this chart" hook shown at the top of a
    docs page, pulled from `fn_name`'s own docstring in dataviz_mojo/
    <file>.mojo via `_extract_docstring()`/`_first_sentence()`."""
    var lines = _lines_of(file)
    var want_indent = 4 if is_method else 0
    var def_idx = _def_index(lines, fn_name, want_indent)
    var from_def = String("\n").join(lines[def_idx:])
    return _first_sentence(_extract_docstring(from_def))


def _extract_args_lines(fn_name: String, file: String, is_method: Bool) raises -> List[String]:
    """The `Args:` section's own bullet lines out of `fn_name`'s
    docstring in dataviz_mojo/<file>.mojo, formatted as markdown --
    `[]` if that function has no `Args:` section. Every docstring
    shares one consistent indent relative to its own `def` (8 spaces
    for a bullet's `name: description` line, 12 for a continuation,
    for a free function; 12/16 for a method, one level deeper) --
    confirmed across every quickplot function's own docstring, not
    assumed. Skips the type annotation entirely -- reliably parsing
    each argument's real type back out of the function's own
    multi-line signature (`Theme`'s own giant default-value literal,
    `List[Float64]`, ...) isn't worth it for what the snippet's own
    real usage, shown right above, already makes clear."""
    var lines = _lines_of(file)
    var want_indent = 4 if is_method else 0
    var def_idx = _def_index(lines, fn_name, want_indent)
    var bullet_indent = want_indent + 8

    # Bounded to this function's own docstring (its closing `"""` line,
    # at the docstring's own base indent) -- unbounded would happily
    # keep scanning into whatever function comes next in the file and
    # find *its* "Args:" instead, for any function with no Args:
    # section of its own (secondary_axis() takes no documented
    # parameters at all).
    var doc_indent_str = " " * (want_indent + 4)
    var doc_close = -1
    for i in range(def_idx + 1, len(lines)):
        if lines[i] == doc_indent_str + '"""':
            doc_close = i
            break
    if doc_close == -1:
        raise Error("gen_example_docs: no closing docstring line found for " + fn_name)

    var args_idx = -1
    var end_idx = -1
    for i in range(def_idx, doc_close):
        var stripped = lines[i].strip()
        if stripped == "Args:":
            args_idx = i
        elif args_idx != -1 and (stripped == "Returns:" or stripped == '"""'):
            end_idx = i
            break
    if args_idx == -1:
        return List[String]()
    if end_idx == -1:
        end_idx = doc_close

    var result = List[String]()
    for i in range(args_idx + 1, end_idx):
        var raw = lines[i]
        if raw.strip() == "":
            continue
        if raw.startswith(" " * bullet_indent) and not raw.startswith(" " * (bullet_indent + 1)):
            var colon = raw.find(": ")
            var arg_name = String(raw[byte=bullet_indent:colon])
            var desc = String(raw[byte = colon + 2 :])
            result.append("- `" + arg_name + "`: " + desc)
        else:
            result.append("  " + raw.strip())
    return result^


struct _ExampleBlock(Copyable, Movable):
    var heading: String  # "" for the default (first/unnamed) block
    var lines: List[String]  # the complete program's own real source lines

    def __init__(out self, heading: String, var lines: List[String]):
        self.heading = heading
        self.lines = lines^


def _extract_example_blocks(fn_name: String, file: String, is_method: Bool) raises -> List[_ExampleBlock]:
    """Every `Example:`/`Example (<heading>):` section's own fenced
    ` ```mojo ` block out of `fn_name`'s docstring, each already a
    complete, ready-to-embed program (the docstring text itself is
    exactly what's shown and exactly what `extract_docstring_examples.
    mojo` compiles and runs -- no cleanup step). Same 8-spaces-per-
    indent-level convention `_extract_args_lines()` already relies on:
    the fence and its code sit one level deeper than `Example:`'s own
    line, which sits at the docstring's own base indent (4 for a free
    function, 8 for a method)."""
    var lines = _lines_of(file)
    var want_indent = 4 if is_method else 0
    var def_idx = _def_index(lines, fn_name, want_indent)
    var doc_indent = want_indent + 4
    var doc_indent_str = " " * doc_indent
    var code_indent_str = doc_indent_str + "    "

    var close_idx = -1
    for i in range(def_idx + 1, len(lines)):
        if lines[i] == doc_indent_str + '"""':
            close_idx = i
            break
    if close_idx == -1:
        raise Error("gen_example_docs: no closing docstring line found for " + fn_name)

    var blocks = List[_ExampleBlock]()
    var i = def_idx + 1
    while i < close_idx:
        var line = lines[i]
        var is_default = line == doc_indent_str + "Example:"
        var is_named = line.startswith(doc_indent_str + "Example (") and line.endswith("):")
        if not (is_default or is_named):
            i += 1
            continue

        var heading = ""
        if is_named:
            var prefix_len = doc_indent_str.byte_length() + 9  # 9 == len("Example (")
            heading = String(line[byte=prefix_len : line.byte_length() - 2])

        i += 1
        if i >= close_idx or lines[i] != code_indent_str + "```mojo":
            raise Error("gen_example_docs: Example: in " + fn_name + " has no opening ```mojo fence")
        i += 1

        var code_lines = List[String]()
        var closed = False
        while i < close_idx:
            if lines[i] == code_indent_str + "```":
                closed = True
                i += 1
                break
            if lines[i].strip() == "":
                code_lines.append("")
            elif lines[i].startswith(code_indent_str):
                code_lines.append(String(lines[i][byte = code_indent_str.byte_length() :]))
            else:
                raise Error("gen_example_docs: Example: code line wrongly indented in " + fn_name + ": " + lines[i])
            i += 1
        if not closed:
            raise Error("gen_example_docs: Example: fence never closed for " + fn_name)
        blocks.append(_ExampleBlock(heading, code_lines^))

    if len(blocks) == 0:
        raise Error("gen_example_docs: no Example: section found for " + fn_name)
    return blocks^


def _output_svg_name(code_lines: List[String]) -> String:
    """The bare filename (e.g. "out_bar.svg") this block's own save()/
    write_accessible_svg() call writes into docs/src/examples/ --
    parsed straight out of the shown code's own path argument, not
    derived a second, independent way, so the image reference on the
    page always matches exactly what the code actually writes."""
    comptime marker = "docs/src/examples/"
    for line in code_lines:
        var idx = line.find(marker)
        if idx == -1:
            continue
        var after = String(line[byte = idx + 18 :])  # 18 == len("docs/src/examples/")
        var quote = after.find('"')
        if quote != -1:
            return String(after[byte=0:quote])
    return ""
