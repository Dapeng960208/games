#!/usr/bin/env python3
"""Reproduce selected round-two audit calculations, without running the game.

Manually transcribed from commit 5046cfdb6bdf483b7d1dd474364b1138a0ee3668.
This is NOT a production-data reader, Godot test, save validator, exploit against
an account, or estimate of player behavior. It neither opens nor changes saves.
The ledger example is synthetic; its compact JSON byte count is a lower bound
for the same records in an indented, complete save document.
Run: python docs/audits/interaction_models_2026_10_01.py
"""
from __future__ import annotations

from copy import deepcopy
import json
import math
from typing import Any

BASE_COMMIT = "5046cfdb6bdf483b7d1dd474364b1138a0ee3668"
READ_LIMIT = 1_048_576
TRANSACTION_LIMIT = 4096
SLOT_PRICES = (180, 140, 180, 120, 120, 160)
UPGRADE_COSTS = (60, 100, 160, 240, 340)


def check(results: list[str], name: str, condition: bool) -> None:
    if not condition:
        raise AssertionError(name)
    results.append(name)


def rounded_positive(value: float) -> int:
    """Godot-style round for the nonnegative values used in this model."""
    if not math.isfinite(value) or value < 0:
        raise ValueError("Expected a finite nonnegative value")
    return math.floor(value + 0.5)


def eq01_stats(level: int) -> dict[str, int]:
    if level not in range(6):
        raise ValueError("Expected refinement level 0..5")
    return {key: rounded_positive(base * (1 + 0.1 * level))
            for key, base in {"attack": 4, "armor_penetration": 3}.items()}


def sale_price(price: int, level: int = 0) -> int:
    return price // 4 + sum(cost // 5 for cost in UPGRADE_COSTS[:level])


