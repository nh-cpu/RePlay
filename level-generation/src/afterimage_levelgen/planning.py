"""Stable creative rules connecting album interpretation to music direction."""

from .models import AlbumProfile, MusicPlan, Section


def make_plan(album: AlbumProfile, duration: float, style: str) -> MusicPlan:
    count = min(3, len(album.photos))
    sections = []
    for i in range(count):
        group = album.photos[i * len(album.photos) // count:(i + 1) * len(album.photos) // count]
        energy = sum(p.activity for p in group) / len(group)
        instruments = (["warm pads", "soft piano", "light percussion"] if energy < 0.4 else
                       ["synth bass", "bright arpeggios", "clear punchy drums"])
        sections.append(Section(
            name=("Opening", "Development", "Finale")[i] if count == 3 else f"Section {i + 1}",
            photo_ids=[p.photo_id for p in group], start_seconds=i * duration / count,
            duration_seconds=duration / count, energy=energy,
            intention="; ".join(dict.fromkeys(p.atmosphere for p in group))[:600],
            instruments=instruments,
        ))
    bpm = round(100 + 40 * sum(p.activity for p in album.photos) / len(album.photos))
    prompt = (
        f"Instrumental {style}. No vocals, speech or lyrics. {duration:g} seconds. "
        f"Steady 4/4 pulse around {bpm} BPM, distinct percussion for a rhythm game. "
        f"Cohesive motifs and smooth transitions. Album inspiration: {album.summary}. "
        + " ".join(f"{s.name}, approximately {s.start_seconds:g}-{s.start_seconds + s.duration_seconds:g}s: "
                   f"{s.intention}; {', '.join(s.instruments)}; energy {s.energy:.2f}." for s in sections)
        + " Resolve naturally at the end."
    )
    return MusicPlan(style=style, target_bpm=bpm, duration_seconds=duration,
                     sections=sections, prompt=prompt)
