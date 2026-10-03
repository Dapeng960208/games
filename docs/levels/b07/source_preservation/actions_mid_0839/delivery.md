# B07 M08–M12 action and object design candidates

20 selected target images: 15 individual action key poses and five independent skill objects/VFX. There are 24 preserved generated PNGs including four repair attempts. All were created with the built-in image-generation tool and copied byte-for-byte, with per-image prompts, provenance, SHA-256 and alpha statistics. Repository, manifest, runtime, room data and remote branches were not changed.

`index.json` is the complete machine-readable delivery index with exact absolute paths, original source paths/hashes, per-threshold alpha bounds, effective occupied pixels, per-pose manual crown/foot estimates, caveats and rejected variants. `manual_qa.json` is the manually observed selection record. `diagnostics/` contains review-only normal-alpha composites on pale sand and dark purple; they are not game assets and must not be committed as formal resources.

## Status that must remain explicit

- All five actual active skills remain unimplemented/basic-attack fallback. These are visual design candidates only, with zero runtime coverage implied.
- Three poses are not continuous animations. Directions, transitions, timing, walk, hit/death and full camera/2K scene validation remain outside this delivery.
- All 20 selected images have no occupied boundary pixel at alpha >= 16 or >= 128. This does not mean safety margins passed: M08 execute repair has only 13 px on the blade side; M09 pipe and M10 mirror tops are tight.
- M11 telegraph is BLOCKED for pose readability: original retains four feet but insufficiently clear lift; its one repair improved lift but lost the far hind foot and is rejected. Do not describe all 15 poses as accepted.
- M11 execute repair restores a distinct fourth paw. M12 recovery repair removes the duplicated left hand. Both originals are rejected.
- M10 three-state mirror is one compound design object with two ghost orientations, not three production-separated state assets and not implemented logic.
- M12 execute string release and reload mechanics remain uncertain. M09 anticipation is subtle. M08 recovery is close to idle. Manual foot anchors and body-height estimates are provisional and need runtime alignment.
- Normal alpha composites show no broad glow/matte from the raw RGBA previews. Source RGB under zero alpha was not edited or thresholded.

## Chosen files

Paths below are relative to this delivery directory. Complete absolute equivalents are in `index.json`.

- M08 telegraph: `m08/telegraph/candidate.png`
- M08 execute: `m08/execute/repair/candidate.png`
- M08 recovery: `m08/recovery/candidate.png`
- M08 short light: `m08/mirror_short_light/candidate.png`
- M09 telegraph: `m09/telegraph/candidate.png`
- M09 execute: `m09/execute/candidate.png`
- M09 recovery: `m09/recovery/candidate.png`
- M09 poison dart: `m09/poison_dart/candidate.png`
- M10 telegraph: `m10/telegraph/candidate.png`
- M10 execute: `m10/execute/candidate.png`
- M10 recovery: `m10/recovery/candidate.png`
- M10 three-state mirror indicator: `m10/mirror_state_indicator/candidate.png`
- M11 telegraph, readability blocked: `m11/telegraph/candidate.png`
- M11 execute: `m11/execute/repair/candidate.png`
- M11 recovery: `m11/recovery/candidate.png`
- M11 ridge segment: `m11/sand_ridge_segment/candidate.png`
- M12 telegraph: `m12/telegraph/candidate.png`
- M12 execute: `m12/execute/candidate.png`
- M12 recovery: `m12/recovery/repair/candidate.png`
- M12 heavy bolt: `m12/heavy_crossbow_bolt/candidate.png`
