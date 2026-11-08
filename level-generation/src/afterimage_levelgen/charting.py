"""Deterministic authored lane patterns over measured musical events."""

import random
from collections import deque

import numpy as np

from .models import Analysis, Chart, Note

CHART_VERSION = 2


def hold_end(analysis: Analysis, index: int, normal: bool) -> float:
    """Use sustained mix energy, allowing drums underneath a long-note phrase."""
    start = analysis.beats[index]
    lengths = (4, 2) if normal else (2,)
    for length in lengths:
        if index + length >= len(analysis.beats):
            continue
        end = analysis.beats[index + length]
        if not 0.4 <= end - start <= 4 or end >= analysis.duration - 0.05:
            continue
        energy = np.asarray([e for t, e in zip(analysis.feature_times, analysis.energy)
                             if start <= t <= end])
        # Percussive clicks alone have low energy between attacks; a sustained
        # backing can carry a hold even when the drum track has many onsets.
        if (len(energy) and float(energy.mean()) >= 0.15
                and float(np.quantile(energy, 0.2)) >= max(0.08, float(np.median(energy)) * 0.25)):
            return end
    return start


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
    last_hold_index = -8
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
        strong = any(abs(timestamp - t) <= 0.07 for t in analysis.downbeats)
        anchor = strong if analysis.downbeats else index % 4 == 0
        if not subdivision and anchor and index - last_hold_index >= 8:
            tail = hold_end(analysis, index, normal)
            if tail > timestamp:
                last_hold_index = index
        notes.append(Note(beat=timestamp * analysis.bpm / 60, lane=lane,
                          type="hold" if tail > timestamp else "tap",
                          duration_beats=(tail - timestamp) * analysis.bpm / 60 if tail > timestamp else None))
        reserved[lane] = tail
        recent.append(timestamp)
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
