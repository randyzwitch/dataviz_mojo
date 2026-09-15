"""Build each tree, then collect three alternating runtime sample processes.

Usage: python3 benchmarks/issue607/measure_runtime.py BASELINE PROTOTYPE RESULTS
Run separately from compile measurements; requires installed locked environments.
"""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

baseline, prototype, results = (Path(s).resolve() for s in sys.argv[1:])
results.mkdir(parents=True, exist_ok=True)
trees = {'baseline': baseline, 'prototype': prototype}
source = prototype / 'benchmarks/issue607/runtime.mojo'
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
        assert len(samples) == 6
        for (mark, backend), values in samples.items():
            assert len(values) == 41
            rows.append(dict(tree=name, run=run, mark=['line', 'hexbin'][int(mark)],
                             backend=backend, median_s=statistics.median(values)))
assert len(checks) == 1
(results / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
(results / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
print(json.dumps(rows, indent=2))
