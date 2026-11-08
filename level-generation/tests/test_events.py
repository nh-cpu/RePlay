import numpy as np
import pytest
import soundfile as sf

from afterimage_levelgen.audio import analyze
from afterimage_levelgen.events import label_events
from afterimage_levelgen.models import MusicalEvent
from afterimage_levelgen.dynamic_chart import build_chart, difficulty_notices


def event(time, strength=.8, **kwargs):
    return MusicalEvent(time=time, strength=strength, confidence=.9, components=["mix"],
                        beat_index=0, phase=0, rhythm="offgrid", **kwargs)


@pytest.mark.parametrize("rhythm", ["straight", "swing", "triplet", "offbeat", "drift", "quiet"])
def test_waveform_attacks_and_export(tmp_path, rhythm):
    rate = 22050
    beats = np.arange(.5, 12, .5)
    if rhythm == "drift":
        beats = np.cumsum(np.linspace(.4, .65, 20))
    attacks = []
    for start, end in zip(beats, beats[1:]):
        fractions = {"straight": [0, .25, .5, .75], "swing": [0, 2 / 3],
                     "triplet": [0, 1 / 3, 2 / 3], "offbeat": [.19, .61]}.get(rhythm, [0])
        attacks.extend(start + (end - start) * f for f in fractions)
    audio = np.zeros(rate * 13)
    rng = np.random.default_rng(12)
    for time in attacks:
        start = int(time * rate)
        amplitude = .08 if rhythm == "quiet" and time > 6 else .7
        audio[start:start + 220] += amplitude * rng.normal(size=220) * np.hanning(220)
    path = tmp_path / "rhythm.wav"
    sf.write(path, audio, rate)
    data = analyze(path, tracker=lambda *_: (beats, beats[::4]))
    assert all(min(abs(e.time - t) for t in attacks) < .03 for e in data.events)
    assert sum(min(abs(e.time - t) for e in data.events) < .03 for t in attacks) >= .85 * len(attacks)
    assert not any(e.compound for e in data.events)
    for difficulty in ("Easy", "Normal", "Hard"):
        chart, report = build_chart(data, difficulty, "Test", 42)
        for note, selected in zip(chart.notes, report["events"]):
            assert abs(note.beat * 60 / chart.bpm - data.events[selected["source_event"]].time) < .001


def test_rich_difficulties_and_continuous_streams(analysis):
    analysis.events = label_events([event(float(t)) for t in np.arange(2, 19, .125)], analysis.beats)
    reports = {name.lower(): build_chart(analysis, name, "Rich", 42)[1] for name in ("Easy", "Normal", "Hard")}
    assert reports["hard"]["note_count"] > reports["normal"]["note_count"] > reports["easy"]["note_count"]
    assert reports["hard"]["peak_density"] == 8
    assert len(reports["hard"]["events"]) == len(analysis.events)


def test_chord_and_hold_need_evidence(analysis):
    analysis.events = label_events([event(t, compound=(t == 2.3), sustain_end=3.3 if t == 2.3 else None)
                                   for t in [2.3, 4.3, 6.3, 8.3]], analysis.beats)
    _, report = build_chart(analysis, "Hard", "Evidence", 42)
    assert report["chords"] == 1
    assert report["holds"] == 1
    assert all(e["time"] == 2.3 for e in report["events"] if e["chord"] or e["type"] == "hold")


def test_sparse_notice_and_no_filler(analysis):
    analysis.onsets = [2.3, 5.3, 8.3, 11.3]
    reports = {d.lower(): build_chart(analysis, d, "Sparse", 42)[1] for d in ("Easy", "Normal", "Hard")}
    assert len(difficulty_notices(reports)) == 2
    assert all(e["time"] in analysis.onsets for report in reports.values() for e in report["events"])


def test_seed_changes_lanes_not_timestamps(analysis):
    a = build_chart(analysis, "Hard", "Same", 42)[1]
    b = build_chart(analysis, "Hard", "Same", 81)[1]
    assert [e["time"] for e in a["events"]] == [e["time"] for e in b["events"]]


def test_strong_later_accent_wins(analysis):
    analysis.events = label_events([event(2.3, .1), event(2.6, .1), event(2.8, 1), event(4.3)], analysis.beats)
    _, report = build_chart(analysis, "Easy", "Accent", 42)
    assert 2.8 in [e["time"] for e in report["events"]]


@pytest.mark.parametrize("drums", [True, False])
def test_harmonic_entrance_under_drums(tmp_path, drums):
    rate = 22050
    audio = np.zeros(rate * 12)
    rng = np.random.default_rng(4)
    beats = np.arange(.5, 12, .5)
    for time in beats if drums else []:
        start = int(time * rate)
        audio[start:start + 180] += .3 * rng.normal(size=180) * np.hanning(180)
    entrances = (2.5, 4.5, 6.5, 8.5)
    for start_time in entrances:
        samples = np.arange(int(1.7 * rate)) / rate
        tone = .2 * np.sin(2 * np.pi * 440 * samples)
        tone[:220] *= np.linspace(0, 1, 220)
        tone[-220:] *= np.linspace(1, 0, 220)
        start = int(start_time * rate)
        audio[start:start + len(tone)] += tone
    path = tmp_path / "sustain.wav"
    sf.write(path, audio, rate)
    data = analyze(path, tracker=lambda *_: (beats, beats[::4]))
    sustained = [e for e in data.events if e.sustain_end is not None]
    assert sustained
    assert all(min(abs(e.time - t) for t in entrances) < .03 for e in sustained)
    assert any(e.compound for e in sustained) == drums
    assert all(e.sustain_end <= min(entrances, key=lambda t: abs(t - e.time)) + 1.75 for e in sustained)


def test_stationary_noise_does_not_become_dense_chart(tmp_path):
    rate = 22050
    rng = np.random.default_rng(3)
    path = tmp_path / "noise.wav"
    sf.write(path, rng.normal(0, .02, rate * 12), rate)
    beats = np.arange(.5, 12, .5)
    try:
        data = analyze(path, tracker=lambda *_: (beats, beats[::4]))
    except ValueError as error:
        assert "Insufficient rhythmic" in str(error)
    else:
        assert len([e for e in data.events if e.time >= 2]) < 4


def test_reanalysis_without_provider_calls_and_cached_notices(tmp_path, audio_path, analysis, monkeypatch, capsys):
    from afterimage_levelgen import pipeline
    from afterimage_levelgen.cli import main
    analysis.onsets = [2.3, 5.3, 8.3, 11.3]
    calls = []
    monkeypatch.setattr(pipeline, "analyze", lambda *_: calls.append(1) or analysis)
    def forbidden(*args, **kwargs):
        pytest.fail("Rechart must never contact a paid provider")
    monkeypatch.setattr(pipeline, "generate_music", forbidden)
    monkeypatch.setattr(pipeline, "describe_album", forbidden)
    output = tmp_path / "cached"
    assert main(["chart", "--audio", str(audio_path), "--output", str(output)]) == 0
    capsys.readouterr()
    monkeypatch.setattr(pipeline, "ANALYSIS_VERSION", 999)
    assert main(["rechart", "--output", str(output)]) == 0
    assert len(calls) == 2
    assert "Difficulty notice" in capsys.readouterr().out
    assert main(["rechart", "--output", str(output)]) == 0
    assert len(calls) == 2
    assert "Difficulty notice" in capsys.readouterr().out
