#!/usr/bin/env bash
# Fail when `mojo doc` warns about anything under dataviz/.
#
# `mojo doc` exits 0 however much it warns, so a warning about this
# package is invisible to every gate that reads an exit code (#756).
# When this check was written it was warning 45 times and had been for
# some while: five DataFrame overloads whose `Args:` block was cut
# short by a stray blank line (so every argument after it read as
# undocumented), three private column readers that never documented
# their `missing`/`label` policy arguments, one argument documented out
# of signature order, and one deprecated positional index. The docs
# built and the tests passed throughout -- a warning is not a failure
# anywhere else, which is exactly why it needed a gate of its own.
#
# Scoped to `dataviz/` on purpose: a warning from a dependency is not
# ours to fix and must not fail our build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$(mktemp)"
JSON="$(mktemp)"
trap 'rm -f "$LOG" "$JSON"' EXIT

cd "$ROOT"
if ! mojo doc -I . -o "$JSON" dataviz > "$LOG" 2>&1; then
    echo "check_doc_warnings.sh: 'mojo doc' failed:" >&2
    cat "$LOG" >&2
    exit 1
fi

# Matches the compiler's own `path:line:col: warning:` form, so a
# mention of the word in a docstring can never trip it.
PATTERN='dataviz/[^ ]*\.mojo:[0-9]+:[0-9]+: warning:'
if grep -qE "$PATTERN" "$LOG"; then
    echo "check_doc_warnings.sh: 'mojo doc' warned about this package:" >&2
    grep -E "$PATTERN" "$LOG" >&2
    echo >&2
    echo "Fix the warnings above, or explain in the docstring why the" >&2
    echo "argument is absent. Do not widen this check's scope." >&2
    exit 1
fi

echo "check_doc_warnings.sh: 'mojo doc' reports no warnings under dataviz/"
