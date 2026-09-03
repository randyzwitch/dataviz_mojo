#!/usr/bin/env bash
# Polls docs/src/**/*.md for changes and re-runs `modo build` on each,
# so a running `hugo server` (`pixi run docs-serve`) picks the
# regenerated docs/site/content up and live-reloads.
#
# Not `pixi run docs-build`: that starts with `rm -rf docs/site/content`,
# which deletes the directory hugo server is watching, so every edit
# would need a server restart. docs-build also reruns `mojo doc`/
# gen_example_docs.mojo, which a docs/src/*.md-only edit doesn't need.
#
# A 1s polling loop, since inotify-tools/entr aren't available here.
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
