#!/usr/bin/env python3
"""
IPC entry point for the KeynoteToSlides Swift app.

Protocol
--------
Swift writes ONE JSON line to stdin:
    {"command": "<name>", "args": {<key: value, ...>}}

Python writes one or more JSON lines to stdout:
    {"type": "progress", "done": <int>, "total": <int>, "message": "<str>"}  -- 0..n
    {"type": "result",   <command-specific fields...>}                        -- always last
    {"type": "error",    "message": "<str>"}                                  -- on failure

Exit code is 0 on success, 1 on any error.
Errors also go to stderr in plain text for easier debugging.

Path resolution
---------------
In development  : cli.py lives at <project>/python/cli.py
                  business logic lives at <project>/src/
In the .app bundle: cli.py lives at Contents/Resources/python/cli.py
                    business logic lives at Contents/Resources/python/src/
The code below handles both automatically.
"""
from __future__ import annotations

import json
import os
import sys
import zipfile
from pathlib import Path

# ── Locate src/ package ───────────────────────────────────────────────────────
_HERE = Path(__file__).resolve().parent          # .../python/
_PARENT = _HERE.parent                           # project root (dev) or Resources/ (bundle)

for _candidate in [_HERE, _PARENT]:
    if (_candidate / "src").is_dir():
        sys.path.insert(0, str(_candidate))
        break
else:
    sys.exit("cli.py: cannot find src/ package next to cli.py or in parent directory")


# ── Emit helpers ──────────────────────────────────────────────────────────────

def _emit(obj: dict) -> None:
    """Write a JSON object as a single line to stdout and flush immediately."""
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def _progress(done: int, total: int, message: str) -> None:
    _emit({"type": "progress", "done": done, "total": total, "message": message})


def _result(**kwargs) -> None:
    _emit({"type": "result", **kwargs})


def _error(message: str) -> None:
    _emit({"type": "error", "message": message})
    print(f"[cli.py error] {message}", file=sys.stderr, flush=True)


# ── Command handlers ──────────────────────────────────────────────────────────

def _cmd_check_fonts(args: dict) -> None:
    """
    Scan a PPTX for fonts that Google Slides doesn't support natively.

    Input args:
        pptx_path: str  — path to the .pptx file

    Result fields:
        unsupported: list[str]  — fonts present but not in Google Slides
        all_fonts:   list[str]  — all fonts found in the file
    """
    from src.font_checker import extract_fonts_from_pptx, is_supported

    pptx_path = args["pptx_path"]
    all_fonts = sorted(extract_fonts_from_pptx(pptx_path))
    unsupported = [f for f in all_fonts if not is_supported(f)]
    _result(unsupported=unsupported, all_fonts=all_fonts)


def _cmd_replace_fonts(args: dict) -> None:
    """
    Write a new PPTX with font names substituted.

    Input args:
        pptx_path:    str          — source .pptx
        output_path:  str          — destination .pptx
        replacements: dict[str,str] — {"OldFont": "NewFont", ...}

    Result fields:
        output_path: str  — same as input output_path on success
    """
    from src.font_replacer import replace_fonts_in_pptx

    out = replace_fonts_in_pptx(
        args["pptx_path"],
        args["replacements"],
        args["output_path"],
    )
    _result(output_path=out)


def _cmd_has_videos(args: dict) -> None:
    """
    Check whether a PPTX contains embedded video files.

    Input args:
        pptx_path: str  — path to the .pptx file

    Result fields:
        has_videos:  bool       — True if at least one video was found
        video_names: list[str]  — filenames of found videos (basename only)
    """
    _VIDEO_EXTS = {".mp4", ".mov", ".avi", ".wmv", ".m4v", ".mkv", ".ogv", ".webm"}
    pptx_path = args["pptx_path"]
    video_names: list[str] = []

    try:
        with zipfile.ZipFile(pptx_path, "r") as z:
            video_names = [
                Path(name).name
                for name in z.namelist()
                if Path(name).suffix.lower() in _VIDEO_EXTS
            ]
    except Exception as exc:
        _error(f"Could not inspect PPTX for videos: {exc}")
        sys.exit(1)

    _result(has_videos=bool(video_names), video_names=video_names)


def _cmd_list_fonts(args: dict) -> None:
    """
    Return the complete list of fonts known to be supported by Google Slides.

    Result fields:
        fonts: list[str]  — sorted list of all font names
    """
    from src.font_checker import get_all_font_names
    _result(fonts=get_all_font_names())


def _cmd_compress_pptx(args: dict) -> None:
    """
    Recompress images (and optionally strip videos) from a PPTX to bring
    it under Google's 100 MB import limit.

    Input args:
        pptx_path:    str   — source .pptx
        output_path:  str   — destination .pptx

    Progress events are emitted per image processed across all passes.

    Result fields:
        output_path:     str       — path to the compressed file
        original_size:   int       — bytes before compression
        final_size:      int       — bytes after compression
        videos_stripped: list[str] — video filenames that were removed
        under_limit:     bool      — True if final_size ≤ 95 MB
    """
    from src.pptx_compressor import compress_pptx

    def _cb(done: int, total: int, message: str) -> None:
        _progress(done, total, message)

    result = compress_pptx(
        args["pptx_path"],
        args["output_path"],
        progress_callback=_cb,
    )
    _result(
        output_path=result.path,
        original_size=result.original_size,
        final_size=result.final_size,
        videos_stripped=result.videos_stripped,
        under_limit=result.under_limit,
    )


# ── Dispatch table ────────────────────────────────────────────────────────────

_COMMANDS: dict[str, callable] = {
    "check_fonts":   _cmd_check_fonts,
    "replace_fonts": _cmd_replace_fonts,
    "has_videos":    _cmd_has_videos,
    "compress_pptx": _cmd_compress_pptx,
    "list_fonts":    _cmd_list_fonts,
}


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    try:
        raw = sys.stdin.readline()
        if not raw.strip():
            _error("Empty request — expected a JSON line on stdin")
            sys.exit(1)

        try:
            request = json.loads(raw)
        except json.JSONDecodeError as exc:
            _error(f"Invalid JSON on stdin: {exc}")
            sys.exit(1)

        command = request.get("command", "")
        args    = request.get("args", {})

        if command not in _COMMANDS:
            known = ", ".join(sorted(_COMMANDS))
            _error(f"Unknown command '{command}'. Known commands: {known}")
            sys.exit(1)

        _COMMANDS[command](args)

    except Exception as exc:
        import traceback
        _error(str(exc))
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
