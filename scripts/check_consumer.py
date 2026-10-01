#!/usr/bin/env python3
"""Build this package the way a user installs it, and run a program on it.

A throwaway workspace with a path dependency on this checkout builds the
package through the pixi-build-mojo backend, then compiles and runs a
small chart program against it. CI's package job runs this, and so can
`pixi run check-consumer` locally.

`pixi build` is not a substitute (#863): pixi deprecated it, and it
solves the source dependencies' build environments without the
workspace channel's `exclude-newer`, so canvas_mojo and dataframe_mojo
get precompiled by the newest Mojo nightly and the pinned compiler
refuses their `.mojoc`. A consumer workspace honors the cutoff. Its
channels are read from this pixi.toml rather than copied, so moving the
cutoff moves it here too.

Usage: check_consumer.py [consumer-dir]
    The directory is created if missing; default is a fresh temporary
    directory. The build log is left there as build.log.
"""

import platform
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

CONSUMER = """from dataviz import bar, save

def main() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var c = bar(cats, vals, title="Consumer check")
    save(c, "out.svg")
    save(c, "out.png")
    print("consumer ok")
"""

PLATFORMS = {
    ("Linux", "x86_64"): "linux-64",
    ("Linux", "aarch64"): "linux-aarch64",
    ("Darwin", "arm64"): "osx-arm64",
}


def _toml_value(value) -> str:
    """The inline TOML for a channel entry: a string or a flat table."""
    if isinstance(value, str):
        return '"' + value + '"'
    if isinstance(value, dict):
        fields = ", ".join(f"{key} = {_toml_value(v)}" for key, v in value.items())
        return "{ " + fields + " }"
    raise TypeError(f"unexpected channel entry {value!r}")


def _manifest(channels: list, consumer_platform: str) -> str:
    entries = ", ".join(_toml_value(channel) for channel in channels)
    return f"""[workspace]
name = "dataviz-consumer-check"
version = "0.0.0"
channels = [{entries}]
platforms = ["{consumer_platform}"]
preview = ["pixi-build"]

[dependencies]
dataviz_mojo = {{ path = "{ROOT}" }}
"""


def main() -> int:
    if len(sys.argv) > 2:
        print("usage: check_consumer.py [consumer-dir]", file=sys.stderr)
        return 2
    consumer = (
        Path(sys.argv[1])
        if len(sys.argv) == 2
        else Path(tempfile.mkdtemp(prefix="dataviz-consumer-"))
    )
    consumer.mkdir(parents=True, exist_ok=True)

    consumer_platform = PLATFORMS.get((platform.system(), platform.machine()))
    if consumer_platform is None:
        print(
            f"check_consumer: unsupported platform {platform.system()}"
            f" {platform.machine()}",
            file=sys.stderr,
        )
        return 1

    with (ROOT / "pixi.toml").open("rb") as source:
        channels = tomllib.load(source)["workspace"]["channels"]
    (consumer / "pixi.toml").write_text(_manifest(channels, consumer_platform))
    (consumer / "consumer.mojo").write_text(CONSUMER)
    for stale in ("out.svg", "out.png"):
        (consumer / stale).unlink(missing_ok=True)

    # The backend builds the package on the first `pixi run`, so its
    # output is only here; keep all of it for the checks below.
    run = subprocess.run(
        ["pixi", "run", "mojo", "run", "consumer.mojo"],
        cwd=consumer,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    log = run.stdout
    (consumer / "build.log").write_text(log)
    sys.stdout.write(log)
    if run.returncode != 0:
        print(f"check_consumer: the consumer failed (exit {run.returncode})")
        return 1

    # pixi-build-mojo below 0.2.6 packages with `mojo package` into a
    # .mojopkg and warns twice while doing it (#603). Those warnings are
    # the only symptom, so without this the backend can quietly fall
    # back and nothing fails. A cached package prints no build output,
    # so only a fresh consumer directory can show this.
    if "mojo precompile" not in log:
        print(
            "check_consumer: the backend did not use 'mojo precompile' --"
            " it resolved an older pixi-build-mojo than intended, or the"
            " package came from a cache (use a fresh directory). The"
            " backend's pixi-build-api-version 7 needs pixi 0.77.0 or later."
        )
        return 1
    deprecations = [
        line
        for line in log.splitlines()
        if "'package' is deprecated" in line
        or "'.mojopkg' file extensions is deprecated" in line
    ]
    if deprecations:
        print("check_consumer: the packaging deprecation warnings of #603 are back:")
        print("\n".join(deprecations))
        return 1

    for output in ("out.svg", "out.png"):
        path = consumer / output
        if not path.is_file() or path.stat().st_size == 0:
            print(f"check_consumer: {output} missing or empty")
            return 1
    print(f"check_consumer: packaged with precompile, consumer ran in {consumer}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
