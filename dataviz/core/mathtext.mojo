"""Mathematical labels: a small expression language for titles, axis
captions, legend entries, tick labels and annotations (#371).

A label such as `"$\\sigma^2$"` or `"Rate $\\frac{\\Delta y}{\\Delta x}$"`
is parsed here, laid out into positioned text runs, and handed to the
same deferred-`_TextRequest` path every plain label takes. A label with
no `$` in it never enters this module: `_needs_math()` is a byte scan,
and the plain path is byte-for-byte what it was before this existed.

## Why the layout lives here and not in canvas

An expression is a tree of runs at different sizes and offsets, and
laying it out needs exactly two things of a backend: measure a string,
and draw a string at an anchor. `measure_text` and `draw_text` are on
the `DrawTarget` trait, so one layout serves every backend, and the
raster, SVG and PDF outputs put each run at the same anchor by
construction rather than by three implementations agreeing. What a
backend would have to add for this to move upstream -- a math axis
height, a superscript shift -- are typographic conventions rather than
font facts, and the numbers below are those conventions. Canvas already
does the two things that *are* font facts: it shapes each run with
kerning, and it pulls a glyph the chosen face lacks from another
installed one, which is what makes `∑` and `∂` appear at all.

## The subset

Math is delimited by `$...$`. Inside it:

- Latin letters are italic, as variables; digits, operators and Greek
  are upright. `\\mathrm{...}` forces upright text.
- `^` and `_` attach a superscript or subscript to the atom before
  them: `x^2`, `x_i`, `x_i^2`, `e^{-t}`.
- `\\frac{num}{den}` stacks a fraction with a rule at the math axis.
- `{...}` groups. `\\,` is a thin space. `\\$` is a literal dollar
  sign, inside or outside math.
- Named symbols: the Greek alphabet (`\\alpha`...`\\omega`,
  `\\Gamma`...`\\Omega`) and the operators listed in `_symbol()`.

A single `$` with no partner is a literal (so `"Cost $5"` stays
plain); three or more that cannot pair raise. An unknown `\\command`,
an unbalanced brace, or a `^`/`_` with nothing to attach to raise at
render time naming the label and the position, rather than drawing
something that looks almost right.

## What is not here

No radicals with a vinculum (`\\sqrt` gives the `√` glyph and nothing
over its argument), no large operators with limits, no matrices, no
line breaks inside math. Kerning applies within a run, not across the
boundary between a base and its script. Each run is anchored on a
whole pixel, like every other label.
"""

from std.math import ceil, cos, floor, sin

from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.text.font_discovery import FontSlant
from canvas.text.render import (
    FontWeight,
    TextAlign,
    measure_text,
    measure_text_block,
)

from dataviz.core.text import _TextRequest

# Typographic conventions, as fractions of the font size of the text the
# construct is attached to. Named so a reader can see what each one is,
# and so a test can check a script is smaller and higher rather than
# reading the numbers back.
comptime _SCRIPT_SCALE = 0.7
"""A superscript or subscript is this fraction of its base's size."""
comptime _SUP_RISE = 0.45
"""A superscript's baseline sits this far above its base's baseline."""
comptime _SUB_DROP = 0.2
"""A subscript's baseline sits this far below its base's baseline."""
comptime _SCRIPT_KERN = 0.04
"""Gap between a base and the scripts attached to it."""
comptime _FRAC_SCALE = 0.8
"""A fraction's numerator and denominator are this fraction of the
surrounding size -- smaller than the line, larger than a script."""
comptime _AXIS = 0.33
"""The math axis: the height above the baseline where a minus sign and
a fraction rule sit."""
comptime _RULE = 0.06
"""A fraction rule's thickness, never less than one pixel."""
comptime _FRAC_GAP = 0.1
"""Clearance between a fraction rule and the numerator above and
denominator below it."""
comptime _FRAC_PAD = 0.08
"""Horizontal clearance on each side of a fraction."""
comptime _MIN_ASCENT = 0.7
"""A run is at least this tall above its baseline, so a row of "x"
stacks the same way a row of "H" does."""
comptime _MIN_DESCENT = 0.2
"""A run is at least this deep below its baseline, for the same
reason."""
comptime _RELATION_SPACE = 0.25
"""Space on each side of a relation such as `=` or `\\leq`."""
comptime _BINARY_SPACE = 0.16
"""Space on each side of a binary operator such as `+` or `\\times`
-- none when it is unary, as the minus in `e^{-t}` is."""
comptime _NO_SPACING = 0
comptime _BINARY = 1
comptime _RELATION = 2

