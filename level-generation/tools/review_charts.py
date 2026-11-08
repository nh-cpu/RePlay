"""Create short audio-plus-chart-click clips for human timing/playability review."""

import argparse
import json
from pathlib import Path

import numpy as np
import soundfile as sf


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("generation", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if args.destination.exists() and any(args.destination.iterdir()):
        parser.error("Review destination must be empty; existing files are never overwritten")
    report = json.loads((args.generation / "chart_report.json").read_text())
    samples, rate = sf.read(args.generation / "song.wav", always_2d=True)
    duration = len(samples) / rate
    phrases = [p for p in report["difficulties"]["hard"]["phrases"] if p["end"] > 2]
    selections = {"opening": 2, "middle": duration / 2,
                  "breakdown": min(phrases, key=lambda p: p["energy"])["start"],
                  "climax": max(phrases, key=lambda p: p["onset_density"])["start"]}
    args.destination.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for label, start in selections.items():
        start = max(0, min(start, duration - 15))
        end = min(duration, start + 15)
        for difficulty, chart in report["difficulties"].items():
            clip = samples[int(start * rate):int(end * rate)].copy() * .65
            for event in chart["events"]:
                if not start <= event["time"] < end:
                    continue
                position = int((event["time"] - start) * rate)
                length = min(int(.035 * rate), len(clip) - position)
                t = np.arange(length) / rate
                click = .22 * np.sin(2 * np.pi * (1000 + event["lane"] * 350) * t) * np.exp(-t * 150)
                clip[position:position + length] += click[:, None]
            filename = f"{label}-{difficulty}.wav"
            sf.write(args.destination / filename, np.clip(clip, -1, 1), rate, subtype="PCM_16")
            manifest[filename] = {"start_seconds": start, "end_seconds": end}
    (args.destination / "clips.json").write_text(json.dumps(manifest, indent=2))
    print(f"Created {len(manifest)} listening clips in {args.destination}; human review still required.")


if __name__ == "__main__":
    main()
