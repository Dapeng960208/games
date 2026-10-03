"""Validate delivered native B10 artwork; never modify source pixels."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / 'assets/levels/b10'
errors = []
checks = 0

def check(ok, label):
    global checks
    checks += 1
    if not ok:
        errors.append(label)

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

resources = read(ROOT / 'assets/manifest.json')['resources']

def resolve(identifier):
    return ROOT / resources.get(identifier.removeprefix('asset://'), identifier).removeprefix('res://')

def pixels(path, size, digest):
    with Image.open(path) as image:
        check(list(image.size) == list(size), f'native dimensions {path}')
    check(hashlib.sha256(path.read_bytes()).hexdigest().lower() == digest.lower(), f'original source bytes {path}')

backgrounds = set()
for room in ['l55', 'l56', 'l57', 'l58', 'l59', 'l60', 'bo10']:
    folder = PACK / 'rooms' / room
    environment = read(folder / 'background/environment.json')
    detail = read(folder / 'detail/manifest.json')
    source = resolve(detail['source_texture'])
    backgrounds.add(source)
    pixels(source, detail['source_size'], detail['source_sha256'])
    placement = environment['placement_normalized_rect']
    width, height = detail['source_size']
    sx = 2800 * .58 / (placement[2] * width)
    sy = 1800 * .58 / (placement[3] * height)
    check(abs(sx - sy) < .00001, f'uniform background mapping {room}')
    check(len(detail['tiles']) == 6, f'six details {room}')
    for tile in detail['tiles']:
        pixels(resolve(tile['texture']), tile['native_size'], tile['sha256'])
        rect, native = tile['source_rect'], tile['native_size']
        factor = max(rect[2] * sx / native[0], rect[3] * sy / native[1])
        check(factor * .85 * 2 <= 1, f'2K native detail pixel budget {room}/{tile["id"]}')
check(len(backgrounds) == 7, 'seven independent room paintings')

actors = list((PACK / 'enemies').glob('*/body.png')) + list((PACK / 'bosses').glob('*/body.png'))
objects = list((PACK / 'decorations').glob('*.png'))
check(len(actors) == 25 and len(objects) == 4, '18 monsters, seven dragons and four independent props')
for image in actors + objects:
    paths = [image.with_name(image.stem + '.prompt.provenance.json'), image.with_name(image.stem + '.provenance.json'), image.with_name('provenance.json'), image.with_name('prompt.provenance.json')]
    metadata = read(next(path for path in paths if path.is_file()))
    metadata = metadata.get('assets', {}).get(image.stem, metadata)
    pixels(image, metadata.get('source_size', metadata.get('native_dimensions', metadata.get('actual_dimensions'))), metadata['sha256'])
    with Image.open(image) as source:
        check(source.getchannel('A').getextrema() == (0, 255), f'native transparency {image}')
        x, y = metadata['actual_foot_px']
        check(0 <= x < source.width and 0 <= y < source.height, f'source ground foot {image}')
        check(0 < metadata['effective_body_height_px'] <= source.height, f'effective source height {image}')

equipment = read(PACK / 'equipment/manifest.json')['items']
check(len(equipment) == 36 and 'B10-EASTER-RING' in equipment, '35 natural illustrations plus unique ring')
for identity, item in equipment.items():
    pixels(resolve(item['texture']), item['native_dimensions'], item['sha256'])
    x, y, w, h = item['region']
    check(x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= item['native_dimensions'][0] and y + h <= item['native_dimensions'][1], f'valid native gear region {identity}')
    check(min(w, h) >= 296, f'2K inventory pixel budget {identity}')
print(f'B10 native artwork: {checks} checks, {len(errors)} failures')
for error in errors:
    print(error)
raise SystemExit(1 if errors else 0)
