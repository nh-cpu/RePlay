"""Measured musical phrases and deterministic motif selection."""

import random

import numpy as np

from .audio import beat_features
from .models import Analysis


PATTERNS = {
    "alternating": (0, 2, 1, 3, 0, 3, 1, 2),
    "ascending": (0, 1, 2, 3, 0, 1, 2, 3),
    "descending": (3, 2, 1, 0, 3, 2, 1, 0),
    "mirrored": (0, 1, 2, 3, 3, 2, 1, 0),
    "call_response": (0, 1, 0, 1, 2, 3, 2, 3),
    "chord_accents": (0, 3, 1, 2, 0, 2, 1, 3),
    "hold_led": (0, 2, 3, 2, 1, 3, 2, 3),
}


def musical_phrases(analysis: Analysis, seed: int, difficulty: str) -> list[dict]:
    data = analysis if analysis.beat_energy else beat_features(analysis)
    fallback = len(data.downbeats) < 2
    starts = data.beats[::16] if fallback else data.downbeats[::4]
    starts = sorted(set([data.beats[0]] + [t for t in starts if t >= data.beats[0]]))
    ends = starts[1:] + [data.duration]
    rows = []
    for start, end in zip(starts, ends):
        first, last = np.searchsorted(data.beats, [start - 0.07, end - 0.07])
        if last <= first:
            continue
        def mean(values):
            return float(np.mean(values[first:last])) if values else 0.0
        rows.append(dict(start=start, end=end, first_beat=int(first), last_beat=int(last),
                         energy=mean(data.beat_energy), onset_density=mean(data.beat_onset_density),
                         harmonic=mean(data.beat_harmonic), percussion=mean(data.beat_percussion),
                         change=mean(data.musical_change), boundary_source="16-beat fallback" if fallback else "downbeats"))
    if not rows:
        raise ValueError("No measurable musical phrases")
    def relative(field):
        values = np.array([row[field] for row in rows])
        low, high = np.quantile(values, [0.1, 0.9])
        if high - low < 0.05:
            neutral = 0.8 if field == "onset_density" and high >= 5 else 0.5
            return np.full(len(rows), neutral)
        return np.clip((values - low) / (high - low), 0, 1)
    energies, densities = relative("energy"), relative("onset_density")
    rng = random.Random(seed + {"Easy": 0, "Normal": 1009, "Hard": 2017}[difficulty])
    previous = None
    previous_score = 0.0
    motifs = {}
    for i, row in enumerate(rows):
        score = float(0.5 * energies[i] + 0.5 * densities[i])
        if row["energy"] < 0.05:
            score = 0.0
        intensity = "low" if score < 0.34 else "high" if score >= 0.65 else "medium"
        family = (intensity, round(row["energy"] * 4), round(row["onset_density"]))
        options = ["alternating", "call_response", "hold_led"] if intensity == "low" else list(PATTERNS)
        if difficulty == "Easy":
            options = [p for p in options if p != "chord_accents"]
        motif = motifs.get(family)
        pattern = motif if motif in options and motif != previous else rng.choice([p for p in options if p != previous])
        motifs.setdefault(family, pattern)
        row.update(index=i, intensity=intensity, intensity_score=score, pattern=pattern,
                   variant=rng.randrange(4), returning_motif=motif == pattern,
                   transition=i > 0 and (abs(score - previous_score) >= 0.2 or row["change"] >= 0.25))
        previous, previous_score = pattern, score
    return rows
