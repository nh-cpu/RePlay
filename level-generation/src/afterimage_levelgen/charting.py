"""Deterministic authored lane patterns over measured musical events."""

import random
from collections import deque

import numpy as np

from .models import Analysis, Chart, Note


def make_chart(analysis: Analysis, difficulty: str, title: str, seed: int) -> Chart:
    if difficulty not in {"Easy", "Normal"}:
        raise ValueError("Supported difficulties: Easy, Normal")
    rng = random.Random(seed)
    pattern = rng.choice([(0, 1, 2, 3, 2, 1, 0, 3), (0, 2, 1, 3, 1, 2, 3, 0)])
    if rng.choice([False, True]):
        pattern = tuple(3 - lane for lane in pattern)
    normal = difficulty == "Normal"
    cap = 4 if normal else 2
    candidates = [(t, i, False) for i, t in enumerate(analysis.beats)]
    if normal:
        for i, (start, end) in enumerate(zip(analysis.beats, analysis.beats[1:])):
            midpoint = (start + end) / 2
            attacks = [t for t in analysis.onsets if abs(t - midpoint) <= min(0.07, (end - start) * 0.15)]
            if attacks and i % 4 in {1, 3}:
                # Follow the audible attack, using the local half-beat only to select it.
                candidates.append((min(attacks, key=lambda t: abs(t - midpoint)), i, True))
    candidates.sort()
    recent: deque[float] = deque()
    reserved = [-1.0] * 4
    notes: list[Note] = []
    for timestamp, index, subdivision in candidates:
        if timestamp < 2 or timestamp >= analysis.duration - 0.05:
            continue
        energy = float(np.interp(timestamp, analysis.feature_times, analysis.energy))
        if energy < 0.08 or (index % 16 == 15 and not subdivision):
            continue
        while recent and recent[0] <= timestamp - 1 + 1e-9:
            recent.popleft()
        if len(recent) >= cap:
            continue
        preferred = pattern[(index + int(subdivision)) % len(pattern)]
        available = [lane for lane in range(4) if reserved[lane] + 0.12 < timestamp]
        if not available:
            continue
        lane = preferred if preferred in available else min(available, key=lambda x: abs(x - preferred))
        tail = timestamp
        if not subdivision and index % 8 == 0 and index + 2 < len(analysis.beats):
            end = analysis.beats[index + 2]
            attacks = sum(timestamp + 0.1 < t < end for t in analysis.onsets)
            sustained = [e for t, e in zip(analysis.feature_times, analysis.energy) if timestamp <= t <= end]
            if (0.4 <= end - timestamp <= 2 and end < analysis.duration - 0.05
                    and attacks <= 1 and sustained and min(sustained) >= 0.2):
                tail = end
        notes.append(Note(beat=timestamp * analysis.bpm / 60, lane=lane,
                          type="hold" if tail > timestamp else "tap",
                          duration_beats=(tail - timestamp) * analysis.bpm / 60 if tail > timestamp else None))
        reserved[lane] = tail
        recent.append(timestamp)
        strong = any(abs(timestamp - t) <= 0.07 for t in analysis.downbeats)
        if normal and strong and index % 8 == 0 and energy >= 0.55 and len(recent) < cap:
            opposite = [other for other in available if other != lane and (other < 2) != (lane < 2)]
            if opposite:
                other = opposite[0]
                notes.append(Note(beat=timestamp * analysis.bpm / 60, lane=other, type="tap"))
                reserved[other] = timestamp
                recent.append(timestamp)
    if not notes:
        raise ValueError("No playable notes after lead-in and energy filtering; try a more rhythmic song")
    chart = Chart(format_version=1, lane_count=4, title=title, difficulty=difficulty, song="song.wav", bpm=analysis.bpm,
                  offset_seconds=0.0, notes=notes)
    chart.check_timing(analysis.duration)
    return chart
