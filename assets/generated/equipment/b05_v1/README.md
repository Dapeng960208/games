# B05 equipment native candidates

This independent pack contains 35 exact B05 catalog icons, nine unchanged native generation atlases, and the nine exact prompts. The B05 art manifest remains disabled after bounded actual production-UI pixel review; activation belongs to the chapter integration lead. It does not enable chapter five, change acquisition policy, or change saves.

## Reproducible source provenance

The generation requested 2048×2048 in its prompts but returned **1254×1254 RGBA** images. Returned native dimensions are authoritative. All original source and icon bytes are retained. There was no enlargement, sharpening, alpha normalization, or repainting. Source output basenames and content hashes in `generation-provenance.json` identify the generation calls without depending on a workstation path.

`B05-equipment-v1.manifest.json` records full-image regions, original atlas crop rectangles, component IDs, effective foreground bounds, texture hashes and exact catalog IDs. `slot` duplicates `runtime_slot`; the design accessory slot maps to runtime `charm`.

Extraction uses alpha >16 as the foreground mask and four-connected component labeling (SciPy ndimage.label default connectivity). Each crop retains its assigned components plus the nearest-owned-component fringe at distance ≤8 pixels. Excluded neighboring components become transparent. All retained RGBA bytes, including alpha, are unchanged. Transparent crop padding is eight pixels. This records the algorithm rather than a dependency on temporary extraction scripts.

The minimum effective foreground short axis is 377 pixels. The existing production creation preview is 148×140 logical pixels, or 296×280 at 2560×1440; inventory detail is 232×232, forge is 260×260, common inventory cells are 156×156, equipped cells are 96×96. Native density and contact sheets are asset evidence, not runtime acceptance.

The visual-reference content hash identifies the existing B05 design artwork as a style guide, not an icon source or runtime dependency. External asset contact sheets named in `asset-qa.json` are not packaged production screenshots.

## Consumption and isolated acceptance

`EquipmentArt` adds enabled B05 entries only, without replacing existing IDs or slot fallbacks. A missing or disabled B05 pack preserves the current fallback chain. The independent quality gate is separate from the chapter release gate. Existing 96 exact-art entries plus 35 B05 entries total 131; 28 earlier legs/rings continue to use their existing slot fallbacks.

`tests/test_b05_equipment_art.tscn` validates the candidate and renders the actual main/workshop consumers at 2560×1440. It requires an explicit `test_b05_equipment_art*.json` isolated profile. Candidate activation and Lv25 catalog access are injected in memory only. Three classes use valid v3 nineteen-template natural pools, with eight equipped class pieces, and exercise both Chinese and English inventory/detail, forge and largest shop creation previews. It saves images and structured physical-size evidence next to the isolated profile, outside formal assets. No transactions or chapter runs are performed by this visual fixture.

Run only under the repository's serial engine lease, with the official Godot4.7.2 executable and isolated XDG directories. Captures remain excluded from Git. Software-rendered 2K evidence does not establish hardware-GPU performance or natural progression balance.

## Bounded acceptance, 2026-10-02

- Native44-PNG import completed in official Godot4.7.2
- Initial actual30-page workshop pass:628 checks, zero failures; every image2560×1440
- The real screenshots exposed blank B05 shop ranges because the old preview constructor omitted required B05 eligibility provenance. The UI now supplies authoritative class-policy/hero metadata only for its nonpersistent deterministic endpoint record. All35 templates × every legal power type × four qualities have nonempty, ordered, repeatable endpoint assertions without profile mutation
- Final targeted headless:1157 checks, zero failures; final graphical correction pass:1181 checks, zero failures,12 images
- Lead-owned table/hint fixes retain complete tooltip units and keep the inventory hint above the action button. Final six inventory and six shop pages were reviewed in both languages
- Imported alpha, crop bounds, cache identity and render-time mipmaps passed; the sampled source PNGs were not modified

Use `--b05-art-shop-only` after `--` for six weapon-shop screenshots, or `--b05-art-ui-fixes` for six shop plus six corrected inventory screenshots. Keep correction output in a new isolated profile directory so prior evidence stays intact. `runtime-review.json` records scope, pixel sizes and capture hashes without including PNG copies.

Field-loot/pending-reward presentations were not captured here. This is not full B05 gameplay, user acceptance, balance or hardware-GPU performance sign-off. `enabled:false` is intentional.