comptime _ROW = 0
comptime _TEXT = 1
comptime _SCRIPTS = 2
comptime _FRAC = 3


struct _Node(Copyable, Movable):
    """One node of a parsed expression, in an arena indexed by
    position. `children` are indices into the same arena: a `_ROW`'s
    members in order; a `_SCRIPTS`'s `[base, superscript, subscript]`
    with `-1` for a missing script; a `_FRAC`'s `[numerator,
    denominator]`. A `_TEXT` holds its run and whether it is forced
    upright; an operator's `spacing` says how much room the row gives
    it on each side.
    """

    var kind: Int
    var text: String
    var upright: Bool
    var spacing: Int
    var children: List[Int]

    def __init__(
        out self,
        kind: Int,
        text: String = "",
        upright: Bool = False,
        spacing: Int = _NO_SPACING,
    ):
        self.kind = kind
        self.text = text
        self.upright = upright
        self.spacing = spacing
        self.children = List[Int]()


struct _Run(Copyable, Movable):
    """One positioned piece of text: its baseline-left corner relative
    to the expression's origin, its size, and its slant."""

    var dx: Float64
    var dy: Float64
    var text: String
    var size: Float64
    var slant: FontSlant

    def __init__(
        out self,
        dx: Float64,
        dy: Float64,
        text: String,
        size: Float64,
        slant: FontSlant,
    ):
        self.dx = dx
        self.dy = dy
        self.text = text
        self.size = size
        self.slant = slant


struct _Rule(Copyable, Movable):
    """A fraction bar: a horizontal line from `(dx, dy)` of `width`,
    `thickness` pixels thick, relative to the expression's origin."""

    var dx: Float64
    var dy: Float64
    var width: Float64
    var thickness: Float64

    def __init__(
        out self, dx: Float64, dy: Float64, width: Float64, thickness: Float64
    ):
        self.dx = dx
        self.dy = dy
        self.width = width
        self.thickness = thickness


struct _MathBox(Movable):
    """A laid-out expression: its extent about the baseline-left origin,
    and the runs and rules that draw it, positioned relative to that
    origin.

    `ascent` is how far the ink reaches above the baseline and
    `descent` how far below, both non-negative; `width` is the advance
    of the whole expression. Every child box is laid out about its own
    origin and then `placed()` into its parent at an offset, so nothing
    knows its absolute position until the requests are emitted.
    """

    var width: Float64
    var ascent: Float64
    var descent: Float64
    var runs: List[_Run]
    var rules: List[_Rule]

    def __init__(out self):
        self.width = 0.0
        self.ascent = 0.0
        self.descent = 0.0
        self.runs = List[_Run]()
        self.rules = List[_Rule]()

    def place(mut self, other: _MathBox, dx: Float64, dy: Float64):
        """Add `other`'s runs and rules into this box, shifted by
        `(dx, dy)`. Extent is the caller's to update, since what the
        placement means for it depends on the construct.

        Args:
            other: The child box.
            dx: Horizontal offset of the child's origin from this one.
            dy: Vertical offset, positive downward.
        """
        for r in other.runs:
            self.runs.append(
                _Run(r.dx + dx, r.dy + dy, r.text, r.size, r.slant)
            )
        for r in other.rules:
            self.rules.append(_Rule(r.dx + dx, r.dy + dy, r.width, r.thickness))


