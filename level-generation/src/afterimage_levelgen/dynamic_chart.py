"""Select evidenced musical events before assigning playable lanes."""

from collections import Counter, deque
import random

import numpy as np

from .events import onset_candidates
from .models import Chart, Note
from .phrases import musical_phrases


def density_fits(times, time, cap):
    ordered = sorted([*times, time])
    return all(ordered[i + cap] - ordered[i] >= 1 - 1e-8 for i in range(len(ordered) - cap))


def build_chart(analysis, difficulty, title, seed):
    if difficulty not in {"Easy", "Normal", "Hard"}:
        raise ValueError("Supported difficulties: Easy, Normal, Hard")
    cap = {"Easy": 2, "Normal": 4, "Hard": 8}[difficulty]
    gap = .09 if difficulty == "Hard" else .12
    candidates = onset_candidates(analysis)
    phrases = musical_phrases(analysis, seed, difficulty)
    rejected = Counter()
    eligible = []
    for source_id, event in enumerate(candidates):
        if not 2 <= event.time < analysis.duration - .05:
            rejected["audio_boundary"] += 1
            continue
        threshold = {"Easy": .6, "Normal": .5, "Hard": .45}[difficulty]
        if event.confidence < threshold:
            rejected["confidence"] += 1
            continue
        if difficulty == "Normal" and event.rhythm == "sixteenth":
            rejected["rhythmic_complexity"] += 1
            continue
        if difficulty == "Easy" and event.rhythm not in {"quarter", "eighth"} and event.strength < .6:
            rejected["rhythmic_complexity"] += 1
            continue
        pulse_bonus = {"quarter": .45, "eighth": .2, "swing": .15, "triplet": .1}.get(event.rhythm, 0)
        score = (event.confidence + .5 * event.strength + .2 * event.compound
                 + pulse_bonus * (1 if difficulty == "Easy" else .5))
        eligible.append((source_id, event, score))
    # Stronger accents win conflicts regardless of chronological order.
    selected, times = [], []
    for item in sorted(eligible, key=lambda row: (-row[2], row[1].time)):
        time = item[1].time
        minimum_spacing = {"Easy": .25, "Normal": .12, "Hard": .065}[difficulty]
        if not density_fits(times, time, cap) or any(abs(time - t) < minimum_spacing - 1e-8 for t in times):
            rejected["density_or_spacing"] += 1
            continue
        times.append(time)
        chord = difficulty != "Easy" and item[1].compound and density_fits(times, time, cap)
        if chord:
            times.append(time)
        selected.append((*item, chord))
    selected.sort(key=lambda row: row[1].time)
    rng = random.Random(seed)
    # Stable roles and alternating hands; seed changes mapping, never evidence.
    roles = {role: rng.randrange(2) for role in ("low", "mid", "high", "harmonic", "percussive", "mix")}
    tails = [-1.0] * 4
    notes, events = [], []
    placed_times = []
    for number, (source_id, source, _, chord_selected) in enumerate(selected):
        time = source.time
        active = [lane for lane, tail in enumerate(tails) if tail >= time - 1e-8]
        available = [lane for lane in range(4) if tails[lane] + gap <= time + 1e-8]
        if len(active) >= 2 or not available:
            rejected["active_keys_or_lane_gap"] += 1
            continue
        phrase = next((p for p in phrases if p["start"] <= time < p["end"]), phrases[0])
        role = next((role for role in ("harmonic", "low", "mid", "high", "percussive")
                     if role in source.components), "mix")
        preferred = (number % 2) * 2 + (roles[role] + number // 2 + seed % 2) % 2
        lane = min(available, key=lambda lane: (lane != preferred, lane // 2 != preferred // 2, lane))
        end = time
        if source.sustain_end is not None and not active:
            length = 2 if difficulty == "Easy" else 4
            beat = min(source.beat_index + length, len(analysis.beats) - 1)
            end = min(source.sustain_end, analysis.beats[beat], analysis.duration - .05)
            if end - time < .4:
                end = time
        def append(lane, tail, chord=False):
            note = Note(beat=time * analysis.bpm / 60, lane=lane,
                        type="hold" if tail > time else "tap",
                        duration_beats=(tail - time) * analysis.bpm / 60 if tail > time else None)
            notes.append(note)
            events.append(dict(time=time, end=tail, lane=lane, type=note.type,
                source_event=source_id, components=source.components, confidence=source.confidence,
                selection_reason="compound accent" if chord else "supported " + source.rhythm,
                chord=chord, hold_evidence=source.sustain_end, chord_evidence=source.compound,
                rhythm=source.rhythm, phrase=phrase["index"], beat_index=source.beat_index,
                subdivision=0.0 if source.rhythm == "quarter" else source.phase))
            tails[lane] = tail
            placed_times.append(time)
        append(lane, end)
        # Compound accents reserve both starts during strength-ranked selection.
        if chord_selected and not active:
            opposite = [other for other in available if other // 2 != lane // 2]
            if opposite:
                append(opposite[0], time, True)
    if not notes:
        raise ValueError("No reliable playable attacks after lead-in; try a more rhythmic recording")
    chart = Chart(format_version=1, lane_count=4, title=title, difficulty=difficulty,
                  song="song.wav", bpm=analysis.bpm, offset_seconds=0.0, notes=notes)
    chart.check_timing(analysis.duration)
    check_playability(chart)
    signatures = []
    for phrase in phrases:
        chosen = [event for event in events if event["phrase"] == phrase["index"]]
        signatures.append(tuple((round(e["time"] - phrase["start"], 3), e["lane"], e["type"]) for e in chosen))
        phrase.update(pattern="audible_roles", note_count=len(chosen),
            holds=sum(e["type"] == "hold" for e in chosen),
            eighth_notes=sum(e["rhythm"] == "eighth" for e in chosen),
            sixteenth_notes=sum(e["rhythm"] == "sixteenth" for e in chosen),
            starts_per_second=len(chosen) / (phrase["end"] - phrase["start"]))
    peak = max(sum(t <= other < t + 1 - 1e-8 for other in placed_times) for t in placed_times)
    report = dict(difficulty=difficulty, note_count=len(notes), events=events, phrases=phrases,
        holds=sum(n.type == "hold" for n in notes), chords=sum(e["chord"] for e in events),
        average_density=len(notes) / analysis.duration, peak_density=peak,
        active_phrase_density=float(np.mean([p["starts_per_second"] for p in phrases if p["note_count"]])),
        subdivision_coverage=dict(Counter(e["rhythm"] for e in events)),
        candidate_count=len(candidates), eligible_count=len(eligible), rejected_candidates=dict(rejected),
        adjacent_identical_phrases=sum(bool(a) and a == b for a, b in zip(signatures, signatures[1:])),
        unique_phrase_patterns=len(set(signatures)))
    return chart, report


def difficulty_notices(reports):
    notices = []
    for previous, current in (("easy", "normal"), ("normal", "hard")):
        before, after = reports[previous], reports[current]
        old = {e["source_event"] for e in before["events"]}
        new = {e["source_event"] for e in after["events"]}
        additional = len(new - old) / max(len(old), 1)
        coordination = sum(e["chord"] or e["type"] == "hold" for e in after["events"]) / max(after["note_count"], 1)
        after["comparison"] = dict(previous=previous, additional_attack_ratio=additional,
            coordination_ratio=coordination, shared_attack_count=len(old & new))
        if additional < .15 and coordination < .1:
            rejected = after["rejected_candidates"]
            limited = sum(rejected.get(key, 0) for key in ("density_or_spacing", "active_keys_or_lane_gap"))
            reason = "playability constraints" if limited > max(1, .15 * after["eligible_count"]) else "limited reliable audio evidence"
            notices.append(f"{current.title()} adds little difficulty over {previous.title()}: {reason}. "
                           "Exported the best supported chart without filler notes (diagnostic, not a difficulty rating).")
    return notices


def check_playability(chart):
    cap = {"Easy": 2, "Normal": 4, "Hard": 8}[chart.difficulty]
    gap = .09 if chart.difficulty == "Hard" else .12
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
