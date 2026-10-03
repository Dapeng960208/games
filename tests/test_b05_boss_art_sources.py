"""Verify exact regenerated BO05 native inputs; report source clipping honestly."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'assets/generated/bosses/b05_poses_v1'

def test_sources():
    manifest = json.loads((ROOT / 'BO05_regenerated_manifest.json').read_text())
    assert len(manifest['poses']) == 7
    assert manifest['runtime_quality_gate_passed'] is False
    edges = {}
    for pose in manifest['poses']:
        path = ROOT / pose['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == pose['source_sha256']
        im = Image.open(path)
        assert im.size == (1254, 1254) and im.mode == 'RGBA'
        a = im.getchannel('A')
        assert a.getextrema()[0] == 0 and a.getextrema()[1] >= 250
        assert list(a.point(lambda v: 255 if v >= 32 else 0).getbbox()) == pose['alpha_bbox_ge32']
        core = tuple(pose['absolute_core_px'])
        assert a.getpixel(core) >= 128
        rows = [y for y in range(1254) if a.getpixel((1253, y)) >= 128]
        edges[pose['state']] = {'right_edge_alpha128_pixels': len(rows), 'y_range': [min(rows), max(rows)] if rows else []}
    assert edges['cast-windup']['right_edge_alpha128_pixels'] == 47
    assert edges['root-execute']['right_edge_alpha128_pixels'] == 6
    active = json.loads((ROOT / 'runtime_manifest.json').read_text())
    for pose in active['poses']:
        path = ROOT / pose['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == pose['source_sha256']
        im = Image.open(path)
        assert im.size == (1254,1254) and im.mode == 'RGBA'
        a = im.getchannel('A')
        assert list(a.point(lambda v:255 if v>=32 else 0).getbbox()) == pose['alpha_bbox_ge32']
        for edge in [a.crop((0,0,1,1254)),a.crop((1253,0,1254,1254)),a.crop((0,0,1254,1)),a.crop((0,1253,1254,1254))]:
            assert edge.getextrema()[1] < 128, pose['state']
        if pose['state'] in ['cast-windup','root-execute']:
            x,y,r,b=pose['alpha_bbox_ge32']
            assert min(x,y,1254-r,1254-b)>=53
    print('Active seven poses: exact hashes, native RGBA, zero opaque edge contacts; corrected poses have >=53px solid margins')
    print(json.dumps({'source_integrity': 'passed', 'source_quality_gate': False, 'retained_original_edge_contact': edges}, indent=2))

if __name__ == '__main__':
    test_sources()
