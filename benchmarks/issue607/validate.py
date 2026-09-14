"""Run after measure.py, without concurrent compile timing."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

baseline, prototype, results = map(lambda s: Path(s).resolve(),sys.argv[1:])
results.mkdir(parents=True,exist_ok=True)
source=prototype/'benchmarks/issue607'
for name,tree in [('baseline',baseline),('prototype',prototype)]:
    out=results/name
    out.mkdir(exist_ok=True)
    for case in ['verify_output','runtime']:
        cmd=['pixi','run','--as-is','mojo','build','-I',str(tree),'-I',str(tree/'tests'),str(source/(case+'.mojo')),'-o',str(results/(name+'-'+case))]
        with (results/(name+'-'+case+'.log')).open('w') as log:
            subprocess.run(cmd,cwd=tree,stdout=log,stderr=log,check=True)
    print(subprocess.check_output([str(results/(name+'-verify_output')),str(out)],cwd=tree,text=True),flush=True)
files=sorted(p.name for p in (results/'baseline').iterdir())
assert files==sorted(p.name for p in (results/'prototype').iterdir())
assert files
for f in files:
    assert (results/'baseline'/f).read_bytes()==(results/'prototype'/f).read_bytes(), f
(results/'output_hashes.json').write_text(json.dumps({f:hashlib.sha256((results/'baseline'/f).read_bytes()).hexdigest() for f in files},indent=2))
print('Exact byte identity:',len(files),'files',flush=True)
for run in range(3):
    for name in (['baseline','prototype'] if run%2==0 else ['prototype','baseline']):
        with (results/f'runtime-{name}-{run+1}.txt').open('w') as out:
            subprocess.run([str(results/(name+'-runtime'))],stdout=out,check=True)
print('Runtime measurements complete',flush=True)
modules=['test_output_digest','test_layers_facets','test_core_plot','test_marks_basic','test_marks_binned']
modules=[m for m in modules if (prototype/'tests'/(m+'.mojo')).exists()]
# The binned cases actually live in test_binned.mojo.
modules.append('test_binned')
def test(module):
    with (results/(module+'.log')).open('w') as log:
        p=subprocess.run(['pixi','run','--as-is','mojo','run','-I','.', '-I','tests','tests/'+module+'.mojo'],cwd=prototype,stdout=log,stderr=log)
    print(module,'PASS' if p.returncode==0 else 'FAIL',flush=True)
    return module,p.returncode
with ThreadPoolExecutor(max_workers=3) as pool:
    statuses=dict(pool.map(test,modules))
(results/'test_results.json').write_text(json.dumps(statuses,indent=2))
assert not any(statuses.values()),statuses
