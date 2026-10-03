"""Check B09 source hashes, atlas bounds and accidental reuse of B05/B06 files."""
import hashlib
import json
import struct
from pathlib import Path
from PIL import Image


def audit(root: Path) -> None:
    art = root / "assets/levels/b09"
    sources = sorted(art.rglob("*.png"))
    assert len(sources) == 33, f"expected 32 original sources and one L54 bridge edit, got {len(sources)}"
    hashes = {}
    for path in sources:
        data = path.read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n", path
        size = list(struct.unpack(">II", data[16:24]))
        provenance = json.loads(path.with_name("provenance.json").read_text(encoding="utf-8"))
        digest = hashlib.sha256(data).hexdigest()
        assert provenance["sha256"] == digest, f"source hash mismatch: {path}"
        assert provenance["source_size"] == size, f"source size mismatch: {path}"
        assert provenance["prompt"] and provenance["generator"], path
        assert digest not in hashes, f"duplicate B09 images: {path}, {hashes.get(digest)}"
        hashes[digest] = path
    sizes = {p.stat().st_size for p in sources}
    for biome in ("b05", "b06"):
        for path in (root / "assets/levels" / biome).rglob("*.png"):
            if path.stat().st_size in sizes:
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                assert digest not in hashes, f"B09 source reused from {path}"
    manifest = json.loads((root / "assets/manifest.json").read_text(encoding="utf-8"))
    atlas = json.loads((art / "registration/actors.json").read_text(encoding="utf-8"))
    assert len(atlas["identities"]) == 19
    frames = 0
    for identity, actor in atlas["identities"].items():
        width, height = actor["source_size"]
        last_right = 0
        for pose in ("idle", "telegraph", "execute"):
            frame = actor["frames"][pose]
            x, y, w, h = frame["region"]
            assert x >= last_right and y >= 0 and x + w <= width and y + h <= height, (identity, pose)
            bx, by, bw, bh = frame["alpha160_bounds"]
            assert x <= bx < bx + bw <= x + w and y <= by < by + bh <= y + h, (identity, pose)
            fx, fy = frame["foot"]
            assert bx <= fx <= bx + bw and by <= fy <= by + bh, (identity, pose, "foot")
            logical = frame["texture"].removeprefix("asset://")
            assert (root / manifest["resources"][logical].removeprefix("res://")).is_file(), logical
            last_right = x + w
            frames += 1
    detail_count = 0
    detail_bytes = 0
    rects = [[0,0,520,528],[504,0,528,528],[1016,0,520,528],
             [0,504,520,520],[504,504,528,520],[1016,504,520,520]]
    for room in ("L49", "L50", "L51", "L52", "L53", "L54", "BO09"):
        folder = art / "rooms" / room.lower()
        source = folder / "background/environment.png"
        pack = json.loads((folder / "detail/manifest.json").read_text(encoding="utf-8"))
        assert pack["room_id"] == room and pack["approved"], room
        assert pack["source_sha256"] == hashlib.sha256(source.read_bytes()).hexdigest(), room
        assert pack["source_size"] == [1536, 1024] and len(pack["tiles"]) == 6, room
        paths = set()
        for entry, rect in zip(pack["tiles"], rects):
            logical = entry["texture"].removeprefix("asset://").lower()
            path = root / manifest["resources"][logical].removeprefix("res://")
            assert path.parent == folder / "detail" and path not in paths, path
            paths.add(path)
            assert entry["source_rect"] == rect and entry["prompt"] and entry["generated_source_path"], path
            data = path.read_bytes()
            assert hashlib.sha256(data).hexdigest() == entry["webp_sha256"], path
            with Image.open(path) as image:
                image = image.convert("RGB")
                assert list(image.size) == entry["native_size"], path
                assert min(image.width/rect[2], image.height/rect[3]) >= 2.35, path
                assert hashlib.sha256(image.tobytes()).hexdigest() == entry["decoded_rgb_sha256"], path
            detail_count += 1
            detail_bytes += len(data)
    print(f"B09_ART sources={len(sources)} identities=19 poses={frames} native_detail={detail_count} bytes={detail_bytes}; hashes, native density and bounds OK; no identical B05/B06 source")


if __name__ == "__main__":
    audit(next(p for p in Path(__file__).resolve().parents if (p / "project.godot").is_file()))
