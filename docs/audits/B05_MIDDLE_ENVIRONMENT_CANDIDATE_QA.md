# B05 L27–L29 candidate environment integration

Date: 2026-10-02. These resources remain `approved=false`. This is a recoverable candidate checkpoint, not chapter completion, full-room visual acceptance, natural-play acceptance, or permission to merge PR #7.

## Installed scope and immutable provenance

- L27: selected base v2; six original native PNGs from `b05-art/regenerated/maps/L27/L27_SIX_NATIVE_TILES_MANIFEST.json`. Includes asymmetric native dimensions (top-right 1241×1268, bottom-middle 1268×1241); the renderer scales each axis independently. Existing separate 2171×724 void preserved.
- L28: selected base v2; six original native PNGs from `b05-art/regenerated/maps/L28/L28_NATIVE_SELECTED_MANIFEST.json`. Top-left v2, top-right v3, other four v1; all 1254².
- L29: existing six original native PNGs preserved. Registered original 1254² local floor repair and complete `L29_floor_provenance.json`. Root fascia references only the L26 narrow edge material, never its room painting.
- L29 sunleaf: preserved both original 1254² alpha PNGs, copied original provenance into runtime manifest with exact resource paths. States retain full 140×140 world canvas and individually measured foot pivots; no independent alpha-bounds fitting.
- All 18 tile SHA256 hashes, declared native sizes, and minimum axis density ≥2.35 were independently checked. Native output bytes were never resampled, cropped, recompressed, or edited.

Each runtime room manifest includes original source selection and generation metadata. Missing model identity stays unknown. Approved flags were not promoted.

## Exact mapping contract

Source coordinate space: 1536×1024. Ordered rectangles:

1. top_left: [0,0,520,528]
2. top_middle: [504,0,528,528]
3. top_right: [1016,0,520,528]
4. bottom_left: [0,504,520,520]
5. bottom_middle: [504,504,528,520]
6. bottom_right: [1016,504,520,520]

Horizontal overlaps are 16 source pixels; vertical overlap is 24. Renderer uses source-space feather widths, native-independent placement, and mipmapped textures. Feathering blends independently repainted details; it does not prove their shapes match.

L27 void remains bound to frozen blueprint [1100,790,750,210] at 0.58 world scale. L29 repair uses source [205,730,1130,125], clipped by the existing authored ground. No collision polygon, route, obstruction, portal, or gameplay anchor was moved.

## Focused runtime checks

`tests/test_b05_environment_rooms.gd/.tscn` validates candidate gating; six tile hashes and exact source transforms; independent native dimensions; source-space feather widths; frozen 180-world-pixel main and 140-world-pixel safe corridors; exact L27 void rectangle; both independent L29 sunleaf states and production toggle; unchanged ground; audio cleanup.

Initial fixture failures were corrected: mechanism configuration refreshes the backdrop, so explicit candidate art must be applied afterward. `set_input_blocked(false)` sets the release gate and must precede clearing that fixture gate. These were test sequencing failures, not evidence of changed game geometry.

Three serialized runs used `tools/test_workspace.py`, isolated save paths and output roots, Godot 4.6.3, Dummy audio, and Mesa llvmpipe OpenGL compatibility. This is software-rendered actual 2560×1440 evidence, not hardware GPU performance or audible output validation.

- L27: `20261002T153432881979Z-163ab278`, 37 checks, zero failures; center and southwest.
- L28: `20261002T153532695438Z-4a241f46`, 36 checks, zero failures; center and southwest.
- L29: `20261002T153630408181Z-c3fccb6a`, 43 checks, zero failures; center, southwest, and closed-west leaf.

Seven captures total, retained only in managed test output, never committed. Camera positions are synthetic; L27 center lies in the void and is not proof of legal movement. Corridor checks are geometry tests, not manual traversal evidence.

## Pixel review and blockers

### L27: rejected pending edge/void repair

Native detail is crisp and inspected joins are not conspicuous. The southwest clamped legal-ground position visibly places the hero beyond the painted dry floor, on the flowering root fascia. The separate void has the correct collision rectangle but reads as a sharply pasted rectangular landscape. Fix appearance at frozen geometry; do not move geometry toward the picture. Northern foliage and other perimeter views still require review.

### L28: two inspected views look coherent; full acceptance pending

Center floor is crisp, southwest hero feet remain on visible dry floor, and no hard tile line stands out in these views. Northern edges and full traversal remain unverified. Do not interpret this limited review as a six-tile/full-room approval.

### L29: rejected pending repair material/blending work

The exact south-edge overlay produces a visibly bright strip that erases source shadow. Its left boundary is abrupt, and a prominent vertical repetition seam exposes the non-seamless material. The original painted lower flower edge remains visible beneath/outside the new fascia. The shader currently softens only the top edge; exact clipping alone does not establish visual blending.

West closed/east open leaf states are clear, fixed-canvas and independently toggled. The test places the hero at the leaf's anchor to invoke interaction; this intentional overlap is not a final presentation composition.

## Follow-through

Shared renderer owner was sent the failures and exact capture run IDs. Required fixes: geometry-aligned L27 visible floor/perimeter; better integrated void rim; L29 non-seamless repeat and side/shadow transition; inspect repaired boundaries and remaining northern/alternative-route views before changing acceptance flags. PR mainline publication remains the chapter lead's separate completion gate.

## Targeted correction pass

Preserved checkpoint `0fae111` contains the initial candidates and evidence above. `898cd06` adds one new native L27 void candidate (2172×724 RGBA), complete prompt/provenance, and safer camera placement. Native v1 remains available. V2 was generated once with the original void as edit target and L27 base as style/material reference; exact returned PNG bytes were copied, never edited.

Camera anchors now must pass production `valid_ground(target,30)`. An invalid target is approached from the authored entry through `move_actor`, then verified before capturing. Frozen source rectangles are compared component-by-component as exact floats; JSON-float versus constant-int Variant-array equality was a test-only false failure, corrected without truncation or tolerance that could hide real offsets.

Lead-owned renderer changes preserve candidate opt-in during real depth-layer refreshes, use v2 void, extend L27 west dry floor at fixed geometry, and improve repair mirroring, edge feather and low-frequency source-lighting matching. No geometry was adjusted.

Targeted rechecks (same isolated wrapper, software renderer and actual 2560×1440 window):

- L27 `20261002T155242319815Z-262087de`: 45 checks, zero failures, two captures. Hero anchors legal. V2 now reads as downward depth with an organic blended rim; the southwest hero stands on visible dry floor. Remaining rejection: broad west repair changes plank scale/material, truncates original curved trim and obscures the braided inlay with a visible patch transition.
- L29 `20261002T155344724784Z-437c9f01`: 51 checks, zero failures, three captures. Hard vertical repeat seam removed and shading improved. Remaining rejection: broad southern repair band is visibly blurred/smeared, carries ghost petal/flower shapes, and leaves an abrupt trimmed stub at the west edge. This remains visible from center as well as southwest. Leaf open/closed behavior still passes.

Twelve captures total across initial and corrective passes; all remain managed-output-only. The corrected states improve readability and legal-floor correspondence but still do not pass final visual acceptance. A localized native repaint matched to the frozen boundary is preferable to indefinite broad material/shadow mixing. All acceptance flags remain false, and no additional generation loop was started.
