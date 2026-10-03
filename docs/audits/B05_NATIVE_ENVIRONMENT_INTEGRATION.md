# B05 native environment candidate integration

2026-10-02. Default release remains four chapters. Candidate detail, repaired floor and fixed void require explicit candidate rendering. Frozen room polygons, portals, routes and void collision are unchanged.

## Native sources and mapping

Seven room-specific bases now exist. Every room has a six-tile native-detail candidate pack. Independent texture width/height mapping is preserved; non-square outputs are not resampled. Native minimum density is recorded in each manifest, rather than described as native 2K when dimensions are smaller.

L27 uses the separate transparent native void v2, exactly mapped to the frozen collision rectangle. L29 leaf open/closed sources use fixed anchor registration and respond to the existing interaction/checkpoint state.

L27 west and L29 three southern strips have unique native repair images, exact prompts and SHA256 in native_floor_patches_v1.json. Each image is sampled once over its recorded original-source rectangle, clipped to frozen walkable ground. There is no texture repetition or reference-color/shadow reconstruction on these four patches. Original and prior material candidates are retained. Shared floor/fascia candidates for L26 and BO05 remain separate layers.

## Verification

- Seven-room source/geometry/candidate-gate/unique-repair registration: 53 checks, 0 failures, run 20261002T161319376977Z-580810c0.
- Middle-room headless source, native mapping, mechanism and geometry checks: 118/0, run 20261002T161029919793Z-6923c6a6.
- Outer-room headless source/mapping checks: 112/0, run 20261002T155955828393Z-abb694d6.
- L27 actual 2560x1440 camera: 45/0, run 20261002T161130260315Z-03d10bab. Legal southwest foot remains on dry floor; braided inlay continues across the repaired west surface; void reads downward with an organic alpha rim.
- L29 actual 2560x1440 camera: 51/0, run 20261002T161146070920Z-cddc530f. Repaired south floor preserves clear native grain and shadow rather than smeared ghost flowers. Open/closed sunleaf states remain distinct.

## Known visual exceptions

These are still candidate assets. Inspected L27 west entrance and L29 left corner retain a short discontinuity where the original curved decorative trim meets the exact repaired perimeter. Current legal actor camera anchors have dry visible floor; this remaining observed issue is decorative continuity, not a demonstrated collision/walkability failure. These views do not establish all-room or all-edge acceptance. No final art approval or combat-balance claim is made from structural checks.

## Chapter-wide camera review

Outer-room actual 2560x1440 standard camera checks: L26 44/0 (20261002T161413244226Z-1cafbf77), L30 44/0 (20261002T161431192444Z-7f1726b1), BO05 44/0 (20261002T161445754470Z-216933ef). Each has center and southwest frames.

Seven additional full-painted-room overview frames are in run 20261002T161831385218Z-5456a8c7. These use a deliberately zoomed-out diagnostic camera, not the production gameplay zoom. All seven native packs, exits and complete floor silhouettes were inspected. The original run reported 294 checks with six L25 hash failures: the shared test compared lossless WebP bytes to the original generated PNG hash. The test now uses the manifest's webp_sha256 for this older pack, retaining generated_png_sha256 for native PNG packs. The original frames remain valid visual evidence; that original run is not relabeled as a passing run.

Remaining exceptions by observed impact:

- L25: no new full-room visual blocker found in this review.
- L26: conspicuous lighter south repair band and corner trim joins; cosmetic material continuity. Inspected legal southwest feet remain on dry floor.
- L27: original curved west-entry trim terminates at the new exact straight perimeter; decorative continuity. Fixed void and repaired floor are readable in inspected frames.
- L28: no new full-room visual blocker found; two close gameplay views and overview do not prove every boundary pixel.
- L29: small old trim remnants at repaired southern corners; decorative continuity. New native south strips preserve floor/shadow readability.
- L30: southwest legal actor foot overlaps painted flowers on the perimeter; ground-readability exception, despite valid collision position. Prioritize a later bounded native edge repair, without moving frozen geometry.
- BO05: south repair material band and short corner trim discontinuity; cosmetic continuity. No obsolete bronze urn appears. This environment fixture does not instantiate the boss actor; separate boss-pose QA remains the actor evidence.

No additional generation was attempted after this chapter-wide classification. Balance and natural gameplay acceptance remain separate gates.

Corrected all-seven headless verification: 266 checks / 0 failures, run 20261002T161930746641Z-df0bf00e. No screenshot rewriting or native asset alteration was involved in the hash-fixture fix.

## Bounded L30 readability repair

