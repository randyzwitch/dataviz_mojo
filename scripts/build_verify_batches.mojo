"""`pixi run example`'s batching step: rewrites the standalone example
and Cookbook-recipe programs into a handful of batch drivers so
`mojo run` compiles them a handful of times instead of once per file.

`_render_generic[T: DrawTarget]` (dataviz/plot.mojo) names every
`_render_*` function, so a single `save()` call monomorphizes the
whole mark dispatch tree, roughly 50 CPU-seconds per process
regardless of which chart is drawn. See pixi.toml's `[tasks]` comment
for the measurements.

The standalone programs are left untouched:
`docs/cookbook_recipes/*.mojo` stays as contributed and
`docs/src/examples/*.mojo` as `extract_docstring_examples.mojo` wrote
it. The batches under `docs/src/examples/verify/` are a throwaway
build artifact read only by `mojo run`.

Each source program is an optional `# title:` comment, an optional
module docstring, imports, optionally some module-level declarations
(two recipes define a `struct`), then exactly one `def main()
raises:`. The transform unions the imports, hoists module-level
declarations as they are, renames each `main` to `_run_<stem>`, and
emits one `main()` per batch calling them in order. Every `save()`
keeps its original output path. Two hoisted declarations sharing a
name are a duplicate-declaration compile error naming both.

Several batches rather than one program so a failure names its batch
(and the `_run_<stem>` frame names the recipe) and CI cores stay
busy. `_BATCHES_PER_CORPUS` is the only knob.
"""

from std.os import listdir, makedirs, path

from _example_docstrings import _read_file, _write_file

comptime _EXAMPLES_DIR = "docs/src/examples"
comptime _RECIPES_DIR = "docs/cookbook_recipes"
comptime _OUT_DIR = "docs/src/examples/verify"
comptime _BATCHES_PER_CORPUS = 4


struct _Program(Movable):
    """One standalone source program, split into the pieces a batch
    driver needs."""

    var stem: String
    """The file's basename without `.mojo` -- becomes `_run_<stem>`."""
    var source_path: String
    """Where it came from, recorded as a comment in the batch."""
    var imports: List[String]
    var preamble: List[String]
    """Any module-level declarations before `main()`, hoisted verbatim
    (a `struct` and its methods, say) -- empty for all but two
    recipes."""
    var body: List[String]
    """`main()`'s own lines, indentation untouched, so they read as the
    body of the `_run_<stem>` this becomes."""

    def __init__(
        out self,
        stem: String,
        source_path: String,
        var imports: List[String],
        var preamble: List[String],
        var body: List[String],
    ):
        self.stem = stem
        self.source_path = source_path
        self.imports = imports^
        self.preamble = preamble^
        self.body = body^


def _parse(stem: String, source_path: String) raises -> _Program:
    """Split one source program into imports, hoistable preamble, and
    `main()`'s body. Raises if there is no `main()`.
    """
    var lines = _read_file(source_path).split("\n")
    var imports = List[String]()
    var preamble = List[String]()
    var body = List[String]()
    var seen_main = False
    var in_preamble = False
    var in_docstring = False

    for i in range(len(lines)):
        var line = lines[i]
        if seen_main:
            body.append(String(line))
            continue

        # Everything from the first module-level declaration up to
        # `main()` is hoisted as-is, blank lines and comments included:
        # a `struct`'s own methods are indented, so they can't be
        # classified line by line the way the header can.
        if in_preamble:
            if line.startswith("def main("):
                seen_main = True
                in_preamble = False
            else:
                preamble.append(String(line))
            continue

        if in_docstring:
            if line.find('"""') >= 0:
                in_docstring = False
            continue
        var stripped = String(line.strip())
        if stripped.startswith('"""'):
            # A one-line docstring opens and closes on the same line.
            if stripped.find('"""', 3) < 0:
                in_docstring = True
            continue
        if stripped == "" or stripped.startswith("#"):
            continue
        if line.startswith("from ") or line.startswith("import "):
            imports.append(String(line))
            continue
        if line.startswith("def main("):
            seen_main = True
            continue
        # Anything else at this point is a module-level declaration of
        # the program's own -- hoist it and everything after it.
        in_preamble = True
        preamble.append(String(line))

    if not seen_main:
        raise Error(
            "build_verify_batches: " + source_path + " has no `def main(`"
        )
    return _Program(stem, source_path, imports^, preamble^, body^)


def _collect(dir: String) raises -> List[_Program]:
    """Every `*.mojo` directly in `dir`, parsed, in sorted order so batch
    membership is stable run to run; non-recursive so
    `docs/src/examples/quickstart/` and `verify/` are left alone.
    """
    var entries = listdir(dir)
    sort(entries)
    var out = List[_Program]()
    for e in entries:
        if not e.endswith(".mojo"):
            continue
        var full = dir + "/" + e
        if path.isdir(full):
            continue
        out.append(_parse(String(e[byte = 0 : e.byte_length() - 5]), full))
    return out^


def _emit(label: String, programs: List[_Program], batches: Int) raises -> Int:
    """Write `programs` out as at most `batches` driver files, returning how
    many were written. Members are strided (`range(b, n, batches)`)
    rather than chunked, so neighbouring names from the same mark family
    spread across batches.
    """
    var written = 0
    for b in range(batches):
        var members = List[Int]()
        for i in range(b, len(programs), batches):
            members.append(i)
        if len(members) == 0:
            continue

        var seen_imports = List[String]()
        var out = List[String]()
        out.append(
            '"""Generated by scripts/build_verify_batches.mojo -- do not edit.'
        )
        out.append("")
        out.append(
            "Compile-and-run verification for "
            + String(len(members))
            + " standalone"
        )
        out.append(
            "programs, batched into one process. The files named below are the"
        )
        out.append(
            "real sources; see that script's docstring for why this exists."
        )
        out.append('"""')
        out.append("")
        for m in members:
            for k in range(len(programs[m].imports)):
                var imp = programs[m].imports[k]
                var already = False
                for s in seen_imports:
                    if s == imp:
                        already = True
                        break
                if not already:
                    seen_imports.append(imp)
                    out.append(imp)
        for m in members:
            if len(programs[m].preamble) == 0:
                continue
            out.append("")
            out.append("")
            out.append("# hoisted from " + programs[m].source_path)
            for k in range(len(programs[m].preamble)):
                out.append(programs[m].preamble[k])
        for m in members:
            out.append("")
            out.append("")
            out.append("# from " + programs[m].source_path)
            out.append("def _run_" + programs[m].stem + "() raises:")
            for k in range(len(programs[m].body)):
                out.append(programs[m].body[k])
        out.append("")
        out.append("def main() raises:")
        for m in members:
            out.append("    _run_" + programs[m].stem + "()")
        out.append("")

        _write_file(
            _OUT_DIR + "/" + label + "_" + String(b) + ".mojo",
            String("\n").join(out),
        )
        written += 1
    return written


def main() raises:
    makedirs(_OUT_DIR, exist_ok=True)

    var examples = _collect(_EXAMPLES_DIR)
    var recipes = _collect(_RECIPES_DIR)

    var n_ex = _emit("examples", examples, _BATCHES_PER_CORPUS)
    var n_re = _emit("recipes", recipes, _BATCHES_PER_CORPUS)

    print(
        "Batched",
        len(examples),
        "examples +",
        len(recipes),
        "recipes ->",
        n_ex + n_re,
        "driver programs in",
        _OUT_DIR,
    )
