"""Build runtime223.mojo in each tree, then three alternating sample
processes per tree; medians of the per-process medians.
Usage: python3 measure_runtime223.py BASELINE PROTOTYPE RESULTS SOURCE
"""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

baseline, prototype, results, source = (Path(s).resolve() for s in sys.argv[1:])
results.mkdir(parents=True, exist_ok=True)
trees = {'baseline': baseline, 'prototype': prototype}
MARKS = ['line', 'hexbin', 'scatter3d', 'heatmap']
metadata = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
for name, tree in trees.items():
    metadata[name + '_commit'] = subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=tree, text=True).strip()
    with (results / (name + '-build.log')).open('w') as log:
        subprocess.run(['pixi', 'run', '--as-is', 'mojo', 'build', '-I', str(tree),
                        str(source), '-o', str(results / name)],
                       cwd=tree, stdout=log, stderr=log, check=True)
rows = []
checks = set()
for run in range(1, 4):
    for name in (['baseline', 'prototype'] if run % 2 else ['prototype', 'baseline']):
        output = subprocess.check_output([str(results / name)], text=True, cwd=trees[name])
        (results / f'{name}-{run}.txt').write_text(output)
        samples = {}
        for line in output.splitlines():
            parts = line.split()
            if parts[0] == 'check':
                checks.add(parts[1])
                continue
            mark, backend, elapsed = parts
            samples.setdefault((mark, backend), []).append(float(elapsed))
        assert len(samples) == 8
        for (mark, backend), values in samples.items():
            assert len(values) == 41
            rows.append(dict(tree=name, run=run, mark=MARKS[int(mark)],
                             backend=backend, median_ms=statistics.median(values) * 1000))
assert len(checks) == 1, checks
(results / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
(results / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
print("| mark | backend | main ms [range] | prototype ms [range] | change |")
print("| --- | --- | ---: | ---: | ---: |")
for mark in MARKS:
    for backend in ['raster', 'svg']:
        b = [r['median_ms'] for r in rows if r['tree'] == 'baseline' and r['mark'] == mark and r['backend'] == backend]
        p = [r['median_ms'] for r in rows if r['tree'] == 'prototype' and r['mark'] == mark and r['backend'] == backend]
        bm, pm = statistics.median(b), statistics.median(p)
        print(f"| {mark} | {backend} | {bm:.3f} [{min(b):.3f}–{max(b):.3f}] | {pm:.3f} [{min(p):.3f}–{max(p):.3f}] | {100 * (pm - bm) / bm:+.1f}% |")
