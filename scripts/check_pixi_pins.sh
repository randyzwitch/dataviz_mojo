#!/usr/bin/env bash
# Every workflow must pin the same pixi (#658).
#
# #646 raised the pin in ci.yml and said the jobs move together; the
# reusable docs-build workflow kept the old one, and the next pin bump
# (#665) broke every docs deploy while CI stayed green -- the two never
# ran on the same pixi again. One value, or this fails and names them.
set -u
pins=$(grep -rhoE '^\s*pixi-version:\s*\S+' .github/workflows/*.yml | awk '{print $2}' | sort -u)
count=$(echo "$pins" | grep -c .)
if [ "$count" -ne 1 ]; then
  echo "check_pixi_pins: the workflows pin $count different pixi versions:"
  grep -rnE '^\s*pixi-version:' .github/workflows/*.yml
  exit 1
fi
echo "check_pixi_pins: every workflow pins pixi $pins"
