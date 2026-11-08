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
    # Separate sustained and transient components before choosing hold passages.
    harmonic, percussive = librosa.decompose.hpss(librosa.stft(signal, hop_length=hop))
    harmonic_rms = librosa.feature.rms(S=np.abs(harmonic))[0]
    percussive_rms = librosa.feature.rms(S=np.abs(percussive))[0]
    length = min(len(strength), len(energy))
    times = librosa.frames_to_time(np.arange(length), sr=analysis_rate, hop_length=hop)
    keep = times < duration
    energy = energy[:length][keep]
    strength = strength[:length][keep]
    scale = max(float(energy.max()), 1e-9)
    result = Analysis(
        duration=duration, bpm=float(60 / np.median(np.diff(beats))), beats=beats.tolist(),
        downbeats=downbeats.tolist(), onsets=onsets[onsets < duration].tolist(),
        feature_times=times[keep].tolist(), energy=(energy / scale).tolist(),
        onset_strength=(strength / max(float(strength.max()), 1e-9)).tolist(),
        harmonic_energy=(harmonic_rms[:length][keep] / scale).tolist(),
        percussive_activity=(percussive_rms[:length][keep] / scale).tolist(),
    )
    return beat_features(result)


def beat_features(analysis: Analysis) -> Analysis:
    """Aggregate measurements over actual local beat intervals, not nominal BPM."""
    times = np.asarray(analysis.feature_times)
    attacks = np.asarray(analysis.onsets)
    result = analysis.model_copy(deep=True)
    result.beat_energy, result.beat_onset_density = [], []
    result.beat_harmonic, result.beat_percussion = [], []
    for i, start in enumerate(analysis.beats):
        end = analysis.beats[i + 1] if i + 1 < len(analysis.beats) else analysis.duration
        left, right = np.searchsorted(times, [start, end])
        right = max(left + 1, right)
        def average(values):
            if not values:
                return 0.0
            segment = values[left:right]
            return float(np.mean(segment)) if segment else float(values[-1])
        result.beat_energy.append(average(analysis.energy))
        result.beat_harmonic.append(average(analysis.harmonic_energy))
        result.beat_percussion.append(average(analysis.percussive_activity))
        result.beat_onset_density.append(float(np.sum((attacks >= start) & (attacks < end))) / max(end - start, 0.001))
    features = np.array([result.beat_energy, result.beat_onset_density,
                         result.beat_harmonic, result.beat_percussion]).T
    scales = np.maximum(np.max(features, axis=0), 1e-9)
    features /= scales
    result.musical_change = [0.0] + np.mean(np.abs(np.diff(features, axis=0)), axis=1).tolist()
    return Analysis.model_validate(result.model_dump())
