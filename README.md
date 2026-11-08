# AFTERIMAGE-2.0

Four-lane rhythm game for **Godot 4.7.2**. Open
`afterimage-2.0/project.godot` and press **F6** on `main.tscn`, or **F5**
to launch the project. The included **First Light** track is a 36-second
original synthesized demo with 72 taps, chord notes, and holds.

The game starts in a landscape window sized to fit the current desktop monitor
and centered within its usable area. Mobile uses the device's native screen
with landscape orientation. Resizing the desktop window still adapts the UI.

## Playing

The song wheel supports mouse-wheel scrolling, click/drag, and touch dragging
with inertia and snapping. **Up/down** or the controller D-pad/left stick browses
songs; **left/right** chooses an expanded difficulty. **Enter**, controller
confirm, or **Play** starts the chart. Double-click/tap a difficulty row to start
it directly. Each song remembers its chosen difficulty while the menu is open.
Photo artwork in the menu is independent of the gameplay Album background switch.

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

## Create a track from photos

Choose **Create from photos**, add 1–30 JPEG/PNG/WebP photos, review their
thumbnails, and drag the ≡ handles up/down to arrange them. The list scrolls
automatically near its edges; dropping outside it or pressing Escape cancels
the drag. Focus a handle and use Up/Down for keyboard reordering. Remove unwanted photos
with ×, enter a title and optional description, then choose **Generate track**.
Cancel discards the local draft; removing a photo never deletes the original.
Previews are local and orientation-corrected. No upload occurs before confirmation.

Generation uses the existing [Python environment](level-generation/README.md).
The worker reads API credentials from its inherited environment, falling back to
`level-generation/.env`. It accepts simple `KEY=value` entries with optional
quotes/comments; shell values win. Only `GEMINI_API_KEY`, `STABILITY_API_KEY`,
and `GEMINI_MODEL` are loaded. Keys are not stored in Godot preferences or jobs.
Gemini receives normalized photo copies; Stable Audio receives a musical prompt.
These provider requests require network access and may incur account charges.

Style and duration are photo-inspired, with automatic duration capped at four
minutes. The game supplies no style or duration override. One job runs at a time
in a separate process; you can play existing songs while it works. A completed
track appears once in the playlist, with **Easy / Normal / Hard** choices and
separate best scores. Playback of saved tracks needs no network.

Failed jobs expose **Retry saved generation**, reusing saved stages and provider
job IDs. Unknown submission outcomes are never automatically resubmitted. If a
provider recording exceeds four minutes, it is retained in the job workspace
but not published or automatically regenerated. Jobs continue when you return
to another screen or close the game; reopening reconnects or offers recovery.

Normalized snapshots and generation artifacts live under
`user://generation_jobs/album_*/`. Successful self-contained packages live under
`user://levels/album_*/`, containing audio, three unchanged v1 charts, photos,
and `album.json` (track identity, relative chart/photo paths, timed photo cues).
Original photos can move afterward. Existing imported levels and the demo remain
available; JSON import is no longer a menu action. Best scores remain in
`user://bests.json`.

**Album background** in the main and pause menus controls the same saved setting.
Photos pan and subtly zoom, crossfading through the music plan's photo groups,
scaled to actual audio duration. Motion follows song time and freezes on pause.
The highway panels become translucent while notes and receptors remain opaque.
Turning the setting off restores the plain background and opaque highway.
Tracks without usable photos always use the plain presentation.

On Windows, Godot's default user folder is
`%APPDATA%/Godot/app_userdata/AFTERIMAGE-2.0/`.

For a nonstandard Python installation, edit `user://preferences.cfg`:

```ini
[generator]
python_path="C:/path/to/python.exe"
worker_path="C:/path/to/level-generation/src/afterimage_levelgen/godot_worker.py"
```

The defaults use this repository's `level-generation/.venv/Scripts/python.exe`.
This integration targets desktop development; distributing Python or a hosted
generation service is not included.

## Chart format

The root [example chart](level_format_example.json) documents the unchanged v1
chart format. Legacy library folders containing `chart.json` still load.

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

The [photo-to-level CLI](level-generation/README.md) can also generate music or
chart existing audio independently. Its local worker connects the same pipeline
to the game. Use CLI `rechart --output <job-folder>/generation` for explicit,
local chart upgrades without another music call. Published library copies are
independent; recharting a job does not silently replace a playable package.

- `main.tscn` / `main.gd`: small screen coordinator.
- `data/`: typed chart/note Resources, JSON/audio loading, persistent library.
- `gameplay/`: composed gameplay scene; independent song clock, scheduler,
  judgment controller, score tracker, and input router. Lane, receptor, tap,
  hold, and effect scenes can be edited independently.
- `ui/`: home, reusable SongWheel/SongCard, photo review, HUD, pause, and results.
  The wheel consumes SongMetadata/SongDifficultyMetadata Resources and emits
  stable song/chart IDs; only the home controller maps those IDs to gameplay.
  It pools 13 cards, bounds its artwork cache to 16 entries, and owns no audio.
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
godot --headless --path afterimage-2.0 --script res://tests/album_checks.gd
godot --headless --path afterimage-2.0 --script res://tests/playback_check.gd
godot --path afterimage-2.0 --script res://tests/visual_check.gd
godot --path afterimage-2.0 --script res://tests/album_visual_check.gd
godot --headless --path afterimage-2.0 --script res://tests/song_wheel_checks.gd
godot --path afterimage-2.0 --script res://tests/song_wheel_visual.gd
python tools/build_assets.py
```

The test runner uses temporary isolated user-data folders for imports and
scores. The playback check takes about 39 seconds. The visual check saves
landscape and portrait PNGs to `tests/artifacts/`. Generated checks and logs
are ignored by Git. The Python generator uses only the standard library and
recreates the deterministic demo WAV, chart, and atlas resources.

Keyboard/touch merging and multi-finger input are covered by synthetic events;
physical touchscreen feel still needs testing on a target device.

Album checks use isolated temporary data and a real local preview subprocess,
without paid requests. The album visual check uses synthetic bright/dark images.
Provider integration is tested with mocks in the Python suite; live generation
is separate from automated verification.


## License

The interface uses [Outfit](https://github.com/Outfitio/Outfit-Fonts), bundled
under the SIL Open Font License in `afterimage-2.0/assets/fonts/OFL.txt`.
Regular, Medium, SemiBold, and Bold share the same variable font. Menu atlas
crops and nine-slice themes can be rebuilt with
`python tools/build_menu_assets.py` (requires Pillow). The menu theme is separate
from the gameplay theme; gameplay uses Outfit without changing lane or HUD layout.

Copyright © 2026. All rights reserved.

This repository is publicly available for viewing and hackathon evaluation purposes only.

No permission is granted to use, copy, modify, redistribute, sublicense, or commercially exploit the source code, except as permitted by applicable law or GitHub's Terms of Service.

For licensing inquiries, contact the repository owner.
