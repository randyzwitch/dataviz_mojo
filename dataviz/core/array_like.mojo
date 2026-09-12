"""Adapters for data not stored as `List[Float64]` or `List[String]`.

Two independent axes, each with its own mechanism:

- A different *container* type (a custom buffer wrapper, a future
  dataframe column type) via `Float64Sequence`/`StringSequence`
  (`__len__` + `Int`-indexed element access), which that type's
  author declares conformance to.
- A different numeric *element* type through an ordinary `List`
  (`List[Int]`, `List[Float32]`, any `List[Scalar[dtype]]`) via
  `_materialize_scalar_list`'s `DType` genericity, with no trait
  involved.

Trait adapters require declared conformance; third-party types such as numpy
arrays need dedicated overloads. The traits extend `Sized` so `len()` works
on conforming values.
"""


trait Float64Sequence(Sized):
    """Anything with a length and `Int`-indexed `Float64` access. Conform a
    data-holding struct to this to pass it directly as `Plot.encode()`'s
    `x`/`y` without first copying it into a `List[Float64]`.

    A minimal read-only shape: only what `_materialize_floats` needs to
    walk the sequence once. No slicing, mutation, or `Copyable`/`Movable`
    requirement.
    """

    def __getitem__(self, idx: Int) -> Float64:
        ...


trait StringSequence(Sized):
    """`Float64Sequence`'s counterpart for categorical data
    (`Plot.encode_categorical()`'s `x`), with `String` elements.
    """

    def __getitem__(self, idx: Int) -> String:
        ...


def _materialize_floats[T: Float64Sequence](data: T) -> List[Float64]:
    """Copy any `Float64Sequence`-conforming value into a `List[Float64]`,
    the one place every array-like `Plot.encode()` overload converges, so
    the rest of the package only ever sees `List[Float64]`. An
    element-by-element copy: there is no way to borrow storage generically
    across arbitrary conforming types.
    """
    var out = List[Float64](capacity=len(data))
    for i in range(len(data)):
        out.append(data[i])
    return out^


def _materialize_strings[T: StringSequence](data: T) -> List[String]:
    """`_materialize_floats`'s counterpart for `StringSequence`."""
    var out = List[String](capacity=len(data))
    for i in range(len(data)):
        out.append(data[i])
    return out^


def _materialize_scalar_list[
    dtype: DType
](data: List[Scalar[dtype]]) -> List[Float64]:
    """Copy any numeric `List[Scalar[dtype]]` (`List[Int]`, `List[Float32]`,
    `List[Int32]`, ...) into a `List[Float64]`, converting each element
    with `.cast[DType.float64]()`. See the module docstring for why this
    is `DType`-generic rather than trait-based. `List[Float64]` would also
    match with `dtype = DType.float64`, but `Plot.encode()`'s concrete
    `List[Float64]` overload is more specific and wins for that input.
    """
    var out = List[Float64](capacity=len(data))
    for v in data:
        out.append(v.cast[DType.float64]())
    return out^


def _materialize_nested_scalar_list[
    dtype: DType
](data: List[List[Scalar[dtype]]]) -> List[List[Float64]]:
    """`_materialize_scalar_list`'s counterpart for the outer-list-per-series
    shape several marks share (`Mark.GROUPED_BAR`/`STACKED_BAR`, `BOX`,
    `BEESWARM`/`VIOLIN`/`RIDGELINE`, `CORRPLOT`, `MARIMEKKO`, `RADAR`,
    `PARALLEL`, the multi-series `POLAR`): one `_materialize_scalar_list`
    call per inner list.
    """
    var out = List[List[Float64]](capacity=len(data))
    for row in data:
        out.append(_materialize_scalar_list(row))
    return out^
