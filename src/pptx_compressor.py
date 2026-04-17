"""
Reduce PPTX file size so it fits within Google's 100 MB import limit.

Strategy (applied in order until the file is small enough):
  Pass 1 — Recompress images to JPEG @ quality 82, max 1920 px longest edge
  Pass 2 — More aggressive: quality 65, max 1280 px
  Pass 3 — Strip embedded videos entirely (user is warned)
  Pass 4 — Ultra: quality 45, max 960 px
  Fail   — Return the best we could do with a clear message; caller decides

Videos cannot be recompressed without ffmpeg, so they are removed and the
caller receives a list of stripped filenames to show the user.
"""
from __future__ import annotations

import io
import os
import re
import shutil
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

from PIL import Image

_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".tif", ".gif", ".webp"}
_VIDEO_EXTS = {".mp4", ".mov", ".avi", ".wmv", ".m4v", ".mkv", ".ogv", ".webm"}
_MIN_IMAGE_BYTES = 8_000   # skip tiny images (icons, bullets)
_LIMIT_BYTES = 95 * 1024 * 1024   # 95 MB — leave 5 MB headroom under Google's 100 MB cap

_PASSES = [
    # (max_dimension, jpeg_quality, strip_video)
    (1920, 82, False),
    (1280, 65, False),
    (1280, 65, True),    # strip videos on this pass
    (960,  45, True),
]


@dataclass
class CompressionResult:
    path: str                          # path to the (possibly rewritten) PPTX
    original_size: int                 # bytes
    final_size: int                    # bytes
    videos_stripped: list[str] = field(default_factory=list)   # filenames
    under_limit: bool = True           # False if even max compression wasn't enough


def _has_transparency(img: Image.Image) -> bool:
    """Return True if the image has any transparent or semi-transparent pixels."""
    if img.mode in ("RGBA", "LA"):
        extrema = img.getextrema()
        alpha_extrema = extrema[3] if img.mode == "RGBA" else extrema[1]
        return alpha_extrema[0] < 255   # at least one non-opaque pixel
    if img.mode == "P":
        # Palette mode may have a transparency index
        return "transparency" in img.info
    return False


def _recompress_image(data: bytes, max_dim: int, quality: int) -> bytes:
    """
    Return recompressed image bytes.
    - PNGs with transparency are kept as PNG (transparency preserved).
    - All other images are recompressed as JPEG.
    - Returns original bytes if recompression saves nothing.
    """
    try:
        img = Image.open(io.BytesIO(data))
        orig_mode = img.mode

        # ── Detect transparency before any conversion ──────────────────────
        transparent = _has_transparency(img)

        # ── Resize if oversized ────────────────────────────────────────────
        w, h = img.size
        if max(w, h) > max_dim:
            ratio = max_dim / max(w, h)
            new_size = (max(1, int(w * ratio)), max(1, int(h * ratio)))
            resample = Image.LANCZOS
            if transparent:
                img = img.convert("RGBA").resize(new_size, resample)
            else:
                img = img.convert("RGB").resize(new_size, resample)

        buf = io.BytesIO()

        if transparent:
            # Keep as PNG — converting to JPEG would destroy the alpha channel
            img = img.convert("RGBA")
            img.save(buf, format="PNG", optimize=True)
        else:
            img = img.convert("RGB")
            img.save(buf, format="JPEG", quality=quality, optimize=True)
        result = buf.getvalue()
        return result if len(result) < len(data) else data
    except Exception:
        return data


def _run_pass(
    src: str,
    dst: str,
    max_dim: int,
    quality: int,
    strip_video: bool,
    progress_cb: Optional[Callable[[int, int, str], None]] = None,
) -> list[str]:
    """
    Rewrite src → dst applying the given compression settings.
    Returns list of stripped video filenames.
    """
    stripped: list[str] = []
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".pptx")
    os.close(tmp_fd)

    try:
        with zipfile.ZipFile(src, "r") as zin:
            names = zin.namelist()
            images = [n for n in names if Path(n).suffix.lower() in _IMAGE_EXTS]
            videos = [n for n in names if Path(n).suffix.lower() in _VIDEO_EXTS]
            total = len(images)

            with zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as zout:
                done = 0
                for name in names:
                    ext = Path(name).suffix.lower()

                    # ── Video handling ───────────────────────────────────────
                    if ext in _VIDEO_EXTS:
                        if strip_video:
                            stripped.append(Path(name).name)
                            # Skip — don't write to output
                            continue
                        else:
                            data = zin.read(name)
                            zout.writestr(zin.getinfo(name), data)
                            continue

                    # ── Image recompression ──────────────────────────────────
                    if ext in _IMAGE_EXTS:
                        data = zin.read(name)
                        if len(data) >= _MIN_IMAGE_BYTES:
                            data = _recompress_image(data, max_dim, quality)
                        # JPEG is already compressed — store without deflate
                        zout.writestr(name, data, compress_type=zipfile.ZIP_STORED)
                        done += 1
                        if progress_cb:
                            progress_cb(done, total, f"Compressing image {done}/{total}")
                        continue

                    # ── Everything else (XML, fonts, theme…) ─────────────────
                    zout.writestr(zin.getinfo(name), zin.read(name))

        shutil.move(tmp_path, dst)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise

    return stripped


def compress_pptx(
    src_path: str,
    dst_path: str,
    progress_callback: Optional[Callable[[int, int, str], None]] = None,
) -> CompressionResult:
    """
    Compress a PPTX file using escalating passes until it fits under _LIMIT_BYTES.

    Args:
        src_path:          Source .pptx
        dst_path:          Destination .pptx (may equal src_path)
        progress_callback: Optional callable(done, total, status_message)

    Returns:
        CompressionResult with details of what was done.
    """
    original_size = os.path.getsize(src_path)
    all_stripped: list[str] = []

    # Work in a temp directory so we never corrupt src
    tmp_dir = tempfile.mkdtemp()
    current = src_path

    try:
        for i, (max_dim, quality, strip_video) in enumerate(_PASSES):
            pass_dst = os.path.join(tmp_dir, f"pass{i}.pptx")

            if progress_callback:
                msg = (
                    f"Compression pass {i + 1}/4 "
                    f"({'stripping videos' if strip_video else f'quality {quality}, max {max_dim}px'})…"
                )
                progress_callback(0, 1, msg)

            stripped = _run_pass(
                current, pass_dst,
                max_dim=max_dim,
                quality=quality,
                strip_video=strip_video,
                progress_cb=progress_callback,
            )
            all_stripped.extend(stripped)
            current = pass_dst

            new_size = os.path.getsize(current)
            if new_size <= _LIMIT_BYTES:
                shutil.copy2(current, dst_path)
                return CompressionResult(
                    path=dst_path,
                    original_size=original_size,
                    final_size=new_size,
                    videos_stripped=all_stripped,
                    under_limit=True,
                )

        # All passes exhausted — copy best result anyway
        final_size = os.path.getsize(current)
        shutil.copy2(current, dst_path)
        return CompressionResult(
            path=dst_path,
            original_size=original_size,
            final_size=final_size,
            videos_stripped=all_stripped,
            under_limit=final_size <= _LIMIT_BYTES,
        )

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def needs_compression(path: str) -> bool:
    """Return True if the file exceeds the safe upload threshold."""
    return os.path.getsize(path) > _LIMIT_BYTES


def has_videos(path: str) -> bool:
    """Quick check — returns True if the PPTX contains embedded video files."""
    try:
        with zipfile.ZipFile(path, "r") as z:
            return any(Path(n).suffix.lower() in _VIDEO_EXTS for n in z.namelist())
    except Exception:
        return False
