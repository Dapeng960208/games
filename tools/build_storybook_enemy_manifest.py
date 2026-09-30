"""Read source alpha and write atlas metadata; never alter generated PNG pixels."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
path = root / "assets/generated/enemies/storybook_B01_bodies_v1.png"
image = Image.open(path).convert("RGBA")
width, height = image.size
alpha = image.getchannel("A")
catalog = json.loads((root / "data/enemies.json").read_text(encoding="utf-8"))
ids = [f"M{index:02}" for index in range(1, 10)] + ["BO01"]
entries = {}
diagnostics = []
for index, identity in enumerate(ids):
    x0, x1 = round(index % 5 * width / 5), round((index % 5 + 1) * width / 5)
    y0, y1 = round(index // 5 * height / 2), round((index // 5 + 1) * height / 2)
    crop = alpha.crop((x0, y0, x1, y1))
    bbox = crop.point(lambda value: 255 if value >= 16 else 0).getbbox()
    if bbox is None:
        raise ValueError(f"empty {identity}")
    bx0, by0 = max(x0, x0 + bbox[0] - 2), max(y0, y0 + bbox[1] - 2)
    bx1, by1 = min(x1, x0 + bbox[2] + 2), min(y1, y0 + bbox[3] + 2)
    region = [bx0, by0, bx1 - bx0, by1 - by0]
    radius = 54 if identity == "BO01" else catalog["enemies"][identity]["navigation_radius"]
    native_height = min(220, max(170, radius * 3.45)) if identity == "BO01" else min(88, max(66, radius * 3.8))
    entries[identity] = {"region": region, "foot": [(bx0 + bx1) / 2, by1],
        "source_height": region[3], "native_height": native_height,
        "collision_radius": radius, "facing": "right", "full_color": True}
    diagnostics.append({"id": identity, "alpha16_bbox": list(bbox),
        "transparent_margins": [bbox[0], bbox[1], x1-x0-bbox[2], y1-y0-bbox[3]]})
manifest = {"schema_version": 1, "texture": "res://assets/generated/enemies/storybook_B01_bodies_v1.png",
    "source_family": "storybook_2_5d_v1", "biome_id": "B01", "visual_clan": "辉砂虫族",
    "image_size": [width, height], "grid": {"columns": 5, "rows": 2},
    "entries": entries, "alpha_threshold": 16, "diagnostics": diagnostics,
    "pixel_processing": "metadata sampling only; source RGBA PNG unchanged"}
path.with_suffix(".regions.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"size": [width, height], "entries": len(entries), "minimum_margin": min(min(item["transparent_margins"]) for item in diagnostics)}, ensure_ascii=False))
