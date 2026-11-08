"""Reproduce the original demo audio and Godot atlas resources (stdlib only)."""
from pathlib import Path
import array
import json
import math
import random
import wave

ROOT = Path(__file__).resolve().parents[1] / "afterimage-2.0"


def build_atlas():
    # Tight visual bounds keep the transparent cell padding out of note geometry.
    regions = {
        "tap": (29, 125, 256, 88), "hold_head": (342, 125, 256, 88),
        "receptor": (655, 125, 256, 88), "pressed": (965, 125, 256, 88),
        "body": (116, 314, 82, 310), "tail": (429, 535, 82, 92),
        "flash": (651, 426, 267, 94), "spark": (28, 653, 259, 260),
        "ring": (320, 643, 300, 292), "glow": (642, 646, 291, 288),
        "diamonds": (1010, 711, 171, 158), "panel": (24, 1026, 267, 146),
        "pause": (399, 1017, 139, 160), "play": (713, 1017, 142, 160),
        "selection": (1003, 1011, 199, 185),
    }
    for name, rect in regions.items():
        text = '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
        text += '[ext_resource type="Texture2D" path="res://Minimal Rhythm Game Sprite Atlas.png" id="1"]\n\n'
        text += '[resource]\natlas = ExtResource("1")\nregion = Rect2(%s)\nfilter_clip = true\n' % ", ".join(map(str, rect))
        (ROOT / "assets" / (name + ".tres")).write_text(text)


def build_demo():
    rate = 22050
    seconds = 36
    samples = [0.0] * (rate * seconds)
    rng = random.Random(42)

    def add(start, duration, voice):
        offset = int(start * rate)
        for i in range(int(duration * rate)):
            if offset + i >= len(samples):
                break
            samples[offset + i] += voice(i / rate)

    # 120 BPM, four-bar chord progression and a clean, audible eighth-note pulse.
    roots = [130.8128, 103.8262, 155.5635, 116.5409]
    for beat in range(68):
        start = beat * 0.5
        add(start, 0.32, lambda t: 0.46 * math.exp(-t * 18) * math.sin(2 * math.pi * (48 * t + 3.4 * (1 - math.exp(-t * 30)))))
        if beat % 2:
            add(start, 0.16, lambda t: 0.17 * rng.uniform(-1, 1) * math.exp(-t * 28))
        for half in (0, 0.25):
            add(start + half, 0.055, lambda t: 0.065 * rng.uniform(-1, 1) * math.exp(-t * 65))
        root = roots[(beat // 8) % 4]
        add(start, 0.42, lambda t, f=root / 2: 0.16 * math.sin(2 * math.pi * f * t) * min(1, t * 80) * math.exp(-t * 7))
        melody = root * [2, 2.5, 3, 4, 3, 2.5, 2, 3][beat % 8]
        add(start, 0.46, lambda t, f=melody: 0.12 * (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t)) * min(1, t * 100) * math.exp(-t * 8))
    pcm = array.array("h", (int(max(-1, min(1, x)) * 29000) for x in samples))
    with wave.open(str(ROOT / "assets/first_light.wav"), "wb") as audio:
        audio.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        audio.writeframes(pcm.tobytes())
    notes = []
    for beat in range(4, 64):
        lane = [0, 1, 2, 3, 2, 1, 0, 3][beat % 8]
        if beat % 8 == 4:
            notes.append({"beat": beat, "lane": lane, "type": "hold", "duration_beats": 1.5})
        else:
            notes.append({"beat": beat, "lane": lane, "type": "tap"})
        if beat % 8 == 7:
            notes.append({"beat": beat, "lane": 0, "type": "tap"})
        if beat >= 32 and beat % 8 == 1:
            notes.append({"beat": beat + 0.5, "lane": 3, "type": "tap"})
    chart = {"format_version": 1, "title": "First Light", "artist": "AFTERIMAGE", "difficulty": "INTRO / 01",
             "song": "res://assets/first_light.wav", "bpm": 120.0, "offset_seconds": 0.0, "lane_count": 4, "notes": notes}
    (ROOT / "levels/first_light.json").write_text(json.dumps(chart, indent=2) + "\n")


if __name__ == "__main__":
    build_atlas()
    build_demo()
