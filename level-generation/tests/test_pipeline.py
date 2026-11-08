import io
import json
from pathlib import Path

import pytest
from PIL import Image

from afterimage_levelgen import pipeline
from afterimage_levelgen.cli import main, parser
from afterimage_levelgen.photos import prepare_photos
from afterimage_levelgen.planning import make_plan
from afterimage_levelgen.storage import Store, stage_key


def test_photo_order_resize_metadata(tmp_path):
    exif = Image.Exif()
    exif[274] = 6
    for name in ["photo10.jpg", "photo2.jpg", "photo1.jpg"]:
        Image.new("RGB", (1600, 800), "blue").save(tmp_path / name, exif=exif)
    photos = prepare_photos(tmp_path)
    assert [p[0] for p in photos] == ["photo1.jpg", "photo2.jpg", "photo10.jpg"]
    with Image.open(io.BytesIO(photos[0][1])) as image:
        assert image.size == (640, 1280)
        assert not image.getexif()
    with Image.open(tmp_path / "photo1.jpg") as image:
        assert image.size == (1600, 800)


@pytest.mark.parametrize("kind", ["empty", "many", "unsupported", "corrupt"])
def test_bad_albums(tmp_path, kind):
    if kind == "many":
        for i in range(31):
            (tmp_path / f"{i}.jpg").touch()
    elif kind == "unsupported":
        (tmp_path / "image.heic").touch()
    elif kind == "corrupt":
        (tmp_path / "image.jpg").write_bytes(b"bad")
    with pytest.raises(ValueError):
        prepare_photos(tmp_path)


def test_plan_groups_and_duration(album):
    plan = make_plan(album, 120, "electronic")
    assert sum(s.duration_seconds for s in plan.sections) == 120
    ids = [p for s in plan.sections for p in s.photo_ids]
    assert set(ids) == {0, 1} and ids == sorted(ids)
    assert len(plan.sections) == 4
    assert "No vocals" in plan.prompt
    assert plan.sections[0].energy < plan.sections[-1].energy


def test_store_refuses_unrelated_and_modified(tmp_path):
    (tmp_path / "mine.txt").write_text("keep")
    with pytest.raises(ValueError, match="empty"):
        Store(tmp_path)
    store = Store(tmp_path / "output")
    with store.lock():
        store.write("song.wav", b"owned")
    (store.root / "song.wav").write_bytes(b"edited")
    with pytest.raises(ValueError, match="modified"), store.lock():
        pass
    assert (store.root / "song.wav").read_bytes() == b"edited"


def test_cache_settings_and_content(tmp_path):
    store = Store(tmp_path)
    key = stage_key("analysis", {"audio": "abc", "device": "cpu"})
    store.write_json("analysis.json", {"ok": True})
    store.commit("analysis", key)
    assert store.cached("analysis", key, "analysis.json")
    assert not store.cached("analysis", stage_key("analysis", {"audio": "changed"}), "analysis.json")
    (tmp_path / "analysis.json").unlink()
    assert not store.cached("analysis", key, "analysis.json")


def test_chart_pipeline_and_reuse(tmp_path, audio_path, analysis, monkeypatch):
    calls = []
    monkeypatch.setattr(pipeline, "analyze", lambda *a: calls.append(a) or analysis)
    output = tmp_path / "out"
    argv = ["chart", "--audio", str(audio_path), "--output", str(output)]
    assert main(argv) == 0
    assert main(argv + ["--chart-seed", "81"]) == 0
    assert len(calls) == 1
    assert main(["validate", str(output / "easy.json")]) == 0
    assert main(["validate", str(output / "normal.json")]) == 0
    assert (output / "song.wav").read_bytes() == audio_path.read_bytes()


def test_full_pipeline_mocked_providers(tmp_path, audio_path, analysis, album, monkeypatch):
    photos = tmp_path / "photos"
    photos.mkdir()
    for i in range(2):
        Image.new("RGB", (32, 32), "blue").save(photos / f"{i}.jpg")
    calls = {"vision": 0, "music": 0, "analysis": 0}
    def describe(*args):
        calls["vision"] += 1
        return album
    def music(*args, **kwargs):
        calls["music"] += 1
        return audio_path.read_bytes()
    def detect(*args):
        calls["analysis"] += 1
        return analysis
    monkeypatch.setattr(pipeline, "describe_album", describe)
    monkeypatch.setattr(pipeline, "generate_music", music)
    monkeypatch.setattr(pipeline, "analyze", detect)
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setenv("STABILITY_API_KEY", "test")
    output = tmp_path / "out"
    args = ["generate", "--photos", str(photos), "--output", str(output)]
    assert main(args) == 0
    assert calls == {"vision": 1, "music": 1, "analysis": 1}
    monkeypatch.delenv("GEMINI_API_KEY")
    monkeypatch.delenv("STABILITY_API_KEY")
    assert main(args + ["--chart-seed", "12", "--title", "Changed title"]) == 0
    assert calls == {"vision": 1, "music": 1, "analysis": 1}
    monkeypatch.setenv("STABILITY_API_KEY", "test")
    assert main(args + ["--style", "ambient"]) == 0
    assert calls["vision"] == 1 and calls["music"] == 2
    # The mocked provider returned identical audio, so analysis remains reusable.
    assert calls["analysis"] == 1
    assert pipeline.validate(output / "easy.json")
    assert pipeline.validate(output / "normal.json")


def test_cli_defaults_and_invalid_settings(tmp_path):
    args = parser().parse_args(["generate", "--photos", "photos", "--output", "out"])
    assert args.duration is None and args.style is None and args.seed == 42 and args.device == "cpu"
    assert main(["generate", "--photos", "photos", "--output", str(tmp_path), "--duration", "nan"]) == 1
    assert main(["chart", "--audio", "missing.wav", "--output", str(tmp_path), "--seed", "0"]) == 1


@pytest.mark.parametrize("field", ["format_version", "lane_count", "offset_seconds"])
def test_validator_requires_fields(tmp_path, audio_path, field):
    data = {"format_version": 1, "lane_count": 4, "bpm": 120, "offset_seconds": 0,
            "song": audio_path.name, "notes": [{"beat": 4, "lane": 0, "type": "tap"}]}
    del data[field]
    path = tmp_path / "chart.json"
    path.write_text(json.dumps(data))
    assert main(["validate", str(path)]) == 1
