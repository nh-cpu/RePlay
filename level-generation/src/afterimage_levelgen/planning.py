"""Photo-driven musical identity, duration, and evolving arrangement."""

from .models import AlbumProfile, MusicPlan, Section


def make_plan(album: AlbumProfile, duration: float | None = None, style: str | None = None) -> MusicPlan:
    automatic = min(240, 95 + 5 * max(len(album.photos) - 4, 0) + 10 * (len(album.themes) - 1))
    chosen_duration = automatic if duration is None else duration
    if not 10 <= chosen_duration <= 240:
        raise ValueError("Generated duration must be between 10 and 240 seconds")
    chosen_style = style.strip() if style is not None else album.suggested_genre
    if not chosen_style:
        raise ValueError("Musical style cannot be empty")
    arrangements = {
        4: [("Introduction", 0.4), ("Development and main theme", 0.8),
            ("Contrast then varied theme return", 0.65), ("Climax and resolution", 1.0)],
        6: [("Introduction", 0.35), ("Main theme", 0.65), ("Development", 0.85),
            ("Breakdown", 0.3), ("Varied return and climax", 1.0), ("Resolution", 0.4)],
        8: [("Introduction", 0.35), ("Main theme", 0.65), ("Development", 0.8),
            ("Contrasting passage", 0.5), ("Build", 0.85), ("Breakdown", 0.3),
            ("Varied return and climax", 1.0), ("Resolution", 0.4)],
    }
    count = 4 if chosen_duration <= 120 else 6 if chosen_duration <= 180 else 8
    rhythms = ["Sparse quarter-note pulse; leave space for the motif",
               "Introduce eighth-note accompaniment and clear offbeat accents",
               "Develop syncopation; brief sixteenth-note fills, then return to the pulse",
               "Thin percussion and sustain the melody; leave deliberate rests",
               "Vary the main motif with rhythmic answers and short fills",
               "Resolve the motif and simplify percussion toward the ending"]
    sections = []
    for i, (role, multiplier) in enumerate(arrangements[count]):
        start = i * len(album.photos) // count
        end = max(start + 1, (i + 1) * len(album.photos) // count)
        group = album.photos[start:end]
        activity = sum(p.activity for p in group) / len(group)
        instruments = list(album.instruments)
        if "Introduction" in role or "Breakdown" in role or role == "Resolution":
            instruments = instruments[:2]
        elif i % 2:
            instruments = instruments[1:] + instruments[:1]
        rhythm = rhythms[min(i, len(rhythms) - 1)]
        if "return" in role.lower() or "climax" in role.lower():
            rhythm = "Return the recognizable theme with changed accents, rhythmic answers and brief fills; avoid an unchanged loop"
        if "Breakdown" in role:
            rhythm = rhythms[3]
        sections.append(Section(
            name=role, photo_ids=[p.photo_id for p in group], start_seconds=i * chosen_duration / count,
            duration_seconds=chosen_duration / count, energy=round((0.3 + 0.7 * activity) * multiplier, 3),
            intention=(album.emotional_progression[i * len(album.emotional_progression) // count]
                       + "; " + "; ".join(dict.fromkeys(p.atmosphere for p in group)))[:800],
            instruments=instruments, rhythm=rhythm,
            transition="Finish with a natural cadence" if i == count - 1 else
                       "Use a brief fill or melodic pickup to introduce the next texture; maintain musical continuity",
        ))
    prompt = (
        f"Instrumental {chosen_style}. No vocals, speech or lyrics. {chosen_duration:g} seconds. "
        f"A cohesive soundtrack inspired by {album.summary}. Instrument palette: {', '.join(album.instruments)}. "
        f"Maintain a clear 4/4 pulse around {album.target_bpm:g} BPM. "
        "Develop recognizable motifs across distinct phrases. Alternate rhythmic activity and breathing room. "
        "Use audible arrangement changes, evolving accompaniment, accents and fills rather than a static loop. "
        + " ".join(f"{s.start_seconds:g}-{s.start_seconds + s.duration_seconds:g}s {s.name}: "
                   f"{s.intention}; feature {', '.join(s.instruments)}; dynamics {s.energy:.2f}. "
                   f"{s.rhythm}. {s.transition}." for s in sections)
    )
    return MusicPlan(style=chosen_style, target_bpm=album.target_bpm, duration_seconds=chosen_duration,
                     duration_reason=f"95 + 5 * max({len(album.photos)} - 4, 0) + 10 * ({len(album.themes)} - 1), capped at 240 = {automatic}; "
                                     + (f"explicit override {duration:g}" if duration is not None else "automatic"),
                     distinct_theme_count=len(album.themes), duration_override=duration is not None,
                     style_override=style is not None, sections=sections, prompt=prompt)
