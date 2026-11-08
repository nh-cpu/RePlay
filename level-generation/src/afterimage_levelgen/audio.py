"""Audio decoding and analysis; exported audio keeps the original timeline."""

import io
from pathlib import Path

import numpy as np
import soundfile as sf

from .models import Analysis


def read_audio(path: Path):
    try:
        samples, rate = sf.read(path, dtype="float32", always_2d=True)
    except (OSError, sf.LibsndfileError):
        raise ValueError(f"Cannot decode audio: {path.name}. Use WAV, OGG Vorbis, or MP3") from None
    if not len(samples) or not np.isfinite(samples).all():
        raise ValueError("Audio is empty or contains nonfinite samples")
    if samples.shape[1] > 2:
        raise ValueError("Use mono or stereo audio")
    return samples, rate


def import_audio(path: Path) -> bytes:
    samples, rate = read_audio(path)
    # Even WAV input is decoded for validation; compatible PCM WAV can be copied exactly.
    info = sf.info(path)
    if info.format == "WAV" and info.subtype in {"PCM_16", "PCM_8", "PCM_U8"}:
        return path.read_bytes()
    output = io.BytesIO()
    sf.write(output, samples, rate, format="WAV", subtype="PCM_16")
    return output.getvalue()


def analyze(path: Path, device: str = "cpu", tracker=None) -> Analysis:
    import librosa

    samples, rate = read_audio(path)
    duration = len(samples) / rate
    mono = samples.mean(axis=1)
    if duration < 4 or np.max(np.abs(mono)) < 1e-5:
        raise ValueError("Insufficient rhythmic information: audio is too short or silent")
    if tracker is None:
        from beat_this.inference import Audio2Beats

        try:
            tracker = Audio2Beats(checkpoint_path="final0", device=device, dbn=False)
        except Exception:
            raise ValueError("Cannot load Beat This! final0. Check model download connectivity and --device; no fallback was used") from None
    try:
        beats, downbeats = tracker(mono, rate)
    except Exception:
        raise ValueError("Beat This! inference failed; check the selected device and model installation") from None
    beats = np.asarray(beats, dtype=float)
    downbeats = np.asarray(downbeats, dtype=float)
    if not np.isfinite(beats).all() or not np.isfinite(downbeats).all():
        raise ValueError("Detector returned nonfinite timestamps")
    beats = np.unique(beats[(beats >= 0) & (beats < duration)])
    downbeats = np.unique(downbeats[(downbeats >= 0) & (downbeats < duration)])
    if len(beats) < 4:
        raise ValueError("Insufficient rhythmic information: fewer than four detected beats")
    analysis_rate = 22050
    signal = librosa.resample(mono, orig_sr=rate, target_sr=analysis_rate)
    hop = 256
    strength = librosa.onset.onset_strength(y=signal, sr=analysis_rate, hop_length=hop)
    onset_frames = librosa.onset.onset_detect(onset_envelope=strength, sr=analysis_rate, hop_length=hop)
    onsets = librosa.frames_to_time(onset_frames, sr=analysis_rate, hop_length=hop)
    if len(onsets) < 4:
        raise ValueError("Insufficient rhythmic information: fewer than four sound attacks")
    energy = librosa.feature.rms(y=signal, hop_length=hop)[0]
    length = min(len(strength), len(energy))
    times = librosa.frames_to_time(np.arange(length), sr=analysis_rate, hop_length=hop)
    keep = times < duration
    energy = energy[:length][keep]
    strength = strength[:length][keep]
    return Analysis(
        duration=duration, bpm=float(60 / np.median(np.diff(beats))), beats=beats.tolist(),
        downbeats=downbeats.tolist(), onsets=onsets[onsets < duration].tolist(),
        feature_times=times[keep].tolist(), energy=(energy / max(float(energy.max()), 1e-9)).tolist(),
        onset_strength=(strength / max(float(strength.max()), 1e-9)).tolist(),
    )
