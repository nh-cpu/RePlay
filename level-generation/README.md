# AFTERIMAGE photo-to-level CLI

This standalone Python 3.11 tool produces `song.wav`, `easy.json`, `normal.json`,
and `hard.json`. Godot's **Create from photos** menu calls the same pipeline
through a local worker; the CLI remains independently usable.

## Windows setup

From the repository root, use PowerShell:

```powershell
py -3.11 -m venv level-generation/.venv
& ./level-generation/.venv/Scripts/python.exe -m pip install -r ./level-generation/requirements-lock.txt
& ./level-generation/.venv/Scripts/python.exe -m pip install -e './level-generation[test]'
& ./level-generation/.venv/Scripts/python.exe -m afterimage_levelgen --help
```

Python 3.11 must be installed and runnable. If Windows App Execution Aliases
intercept `python`, use `py -3.11` or the interpreter's full path. Activation is
optional; the commands use the virtual environment explicitly.

`requirements-lock.txt` records the complete resolved Windows/Python 3.11
dependency set; `pyproject.toml` also pins the direct dependencies.

The default runs on CPU. Beat This! downloads its `final0` checkpoint on the first
analysis run into `level-generation/.cache/torch/`; allow network access and disk
space for the model and PyTorch dependencies. Subsequent runs reuse the checkpoint.
There is no silent detector fallback. `--device cuda` requires an appropriate CUDA
build of the matching PyTorch/torchaudio versions and a compatible NVIDIA GPU.

## Try existing audio first (no API keys)

```powershell
& ./level-generation/.venv/Scripts/python.exe -m afterimage_levelgen chart --audio ./afterimage-2.0/assets/first_light.wav --output ./level-generation/outputs/first-light
& ./level-generation/.venv/Scripts/python.exe -m afterimage_levelgen validate ./level-generation/outputs/first-light/easy.json
```

WAV, OGG Vorbis, and MP3 input are decoded with SoundFile. Export is compatible
PCM WAV at the original sample rate, with the same sample count and no trimming
or time stretching. The provider's original WAV is also retained as `generated.wav`.

## Generate from an album

Create a dedicated `level-generation/photos/trip/` folder containing 1–30 JPEG,
PNG, or WebP images. Natural filename order determines the sequence: `1.jpg`,
`2.jpg`, …, `10.jpg`. Unsupported files are rejected; hidden files are ignored.
Subfolders are not traversed. Rename files to choose the story order.

Set credentials in your shell (do not commit them):

```powershell
$env:GEMINI_API_KEY = 'your-key'
$env:STABILITY_API_KEY = 'your-key'
$env:GEMINI_MODEL = 'gemini-3.8-flash'
& ./level-generation/.venv/Scripts/python.exe -m afterimage_levelgen generate --photos ./level-generation/photos/trip --output ./level-generation/outputs/trip --title 'Our Trip' --description 'A calm beach morning ending in a city celebration'
```

`.env.example` lists settings; `.env` files are not automatically loaded. Both
providers require accounts with suitable API access. Gemini receives resized,
orientation-corrected JPEG copies without EXIF metadata. Stable Audio receives
the musical prompt, not the photos. Original photos remain untouched.

Defaults: photo-inspired instrumental music, seed 42, CPU analysis, and all three
difficulties. Gemini chooses a cohesive genre, instruments, tempo, theme groups,
and emotional progression. Electronic music is one possibility, not a fixed default.

Automatic duration is `min(240, 95 + 5 * max(photo_count - 4, 0) + 10 * (distinct_theme_count - 1))`
seconds. Similar scenes share themes, including when they recur later. Small,
single-theme albums start at 95 seconds. The plan records the calculation and
any overrides. Four sections are planned through 120 seconds, six through 180,
and eight above 180, with contrasting passages, evolving motifs, and a resolution.

Optional flags: `--duration` (10–240 seconds), `--style`,
`--description`, `--title`, `--gemini-model`, `--seed`, `--chart-seed`, `--device`.
Seed 0 is rejected because Stability treats it as random. Provider seeds do not
guarantee identical audio across future model revisions; cached audio is definitive.

Explicit duration/style override the automatic choices. Requested duration is
limited to four minutes. A provider recording exceeding 240 seconds is saved but
rejected for album export without automatic regeneration. Existing-audio `chart`
and `rechart` commands accept longer songs.

The music provider uses Stable Audio 3's asynchronous official endpoint. Job IDs
are saved before polling, and interrupted downloads resume on the next invocation.
A submission timeout or interruption before receiving its ID has an unknown outcome:
the tool refuses to submit that job again automatically. Check your provider account;
use a new output directory only when you intend another paid generation. Result
downloads expire after 24 hours. Authentication/credit/rate-limit errors are reported
without response bodies or credentials. No paid call is retried automatically.

