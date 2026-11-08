"""Phrase-based chart scheduling with explicit input-load constraints."""

from collections import deque

import numpy as np

from .models import Analysis, Chart, Note
from .phrases import PATTERNS, musical_phrases


def build_chart(analysis: Analysis, difficulty: str, title: str, seed: int):
    from .charting import hold_end

    if difficulty not in {"Easy", "Normal", "Hard"}:
        raise ValueError("Supported difficulties: Easy, Normal, Hard")
    phrases = musical_phrases(analysis, seed, difficulty)
    cap = {"Easy": 2, "Normal": 4, "Hard": 8}[difficulty]
    gap = 0.09 if difficulty == "Hard" else 0.12
    notes, events = [], []
    reserved = [-1.0] * 4
    recent = deque()
    last_hold = -8
    used_attacks = set()
    last_sixteenth_beat = -4
    burst_start = -4
    for phrase in phrases:
        candidates = []
        low, high = phrase["intensity"] == "low", phrase["intensity"] == "high"
        first, last = phrase["first_beat"], phrase["last_beat"]
        for index in range(first, last):
            time = analysis.beats[index]
            if time < phrase["start"] - 0.07 or time >= phrase["end"]:
                continue
            local = index - first
            # Sparse passages follow half-time; phrase endings leave room to breathe.
            stride = 2 if low else 1
            rest = local == last - first - 1 or (phrase["pattern"] == "call_response" and local % 8 == 3)
            if local % stride == 0 and not rest:
                candidates.append((time, index, 0.0))
            if difficulty == "Easy" or index + 1 >= len(analysis.beats) or rest:
                continue
            fractions = [0.5] if not low or local % 4 == 1 else []
            # Global beat-index windows guarantee two-beat bursts and two-beat recovery.
            if difficulty == "Hard" and high and index % 4 < 2:
                fractions.extend([0.25, 0.75])
            interval = analysis.beats[index + 1] - time
            tolerance = min(0.06, interval * 0.1)
            for fraction in fractions:
                target = time + fraction * interval
                attack = min(analysis.onsets, key=lambda t: abs(t - target), default=-1)
                if abs(attack - target) <= tolerance and attack < phrase["end"] and attack not in used_attacks:
                    candidates.append((attack, index, fraction))
                    used_attacks.add(attack)
        candidates.sort()
        pattern = PATTERNS[phrase["pattern"]]
        event_number = 0
        for time, index, fraction in candidates:
            if time < 2 or time >= analysis.duration - 0.05:
                continue
            energy = float(np.interp(time, analysis.feature_times, analysis.energy))
            if energy < 0.04:
                continue
            while recent and recent[0] <= time - 1 + 1e-9:
                recent.popleft()
            active = [lane for lane, tail in enumerate(reserved) if tail >= time - 1e-9]
            if len(recent) >= cap or len(active) >= 2:
                continue
            available = [lane for lane in range(4) if reserved[lane] + gap <= time + 1e-9]
            if not available:
                continue
            sixteenth = fraction in {0.25, 0.75}
            if sixteenth:
                if index > burst_start + 1:
                    if index - last_sixteenth_beat < 3:
                        continue
                    burst_start = index
                last_sixteenth_beat = index
            preferred = pattern[(event_number + phrase["variant"]) % len(pattern)]
            if phrase["variant"] % 2:
                preferred = 3 - preferred
            lane = preferred if preferred in available else min(available, key=lambda x: (abs(x - preferred), x))
            tail = time
            downbeat = any(abs(time - t) <= 0.07 for t in analysis.downbeats) if analysis.downbeats else index % 4 == 0
            if (fraction == 0 and downbeat and not active and index - last_hold >= 8
                    and (low or phrase["pattern"] == "hold_led" or index % 8 == 0)):
                tail = min(hold_end(analysis, index, difficulty != "Easy"), phrase["end"] - gap)
                if tail - time < 0.4:
                    tail = time
                if tail > time:
                    last_hold = index
            note = Note(beat=time * analysis.bpm / 60, lane=lane, type="hold" if tail > time else "tap",
                        duration_beats=(tail - time) * analysis.bpm / 60 if tail > time else None)
            notes.append(note)
            events.append(dict(time=time, end=tail, lane=lane, type=note.type,
                               phrase=phrase["index"], beat_index=index, subdivision=fraction))
            recent.append(time)
            reserved[lane] = tail
            event_number += 1
            chord_accent = downbeat and (high or phrase["pattern"] == "chord_accents")
            if difficulty != "Easy" and fraction == 0 and chord_accent and not active and len(recent) < cap:
                opposite = [other for other in available if (other < 2) != (lane < 2)]
                if opposite:
                    other = opposite[0]
                    notes.append(Note(beat=time * analysis.bpm / 60, lane=other, type="tap"))
                    events.append(dict(time=time, end=time, lane=other, type="tap", phrase=phrase["index"],
                                       beat_index=index, subdivision=0.0))
                    reserved[other] = time
                    recent.append(time)
    if not notes:
        raise ValueError("No playable notes after lead-in and energy filtering; try a more rhythmic song")
    chart = Chart(format_version=1, lane_count=4, title=title, difficulty=difficulty, song="song.wav",
                  bpm=analysis.bpm, offset_seconds=0.0, notes=notes)
    chart.check_timing(analysis.duration)
    check_playability(chart)
    signatures = []
    for phrase in phrases:
        selected = [event for event in events if event["phrase"] == phrase["index"]]
        signature = tuple((e["beat_index"] - phrase["first_beat"], e["subdivision"], e["lane"], e["type"])
                          for e in selected)
        signatures.append(signature)
        phrase.update(note_count=len(selected), holds=sum(e["type"] == "hold" for e in selected),
                      eighth_notes=sum(e["subdivision"] == 0.5 for e in selected),
                      sixteenth_notes=sum(e["subdivision"] in {0.25, 0.75} for e in selected))
    repeated = sum(bool(a) and a == b for a, b in zip(signatures, signatures[1:]))
    report = dict(difficulty=difficulty, note_count=len(notes), holds=sum(n.type == "hold" for n in notes),
                  phrases=phrases, adjacent_identical_phrases=repeated,
                  unique_phrase_patterns=len(set(signatures)), events=events)
    return chart, report


def check_playability(chart: Chart) -> None:
    """Audit generated charts independently of the scheduling decisions."""
    cap = {"Easy": 2, "Normal": 4, "Hard": 8}[chart.difficulty]
    gap = 0.09 if chart.difficulty == "Hard" else 0.12
    tails = [-1.0] * 4
    recent = deque()
    for note in sorted(chart.notes, key=lambda n: (n.beat, n.lane)):
        time = chart.offset_seconds + note.beat * 60 / chart.bpm
        if time < 2 - 1e-8 or time - tails[note.lane] < gap - 1e-8:
            raise ValueError("Generated chart violates lead-in or lane reuse gap")
        if sum(tail >= time - 1e-8 for tail in tails) >= 2:
            raise ValueError("Generated chart requires more than two simultaneous keys")
        while recent and recent[0] <= time - 1 + 1e-8:
            recent.popleft()
        recent.append(time)
        if len(recent) > cap:
            raise ValueError("Generated chart exceeds its note density cap")
        tails[note.lane] = time + (note.duration_beats or 0) * 60 / chart.bpm
