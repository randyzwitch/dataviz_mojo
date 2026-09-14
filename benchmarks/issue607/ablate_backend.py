"""Diagnostic only: disable hexbin's raster callback in a copied source tree.

This deliberately breaks raster hexbin and is NOT a proposed implementation.
It isolates the cost of registering its unused raster callback for SVG-only use.
Run after measure.py and before validate.py to avoid concurrent measurements.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

prototype,results=map(lambda p:Path(p).resolve(),sys.argv[1:])
results.mkdir(parents=True,exist_ok=True)
ablation=results/'source'
assert not ablation.exists(), 'Choose a fresh results directory'
shutil.copytree(prototype/'dataviz',ablation/'dataviz')
p=ablation/'dataviz/plot.mojo'
s=p.read_text()
needle='self._render_canvas_family = _callback_binned[Canvas]'
assert s.count(needle)==1
p.write_text(s.replace(needle,'self._render_canvas_family = _callback_continuous[Canvas]'))
case_source=results/'hexbin_svg_full.mojo'
case_source.write_text((prototype/'benchmarks/issue607/hexbin_svg.mojo').read_text().replace('print(s.to_string().byte_length())','print(s.to_string())'))
rows=[]
expected=None
for run in range(3):
    for name in (['two_callbacks','svg_callback_only'] if run%2==0 else ['svg_callback_only','two_callbacks']):
        tree=prototype if name=='two_callbacks' else ablation
        cache=prototype/'.pixi/envs/default/share/max/cache/.mojo_cache'
        if cache.exists(): shutil.rmtree(cache)
        tag=f'{name}-{run+1}'
        binary=results/tag
        with (results/(tag+'.log')).open('w') as log:
            subprocess.run(['/usr/bin/time','-f','%e %U %S','-o',str(results/(tag+'.time')),
                            'pixi','run','--as-is','mojo','build','-I',str(tree),
                            str(case_source),'-o',str(binary)],
                           cwd=prototype,stdout=log,stderr=log,check=True)
        out=subprocess.check_output([str(binary)])
        if expected is not None: assert out==expected
        expected=out
        (results/(tag+'.svg')).write_bytes(out)
        wall,user,system=map(float,(results/(tag+'.time')).read_text().split())
        row=dict(case=name,run=run+1,wall_s=wall,cpu_s=user+system,bytes=binary.stat().st_size)
        rows.append(row)
        (results/'results.json').write_text(json.dumps(rows,indent=2))
        print(json.dumps(row),flush=True)
