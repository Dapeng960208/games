#!/usr/bin/env python3
"""Focused B07 pure checks. No formal art copy or full-project import."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from test_workspace import ensure_managed

def main():
    ensure_managed('B07')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default='/usr/local/bin/godot')
    parser.add_argument('--suites',nargs='+',choices=['content','sun_state'],default=['content','sun_state'])
    args=parser.parse_args()
    root=next(p for p in Path(__file__).resolve().parents if (p / "project.godot").is_file())
    suites=args.suites
    with tempfile.TemporaryDirectory(prefix='b07-foundation-') as directory:
        project=Path(directory)
        pending=[f'tests/levels/b07/test_{suite}.gd' for suite in suites]
        pending+=['data/levels/b07/content.json','data/monsters/enemy_species_policy.json','data/rules/numerical.json','scripts/infrastructure/assets/asset_catalog.gd']
        copied=set()
        while pending:
            name=pending.pop()
            if name in copied: continue
            copied.add(name)
            source=root/name
            target=project/name
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,target)
            if source.suffix=='.gd':
                pending.extend(re.findall(r'(?:preload|load)\("res://([^"\n]+\.gd)"\)',source.read_text()))
                pending.extend(re.findall(r'extends "res://([^"\n]+\.gd)"',source.read_text()))
        classes=[]
        for name in sorted(copied):
            if not name.endswith('.gd'): continue
            text=(project/name).read_text()
            found=re.search(r'^class_name (\w+)',text,re.M)
            base=re.search(r'^extends (\w+)',text,re.M)
            if found and base:
                classes.append('{\"base\": &\"'+base[1]+'\", \"class\": &\"'+found[1]+'\", \"icon\": \"\", \"is_abstract\": false, \"is_tool\": false, \"language\": &\"GDScript\", \"path\": \"res://'+name+'\"}')
        (project/'.godot').mkdir(exist_ok=True)
        (project/'.godot/global_script_class_cache.cfg').write_text('list=['+', '.join(classes)+']')
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="B07PureQA"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        failed=False
        for suite in suites:
            try:
                result=subprocess.run([args.godot,'--headless','--path',str(project),'--script',f'res://tests/levels/b07/test_{suite}.gd'],capture_output=True,text=True,timeout=10)
            except subprocess.TimeoutExpired as exc:
                print((exc.stdout or b'').decode(errors='replace'),(exc.stderr or b'').decode(errors='replace'),flush=True)
                failed=True
                continue
            output=result.stdout+result.stderr
            print(output,flush=True)
            failed |= result.returncode!=0 or 'SCRIPT ERROR' in output or 'ERROR:' in output or '0 failures' not in output
        return 1 if failed else 0
if __name__=='__main__': raise SystemExit(main())
