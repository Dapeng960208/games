"""Validate measured original pose sources and register an atomic shared family.

No pixels are resized or repainted. Runtime aligns each measured sole anchor and
uses one standing reference per direction, including crouched and airborne poses.
Run with the bundled Python/Pillow runtime. Default is a read-only source check.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ROLES = {"warrior": "CH01", "gunner": "CH02", "mage": "CH03"}
DIRECTIONS = ("E", "SE", "S", "SW", "W", "NW", "N", "NE")
POSES = ("idle", "walk_left", "walk_right", "basic_windup", "basic_release", "basic_recovery", "dash", "guard_cast")
ANCHORS = ("foot", "head", "grip", "muzzle", "left_hand", "right_hand", "wand", "pet")


def pack_direction(role, direction, sources, output):
    """Reuse the existing alpha-component separator, preserving native pixels."""
    if direction not in DIRECTIONS:
        raise ValueError(f"Unsupported runtime direction: {direction}")
    import numpy as np
    sources, output = Path(sources).resolve(), Path(output).resolve()
    helper_spec = importlib.util.spec_from_file_location("role_pose_separator", ROOT / "tools/maintenance/prepare_role_action_samples.py")
    helper = importlib.util.module_from_spec(helper_spec)
    helper_spec.loader.exec_module(helper)
    frames, originals, crops, source_records = [], [], [], []
    for bank_index, bank in enumerate(("a", "b")):
        stem = f"poses_{direction.lower()}_{bank}"
        source = sources / f"{stem}.png"
        metadata = json.loads(source.with_suffix(".generation.json").read_text(encoding="utf-8"))
        measured = metadata["frames"]
        if len(measured) != 4:
            raise ValueError(f"{stem}: four measured poses required before component packing")
        with Image.open(source) as image:
            pixels = np.array(image.convert("RGBA"))
            dimensions = list(image.size)
        alpha = pixels[:, :, 3]
        masks = helper.separate_quads(alpha)
        if any("component_seed" in frame for frame in measured):
            ordered, used = [], set()
            for frame in measured:
                if not coordinates(frame.get("component_seed"), 2):
                    raise ValueError(f"{stem}: four interior component seeds required")
                sx, sy = (round(value) for value in frame["component_seed"])
                if not (0 <= sx < alpha.shape[1] and 0 <= sy < alpha.shape[0]):
                    raise ValueError(f"{stem}: component seed outside source")
                owners = [index for index, mask in enumerate(masks) if mask[sy, sx]]
                if len(owners) != 1 or owners[0] in used:
                    raise ValueError(f"{stem}: each measured pose must own a unique opaque component seed")
                used.add(owners[0])
                ordered.append(masks[owners[0]])
            masks = ordered
        cleaned = pixels.copy()
        cleaned[alpha < 8] = 0
        retained = 0
        for index, (mask, frame) in enumerate(zip(masks, measured)):
            name = POSES[bank_index * 4 + index]
            if frame.get("name") != name:
                raise ValueError(f"{stem}: source order differs from {name}")
            for anchor in ANCHORS:
                if anchor not in frame and anchor not in ANCHORS[:4]:
                    continue
                if not coordinates(frame.get(anchor), 2):
                    raise ValueError(f"{stem}/{name}: measured {anchor} required")
            isolated = cleaned.copy()
            isolated[~mask] = 0
            body = Image.fromarray(isolated)
            bounds = body.getbbox()
            if bounds is None:
                raise ValueError(f"{stem}/{name}: empty independent body")
            crop = body.crop(bounds)
            retained += int((np.array(crop)[:, :, 3] >= 8).sum())
            crops.append((crop, bounds))
            originals.append(frame)
            frames.append({"name": name, "body_height": frame["body_height"]})
        if retained != int((alpha >= 8).sum()):
            raise ValueError(f"{stem}: source pixels were lost or duplicated")
        source_records.append({"metadata": metadata, "source": source, "dimensions": dimensions, "retained_pixels": retained})
    feet = [[round(value) for value in frame["foot"]] for frame in originals]
    extents = []
    for (_, box), frame in zip(crops, originals):
        points = [frame[anchor] for anchor in ANCHORS if anchor in frame]
        extents.append((min(box[0], *(point[0] for point in points)), min(box[1], *(point[1] for point in points)), max(box[2], *(point[0]+1 for point in points)), max(box[3], *(point[1]+1 for point in points))))
    foot_x = math.ceil(max(point[0]-box[0] for point, box in zip(feet, extents))) + 16
    foot_y = math.ceil(max(point[1]-box[1] for point, box in zip(feet, extents))) + 16
    width = math.ceil((foot_x + max(box[2]-point[0] for point, box in zip(feet, extents)) + 16)/64)*64
    height = math.ceil((foot_y + max(box[3]-point[1] for point, box in zip(feet, extents)) + 16)/64)*64
    if width > 1024 or height > 1024:
        raise ValueError(f"{role}/{direction}: native foot-aligned poses exceed 2048 atlas; artwork layout repair required")
    atlases = [Image.new("RGBA", (width*2, height*2)) for _ in range(2)]
    for index, ((crop, box), original, foot, frame) in enumerate(zip(crops, originals, feet, frames)):
        ox, oy = (index%2)*width, (0 if index%4 < 2 else height)
        shift_x, shift_y = ox+foot_x-foot[0], oy+foot_y-foot[1]
        atlases[index//4].paste(crop, (round(box[0]+shift_x), round(box[1]+shift_y)))
        frame["region"] = [ox, oy, width, height]
        for anchor in ANCHORS:
            if anchor in original:
                frame[anchor] = [original[anchor][0]+shift_x, original[anchor][1]+shift_y]
        frame["source_frame"] = original
    output.mkdir(parents=True, exist_ok=True)
    for bank_index, bank in enumerate(("a", "b")):
        stem = f"poses_{direction.lower()}_{bank}"
        record = source_records[bank_index]
        atlases[bank_index].save(output / f"{stem}.png")
        metadata = dict(record["metadata"])
        metadata.update({"frames": frames[bank_index*4:bank_index*4+4], "native_source_dimensions": record["dimensions"], "packed_dimensions": [width*2, height*2], "raw_source": record["source"].relative_to(ROOT).as_posix(), "raw_source_sha256": hashlib.sha256(record["source"].read_bytes()).hexdigest(), "pixel_scale": 1, "upscaled": False, "processing": "Existing independent alpha8 components; alpha<8/hidden RGB cleared, sole anchors aligned by integer translation. No redraw, rotation, mirroring, pixel resizing or pose fitting.", "retained_alpha8_pixels": record["retained_pixels"], "standing_reference_body_height": originals[0]["body_height"]})
        (output / f"{stem}.generation.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")


def coordinates(value, count):
    return isinstance(value, list) and len(value) == count and all(
        isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) for v in value
    )


def review_contacts(family, directory, output):
    """Show actual standing scale and sole alignment; these are not screenshots."""
    entries = []
    for direction, group in family["directions"].items():
        scale = 224 / group["reference_body_height"]
        for name in ("idle", "basic_release"):
            frame = next(frame for frame in group["frames"] if frame["name"] == name)
            bank = "a" if name == "idle" else "b"
            with Image.open(directory / f"poses_{direction.lower()}_{bank}.png") as image:
                x, y, width, height = frame["region"]
                crop = image.crop((x, y, x+width, y+height))
                box = crop.getbbox()
                body = crop.crop(box)
            left, top = (x+box[0]-frame["foot"][0])*scale, (y+box[1]-frame["foot"][1])*scale
            entries.append({"direction": direction, "name": name, "body": body, "scale": scale, "reference": group["reference_body_height"], "left": left, "top": top, "right": left+body.width*scale, "bottom": top+body.height*scale})
    min_x, min_y = min(entry["left"] for entry in entries), min(entry["top"] for entry in entries)
    width = math.ceil((max(entry["right"] for entry in entries)-min_x+40)/32)*32
    height = math.ceil((max(entry["bottom"] for entry in entries)-min_y+76)/32)*32
    foot_x, foot_y = 24-min_x, 48-min_y
    try:
        font = ImageFont.truetype("arial.ttf", 17)
    except OSError:
        font = ImageFont.load_default()
    output.mkdir(parents=True, exist_ok=True)
    for name in ("idle", "basic_release"):
        selected = [entry for entry in entries if entry["name"] == name]
        contact = Image.new("RGB", (width*4, height*math.ceil(len(selected)/4)), "#eee9df")
        draw = ImageDraw.Draw(contact)
        for index, entry in enumerate(selected):
            x, y = (index%4)*width, (index//4)*height
            body = entry["body"].resize((round(entry["body"].width*entry["scale"]), round(entry["body"].height*entry["scale"])), Image.Resampling.LANCZOS)
            contact.paste(body, (round(x+foot_x+entry["left"]), round(y+foot_y+entry["top"])), body)
            draw.text((x+12,y+7), entry["direction"]+" | "+("idle" if name == "idle" else "release"), font=font, fill="#233b66")
            draw.text((x+12,y+26), "standing source "+str(entry["reference"])+"px", font=font, fill="#514253")
            fx, fy = x+foot_x, y+foot_y
            draw.line((fx-10,fy,fx+10,fy), fill="#b75b50", width=1)
            draw.line((fx,fy-5,fx,fy+5), fill="#b75b50", width=1)
            draw.rectangle((x,y,x+width-1,y+height-1), outline="#bcb1a3")
        contact.save(output / f"qa_{len(selected)}dir_{name}_224px.png")


def build(role, source_directory=None, directions_to_check=DIRECTIONS):
    hero = ROLES[role]
    sources = Path(source_directory) if source_directory else ROOT / "assets" / "characters" / role / "animations" / "runtime_sources"
    directions = {}
    native_sizes = {}
    for direction in directions_to_check:
        if direction not in DIRECTIONS:
            raise ValueError(f"Unsupported runtime direction: {direction}")
        frames = []
        reference = None
        for bank_index, bank in enumerate(("a", "b")):
            stem = f"poses_{direction.lower()}_{bank}"
            source = sources / f"{stem}.png"
            metadata = json.loads((sources / f"{stem}.generation.json").read_text(encoding="utf-8"))
            measured = metadata["frames"]
            if not isinstance(measured, list) or len(measured) != 4:
                raise ValueError(f"{stem}: expected four measured original poses")
            with Image.open(source) as image:
                if image.mode != "RGBA" or image.width > 2048 or image.height > 2048:
                    raise ValueError(f"{stem}: expected RGBA source within 2048 atlas limit")
                alpha = image.getchannel("A")
                minimum_alpha, maximum_alpha = alpha.getextrema()
                if minimum_alpha != 0 or maximum_alpha < 128:
                    raise ValueError(f"{stem}: true transparent exterior and visible artwork required")
                native_sizes[stem] = metadata.get("native_source_dimensions", list(image.size))
                used = []
                for index, frame in enumerate(measured):
                    name = POSES[bank_index * 4 + index]
                    if frame.get("name") != name or not coordinates(frame.get("region"), 4):
                        raise ValueError(f"{stem}: incorrect pose identity or region for {name}")
                    x, y, width, height = frame["region"]
                    if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > image.width or y + height > image.height:
                        raise ValueError(f"{stem}/{name}: region exceeds the unchanged source")
                    rectangle = (x, y, x + width, y + height)
                    if alpha.crop(rectangle).getbbox() is None:
                        raise ValueError(f"{stem}/{name}: empty source pose")
                    if any(x < old[2] and old[0] < x + width and y < old[3] and old[1] < y + height for old in used):
                        raise ValueError(f"{stem}/{name}: source poses overlap")
                    used.append(rectangle)
                    for anchor in ("foot", "head", "grip", "muzzle", "left_hand", "right_hand", "wand", "pet"):
                        if anchor not in frame and anchor not in ("foot", "head", "grip", "muzzle"):
                            continue
                        point = frame.get(anchor)
                        if not coordinates(point, 2) or not (x <= point[0] < x + width and y <= point[1] < y + height):
                            raise ValueError(f"{stem}/{name}: invalid measured {anchor}")
                    measured_height = frame.get("body_height")
                    if isinstance(measured_height, bool) or not isinstance(measured_height, (int, float)) or not math.isfinite(measured_height) or measured_height <= 0:
                        raise ValueError(f"{stem}/{name}: actual anatomical body height required")
                    if name == "idle":
                        reference = measured_height
                        if reference < 256:
                            raise ValueError(f"{stem}: standing native density below minimum 256 pixels")
                    frame = dict(frame)
                    frame["texture"] = f"asset://heroes/{hero.lower()}_{stem}.png"
                    frames.append(frame)
        directions[direction] = {"reference_body_height": reference, "frames": frames}
    return {
        "schema_version": 3,
        "hero_id": hero,
        "enabled": False,
        "production_ready": False,
        "directions": directions,
        "source_native_sizes": native_sizes,
        "native_2k_sources_met": all(size[0] >= 2048 and size[1] >= 2048 for size in native_sizes.values()),
        "registration": "Measured original pixels; runtime sole=(0,8), fixed standing scale per authored direction; no body rotation or mirroring.",
        "limitations": ["64 shared authored body poses in eight directions, not twelve independent eight-frame skill animations.", "Individual skills retain production effect timelines and use explicit basic, guard/cast or travel body categories.", "Manual anatomy/weapon anchors require graphical verification."],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role", choices=ROLES, required=True)
    parser.add_argument("--source-directory", type=Path, help="read ignored staged sources before importing into assets")
    parser.add_argument("--direction", choices=DIRECTIONS, help="check one A/B pair; partial checks cannot write or enable family JSON")
    parser.add_argument("--pack", action="store_true", help="separate original alpha components and align native pose anchors before registration")
    parser.add_argument("--preview", action="store_true", help="write ignored source-scale review contacts; never game screenshots")
    parser.add_argument("--write", action="store_true", help="write complete measured family JSON")
    parser.add_argument("--enable", action="store_true", help="enable only after all source artwork is visually approved")
    args = parser.parse_args()
    if args.enable and not args.write:
        parser.error("--enable requires --write")
    if args.direction and args.write:
        parser.error("a partial directional check cannot write or enable a family")
    production_sources = ROOT / "assets" / "characters" / args.role / "animations" / "runtime_sources"
    production_packed = production_sources.parent / "runtime"
    if args.write and args.source_directory and args.source_directory.resolve() not in (production_sources.resolve(), production_packed.resolve()):
        parser.error("staged sources are read-only; copy approved sources into assets before writing a family")
    source_directory = args.source_directory or production_sources
    checked_directions = (args.direction,) if args.direction else DIRECTIONS
    if args.pack:
        output = production_packed if source_directory.resolve() == production_sources.resolve() else ROOT / "tools/godot/art_preview/runtime_packed" / args.role
        for direction in checked_directions:
            pack_direction(args.role, direction, source_directory, output)
        source_directory = output
    family = build(args.role, source_directory, checked_directions)
    family["enabled"] = args.enable
    family["production_ready"] = args.enable
    if args.preview:
        review_contacts(family, source_directory, ROOT / "tools/godot/art_preview/runtime_packed" / args.role)
    if args.write:
        target = ROOT / "assets" / "characters" / args.role / "animations" / "action_family.json"
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(family, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(target)
    print(json.dumps({"hero_id": family["hero_id"], "directions": len(family["directions"]), "poses": len(family["directions"])*8, "enabled": family["enabled"], "native_2k_sources_met": family["native_2k_sources_met"], "standing_source_heights": {key: value["reference_body_height"] for key, value in family["directions"].items()}}, ensure_ascii=False))


if __name__ == "__main__":
    main()