# ==== detection ====


def _needs_math(label: String) -> Bool:
    """Whether `label` has anything for this module to do: two or more
    dollar signs that are not escaped, or an escaped one to unescape.

    A byte scan, so the cost to a plain label is a pass over its bytes
    and nothing else. A lone unescaped `$` is a literal -- `"Cost $5"`
    is a plain label -- and its owner never reaches the parser.
    """
    var bytes = label.as_bytes()
    var dollars = 0
    var i = 0
    while i < len(bytes):
        var b = Int(bytes[i])
        if (
            b == ord("\\")
            and i + 1 < len(bytes)
            and Int(bytes[i + 1]) == ord("$")
        ):
            return True
        if b == ord("$"):
            dollars += 1
        i += 1
    return dollars >= 2


# ==== parsing ====


def _symbol(name: String) -> String:
    """The character a `\\name` stands for, or `""` for a name this
    module does not know.

    Greek covers the alphabet in both cases, with `\\epsilon` the
    lunate form and `\\varepsilon` the open one, as usual. The
    operators are the ones axis captions and titles reach for; a name
    missing here is an error at the call site, not a silent blank.
    """
    if name == "alpha":
        return "α"
    if name == "beta":
        return "β"
    if name == "gamma":
        return "γ"
    if name == "delta":
        return "δ"
    if name == "epsilon":
        return "ϵ"
    if name == "varepsilon":
        return "ε"
    if name == "zeta":
        return "ζ"
    if name == "eta":
        return "η"
    if name == "theta":
        return "θ"
    if name == "iota":
        return "ι"
    if name == "kappa":
        return "κ"
    if name == "lambda":
        return "λ"
    if name == "mu":
        return "μ"
    if name == "nu":
        return "ν"
    if name == "xi":
        return "ξ"
    if name == "pi":
        return "π"
    if name == "rho":
        return "ρ"
    if name == "sigma":
        return "σ"
    if name == "tau":
        return "τ"
    if name == "upsilon":
        return "υ"
    if name == "phi":
        return "ϕ"
    if name == "varphi":
        return "φ"
    if name == "chi":
        return "χ"
    if name == "psi":
        return "ψ"
    if name == "omega":
        return "ω"
    if name == "Gamma":
        return "Γ"
    if name == "Delta":
        return "Δ"
    if name == "Theta":
        return "Θ"
    if name == "Lambda":
        return "Λ"
    if name == "Xi":
        return "Ξ"
    if name == "Pi":
        return "Π"
    if name == "Sigma":
        return "Σ"
    if name == "Upsilon":
        return "Υ"
    if name == "Phi":
        return "Φ"
    if name == "Psi":
        return "Ψ"
    if name == "Omega":
        return "Ω"
    if name == "times":
        return "×"
    if name == "cdot":
        return "·"
    if name == "pm":
        return "±"
    if name == "mp":
        return "∓"
    if name == "leq" or name == "le":
        return "≤"
    if name == "geq" or name == "ge":
        return "≥"
    if name == "neq" or name == "ne":
        return "≠"
    if name == "approx":
        return "≈"
    if name == "equiv":
        return "≡"
    if name == "propto":
        return "∝"
    if name == "infty":
        return "∞"
    if name == "partial":
        return "∂"
    if name == "nabla":
        return "∇"
    if name == "sum":
        return "∑"
    if name == "prod":
        return "∏"
    if name == "int":
        return "∫"
    if name == "sqrt":
        return "√"
    if name == "rightarrow" or name == "to":
        return "→"
    if name == "leftarrow":
        return "←"
    if name == "cdots" or name == "ldots" or name == "dots":
        return "⋯"
    if name == "degree" or name == "circ":
        return "°"
    if name == "hbar":
        return "ℏ"
    if name == "ell":
        return "ℓ"
    if name == "angle":
        return "∠"
    if name == "perp":
        return "⊥"
    if name == "parallel":
        return "∥"
    if name == "minus":
        return "−"
    return ""


