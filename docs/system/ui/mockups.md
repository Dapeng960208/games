# Full-screen UI design references

> 状态：当前参考：具体已实现范围以开发进度和运行代码为准。

Seventeen built-in-imagegen concepts cover sixteen interface families. Each is a standalone full-screen PNG, not a contact sheet. The native outputs are 1672 × 941; the game target is 2560 × 1440. No images were upscaled or described as native 2K. See `mockup-manifest.json` for dimensions, hashes and coverage.

## Source authority and implementation rules

- These are **design concepts, not runtime screenshots**. Live Godot controls, text, stats, item identity, focus and behavior remain source-authoritative.
- Use crisp live Chinese typography and scalable panel geometry; never flatten a generated screen into a functional UI.
- Preserve the real heroes: CH01 罗砧 (战士), CH02 岑线 (枪手), CH03 谷频 (法师). Concept portraits and other names are placeholders.
- Preserve all actual equipment, recipes, prices, skills, branches, regions and monster IDs. Generated numerical examples and descriptions are not balance changes.
- In `07-combat-hud.png`, illustrative labels omit W. Actual gameplay requires **four Q/W/E/R ability slots plus dodge**, with source-defined bindings. Do not copy the mockup's incorrect labels or infer additional abilities.
- Minimap, tracking, export, difficulty and other suggested controls are visual examples only. Do not add unsupported functionality to match a picture.
- Preserve gameplay sprites and room/world art. The HUD image's scene and enemies are conceptual illustrations, not approved replacements.
- `04b-monster-codex-sharp.png` supersedes `04-monster-codex.png` for card size and detail hierarchy. Its M01 uses the newly generated source-grounded pincer construct portrait. Other depicted specimens and labels are illustrative, not authoritative M02–M06 identities.
- Production codex portraits are separate native high-resolution files under `assets/generated/ui/refactor_v1/codex/`; never crop a whole mockup for runtime art.
- The error modal demonstrates calm recovery hierarchy. Claims about save preservation and available recovery actions must reflect actual implementation.

## Coverage

1. Inventory/equipment and item detail/compare/set family
2. Hero dossier and roster
3. Skills and branch detail
4. Monster codex/detail, including sharper revised composition
5. Main menu
6. Settings and controls
7. Combat and testplay HUD
8. Camp/departure preparation
9. Shop and crafting family
10. Forge and recycle family
11. Trial selection
12. Route/room map and encounter details
13. Relic, supply and loot choice family
14. Saves/profiles and empty slots
15. Results/rewards, reusable success/defeat family
16. Recoverable error/dialog family

## Generation direction

All concepts share the supplied reference's warm ivory panels, sunlit forest atmosphere, dark readable type, deep teal selection/action states, fine antique-gold borders and rich painterly illustration. Each screen was generated separately with its screen-specific information hierarchy, then visually inspected. The revised codex explicitly requested six larger specimens, no haze on creature art and a large source-correct M01 detail. Runtime forest and decor provenance are recorded alongside production assets.

## Delivery limitation

Two supported Library prepared-upload attempts failed explicitly with `transfer_failed`; no Library attachment ID was produced. These committed PNGs are the durable design deliverables.
