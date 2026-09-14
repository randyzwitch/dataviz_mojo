"""Cold builds, alternating fixed trees, guarded source hashes, exact output checks.

Usage: python3 benchmarks/issue607/measure.py BASELINE PROTOTYPE RESULTS
Each tree must already have its own locked Pixi environment installed.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

baseline, prototype, results = map(lambda s: Path(s).resolve(), sys.argv[1:])
results.mkdir(parents=True, exist_ok=True)
cases = ['line_both', 'line_svg', 'hexbin_both', 'hexbin_svg']

def digest(tree):
    h = hashlib.sha256()
    for f in sorted((tree / 'dataviz').rglob('*.mojo')):
        h.update(str(f.relative_to(tree)).encode())
        h.update(f.read_bytes())
    h.update((tree/'pixi.lock').read_bytes())
    return h.hexdigest()

trees = {'baseline': baseline, 'prototype': prototype}
hashes = {name: digest(tree) for name, tree in trees.items()}
assert hashes['baseline'] != hashes['prototype']
assert '_render_canvas_family' not in (baseline/'dataviz/plot.mojo').read_text()
assert 'var r_basic = _render_basic_family(' not in (prototype/'dataviz/plot.mojo').read_text()
assert (baseline/'pixi.lock').read_bytes() == (prototype/'pixi.lock').read_bytes()
metadata = {'hashes': hashes, 'trees': {k:str(v) for k,v in trees.items()},
            'baseline_commit': subprocess.check_output(['git','rev-parse','HEAD'],cwd=baseline,text=True).strip(),
            'uname': list(os.uname()), 'cpu': subprocess.check_output(['lscpu'],text=True)}
for name, tree in trees.items():
    metadata[name+'_mojo'] = subprocess.check_output(['pixi','run','--as-is','mojo','--version'],cwd=tree,text=True)
(results/'metadata.json').write_text(json.dumps(metadata,indent=2))
rows=[]
outputs={}
for run in range(3):
    for case in cases:
        for name in (['baseline','prototype'] if run % 2 == 0 else ['prototype','baseline']):
            tree=trees[name]
            assert digest(tree)==hashes[name], f'{name} changed during measurement'
            cache=tree/'.pixi/envs/default/share/max/cache/.mojo_cache'
            if cache.exists(): shutil.rmtree(cache)
            assert not cache.exists()
            tag=f'{case}-{name}-{run+1}'
            binary=results/tag
            if binary.exists(): binary.unlink()
            timefile=results/(tag+'.time')
            cmd=['/usr/bin/time','-f','%e %U %S %M','-o',str(timefile),
                 'pixi','run','--as-is','mojo','build','-I',str(tree),
                 str(prototype/'benchmarks/issue607'/(case+'.mojo')),'-o',str(binary)]
            with (results/(tag+'.log')).open('w') as log:
                subprocess.run(cmd,cwd=tree,stdout=log,stderr=log,check=True)
            assert binary.is_file() and binary.stat().st_size>0
            output=subprocess.check_output([str(binary)],cwd=tree)
            if case in outputs: assert output==outputs[case],f'Output changed: {tag}'
            outputs[case]=output
            (results/(tag+'.stdout')).write_bytes(output)
            wall,user,system,rss=map(float,timefile.read_text().split())
            row=dict(case=case,tree=name,run=run+1,wall_s=wall,cpu_s=user+system,
                     max_rss_kb=rss,bytes=binary.stat().st_size)
            rows.append(row)
            (results/'results.json').write_text(json.dumps(rows,indent=2))
            print(json.dumps(row),flush=True)