struct _Parser(Movable):
    """A recursive-descent parser over the codepoints of one label.

    The label is split into characters up front so every position is a
    character index, which is what an error message should quote and
    what `^` and `_` need to look one atom back over.
    """

    var label: String
    var chars: List[String]
    var pos: Int
    var nodes: List[_Node]

    def __init__(out self, label: String):
        self.label = label
        self.chars = List[String]()
        for cp in label.codepoints():
            self.chars.append(chr(Int(cp.to_u32())))
        self.pos = 0
        self.nodes = List[_Node]()

    def fail(self, what: String) raises:
        """Raise the one error shape this module produces."""
        raise Error(
            "Math label '"
            + self.label
            + "': "
            + what
            + " at character "
            + String(self.pos + 1)
        )

    def add(mut self, var node: _Node) -> Int:
        """Append `node` to the arena and return its index."""
        self.nodes.append(node^)
        return len(self.nodes) - 1

    def peek(self) -> String:
        """The character at `pos`, or `""` at the end."""
        if self.pos < len(self.chars):
            return self.chars[self.pos]
        return ""

    def parse_label(mut self) raises -> Int:
        """The whole label: plain text and `$...$` segments alternating,
        as one row. Returns the root index.

        An odd number of unescaped `$` is only allowed when it is one:
        that one is a literal. Three cannot be told apart from a typo.
        """
        var row = _Node(_ROW)
        var plain = String()
        # Count the delimiters, skipping every escaped `\$`: those are
        # literal wherever they sit and must not decide anything here.
        var dollars = 0
        var k = 0
        while k < len(self.chars):
            if (
                self.chars[k] == "\\"
                and k + 1 < len(self.chars)
                and self.chars[k + 1] == "$"
            ):
                k += 2
                continue
            if self.chars[k] == "$":
                dollars += 1
            k += 1
        var lone_dollar_is_literal = dollars == 1
        if dollars > 1 and dollars % 2 == 1:
            # Report at the last one, which is the one without a partner
            # as often as any.
            self.pos = len(self.chars) - 1
            while self.pos > 0 and not (
                self.chars[self.pos] == "$" and self.chars[self.pos - 1] != "\\"
            ):
                self.pos -= 1
            self.fail("unbalanced $")
        while self.pos < len(self.chars):
            var c = self.chars[self.pos]
            if (
                c == "\\"
                and self.pos + 1 < len(self.chars)
                and self.chars[self.pos + 1] == "$"
            ):
                plain += "$"
                self.pos += 2
                continue
            if c == "$" and not lone_dollar_is_literal:
                if plain.byte_length() > 0:
                    row.children.append(self.add(_Node(_TEXT, plain, True)))
                    plain = String()
                self.pos += 1
                row.children.append(self.parse_math(closing="$"))
                # parse_math stops on the closing "$"; step past it.
                self.pos += 1
                continue
            plain += c
            self.pos += 1
        if plain.byte_length() > 0:
            row.children.append(self.add(_Node(_TEXT, plain, True)))
        return self.add(row^)

    def parse_math(
        mut self, closing: String, upright: Bool = False
    ) raises -> Int:
        """A math sequence up to (not past) `closing`, as a row.

        Letters become italic runs and everything else upright, with
        adjacent characters of one style merged into one run so the
        shaper can kern them. `^` and `_` reach back to the row's last
        atom; a script on nothing is an error rather than a guess.
        """
        var row = _Node(_ROW)
        var run = String()
        var run_italic = False

        while True:
            var c = self.peek()
            if c == "":
                if closing == "$":
                    self.fail("missing closing $")
                self.fail("missing closing }")
            if c == closing:
                break
            if c == "}":
                self.fail("unmatched }")
            if c == " " or c == "\t":
                self.pos += 1
                continue
            if c == "^" or c == "_":
                self._flush(row, run, run_italic, upright)
                run = String()
                if len(row.children) == 0:
                    self.fail("nothing for " + c + " to attach to")
                self.pos += 1
                var arg = self.parse_argument(upright)
                var last = row.children[len(row.children) - 1]
                var scripts: Int
                if self.nodes[last].kind == _SCRIPTS:
                    scripts = last
                else:
                    var node = _Node(_SCRIPTS)
                    node.children.append(last)
                    node.children.append(-1)
                    node.children.append(-1)
                    scripts = self.add(node^)
                    row.children[len(row.children) - 1] = scripts
                var slot = 1 if c == "^" else 2
                if self.nodes[scripts].children[slot] >= 0:
                    self.fail("a second " + c + " on the same atom")
                self.nodes[scripts].children[slot] = arg
                continue
            if c == "{":
                self._flush(row, run, run_italic, upright)
                run = String()
                self.pos += 1
                row.children.append(
                    self.parse_math(closing="}", upright=upright)
                )
                self.pos += 1
                continue
            if c == "\\":
                self._flush(row, run, run_italic, upright)
                run = String()
                row.children.append(self.parse_command(upright))
                continue
            # An operator stands alone so the row can space it. `-` is
            # the minus sign in math, not a hyphen.
            var spacing = _spacing_of_char(c)
            if spacing != _NO_SPACING:
                self._flush(row, run, run_italic, upright)
                run = String()
                var glyph = "\u2212" if c == "-" else c
                row.children.append(
                    self.add(_Node(_TEXT, glyph, True, spacing=spacing))
                )
                self.pos += 1
                continue
            # A literal character. Letters are variables and italic
            # unless upright was forced; everything else is upright.
            var italic = _is_latin_letter(c) and not upright
            if run.byte_length() > 0 and italic != run_italic:
                self._flush(row, run, run_italic, upright)
                run = String()
            run += c
            run_italic = italic
            self.pos += 1

        self._flush(row, run, run_italic, upright)
        return self.add(row^)

    def _flush(
        mut self, mut row: _Node, run: String, italic: Bool, upright: Bool
    ):
        """Append the pending run to `row` as a text node, if any."""
        if run.byte_length() > 0:
            row.children.append(
                self.add(_Node(_TEXT, run, upright or not italic))
            )

    def parse_argument(mut self, upright: Bool) raises -> Int:
        """What follows `^`, `_` or a command that takes an argument: a
        braced group, or a single character or command."""
        var c = self.peek()
        if c == "":
            self.fail("expected an argument")
        if c == "{":
            self.pos += 1
            var group = self.parse_math(closing="}", upright=upright)
            self.pos += 1
            return group
        if c == "\\":
            return self.parse_command(upright)
        if c == "^" or c == "_" or c == "}" or c == "$":
            self.fail("expected an argument, found " + c)
        self.pos += 1
        var italic = _is_latin_letter(c) and not upright
        return self.add(_Node(_TEXT, c, upright or not italic))

    def parse_command(mut self, upright: Bool) raises -> Int:
        """A backslash command: a named symbol, `\\frac`, `\\mathrm`, a
        spacing command, or an escaped `$`."""
        var start = self.pos
        self.pos += 1
        var c = self.peek()
        if c == "$":
            self.pos += 1
            return self.add(_Node(_TEXT, "$", True))
        if c == ",":
            self.pos += 1
            return self.add(_Node(_TEXT, " ", True))
        if c == ";" or c == " ":
            self.pos += 1
            return self.add(_Node(_TEXT, "  ", True))
        var name = String()
        while self.peek() != "" and _is_latin_letter(self.peek()):
            name += self.peek()
            self.pos += 1
        if name.byte_length() == 0:
            self.pos = start
            self.fail("a backslash needs a command name after it")
        if name == "frac":
            var node = _Node(_FRAC)
            node.children.append(self.parse_argument(upright))
            node.children.append(self.parse_argument(upright))
            return self.add(node^)
        if name == "mathrm" or name == "text":
            var c2 = self.peek()
            if c2 != "{":
                self.fail("\\" + name + " needs a braced argument")
            self.pos += 1
            var group = self.parse_math(closing="}", upright=True)
            self.pos += 1
            return group
        var glyph = _symbol(name)
        if glyph.byte_length() == 0:
            self.pos = start
            self.fail("unknown command \\" + name)
        return self.add(
            _Node(_TEXT, glyph, True, spacing=_spacing_of_char(glyph))
        )


