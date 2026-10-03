# B05 isolated candidate traversal

2026-10-02. Candidate integration only; B05 is not accepted or released.

## Gate and preview

The shipped `data/numerical_v2.json` remains `implemented_chapters: 4`.
B06 remains unavailable. A debug process enables the B05 adapter only with both:

- `--candidate-b05`
- `--test-profile=user://test_b05_candidate/<name>.json`

The argument validator rejects missing, duplicate, ordinary-profile, traversal,
backslash and non-JSON paths. Existing profile storage creates the isolated
folder. The process override never rewrites numerical JSON. A saved candidate
checkpoint is resumable only in the explicitly enabled process. Do not copy
candidate saves into the ordinary player profile.

Use the managed runner so user data, temporary files and logs stay isolated and
Godot shares the cross-worktree lock:

```
python tools/test_workspace.py run --biome B05 -- godot --headless --path . tests/test_b05_candidate_traversal.tscn -- --candidate-b05 --test-profile=user://test_b05_candidate/traversal.json
```

The test creates synthetic BO04-completed profiles for CH01/CH02/CH03. For manual
preview, use the same two user arguments with the ordinary main scene and an
isolated candidate profile. BO04 completion remains mandatory; the flag does not
silently grant unlocks, XP, equipment or rewards.

## Contracts

- Runtime adapter consumes current `b05_content.json` and frozen geometry, not
  archived design or copied first-four definitions.
- Default catalog: 24 ordinary rooms, 54 species, four regions/four bosses.
  Candidate catalog: 30/72/5/5.
- New B05 runs use route version two. Twelve stations are retained. Six combat
  introductions are ordered L25–L30; remaining combat slots reuse the back-zone
  rooms. Lv20 entrants therefore begin in the Lv21 teaching room.
- Version-one descent preserves its original four-region ring. Existing content
  version and historical route/receipt contracts are unchanged.
- L25 uses two existing anchor points with one sequential wave each. Other rooms
  use three existing anchors, one wave each; L30 has exactly three finite waves.
  Frozen geometry is not relocated. Every D0 species is present across six rooms.
- Enemy and reward levels are room-fixed 21/23/25. Each wave respects six actors
  and shared eighteen-room capacity. Difficulty support replaces ordinary slots;
  D3+ has one final-zone elite. Summon rewards remain excluded.
- Existing 35-template equipment registration and class-aware 19-item natural
  pools are enabled only for this candidate process. No proposed first-boss pool
  selection UI or extra reward count is implemented.

## Verification scope

The focused candidate scene verifies catalog, flags, levels, finite plans,
version-one/two routing, three-class BO04 prerequisite, all six rooms plus BO05,
natural-kill and completion receipt idempotence, summon exclusion, extraction,
banking and real disk reload. Combat boundaries are synthetic; successful
transactions are not natural combat, balance, artwork or hardware acceptance.

Remaining acceptance: seven-room actual-host integration; natural three-class
B04-to-B05 combat; root/bridge/warning readability and safe routes; D0–D4 legal
mixed-set timing and resource behavior; rendered/UI checks. No S11/fullscreen or
full-suite run is implied.

### Verified focused results (Godot 4.6.3)

- Candidate integration: 652 checks, zero failures, including Lv25 saved departure.
- Closed candidate gate: 8 checks, zero failures.
- Single-biome routes: 44 checks in closed mode and 44 in candidate mode.
- Dynamic route regression: 31,698 checks, zero failures.
- Legacy authored route regression: 365,660 checks, zero failures. Its stale
  pre-expansion 36-species assertion was corrected to the existing 54-species gate.
- B05 acquisition/progression/save: 2,693 checks, zero failures. Its synthetic
  L28 fixture now includes room-authored level23 rather than assuming zone level.

All tests used the managed runner; no test artifacts or synthetic saves are
committed. These results do not waive the remaining acceptance gates above.
