# Ordinary-variant native-HD pilot

This file retains the original four-key pilot record below. The current runtime allowlist is 22 exact keys across the original, ruins, hive and soft-combat manifests; the other 577 entries remain unchanged. See `docs/ui/ENEMY_VARIANT_HD_BATCH_2.md` for source-matched registration, the three render-only virtual canvases and completed 2K sampling acceptance.

Four source-identity-reviewed native redraws only:

| Enemy | Variant index | Exact original variant ID | Original body height | Native visible body height |
|---|---:|---|---:|---:|
| M22 | 0 | `storybook_B03_variants_v1:M22:r01c04` | 118 px | 1025 px |
| M34 | 0 | `storybook_B04_variants_v1:M34:r01c07` | 125 px | 1060 px |
| M34 | 1 | `storybook_B04_variants_v1:M34:r02c07` | 125 px | 1045 px |
| M34 | 4 | `storybook_B04_variants_v1:M34:r05c07` | 125 px | 978 px |

These preserve the actual combat-variant identities. They do not replace them with canonical codex illustrations. M22 keeps its orange cannon, colored ammunition and purple patched clothing. The three M34 bodies retain their different plain/red/spiked armor, red/dark crests, shield silhouettes and open-toed sandals.

`variant_hd_v1.overrides.json` binds each replacement to its exact original identity, index, variant ID, texture, region, foot and source height. Replacement must occur in place after original variant enumeration. All other 595 original entries, canonical images and boss images remain outside this pilot. Invalid or mismatched entries must retain their original artwork.

Each PNG is the unchanged 1254×1254 output of a native image-generation repaint and targeted identity repair. No pixel enlargement, sharpening or alpha cleanup was applied. Source evidence, rejected revisions and inspection composites are excluded from runtime assets. Portable source metadata and the complete prompt sequence are in `provenance.json`.

The supplied floating-point source rectangles retain each original width-to-height ratio and centered bottom foot. With the existing uniform height registration this preserves the original body bounds, display height and ground pivot; collision, navigation and skill/gameplay data are not art concerns and must remain unchanged. Visible alpha bounds use alpha > 8 plus two pixels of anti-alias allowance. This avoids very faint stray alpha outside the drawn character controlling its displayed size.

At the audited 2560×1440 framebuffer, 1280×720 logical canvas and camera zoom 0.85, all four remain approximately 179.52 screen pixels high. Their visible source-to-display ratios are 0.169–0.184 rather than the original 1.436–1.521 enlargement. The PNGs total 5,494,474 bytes; decoded RGBA is 25,160,256 bytes before engine mipmaps/compression.

Source-identity review passed on 2026-10-02. Focused source/pixel/registration validation passed 85 checks. Runtime identity selection, untouched-595 behavior, left/right flips and skill-state GPU sampling are separate integration acceptance gates; asset generation and static checks alone do not prove those gates passed.