def _spacing_of_char(c: String) -> Int:
    """The spacing class of a one-character operator, or none.

    Relations get more room than binary operators, as they do in any
    typeset formula; everything not listed is an ordinary character.
    """
    if c == "=" or c == "<" or c == ">":
        return _RELATION
    for rel in ["≤", "≥", "≠", "≈", "≡", "∝", "→", "←"]:
        if c == rel:
            return _RELATION
    for op in ["+", "-", "−", "×", "·", "±", "∓"]:
        if c == op:
            return _BINARY
    return _NO_SPACING


def _is_latin_letter(c: String) -> Bool:
    """Whether `c` is a single ASCII letter -- the characters math mode
    sets in italic."""
    if c.byte_length() != 1:
        return False
    var b = Int(c.as_bytes()[0])
    return (b >= ord("a") and b <= ord("z")) or (
        b >= ord("A") and b <= ord("Z")
    )


# ==== layout ====


def _layout_run(
    text: String,
    size: Float64,
    slant: FontSlant,
    family: String,
    weight: FontWeight,
    *,
    mut cache: FontCache,
) raises -> _MathBox:
    """One run of text as a box about its own baseline-left origin.

    Width is the advance, not the ink width, so a trailing space
    counts and two runs abut the way the shaper would abut them.
    Ascent and descent are the ink's, floored at `_MIN_ASCENT` and
    `_MIN_DESCENT` of the size so a row of short letters keeps the
    same line box as a row of tall ones.
    """
    var box = _MathBox()
    var m = measure_text(
        text, size, family=family, slant=slant, weight=weight, cache=cache
    )
    var b = measure_text_block(
        text, size, family=family, slant=slant, weight=weight, cache=cache
    )
    box.width = m.advance
    box.ascent = max(-b.y, _MIN_ASCENT * size)
    box.descent = max(b.y + b.height, _MIN_DESCENT * size)
    box.runs.append(_Run(0.0, 0.0, text, size, slant))
    return box^


