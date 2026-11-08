"""Validated intermediate contracts and the existing v1 game format."""

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class PhotoProfile(Model):
    photo_id: int = Field(ge=0)
    scene: str = Field(min_length=1, max_length=300)
    palette: list[str] = Field(min_length=1, max_length=8)
    atmosphere: str = Field(min_length=1, max_length=300)
    activity: float = Field(ge=0, le=1)


class AlbumProfile(Model):
    summary: str = Field(min_length=1, max_length=1000)
    photos: list[PhotoProfile] = Field(min_length=1, max_length=30)


class Section(Model):
    name: str
    photo_ids: list[int]
    start_seconds: float = Field(ge=0)
    duration_seconds: float = Field(gt=0)
    energy: float = Field(ge=0, le=1)
    intention: str
    instruments: list[str]


class MusicPlan(Model):
    style: str
    target_bpm: float = Field(gt=0)
    duration_seconds: float = Field(ge=10, le=380)
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
