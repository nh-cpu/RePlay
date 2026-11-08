"""Validated intermediate contracts and the existing v1 game format."""

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class PhotoProfile(Model):
    photo_id: int = Field(ge=0)
    theme_id: int = Field(ge=0)
    scene: str = Field(min_length=1, max_length=300)
    palette: list[str] = Field(min_length=1, max_length=8)
    atmosphere: str = Field(min_length=1, max_length=300)
    activity: float = Field(ge=0, le=1)


class Theme(Model):
    theme_id: int = Field(ge=0)
    name: str = Field(min_length=1, max_length=100)
    description: str = Field(min_length=1, max_length=400)


class AlbumProfile(Model):
    summary: str = Field(min_length=1, max_length=1000)
    photos: list[PhotoProfile] = Field(min_length=1, max_length=30)
    themes: list[Theme] = Field(min_length=1, max_length=30)
    suggested_genre: str = Field(min_length=1, max_length=200)
    instruments: list[str] = Field(min_length=2, max_length=8)
    target_bpm: float = Field(ge=60, le=180)
    emotional_progression: list[str] = Field(min_length=2, max_length=8)

    @model_validator(mode="after")
    def complete_groups(self):
        if [p.photo_id for p in self.photos] != list(range(len(self.photos))):
            raise ValueError("Photos must cover consecutive IDs in album order")
        ids = [theme.theme_id for theme in self.themes]
        if len(set(ids)) != len(ids) or set(ids) != {p.theme_id for p in self.photos}:
            raise ValueError("Each photo must reference one theme; themes must be unique and used")
        return self


class Section(Model):
    name: str
    photo_ids: list[int]
    start_seconds: float = Field(ge=0)
    duration_seconds: float = Field(gt=0)
    energy: float = Field(ge=0, le=1)
    intention: str
    instruments: list[str]
    rhythm: str
    transition: str


class MusicPlan(Model):
    style: str
    target_bpm: float = Field(gt=0)
    duration_seconds: float = Field(ge=10, le=240)
    duration_reason: str
    distinct_theme_count: int = Field(ge=1)
    duration_override: bool
    style_override: bool
    sections: list[Section]
    prompt: str = Field(min_length=1, max_length=10000)


class Analysis(Model):
    duration: float = Field(gt=0)
    bpm: float = Field(gt=0)
    beats: list[float]
    downbeats: list[float]
    onsets: list[float]
    feature_times: list[float]
    energy: list[float]
    onset_strength: list[float]
    harmonic_energy: list[float] = Field(default_factory=list)
    percussive_activity: list[float] = Field(default_factory=list)
    beat_energy: list[float] = Field(default_factory=list)
    beat_onset_density: list[float] = Field(default_factory=list)
    beat_percussion: list[float] = Field(default_factory=list)
    beat_harmonic: list[float] = Field(default_factory=list)
    musical_change: list[float] = Field(default_factory=list)
    detector: str = "beat-this/final0"

    @model_validator(mode="after")
    def valid_timeline(self):
        for name in ("beats", "downbeats", "onsets", "feature_times"):
            values = getattr(self, name)
            if any(t < 0 or t > self.duration for t in values):
                raise ValueError(f"{name} outside the audio timeline")
            if any(a >= b for a, b in zip(values, values[1:])):
                raise ValueError(f"{name} must be strictly increasing")
        if len(self.beats) < 4:
            raise ValueError("Insufficient rhythmic information: fewer than four beats")
        if not self.feature_times or not (
            len(self.feature_times) == len(self.energy) == len(self.onset_strength)
        ):
            raise ValueError("Feature arrays must be nonempty and aligned")
        for name in ("harmonic_energy", "percussive_activity"):
            values = getattr(self, name)
            if values and len(values) != len(self.feature_times):
                raise ValueError(f"{name} must align with feature_times")
        for name in ("beat_energy", "beat_onset_density", "beat_percussion", "beat_harmonic", "musical_change"):
            values = getattr(self, name)
            if values and len(values) != len(self.beats):
                raise ValueError(f"{name} must align with beats")
        return self


class Note(Model):
    beat: float = Field(ge=0, strict=True)
    lane: int = Field(ge=0, le=3, strict=True)
    type: Literal["tap", "hold"]
    duration_beats: float | None = Field(default=None, gt=0, strict=True)

    @model_validator(mode="after")
    def hold_duration(self):
        if self.type == "hold" and self.duration_beats is None:
            raise ValueError("Holds require duration_beats")
        return self


class Chart(Model):
    format_version: Literal[1]
    title: str = "Untitled"
    artist: str = "AFTERIMAGE"
    difficulty: str = "Normal"
    song: str = Field(min_length=1)
    bpm: float = Field(gt=0, strict=True)
    offset_seconds: float = Field(strict=True)
    lane_count: Literal[4]
    notes: list[Note] = Field(min_length=1)

    def check_timing(self, duration: float) -> None:
        tails: dict[int, float] = {}
        for note in sorted(self.notes, key=lambda n: (n.beat, n.lane)):
            if note.beat <= tails.get(note.lane, -1):
                raise ValueError(f"Same-lane overlap at beat {note.beat}, lane {note.lane}")
            tail = note.beat + (note.duration_beats if note.type == "hold" else 0)
            tails[note.lane] = tail
            start_seconds = self.offset_seconds + note.beat * 60 / self.bpm
            end_seconds = self.offset_seconds + tail * 60 / self.bpm
            if not math.isfinite(start_seconds) or not math.isfinite(end_seconds):
                raise ValueError("Note timing is outside the supported range")
            if end_seconds > duration + 0.160:
                raise ValueError("Chart extends beyond audio duration and judgment window")
