#!/usr/bin/env python3
"""Prepare exact room references or package approved-generation candidates.

This does not generate, upscale, retouch, approve, or enable artwork.
Examples:
  python tools/package_environment_tiles.py prepare L01
  python tools/package_environment_tiles.py package L01 --jobs artifacts/L01_jobs.json
A jobs JSON array contains six {id, generated_path, prompt} objects.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IDS = ("top_left", "top_middle", "top_right", "bottom_left", "bottom_middle", "bottom_right")
RECTS = ((0,0,520,528),(504,0,528,528),(1016,0,520,528),(0,504,520,520),(504,504,528,520),(1016,504,520,520))

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def source(room: str):
    path = ROOT / "assets/generated/world/rooms" / f"{room}_environment_v1.png"
    image = Image.open(path).convert("RGB")
    if image.size != (1536,1024):
        raise ValueError("This validated six-region layout requires a 1536x1024 original")
    return path, image

def prepare(room: str) -> None:
    path, image = source(room)
    out = ROOT / "artifacts/world-2k-production/references" / room
    out.mkdir(parents=True, exist_ok=True)
    for name,(x,y,w,h) in zip(IDS,RECTS):
        image.crop((x,y,x+w,y+h)).save(out/f"{name}.png")
    print(out)

def package(room: str, jobs_path: str) -> None:
    original, _ = source(room)
    jobs = json.loads(Path(jobs_path).read_text(encoding="utf-8"))
    by_id = {job["id"]:job for job in jobs}
    if set(by_id) != set(IDS) or len(jobs)!=6:
        raise ValueError("Exactly six distinct region jobs are required")
    out = ROOT / "assets/generated/world/rooms_2k" / room
    if (out/"manifest.json").exists():
        raise ValueError("Existing pack must be deliberately reviewed before replacement")
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"schema_version":1,"room_id":room,"approved":False,
        "source_texture":"res://"+str(original.relative_to(ROOT)),"source_size":[1536,1024],
        "source_sha256":sha(original.read_bytes()),"generation_tool":"built-in image_gen",
        "representation":"six native detail repaints over exact original mapping; narrow overlapping feather zones retain fallback",
        "feather_source_pixels":[16,24],"tiles":[]}
    for name,rect in zip(IDS,RECTS):
        job=by_id[name]
        generated=Path(job["generated_path"])
        image=Image.open(generated).convert("RGB")
        if min(image.width/rect[2],image.height/rect[3]) < 2.35:
            raise ValueError(f"{name}: insufficient native density {image.size} for {rect}")
        dest=out/f"{name}.webp"
        image.save(dest,"WEBP",lossless=True,quality=100,method=4,exact=True)
        decoded=Image.open(dest).convert("RGB")
        if image.size!=decoded.size or image.tobytes()!=decoded.tobytes():
            raise ValueError(f"{name}: lossless pixel verification failed")
        manifest["tiles"].append({"id":name,"texture":"res://"+str(dest.relative_to(ROOT)),
            "source_rect":rect,"native_size":list(image.size),"generated_png_sha256":sha(generated.read_bytes()),
            "decoded_rgb_sha256":sha(image.tobytes()),"webp_sha256":sha(dest.read_bytes()),
            "encoding":"lossless WebP; decoded RGB verified identical; no resize","prompt":job["prompt"]})
        # Godot fills the identity/remap paths on import, with mip intent present.
        Path(str(dest)+".import").write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\ncompress/mode=0\nmipmaps/generate=true\nprocess/size_limit=0\n',encoding="utf-8")
    (out/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"{room}: candidate only, 6 lossless tiles, {sum(p.stat().st_size for p in out.glob('*.webp'))} bytes")

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command",choices=("prepare","package"))
    parser.add_argument("room")
    parser.add_argument("--jobs")
    args=parser.parse_args()
    if args.command=="prepare": prepare(args.room)
    elif args.jobs: package(args.room,args.jobs)
    else: parser.error("package requires --jobs")
