#!/usr/bin/env python3
"""Run and summarize S11 production-scene input experiments in isolated saves.

Raw reports/logs stay outside the repository. A zero process exit establishes
instrumentation integrity, never that the numerical calibration gates passed.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ("G2", "P5", "G0", "mixed", "green", "white", "lowG2")
SEEDS = list(range(1001, 1011))
SCHEMA = "s11-controlled-matrix-v2"


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def measurement_protocol(args, manifest):
    with args.godot.open("rb") as binary:
        engine_sha = hashlib.file_digest(binary, "sha256").hexdigest()
    control = (ROOT / "tests/support/s11_battle_controller.gd").read_text()
    controller_version = re.search(r'const VERSION := "([^"]+)"', control).group(1)
    data = json.loads((ROOT / "data/numerical_v2.json").read_text())
    return {"schema": SCHEMA, "protocol_pinned": True, "seeds": args.seeds,
            "max_seconds": args.max_seconds, "timing_mode": "real_time" if args.real_time else "fixed_fps",
            "display_mode": "gpu" if args.gpu else "headless", "probe": args.probe,
            "physics_hz": 60, "time_scale": 1, "controller_version": controller_version,
            "source_fingerprint": fingerprint(manifest["sha256"]), "engine_sha256": engine_sha,
            "calibration": data["enemy_calibration"],
            "boss_seed_policy": "production configure_boss with requested seed before clock and physics"}


def source_manifest():
    selected = [ROOT / "project.godot"]
    selected += list((ROOT / "config").glob("*.gd"))
    selected += list((ROOT / "scripts").rglob("*.gd"))
    selected += list((ROOT / "scenes").rglob("*.tscn"))
    selected += list((ROOT / "data").glob("*.json"))
    selected += list((ROOT / "tests/support").glob("s11_*.gd"))
    selected += [ROOT / "tests/test_s11_battle_matrix.gd"]
    result = {
        "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "git_status": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).splitlines(),
        "sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in selected if p.exists()},
    }
    if (ROOT / "s11_snapshot_overlay.json").exists():
        result["frozen_snapshot"] = json.loads((ROOT / "s11_snapshot_overlay.json").read_text())
    return result


def run_job(args, case):
    chapter, hero, sample, difficulty, room_id = case
    label = f"{room_id or f'B{chapter:02d}'}_{hero}_{sample}_D{difficulty}"
    job = args.output / label
    job.mkdir(parents=True, exist_ok=True)
    report = job / "observations.json"
    if args.resume and report.exists():
        prior = json.loads(report.read_text())
        execution = json.loads((job / "execution.json").read_text()) if (job / "execution.json").exists() else {}
        configurations_match = all(r["configuration"]["chapter"] == chapter and r["configuration"]["hero_id"] == hero
                                   and r["configuration"]["sample"] == sample and r["configuration"]["difficulty"] == difficulty
                                   and r["configuration"].get("room_id", "") == room_id for r in prior.get("cases", []))
        if (prior.get("measurement_protocol") == args.protocol and not prior.get("failures")
                and [r["configuration"]["seed"] for r in prior.get("cases", [])] == args.seeds
                and execution.get("status") == "ok" and configurations_match):
            return label, "reused"
    env = dict(os.environ)
    for name, suffix in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        env[name] = str(job / suffix)
    timing = ["--max-fps", "60"] if args.real_time else ["--fixed-fps", "60"]
    display = [] if args.gpu else ["--headless"]
    command = [str(args.godot), *display, *timing, "--path", str(ROOT),
               "res://tests/test_s11_battle_matrix.tscn", "--",
               "--test-profile=user://test_s11_battle_matrix/profile.json", "--test-ruleset=2",
               f"--chapters={chapter}", f"--heroes={hero}", f"--samples={sample}",
               f"--difficulties={difficulty}", "--seeds=" + ",".join(map(str, args.seeds)),
               f"--max-seconds={args.max_seconds}", f"--output={report}",
               f"--protocol-file={args.output / 'measurement_protocol.json'}",
               "--timing-mode=" + ("real_time" if args.real_time else "fixed_fps")]
    if args.probe:
        command.append("--probe=true")
    if room_id:
        command.append(f"--room-id={room_id}")
    start = time.monotonic()
    with (job / "engine.log").open("w") as log:
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=max(180, args.max_seconds * len(args.seeds) * 4))
        except subprocess.TimeoutExpired:
            log.write("\nERROR: Harness host wall watchdog expired\n")
            result = subprocess.CompletedProcess(command, 124)
    log_text = (job / "engine.log").read_text()
    status = "ok" if result.returncode == 0 and "SCRIPT ERROR" not in log_text and "ERROR:" not in log_text else "error"
    (job / "execution.json").write_text(json.dumps({"command": command, "returncode": result.returncode,
                                                   "wall_seconds": time.monotonic() - start, "status": status}, indent=2))
    print(f"{label}: {status} ({time.monotonic()-start:.2f}s host wall)", flush=True)
    return label, status


def median(values):
    return statistics.median(values) if values else None


def summarize(output: Path):
    rows, errors, groups, duplicates = [], [], {}, []
    room_rows, room_groups, room_seen = [], {}, set()
    seen = set()
    common_protocol = None
    for execution_path in sorted(output.glob("*/execution.json")):
        execution = json.loads(execution_path.read_text())
        if execution.get("status") != "ok":
            errors.append({"report": str(execution_path), "error": "execution did not complete cleanly", "returncode": execution.get("returncode")})
    for path in sorted(output.glob("*/observations.json")):
        try:
            doc = json.loads(path.read_text())
        except json.JSONDecodeError:
            errors.append({"report": str(path), "error": "incomplete JSON report"})
            continue
        protocol = doc.get("measurement_protocol")
        if not isinstance(protocol, dict) or protocol.get("schema") != SCHEMA or protocol.get("protocol_pinned") is not True:
            raise ValueError(f"Unpinned/legacy protocol in {path}; retain as diagnostic only, never merge into calibrated evidence")
        if common_protocol is None:
            common_protocol = protocol
        elif protocol != common_protocol:
            raise ValueError(f"Mixed measurement protocols rejected: {path}")
        if doc.get("controller") != protocol["controller_version"] or doc.get("timing_mode") != protocol["timing_mode"] or doc.get("probe") != protocol["probe"]:
            raise ValueError(f"Runtime metadata does not match pinned protocol: {path}")
        execution_path = path.parent / "execution.json"
        execution = json.loads(execution_path.read_text()) if execution_path.exists() else {}
        if execution.get("status") != "ok":
            errors.append({"report": str(path), "error": "incomplete execution excluded from balance statistics"})
            continue
        errors.extend({"report": str(path), "error": error} for error in doc.get("failures", []))
        for row in doc.get("cases", []):
            c = row["configuration"]
            if c.get("encounter") == "room":
                room_key = (c["room_id"], c["hero_id"], c["sample"], c["difficulty"], c["seed"])
                if room_key in room_seen:
                    duplicates.append(room_key)
                    continue
                room_seen.add(room_key)
                room_rows.append(row)
                room_groups.setdefault(room_key[:4], []).append(row)
                continue
            key = (c["chapter"], c["hero_id"], c["sample"], c["difficulty"], c["seed"])
            if key in seen:
                duplicates.append(key)
                continue
            seen.add(key)
            rows.append(row)
            groups.setdefault(key[:4], []).append(row)
    summaries = []
    for (chapter, hero, sample, difficulty), fights in sorted(groups.items()):
        victories = [x for x in fights if x["outcome"] == "boss_defeated" and x["hp_fraction"] > 0]
        ttk = [x["simulation_seconds"] for x in victories]
        hp = [x["hp_fraction"] for x in fights]
        summary = {"chapter": chapter, "hero_id": hero, "sample": sample, "difficulty": difficulty,
                   "seeds": sorted(x["configuration"]["seed"] for x in fights), "n": len(fights), "wins": len(victories),
                   "timeouts": sum(x["outcome"] == "time_limit" for x in fights),
                   "median_victory_ttk": median(ttk), "worst_victory_ttk": max(ttk) if ttk else None,
                   "median_end_hp_all_fights": median(hp), "worst_end_hp": min(hp),
                   "median_hp_loss": median([x["hp_loss"] for x in fights]),
                   "median_shield_absorbed": median([x["shield_absorbed"] for x in fights]),
                   "median_effective_player_healing": median([x["effective_player_healing"] for x in fights]),
                   "median_effective_boss_healing": median([x["effective_boss_healing"] for x in fights]),
                   "median_resource_empty_seconds": median([x["resource_empty_seconds"] for x in fights]),
                   "skipped_phase_fights": sum(bool(x["phase_casts_skipped_by_output_or_termination"]) for x in fights),
                   "probe": any(x.get("probe") for x in fights), "gates": {}, "failures": []}
        node_hp, node_shield, detonation_hp, remote_decisions = [], [], [], []
        for fight in fights:
            node_packets = [p for p in fight.get("outgoing_packets", []) if p.get("boss") and p["kind"] in ("node", "node_echo", "node_detonation")]
            node_hp.append(sum(p["amount"] for p in node_packets if p["feedback_kind"] != "shield"))
            node_shield.append(sum(p["amount"] for p in node_packets if p["feedback_kind"] == "shield"))
            detonation_hp.append(sum(p["amount"] for p in node_packets if p["kind"] == "node_detonation" and p["feedback_kind"] != "shield"))
            remote_decisions.append(sum(d.get("mode") == "remote_node_detonation" for d in fight.get("decisions", [])))
        summary["nodes"] = {"median_actual_boss_hp_loss": median(node_hp), "median_actual_boss_shield_loss": median(node_shield),
                            "median_detonation_boss_hp_loss": median(detonation_hp), "fights_with_detonation_hp_loss": sum(x > 0 for x in detonation_hp),
                            "remote_e_decisions": sum(remote_decisions)}
        complete = summary["seeds"] == SEEDS and not summary["probe"]
        if difficulty == 4 and sample in ("G2", "P5", "lowG2"):
            summary["gates"]["complete_10_seed_evidence"] = complete
            summary["gates"]["wins"] = len(victories) >= (9 if sample == "P5" else 10)
            if sample == "G2":
                summary["gates"].update(ttk=bool(ttk) and 35 <= median(ttk) <= 50, hp=median(hp) >= .60)
            elif sample == "lowG2":
                summary["gates"].update(ttk=bool(ttk) and median(ttk) <= 60, hp=median(hp) >= .45)
        summaries.append(summary)
    lookup = {(x["chapter"], x["hero_id"], x["sample"], x["difficulty"]): x for x in summaries}
    for summary in summaries:
        if summary["sample"] == "P5" and summary["difficulty"] == 4:
            gold = lookup.get((summary["chapter"], summary["hero_id"], "G2", 4))
            summary["gates"]["complete_paired_gold_reference"] = bool(gold and gold["seeds"] == SEEDS and not gold["probe"])
            if gold and gold["median_victory_ttk"] is not None and summary["median_victory_ttk"] is not None:
                ratio = summary["median_victory_ttk"] / gold["median_victory_ttk"]
                gap = gold["median_end_hp_all_fights"] - summary["median_end_hp_all_fights"]
                summary["gold_comparison"] = {"ttk_ratio": ratio, "hp_percentage_point_gap": 100 * gap}
                summary["gates"]["gold_gap"] = ratio >= 1.15 or gap >= .15
            else:
                summary["gates"]["gold_gap"] = False
        summary["failures"] = [name for name, ok in summary["gates"].items() if not ok]
    ladders = []
    for chapter in range(1, 5):
        for hero in ("CH01", "CH02", "CH03"):
            ladder = [lookup.get((chapter, hero, "G2", difficulty)) for difficulty in range(5)]
            ladders.append({"chapter": chapter, "hero_id": hero, "complete": all(x and x["seeds"] == SEEDS for x in ladder),
                            "median_ttk_by_d": [x["median_victory_ttk"] if x else None for x in ladder],
                            "paired_seed_inversions": [{"lower_d": d, "seed": seed,
                                "lower_ttk": low["simulation_seconds"], "higher_ttk": high["simulation_seconds"]}
                                for d in range(4) for seed in SEEDS
                                for low in groups.get((chapter, hero, "G2", d), []) if low["configuration"]["seed"] == seed
                                for high in groups.get((chapter, hero, "G2", d+1), []) if high["configuration"]["seed"] == seed
                                if low["outcome"] == high["outcome"] == "boss_defeated" and low["simulation_seconds"] > high["simulation_seconds"]]})
    hp_intervals = []
    for chapter in range(1, 5):
        heroes = []
        for hero in ("CH01", "CH02", "CH03"):
            gold = lookup.get((chapter, hero, "G2", 4))
            low = lookup.get((chapter, hero, "lowG2", 4))
            if not gold or gold["seeds"] != SEEDS or gold["wins"] != 10 or gold["probe"]:
                continue
            ttk = gold["median_victory_ttk"]
            upper = 50 / ttk
            lower_quantile_upper = None
            if low and low["seeds"] == SEEDS and low["wins"] == 10 and not low["probe"]:
                lower_quantile_upper = 60 / low["median_victory_ttk"]
                upper = min(upper, lower_quantile_upper)
            heroes.append({"hero_id": hero, "gold_median_ttk": ttk,
                           "hp_multiplier_min": 35 / ttk, "hp_multiplier_max": upper,
                           "low_quantile_hp_multiplier_max": lower_quantile_upper})
        lower = max(x["hp_multiplier_min"] for x in heroes) if heroes else None
        upper = min(x["hp_multiplier_max"] for x in heroes) if heroes else None
        hp_intervals.append({"chapter": chapter, "complete_three_hero_evidence": len(heroes) == 3,
                             "method": "first-order TTK proportional-to-HP diagnostic; not a proof under phase/resource/ICD changes",
                             "heroes": heroes, "intersection": [lower, upper] if heroes else None,
                             "empty_intersection": lower > upper if len(heroes) == 3 else None})
    missing = [{"chapter": chapter, "hero_id": hero, "sample": sample, "difficulty": difficulty,
                "missing_seeds": [seed for seed in SEEDS if (chapter, hero, sample, difficulty, seed) not in seen]}
               for chapter in range(1, 5) for hero in ("CH01", "CH02", "CH03")
               for sample, difficulty in [(s, 4) for s in SAMPLES] + [("G2", d) for d in range(4)]
               if any((chapter, hero, sample, difficulty, seed) not in seen for seed in SEEDS)]
    room_summaries = []
    for (room_id, hero, sample, difficulty), fights in sorted(room_groups.items()):
        wins = [x for x in fights if x["outcome"] == "room_cleared" and x["hp_fraction"] > 0]
        ranks = {}
        for rank in ("normal", "elite"):
            actors = [a for x in fights for a in x.get("enemy_roster", {}).values() if a["rank"] == rank and a["actor_kind"] == "enemy"]
            ranks[rank] = {"actors": len(actors), "templates": sorted(set(a["template"] for a in actors)),
                           "levels": sorted(set(a["level"] for a in actors)),
                           "hp_range": [min(a["max_hp"] for a in actors), max(a["max_hp"] for a in actors)] if actors else None,
                           "actor_damage_range": [min(a["actor_damage"] for a in actors), max(a["actor_damage"] for a in actors)] if actors else None}
        room_summaries.append({"room_id": room_id, "hero_id": hero, "sample": sample, "difficulty": difficulty,
                               "seeds": sorted(x["configuration"]["seed"] for x in fights), "n": len(fights), "clears": len(wins),
                               "median_clear_simulation_seconds": median([x["simulation_seconds"] for x in wins]),
                               "median_end_hp": median([x["hp_fraction"] for x in fights]),
                               "median_received_hp_loss": median([x["hp_loss"] for x in fights]),
                               "median_shield_absorbed": median([x["shield_absorbed"] for x in fights]),
                               "ranks": ranks, "outcomes": [x["outcome"] for x in fights], "reward_evidence": False})
    all_rows = rows + room_rows
    result = {"method": "controlled production-scene input experiments; not natural human/economic validation",
              "measurement_protocol": common_protocol,
              "fights": len(all_rows), "boss_fights": len(rows), "ordinary_room_scenes": len(room_rows),
              "simulation_hours": sum(x["simulation_seconds"] for x in all_rows)/3600,
              "summed_combat_host_wall_seconds": sum(x["host_wall_seconds"] for x in all_rows),
              "integrity_errors": errors, "duplicates": duplicates, "missing_primary_evidence": missing,
              "groups": summaries, "room_groups": room_summaries, "g2_ladders": ladders, "shared_chapter_hp_intervals": hp_intervals,
              "outstanding_separate_evidence": ["phase-directed complete moves after output skips", "P3 full-HP/no-existing-shield single-package tolerance",
                                                 "normal/elite finite-wave five-difficulty threat and resource observations", "natural economic progression", "manual gameplay"]}
    (output / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))
    lines = ["# S11 controlled battle observations", "", result["method"], "",
             f"Fights: {len(rows)}; simulation hours: {result['simulation_hours']:.3f}; integrity errors: {len(errors)}", "",
             "TTK excludes failed/censored fights; their wins/timeouts and all-fight HP remain explicit. A probe cannot pass a gate.", "",
             "| Group | Sample | D | Wins/n | Median victory TTK | Median end HP | Failed gates |",
             "|---|---|---:|---:|---:|---:|---|"]
    for s in summaries:
        ttk = f"{s['median_victory_ttk']:.2f}s" if s["median_victory_ttk"] is not None else "censored"
        lines.append(f"| B{s['chapter']:02d}/{s['hero_id']} | {s['sample']} | {s['difficulty']} | {s['wins']}/{s['n']} | {ttk} | {s['median_end_hp_all_fights']:.1%} | {', '.join(s['failures']) or 'observation only' if not s['gates'] else ', '.join(s['failures']) or 'none'} |")
    if room_summaries:
        lines += ["", "Ordinary/elite room scenes (actual objective completion; no reward evidence):", "",
                  "| Room | Hero | D | Clears/n | Median clear time | Median HP | Normal/elite actors |",
                  "|---|---|---:|---:|---:|---:|---:|"]
        for s in room_summaries:
            clear_time = f"{s['median_clear_simulation_seconds']:.2f}s" if s["median_clear_simulation_seconds"] is not None else "censored"
            lines.append(f"| {s['room_id']} | {s['hero_id']} | {s['difficulty']} | {s['clears']}/{s['n']} | {clear_time} | {s['median_end_hp']:.1%} | {s['ranks']['normal']['actors']}/{s['ranks']['elite']['actors']} |")
    lines += ["", "Separate evidence still required:"] + ["- " + x for x in result["outstanding_separate_evidence"]]
    (output / "summary.md").write_text("\n".join(lines)+"\n")
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--godot", type=Path, default=Path("/tmp/godot-pr2-4.7.2/Godot_v4.7.2-stable_linux.x86_64"))
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--suite", choices=["d4", "ladder", "full", "rooms"], default="full")
    p.add_argument("--chapters", default="1,2,3,4")
    p.add_argument("--heroes", default="CH01,CH02,CH03")
    p.add_argument("--samples")
    p.add_argument("--seeds")
    p.add_argument("--rooms", default=",".join(f"L{x:02d}" for x in range(1, 25)))
    p.add_argument("--difficulties", help="Optional D0..D4 subset for staged probes")
    p.add_argument("--max-seconds", type=float, default=180)
    p.add_argument("--workers", type=int, default=1)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--probe", action="store_true")
    p.add_argument("--real-time", action="store_true", help="Omit --fixed-fps and cap real-time rendering at 60 FPS")
    p.add_argument("--gpu", action="store_true", help="Render the actual room in a visible window; requires a usable DISPLAY")
    p.add_argument("--summarize-only", action="store_true")
    args = p.parse_args()
    args.output = args.output.resolve()
    if args.output == ROOT or ROOT in args.output.parents:
        p.error("Evidence must be outside the repository")
    args.output.mkdir(parents=True, exist_ok=True)
    args.seeds = [int(x) for x in (args.seeds or ("1001" if args.suite == "rooms" else ",".join(map(str, SEEDS)))).split(",")]
    args.samples = args.samples or ("G2" if args.suite == "rooms" else ",".join(SAMPLES))
    if not args.seeds or len(set(args.seeds)) != len(args.seeds) or any(seed <= 0 for seed in args.seeds):
        p.error("Seeds must be distinct positive integers; zero would invoke the Boss fallback seed")
    if not math.isfinite(args.max_seconds) or args.max_seconds <= 0:
        p.error("Observation limit must be finite and positive")
    if args.summarize_only:
        try:
            summarize(args.output)
        except ValueError as exc:
            p.error(str(exc))
        return
    manifest = source_manifest()
    args.protocol = measurement_protocol(args, manifest)
    protocol_path = args.output / "measurement_protocol.json"
    if protocol_path.exists() and json.loads(protocol_path.read_text()) != args.protocol:
        p.error("Measurement protocol changed (seeds/timing/display/probe/limit/controller/calibration/engine/source); use a new output directory")
    if not protocol_path.exists() and any(args.output.glob("*/observations.json")):
        p.error("Existing unpinned results cannot be resumed or overwritten as calibrated evidence")
    protocol_path.write_text(json.dumps(args.protocol, indent=2))
    manifest_path = args.output / "source_manifest.json"
    if args.resume and manifest_path.exists() and json.loads(manifest_path.read_text())["sha256"] != manifest["sha256"]:
        p.error("Source changed since the prior run; use a new output directory instead of mixing evidence")
    manifest_path.write_text(json.dumps(manifest, indent=2))
    jobs = []
    selected_chapters = list(map(int, args.chapters.split(",")))
    for chapter in selected_chapters:
        for hero in args.heroes.split(","):
            if args.suite in ("d4", "full"):
                jobs.extend((chapter, hero, sample, 4, "") for sample in args.samples.split(","))
            if args.suite in ("ladder", "full"):
                jobs.extend((chapter, hero, "G2", d, "") for d in range(4 if args.suite == "full" else 5))
            if args.suite == "rooms":
                for room_id in args.rooms.split(","):
                    if not re.fullmatch(r"L(?:0[1-9]|1[0-9]|2[0-4])", room_id):
                        p.error("Rooms must be authored L01..L24")
                    if (int(room_id[1:])-1)//6+1 == chapter:
                        jobs.extend((chapter, hero, sample, d, room_id) for sample in args.samples.split(",") for d in range(5))
    if args.difficulties:
        selected_difficulties = list(map(int, args.difficulties.split(",")))
        if any(d not in range(5) for d in selected_difficulties): p.error("Difficulties must be 0..4")
        jobs = [job for job in jobs if job[3] in selected_difficulties]
    if not jobs: p.error("No matrix cases matched the request")
    request_path = args.output / "run_request.json"
    request = {"protocol": args.protocol, "jobs": [list(job) for job in jobs]}
    if request_path.exists() and json.loads(request_path.read_text()) != request:
        p.error("Requested matrix scope differs from the pinned resume request; use a new output directory")
    request_path.write_text(json.dumps(request, indent=2))
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        for label, status in executor.map(lambda case: run_job(args, case), jobs):
            if status == "error": failures.append(label)
    try:
        summary = summarize(args.output)
    except ValueError as exc:
        p.error(str(exc))
    print(json.dumps({"jobs": len(jobs), "errors": failures, "fights": summary["fights"], "output": str(args.output)}, indent=2))
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
