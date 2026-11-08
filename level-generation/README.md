# AFTERIMAGE photo-to-level CLI

This standalone Python 3.11 tool produces `song.wav`, `easy.json`, and
`normal.json` for the game's existing **Import JSON** action. It does not change
Godot, deploy a service, or add an upload interface to the game.

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
$env:GEMINI_MODEL = 'gemini-2.5-flash'
& ./level-generation/.venv/Scripts/python.exe -m afterimage_levelgen generate --photos ./level-generation/photos/trip --output ./level-generation/outputs/trip --title 'Our Trip' --description 'A calm beach morning ending in a city celebration'
```

`.env.example` lists settings; `.env` files are not automatically loaded. Both
providers require accounts with suitable API access. Gemini receives resized,
orientation-corrected JPEG copies without EXIF metadata. Stable Audio receives
the musical prompt, not the photos. Original photos remain untouched.

Defaults: 120-second instrumental electronic music, seed 42, CPU analysis, Easy
and Normal charts. Optional flags: `--duration` (10–380 seconds), `--style`,
`--description`, `--title`, `--gemini-model`, `--seed`, `--chart-seed`, `--device`.
Seed 0 is rejected because Stability treats it as random. Provider seeds do not
guarantee identical audio across future model revisions; cached audio is definitive.

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
- `song.wav`: game-compatible audio shared by both charts.
- `audio_analysis.json`: beat/downbeat/onset timestamps and energy features.
- `easy.json`, `normal.json`: game format version 1, with relative `song.wav` paths.
- `generation_metadata.json`: stage fingerprints, versions, and chart settings.

Keep input photos under `level-generation/photos/` and outputs under
`level-generation/outputs/` so Git ignores them. Arbitrary folders elsewhere in
the repository are not automatically ignored.

Change `--chart-seed` or `--title` to rebuild charts without another music call.
Changing `--seed` in album mode changes the music generation request too. Copy
the whole output folder when moving a level; the JSON files expect `song.wav`
beside them. Import either chart through Godot's **Import JSON** button.

Easy uses quarter-note patterns without chords, with at most two note starts
in any half-open one-second window. Normal adds selected local half-beat attacks
and occasional downbeat chords, capped at four starts in the same window. Both
leave at least two seconds before the first note, insert phrase rests, and use
holds only in sustained passages with sparse attacks. Held lanes are reserved
through release, with an additional reuse gap. Chords count as two starts.

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
both charts to evaluate musical relevance, beat-detection accuracy, and comfort.

Provider and algorithm references:
[Gemini structured output](https://ai.google.dev/gemini-api/docs/structured-output),
[Stable Audio API](https://docs.stability.ai/api-reference/stable-audio/text-to-audio),
[Beat This!](https://github.com/CPJKU/beat_this),
[librosa](https://librosa.org/doc/latest/index.html).
