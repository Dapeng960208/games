# L37 Sunscale Gate: superseded early art candidates

## Latest user-design correction

The actual user-supplied B07 design was inspected at 2026-10-03 04:00 UTC. Its canyon-spanning multilevel fortress city, arched bridges, huge golden mirrors, lizard-head guardians, red-orange banners, terraces and palms differ materially from this early flat courtyard direction. All early composition/facade candidates are superseded and must not be promoted as faithful to that reference. The plain sandstone floor may be technically reusable as material only. Generation is paused pending a newly approved first-room layered composition brief.

## Current update: 2026-10-03 03:58 UTC

The parent-supplied actual engine screenshot confirmed that inverse-clipping the full-scene candidate cuts masonry bases and creates a seam. **Both direct full-scene activation and the previously proposed inverse-clipped composite are now rejected.** The clean floor remains usable.

A dedicated replacement north facade is available as `L37_north_facade_v1.png` (2172 × 724 RGBA), with its own `.metadata.json` and `.prompt.txt`. Place the significant source region (43, 111, 2090, 401) uniformly along blueprint x650..2460 with its lower baseline at y100. Keep it intact; do not clip its bases. Raw alpha contains tiny 1–4/255 residue beyond the silhouette, so the metadata requires runtime alpha ≤5/255 discard. The module extends north of the blueprint rectangle. A new actual composite is still required. No other side modules were generated.

The following initial report is retained as history; its inverse-clipping recommendation has been superseded.

## Delivery decision

Use the layered candidate only for an integration trial. **Neither full background is approved for direct activation.** The corrected full scene still places architecture and static covers differently from the authoritative room geometry. Do not change gameplay geometry to accommodate it.

Recommended assets:

- `L37_sandstone_floor_v1.png`: actual 1565 × 1005 RGB, clean hand-painted sandstone, no objects. Clip to the exact authoritative walkable polygon.
- `L37_environment_candidate_v2.png`: actual 1564 × 1006 RGB, sandstone lizard city architecture source. Draw only outside the same polygon, using an inverse clip. Do not expose its baked interior covers/circles.
- `L37_art_candidate_metadata.json`: source geometry snapshot, dimensions, hashes, normalized mapping, aspect-preserving transform, layering contract and validation limits.
- Corresponding `.prompt.txt` files record the exact prompts and image editing steps.

Rejected assets retained as provenance in staging only:

- `L37_environment_candidate_v1.png`: initial 1564 × 1006 candidate; walkable-boundary infringements.
- `L37_low_stone_cover_v1.png`: optional 1536 × 1024 RGBA standalone stone cover; broad alpha halo makes it unsuitable for activation. Existing runtime covers should remain until a clean sprite is accepted.
- `geometry-guide.svg/png`: QA/input diagram, not formal art; do not add to the game repository.

## Visual findings

The original and edited backgrounds establish a distinct B07 identity: golden sandstone, turquoise/jade lizard bas-reliefs, sun architectural medallions and small vermilion canopy fragments. They match the bright, softly modeled hand-painted fantasy direction observed in the actual L01/L25 reference pixels, without copying either reference layout. No ocean, plants, mechanical turrets, characters, mirror mechanism, active altar, puzzle beam or UI is painted into the floor layer.

The full-background edit did not reliably follow the numeric/diagram geometry. Its north/south structures overlap the true polygon, and the reserved anchor circles and stone covers remain misplaced. This is why it is restricted to inverse-clipped perimeter use. The floor layer is clear across the entire image, so it supplies unobstructed pixels at all authoritative gameplay locations. Runtime masks and exact-position objects are required to turn these sources into a geometrically truthful room.

## Mapping and integration limits

Blueprint: 2800 × 1800. Runtime: multiply positions and dimensions by 0.58, giving 1624 × 1044. Returned native images are not exactly the requested blueprint resolution; no pixels were stretched, upscaled or cropped. Per-asset normalized and aspect-preserving cover transforms are recorded in the JSON. Prefer uniform-scale cover with tiny centered cropping to avoid even small anisotropic distortion.

Keep the functional mirror at (980, 630), altar at (1904, 630), manual gates at (2340, 1000) / (2520, 860), and the two collision rectangles at (1420, 660, 120, 70) / (2160, 650, 110, 70), all in blueprint units. They are separate runtime objects. Main route and mirror-access route remain the authoritative geometry. The generated floor does not establish collision, interaction or route validation.

Exact polygon clipping may visibly cut some perimeter masonry bases and create a transition seam against the new floor. A short in-game pixel review must assess that before activation. No in-game test, engine import, camera check, interaction test or natural combat check has been performed for this candidate. This delivery changes no code, runtime data, repository asset, commit or branch.

## Provenance

All painted pixels were produced by the built-in image generation tool. The sequence was one new image, one targeted geometry edit using a QA diagram, one clean-floor extraction, and one optional transparent cover extraction. Only file copies were used afterward. Actual reference images were inspected before generation. Exact prompts and source-output filenames are recorded beside the candidate.
