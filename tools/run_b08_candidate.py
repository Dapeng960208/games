#!/usr/bin/env python3
"""Bounded, managed, headless B08 verification. Never opens a visible game."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from test_workspace import ensure_managed

ROOT = Path(__file__).resolve().parents[1]


def cache_signature() -> str:
    cache = ROOT / '.godot' / 'imported'
    rows = [(p.name, p.stat().st_size, p.stat().st_mtime_ns) for p in sorted(cache.glob('*')) if p.is_file()]
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


def main() -> int:
    ensure_managed('B08')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    output = Path(os.environ['GAMES_TEST_OUTPUT_DIR'])
    sources = sorted([*ROOT.glob('scripts/world/b08*.gd'), *ROOT.glob('scripts/combat/b08*.gd'),
                      ROOT/'data/b08_content.json', ROOT/'tests/test_b08_candidate.gd'])
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    cache_before = cache_signature()
    results = []
    for label, scene, extra in [('contract_live', 'tests/test_b08_candidate.tscn', []),
                                ('lifecycle', 'scenes/b08_candidate.tscn', ['--fixed-fps', '60', '--quit-after', '150'])]:
        command = [args.godot, '--headless', '--path', str(ROOT), '--audio-driver', 'Dummy', *extra,
                   'res://'+scene, '--', '--candidate-b08', '--test-profile=user://test_b08_candidate/'+label+'.json']
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=20)
            text = result.stdout + result.stderr
            valid = result.returncode == 0 and not any(x in text for x in ['SCRIPT ERROR', 'ERROR:'])
            if label == 'contract_live': valid &= 'failures=0' in text
            print(text, flush=True)
            (output/(label+'.log')).write_text(text)
            results.append({'stage':label, 'passed':valid, 'exit_code':result.returncode})
        except subprocess.TimeoutExpired:
            results.append({'stage':label, 'passed':False, 'timeout_seconds':20})
            break
    stable = cache_before == cache_signature()
    unchanged = all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==value for name,value in hashes.items())
    manifest = {'schema':'b08-initial-candidate-verification-v1','results':results,
                'source_sha256':hashes,'source_unchanged':unchanged,'imported_cache_metadata_unchanged':stable,
                'scope':'Focused headless contract/live integration and 150-frame lifecycle. No art, rendered pixels, natural balance or full chapter acceptance.'}
    (output/'verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k!='source_sha256'}),flush=True)
    return 0 if len(results)==2 and all(r['passed'] for r in results) and stable and unchanged else 1


if __name__ == '__main__':
    raise SystemExit(main())
