"""`_materialize_python_floats`: the numpy/pandas adapter piece of the
#158/#107 plan (see array_like.mojo's own module docstring for the
other two axes -- a different container type via `Float64Sequence`/
`StringSequence`, a different numeric element type via `DType`
genericity). `PythonObject` (a numpy `ndarray`, a pandas `Series`, or
a plain Python list of numbers) is a third, independent axis again:
`PythonObject` can't be made to conform to a Mojo trait (it isn't ours
to declare conformance on, same reason `List`/`Int`/`Float32` can't
be either), so this needs its own dedicated adapter, not `Float64Sequence`
or the `DType` mechanism.

Deliberately delegates the actual array-like detection and numeric
conversion to numpy itself (`np.ascontiguousarray(array, dtype=
"float64")`) rather than walking `array` element-by-element through
Python's own indexing protocol -- confirmed empirically that this
single call already accepts a numpy `ndarray` of any numeric dtype, a
plain Python list, *and* a raw pandas `Series` (no `.to_numpy()`
needed first -- numpy's own array-like conversion protocol handles a
Series transparently), because numpy's own C implementation already
solves "make this array-like Python object a contiguous float64
buffer" far more robustly than reimplementing that detection here
would. `std.python.numpy.from_numpy_array` then borrows the result's
buffer as a Mojo `Span` with zero extra copies (Modular's own
official numpy interop, not something built by hand here) -- the one
remaining copy, from that borrowed `Span` into a real `List[Float64]`,
is the same unavoidable "materialize into what the rest of this
package already expects" cost `_materialize_floats`/`_materialize_
scalar_list` (array_like.mojo) pay too.

Requires numpy installed in the *caller's* own environment --
`Python.import_module("numpy")` raises a clear error if it isn't,
same as any optional Python interop. dataviz_mojo itself never
depends on numpy (see pixi.toml's own comment on its dev-only numpy/
pandas dependency, there purely so this file has something real to
compile and test against); only someone who actually calls this
adapter needs numpy available.

Scoped to numeric `x`/`y` only, matching array_like.mojo's own `DType`
axis -- a `PythonObject` string column (a numpy array of `dtype=str`,
or a pandas `Series` of strings) for `Plot.encode_categorical()`'s `x`
is a real, separate follow-up (see #158's own tracking issue), not
attempted here.
"""

from std.python import Python, PythonObject
from std.python.numpy import from_numpy_array


def _materialize_python_floats(array: PythonObject) raises -> List[Float64]:
    """Copy a numpy `ndarray`/pandas `Series`/plain Python number list
    into a real `List[Float64]` -- see this module's own docstring for
    the full reasoning (numpy does the actual array-like detection and
    numeric conversion; this only unwraps its result into a `List`).

    Raises with numpy's/`from_numpy_array`'s own message on anything
    that can't become a 1-D numeric array (non-numeric data, more than
    one dimension, ...) -- not re-wrapped, since that message already
    names the actual problem.
    """
    var np = Python.import_module("numpy")
    var contig = np.ascontiguousarray(array, dtype="float64")
    var span = from_numpy_array[DType.float64](contig)
    var out = List[Float64](capacity=len(span))
    for v in span:
        out.append(v)
    return out^
