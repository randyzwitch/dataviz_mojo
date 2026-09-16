#!/usr/bin/env bash
# Fail when a docstring names another plotting library (#650).
#
# A docstring describes what a function does in this library's own
# terms. A comparison to matplotlib or seaborn there is a crib sheet for
# users of the other library, dates the text to that library's API, and
# belongs in a migration guide (#613). #612 swept about 140 of them out;
# four were back within days (#641). This is what stops the drift.
#
# Only docstrings are checked: a `#` comment may say where an algorithm
# was checked against another implementation, and the colormap module's
# provenance line (stops sampled from matplotlib's tables) is allowed by
# name below. Docstrings are the text between `"""` pairs, which is how
# this package uses them; the scan toggles on each `"""` it sees.
#
# `numpy` and `pandas` are deliberately not on the list: those are
# interop features described in their own terms.
set -u
pattern='matplotlib|seaborn|pyplot|mplot3d|ggplot|plotly|bokeh|altair|vega'
allow='dataviz/core/colormaps.mojo:.*sampled from matplotlib'
found=0
while IFS= read -r file; do
  awk -v pat="$pattern" -v file="$file" '
    {
      line = $0
      n = gsub(/"""/, "&", line)      # how many delimiters on this line
      if (indoc && match($0, pat)) print file ":" NR ":" $0
      else if (!indoc && n >= 1) {
        # a docstring opens here; the same line may close it
        rest = $0; sub(/^[^"]*"""/, "", rest)
        if (match(rest, pat)) print file ":" NR ":" $0
      }
      if (n % 2 == 1) indoc = !indoc
    }' "$file"
done < <(find dataviz -name '*.mojo' | sort) | grep -vE "$allow" | tee /tmp/docstring_terms.txt
found=$(wc -l < /tmp/docstring_terms.txt)
if [ "$found" -gt 0 ]; then
  echo "check_docstring_terms: $found docstring line(s) name another library -- describe the feature in its own terms; the mapping belongs in a migration guide (#613)"
  exit 1
fi
echo "check_docstring_terms: no docstring names another library"
