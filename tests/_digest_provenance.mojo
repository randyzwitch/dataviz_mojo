"""Installed toolchain identity for the byte-exact output digest (#780)."""

from std.os import getenv, listdir


def _installed_version(name: String) raises -> String:
    var prefix = getenv("CONDA_PREFIX")
    if prefix.byte_length() == 0:
        raise Error(
            "output digest provenance requires CONDA_PREFIX (run with pixi)"
        )
    var found = String("")
    for entry in listdir(prefix + "/conda-meta"):
        var file = String(entry)
        if not file.startswith(name + "-") or not file.endswith(".json"):
            continue
        if name == "mojo" and (
            file.startswith("mojo-compiler-") or file.startswith("mojo-python-")
        ):
            continue
        if found.byte_length() > 0:
            raise Error(
                "multiple installed " + name + " packages in conda-meta"
            )
        var parts = file.split("-")
        if len(parts) < 3:
            raise Error("invalid conda metadata name for " + name + ": " + file)
        found = String(parts[1])
    if found.byte_length() == 0:
        raise Error("no installed " + name + " package in conda-meta")
    return found^


def _locked_revision(name: String) raises -> String:
    """The one Git commit used by every platform in pixi.lock.

    Package versions alone do not distinguish rebuilt source tags.
    The lock records the source commit after `#`; requiring agreement
    across entries keeps this header platform-independent.
    """
    var root = getenv("PIXI_PROJECT_ROOT")
    if root.byte_length() == 0:
        raise Error(
            "output digest provenance requires PIXI_PROJECT_ROOT"
            " (run with pixi)"
        )
    var f = open(root + "/pixi.lock", "r")
    var lock_text = f.read()
    f.close()
    var found = String("")
    for line in lock_text.split("\n"):
        var entry = String(String(line).strip())
        if not entry.startswith("- conda_source: " + name + "["):
            continue
        var parts = entry.split("#")
        if len(parts) != 2:
            raise Error("invalid source pin for " + name + " in pixi.lock")
        var revision = String(parts[1])
        if revision.byte_length() != 40:
            raise Error("invalid Git revision for " + name + " in pixi.lock")
        if found.byte_length() > 0 and found != revision:
            raise Error("different " + name + " revisions in pixi.lock")
        found = revision
    if found.byte_length() == 0:
        raise Error("no source pin for " + name + " in pixi.lock")
    return found^


def _provenance_line() raises -> String:
    return (
        "# toolchain: mojo="
        + _installed_version("mojo")
        + " canvas_mojo="
        + _installed_version("canvas_mojo")
        + "@"
        + _locked_revision("canvas_mojo")
        + " dataframe_mojo="
        + _installed_version("dataframe_mojo")
        + "@"
        + _locked_revision("dataframe_mojo")
    )


def _validate_provenance(text: String) raises:
    var recorded = String("")
    for line in text.split("\n"):
        var value = String(line)
        if value.startswith("# toolchain: "):
            if recorded.byte_length() > 0:
                raise Error("output digest has multiple toolchain headers")
            recorded = value
    var running = _provenance_line()
    if recorded != running:
        raise Error(
            "output digest toolchain differs: recorded "
            + (recorded if recorded.byte_length() > 0 else "(missing)")
            + "; running "
            + running
        )
