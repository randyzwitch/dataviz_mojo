#!/usr/bin/env bash
# Polls docs/src/**/*.md for changes and re-runs `modo build` on each one,
# so the already-running `hugo server` (`pixi run docs-serve`) picks the
# regenerated docs/site/content up via its own file watch and live-reloads
# the browser -- no manual rebuild-and-restart needed while hand-editing a
# page like docs/src/_index.md.
#
# Deliberately NOT `pixi run docs-build`: that task starts with `rm -rf
# docs/site/content docs/site/public`, which deletes the very directory
# hugo server is watching out from under it -- its fsnotify watch doesn't
# survive that, so every edit would otherwise need a full server restart
# to show up (see the wiki/session history for how that was diagnosed).
# `docs-build` also reruns `mojo doc`/`gen_example_docs.mojo`, needed
# after touching dataviz/*.mojo docstrings or examples/, but not for
# a docs/src/*.md-only edit -- this script only ever calls modo directly,
# the same "regenerate site/content from src/" step docs-build's own
# comment describes, without the steps that don't apply here.
#
# No inotify-tools/entr available in this environment, hence the polling
# loop rather than a real filesystem watch -- 1s is frequent enough to
# feel instant for hand-editing without burning meaningful CPU.
set -euo pipefail
cd "$(dirname "$0")/.."

last=""
echo "Watching docs/src/ for changes -- Ctrl+C to stop."
echo "(Run 'pixi run docs-serve' separately first if it isn't already running.)"
while true; do
  cur=$(find docs/src -name '*.md' -printf '%p %T@\n' 2>/dev/null | sort | md5sum)
  if [[ "$cur" != "$last" ]]; then
    if [[ -n "$last" ]]; then
      echo "[$(date +%H:%M:%S)] docs/src changed -- rebuilding..."
      if .tools/modo build docs -c modo.yaml >/tmp/modo-watch.log 2>&1; then
        echo "[$(date +%H:%M:%S)] done."
      else
        echo "[$(date +%H:%M:%S)] modo build failed -- see /tmp/modo-watch.log"
      fi
    fi
    last="$cur"
  fi
  sleep 1
done
