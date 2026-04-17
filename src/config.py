"""Persistent app configuration stored in ~/.keynote_to_gslides/config.json"""
from __future__ import annotations

import json
import os
from pathlib import Path

_CONFIG_DIR  = Path.home() / ".keynote_to_gslides"
_CONFIG_FILE = _CONFIG_DIR / "config.json"


def _load() -> dict:
    try:
        return json.loads(_CONFIG_FILE.read_text())
    except Exception:
        return {}


def _save(data: dict) -> None:
    _CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    _CONFIG_FILE.write_text(json.dumps(data, indent=2))


def get_google_fonts_api_key() -> str:
    """Return the Google Fonts API key — env var takes priority over saved config."""
    return (
        os.environ.get("GOOGLE_FONTS_API_KEY", "")
        or _load().get("google_fonts_api_key", "")
    )


def set_google_fonts_api_key(key: str) -> None:
    """Persist the API key to config file."""
    data = _load()
    data["google_fonts_api_key"] = key.strip()
    _save(data)


# ── Font replacement memory ────────────────────────────────────────────────────

def get_font_replacements() -> dict:
    """Return the saved font-replacement mapping (may be empty)."""
    return _load().get("font_replacements", {})


def set_font_replacements(replacements: dict) -> None:
    """Merge new replacements into the saved mapping."""
    data = _load()
    existing = data.get("font_replacements", {})
    existing.update(replacements)
    data["font_replacements"] = existing
    _save(data)


def clear_font_replacements() -> None:
    """Wipe all saved font replacements."""
    data = _load()
    data.pop("font_replacements", None)
    _save(data)


def has_font_replacements() -> bool:
    """Return True if there are any saved font replacements."""
    return bool(_load().get("font_replacements"))
