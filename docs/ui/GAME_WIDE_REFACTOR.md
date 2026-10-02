# Game-wide interface refactor

## Baseline and scope

Started from `origin/main` at `4283578` on 2026-10-02. PR #2 is already merged (`39ec7e3`); this independent UI branch retains its eight-slot instances, transactions, migration, and subsequent loot/performance fixes. S11 remains deferred. No combat balance work, gameplay tuning, merging, or player-save changes belong to this refactor.

The supplied visual reference is the approved direction: warm ivory, restrained antique gold, teal selected states, atmospheric forest, slim horizontal navigation, generous artwork and clear live typography. Concept illustrations are design references, not runtime screenshots or proof of functionality. The runtime remains Godot Control-based, with live translated labels and existing callbacks; `canvas_items` scaling preserves vector text at 2560×1440.

## Ownership and architecture

- Shared `MineStyle`, button skin, panel ornament and menu backdrop establish the visual system
- `main.gd` owns route transitions, menus, settings, saves, confirmations, reward flows and results
- `workshop_panel.gd` hosts heroes, skills, inventory, set shop, directed crafting, forging and recycling
- Equipment catalog/grid/details/inspection retain instance IDs and existing transaction APIs
- Hero dossier, skill inspection and stat sheet share the visual system
- New monster codex reads production enemy/boss catalogs; it does not invent mechanics
- HUD, skill slots, route and loot panels retain pause/input behavior and real values

## Coverage checklist

The status below distinguishes implemented behavior from final graphical acceptance. The draft PR remains in progress.

| Family | Screens and states | Current result | Remaining acceptance |
|---|---|---|---|
| Entry | Main menu, continue disabled, new-profile confirmation | New ivory navigation column, live hero card and functional profile entry; 2K zh/en captured | Final small-window pass |
| Camp | Departure, region/difficulty, save warning, navigation | Shared slim navigation with profile/codex access; gameplay decisions unchanged | Recheck final header at both sizes |
| Heroes | Three dossiers, progression, selection, equipment, attributes | New selector, illustrated dossier and stat-source table; corrected metadata backing and percent cells | Recapture latest corrections |
| Skills | Growth, branches, per-skill details, locked/unlocked states | Art-led four-skill ledger and consistent detail sheets | Final bilingual focus/scroll review |
| Inventory | Eight slots, search/filter/sort, empty, stats/compare/set, recycle | Slim top nav, five-column grid, eight-slot rail and raised detail; text/table widths fixed | Final all-state recapture |
| Shop | Set/single catalog, purchase, funds, owned states | Three-column catalog/preview/order; all eight-piece controls retained | Final low-funds/error pixels |
| Craft/forge | Craft, enhance, affixes, reroll, inheritance, lock, frozen results/errors | Seven operations preserved, separate preview/order, bounded cost/result scroll | Final frozen-error screenshots |
| Bestiary | Four factions, 36 enemies, four bosses and skill details | All 40 production entries, level/difficulty previews, six-card layout and wider inspector | HD normal-enemy portraits in progress; latest layout recapture |
| Settings | General/audio/display, controls, binding capture/conflicts/reset | Side-rail layout, live saved settings and key bindings; 2K zh/en captured | Repeated binding/cancel interaction review |
| Trial | Hero select, branches, briefing, play, pause, exit | Shared visual language applied; live trial launches and returns | Final state/keyboard review |
| Combat | HUD, cooldowns, buffs, attributes, backpack, boss casts | Ivory scalable surfaces, larger skill artwork, existing QWER/dodge and live values | Final render after latest plate/icon changes |
| Expedition | Route/current room, relics, supply, loot | Shared surfaces and equipment comparison refactor; vector route/map geometry retained | Final reward/error screenshots and map-specific polish |
| Save/results | Save/quit, abandon, extraction, retry/error, death review/result | Consistent modal system, equal paired actions, new read-only profile overview | Final outcome/error coverage |
| Room environment | Actual terrain/walls/background clarity | Separate native-source density audit underway | No world-art completion claimed; preserve geometry/collisions |

## Checkpoints and evidence

- Baseline: current-main Godot 4.7.2 OpenGL/X11 captured 102 zh/en UI states; 115 fixture checks passed. Existing resource-in-use-at-exit warning recorded; this is not a clean-engine pass.
- Second V2 graphical gallery: 54 actual 2560×1440 screenshots, 1,066 bounds/output assertions passed, no script/engine errors (Mesa V-sync capability warning only). Later codex/metadata/width refinements require recapture. First gallery exposed a codex reserved-word parse issue and was not counted as clean.
- Dedicated hero/codex checks: 249 passed, covering 40 identities, art bounds, real stats/skills, filtering, selection, three heroes, 27 V2 stat sources, both languages and unchanged save bytes.
- Instance UI: 29 passed. Acquisition: 347 passed. Forging: 62 passed. Separate-column acquisition bounds replaced a stale same-column assumption with actual rectangle nonintersection; transaction assertions remain intact.
- Workshop layout smoke: 59 passed. Expedition panel smoke: 87 passed. These are targeted checks, not substitutes for natural gameplay or balance validation.
- Full bilingual text audit: 1,519 assertions, 102 routes, zero failures in headless mode. Existing `custom_samplers` world-shader diagnostic occurs with the dummy renderer and remains disclosed.
- HUD controls/reflow: 28 assertions, zero failures including 2560×1440; same headless world-shader diagnostic. No S11 sampling ran.
- Continuous live preview uses an isolated test profile and remains under user control; it is not replaced by auto-closing screenshot automation.

### Native asset resolution

- Forest UI backdrop: 1672×941 native, intentionally soft atmosphere; not described as native 2K art.
- Compass and panel ornament: 1254×1254 native RGBA, substantially above actual UI display size.
- Codex normal-enemy portraits: dedicated 1254×1254 art is being supplied per catalog ID. Missing entries use original art without enlargement beyond source physical pixels. Bosses use the exact production `EnemyArt` storybook atlas regions (approximately231–286px), capped to source pixels. The standalone1254px legacy boss images are not the active battle identities and must not be used by the codex.
- Live fonts, frames, room emblems, room-map polygons and route glyphs remain resolution-independent drawing primitives. Route thumbnails display native 1536px room sources well below their native pixel dimensions; actual fullscreen room backgrounds are a separate density problem.

## Verification boundary

Use isolated test profiles only. Capture before/after runtime screenshots in the ignored `artifacts/` directory. Verify affected flows in Chinese and English, 1280×720 compatibility and 2560×1440 output. Test repeated/cancel/back/disabled states and existing transaction suites without restarting balance sampling. Record exact passed/failed/unrun checks and asset source dimensions; do not describe an upscaled image as native 1440p artwork.
