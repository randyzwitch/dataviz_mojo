"""Resolve every link and image in the built site against the built tree.

Usage: python3 scripts/check_site_links.py docs/site/public

`check_docs_links.sh` reads the hand-written pages' Markdown before Hugo
runs; this reads what Hugo wrote, so it also covers the generated
Examples and Cookbook pages, whose links are built by
`scripts/gen_example_docs.mojo` at three different depths. The
cookbook's "Relevant API" links pointed at `dataviz/theme/Theme/` for
a week after #524 moved it under `core/`, and nothing noticed (#671).

Only the page body (`<main>`) is read: the theme's own navigation is
Hugo's to get right. A target counts as resolved when it is a file or
a directory with an `index.html`; fragments are not checked.
"""
import pathlib
import re
import sys
from urllib.parse import urljoin

public = pathlib.Path(sys.argv[1])
base = "/dataviz_mojo/"
bad = 0
checked = 0
for page in sorted(public.rglob("index.html")):
    html = page.read_text(errors="replace")
    if 'http-equiv="refresh"' in html:
        continue  # an alias page: one redirect, nothing to read
    url = base + str(page.relative_to(public).parent).replace("\\", "/").rstrip(".") + "/"
    url = url.replace("//", "/")
    main = re.search(r"<main.*?</main>", html, re.S)
    body = main.group(0) if main else html
    for m in re.finditer(r'(?:href|src)="([^"#]+)(?:#[^"]*)?"', body):
        target = m.group(1)
        if target.startswith(("http:", "https:", "mailto:", "data:", "//")):
            continue
        resolved = urljoin(url, target)
        if not resolved.startswith(base):
            bad += 1
            print("OUTSIDE SITE", url, "->", target)
            continue
        p = public / resolved[len(base):]
        checked += 1
        if not (p.is_file() or (p / "index.html").is_file()):
            bad += 1
            print("MISSING", url, "->", target)
print(f"check_site_links: {checked} links resolve, {bad} do not")
sys.exit(1 if bad else 0)
