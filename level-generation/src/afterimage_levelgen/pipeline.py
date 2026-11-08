"""Stage orchestration shared by both CLI entry paths."""

import os
from pathlib import Path

from . import __version__
from .audio import analyze, import_audio, read_audio
from .charting import make_chart
from .models import AlbumProfile, Analysis, Chart
from .photos import prepare_photos
from .planning import make_plan
from .providers import describe_album, generate_music
from .storage import Store, digest, stage_key


def require_key(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Set {name} in your shell before using this uncached provider stage")
    return value


def generate(args, progress=print):
    progress("Preparing album photos...")
    photos = prepare_photos(args.photos)
    with Store(args.output).lock() as store:
        profile_key = stage_key("album", {"photos": [(name, digest(data)) for name, data in photos],
                                          "description": args.description, "model": args.gemini_model})
        if store.cached("album", profile_key, "album_profile.json"):
            progress("Reusing album interpretation")
            profile = AlbumProfile.model_validate(store.read_json("album_profile.json"))
        else:
            progress("Interpreting album with Gemini...")
            profile = describe_album(photos, args.description, args.gemini_model, require_key("GEMINI_API_KEY"))
            store.write_json("album_profile.json", profile.model_dump())
            store.commit("album", profile_key)
        plan = make_plan(profile, args.duration, args.style)
        store.write_json("music_plan.json", plan.model_dump())
        music_key = stage_key("music", {"plan": plan.model_dump(), "seed": args.seed,
                                        "provider": "stable-audio-3"})
        if not store.cached("music", music_key, "generated.wav"):
            key = require_key("STABILITY_API_KEY")
            state = {}
            if "music_job.json" in store.data["files"] and (store.root / "music_job.json").exists():
                saved = store.read_json("music_job.json")
                if saved.get("key") == music_key:
                    state = saved["state"]
            progress("Generating music with Stable Audio...")
            audio = generate_music(plan, args.seed, key, state,
                lambda value: store.write_json("music_job.json", {"key": music_key, "state": value}),
                progress=progress)
            store.write("generated.wav", audio)
            store.commit("music", music_key)
        else:
            progress("Reusing generated music")
        source = store.root / "generated.wav"
        finish(store, source, args, progress, {"album_key": profile_key, "music_key": music_key,
                                             "gemini_model": args.gemini_model, "music_model": "stable-audio-3"})


def chart(args, progress=print):
    if not args.audio.is_file():
        raise ValueError(f"Audio file does not exist: {args.audio}")
    # Read before touching outputs so invalid inputs cannot claim an output directory.
    read_audio(args.audio)
    with Store(args.output).lock() as store:
        finish(store, args.audio, args, progress, {"source_audio_hash": digest(args.audio.read_bytes())})


def finish(store: Store, source: Path, args, progress, metadata: dict):
    audio_key = stage_key("audio", digest(source.read_bytes()))
    if not store.cached("audio", audio_key, "song.wav"):
        store.write("song.wav", import_audio(source))
        store.commit("audio", audio_key)
    analysis_key = stage_key("analysis", {"audio": store.data["files"]["song.wav"],
                                          "device": args.device, "checkpoint": "final0"})
    if store.cached("analysis", analysis_key, "audio_analysis.json"):
        progress("Reusing audio analysis")
        analysis = Analysis.model_validate(store.read_json("audio_analysis.json"))
    else:
        progress("Analyzing beats and sound attacks (first run downloads final0)...")
        analysis = analyze(store.root / "song.wav", args.device)
        store.write_json("audio_analysis.json", analysis.model_dump())
        store.commit("analysis", analysis_key)
    chart_seed = args.chart_seed if args.chart_seed is not None else args.seed
    title = args.title or (args.photos.name if args.command == "generate" else args.audio.stem)
    for difficulty in ("Easy", "Normal"):
        name = difficulty.lower()
        key = stage_key("chart", {"analysis": analysis_key, "difficulty": difficulty,
                                   "seed": chart_seed, "title": title})
        if not store.cached(name, key, name + ".json"):
            result = make_chart(analysis, difficulty, title, chart_seed)
            store.write_json(name + ".json", result.model_dump(exclude_none=True))
            store.commit(name, key)
        validate(store.root / (name + ".json"))
    store.write_json("generation_metadata.json", {
        "version": __version__, "duration_seconds": analysis.duration, "bpm": analysis.bpm,
        "chart_seed": chart_seed, "audio_key": audio_key, "analysis_key": analysis_key,
        "photos": [p.photo_id for p in AlbumProfile.model_validate(store.read_json("album_profile.json")).photos]
                  if args.command == "generate" else [], **metadata,
    })
    progress(f"Ready: {store.root / 'easy.json'} and {store.root / 'normal.json'}")


def validate(path: Path) -> Chart:
    parsed = Chart.model_validate_json(path.read_text(encoding="utf-8"))
    if parsed.song.startswith(("res://", "user://")):
        raise ValueError("Standalone validation needs a relative or absolute filesystem audio path")
    audio = Path(parsed.song)
    if not audio.is_absolute():
        audio = path.parent / audio
    if audio.suffix.lower() not in {".wav", ".ogg", ".mp3"}:
        raise ValueError("Audio must be WAV, OGG Vorbis, or MP3")
    samples, rate = read_audio(audio)
    parsed.check_timing(len(samples) / rate)
    return parsed
