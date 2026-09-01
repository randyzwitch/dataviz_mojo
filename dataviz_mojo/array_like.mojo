"""`Float64Sequence`/`StringSequence`: the public extension point for
accepting chart data that isn't a plain `List[Float64]`/`List[String]`
-- a custom buffer wrapper, a future dataframe column type, anything
with a length and integer-indexed access to the right element type.
See #158/#107 for the design discussion this closes the first slice
of.

Why a trait at all, rather than just genericizing every `encode()`
parameter over "anything indexable": Mojo trait conformance is
nominal, not structural -- a type must be *declared* to conform
(`struct Foo(Float64Sequence): ...`), and critically, that declaration
can only happen where the type itself is defined. There is no way for
this package (or anyone) to retroactively make an existing third-party
type conform to a trait invented after the fact (Mojo has no "struct
extensions" yet) -- so this only ever helps for a type whose *author*
adds the conformance, which is exactly the "a future dataframe column
type" case #158 asks for. It does nothing for types this package can't
ask to change (`List` itself, a numpy array via `PythonObject`, a MAX
`Tensor`/`DeviceBuffer`) -- those need their own dedicated adapter
overloads instead (numpy's is the next piece of this plan; see #158),
not this trait.

Confirmed empirically, not just from the docs, before building this:
`List[Float64]` already has a matching `__len__`/`__getitem__` shape
but does *not* satisfy `Float64Sequence` -- passing one to a function
generic over `T: Float64Sequence` is a compile error, not a silent
match. That's exactly why `Plot.encode()`'s array-like overload (see
plot.mojo) exists *alongside* the original concrete `List[Float64]`
one rather than replacing it -- there is no single signature that
covers both without this trait, however structurally similar the two
inputs are.

`(Sized)`: composing the stdlib's own `Sized` trait, not just
requiring a matching `__len__` by convention -- `len(x)` (used by
`_materialize_floats`/`_materialize_strings` below, and by any caller
outside this package) only dispatches against a value whose type
provably conforms to `Sized` itself; requiring `__len__`'s shape on
its own isn't enough to make the builtin accept it.
"""


trait Float64Sequence(Sized):
    """Anything with a length and `Int`-indexed `Float64` access --
    conform a data-holding struct to this to pass it directly as
    `Plot.encode()`'s `x`/`y` (see that method's array-like overload)
    without first copying it into a `List[Float64]` by hand.

    A minimal, read-only shape deliberately: only what `_materialize_
    floats` below needs to walk the whole sequence once. No slicing,
    no mutation, no `Copyable`/`Movable` requirement of its own (this
    trait doesn't need to move or duplicate a conforming value, only
    read from a borrowed reference to it).
    """

    def __getitem__(self, idx: Int) -> Float64:
        ...


trait StringSequence(Sized):
    """`Float64Sequence`'s exact counterpart for categorical data
    (`Plot.encode_categorical()`'s `x`) -- see that trait's own
    docstring for the shape and reasoning, identical here but for
    `String` elements instead of `Float64`.
    """

    def __getitem__(self, idx: Int) -> String:
        ...


def _materialize_floats[T: Float64Sequence](data: T) -> List[Float64]:
    """Copy any `Float64Sequence`-conforming value into a real
    `List[Float64]` -- the one place every array-like `Plot.encode()`
    overload converges, so the rest of this package (every `_render_
    */_draw_*/_validate_*` function, all ~185 call sites across every
    mark file) never has to know about `Float64Sequence` at all; it
    only ever sees the same concrete `List[Float64]` it always has.

    A plain element-by-element copy, not a zero-copy view -- there's
    no way to borrow storage generically across arbitrary conforming
    types (a MAX `Tensor`'s memory doesn't share a layout with a
    `List`'s), so this is the one, honest, unavoidable cost of
    accepting a foreign array-like source. Exactly the same shape a
    numpy or MAX `Tensor`/`DeviceBuffer` adapter will do next (see
    this module's own docstring) -- reading through *their* own
    indexing instead of this trait's, since neither can be made to
    conform to it.
    """
    var out = List[Float64](capacity=len(data))
    for i in range(len(data)):
        out.append(data[i])
    return out^


def _materialize_strings[T: StringSequence](data: T) -> List[String]:
    """`_materialize_floats`'s exact counterpart for `StringSequence`
    -- see that function's own docstring."""
    var out = List[String](capacity=len(data))
    for i in range(len(data)):
        out.append(data[i])
    return out^