def add_drop_model(pending: dict[str, int], owned: dict[str, int],
                   item: str, level: int, price: int) -> dict[str, Any]:
    """Only the pending-vs-duplicate decision; not the persistence pipeline."""
    after = pending.copy()
    if item in pending or (item in owned and level <= owned[item]):
        return {"pending": after, "gold": price // 10, "result": "gold"}
    after[item] = level
    return {"pending": after, "gold": 0, "result": "pending"}


def synthetic_ledger(cycles: int = 1000) -> dict[str, Any]:
    """Three six-piece purchases and one batch sale per cycle.

    Shapes/prices match S01-S03 receipts. A hypothetical profile has unlocked
    their bosses, equips other gear, and has enough earned gold. This generator
    does not claim to validate such a profile in Godot.
    """
    sets = {f"S{k:02d}": [f"EQ{k + 2 + 10 * slot:02d}" for slot in range(6)]
            for k in (1, 2, 3)}
    ledger: dict[str, Any] = {"starter_grant_v1": {"kind": "starter"}}
    for cycle in range(cycles):
        for offset, (set_id, ids) in enumerate(sets.items()):
            ledger[f"{4 * cycle + offset + 1:032x}"] = {
                "kind": "purchase_set", "item": set_id,
                "price": 810, "items": ids.copy(),
            }
        ids = sorted(item for pieces in sets.values() for item in pieces)
        records = {item: {"level": 0, "price": price // 4}
                   for pieces in sets.values()
                   for item, price in zip(pieces, SLOT_PRICES)}
        ledger[f"{4 * cycle + 4:032x}"] = {
            "kind": "sale", "item": ",".join(ids),
            "items": records, "price": 675,
        }
    return {"profile": {"applied_transactions": ledger}}


def same_status_write(old_power: float, old_clock: float,
                      new_power: float, new_clock: float) -> float:
    """Only power resolution, not duration, combat, or stacking DPS."""
    return max(old_power, new_power) if old_clock == new_clock else new_power


def main() -> None:
    checks: list[str] = []
    first = add_drop_model({}, {"EQ03": 0}, "EQ03", 1, 180)
    later = add_drop_model(first["pending"], {"EQ03": 0}, "EQ03", 2, 180)
    check(checks, "higher second drop is converted to gold", later["result"] == "gold")
    check(checks, "pending refinement remains +1 rather than +2", later["pending"]["EQ03"] == 1)
    check(checks, "automatic conversion is 10 percent of base price", later["gold"] == 18)

    old_sale = sale_price(180)
    new_sale = sale_price(200)
    check(checks, "old sale price differs after catalog repricing", (old_sale, new_sale) == (45, 50))
    repriced_parts = (200,) + SLOT_PRICES[1:]
    old_set = sum(price * 9 // 10 for price in SLOT_PRICES)
    new_set = sum(price * 9 // 10 for price in repriced_parts)
    check(checks, "old set receipt differs after one component repricing", (old_set, new_set) == (810, 828))

    ledger = synthetic_ledger()
    ledger_count = len(ledger["profile"]["applied_transactions"])
    compact_bytes = len(json.dumps(ledger, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
    indented_bytes = len(json.dumps(ledger, indent="\t", ensure_ascii=False).encode("utf-8"))
    check(checks, "synthetic ledger stays below transaction cap", ledger_count == 4001 < TRANSACTION_LIMIT)
    check(checks, "compact partial document already exceeds reader limit", compact_bytes > READ_LIMIT)

    refinement = [{"level": level, **eq01_stats(level)} for level in range(6)]
    check(checks, "starter weapon +0 to +1 has no base-stat increase", eq01_stats(0) == eq01_stats(1))
    check(checks, "starter weapon +2 to +3 also has no base-stat increase", eq01_stats(2) == eq01_stats(3))
    check(checks, "first plateau still has a 60-gold cost", UPGRADE_COSTS[0] == 60)

    # When this is the only missing suitable item, fresh-first selection picks it.
    pool = ["EQ03", "EQ13", "EQ23"]
    owned_after_sale = ["EQ13", "EQ23"]
    fresh = [item for item in pool if item not in owned_after_sale]
    check(checks, "selling the only missing target restores fresh priority", fresh == ["EQ03"])
    check(checks, "successful reacquisition delta versus duplicate conversion", sale_price(180) - 180 // 10 == 27)

    energy_seconds = (100 * 0.20) / 18
    mana_seconds = (100 * 0.30) / 5
    check(checks, "resource replacement time excludes activation delay", math.isclose(energy_seconds, 10 / 9) and mana_seconds == 6)
    check(checks, "death keeps more gold than abandonment under current rules", (1000 // 2, 1000 // 5) == (500, 200))
    check(checks, "first Q branch is at 85 percent of cumulative XP cap", math.isclose(3060 / 3600, 0.85))

    guards = {"class": 12.0, "equipment": 5.0}
    absorbed = min(max(guards.values()), 10.0)
    after_guards = {key: max(0.0, amount - absorbed) for key, amount in guards.items()}
    check(checks, "simultaneous shields are max-based and both are consumed", after_guards == {"class": 2.0, "equipment": 0.0})
    check(checks, "same-clock status writes keep the stronger power", same_status_write(100, 0, 20, 0) == 100)
    check(checks, "later weaker status overwrites stronger power", same_status_write(100, 0, 20, 0.1) == 20)
    check(checks, "skipping relic at full HP produces no healing", min(100 - 100, 100 * 0.06) == 0)

    # The normal-room race reward path passes base_count=1, not option.count.
    l02 = {"full": {"gold": 18, "equipment_count": 1},
           "reduced": {"gold": 34, "equipment_count": 1}}
    check(checks, "L02 race-policy reduced quality keeps gear and more gold", l02["reduced"]["gold"] > l02["full"]["gold"] and l02["full"]["equipment_count"] == l02["reduced"]["equipment_count"])

    output = {
        "base_commit": BASE_COMMIT,
        "evidence": "manually transcribed arithmetic and policy models; NOT Godot execution",
        "checks_passed": len(checks), "checks": checks,
        "higher_drop": later,
        "repricing": {"sale_before": old_sale, "sale_after": new_sale,
                      "set_before": old_set, "set_after": new_set},
        "save_size": {"synthetic_transactions": ledger_count, "transaction_limit": TRANSACTION_LIMIT,
                      "compact_partial_document_bytes": compact_bytes,
                      "python_indented_partial_document_bytes": indented_bytes,
                      "reader_limit_bytes": READ_LIMIT},
        "starter_weapon_refinement": refinement,
        "reacquisition": {"sale": 45, "duplicate_conversion": 18, "conditional_delta": 27,
                          "conditions": "eligible pool otherwise owned; unenhanced unequipped item; successfully extract same item"},
        "resource_wait_seconds_after_regen_starts": {"energy": energy_seconds, "mana": mana_seconds},
        "shield_after_10_damage": after_guards,
        "l02_race_reward_policy_at_difficulty_zero": deepcopy(l02),
        "limits": ["No full-save validation or loading", "No Godot runtime or UI screenshots",
                   "No player timing, win rate, or retention evidence",
                   "L02 quality branch reachability in the current room lifecycle remains unverified"],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
