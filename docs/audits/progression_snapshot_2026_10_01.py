#!/usr/bin/env python3
"""Reproduce arithmetic in the 2026-10-01 Abyss Salvager audit.

This is a manually transcribed model of commit 5046cfdb6bdf483b7d1dd474364b1138a0ee3668,
NOT an engine test and NOT a reader of current production data. It does not model
combat, elapsed time, RNG, purchase efficiency, or actual player retention.
Run: python docs/audits/progression_snapshot_2026_10_01.py
"""
from itertools import product
import json

BASE_COMMIT = "5046cfdb6bdf483b7d1dd474364b1138a0ee3668"
XP = (0, 30, 70, 120, 170, 230, 290, 360, 630, 900, 1170,
      1440, 1710, 1980, 2250, 2520, 2790, 3060, 3330, 3600)
MASTERY_THRESHOLDS = (0, 100, 240, 420, 640, 900)
ROUTES = ((1, 4, 6, 3), (5, 9, 8, 5), (10, 14, 10, 7), (15, 20, 12, 9))
SOURCES = {
    "xp_and_upgrade_costs": "scripts/data/content_registry.gd",
    "route_lengths": "scripts/world/route_generator.gd",
    "relic_pool_and_mastery": "scripts/core/expedition_state.gd",
    "relic_awards_and_skip": "scripts/core/run_controller.gd",
    "room_rewards": "scripts/world/room_rewards.gd",
    "enemy_scaling": "scripts/combat/enemy_difficulty.gd",
}


def relic_vectors(picks: int) -> list[list[int]]:
    """All cap-two terminal vectors for three relics, assuming no healing skips."""
    return [list(v) for v in product(range(3), repeat=3) if sum(v) == picks]


def model() -> dict:
    routes = []
    for low, high, nodes, rooms in ROUTES:
        mastery = min(900, rooms * 180)
        picks = sum(mastery >= threshold for threshold in MASTERY_THRESHOLDS)
        routes.append({
            "departure_levels": [low, high], "total_nodes": nodes,
            "ordinary_combat_nodes": rooms, "boss_nodes": 1,
            "service_nodes": 2, "mastery": mastery, "relic_offers": picks,
            "no_skip_terminal_relic_vectors": relic_vectors(picks),
            "full_clear_xp_excluding_first_tutorial": rooms * 30 + 80,
            "minimum_reused_combat_slots_from_six_templates": max(0, rooms - 6),
        })
    rewards = []
    for difficulty in range(5):
        low = max(0, difficulty - 1)
        high = low + (1 if difficulty == 1 else 0)
        boss_add = 1 if difficulty >= 1 else 0
        rewards.append({
            "difficulty": difficulty,
            "ordinary_item_count": 1 + int(difficulty >= 2),
            "ordinary_upgrade_range": [min(3, low), min(3, high)],
            "boss_item_count": 2 + difficulty // 2,
            "boss_upgrade_range": [min(3, low + boss_add), min(3, high + boss_add)],
            "base_gold_multiplier_before_rounding": 1 + .25 * difficulty,
            "normal_xp": 30, "boss_xp": 80,
        })
    return {
        "base_commit": BASE_COMMIT, "evidence_type": "arithmetic_snapshot_not_engine_test",
        "sources": SOURCES, "routes": routes, "reward_tiers": rewards,
        "xp_step_7_to_8": XP[7] - XP[6],
        "xp_step_8_to_9": XP[8] - XP[7],
        "xp_step_ratio": (XP[8] - XP[7]) / (XP[7] - XP[6]),
        "six_items_upgrade_0_to_5_cost": 6 * sum((60, 100, 160, 240, 340)),
        "six_items_upgrade_3_to_5_cost": 6 * sum((240, 340)),
        "normal_enemy_d4_scaling_before_level_and_armor_effects": {
            "hp_multiplier": 1.48, "damage_multiplier": 1.4,
            "speed_multiplier": 1.16, "armor_add": 8, "magic_resist_add": 8,
        },
        "limits": [
            "Relic vectors exclude skip-for-healing decisions and describe relic levels only, not whole character builds.",
            "Gold excludes duplicate conversion, optional rewards, enemy gold, supplies and extraction outcomes.",
            "XP excludes the once-per-hero 30 XP tutorial, deaths and early extraction.",
            "No duration, drop RNG, DPS, win rate, fun or retention is estimated.",
            "Source constants must be rechecked before applying this model to another commit.",
        ],
    }


def validate(result: dict) -> None:
    checks = {
        "route_counts": all(r["total_nodes"] == r["ordinary_combat_nodes"] + 3 for r in result["routes"]),
        "xp_steps": (result["xp_step_7_to_8"], result["xp_step_8_to_9"]) == (70, 270),
        "short_route_vectors": len(result["routes"][0]["no_skip_terminal_relic_vectors"]) == 6,
        "long_route_convergence": all(r["no_skip_terminal_relic_vectors"] == [[2, 2, 2]] for r in result["routes"][1:]),
        "d1_upgrade_ranges": result["reward_tiers"][1]["ordinary_upgrade_range"] == [0, 1] and result["reward_tiers"][1]["boss_upgrade_range"] == [1, 2],
        "d3_d4_boss_cap": all(result["reward_tiers"][d]["boss_upgrade_range"] == [3, 3] for d in (3, 4)),
        "d3_d4_ordinary_difference": result["reward_tiers"][3]["ordinary_upgrade_range"] == [2, 2] and result["reward_tiers"][4]["ordinary_upgrade_range"] == [3, 3],
        "upgrade_costs": result["six_items_upgrade_0_to_5_cost"] == 5400 and result["six_items_upgrade_3_to_5_cost"] == 3480,
    }
    failures = [name for name, passed in checks.items() if not passed]
    if failures:
        raise RuntimeError("Snapshot arithmetic checks failed: " + ", ".join(failures))
    result["snapshot_checks_passed"] = len(checks)


if __name__ == "__main__":
    result = model()
    validate(result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
