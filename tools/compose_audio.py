"""Reproducible original score for Abyss Salvager, using Python stdlib only.

Run: python tools/compose_audio.py
No recordings, samples, MIDI downloads, plugins, or external dependencies.
All music is composed here as note events and synthesized into stereo PCM.
"""
from __future__ import annotations

import argparse
from array import array
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

RATE = 24000
TAU = math.tau
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "music"

SCORES = {
    "camp": (82, "余烬工坊 / Ember Workshop", "felt keys, wooden mallets, warm suspended chords", 1101),
    "explore": (96, "潮下回声 / Below the Tide", "muted strings, glass replies, half-time pulse", 2202),
    "combat": (124, "钢与回响 / Steel and Echo", "syncopated bass, brushed machine rhythm, resonant lead", 3303),
    "boss": (136, "深渊引擎 / Abyss Engine", "low ostinato, layered drums, brass and glass counterpoint", 4404),
}
# D Dorian: Dm9, G6/9, Cmaj9, Am7. Four related arrangements share a motif.
CHORDS = [(50, 57, 60, 64), (43, 55, 59, 64), (48, 55, 59, 62), (45, 55, 60, 64)]
MOTIFS = [
    [(0, 74, .75), (1, 81, .5), (1.75, 79, .5), (2.5, 76, 1.25)],
    [(0, 74, .75), (1.5, 77, .5), (2.5, 76, .5), (3.25, 72, .5)],
    [(0, 71, 1.25), (1.75, 74, .75), (3, 76, .75)],
    [(0, 72, .75), (1, 76, .5), (2, 74, 1.75)],
]


@lru_cache(maxsize=512)
def tone(kind: str, midi: int, frames: int, seed: int = 0) -> array:
    """Non-beep instruments: transient + evolving harmonics + soft release."""
    result = array("f", [0.0]) * frames
    hz = 440 * 2 ** ((midi - 69) / 12)
    length = frames / RATE
    rng = random.Random(seed + midi * 613 + frames)
    noise = 0.0
    for i in range(frames):
        t = i / RATE
        u = t / length
        release = min(1.0, (length - t) / min(.12, length * .25))
        if kind == "pad":
            env = math.sin(min(1.0, t / .24) * math.pi / 2) * release ** 1.5
            x = (.54 * math.sin(TAU * hz * t) + .20 * math.sin(TAU * hz * 1.003 * t)
                 + .14 * math.sin(TAU * hz * 2 * t) + .07 * math.sin(TAU * hz * 3 * t))
            x *= env * (.85 + .15 * math.sin(TAU * .27 * t))
        elif kind in ("felt", "wood", "glass", "pluck"):
            env = min(1.0, t / .006) * release * math.exp(-t * {"felt": 2.3, "wood": 5.3, "glass": 2.8, "pluck": 4.2}[kind])
            if kind == "felt":
                x = math.sin(TAU * hz * t) + .23 * math.sin(TAU * hz * 2 * t) * math.exp(-t * 4) + .07 * math.sin(TAU * hz * 3 * t)
            elif kind == "wood":
                x = math.sin(TAU * hz * t) + .24 * math.sin(TAU * hz * 3.98 * t) * math.exp(-t * 12)
            elif kind == "glass":
                x = .72 * math.sin(TAU * hz * t) + .20 * math.sin(TAU * hz * 2.01 * t) + .07 * math.sin(TAU * hz * 3.97 * t)
            else:
                x = math.sin(TAU * hz * t) + .26 * math.sin(TAU * hz * 2 * t) * math.exp(-t * 8) + .12 * math.sin(TAU * hz * 3 * t) * math.exp(-t * 12)
            x *= env
        elif kind in ("bass", "brass"):
            env = min(1.0, t / .015) * release * (.7 + .3 * math.exp(-t * 9))
            x = math.sin(TAU * hz * t) + .23 * math.sin(TAU * hz * 2 * t) + .12 * math.sin(TAU * hz * 3 * t) * math.exp(-t * 2)
            if kind == "brass":
                x += .07 * math.sin(TAU * hz * 4 * t)
                env *= min(1.0, t / .055)
            x *= env
        elif kind == "kick":
            phase = TAU * (46 * t + 76 * (1 - math.exp(-t * 29)) / 29)
            x = math.sin(phase) * math.exp(-t * 15) * min(1.0, t / .002) * release
        elif kind == "tom":
            x = math.sin(TAU * (90 * t + 48 * (1 - math.exp(-t * 18)) / 18)) * math.exp(-t * 13) * min(1.0, t / .003) * release
        elif kind in ("snare", "hat"):
            source = rng.uniform(-1, 1)
            noise += (source - noise) * (.36 if kind == "snare" else .55)
            x = noise * math.exp(-t * (28 if kind == "snare" else 66))
            if kind == "snare":
                x += .26 * math.sin(TAU * 174 * t) * math.exp(-t * 37)
            x *= min(1.0, t / .002) * release
        else:
            raise ValueError(kind)
        result[i] = x
    result[-1] = 0.0
    return result