def _layout(
    nodes: List[_Node],
    index: Int,
    size: Float64,
    family: String,
    weight: FontWeight,
    *,
    mut cache: FontCache,
) raises -> _MathBox:
    """Lay out the subtree at `index` at `size`, recursively."""
    ref node = nodes[index]
    if node.kind == _TEXT:
        var slant = FontSlant.NORMAL if node.upright else FontSlant.ITALIC
        return _layout_run(node.text, size, slant, family, weight, cache=cache)

    if node.kind == _ROW:
        var box = _MathBox()
        var count = len(node.children)
        for i in range(count):
            var child = node.children[i]
            var c = _layout(nodes, child, size, family, weight, cache=cache)
            # An operator gets room on each side, except a binary one
            # with nothing before it -- the unary minus of `e^{-t}` --
            # which hugs its operand.
            var spacing = nodes[child].spacing
            var room = 0.0
            if spacing == _RELATION:
                room = _RELATION_SPACE * size
            elif spacing == _BINARY:
                var unary = (
                    i == 0 or nodes[node.children[i - 1]].spacing != _NO_SPACING
                )
                if not unary:
                    room = _BINARY_SPACE * size
            if room > 0.0 and i > 0:
                box.width += room
            box.place(c, box.width, 0.0)
            box.width += c.width
            if room > 0.0 and i < count - 1:
                box.width += room
            box.ascent = max(box.ascent, c.ascent)
            box.descent = max(box.descent, c.descent)
        return box^

    if node.kind == _SCRIPTS:
        var box = _layout(
            nodes, node.children[0], size, family, weight, cache=cache
        )
        var kern = _SCRIPT_KERN * size
        var script_size = size * _SCRIPT_SCALE
        var scripts_width = 0.0
        if node.children[1] >= 0:
            var sup = _layout(
                nodes,
                node.children[1],
                script_size,
                family,
                weight,
                cache=cache,
            )
            var rise = _SUP_RISE * size
            box.place(sup, box.width + kern, -rise)
            box.ascent = max(box.ascent, rise + sup.ascent)
            box.descent = max(box.descent, sup.descent - rise)
            scripts_width = max(scripts_width, sup.width)
        if node.children[2] >= 0:
            var sub = _layout(
                nodes,
                node.children[2],
                script_size,
                family,
                weight,
                cache=cache,
            )
            var drop = _SUB_DROP * size
            box.place(sub, box.width + kern, drop)
            box.descent = max(box.descent, drop + sub.descent)
            box.ascent = max(box.ascent, sub.ascent - drop)
            scripts_width = max(scripts_width, sub.width)
        box.width += kern + scripts_width
        return box^

    # _FRAC
    var inner = size * _FRAC_SCALE
    var num = _layout(
        nodes, node.children[0], inner, family, weight, cache=cache
    )
    var den = _layout(
        nodes, node.children[1], inner, family, weight, cache=cache
    )
    var pad = _FRAC_PAD * size
    var axis = _AXIS * size
    var thickness = max(1.0, _RULE * size)
    var gap = _FRAC_GAP * size
    var inner_width = max(num.width, den.width)
    var box = _MathBox()
    box.width = inner_width + 2.0 * pad
    # The numerator's baseline sits its own descent above the rule's
    # top clearance; the denominator's, its own ascent below the
    # bottom clearance. Both are centered on the wider of the two.
    var num_dy = -(axis + thickness / 2.0 + gap + num.descent)
    var den_dy = -axis + thickness / 2.0 + gap + den.ascent
    box.place(num, pad + (inner_width - num.width) / 2.0, num_dy)
    box.place(den, pad + (inner_width - den.width) / 2.0, den_dy)
    box.rules.append(_Rule(0.0, -axis, box.width, thickness))
    box.ascent = -num_dy + num.ascent
    box.descent = max(den_dy + den.descent, _MIN_DESCENT * size)
    return box^


