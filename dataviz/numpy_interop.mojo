"""`_materialize_python_floats`: the numpy/pandas adapter, a third input
axis alongside array_like.mojo's `Float64Sequence`/`StringSequence`
(container type) and `DType` genericity (element type). `PythonObject`
can't conform to a Mojo trait, so it gets its own adapter.

Array-like detection and numeric conversion are delegated to numpy:
`np.ascontiguousarray(array, dtype="float64")` accepts an `ndarray` of
any numeric dtype, a plain Python list, and a pandas `Series` directly.
`std.python.numpy.from_numpy_array` then borrows the result as a `Span`
without copying; the one copy is from that `Span` into the
`List[Float64]` the rest of the package expects.

Requires numpy in the caller's environment; `Python.import_module(
"numpy")` raises if it is missing. dataviz itself never depends on
numpy (pixi.toml lists it as a dev/test-only dependency).

Numeric `x`/`y` only. A `PythonObject` string column for
`Plot.encode_categorical()` is a separate follow-up (#158).
"""

from std.python import Python, PythonObject
from std.python.numpy import from_numpy_array


def _materialize_python_floats(array: PythonObject) raises -> List[Float64]:
    """Copy a numpy `ndarray`/pandas `Series`/plain Python number list into a
    `List[Float64]`. Raises with numpy's/`from_numpy_array`'s own message
    on anything that can't become a 1-D numeric array.
    """
    var np = Python.import_module("numpy")
    var contig = np.ascontiguousarray(array, dtype="float64")
    var span = from_numpy_array[DType.float64](contig)
    var out = List[Float64](capacity=len(span))
    for v in span:
        out.append(v)
    return out^
