"""Deterministic authored lane patterns over measured musical events."""

import numpy as np

from .models import Analysis, Chart, Note

from .versions import CHART_VERSION


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
        energy = np.asarray([e for t, e in zip(analysis.feature_times, analysis.harmonic_energy or analysis.energy)
                             if start <= t <= end])
        # Percussive clicks alone have low energy between attacks; a sustained
        # backing can carry a hold even when the drum track has many onsets.
        if (len(energy) and float(energy.mean()) >= 0.15
                and float(np.quantile(energy, 0.2)) >= max(0.08, float(np.median(energy)) * 0.25)):
            return end
    return start


def make_chart(analysis: Analysis, difficulty: str, title: str, seed: int) -> Chart:
    from .dynamic_chart import build_chart

    return build_chart(analysis, difficulty, title, seed)[0]
