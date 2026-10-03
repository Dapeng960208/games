# B07-M01 first native actor art pilot

Selected candidate: `B07_M01_spear_lizard_guard_idle_ready_v2.png` (1254 × 1254 native RGBA). V1 remains only as generation provenance; V2 is the review candidate. The PNG was copied losslessly from the built-in imagegen output, with no crop, resizing, upscaling, recoloring or alpha cleanup. Both full prompts are adjacent.

## Identity and scale review

The authoritative reference is the bottom-left 沙蜥战士 in the supplied `B07(1).png`. V2 preserves its gold sand scales, pale throat/chest, elongated lizard muzzle, high golden eye/crown scales, red-orange cloth, restrained bronze-gold light armor, sun motifs, spear, round shield, long tail and toe claws. It does not use the adjacent axe champion, mount, winged creature or the runtime beetle placeholder. V2 improves over V1 by showing more top planes of snout/crown/shoulders/feet and a leaner, longer muzzle.

I inspected the native image and read-only downsized previews at an approximately 82px anatomical body height and the approximately 59px body height produced by the game's 0.72 camera. The spear, lizard head/crest, shield and long tail remain identifiable. Fine scale/sun details collapse at that small scale as expected. This is an isolated sprite check, not an in-game or animation validation. Exact camera match must be reviewed against the hero after integration.

## Landmarks

Coordinates are absolute native pixels, x right / y down. The foot landmark uses the load-bearing centers of the two feet, not the foremost claw tips. Manual semantic landmarks have approximately ±8px uncertainty.

- Near foot load center: (510, 1090)
- Far foot load center: (865, 965)
- `foot`: (687.5, 1027.5)
- Anatomical crest top: (679, 203)
- `reference_body_height_px`: 824.5 = 1027.5 − 203
- `core_anchor`: (687, 585), central upper torso/sternum
- `visual_outlet` / spear tip: (1199, 65)
- Crest-to-lowest-toe edge: 969px; do not use this as the runtime body scale
- Target runtime body height: 82.08 world units versus hero 112, ratio 0.732857

JSON includes normalized anchors, region, alpha128 bounds, both height measures, hashes and source provenance.

## Alpha and framing

There are no nonzero pixels on any image edge, and the spear and tail are intact. At alpha >1, margins are left 74, top 61, right 50 and bottom 79px. Faint native alpha=1 traces extend beyond that silhouette and are retained; exact nonzero bounds are recorded. Most painted interior pixels are alpha 253/255. No opaque background, baked floor, cast ground shadow, lettering or glow was observed. Native alpha has not been altered.

## Gate and next step

The parent visually accepted V2 identity as an idle pilot on 2026-10-03. `runtime_quality_gate_passed=false`: actual game-frame scale, foot attachment, perspective and transparency still need review. Hold telegraph/thrust generation until that check passes.

Important alpha caveat: the parent observed a low-alpha red/yellow edge fringe in the preview. The native image has not been cleaned. There are 26294 pixels with alpha 1–32, including 9127 red-dominant and 3205 yellow-dominant diagnostic pixels. These counts overlap and do not substitute for visual QA. Test light sandstone and dark game backdrops at normal zoom; do not claim clean in-game edges or threshold the asset blindly. Only one right-facing idle-ready pose exists. No telegraph, thrust, walking, tail-sweep, death or full directional coverage is claimed. No code/worktree integration, registry write, commit or push was made.