## Outputs, caching, and chart behavior

The output folder must be empty or already owned by this tool. The ownership
manifest records artifact hashes and completed stage keys. Repeating a command
reuses completed stages; changed inputs/settings invalidate the affected stages.
Only the latest result for each stage is retained, not a historical archive.
Manually edited artifacts are never overwritten: use a fresh output directory.
An output lock prevents concurrent runs. After a killed process, remove `.running`
only after confirming that process is no longer running. A leftover `.tmp` file
likewise requires inspection and removal before resuming that write.

Artifacts:

- `album_profile.json`: ordered photo interpretations (creative suggestions).
- `music_plan.json`: photo groups, energy, instruments, and the exact prompt.
- `music_job.json`: saved provider job state, without credentials.
- `generated.wav`: unmodified provider response (album mode).
- `song.wav`: game-compatible audio shared by all charts.
- `audio_analysis.json`: timestamps, harmonic/percussive measurements, beat-synchronized features, and change scores.
- `easy.json`, `normal.json`, `hard.json`: game format version 1, with relative `song.wav` paths.
- `chart_report.json`: per-difficulty phrase boundaries, intensity, pattern choices, counts, repetition measurements, and event timing.
- `easy_report.json`, `normal_report.json`, `hard_report.json`: individually cached difficulty reports.
- `generation_metadata.json`: stage fingerprints, versions, and chart settings.

Keep input photos under `level-generation/photos/` and outputs under
`level-generation/outputs/` so Git ignores them. Arbitrary folders elsewhere in
the repository are not automatically ignored.

To upgrade existing generations without calling either API:

```powershell
& ./level-generation/.venv/Scripts/python.exe -m afterimage_levelgen rechart --output ./level-generation/outputs/gundum-test
```

`rechart` preserves album/music metadata, title, chart seed, and saved audio. It
updates outdated analysis locally and rebuilds all three charts and their reports.
It also accepts `--chart-seed`, `--title`, and `--device`. Album, music-plan,
analysis, and chart versions are independent; chart changes cannot invalidate
paid music generation. Use `rechart` for old albums instead of `generate` when
you want to keep the song. The upgraded music planner will request new music
when you run `generate` with the new album interpretation and arrangement.

Change `--chart-seed` or `--title` to rebuild current-version charts without another music call.
Changing `--seed` in album mode changes the music generation request too. Copy
the whole output folder when moving a level; the JSON files expect `song.wav`
beside them. Godot-generated albums publish all three charts as one playlist
entry. Previously imported levels remain independent copies in Godot's library.

## Godot worker

`src/afterimage_levelgen/godot_worker.py --request <request.json>` is the local
bridge used by the game. Version-1 requests use `mode: preview` or
`mode: generate`. Preview requests contain ordered `photos` paths and never
import provider code or access the network. They produce normalized JPEGs,
thumbnails, filenames, and content digests for duplicate detection.

Generate requests contain `title`, `description`, ordered snapshot `photos`,
and `library_root`. They use automatic style/duration, CPU analysis, and the
configured Gemini model. The worker publishes atomic `status.json` updates
(`running`, `complete`, or `failed` with stage information and PID).
Only validated three-chart packages are moved into the library. Job folders
retain the standard generation artifacts, reports, and provider state.

Unlike the CLI, this worker loads simple quoted/unquoted key-value entries from
the generator's local `.env`, without overriding inherited credentials.
Supported names are `GEMINI_API_KEY`, `STABILITY_API_KEY`, and `GEMINI_MODEL`;
shell interpolation is not performed. No credentials enter job requests.

Photo cue times follow planned sections, scaled to actual audio duration;
they are visual sequencing intentions, not detected musical boundaries.
Consecutive repetitions of the same photo merge into one uninterrupted cue.
The v1 beatmaps remain byte-for-byte pipeline outputs.

Charts select measured musical events before assigning lanes. Low/mid/high
frequency attacks and harmonic/percussive components supply evidence, with local
thresholds and signal-based timing refinement. Beats provide context; they never
create notes without an attack. Straight, triplet, swung, and off-grid events keep
their measured timestamps. Four-bar phrases (or a 16-beat fallback) describe the
recording in reports. Repeated music may retain repeated lane motifs.

| Difficulty | Vocabulary | Maximum starts in a half-open rolling second |
|---|---|---:|
| Easy | Dominant pulse, strong accents, supported holds up to two beats; no chords | 2 |
| Normal | Eighth notes, swing/triplets, offbeats, supported chords and holds up to four beats | 4 |
| Hard | Additional reliable attacks, continuous sixteenths, syncopation, supported chords and holds | 8 |