One native 1501x1047 PNG was generated from the exact L30 source crop [205,590,380,265] plus its adjacent original floor. Exact prompt, source/generated hashes, native dimensions and tool-returned path accompany the candidate. Flat floor and soft shadows replace only the intrusive southwest foliage inside the frozen polygon. The original native perimeter remains; a partial generic fascia was explicitly disabled because it would introduce a false rim across the visible overscan.

Actual legal-anchor verification: 44/0, run 20261002T162632436306Z-b1f05359, L30_southwest.png. Both actor feet now rest on visible dry timber, closing the specific observed foot-on-flower readability issue. Some cosmetic patch/perimeter continuity remains; this does not certify every edge. Updated registration test: 59/0, run 20261002T162651336309Z-adbead07. Existing sunleaf input/save restriction regression also passes 22/0, run 20261002T162211056123Z-394afd8e. No additional art generation was made beyond this one L30 patch.

## Bounded material and trim continuity pass (2026-10-02 18:48 UTC)

A fresh actual-window baseline, `20261002T183157690045Z-1d0959e7`, reproduced the seven-room overview on current code (294/0). The L26/BO05 repeated pale south material and ornamental end caps, L27 cut west-entry inlay, and L29 short upright corner strips were still visible; the earlier screenshots were not treated as proof of unchanged state.

Two new native imagegen patches replace the shared repeated floor material **only in the bounded southern repair zones**:

- L26: `L26_south_continuity_v1.png`, actual native **2107x746**, SHA256 `8ab1c9cd287c0b7b9296a9e43edefca45c1b4c083190a7ed4305e5d3e7a60463`.
- BO05: `BO05_south_continuity_v1.png`, actual native **2106x747**, SHA256 `a44a357ffe2f0639b2107a0520a208d7fd4e4b8c72202fe08e5ab55def662a8b`.

Each is an exact generated PNG, with unaltered pixels, exact submitted prompt, source/crop/generated/prompt hashes, returned path and dimensions in its native patch manifest. Source crop is [205,455,1130,400]; native density is about 1.865 per axis, **not a 2048-square source**. The renderer now separates source UV registration from paint bounds: L26 only paints [205,665,1130,190], BO05 [205,730,1130,125]. Both retain a 32-source-pixel upper transition. An initial broad application was rejected because it unnecessarily covered side decoration above the repair; its diagnostic run is not final acceptance evidence.

The fascia shader no longer paints semicircular caps at ends of a partial boundary strip; internal polygon joins remain covered. Local repair extents have a short alpha transition. L29 now draws only the southern/diagonal fascia, removing the false upright strips at both corners. L27 reveals its existing **flat** west-entry curved inlay through one bounded 48x145-source-pixel transition, rather than revealing old raised roots along the whole repaired west edge. These are visual masks only. Geometry, portals, routes, collisions, danger admission and combat values are unchanged.

Final evidence (managed output only, no screenshots committed):

- `20261002T184203193631Z-52cc84a4`: seven overviews 298/0; outer-room center/southwest plus L26/BO05 southeast views 136/0; middle-room views 144/0. This verifies the final southern paint bounds and cap correction. L26/BO05 inspected actor feet stand on dry wood; the former small repeated paver band is replaced by room-specific grain, inlay and tree shadow. This overview predates the final L27/L29-only trim corrections below.
- `20261002T184609212344Z-24013249`: final L27 48/0 and L29 54/0. L27 west-entry curve continues softly into its dry floor, with entry/southwest legal anchors. L29 southwest/southeast upright strip artifacts are gone; feet remain on dry floor; independent sunleaf toggle still passes.
- `20261002T184749897800Z-555b1d0e`: final candidate/source/unique-UV/native-dimension/paint-bound/trim/frozen-geometry registration 92/0.

All actual captures are 2560x1440 framebuffer output, launched from the cloud native desktop and serialized with `/tmp/games-godot.lock`, Godot 4.6.3, Dummy audio and Mesa llvmpipe OpenGL compatibility. This is real software-rendered window evidence, not hardware GPU or audio-output validation. Final render logs contain no SCRIPT ERROR/ERROR. No new generation loop beyond the two floor patches was used.

Scope of closure: the repeated southern material, partial-fascia round caps, hard west-entry truncation and artificial L29 upright strips are corrected in inspected views. Small residual painted-to-exact-polygon material joins remain at some side/corner pixels, especially the L29 southeast transition. These are not claimed pixel-perfect, all-edge art acceptance. Candidate approval flags remain false, and no natural gameplay or combat-balance acceptance follows from this pass.
