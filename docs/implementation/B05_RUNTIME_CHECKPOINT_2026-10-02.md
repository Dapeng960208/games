# B05 runtime checkpoint (2026-10-02)

This is an incremental development checkpoint, not a completed or unlocked fifth chapter. The production `implemented_chapters` value remains **4**. B06–B12 runtime content is outside this checkpoint.

## Included implementation

- Frozen geometry for L25–L30 and BO05, compiled through the existing room layout path. The geometry tests check the authored route widths independently of the painted background.
- Root wells use real combat actors and settled damage receipts. Root-network state and remaining shield time round-trip through the versioned combat snapshot. The implementation supplement is a 12-second shield lifetime, distinct from the 12-second cross-well refresh limiter.
- B05 ordinary and boss command providers, production actor/runtime dispatch, difficulty additions, channel interruption, projectile origins and support healing. Existing enemies and historical variant mappings are retained.
- B05 equipment effects, 35 templates, class-qualified generation, level/progression gating, acquisition preferences and versioned save/receipt handling. Historical generator contracts remain replayable.
- Separate first-room native pose banks, four root-well states, L25 native environment detail candidates and 35 equipment icon candidates. Native images are not enlarged copies of low-resolution sources.
- An explicit read-only B05 codex preview uses the real profile and skill providers; the normal menu remains restricted to released chapters. Preview labels disclose unfinished artwork.

## Focused evidence already obtained

Official Godot 4.7.2 isolated checks: acquisition/preferences/save 2,693; equipment runtime 72; real equipment effects 73; legacy effects 179; combat snapshot 136; B05 combat 836; pose registration 131; real actor API 41; root-well live path 23; root network 67; frozen room geometry 38. These checks passed in their scoped suites and are not a natural balance matrix.

L25's seven camera positions plus a reduced-effects view produced 15 actual 2560×1440 frames and 37 passing structural checks. Native six-tile density is at least 2.375 source pixels per base pixel per axis. The art review found no blocking hard join in those views. Narrow feather bands still mix the base painting, and some foreground detail intentionally remains painterly. Production approval flags stay closed while complete encounter acceptance is unfinished.

The first three-monster graphical attempt exposed a missing real-player API assumption. It was fixed and covered by the 41-check real-node regression. Later capture revisions also explicitly freeze the projectile clock while writing images; a saved frame alone is not evidence of projectile release/impact timing. Final capture evidence is recorded in the combat implementation document.

Equipment preview and codex rendering use synthetic isolated data and real UI controls. Their source tests record checks and outputs locally; screenshots, logs and test profiles are deliberately excluded from Git.

All rendered-frame checks use Mesa llvmpipe software OpenGL. They establish actual rendered appearance, not hardware GPU performance or remote-stream smoothness.

## Release blockers retained

B05 is not yet offered for normal departure. Remaining work includes complete room mechanics and collision transitions, boss root rotation and whole-command hazard admission, final actor/telegraph readability, the remaining B05 room and creature artwork, the complete chapter progression/reward/save loop and user play acceptance. Authored content catalogs and candidate art flags do not assert these are complete.

See [root integration](B05_ROOT_MECHANISM_INTEGRATION.md), [combat implementation](B05_COMBAT_IMPLEMENTATION.md), [equipment runtime](B05_EQUIPMENT_RUNTIME_2026-10-02.md), [acquisition and saves](B05_ACQUISITION_PROGRESSION_SAVE_2026-10-02.md), and the [B05 implementation index](../levels/B05_B12_IMPLEMENTATION.md).
