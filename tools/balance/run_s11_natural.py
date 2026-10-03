#!/usr/bin/env python3
"""Run isolated, immutable-source natural-route simulations; never player saves."""
import argparse, concurrent.futures, hashlib, json, math, os, pathlib, subprocess, time

def run_engine(command, env, log_path, timeout):
    """Stop only this isolated child when its runtime fails; retain all output."""
    started=time.monotonic(); reason=''
    with log_path.open('w') as log:
        process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env)
        while process.poll() is None:
            time.sleep(.25)
            text=log_path.read_text(errors='replace')
            if 'SCRIPT ERROR' in text or '\nERROR:' in text: reason='engine_error'
            elif time.monotonic()-started >= timeout: reason='execution_timeout'
            if reason:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
                break
        code=process.wait()
    return (124 if reason=='execution_timeout' else code),reason

def read_events(path):
    events=[]; errors=[]
    if not path.exists(): return events,['missing event journal']
    for number,line in enumerate(path.read_text(errors='replace').splitlines(),1):
        try:
            event=json.loads(line)
            if not isinstance(event,dict): raise ValueError('event is not an object')
            events.append(event)
        except (ValueError,TypeError) as error:
            errors.append(f'line {number}: {error}')
    return events,errors

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--project',type=pathlib.Path,required=True)
    p.add_argument('--engine',type=pathlib.Path,required=True)
    p.add_argument('--output',type=pathlib.Path,required=True)
    p.add_argument('--heroes',default='CH01,CH02,CH03')
    p.add_argument('--seconds',type=float,default=3600)
    p.add_argument('--workers',type=int,default=1)
    a=p.parse_args(); a.project=a.project.resolve(); a.output=a.output.resolve()
    if a.project == a.output or a.project in a.output.parents: raise SystemExit('Evidence must be outside the checkout')
    heroes=a.heroes.split(',')
    if any(h not in ('CH01','CH02','CH03') for h in heroes) or len(set(heroes)) != len(heroes): raise SystemExit('Invalid or repeated hero')
    if not math.isfinite(a.seconds) or a.seconds <= 0 or not 1 <= a.workers <= 3: raise SystemExit('Invalid duration or worker count')
    if a.output.exists() and any(a.output.iterdir()): raise SystemExit('Choose a new evidence directory; do not overwrite samples')
    a.output.mkdir(parents=True,exist_ok=True)
    relevant=[]
    for directory in ('config','scripts','data','scenes','shaders','tests/support'):
        relevant.extend(f for f in (a.project/directory).rglob('*') if f.is_file() and f.suffix in ('.gd','.json','.tscn','.tres','.gdshader'))
    relevant.extend(a.project/name for name in ('tests/balance/test_s11_natural_progression.gd','tests/balance/test_s11_natural_progression.tscn','project.godot','tools/balance/run_s11_natural.py'))
    hashes={str(f.relative_to(a.project)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(set(relevant))}
    manifest={'source_sha256':hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest(),'files':hashes,
        'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=a.project,text=True).strip(),
        'engine':str(a.engine),'engine_sha256':hashlib.sha256(a.engine.read_bytes()).hexdigest(),'project':str(a.project),'heroes':heroes,'simulation_seconds':a.seconds,
        'physics_hz':60,'engine_time_scale':1,'timing':'accelerated simulation elapsed, not human earning or learning time',
        'evidence':'production inputs, natural acquisition and legal transactions; no injected progress'}
    (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2))
    def run(hero):
        out=a.output/hero;out.mkdir()
        env=os.environ.copy()
        for key,folder in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
            target=out/folder;target.mkdir();env[key]=str(target)
        command=[str(a.engine),'--headless','--audio-driver','Dummy','--fixed-fps','60','--path',str(a.project),
            'tests/balance/test_s11_natural_progression.tscn','--',f'--test-profile={out}/test_s11_natural_progression/profile.json',
            f'--hero={hero}',f'--sim-seconds={a.seconds}',f'--output={out}/events.jsonl']
        started=time.monotonic()
        exit_code,execution_failure=run_engine(command,env,out/'engine.log',max(600,a.seconds*3))
        log=(out/'engine.log').read_text(errors='replace')
        events,evidence_errors=read_events(out/'events.jsonl')
        final=events[-1] if events else {}
        value={'hero':hero,'exit_code':exit_code,'execution_timeout':execution_failure=='execution_timeout','execution_failure':execution_failure,'host_wall_seconds':time.monotonic()-started,
            'engine_error':('SCRIPT ERROR' in log or '\nERROR:' in log),'evidence_errors':evidence_errors,'final':final,'events':len(events)}
        (out/'result.json').write_text(json.dumps(value,indent=2));print(json.dumps(value),flush=True)
        return value
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool: results=list(pool.map(run,heroes))
    (a.output/'summary.json').write_text(json.dumps(results,indent=2))
    if any(r['exit_code'] or r['engine_error'] or r['evidence_errors'] or r['final'].get('reason')!='observation_limit' for r in results): raise SystemExit(1)
if __name__=='__main__': main()
