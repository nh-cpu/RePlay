"""Prepare images in memory; never modify the user's album."""

import io
import re
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError


def natural_key(path: Path):
    return [int(s) if s.isdigit() else s.casefold() for s in re.split(r"(\d+)", path.name)]


def prepare_photos(folder: Path) -> list[tuple[str, bytes]]:
    if not folder.is_dir():
        raise ValueError(f"Photo folder does not exist: {folder}")
    paths = sorted((p for p in folder.iterdir() if p.is_file() and not p.name.startswith(".")),
                   key=lambda p: (natural_key(p), p.name))
    if not 1 <= len(paths) <= 30:
        raise ValueError("Provide between 1 and 30 photos in a dedicated folder")
    result = []
    for path in paths:
        if path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
            raise ValueError(f"Unsupported photo {path.name}; use JPEG, PNG, or WebP")
        try:
            with Image.open(path) as source:
                source.load()
                oriented = ImageOps.exif_transpose(source).convert("RGB")
                oriented.thumbnail((1280, 1280))
                clean = Image.new("RGB", oriented.size)
                clean.paste(oriented)
                buffer = io.BytesIO()
                clean.save(buffer, format="JPEG", quality=85)
                result.append((path.name, buffer.getvalue()))
        except (OSError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
            raise ValueError(f"Unreadable photo: {path.name}") from exc
    return result
