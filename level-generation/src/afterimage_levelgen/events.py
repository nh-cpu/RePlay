"""Audio-backed attack candidates; musical grids label evidence, never create it."""

import numpy as np

from .models import MusicalEvent


def label_events(events, beats):
    beats = np.asarray(beats)
    for event in events:
        index = int(np.clip(np.searchsorted(beats, event.time, side="right") - 1, 0, len(beats) - 2))
        phase = (event.time - beats[index]) / (beats[index + 1] - beats[index])
        grids = [(0, "quarter"), (1, "quarter"), (.5, "eighth"),
                 (1 / 3, "triplet"), (2 / 3, "triplet"), (.25, "sixteenth"), (.75, "sixteenth")]
        nearest, rhythm = min(grids, key=lambda pair: abs(phase - pair[0]))
        event.beat_index, event.phase = index, float(phase)
        event.rhythm = rhythm if abs(phase - nearest) <= .07 else "offgrid"
    # Swing needs repeated long-short pairs, not a single triplet-position hit.
    for event in events:
        if event.rhythm != "triplet" or event.phase < .55:
            continue
        neighbors = [e for e in events if abs(e.beat_index - event.beat_index) <= 4]
        late = sum(.58 <= e.phase <= .75 for e in neighbors)
        early = sum(.25 <= e.phase <= .4 for e in neighbors)
        if late >= 3 and early <= 1:
            event.rhythm = "swing"
    return events


def onset_candidates(analysis):
    """Legacy/in-memory analyses still use attacks, never fabricated beat notes."""
    if analysis.events:
        return analysis.events
    return label_events([MusicalEvent(time=t, strength=float(np.clip(np.interp(
        t, analysis.feature_times, analysis.onset_strength), 0, 1)), confidence=.8,
        components=["mix"], beat_index=0, phase=0, rhythm="offgrid")
        for t in analysis.onsets], analysis.beats)


def detect_events(signal, rate, beats, harmonic, percussive, hop=256):
    import librosa
    from scipy.ndimage import median_filter, uniform_filter1d
    from scipy.signal import find_peaks

    spectrum = np.abs(librosa.stft(signal, hop_length=hop))
    frequencies = librosa.fft_frequencies(sr=rate)
    sources = {"low": spectrum[frequencies < 250],
               "mid": spectrum[(frequencies >= 250) & (frequencies < 2500)],
               "high": spectrum[frequencies >= 2500],
               "harmonic": np.abs(harmonic), "percussive": np.abs(percussive)}
    frame_energy = np.mean(spectrum ** 2, axis=0)
    envelope = uniform_filter1d(signal.astype(float) ** 2, max(3, int(rate * .002)))
    attack_floor = max(float(envelope.max()) * 1e-5, 1e-12)
    rise = np.maximum(0, envelope - np.roll(envelope, max(1, int(rate * .003))))
    rise[:int(rate * .003)] = 0
    raw = []
    for name, magnitude in sources.items():
        band_power = np.mean(magnitude ** 2, axis=0)
        flux = np.maximum(0, np.diff(magnitude, axis=1, prepend=magnitude[:, :1])).mean(axis=0)
        local = median_filter(flux, size=87, mode="nearest")
        deviation = median_filter(np.abs(flux - local), size=87, mode="nearest")
        threshold = local + 2.5 * deviation + max(float(flux.max()) * .012, 1e-8)
        peaks, _ = find_peaks(flux, height=threshold, distance=max(1, int(.045 * rate / hop)))
        for frame in peaks:
            if frame_energy[frame] < frame_energy.max() * 1e-5:
                continue
            center = int(frame * hop)
            left, right = max(0, center - int(.035 * rate)), min(len(signal), center + int(.025 * rate))
            if right <= left:
                continue
            sample = left + int(np.argmax(rise[left:right]))
            if rise[sample] <= attack_floor:
                continue
            contrast = float(flux[frame] / max(threshold[frame], 1e-9))
            background = float(np.median(band_power[max(0, frame - 20):max(1, frame - 3)]))
            if band_power[frame] < background * 2.5 and contrast < 2:
                continue
            confidence = float(np.clip(.45 + .2 * np.log2(max(contrast, 1)), 0, 1))
            raw.append((sample / rate, name, float(flux[frame] / max(flux.max(), 1e-9)), confidence))
    groups = []
    for item in sorted(raw):
        if groups and item[0] - groups[-1][0][0] <= .03:
            groups[-1].append(item)
        else:
            groups.append([item])
    harmonic_power = np.mean(np.abs(harmonic) ** 2, axis=0)
    events = []
    for group in groups:
        strongest = max(group, key=lambda item: item[2] * item[3])
        time, _, strength, confidence = strongest
        components = sorted({item[1] for item in group})
        frame = int(round(time * rate / hop))
        before = harmonic_power[max(0, frame - 8):max(1, frame - 2)]
        after = harmonic_power[frame + 2:frame + 12]
        sustain = None
        # A harmonic entrance must rise and persist; spectral leakage from a click
        # or an unchanged pad cannot create a hold/chord on each drum beat.
        if "harmonic" in components and len(after) and np.median(after) > max(
                float(np.mean(before)) * 1.5, float(harmonic_power.max()) * .015):
            baseline = float(np.median(after))
            end = frame + 2
            reference = np.abs(harmonic[:, min(frame + 4, harmonic.shape[1] - 1)])
            for end in range(frame + 3, min(len(harmonic_power), frame + int(4 * rate / hop))):
                current = np.abs(harmonic[:, end])
                similarity = float(np.dot(reference, current) / max(np.linalg.norm(reference) * np.linalg.norm(current), 1e-12))
                if harmonic_power[end] < baseline * .25 or similarity < .65:
                    break
            end_time = min(end * hop / rate, len(signal) / rate - .05)
            if end_time - time >= .4:
                sustain = end_time
        # HPSS can label a tone's own entrance as percussive. Require transient
        # energy outside the sustained harmonic spectrum as independent evidence.
        distinct = False
        if sustain is not None:
            sustained_spectrum = np.abs(harmonic[:, min(frame + 4, harmonic.shape[1] - 1)])
            transient = np.max(np.abs(percussive[:, max(0, frame - 2):frame + 3]), axis=1)
            outside = sustained_spectrum < sustained_spectrum.max() * .05
            outside_power = float(np.sum(transient[outside] ** 2))
            mix_peak = np.max(spectrum[:, max(0, frame - 2):frame + 3], axis=1)
            distinct = (outside_power > .5 * float(np.sum(transient ** 2))
                        and outside_power > .12 * float(np.sum(mix_peak ** 2)))
        compound = sustain is not None and "percussive" in components and distinct
        events.append(MusicalEvent(time=time, strength=strength, confidence=confidence,
            components=components, compound=compound, sustain_end=sustain,
            beat_index=0, phase=0, rhythm="offgrid"))
    return label_events(events, beats)
