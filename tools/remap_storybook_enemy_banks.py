"""Copy approved source pixels and remap measured regions to the final four clans.

This performs metadata work only: no resize, crop, paint, or PNG re-encoding.
Original generations and their complete provenance stay untouched.
"""
import copy
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets/generated/enemies"
CATALOG = json.loads((ROOT / "data/enemies.json").read_text(encoding="utf-8"))

MAPPINGS = {
    "B01": ("B03", "晴辉构装", 54, {
        "M01": "M27", "M02": "M21", "M03": "M20", "M04": "M19",
        "M05": "M24", "M06": "M26", "M07": "M23", "M08": "M25",
        "M09": "M22", "BO01": "BO03"}),
    "B02": ("B01", "琥珀虫族", 60, {
        "M10": "M01", "M11": "M03", "M12": "M09", "M13": "M07",
        "M14": "M04", "M15": "M02", "M16": "M05", "M17": "M06",
        "M18": "M08", "BO02": "BO01"}),
}


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


for target_biome, (source_biome, clan, boss_radius, mapping) in MAPPINGS.items():
    source = ART / f"storybook_{source_biome}_bodies_v1.png"
    target = ART / f"storybook_{target_biome}_bodies_v2.png"
    source_manifest = json.loads(source.with_suffix(".regions.json").read_text(encoding="utf-8"))
    source_provenance = json.loads(source.with_suffix(".json").read_text(encoding="utf-8"))
    shutil.copyfile(source, target)
    entries = {}
    for identity, source_identity in mapping.items():
        entry = copy.deepcopy(source_manifest["entries"][source_identity])
        radius = boss_radius if identity.startswith("BO") else CATALOG["enemies"][identity]["navigation_radius"]
        entry.update({"collision_radius": radius,
                      "native_height": round(min(220, max(170, radius * 3.45)) if identity.startswith("BO") else min(88, max(66, radius * 3.8)), 2),
                      "source_identity": source_identity})
        entries[identity] = entry
    manifest = copy.deepcopy(source_manifest)
    manifest.update({"schema_version": 1, "texture": f"res://assets/generated/enemies/{target.name}",
                     "source_family": "storybook_2_5d_v1", "biome_id": target_biome,
                     "visual_clan": clan, "entries": entries,
                     "region_mapping": mapping, "source_manifest": source.with_suffix(".regions.json").name,
                     "pixel_processing": "raw PNG copied byte-for-byte; only identity/biome metadata remapped"})
    # Diagnostics are source-cell facts; keep that distinction explicit.
    if "diagnostics" in manifest:
        manifest["source_diagnostics"] = manifest.pop("diagnostics")
    write_json(target.with_suffix(".regions.json"), manifest)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    provenance = {"schema_version": 1, "date": "2026-10-01", "biome_id": target_biome,
                  "visual_clan": clan, "texture": f"res://assets/generated/enemies/{target.name}",
                  "source_family": "storybook_2_5d_v1", "source_png": source.name,
                  "source_provenance": source.with_suffix(".json").name,
                  "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "sha256": digest,
                  "region_mapping": mapping,
                  "authorization": "User's final 12-level plan: first four clans construct/insect/zombie/orc.",
                  "processing": "Approved source pixels preserved exactly; measured crops and feet remapped by combat role. No stats or AI changed.",
                  "original_generation": source_provenance}
    write_json(target.with_suffix(".json"), provenance)
    print(json.dumps({"biome": target_biome, "clan": clan, "entries": len(entries), "sha256": digest}, ensure_ascii=False))