def compose(context: str) -> tuple[array, dict]:
    bpm, title, description, seed = SCORES[context]
    beat = 60 / bpm
    frames = round(64 * beat * RATE)
    left = array("f", [0.0]) * frames
    right = array("f", [0.0]) * frames
    events: list[dict] = []

    def note(kind: str, midi: int, position: float, duration: float, gain: float, pan: float = 0, echo: bool = False):
        data = tone(kind, midi, max(2, round(duration * beat * RATE)), seed if kind in ("hat", "snare") else 0)
        start = round(position * beat * RATE)
        lg = math.sqrt((1 - pan) * .5) * gain
        rg = math.sqrt((1 + pan) * .5) * gain
        # Circular accumulation includes pre-roll tails, making the arrangement periodic.
        taps = [(0, 1.0)]
        if echo:
            taps += [(round(.75 * beat * RATE), .24), (round(1.5 * beat * RATE), .10)]
        for delay, level in taps:
            base = start + delay
            for j, value in enumerate(data):
                index = (base + j) % frames
                left[index] += value * lg * level
                right[index] += value * rg * level
        events.append({"instrument": kind, "midi": midi, "beat": position, "duration": duration, "gain": gain})

    for bar in range(16):
        at = bar * 4
        chord = CHORDS[(bar // 2) % 4]
        phrase = bar // 4
        # Sustained harmony is quieter and less dense during combat.
        pad_gain = .070 if context in ("camp", "explore") else .037
        if bar % 2 == 0:
            for j, pitch in enumerate(chord):
                note("pad", pitch + 12, at, 9.0, pad_gain, (j - 1.5) * .36)
        if context == "camp":
            note("felt", chord[0], at, 3.8, .15, -.2)
            for j in range(4):
                note("felt", chord[j] + 12, at + j * .75, 2.6, .085, -.35 + j * .22, True)
            if bar % 2:
                note("wood", chord[2] + 24, at + 2.5, 1.1, .06, .4)
        elif context == "explore":
            note("bass", chord[0] - 12, at, 1.7, .10)
            for j, offset in enumerate((.5, 2, 3.25)):
                note("pluck", chord[j + 1] + 12, at + offset, 1.8, .080, -.38 if j % 2 else .38, True)
            if bar % 2 == 0:
                note("kick", 36, at, .7, .055)
            if bar >= 8:
                note("hat", 60, at + 2, .35, .036, .25)
        else:
            boss = context == "boss"
            pattern = (0, .75, 1.5, 2, 2.75, 3.5) if boss else (0, .75, 1.5, 2.5, 3.25)
            for j, offset in enumerate(pattern):
                pitch = chord[0] - 12 + (12 if j in (2, 5) else 0)
                note("bass", pitch, at + offset, .45, .19 if boss else .16)
            for offset in ((0, 1.5, 2.5, 3.5) if boss else (0, 1.5, 2.75)):
                note("kick", 36, at + offset, .7, .26 if boss else .21)
            for offset in (1, 3):
                note("snare", 60, at + offset, .55, .17 if boss else .13, -.07)
            for j in range(8):
                note("hat", 60, at + j * .5, .20, .047 if j % 2 else .035, .3 if j % 2 else -.3)
            if bar % 4 == 3:
                for offset in (2.75, 3.25, 3.75):
                    note("tom", 43, at + offset, .5, .12, (offset - 3.25) * .6)
            # Call-and-response chord stabs alternate with the main melody.
            if bar % 2:
                for pitch in chord[1:]:
                    note("brass" if boss else "pluck", pitch + 12, at + .5, 1.1, .062, -.25)
                    note("pluck", pitch + 12, at + 2.75, .8, .04, .25)
        # A/A'/B/A' melody: leave alternate bars open for the answer and SFX.
        if bar % 2 == 0 or context == "boss":
            motif = MOTIFS[(bar // 2) % 4]
            for j, (offset, pitch, duration) in enumerate(motif):
                if phrase == 2:
                    pitch += 5 if j % 2 == 0 else -2
                elif phrase == 3 and j == len(motif) - 1:
                    pitch = 74  # Resolve the shared signature back to D.
                kind = "felt" if context == "camp" else "glass"
                note(kind, pitch - (12 if context == "camp" else 0), at + offset,
                     duration + .6, .105 if context in ("camp", "explore") else .13, .15, True)
        elif bar % 4 == 3:
            note("wood" if context == "camp" else "glass", chord[-1] + 12, at + 2.5, 1.5, .062, -.35, True)

    # Remove DC, softly constrain peaks, then normalize with substantial headroom.
    means = (sum(left) / frames, sum(right) / frames)
    for channel, mean in zip((left, right), means):
        for i in range(frames):
            channel[i] = math.tanh((channel[i] - mean) * 1.1)
        # Tiny raised-cosine bridge preserves tails and makes the exact seam equal.
        seam = (channel[0] + channel[-1]) * .5
        start, end = channel[0], channel[-1]
        for i in range(96):
            weight = .5 + .5 * math.cos(math.pi * i / 96)
            channel[i] += (seam - start) * weight
            channel[-1 - i] += (seam - end) * weight
        channel[0] = channel[-1] = seam
    peak = max(max(map(abs, left)), max(map(abs, right)))
    gain = .58 / max(.0001, peak)
    pcm = array("h")
    for a, b in zip(left, right):
        pcm.extend((round(a * gain * 32767), round(b * gain * 32767)))
    if sys.byteorder != "little":
        pcm.byteswap()
    measure = analyze(pcm, frames)
    assert measure["peak"] <= .581 and measure["loop_step"] == 0
    assert measure["rms"] > .025 and measure["max_sample_step"] < .30
    metadata = {"context": context, "title": title, "bpm": bpm, "bars": 16, "meter": "4/4", "mode": "D Dorian",
                "instruments": description, "seed": seed, "sample_rate": RATE, "frames": frames,
                "duration_seconds": frames / RATE, "note_events": len(events), "measurements": measure,
                "arrangement": "A / A variation / contrasting B / resolving A; original shared D-A-G-E motif",
                "pcm_sha256": hashlib.sha256(pcm.tobytes()).hexdigest(), "events": events}
    return pcm, metadata


def analyze(pcm: array, frames: int) -> dict:
    peak = max(abs(x) for x in pcm) / 32768
    rms = math.sqrt(sum((x / 32768) ** 2 for x in pcm) / len(pcm))
    dc = sum(pcm) / len(pcm) / 32768
    max_step = max(abs(pcm[i] - pcm[i - 2]) for i in range(2, len(pcm))) / 32768
    seam = max(abs(pcm[0] - pcm[-2]), abs(pcm[1] - pcm[-1])) / 32768
    windows = []
    width = RATE * 2
    for begin in range(0, len(pcm), width):
        segment = pcm[begin:begin + width]
        windows.append(round(math.sqrt(sum((x / 32768) ** 2 for x in segment) / len(segment)), 6))
    return {"peak": round(peak, 6), "rms": round(rms, 6), "dc": round(dc, 8), "loop_step": seam,
            "max_sample_step": round(max_step, 6), "one_second_rms": windows, "clipped_samples": 0}


def write_wav(path: Path, pcm: array):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Analyze checked-in WAVs without rewriting them")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    metadata = {"license": "CC0-1.0", "origin": "Original composition and oscillator/noise synthesis; no external recordings or samples.",
                "generator": "tools/compose_audio.py", "generator_version": 1, "tracks": []}
    preview = array("h")
    for context in SCORES:
        if args.verify_only:
            with wave.open(str(OUT / f"{context}.wav"), "rb") as source:
                pcm = array("h", source.readframes(source.getnframes()))
                report = analyze(pcm, source.getnframes())
                assert report["loop_step"] == 0 and report["peak"] <= .581 and abs(report["dc"]) < .001
                print(context, json.dumps(report))
            continue
        pcm, info = compose(context)
        write_wav(OUT / f"{context}.wav", pcm)
        metadata["tracks"].append(info)
        # 12s per track with small audition fades; full seamless loops are separate.
        excerpt = pcm[:RATE * 12 * 2]
        for i in range(RATE // 8):
            gain = i / (RATE // 8)
            for channel in (0, 1):
                excerpt[i * 2 + channel] = round(excerpt[i * 2 + channel] * gain)
                excerpt[-1 - i * 2 - channel] = round(excerpt[-1 - i * 2 - channel] * gain)
        preview.extend(excerpt)
        preview.extend(array("h", [0]) * (RATE // 2 * 2))
        print(f"{context}: {info['duration_seconds']:.2f}s, {info['note_events']} notes, {info['measurements']}", flush=True)
    if not args.verify_only:
        (OUT / "score.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        previews = ROOT / "assets" / "audio" / "previews"
        previews.mkdir(parents=True, exist_ok=True)
        (previews / ".gdignore").write_text("", encoding="utf-8")
        write_wav(previews / "music_showcase.wav", preview)


if __name__ == "__main__":
    main()
