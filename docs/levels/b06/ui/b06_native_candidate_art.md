# B06 native candidate registration, 2026-10-02

> 状态：候选／待验证：B05、B06 默认未开放；设计和检查记录不等于正式发布。

## Bounded delivered slice

- `assets/levels/b06/registration/manifest.json` registers M01 idle/telegraph/execute, BO06 seven poses, and drain gate/reef pillar/tide clock. All 20 frozen sources, including seven unactivated room floor candidates, are byte-preserved and SHA256 verified. Exact generation prompts and original lineage are under the dedicated `provenance/` directory.
- EnemyArt/EnemyVisual resolve only B06-prefixed registered identities through `b06_native_art.gd`; B05 paths are unchanged. M01 uses three separate textures, one identity scale, pose-specific feet/core/weapon tip and a display-only outlet transformed by actual visual mirroring/recoil. Logical attack/collision origins are untouched.
- BO06 dispatch maps claw/pincer to melee and cannon/bombard/tidal wall to cannon; recovery and coral escort use idle; exposure and defeat override action. The room owner wires actual Boss and prop presentation, preserving the one shared tide clock and authored geometry.
- Pixel landmarks were freshly reviewed on native sources. Feet are ground-support centroids, not alpha-bounds bottoms. Boss core is the visible pearl; ranged outlet is the cannon bore and melee outlet is the striking claw. Fixed reference heights: M01 930 source pixels, BO06 900. Per-pose bounding-box auto-fit is deliberately absent.

## Evidence and exact boundaries

- `tools/maintenance/audit_b06_native_sources.py`: 20 exact source hashes, native dimensions, provenance and in-bounds landmarks passed. This is source integrity, not gameplay acceptance.
- `tests/levels/b06/test_b06_native_art.gd`: 177 focused checks passed in managed Godot 4.6.3. It exercises actual EnemyVisual configuration, M01 pose selection, fixed scale, four-facing outlet mapping, BO06 dispatch/placement, and candidate gates. It does not test natural combat balance.
- `tests/levels/b06/test_b06_native_capture.tscn`: actual 2560×1440 controlled renderer/codex sheet, Godot 4.6.3 / OpenGL Mesa llvmpipe. Saved in managed B06 batch `20261002T164333866638Z-c61e7c5f`, image `b06-native-registration-2k.png`, with source-path report. Reviewed source pixels, label clearance and separate feet/core/outlet marks. The initial label collision was corrected. The final run uses Dummy audio and has only the expected VSync warning.
- The image is a registration sheet, not a screenshot of a natural room encounter, and its display heights are explicitly controlled. Hardware GPU performance, natural combat readability, strength and skill acceptance remain separate gates.

## Open gates

1. Actual BO06 and mechanism host rendering with current room-owner hooks still needs production-scene screenshot review. The native callback is installed, but the controlled sheet alone does not validate that host integration.
2. M02–M09 corrected three-pose sources are pending selection from the generation worker. Unselected pose-v1 sources are not copied or activated. M10–M18 are outside this slice.
3. Seven floor sources are below native 2K, not final native2K maps; no floor is activated. Transparent water/mechanism overlays and exact collision/edge alignment, especially L32 cutouts, remain unverified. Geometry must not be edited to fit these pictures.
4. `runtime_quality_gate_passed=false` and `candidate_only=true` remain explicit. The source images retain native low-alpha remnants and color fringes; no procedural repaint, cleanup, upscaling or generated effects were added.
5. No GitHub/Drive uploads, publication, balance changes, player-save changes or natural S11 run were performed.

## M02–M09 integration checkpoint, 2026-10-02

The 24 selected `native-v2` sources from `selected-24-pose-registration-v1.json` are now registered. Each source was independently viewed, hash-verified and copied without pixel modification; exact provenance JSON and prompt text accompany it. Unselected v1 poses remain outside the runtime bank. M02–M09 now resolve idle, telegraph/locked and execute through the actual shared EnemyVisual, with recovery/walk using the declared idle fallback.

Source composition drift is handled by **static anatomy registration**, not per-frame silhouette fitting. Each identity retains a fixed world reference height. A frame may carry one measured `source_pose_scale` derived from a named anatomical segment (e.g. paired eyes, collar-to-belt, shell landmarks). Source segment endpoints and the numerical ratio are recorded in the manifest and checked by the source audit. The same correction transforms the body, foot, core and outlet together; mirroring/recoil remain on the shared visual node. This does not modify source pixels, collision radii, damage or skill timing. It does not eliminate every generator proportion difference.

The production codex portrait function consumes the visible idle-body bounds plus six source pixels of padding, rather than wasting most of its cell on transparent canvas. Combat pose frames still use their full unmodified texture region. Default chapter visibility and the normal codex release list are unchanged: the test calls the portrait function in an isolated candidate panel.

Evidence:

- Native registration: 548 focused checks, zero failures, managed Godot 4.6.3. Covers nine complete ordinary identity banks, three selected textures each, fixed identity scale with explicit anatomy correction, four-facing display outlet mapping, pause preservation and source-contained codex bounds, plus the initial Boss/prop gates.
- Actual actor/codex capture: 68 checks, zero failures, managed batch `20261002T170353712537Z-7ed3844c`. `b06-m02-m05-native-2k.png` shows right-facing actors; `b06-m06-m09-native-2k.png` shows left-facing actors. Both actual 2560×1440 images were inspected. `ordinary-capture-registration.json` records source and capture hashes. The final graphics log has only the expected VSync warning, no script/engine errors.
- This test instantiates the real Enemy factory and its EnemyVisual, then controls the actor's presentation states for comparison. It calls the actual codex portrait function. It is not a natural brain-driven encounter or strength test. Initial fixture runs revealed missing test-only arena fields; the fixture was corrected without changing gameplay code, and the final run is clean.
- Source audit now covers 44 byte-identical files, including the seven inactive floors. The source hash and anatomy-ratio checks pass.

Remaining gates: dense combat readability and effects-to-organ timing in actual rooms; natural gameplay/strength; M10–M18 source registration; floor/overlay/collision alignment. M02's cannon action is subtle without firing feedback. M06's throwing hand changes screen side between windup and release, so its outlet is explicitly pose-specific. Native low-alpha fringes remain. All candidate/release gates remain unchanged and `runtime_quality_gate_passed` stays false. BO06/prop production-room verification is owned and documented separately by the room-runtime work.
