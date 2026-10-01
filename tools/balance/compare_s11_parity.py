#!/usr/bin/env python3
"""Compare actual gameplay observations, excluding rendering/host timing and IDs.

No tolerance is silently applied. Different gameplay hashes remain visible even
when two runs share the same final outcome. Evidence is never merged by this tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def selected(row, names):
    return {name: row[name] for name in names if name in row}


def gameplay(row):
    result = selected(row, ("configuration", "outcome", "simulation_seconds", "physics_steps",
                           "physics_delta_min", "physics_delta_max", "hp_fraction", "hp_loss",
                           "shield_absorbed", "effective_player_healing", "effective_boss_healing",
                           "outgoing", "weakpoint_seconds", "attackable_seconds", "resource_empty_seconds",
                           "resource_rejections", "casts", "cast_failures", "phases", "states"))
    result["incoming_packets"] = [selected(x, ("t", "raw", "resolved", "hp_loss", "shield_absorbed",
                                                "hp_before", "hp_after", "shield_before", "shield_after",
                                                "source_id", "attack_id", "damage_type", "dot", "status", "damage_event", "key_states"))
                                  for x in row["incoming_packets"]]
    result["outgoing_packets"] = [selected(x, ("t", "amount", "kind", "feedback_kind", "target_kind",
                                                "target_template", "target_rank", "boss", "weakpoint", "damage_source",
                                                "skill_slot", "damage_type", "proc_depth", "critical", "X", "H"))
                                  for x in row["outgoing_packets"]]
    result["decisions"] = row["decisions"]
    result["samples"] = [selected(x, ("t", "hp", "shield", "resource", "boss_hp", "boss_shield", "phase",
                                       "player_position", "cooldowns", "hit_chain", "break_stacks", "native_boss_ai_elapsed",
                                       "active_enemy_hazards", "live_enemies", "equipment_counts", "objective_complete"))
                         for x in row["samples"]]
    return result


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def compare(left_path, right_path):
    left, right = [json.loads(p.read_text()) for p in (left_path, right_path)]
    if left.get("failures") or right.get("failures"):
        raise ValueError("Cannot compare reports with failed harness checks")
    allowed_protocol_differences = {"render_loop", "display_mode", "timing_mode", "capture_policy"}
    lp, rp = left["measurement_protocol"], right["measurement_protocol"]
    changed = {k: [lp.get(k), rp.get(k)] for k in lp.keys() | rp.keys() if lp.get(k) != rp.get(k)}
    if set(changed) - allowed_protocol_differences:
        raise ValueError("Source/engine/controller/fixture or experiment protocol changed: " + ", ".join(set(changed) - allowed_protocol_differences))
    lrows = {json.dumps(x["configuration"], sort_keys=True): x for x in left["cases"]}
    rrows = {json.dumps(x["configuration"], sort_keys=True): x for x in right["cases"]}
    if set(lrows) != set(rrows):
        raise ValueError("Case lists differ")
    cases = []
    for key in lrows:
        a, b = lrows[key], rrows[key]
        ag, bg = gameplay(a), gameplay(b)
        differences = [k for k in ag.keys() | bg.keys() if ag.get(k) != bg.get(k)]
        cases.append({"configuration": a["configuration"], "exact_gameplay_parity": not differences,
                      "left_gameplay_sha256": digest(ag), "right_gameplay_sha256": digest(bg),
                      "different_fields": differences, "simulation_seconds": [a["simulation_seconds"], b["simulation_seconds"]],
                      "host_wall_seconds": [a["host_wall_seconds"], b["host_wall_seconds"]],
                      "host_speed_ratio_left_over_right": a["host_wall_seconds"] / max(1e-9, b["host_wall_seconds"])})
    return {"left": str(left_path), "right": str(right_path), "protocol_differences": changed,
            "exact_gameplay_parity": all(x["exact_gameplay_parity"] for x in cases), "cases": cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = compare(args.left, args.right)
    text = json.dumps(result, indent=2, ensure_ascii=False)
    if args.output:
        args.output.write_text(text + "\n")
    print(text)
    raise SystemExit(0 if result["exact_gameplay_parity"] else 1)


if __name__ == "__main__":
    main()
