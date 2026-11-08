import json

import numpy as np
import pytest
from pydantic import ValidationError

from afterimage_levelgen import pipeline
from afterimage_levelgen.audio import beat_features
from afterimage_levelgen.cli import main
from afterimage_levelgen.dynamic_chart import build_chart, check_playability
from afterimage_levelgen.models import AlbumProfile, Analysis
from afterimage_levelgen.planning import make_plan
from afterimage_levelgen.storage import Store, digest, stage_key
from afterimage_levelgen.events import onset_candidates


def long_analysis(duration):
    beats = np.arange(0, duration, 0.5)
    times = np.arange(0, duration, 0.02)
    # A-B-C-A-B-C forms recurring themes with distinct breakdown/build/climax.
    def section(t):
        return int(t // 32) % 3
    energy = [(.18, .5, .9)[section(t)] for t in times]
    onsets = [float(t) for t in np.arange(0, duration, .125)
              if section(t) == 2 or (section(t) == 1 and round(t * 8) % 2 == 0)
              or round(t * 8) % 8 == 0]
    data = Analysis(duration=duration, bpm=120, beats=beats.tolist(), downbeats=beats[::4].tolist(),
                    onsets=onsets, feature_times=times.tolist(), energy=energy,
                    onset_strength=energy, harmonic_energy=[e * .7 for e in energy],
                    percussive_activity=[e * .5 for e in energy])
    data.events = onset_candidates(data)
    for event in data.events:
        if event.time % 32 == 0:
            event.sustain_end = min(event.time + 2, duration - .1)
            event.compound = True
    return beat_features(data)


@pytest.mark.parametrize("duration", [180, 240])
def test_long_song_dynamics_and_constraints(duration):
    data = long_analysis(duration)
    charts = {}
    for difficulty in ("Easy", "Normal", "Hard"):
        chart, report = build_chart(data, difficulty, "Dynamic test", 42)
        charts[difficulty] = (chart, report)
        assert (chart, report) == build_chart(data, difficulty, "Dynamic test", 42)
        assert all(e["time"] == data.events[e["source_event"]].time for e in report["events"])
        assert any(p["transition"] for p in report["phrases"])
        rates = {level: [p["note_count"] / (p["end"] - p["start"]) for p in report["phrases"]
                         if p["intensity"] == level] for level in ("low", "high")}
        assert np.mean(rates["high"]) > np.mean(rates["low"])
        chart.check_timing(data.duration)
        check_playability(chart)
        assert all(e["end"] < duration for e in report["events"])
        for event in report["events"]:
            if event["subdivision"]:
                assert min(abs(event["time"] - onset) for onset in data.onsets) < .001
    normal = charts["Normal"][1]
    hard = charts["Hard"][1]
    assert sum(p["eighth_notes"] for p in normal["phrases"]) > 0
    assert sum(p["sixteenth_notes"] for p in normal["phrases"]) == 0
    assert sum(p["sixteenth_notes"] for p in hard["phrases"]) > 0
    assert len(charts["Hard"][0].notes) > len(charts["Normal"][0].notes)
    assert any(e["type"] == "hold" for e in hard["events"])
    # Verify simultaneous inputs independently, including holds under new taps.
    for event in hard["events"]:
        t = event["time"]
        required = [e for e in hard["events"] if e["time"] <= t + 1e-8 and e["end"] >= t - 1e-8]
        assert len(required) <= 2
    indices = sorted({e["beat_index"] for e in hard["events"] if e["subdivision"] in {.25, .75}})
    runs = []
    for index in indices:
        if runs and index == runs[-1][-1] + 1:
            runs[-1].append(index)
        else:
            runs.append([index])
    assert any(len(run) > 2 for run in runs)


def test_downbeat_fallback_is_reported():
    data = long_analysis(40)
    data.downbeats = []
    _, report = build_chart(data, "Hard", "Fallback", 9)
    assert all(p["boundary_source"] == "16-beat fallback" for p in report["phrases"])


def test_photo_duration_style_and_sections(album):
    plan = make_plan(album)
    assert plan.duration_seconds == 105
    assert plan.style == "acoustic folk"
    assert "guitar" in plan.prompt and "synth bass" not in plan.prompt
    assert not plan.duration_override and not plan.style_override
    data = album.model_dump()
    data["photos"][1]["theme_id"] = 0
    data["themes"] = data["themes"][:1]
    assert make_plan(AlbumProfile.model_validate(data)).duration_seconds == 95
    for length, count in [(120, 4), (121, 6), (180, 6), (181, 8), (240, 8)]:
        override = make_plan(album, length, "orchestral")
        assert len(override.sections) == count
        assert override.duration_override and override.style_override
        assert override.style == "orchestral"
        assert override.sections[-1].start_seconds + override.sections[-1].duration_seconds == pytest.approx(length)
    for invalid in [0, 241, float("nan"), float("inf")]:
        with pytest.raises(ValueError):
            make_plan(album, invalid)
    data = album.model_dump()
    data["photos"] = [dict(data["photos"][i % 2], photo_id=i) for i in range(30)]
    assert make_plan(AlbumProfile.model_validate(data)).duration_seconds == 235
    data["themes"].append(dict(theme_id=2, name="Mountains", description="Different setting"))
    data["photos"][-1]["theme_id"] = 2
    assert make_plan(AlbumProfile.model_validate(data)).duration_seconds == 240


@pytest.mark.parametrize("problem", ["missing", "duplicate", "unordered", "unused"])
def test_theme_validation(album, problem):
    data = album.model_dump()
    if problem == "missing":
        data["photos"][0]["theme_id"] = 20
    elif problem == "duplicate":
        data["themes"].append(data["themes"][0])
    elif problem == "unordered":
        data["photos"].reverse()
    else:
        data["themes"].append(dict(theme_id=20, name="Unused", description="Unused"))
    with pytest.raises(ValidationError):
        AlbumProfile.model_validate(data)


def test_rechart_preserves_metadata_and_never_calls_providers(tmp_path, audio_path, analysis, monkeypatch):
    monkeypatch.setattr(pipeline, "analyze", lambda *a: analysis)
    output = tmp_path / "output"
    assert main(["chart", "--audio", str(audio_path), "--output", str(output), "--title", "Keep title"]) == 0
    with Store(output).lock() as store:
        metadata = store.read_json("generation_metadata.json") | {"music_key": "keep", "photos": [0, 1]}
        store.write_json("generation_metadata.json", metadata)
    def fail(*args, **kwargs):
        pytest.fail("Rechart must not call providers")
    monkeypatch.setattr(pipeline, "generate_music", fail)
    monkeypatch.setattr(pipeline, "describe_album", fail)
    monkeypatch.setattr(pipeline, "analyze", fail)
    before = digest((output / "song.wav").read_bytes())
    assert main(["rechart", "--output", str(output)]) == 0
    metadata = json.loads((output / "generation_metadata.json").read_text())
    assert metadata["music_key"] == "keep" and metadata["photos"] == [0, 1]
    assert before == digest((output / "song.wav").read_bytes())
    assert pipeline.validate(output / "hard.json").title == "Keep title"
    assert (output / "chart_report.json").exists()


def test_rechart_requires_existing_folder(tmp_path):
    assert main(["rechart", "--output", str(tmp_path / "missing")]) == 1
    assert not (tmp_path / "missing").exists()


def test_oversized_generation_is_saved_and_never_automatically_rebought(tmp_path, album, monkeypatch):
    import io
    import soundfile as sf
    from PIL import Image

    photos = tmp_path / "photos"
    photos.mkdir()
    for i in range(2):
        Image.new("RGB", (8, 8), "blue").save(photos / f"{i}.png")
    buffer = io.BytesIO()
    sf.write(buffer, np.zeros(24100), 100, format="WAV")
    calls = []
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setenv("STABILITY_API_KEY", "test")
    monkeypatch.setattr(pipeline, "describe_album", lambda *a: album)
    monkeypatch.setattr(pipeline, "generate_music", lambda *a, **kw: calls.append(1) or buffer.getvalue())
    output = tmp_path / "out"
    argv = ["generate", "--photos", str(photos), "--output", str(output)]
    assert main(argv) == 1
    assert main(argv) == 1
    assert calls == [1]
    assert (output / "generated.wav").exists()
    assert not (output / "song.wav").exists()


def test_chart_version_does_not_change_music_cache(album):
    plan = make_plan(album).model_dump()
    music = {"plan": plan, "seed": 42, "provider": "stable-audio-3", "plan_version": 2}
    before = stage_key("music", music)
    assert stage_key("chart", {"chart_version": 3}) != stage_key("chart", {"chart_version": 4})
    assert stage_key("music", music) == before