Stronger evidenced accents win selection conflicts. Hard follows sustained fast
passages when supported; no fixed burst/recovery cycle interrupts the music.
Chords require distinct coincident component evidence, not merely a downbeat or
broadband hit. Chords count as two starts. At most two
keys are required simultaneously, including held notes. Same-lane reuse gaps are
120 ms on Easy/Normal and 90 ms on Hard.

All charts leave two seconds before the first note. Breathing room follows audible
gaps rather than mandatory phrase-ending rests. Holds require a harmonic entrance,
continuation, and release evidence; unchanged background energy cannot repeatedly
create holds. This remains an audio-feature heuristic, not instrument transcription.

Reports link every note to its source event and record confidence, rhythm,
chord/hold evidence, rejection reasons, density, and difficulty overlap. If a chart
adds fewer than 15% new attack timestamps over the preceding difficulty and fewer
than 10% of its notes add hold/chord coordination, the terminal prints an advisory
on both fresh and cached runs. Sparse songs still export without filler notes.
These diagnostics are not calibrated human difficulty ratings.

Use `rechart --output <existing-folder>` to apply new detection and selection to
saved audio without paid requests. This upgrade invalidates analysis/chart caches
only. Re-import the resulting JSON into Godot: previously imported copies do not
update automatically. Listen and playtest before judging musical fidelity.

Actual audio is the timing authority. A representative BPM is stored for the
v1 importer, but `beat = timestamp_seconds * bpm / 60` encodes each measured event
individually. Fractional beats therefore preserve timing even with tempo drift;
they are not a claim that the music has a constant tempo. Requested tempo, section
durations, and mood are creative intentions, not provider guarantees.

The validator checks schema, finite values, positive durations, lane bounds,
duplicates/overlaps (including hold tails), audio decoding, and the game's 160 ms
end tolerance. Generated charts finish strictly before the audio ends. Standalone
validation accepts filesystem audio references, not Godot `res://` or `user://` URIs.

## Verification

```powershell
& ./level-generation/.venv/Scripts/python.exe -m pytest ./level-generation/tests -q
& ./level-generation/.venv/Scripts/python.exe -m pip check
```

Tests mock paid provider calls, exercise the full orchestration, and use synthetic
audio to test analysis/export timing. The synthetic timing tests supply exact beat
timestamps to isolate clock conversion from machine-learning accuracy. Run the
demo command above to exercise the real pretrained detector. A live album test
requires credentials and is separate from the automated suite. Listen and play
all three charts to evaluate musical relevance, beat-detection accuracy, and comfort.

The long-song tests cover 180- and 240-second synthetic feature timelines with
breakdowns, builds and recurring themes, as well as density, active-key limits,
subdivision evidence and continuous supported streams. Waveform tests additionally
cover swing, triplets, quiet attacks, offbeats, sustained tones, broadband hits,
noise, and tempo drift. To test exports against the real Godot
loader and judgment controller, substitute your Godot executable:

```powershell
godot --headless --path afterimage-2.0 --script ../level-generation/tests/godot_chart_check.gd -- 'C:/absolute/path/to/generation-folder'
```

This simulates perfect input for every note across the entire song; it does not
replace a human listening/playability review.

To prepare 15-second opening, middle, breakdown, and climax excerpts with chart
clicks for all three difficulties (use an empty review destination):

```powershell
& ./level-generation/.venv/Scripts/python.exe ./level-generation/tools/review_charts.py ./level-generation/outputs/gundum-dynamic ./level-generation/outputs/review-dynamic
```

The clips keep original event timing and use different click pitches for lanes.
They are listening aids; the saved song and charts are not modified.

Provider and algorithm references:
[Gemini structured output](https://ai.google.dev/gemini-api/docs/structured-output),
[Stable Audio API](https://docs.stability.ai/api-reference/stable-audio/text-to-audio),
[Beat This!](https://github.com/CPJKU/beat_this),
[librosa](https://librosa.org/doc/latest/index.html).

### Gemini request errors

The pipeline sends an inline schema containing types, required fields, and object
structure. Pydantic's stricter bounds and extra-field checks run locally after
generation; sending those constraints through the older SDK can cause HTTP 400.

If Gemini reports that `gemini-2.5-flash` is unavailable to new users, pass
`--gemini-model gemini-3.8-flash`, or set `GEMINI_MODEL=gemini-3.8-flash` in your
shell. When editing `.env`, reload it into your shell before running the CLI.
The replacement model was verified with a real four-photo album. Switching
models invalidates only the album interpretation stage and its dependent results.
