#!/usr/bin/env python3
"""Build and verify enemy variety metadata without writing source PNG pixels.

Requires Pillow. Run with --write to generate the five second-batch region files
and enrich the four approved first-batch files. The default/--check verifies the
checked-in metadata against a deterministic rebuild. Approved first-batch
sampling rectangles and feet are preserved rather than inferred again.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/generated/enemies"
FAMILY = "storybook_2_5d_v1"
ALPHA_THRESHOLD = 32
GRID_SIZE = 8
SECOND_BATCH = (
    ("B01", "reinforcements", ("M01",) * 4 + ("M04",) * 4),
    ("B02", "reinforcements", ("M10",) * 4 + ("M14",) * 4),
    ("B03", "reinforcements", ("M19",) * 8),
    ("B04", "reinforcements", ("M28",) * 8),
    ("B03", "shovels", ("M27",) * 8),
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_source(stem: str) -> tuple[Image.Image, dict]:
    path = ASSETS / f"{stem}.png"
    with Image.open(path) as source:
        if source.mode != "RGBA":
            raise ValueError(f"{path.name}: expected an original RGBA source")
        image = source.copy()
    prompt_path = ASSETS / f"{stem}.prompt.json"
    prompt = json.loads(prompt_path.read_text(encoding="utf-8"))
    return image, {
        "mode": prompt["mode"],
        "prompt_metadata": f"res://assets/generated/enemies/{prompt_path.name}",
        "source_png_sha256": sha256(path.read_bytes()),
        "source_rgba_sha256": sha256(image.tobytes()),
        "source_size": list(image.size),
        "pixel_editing": False,
    }


def measured_edges(alpha: Image.Image, axis: str) -> list[int]:
    """Find the transparent valley nearest each known 8x8 grid division.

    Generation does not produce exactly equal cell widths/heights. Search only
    within 20% of one cell around each expected internal division, using alpha
    coverage rather than source RGB. Ties prefer the expected grid division.
    """
    width, height = alpha.size
    size = width if axis == "x" else height
    coverage = [0] * size
    pixels = alpha.tobytes()
    for y in range(height):
        for x in range(width):
            if pixels[y * width + x] > ALPHA_THRESHOLD:
                coverage[x if axis == "x" else y] += 1
    cell_size = size / GRID_SIZE
    window = round(cell_size * 0.2)
    edges = [0]
    for division in range(1, GRID_SIZE):
        expected = round(division * cell_size)
        candidates = range(max(edges[-1] + 1, expected - window),
                           min(size, expected + window + 1))
        edges.append(min(candidates,
                         key=lambda value: (coverage[value],
                                            abs(value - expected), value)))
    return edges + [size]


def region_hash(image: Image.Image, region: list[int]) -> str:
    x, y, width, height = region
    # Crop is a read-only view for fingerprinting, never a PNG write or recolor.
    crop = image.crop((x, y, x + width, y + height))
    return sha256(f"{width}x{height}:RGBA:".encode("ascii") + crop.tobytes())


def cell_rect(rows: list[int], columns: list[int], row: int, column: int) -> list[int]:
    return [columns[column], rows[row], columns[column + 1] - columns[column],
            rows[row + 1] - rows[row]]


def enrich_entry(entry: dict, image: Image.Image, stem: str, enemy_id: str,
                 row: int, column: int, cell: list[int]) -> dict:
    result = dict(entry)
    result.update({
        "texture": f"res://assets/generated/enemies/{stem}.png",
        "source_family": FAMILY,
        "variant_id": f"{stem}:{enemy_id}:r{row + 1:02d}c{column + 1:02d}",
        "source_cell": cell,
        "pixel_sha256": region_hash(image, result["region"]),
    })
    return result


def summarize(entries: dict[str, list[dict]], image: Image.Image) -> dict:
    count = sum(len(values) for values in entries.values())
    coordinates: set[tuple] = set()
    pixels: set[str] = set()
    touching = 0
    for values in entries.values():
        for entry in values:
            x, y, width, height = entry["region"]
            if (width <= 0 or height <= 0 or x < 0 or y < 0
                    or x + width > image.width or y + height > image.height):
                raise ValueError(f"{entry['variant_id']}: region outside source")
            foot_x, foot_y = entry["foot"]
            if not (x <= foot_x <= x + width and y <= foot_y <= y + height):
                raise ValueError(f"{entry['variant_id']}: foot outside region")
            if foot_y != y + height or entry["source_height"] != height:
                raise ValueError(f"{entry['variant_id']}: wrong bottom baseline/height")
            if not image.getchannel("A").crop((x, y, x + width, y + height)).getbbox():
                raise ValueError(f"{entry['variant_id']}: empty alpha region")
            key = (entry["texture"], *entry["region"])
            coordinates.add(key)
            pixels.add(entry["pixel_sha256"])
            cx, cy, cw, ch = entry["source_cell"]
            touching += int(x == cx or y == cy or x + width == cx + cw
                            or y + height == cy + ch)
    return {
        "body_count": count,
        "counts_by_archetype": {key: len(values) for key, values in entries.items()},
        "unique_texture_regions": len(coordinates),
        "unique_exact_rgba_regions": len(pixels),
        "duplicate_texture_regions": count - len(coordinates),
        "duplicate_exact_rgba_regions": count - len(pixels),
        "foot_and_bounds_checked": count,
        "regions_touching_measured_cell_edge": touching,
        "deduplication": "texture+region and exact original RGBA fingerprint; no perceptual uniqueness claim",
    }


def build_second(biome: str, kind: str, roles: tuple[str, ...]) -> tuple[Path, dict]:
    stem = f"storybook_{biome}_{kind}_v1"
    image, source = load_source(stem)
    alpha = image.getchannel("A")
    columns = measured_edges(alpha, "x")
    rows = measured_edges(alpha, "y")
    entries: dict[str, list[dict]] = {}
    seen_regions: set[tuple] = set()
    seen_pixels: set[tuple] = set()
    removed: list[dict] = []
    for row in range(GRID_SIZE):
        for column, enemy_id in enumerate(roles):
            cell = cell_rect(rows, columns, row, column)
            cx, cy, cw, ch = cell
            # Include every meaningful opaque component inside its measured
            # cell, including detached weapons, wings and hovering accessories.
            mask = alpha.crop((cx, cy, cx + cw, cy + ch)).point(
                lambda value: 255 if value > ALPHA_THRESHOLD else 0)
            bbox = mask.getbbox()
            if bbox is None:
                raise ValueError(f"{stem}: empty cell r{row + 1}c{column + 1}")
            left, top, right, bottom = bbox
            region = [cx + left, cy + top, right - left, bottom - top]
            entry = enrich_entry({
                "region": region,
                "foot": [cx + (left + right) / 2, cy + bottom],
                "source_height": bottom - top,
                "full_color": True,
            }, image, stem, enemy_id, row, column, cell)
            region_key = (enemy_id, *region)
            pixel_key = (enemy_id, entry["pixel_sha256"])
            if region_key in seen_regions or pixel_key in seen_pixels:
                removed.append({"variant_id": entry["variant_id"],
                                "reason": "duplicate original texture region or exact RGBA"})
                continue
            seen_regions.add(region_key)
            seen_pixels.add(pixel_key)
            entries.setdefault(enemy_id, []).append(entry)
    source["grid_topology"] = [GRID_SIZE, GRID_SIZE]
    source["grid_measurement"] = "minimum alpha coverage within 20% of expected grid division"
    source["region_policy"] = "all alpha > 32 pixels in measured cell; original RGBA unchanged"
    source["foot_policy"] = "center x and exclusive alpha bottom y of tight region"
    document = {
        "texture": f"res://assets/generated/enemies/{stem}.png",
        "biome_id": biome,
        "source_family": FAMILY,
        "full_color": True,
        "alpha_threshold": ALPHA_THRESHOLD,
        "entries": entries,
        "skill_icons": {},
        "row_edges": rows,
        "column_edges": columns,
        "source": source,
        "validation": summarize(entries, image),
        "deduplicated_cells": removed,
    }
    return ASSETS / f"{stem}.regions.json", document


def enrich_first(biome: str) -> tuple[Path, dict]:
    stem = f"storybook_{biome}_variants_v1"
    path = ASSETS / f"{stem}.regions.json"
    document = json.loads(path.read_text(encoding="utf-8"))
    image, source = load_source(stem)
    rows, columns = document["row_edges"], document["column_edges"]
    body_rows = 7 if biome == "B04" else 8
    ids = list(document["entries"])
    if len(ids) != 9 or len(rows) != body_rows + 2 or len(columns) != 10:
        raise ValueError(f"{stem}: approved first-batch topology changed")
    for column, enemy_id in enumerate(ids):
        values = document["entries"][enemy_id]
        if len(values) != body_rows:
            raise ValueError(f"{stem}:{enemy_id}: wrong approved variant count")
        document["entries"][enemy_id] = [
            enrich_entry(entry, image, stem, enemy_id, row, column,
                         cell_rect(rows, columns, row, column))
            for row, entry in enumerate(values)
        ]
    if set(document["skill_icons"]) != set(ids):
        raise ValueError(f"{stem}: expected one approved skill icon per archetype")
    for enemy_id, region in document["skill_icons"].items():
        x, y, width, height = region
        if (x < 0 or y < rows[-2] or width <= 0 or height <= 0
                or x + width > image.width or y + height > image.height):
            raise ValueError(f"{stem}:{enemy_id}: skill icon outside final row")
    document["source_family"] = FAMILY
    document["full_color"] = True
    source["grid_topology"] = [9, body_rows + 1]
    source["body_rows"] = body_rows
    source["skill_icon_row"] = body_rows + 1
    source["region_policy"] = "preserved approved first-batch sampling rectangles"
    source["foot_policy"] = "preserved approved region center x and bottom baseline y"
    document["source"] = source
    document["validation"] = summarize(document["entries"], image)
    document["validation"]["skill_icon_count"] = len(document["skill_icons"])
    return path, document


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="write metadata only")
    mode.add_argument("--check", action="store_true", help="verify checked-in metadata (default)")
    args = parser.parse_args()
    source_hashes = {path: sha256(path.read_bytes())
                     for path in ASSETS.glob("storybook_B0[1-4]*_v1.png")}
    documents = [enrich_first(f"B0{index}") for index in range(1, 5)]
    documents += [build_second(*spec) for spec in SECOND_BATCH]
    all_coordinates: set[tuple] = set()
    all_pixels: set[str] = set()
    totals: Counter = Counter()
    missing = []
    for path, document in documents:
        rendered = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
        if args.write:
            path.write_text(rendered, encoding="utf-8")
        elif not path.exists() or json.loads(path.read_text(encoding="utf-8")) != document:
            missing.append(path.name)
        summary = document["validation"]
        print(json.dumps({"atlas": path.name, **summary,
                          "row_edges": document["row_edges"],
                          "column_edges": document["column_edges"]}, ensure_ascii=False))
        totals.update(summary["counts_by_archetype"])
        for values in document["entries"].values():
            for entry in values:
                all_coordinates.add((entry["texture"], *entry["region"]))
                all_pixels.add(entry["pixel_sha256"])
    for path, original_hash in source_hashes.items():
        if sha256(path.read_bytes()) != original_hash:
            raise ValueError(f"Source PNG changed: {path.name}")
    print(json.dumps({"total_body_variants": sum(totals.values()),
                      "counts_by_archetype": dict(sorted(totals.items())),
                      "unique_texture_regions": len(all_coordinates),
                      "unique_exact_rgba_regions": len(all_pixels),
                      "source_pngs_unchanged": len(source_hashes)}, ensure_ascii=False))
    if missing:
        print("Metadata requires --write: " + ", ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
