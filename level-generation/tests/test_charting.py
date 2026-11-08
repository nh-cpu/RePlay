import json

import numpy as np
import pytest
import soundfile as sf
from pydantic import ValidationError

from afterimage_levelgen.audio import analyze
from afterimage_levelgen.charting import make_chart
from afterimage_levelgen.models import Chart
from afterimage_levelgen.pipeline import validate


@pytest.mark.parametrize("difficulty,cap", [("Easy", 2), ("Normal", 4)])
def test_patterns_limits_and_reproducibility(analysis, difficulty, cap):
    chart = make_chart(analysis, difficulty, "Test", 42)
    assert chart == make_chart(analysis, difficulty, "Test", 42)
    assert chart != make_chart(analysis, difficulty, "Test", 81)
    times = [n.beat * 60 / chart.bpm for n in chart.notes]
    assert min(times) >= 2
    assert max(times) < analysis.duration
    for start in times:
        assert sum(start - 1e-8 <= t < start + 1 - 1e-8 for t in times) <= cap
    if difficulty == "Easy":
        assert len(set(times)) == len(times)
    else:
        assert len(set(times)) < len(times)
    chart.check_timing(analysis.duration)


def test_holds_reserve_lanes(analysis):
    analysis.onsets = [0.3, 2.3, 10.3, 18.3]
    chart = make_chart(analysis, "Normal", "Sustained", 42)
    assert any(n.type == "hold" for n in chart.notes)
    chart.check_timing(analysis.duration)
    for hold in [n for n in chart.notes if n.type == "hold"]:
        assert not any(n is not hold and n.lane == hold.lane
                       and hold.beat <= n.beat <= hold.beat + hold.duration_beats for n in chart.notes)


@pytest.mark.parametrize("delay,variable", [(0.0, False), (1.17, False), (0.73, True)])
def test_click_track_timestamps(tmp_path, delay, variable):
    rate = 22050
    intervals = np.linspace(0.45, 0.65, 30) if variable else np.full(30, 0.5)
    beats = delay + np.cumsum(intervals)
    duration = beats[-1] + 1
    signal = np.zeros(int(duration * rate))
    for t in beats:
        start = int(t * rate)
        signal[start:start + 100] = np.hanning(100)
    path = tmp_path / "clicks.wav"
    sf.write(path, signal, rate)
    # Exact oracle timestamps isolate the analysis/export clock from ML accuracy.
    result = analyze(path, tracker=lambda audio, sr: (beats, beats[::4]))
    chart = make_chart(result, "Easy", "Clicks", 42)
    assert chart.notes
    for note in chart.notes:
        reconstructed = chart.offset_seconds + note.beat * 60 / chart.bpm
        assert min(abs(reconstructed - beats)) < 0.001
    assert np.allclose(result.beats, beats)


def chart_dict():
    return {"format_version": 1, "lane_count": 4, "song": "song.wav", "bpm": 120,
            "offset_seconds": 0, "notes": [{"beat": 4, "lane": 0, "type": "hold", "duration_beats": 2}]}


@pytest.mark.parametrize("change", [
    {"bpm": float("nan")}, {"bpm": 0}, {"offset_seconds": float("inf")},
    {"notes": [{"beat": 1, "lane": 4, "type": "tap"}]},
    {"notes": [{"beat": -1, "lane": 0, "type": "tap"}]},
    {"notes": [{"beat": 1, "lane": 0, "type": "hold"}]},
    {"notes": [{"beat": 1, "lane": 0, "type": "hold", "duration_beats": 0}]},
    {"notes": [{"beat": True, "lane": 0, "type": "tap"}]},
])
def test_invalid_schema(change):
    with pytest.raises(ValidationError):
        Chart.model_validate(chart_dict() | change)


@pytest.mark.parametrize("beat", [4, 5, 6])
def test_hold_collision_including_tail(beat):
    data = chart_dict()
    data["notes"].append({"beat": beat, "lane": 0, "type": "tap"})
    with pytest.raises(ValueError, match="overlap"):
        Chart.model_validate(data).check_timing(20)


def test_duration_and_overflow():
    with pytest.raises(ValueError, match="beyond"):
        Chart.model_validate(chart_dict()).check_timing(2)
    data = chart_dict() | {"bpm": 1e-308}
    with pytest.raises(ValueError, match="supported range"):
        Chart.model_validate(data).check_timing(20)


def test_relative_audio_validation(tmp_path, audio_path):
    data = chart_dict() | {"song": "source.wav"}
    path = tmp_path / "level.json"
    path.write_text(json.dumps(data))
    assert validate(path).song == "source.wav"
    audio_path.unlink()
    with pytest.raises(ValueError, match="decode"):
        validate(path)


@pytest.mark.parametrize("length,amplitude", [(2, 0.5), (10, 0)])
def test_short_silent(tmp_path, length, amplitude):
    path = tmp_path / "silent.wav"
    sf.write(path, np.full(22050 * length, amplitude, dtype=np.float32), 22050)
    with pytest.raises(ValueError, match="Insufficient rhythmic"):
        analyze(path)
