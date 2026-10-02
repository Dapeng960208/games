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

Status begins as pending; updating a theme alone does not establish page-specific acceptance.

| Family | Screens and states | Design | Runtime | Verification |
|---|---|---|---|---|
| Entry | Main menu, continue disabled, new-profile confirmation | Pending | Pending | Pending |
| Camp | Departure, region/difficulty choice, save capacity/warning, navigation | Pending | Pending | Pending |
| Heroes | Three dossiers, progression, selection, equipment, attributes | Pending | Pending | Pending |
| Skills | Growth, branches, per-skill details, locked/unlocked states | Pending | Pending | Pending |
| Inventory | Eight slots, search/filter/sort, empty list, item stats/compare/set, recycle | Reference viewed | Pending | Pending |
| Shop | Set catalog, single items, purchase, insufficient funds, owned states | Pending | Pending | Pending |
| Craft/forge | Directed craft, enhance, affix improvement, reroll, inheritance, results/errors | Pending | Pending | Pending |
| Bestiary | Four faction catalogs, 36 enemy entries, four boss entries and skill details | Pending | Pending | Pending |
| Settings | General, audio, display, controls, binding capture/conflicts/reset | Pending | Pending | Pending |
| Trial | Hero select, branch preview, briefing, play, pause, exit | Pending | Pending | Pending |
| Combat | HUD, skills/cooldowns, buffs, attributes, backpack, boss cast UI | Pending | Pending | Pending |
| Expedition | Route choice/current room, relic choice/details, supply, loot comparison | Pending | Pending | Pending |
| Save/results | Save/quit, abandon, extraction, retry/error, death review and result | Pending | Pending | Pending |

## Verification boundary

Use isolated test profiles only. Capture before/after runtime screenshots in the ignored `artifacts/` directory. Verify affected flows in Chinese and English, 1280×720 compatibility and 2560×1440 output. Test repeated/cancel/back/disabled states and existing transaction suites without restarting balance sampling. Record exact passed/failed/unrun checks and asset source dimensions; do not describe an upscaled image as native 1440p artwork.
