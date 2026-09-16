#!/usr/bin/env bash
# Resolve every relative link in the hand-written docs against the built
# site, and fail on any that does not land on a page (#652).
#
# The pages under docs/src/ link into generated content by path, and
# those paths change whenever a module moves -- #556 moved every one, and
# 59 links on the chart-selection guide were 404 on the live site for
# four days while the docs build stayed green. modo and Hugo validate
# nothing here (report-missing and strict are off, and Hugo does not
# check relative links in content), so this is the only gate.
#
# A link `](../a/b/)` resolves when docs/site/content/a/b exists as a
# directory, as b.md, or as b/_index.md. A `#fragment` must be a heading
# in that page, in Hugo's slug form (lowercase, spaces to hyphens).
#
# Run after `docs-build`; it reads what the build wrote.
set -u
content="docs/site/content"
[ -d "$content" ] || { echo "check_docs_links: $content is missing -- run docs-build first" >&2; exit 2; }
ok=0; bad=0
while IFS= read -r line; do
  src="${line%%:*}"; link="${line#*:}"
  target="${link%%#*}"; anchor=""; [ "$target" != "$link" ] && anchor="${link#*#}"
  path="$content/${target%/}"
  page=""
  for candidate in "$path.md" "$path/_index.md"; do [ -e "$candidate" ] && { page="$candidate"; break; }; done
  if [ -z "$page" ] && [ -d "$path" ]; then page="dir"; fi
  if [ -z "$page" ]; then
    bad=$((bad+1)); echo "MISSING  $src -> ../$link"; continue
  fi
  if [ -n "$anchor" ] && [ "$page" != "dir" ]; then
    want="$(echo "$anchor" | tr -- '-' ' ')"
    if ! grep -qiE "^#+ +${want}\$" "$page"; then bad=$((bad+1)); echo "NO ANCHOR  $src -> ../$link"; continue; fi
  fi
  ok=$((ok+1))
done < <(grep -oHE '\]\(\.\./[^)#]+/?(#[^)]*)?\)' docs/src/*.md | sed -E 's/^([^:]+):\]\(\.\.\//\1:/; s/\)$//' | sort -u)
echo "check_docs_links: $ok links resolve, $bad do not"
[ "$bad" -eq 0 ]
