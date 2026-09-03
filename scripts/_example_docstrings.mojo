"""Shared by `gen_example_docs.mojo` and `extract_docstring_examples.mojo`:
the master list of which function's docstring backs each docs page
(`_pages()`) and the extraction primitives both need
(`_quickplot_hook()`, `_extract_args_lines()`,
`_extract_example_blocks()`). Its own module with no `main()` so both
scripts can import it; callers pass `-I scripts` alongside `-I .`
(see pixi.toml's docs-build/example tasks).

Every example page's content (hook, runnable snippet, `Args:`
reference) comes from exactly one function's docstring in
`dataviz/*.mojo`. The `Example:` section (a peer of `Args:`/
`Returns:`) is the shown snippet verbatim: a complete standalone
program with real imports, `def main() raises:`, and a real `save()`
call.

`_pages()` has one entry per docs page naming the backing function
(`file`/`fn_name`/`is_method`) and, for a page that wants only one of
a function's several `Example:` blocks (`slope` wants `line()`'s
"Slope Chart" variant), which block by heading. Adding an example:
add the function's `Example:` section, then add it to `_pages()`,
`_titles()`, and exactly one category in `_categories()`
(gen_example_docs.mojo).
"""

from std.collections import Dict


struct ExamplePage(Copyable, Movable):
    """One docs page's source: `fn_name` (a `Plot` method when `is_method`,
    else a free function) in `dataviz/<file>.mojo`. `block` is `""` to
    show every `Example:` block the function has (one page section per
    block), or a heading to pick exactly one.
    """
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
        # Cookbook pages used to be listed here too; all migrated to
        # docs/src/cookbook_recipes/ (see its README.md), which needs no entry
        # here. A docstring-sourced Cookbook page is still possible via
        # gen_example_docs.mojo's _cookbook().
    ]


def _hook_overrides() -> Dict[String, String]:
    """Page-level hooks that shouldn't come from the backing function's
    docstring. `slope` calls the general-purpose `line()` but reads as
    its own chart type.
    """
    var d = Dict[String, String]()
    d["slope"] = "A slope chart."
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
    """The line index of `fn_name`'s `def` line at exactly `want_indent`
    leading spaces (0 for a free function, 4 for a `Plot` method), which
    disambiguates a file with the same name at different nesting. A plain
    `startswith` on the indented prefix already rejects deeper indents.
    """
    var prefix = " " * want_indent + "def " + fn_name + "("
    for i in range(len(lines)):
        if lines[i].startswith(prefix):
            return i
    raise Error("gen_example_docs: no `def " + fn_name + "(` at indent " + String(want_indent) + " found")


def _lines_of(file: String) raises -> List[String]:
    """dataviz/<file>.mojo's lines as owned `String`s: `String.split()`
    returns spans tied to the source string, which don't survive being
    passed across a function boundary.
    """
    var raw = _read_file("dataviz/" + file + ".mojo").split("\n")
    var lines = List[String](capacity=len(raw))
    for l in raw:
        lines.append(String(l))
    return lines^


def _quickplot_hook(fn_name: String, file: String, is_method: Bool) raises -> String:
    """The one-line hook shown at the top of a docs page: `fn_name`'s
    docstring's first sentence (`_extract_docstring()`/
    `_first_sentence()`).
    """
    var lines = _lines_of(file)
    var want_indent = 4 if is_method else 0
    var def_idx = _def_index(lines, fn_name, want_indent)
    var from_def = String("\n").join(lines[def_idx:])
    return _first_sentence(_extract_docstring(from_def))


def _extract_args_lines(fn_name: String, file: String, is_method: Bool) raises -> List[String]:
    """The `Args:` section's bullet lines from `fn_name`'s docstring in
    dataviz/<file>.mojo, as markdown; `[]` if there is no `Args:`
    section. Relies on the consistent indent every docstring uses
    relative to its `def` (8 spaces for a bullet, 12 for a continuation,
    one level deeper for a method). Type annotations are not included.
    """
    var lines = _lines_of(file)
    var want_indent = 4 if is_method else 0
    var def_idx = _def_index(lines, fn_name, want_indent)
    var bullet_indent = want_indent + 8

    # Bounded to this function's own docstring (its closing line at the
    # docstring's base indent); scanning further would find the next
    # function's Args: for a function without one.
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
    """Every `Example:`/`Example (<heading>):` section's fenced ` ```mojo `
    block from `fn_name`'s docstring, each a complete program shown and
    run as-is. Same indent convention as `_extract_args_lines()`: the
    fence and its code sit one level deeper than the `Example:` line,
    which sits at the docstring's base indent (4 for a free function, 8
    for a method).
    """
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
    """The bare filename (e.g. "out_bar.svg") this block's `save()`/
    `write_accessible_svg()` call writes into docs/src/examples/, parsed
    from the code's own path argument so the page's image reference
    always matches what the code writes.
    """
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
