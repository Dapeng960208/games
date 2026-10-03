"""Verify exact regenerated BO05 native inputs; report source clipping honestly."""
from pathlib import Path
import hashlib
import json
from PIL import Image

PROJECT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
import sys
sys.path.insert(0, str(PROJECT / 'tools/assets'))
from asset_paths import AssetFolder
ROOT = AssetFolder('bosses/b05_poses_v1')

def test_sources():
    active = json.loads((ROOT / 'runtime_manifest.json').read_text(encoding='utf-8'))
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
    print('Active seven poses: exact hashes, native RGBA, zero opaque edge contacts and >=53px corrected margins')

if __name__ == '__main__':
    test_sources()
