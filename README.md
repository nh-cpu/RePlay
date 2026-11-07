# AFTERIMAGE-2.0

Four-lane rhythm game for **Godot 4.7.2**. Open
`afterimage-2.0/project.godot` and press **F6** on `main.tscn`, or **F5**
to launch the project. The included **First Light** track is a 36-second
original synthesized demo with 72 taps, chord notes, and holds.

## Playing

- **D / F / J / K**: lanes 1–4, left to right. Bindings live in Project Settings
  → Input Map under `lane_1` through `lane_4`.
- On a touchscreen, press anywhere inside a lane. Multiple fingers work
  independently; a finger remains assigned to its initial lane until lifted.
  Mouse clicks also emulate touch for desktop testing.
- Tap as the note reaches the receptor. For holds, press the dotted head
  and keep holding until the pointed tail reaches the receptor.
- **Escape** or the pause icon pauses. Focus loss also pauses. Resume has
  a three-second countdown: re-press any active holds during that countdown.

| Judgment | Absolute timing error | Points |
|---|---:|---:|
| Perfect | ≤40 ms | 1,000 |
| Excellent | ≤80 ms | 750 |
| Good | ≤120 ms | 500 |
| OK | ≤160 ms | 250 |
| Miss | >160 ms | 0 |

Each tap or completed hold counts once toward score and combo. Holds retain
their head judgment but award points only when completed. An early release
or missed note resets combo. Empty presses have no penalty. Accuracy is
earned points divided by the chart's maximum possible points. Results show
judgment totals, accuracy, and maximum combo. Personal best scores persist.

## Importing levels

Choose **Import JSON** on the home screen and select a chart. Its `song`
may be a nearby relative path, an absolute path, or a bundled `res://` path.
Supported audio is WAV, OGG Vorbis, or MP3. If the audio is missing, a second
picker lets you locate it. Validated chart/audio pairs are copied into
`user://levels/<unique-id>/`, so the original files can move afterward.
Repeated imports create separate entries. Best scores live in
`user://bests.json`. No network connection is needed.

On Windows, Godot's default user folder is
`%APPDATA%/Godot/app_userdata/AFTERIMAGE-2.0/`.

The root [example chart](level_format_example.json) can be imported directly.
It uses the bundled demo audio by a relative filesystem path.

```json
{
  "format_version": 1,
  "title": "My Song",
  "artist": "Artist",
  "difficulty": "Normal",
  "song": "song.ogg",
  "bpm": 120.0,
  "offset_seconds": 0.15,
  "lane_count": 4,
  "notes": [
    { "beat": 0.0, "lane": 0, "type": "tap" },
    { "beat": 2.0, "lane": 2, "type": "hold", "duration_beats": 2.0 }
  ]
}
```

Timing is `offset_seconds + beat * 60 / bpm`. A positive offset delays notes
relative to the start of the song; a negative offset permits notes in the
silent pre-roll. Lanes are zero-based (0–3). Beats must be nonnegative,
BPM positive, and hold durations positive. All numeric values must be finite.
Notes are sorted on load. Same-lane duplicates and overlaps, including a note
exactly on another hold's tail, are rejected. Chords across lanes are allowed.
The chart must finish within the audio duration (plus the 160 ms judgment
window). Title, artist, and difficulty are optional; all other top-level
fields shown above are required. Variable BPM and additional note types
are not part of format version 1.

## Project structure

- `main.tscn` / `main.gd`: small screen coordinator.
- `data/`: typed chart/note Resources, JSON/audio loading, persistent library.
- `gameplay/`: composed gameplay scene; independent song clock, scheduler,
  judgment controller, score tracker, and input router. Lane, receptor, tap,
  hold, and effect scenes can be edited independently.
- `ui/`: home, HUD, pause, and results scenes.
- `assets/`: atlas regions/theme and original demo audio.
- `levels/`: bundled demo chart.
- `tests/`: deterministic rules tests, real-time playback check, and rendered
  screenshot checks.

The song clock compensates for audio mix/output latency. Note positions
derive from absolute song time rather than tweens or collision overlap.
An active hold stays anchored to the receptor while its body shrinks.
Atlas regions crop transparent padding without modifying the original PNG.

The lane scenes render through a perspective playfield, narrowing toward
the distance and widening toward the player. Notes, holds, and effects share
one projection; touch coordinates use its inverse. Adjust `distant_width`
on the Playfield node in `gameplay/perspective_playfield.tscn` to control
the perspective strength (smaller values create a deeper perspective).

The Compatibility renderer supports this 2D game on desktop and touch-capable
devices. Portrait and landscape layouts are supported. Mobile export
packaging is not included. When making a Godot export, add `*.json` to the
export preset's non-resource include filter so bundled charts are packaged.

## Verification and asset regeneration

From the repository root, substitute your Godot executable for `godot`:

```text
godot --headless --path afterimage-2.0 --editor --import --quit
godot --headless --path afterimage-2.0 --script res://tests/test_runner.gd
godot --headless --path afterimage-2.0 --script res://tests/playback_check.gd
godot --path afterimage-2.0 --script res://tests/visual_check.gd
python tools/build_assets.py
```

The test runner uses temporary isolated user-data folders for imports and
scores. The playback check takes about 39 seconds. The visual check saves
landscape and portrait PNGs to `tests/artifacts/`. Generated checks and logs
are ignored by Git. The Python generator uses only the standard library and
recreates the deterministic demo WAV, chart, and atlas resources.

Keyboard/touch merging and multi-finger input are covered by synthetic events;
physical touchscreen feel still needs testing on a target device.


## License

Copyright © 2026. All rights reserved.

This repository is publicly available for viewing and hackathon evaluation purposes only.

No permission is granted to use, copy, modify, redistribute, sublicense, or commercially exploit the source code, except as permitted by applicable law or GitHub's Terms of Service.

For licensing inquiries, contact the repository owner.