def _layout_label(
    label: String,
    size: Float64,
    family: String,
    bold: Bool,
    *,
    mut cache: FontCache,
) raises -> _MathBox:
    """Parse and lay out `label`, which `_needs_math()` said needs it.

    Args:
        label: The label, with its `$...$` segments.
        size: The font size of the surrounding text.
        family: The theme's font family.
        bold: Whether the surrounding text is bold; every run follows.
        cache: The render's shared font cache.

    Returns:
        The laid-out box, positioned about its baseline-left origin.

    Raises:
        Error: The label does not parse -- the message names the label
            and the character -- or a measurement fails.
    """
    var parser = _Parser(label)
    var root = parser.parse_label()
    var weight = FontWeight.BOLD if bold else FontWeight.NORMAL
    return _layout(parser.nodes, root, size, family, weight, cache=cache)


# ==== the two questions layout code asks, and the requests ====


def _label_width(
    label: String,
    size: Float64,
    family: String,
    bold: Bool,
    *,
    mut cache: FontCache,
) raises -> Float64:
    """How wide `label` draws: the measured ink width of a plain label,
    exactly as before, or the expression's advance for a math one.

    Args:
        label: The label.
        size: Its font size.
        family: The theme's font family.
        bold: Whether it draws bold.
        cache: The render's shared font cache.

    Returns:
        The width in pixels.

    Raises:
        Error: A math label does not parse, or measuring fails.
    """
    if not _needs_math(label):
        return measure_text(
            label,
            size,
            family=family,
            weight=FontWeight.BOLD if bold else FontWeight.NORMAL,
            cache=cache,
        ).width
    return _layout_label(label, size, family, bold, cache=cache).width


