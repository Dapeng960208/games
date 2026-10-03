"""Separate the current independent A/B SE sources without redrawing/upscaling.

Requires the already-bundled Pillow/numpy runtime. Source sheets are preserved.
Outputs are review assets only: the production combat_clips gate stays disabled.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
HERO_IDS = {"warrior": "CH01", "gunner": "CH02", "mage": "CH03"}


def review_preview(cell, foot, label):
    background = Image.new("RGBA", cell.size, "#f4efdf")
    draw = ImageDraw.Draw(background)
    for y in range(0, cell.height, 32):
        for x in range(0, cell.width, 32):
            if (x // 32 + y // 32) % 2:
                draw.rectangle((x, y, x + 31, y + 31), fill="#d9e1de")
    background.alpha_composite(cell)
    fx, fy = foot
    draw.line((fx - 14, fy, fx + 14, fy), fill="#d52943", width=2)
    draw.line((fx, fy - 14, fx, fy + 14), fill="#d52943", width=2)
    draw.text((12, 12), label, fill="#282535")
    return background.convert("RGB")


def components(mask):
    """Run-length connected components; avoids a dependency for a one-off sheet."""
    spans, parents, previous = [], [], []

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for y, row in enumerate(mask):
        changes = np.diff(np.pad(row.astype(np.int8), (1, 1)))
        current = []
        for left, right in zip(np.where(changes == 1)[0], np.where(changes == -1)[0]):
            index = len(spans)
            spans.append((y, int(left), int(right)))
            parents.append(index)
            current.append(index)
            for prior in previous:
                _, a, b = spans[prior]
                if b < left:
                    continue
                if a > right:
                    break
                root_a, root_b = find(index), find(prior)
                if root_a != root_b:
                    parents[root_b] = root_a
        previous = current
    groups = {}
    for index, (y, left, right) in enumerate(spans):
        group = groups.setdefault(find(index), [0, mask.shape[1], mask.shape[0], 0, 0])
        group[0] += right - left
        group[1] = min(group[1], left)
        group[2] = min(group[2], y)
        group[3] = max(group[3], right)
        group[4] = max(group[4], y + 1)
    labels = np.zeros(mask.shape, dtype=np.int32)
    for index, (y, left, right) in enumerate(spans):
        labels[y, left:right] = find(index) + 1
    return labels, {key + 1: value for key, value in groups.items()}


def separate_quads(alpha):
    labels, groups = components(alpha >= 8)
    majors = [(key, stats) for key, stats in groups.items() if stats[0] >= 10000]
    assert len(majors) == 4, "source must have exactly four separate major bodies; regenerate touching poses"
    by_y = sorted(majors, key=lambda item: item[1][2])
    ordered = sorted(by_y[:2], key=lambda item: item[1][1]) + sorted(by_y[2:], key=lambda item: item[1][1])
    assignments = {key: index + 1 for index, (key, _) in enumerate(ordered)}
    for key, stats in groups.items():
        if key in assignments:
            continue
        _, left, top, right, bottom = stats
        cx, cy = (left + right) / 2, (top + bottom) / 2
        distances = []
        for _, (_, a, b, c, d) in ordered:
            distances.append(max(a - cx, 0, cx - c) ** 2 + max(b - cy, 0, cy - d) ** 2)
        assignments[key] = int(np.argmin(distances)) + 1
    owners = np.zeros_like(labels, dtype=np.uint8)
    for key, owner in assignments.items():
        owners[labels == key] = owner
    assert np.array_equal(owners > 0, alpha >= 8)
    return [owners == index for index in range(1, 5)]


def prepare(role):
    """Two four-frame source sheets: component masks, no ambiguous seam guessing."""
    folder = ROOT / "assets/characters" / role / "animations"
    output = ROOT / "tools/godot/art_preview" / role / "split_native"
    output.mkdir(parents=True, exist_ok=True)
    crops, landmarks, frames = [], [], []
    source_records = []
    for part in ["a", "b"]:
        source = folder / f"basic_southeast_{part}.png"
        provenance = json.loads(source.with_suffix(".generation.json").read_text(encoding="utf-8"))
        annotation = provenance["landmark_annotation"]
        annotated = sorted(annotation["frames"], key=lambda frame: frame["frame_index"])
        assert len(annotated) == 4
        image = np.array(Image.open(source).convert("RGBA"))
        alpha = image[:, :, 3]
        masks = separate_quads(alpha)
        source_records.append({"file": source.name, "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                               "actual_dimensions": list(Image.open(source).size), "scale": 1,
                               "landmark_provenance": source.with_suffix(".generation.json").name,
                               "alpha8_source_pixels": int((alpha >= 8).sum()),
                               "major_independent_components": 4,
                               "outer_edge_alpha128_pixels": int(sum((edge >= 128).sum() for edge in
                                   [alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]])),
                               "outer_edge_alpha8_pixels": int(sum((edge >= 8).sum() for edge in
                                   [alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]])),
                               "landmark_accuracy_px": annotation.get("position_accuracy_px", 5),
                               "occluded_boot_accuracy_px": annotation.get("occluded_boot_accuracy_px", 35)})
        cleaned = image.copy()
        cleaned[alpha < 8] = 0
        retained = 0
        for mask, landmark in zip(masks, annotated):
            pixels = cleaned.copy()
            pixels[~mask] = 0
            body = Image.fromarray(pixels)
            box = body.getbbox()
            assert box is not None
            crop = body.crop(box)
            crops.append((crop, box))
            landmarks.append(landmark)
            retained += int((np.array(crop)[:, :, 3] >= 8).sum())
        assert retained == int((alpha >= 8).sum()), "every retained pixel must belong to exactly one frame"
    feet = [[round(x), round(y)] for x, y in (frame["foot_anchor_xy"] for frame in landmarks)]
    foot_x = max(point[0] - box[0] for point, (_, box) in zip(feet, crops)) + 16
    foot_y = max(point[1] - box[1] for point, (_, box) in zip(feet, crops)) + 16
    cell_size = (768, 768)
    assert all(foot_x + box[2] - point[0] + 16 <= cell_size[0] and
               foot_y + box[3] - point[1] + 16 <= cell_size[1]
               for point, (_, box) in zip(feet, crops)), "source cannot fit native review cells without clipping"
    extents = [max(point[1] for point in frame["boot_bottom_points"]) - frame["hair_top_y"] + 1
               for frame in landmarks]
    reference_indices = [0, 7]
    reference_heights = [extents[index] for index in reference_indices]
    target_height = min(reference_heights)
    preview_scales = [target_height / height for height in reference_heights]
    for source, index, height, scale in zip(source_records, reference_indices, reference_heights, preview_scales):
        source.update({"standing_reference_frame": f"SE_{index}", "reference_body_height": height,
                       "reference_measurement_verified": False, "fixed_reference_preview_scale": scale})
    atlases = [Image.new("RGBA", (1536, 1536)) for _ in range(2)]
    previews, reference_previews = [], []
    for index, ((crop, box), point, landmark) in enumerate(zip(crops, feet, landmarks)):
        cell = Image.new("RGBA", cell_size)
        cell.paste(crop, (foot_x + box[0] - point[0], foot_y + box[1] - point[1]))
        ox, oy = index % 2 * 768, index % 4 // 2 * 768
        part = "a" if index < 4 else "b"
        atlases[index // 4].paste(cell, (ox, oy))
        risks = []
        if landmark.get("occluded_boot", False):
            risks.append("occluded boot anchor is an estimate, not a measured sole")
        if extents[index] < 448:
            risks.append("visible hair-to-sole extent below 448px; retain natural crouch scale, never per-frame enlarge")
        frames.append({"name": f"SE_{index}", "texture_file": f"basic_southeast_aligned_{part}.png",
                       "region": [ox, oy, *cell_size], "foot": [ox + foot_x, oy + foot_y],
                       "source_file": f"basic_southeast_{part}.png", "source_foot": landmark["foot_anchor_xy"],
                       "source_bounds_xywh": [box[0], box[1], box[2] - box[0], box[3] - box[1]],
                       "source_hair_top_y": landmark["hair_top_y"],
                       "source_boot_bottom_points": landmark["boot_bottom_points"],
                       "visible_body_extent": extents[index], "body_height": reference_heights[index // 4],
                       "landmark_accuracy_px": landmark.get("position_accuracy_px",
                           source_records[index // 4]["occluded_boot_accuracy_px"]
                           if landmark.get("occluded_boot", False) else source_records[index // 4]["landmark_accuracy_px"]),
                       "landmark_verified": False, "risks": risks})
        previews.append(review_preview(cell, (foot_x, foot_y), f"{index+1}: native 1:1, visible body {extents[index]}px"))
        scale = preview_scales[index // 4]
        scaled = cell.resize((round(768 * scale), round(768 * scale)), Image.Resampling.LANCZOS)
        normalized = Image.new("RGBA", cell_size)
        normalized.paste(scaled, (round(foot_x * (1 - scale)), round(foot_y * (1 - scale))))
        reference_previews.append(review_preview(normalized, (foot_x, foot_y),
                                                 f"{index+1}: source {part.upper()} fixed reference scale {scale:.4f}"))
    for part, atlas in zip(["a", "b"], atlases):
        atlas.save(output / f"basic_southeast_aligned_{part}.png")
    data = {"schema_version": 2, "hero_id": HERO_IDS[role], "direction": "SE", "action": "basic",
            "enabled": False, "production_ready": False, "status": "isolated_component_review_only",
            "reason": "one direction/action only; natural scale/anchor and complete-family approval outstanding",
            "sources": source_records, "atlas_dimensions_each": [1536, 1536], "cell_dimensions": list(cell_size),
            "review_texture_directory": output.relative_to(ROOT).as_posix(),
            "scale": 1, "upscaled": False, "native_2k_requirement_met": False,
            "source_reference_body_heights": dict(zip(["a", "b"], reference_heights)),
            "body_extent_excludes": "weapons, muzzle flashes, hats, capes and detached ornaments",
            "body_extent_measurement": "manual hair-top to farther sole-contact point; a visible/estimated anatomy extent, not an opaque texture bounding box",
            "body_scale_rule": "native atlases are 1:1; each source uses one fixed standing reference for world scaling; crouch extents never drive per-frame resizing",
            "reference_preview": {"target_body_height": target_height, "source_fixed_scales": dict(zip(["a", "b"], preview_scales)),
                                  "upscaled": False, "purpose": "continuity review only; originals and native atlases unchanged"},
            "processing": "independent alpha8 connected bodies; detached pixels assigned to closest body bounds; alpha<8 cleared and hidden RGB zeroed; manual ground anchor alignment; no redraw",
            "landmark_quality": "manual source annotations are unverified estimates; verify soles before production",
            "start_end_visible_scale_ratio": round(extents[7] / extents[0], 4),
            "phases": {"windup": [0, 1, 2], "release": [3, 4], "recovery": [5, 6, 7]}, "frames": frames}
    (folder / "basic_southeast_split_review.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    preview_folder = ROOT / "tools/godot/art_preview" / role
    preview_folder.mkdir(parents=True, exist_ok=True)
    contact = Image.new("RGB", (3072, 1536))
    for index, preview in enumerate(previews):
        contact.paste(preview, (index % 4 * 768, index // 4 * 768))
    contact.save(preview_folder / "basic_southeast_split_aligned.png")
    previews[0].save(preview_folder / "basic_southeast_split_aligned.gif", save_all=True,
                     append_images=previews[1:], duration=[100, 100, 100, 60, 60, 100, 100, 100], loop=0)
    normalized_contact = Image.new("RGB", (3072, 1536))
    for index, preview in enumerate(reference_previews):
        normalized_contact.paste(preview, (index % 4 * 768, index // 4 * 768))
    normalized_contact.save(preview_folder / "basic_southeast_reference_scale.png")
    reference_previews[0].save(preview_folder / "basic_southeast_reference_scale.gif", save_all=True,
                              append_images=reference_previews[1:], duration=[100, 100, 100, 60, 60, 100, 100, 100], loop=0)
    print(f"{role}: two native 1536-square review atlases; body extents {extents}; start/end ratio {data['start_end_visible_scale_ratio']}")


if __name__ == "__main__":
    preview_root = ROOT / "tools/godot/art_preview"
    preview_root.mkdir(parents=True, exist_ok=True)
    (preview_root / ".gdignore").touch()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role", choices=[*HERO_IDS, "all"], default="all")
    parser.add_argument("--split", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    selected = args.role
    for role in HERO_IDS if selected == "all" else [selected]:
        prepare(role)
