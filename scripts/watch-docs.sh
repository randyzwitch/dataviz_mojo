#!/usr/bin/env bash
# Rebuild modo output when Markdown under docs/src changes.
# Polling preserves the directory watched by a separately running Hugo server.
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
