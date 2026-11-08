import io
import json
import os
from pathlib import Path

import pytest
from PIL import Image

from afterimage_levelgen import godot_worker as worker, pipeline
from afterimage_levelgen.planning import make_plan


def photo(path, color="blue"):
    Image.new("RGB", (320, 180), color).save(path)
    return str(path)


def test_preview_is_local_oriented_and_preserves_original(tmp_path, monkeypatch):
    monkeypatch.setattr(pipeline, "describe_album", lambda *a: pytest.fail("Preview called provider"))
    source = tmp_path / "source.jpg"
    exif = Image.Exif()
    exif[274] = 6
    Image.new("RGB", (1600, 800), "blue").save(source, exif=exif)
    original = source.read_bytes()
    root = tmp_path / "preview"
    root.mkdir()
    (tmp_path / "broken.png").write_bytes(b"bad")
    result = worker.preview({"photos": [str(source), str(tmp_path / "broken.png")]}, root)
    assert result["photos"][1]["error"]
    with Image.open(result["photos"][0]["photo"]) as image:
        assert image.size == (640, 1280)
        assert not image.getexif()
    assert source.read_bytes() == original
    with pytest.raises(ValueError):
        worker.preview({"photos": [str(source)] * 31}, root)


@pytest.mark.parametrize("duration,sections", [(95, 4), (160, 6), (240, 8)])
def test_cues_repeat_merge_and_scale(album, duration, sections):
    plan = make_plan(album, duration)
    assert len(plan.sections) == sections
    cues = worker.make_cues(plan.model_dump(), 111.0, 2)
    assert cues[0]["start"] == 0 and cues[-1]["end"] == pytest.approx(111)
    assert len(cues) == 2
    assert all(a["end"] == pytest.approx(b["start"]) for a, b in zip(cues, cues[1:]))


def test_single_photo_and_invalid_references():
    plan = {"duration_seconds": 100, "sections": [
        {"photo_ids": [0], "start_seconds": i * 25, "duration_seconds": 25} for i in range(4)]}
    assert worker.make_cues(plan, 103, 1) == [{"photo": 0, "start": 0, "end": 103}]
    plan["sections"][0]["photo_ids"] = [2]
    with pytest.raises(ValueError):
        worker.make_cues(plan, 103, 1)


def test_env_fallback_and_precedence(tmp_path, monkeypatch):
    path = tmp_path / ".env"
    path.write_text('GEMINI_API_KEY="local-value"\nSTABILITY_API_KEY=local-music\nIGNORED=ignored\n')
    monkeypatch.setenv("GEMINI_API_KEY", "shell-value")
    monkeypatch.delenv("STABILITY_API_KEY", raising=False)
    worker.load_environment(path)
    assert os.environ["GEMINI_API_KEY"] == "shell-value"
    assert os.environ["STABILITY_API_KEY"] == "local-music"
    assert "IGNORED" not in os.environ


def test_full_worker_package_retry_and_independence(tmp_path, monkeypatch, album, analysis, audio_path):
    root = tmp_path / "job"
    root.mkdir()
    originals = [photo(root / "one.jpg"), photo(root / "two.jpg", "red")]
    request = {"format_version": 1, "mode": "generate", "title": "Album", "description": "",
               "photos": originals, "library_root": str(tmp_path / "library")}
    calls = {"vision": 0, "music": 0}
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setenv("STABILITY_API_KEY", "test")
    monkeypatch.setattr(worker, "load_environment", lambda p: None)

    def describe(*args):
        calls["vision"] += 1
        return album

    def music(plan, *args, **kwargs):
        calls["music"] += 1
        assert plan.style == album.suggested_genre
        assert not plan.duration_override and not plan.style_override
        assert plan.duration_seconds == 105
        return audio_path.read_bytes()

    monkeypatch.setattr(pipeline, "describe_album", describe)
    monkeypatch.setattr(pipeline, "generate_music", music)
    monkeypatch.setattr(pipeline, "analyze", lambda *a: analysis)
    worker.write_json(root / "request.json", request)
    assert worker.run(root / "request.json") == 0
    assert worker.run(root / "request.json") == 0
    assert calls == {"vision": 1, "music": 1}
    status = json.loads((root / "status.json").read_text())
    package = Path(status["package"])
    manifest = json.loads((package / "album.json").read_text())
    assert set(manifest["charts"]) == {"easy", "normal", "hard"}
    assert manifest["cues"][-1]["end"] == 20
    for path in originals:
        Path(path).unlink()
    for name in manifest["photos"]:
        assert (package / name).is_file()
    for name in manifest["charts"].values():
        assert pipeline.validate(package / name)
        assert (package / name).read_bytes() == (root / "generation" / name).read_bytes()
    assert (root / "generation/chart_report.json").is_file()


def test_invalid_chart_never_published(tmp_path, monkeypatch):
    root = tmp_path / "job"
    root.mkdir()
    (root / "generation").mkdir()
    monkeypatch.setattr(pipeline, "validate", lambda p: (_ for _ in ()).throw(ValueError("Invalid chart")))
    with pytest.raises(ValueError):
        worker.package_album({"library_root": str(tmp_path / "library")}, root, pipeline)
    assert not (tmp_path / "library").exists()


def test_failure_status_redacts_credentials(tmp_path, monkeypatch):
    worker.write_json(tmp_path / "request.json", {"format_version": 1, "mode": "generate"})
    monkeypatch.setattr(worker, "load_environment", lambda p: None)
    monkeypatch.setenv("GEMINI_API_KEY", "sensitive-token")
    monkeypatch.setattr(worker, "generate", lambda *a: (_ for _ in ()).throw(ValueError("Failure sensitive-token")))
    assert worker.run(tmp_path / "request.json") == 1
    status = (tmp_path / "status.json").read_text()
    assert "sensitive-token" not in status and "[redacted]" in status


def test_query_process_does_not_terminate():
    assert worker.process_alive(os.getpid())
    assert not worker.process_alive(-1)
