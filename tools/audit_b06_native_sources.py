#!/usr/bin/env python3
"""Read-only native B06 registration audit. Does not grant visual acceptance."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1] / 'assets/generated/b06_native_v1'

def main():
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    seen = set()
    count = 0
    for identity, source in manifest['identities'].items():
        assert source['reference_body_height_px'] > 0, identity
        if identity.startswith('B06-M'):
            assert set(source['frames']) == {'idle', 'telegraph', 'execute'}, identity
        for pose, frame in source['frames'].items():
            count += audit(frame)
            assert frame['source_sha256'] not in seen, (identity, pose, 'reused source')
            seen.add(frame['source_sha256'])
            if 'source_pose_scale' in frame:
                reference = frame['anatomy_reference_segment_px']
                measured = frame['anatomy_pose_segment_px']
                ratio = math.hypot(reference[2]-reference[0], reference[3]-reference[1]) / math.hypot(measured[2]-measured[0], measured[3]-measured[1])
                assert abs(frame['source_pose_scale'] - ratio) < 0.000001, (identity, pose, 'anatomy scale')
                assert 0.5 < ratio < 2.0, (identity, pose, 'registration outlier')
                if pose == 'idle': assert frame['source_pose_scale'] == 1.0
            w, h = frame['native_dimensions']
            for key in ('foot', 'core_anchor', 'visual_outlet'):
                x, y = frame[key]
                assert 0 <= x < w and 0 <= y < h, (identity, pose, key)
    for room, frame in manifest['rooms'].items():
        count += audit(frame)
        assert frame['geometry_alignment_verified'] is False, room
        assert frame['runtime_ready'] is False, room
    equipment_root = ROOT.parent / 'equipment/b06_v1'
    equipment = json.loads((equipment_root / 'B06-equipment-v1.manifest.json').read_text())
    assert len(equipment['items']) == 35
    assert equipment['candidate_only'] and not equipment['enabled'] and not equipment['runtime_quality_gate_passed']
    for identity, item in equipment['items'].items():
        source = ROOT.parents[2] / item['texture'].removeprefix('res://')
        assert hashlib.sha256(source.read_bytes()).hexdigest() == item['sha256'], identity
        with Image.open(source) as image:
            assert image.size == (1254, 1254) and image.mode == 'RGBA', identity
        assert item['region'] == [0, 0, 1254, 1254] and item['native_unmodified'], identity
        record = json.loads((ROOT.parents[2] / item['provenance']).read_text())
        assert record['exact_prompt'] and record['sha256'] == item['sha256'], identity
        count += 1
    assert manifest['candidate_only'] and not manifest['runtime_quality_gate_passed']
    print(f'B06 native sources: {count} exact hashes, dimensions, provenance and landmarks passed; runtime gate remains false')

def audit(frame):
    source = ROOT / frame['texture']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == frame['source_sha256'], source
    with Image.open(source) as image:
        assert list(image.size) == frame['native_dimensions'], source
    assert frame['native_unmodified'], source
    provenance = ROOT / frame['provenance']
    assert provenance.is_file(), source
    record = json.loads(provenance.read_text())
    assert record.get('prompt') or record.get('exact_prompt'), provenance
    return 1

if __name__ == '__main__':
    main()
