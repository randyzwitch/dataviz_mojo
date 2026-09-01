"""Accepting chart data that isn't a plain `List[Float64]`/`List
[String]` -- two independent axes, each its own mechanism (see #158/
#107 for the design discussion this closes the first slice of):

- A different *container* type -- a custom buffer wrapper, a future
  dataframe column type -- via `Float64Sequence`/`StringSequence`
  (`__len__` + `Int`-indexed element access), which that type's own
  author declares conformance to.
- A different numeric *element* type through an ordinary `List` --
  `List[Int]`, `List[Float32]`, any other `List[Scalar[dtype]]` --
  via `_materialize_scalar_list`'s `DType` genericity, no trait or
  author cooperation needed at all (see that function's own
  docstring for why this one doesn't hit the same nominal-conformance
  wall the container axis does).

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

`_materialize_scalar_list` below is a second, *independent* axis of
"not exactly `List[Float64]`": a `List[Int]`/`List[Float32]`/any other
numeric `List` -- a different element *type* through the same `List`
container, rather than a different container type. A `Floatable`
trait exists in the stdlib, but confirmed empirically (again) that
`Int`/`Float32`/`Float64` don't actually conform to it despite each
having a real `__float__` -- the same nominal-conformance wall as
`Float64Sequence` above, just hit from the numeric-type direction
instead of the container direction. The real fix isn't a trait at
all: `Float64`/`Float32`/`Int`/every other Mojo scalar type is
literally `Scalar[some_dtype]` (a `DType` type parameter, not a
trait), so a function generic over `dtype: DType` taking `Scalar[
dtype]`/`List[Scalar[dtype]]` handles all of them uniformly via `.
cast[DType.float64]()` -- confirmed working for `List[Int]`/`List[
Float32]`/`List[Float64]` alike, with zero ambiguity against the
other two `encode()` overloads (Mojo picks the concrete `List[
Float64]` overload when that's exactly what's passed, and this one
otherwise).

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


def _materialize_scalar_list[dtype: DType](data: List[Scalar[dtype]]) -> List[Float64]:
    """Copy any numeric `List[Scalar[dtype]]` -- `List[Int]`, `List[
    Float32]`, `List[Int32]`, ... -- into a real `List[Float64]`,
    widening/narrowing each element with `.cast[DType.float64]()`
    (hardware numeric conversion, the same operation `Float64(v)`
    itself performs for a single scalar). See this module's own
    docstring for why this is a `DType`-generic function rather than a
    trait -- a completely different mechanism from `_materialize_
    floats` above even though the two solve visibly similar problems
    ("my data isn't quite a `List[Float64]`"), because this one is
    about the *element* type varying, not the *container* type.

    `List[Float64]` itself satisfies `List[Scalar[dtype]]` with `dtype
    = DType.float64` -- this function would happily convert it too
    (a no-op cast) -- but `Plot.encode()`'s own overload set never
    actually calls it that way: the plain concrete `List[Float64]`
    overload is more specific and wins for that exact input, so this
    only ever runs for a genuinely different element type in practice.
    """
    var out = List[Float64](capacity=len(data))
    for v in data:
        out.append(v.cast[DType.float64]())
    return out^


def _materialize_nested_scalar_list[
    dtype: DType
](data: List[List[Scalar[dtype]]]) -> List[List[Float64]]:
    """`_materialize_scalar_list`'s counterpart for the "outer list
    indexes a series/category, inner list is its own values" shape
    several marks share (`Mark.GROUPED_BAR`/`STACKED_BAR`, `BOX`,
    `BEESWARM`/`VIOLIN`/`RIDGELINE`, `CORRPLOT`, `MARIMEKKO`, `RADAR`,
    `PARALLEL`, the multi-series `POLAR`) -- one `_materialize_scalar_
    list` call per inner list, same widening cast, same reasoning.

    This is exactly the generalization `Plot.encode_grouped_bar()`'s
    own docstring (and #158's own tracking issue) called out as a
    real, separate follow-up from the flat-list case -- a list *per
    series* needed its own function, not a trivial extension of the
    flat one, since a `List[List[Scalar[dtype]]]` and a `List[List[
    Float64]]` are still two different concrete types no amount of
    flat-list handling covers.
    """
    var out = List[List[Float64]](capacity=len(data))
    for row in data:
        out.append(_materialize_scalar_list(row))
    return out^
