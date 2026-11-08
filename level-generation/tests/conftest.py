import numpy as np
import pytest
import soundfile as sf

from afterimage_levelgen.models import AlbumProfile, Analysis, PhotoProfile


@pytest.fixture
def album():
    return AlbumProfile(summary="A beach trip that becomes a celebration", photos=[
        PhotoProfile(photo_id=0, scene="beach", palette=["blue"], atmosphere="peaceful", activity=0.2),
        PhotoProfile(photo_id=1, scene="city", palette=["orange"], atmosphere="excited", activity=0.8),
    ])


@pytest.fixture
def analysis():
    beats = np.arange(0.3, 20, 0.5)
    times = np.arange(0, 20, 0.02)
    return Analysis(duration=20, bpm=120, beats=beats.tolist(), downbeats=beats[::4].tolist(),
                    onsets=np.arange(0.3, 20, 0.25).tolist(), feature_times=times.tolist(),
                    energy=[0.8] * len(times), onset_strength=[0.5] * len(times))


@pytest.fixture
def audio_path(tmp_path):
    path = tmp_path / "source.wav"
    rate = 22050
    samples = np.zeros(rate * 20)
    for time in np.arange(0.3, 20, 0.5):
        start = int(time * rate)
        samples[start:start + 100] = np.hanning(100) * 0.8
    sf.write(path, samples, rate, subtype="PCM_16")
    return path
