"""Local, file-based Godot bridge. Preview never imports providers or accesses the network."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import time


def process_alive(pid):
    if pid <= 0:
        return False
    if os.name == "nt":
        # os.kill(pid, 0) can terminate a Windows process; use a query-only handle.
        import ctypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x00100000, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5
        try:
            return kernel.WaitForSingleObject(handle, 0) == 258
        finally:
            kernel.CloseHandle(handle)
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True

# Support launching this file with an explicitly configured virtualenv interpreter.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".writing")
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False), encoding="utf-8")
    os.replace(temporary, path)


def load_environment(path):
    """Read simple KEY=value settings, with shell environment taking precedence."""
    allowed = {"GEMINI_API_KEY", "STABILITY_API_KEY", "GEMINI_MODEL"}
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[7:]
        name, separator, value = line.partition("=")
        if not separator or name.strip() not in allowed:
            continue
        parts = shlex.split(value, comments=True)
        if len(parts) > 1:
            raise ValueError("Quote values containing spaces in the generator .env.")
        os.environ.setdefault(name.strip(), parts[0] if parts else "")


def normalize_photo(path):
    from PIL import Image, ImageOps
    path = Path(path)
    if path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
        raise ValueError("Use JPEG, PNG, or WebP photos.")
    with Image.open(path) as source:
        source.load()
        image = ImageOps.exif_transpose(source).convert("RGB")
        image.thumbnail((1280, 1280))
        clean = Image.new("RGB", image.size)
        clean.paste(image)
        buffer = io.BytesIO()
        clean.save(buffer, format="JPEG", quality=85)
        photo = buffer.getvalue()
        clean.thumbnail((160, 120))
        buffer = io.BytesIO()
        clean.save(buffer, format="JPEG", quality=80)
        return photo, buffer.getvalue()


def preview(request, root):
    paths = request.get("photos", [])
    if not isinstance(paths, list) or not 1 <= len(paths) <= 30:
        raise ValueError("Choose between 1 and 30 photos.")
    result = []
    for index, raw in enumerate(paths):
        try:
            path = Path(raw).resolve(strict=True)
            photo, thumb = normalize_photo(path)
            name = f"{index:03}.jpg"
            (root / name).write_bytes(photo)
            (root / f"thumb_{name}").write_bytes(thumb)
            result.append({"source": str(path), "name": path.name, "photo": str(root / name),
                           "thumbnail": str(root / f"thumb_{name}"),
                           "digest": hashlib.sha256(photo).hexdigest()})
        except Exception:
            result.append({"source": str(raw), "error": "Unreadable or unsupported photo."})
    return {"photos": result}


def make_cues(plan, duration, photo_count):
    planned = float(plan["duration_seconds"])
    if planned <= 0 or duration <= 0:
        raise ValueError("Invalid album timeline.")
    cues = []
    for section in plan["sections"]:
        ids = section["photo_ids"]
        if not ids or any(type(i) is not int or not 0 <= i < photo_count for i in ids):
            raise ValueError("Music plan references an invalid photo.")
        length = float(section["duration_seconds"]) / len(ids) * duration / planned
        for index, photo_id in enumerate(ids):
            start = float(section["start_seconds"]) * duration / planned + index * length
            end = min(duration, start + length)
            if cues and cues[-1]["photo"] == photo_id and abs(cues[-1]["end"] - start) < 0.001:
                cues[-1]["end"] = end
            else:
                cues.append({"photo": photo_id, "start": start, "end": end})
    if not cues or abs(cues[0]["start"]) > 0.001 or abs(cues[-1]["end"] - duration) > 0.001:
        raise ValueError("Music plan does not cover the audio.")
    for previous, current in zip(cues, cues[1:]):
        if abs(previous["end"] - current["start"]) > 0.001:
            raise ValueError("Music plan contains gaps or overlapping sections.")
    return cues


def package_album(request, root, pipeline):
    output = root / "generation"
    stage = root / "package"
    stage.mkdir(exist_ok=True)
    # Only app-owned staging files are replaced; original albums are never touched.
    for difficulty in ("easy", "normal", "hard"):
        pipeline.validate(output / f"{difficulty}.json")
        shutil.copy2(output / f"{difficulty}.json", stage / f"{difficulty}.json")
    shutil.copy2(output / "song.wav", stage / "song.wav")
    photos = []
    for index, path in enumerate(request["photos"]):
        name = f"photo_{index:03}.jpg"
        shutil.copy2(path, stage / name)
        photos.append(name)
    metadata = json.loads((output / "generation_metadata.json").read_text())
    plan = json.loads((output / "music_plan.json").read_text())
    manifest = {"format_version": 1, "id": root.name, "title": request["title"],
                "charts": {d: f"{d}.json" for d in ("easy", "normal", "hard")},
                "photos": photos, "cues": make_cues(plan, metadata["duration_seconds"], len(photos))}
    write_json(stage / "album.json", manifest)
    library = Path(request["library_root"])
    library.mkdir(parents=True, exist_ok=True)
    destination = library / root.name
    if destination.exists():
        existing = json.loads((destination / "album.json").read_text())
        if existing != manifest:
            raise ValueError("A different package already occupies this track ID.")
        for name in ["song.wav", "easy.json", "normal.json", "hard.json", *photos]:
            if not (destination / name).is_file() or (destination / name).read_bytes() != (stage / name).read_bytes():
                raise ValueError("Published track files differ from this job. The existing track was preserved.")
    else:
        os.replace(stage, destination)
    return {"package": str(destination), "track_id": root.name}


def generate(request, root, progress):
    from afterimage_levelgen import pipeline
    from afterimage_levelgen.cli import parser
    title = request.get("title", "").strip()
    if not title or len(title) > 120 or len(request.get("description", "")) > 4000:
        raise ValueError("Enter a title (1–120 characters) and description of at most 4000 characters.")
    paths = [Path(p) for p in request.get("photos", [])]
    if not 1 <= len(paths) <= 30:
        raise ValueError("Choose between 1 and 30 photos.")
    prepared = [(f"{i:03}.jpg", p.read_bytes()) for i, p in enumerate(paths)]
    from PIL import Image
    for _, data in prepared:
        with Image.open(io.BytesIO(data)) as image:
            image.verify()
    if len({hashlib.sha256(data).hexdigest() for _, data in prepared}) != len(prepared):
        raise ValueError("Remove duplicate photos.")
    output = root / "generation"
    # Recover only a demonstrably dead worker's pipeline lock, on explicit retry.
    lock = output / ".running"
    if lock.exists():
        try:
            old_pid = int(lock.read_text())
        except ValueError:
            raise ValueError("Generation lock needs inspection before retrying.") from None
        if process_alive(old_pid):
            raise ValueError("This generation still has an active worker.")
        lock.unlink()
    args = parser().parse_args(["generate", "--photos", str(root / "photos"), "--output", str(output),
                                "--title", title, "--description", request.get("description", "")])
    cache = Path(__file__).resolve().parents[2] / ".cache"
    os.environ.setdefault("TORCH_HOME", str(cache / "torch"))
    os.environ.setdefault("NUMBA_CACHE_DIR", str(cache / "numba"))
    pipeline.generate(args, progress=progress, prepared_photos=prepared)
    progress("Packaging validated Easy, Normal, and Hard charts...")
    return package_album(request, root, pipeline)


def run(request_path):
    request_path = Path(request_path).resolve()
    root = request_path.parent
    status_path = root / "status.json"
    state = {"format_version": 1, "pid": os.getpid(), "state": "running", "stage": "Starting local worker"}

    def progress(message):
        state.update(stage=message, updated_at=time.time())
        write_json(status_path, state)

    try:
        request = json.loads(request_path.read_text(encoding="utf-8"))
        if request.get("format_version") != 1:
            raise ValueError("Unsupported job request version.")
        progress("Preparing photos locally" if request["mode"] == "preview" else "Starting generation")
        if request["mode"] == "preview":
            result = preview(request, root)
        elif request["mode"] == "generate":
            load_environment(Path(__file__).resolve().parents[2] / ".env")
            result = generate(request, root, progress)
        else:
            raise ValueError("Unsupported worker mode.")
        state.update(state="complete", stage="Ready", **result)
        write_json(status_path, state)
        return 0
    except Exception as exc:
        # Provider adapters already sanitize errors; never expose validation inputs or tracebacks.
        from_type = type(exc).__name__
        message = str(exc) if from_type in {"ValueError", "ProviderError"} else (
            "Missing Python dependency; install the generator requirements." if isinstance(exc, ImportError)
            else f"Local worker failed ({from_type}). Check the Python environment and job files.")
        for name in ("GEMINI_API_KEY", "STABILITY_API_KEY"):
            secret = os.environ.get(name)
            if secret:
                message = message.replace(secret, "[redacted]")
        state.update(state="failed", stage=message[:1200])
        write_json(status_path, state)
        return 1


if __name__ == "__main__":
    arguments = argparse.ArgumentParser()
    arguments.add_argument("--request", required=True)
    sys.exit(run(arguments.parse_args().request))