def _reserve_height(
    label: String,
    size: Float64,
    family: String,
    bold: Bool,
    *,
    mut cache: FontCache,
) raises -> Int:
    """How many rows a label needs reserved for it: `Int(size)` for a
    plain label, which is the reservation every caller made before this
    module existed, or the expression's full ascent plus descent, so a
    fraction or a superscript is not clipped by a band sized for one
    line.

    Args:
        label: The label.
        size: Its font size.
        family: The theme's font family.
        bold: Whether it draws bold.
        cache: The render's shared font cache.

    Returns:
        Rows to reserve, not counting any gap.

    Raises:
        Error: A math label does not parse, or measuring fails.
    """
    if not _needs_math(label):
        return Int(size)
    var box = _layout_label(label, size, family, bold, cache=cache)
    return Int(ceil(box.ascent + box.descent))


def _round(v: Float64) -> Int:
    """Nearest whole pixel, halves rounding up."""
    return Int(floor(v + 0.5))


def _label_requests(
    label: String,
    x: Int,
    y: Int,
    size: Float64,
    color: Color,
    align: TextAlign,
    family: String,
    bold: Bool,
    rotation: Float64,
    *,
    mut cache: FontCache,
) raises -> List[_TextRequest]:
    """The `_TextRequest`s that draw `label` anchored at `(x, y)`: one,
    unchanged from before, for a plain label; one per run plus one per
    fraction rule for a math label.

    Alignment moves the expression's origin so the whole expression is
    left-, center- or right-anchored on `x`, and each run is then a
    `TextAlign.LEFT` request at its own position. Rotation turns every
    run's offset about the anchor and is passed on to each run, so a
    rotated axis caption keeps its scripts where they belong.

    Args:
        label: The label.
        x: Anchor x, in pixels.
        y: Anchor y -- the baseline of the surrounding text.
        size: Font size of the surrounding text.
        color: Text color.
        align: How the whole label sits against `x`.
        family: The theme's font family.
        bold: Whether the label draws bold.
        rotation: Radians, clockwise on screen, about the anchor.
        cache: The render's shared font cache.

    Returns:
        The requests, in drawing order.

    Raises:
        Error: A math label does not parse, or measuring fails.
    """
    var out = List[_TextRequest]()
    if not _needs_math(label):
        out.append(
            _TextRequest(
                x,
                y,
                label,
                color,
                size,
                align,
                family,
                bold=bold,
                rotation=rotation,
            )
        )
        return out^

    var box = _layout_label(label, size, family, bold, cache=cache)
    var origin = 0.0
    if align == TextAlign.CENTER:
        origin = -box.width / 2.0
    elif align == TextAlign.RIGHT:
        origin = -box.width
    var c = 1.0
    var s = 0.0
    if rotation != 0.0:
        c = cos(rotation)
        s = sin(rotation)

    for r in box.runs:
        var dx = origin + r.dx
        var px = dx * c - r.dy * s
        var py = dx * s + r.dy * c
        out.append(
            _TextRequest(
                x + _round(px),
                y + _round(py),
                r.text,
                color,
                r.size,
                TextAlign.LEFT,
                family,
                bold=bold,
                rotation=rotation,
                slant=r.slant,
            )
        )
    for rule in box.rules:
        var dx0 = origin + rule.dx
        var dx1 = dx0 + rule.width
        var x0 = dx0 * c - rule.dy * s
        var y0 = dx0 * s + rule.dy * c
        var x1 = dx1 * c - rule.dy * s
        var y1 = dx1 * s + rule.dy * c
        out.append(
            _TextRequest.rule(
                x + _round(x0),
                y + _round(y0),
                x + _round(x1),
                y + _round(y1),
                rule.thickness,
                color,
            )
        )
    return out^
