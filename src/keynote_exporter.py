"""Export Keynote files to PPTX using AppleScript."""
import subprocess
import tempfile
import os
from pathlib import Path


def _find_keynote_app() -> tuple[str, str]:
    """
    Return (app_name, app_path) for the Keynote app installed on this machine.
    Searches /Applications and ~/Applications for any .app whose name contains 'keynote'.
    Falls back to 'Keynote' if nothing is found.
    """
    search_dirs = [
        "/Applications",
        "/System/Applications",
        os.path.expanduser("~/Applications"),
    ]
    for d in search_dirs:
        try:
            for entry in os.scandir(d):
                if entry.name.endswith(".app") and "keynote" in entry.name.lower():
                    app_name = entry.name[:-4]   # strip .app
                    return app_name, entry.path
        except FileNotFoundError:
            pass
    return "Keynote", "/Applications/Keynote.app"


_KEYNOTE_APP_NAME, _KEYNOTE_APP_PATH = _find_keynote_app()


def _build_applescript(keynote_path: str, pptx_path: str) -> str:
    """Build an AppleScript that exports a Keynote file to PPTX.

    Uses the app's display name (e.g. "Keynote Creator Studio") so AppleScript
    can address it correctly. The app is pre-launched via `open -a` before this
    script runs, so we just need to wait for it to be ready.
    """
    ks = keynote_path.replace("\\", "\\\\").replace('"', '\\"')
    ps = pptx_path.replace("\\", "\\\\").replace('"', '\\"')
    name = _KEYNOTE_APP_NAME.replace('"', '\\"')

    return f'''
tell application "{name}"
    -- Wait up to 15 s for the app to be fully running
    repeat 30 times
        if running then exit repeat
        delay 0.5
    end repeat

    set targetDoc to open POSIX file "{ks}"

    -- Wait up to 30 s for slides to be available
    repeat 60 times
        try
            if (count of slides of targetDoc) > 0 then exit repeat
        end try
        delay 0.5
    end repeat

    export targetDoc to POSIX file "{ps}" as Microsoft PowerPoint

    close targetDoc saving no
end tell
'''


def _resolve_path(raw: str) -> str:
    """
    Safely resolve a file path without breaking iCloud/network shared files.

    `Path.resolve()` follows symlinks and can return a path that doesn't exist
    for iCloud Drive files that haven't been downloaded yet, or for files shared
    via Finder/AirDrop. We try resolve() first, then fall back to abspath().
    If the file still appears missing we attempt to trigger an iCloud download
    via `brctl download` and wait briefly.
    """
    p = Path(raw)

    # Try full resolution first
    resolved = p.resolve()
    if resolved.exists():
        return str(resolved)

    # Fall back to abspath (doesn't chase symlinks)
    absolute = Path(os.path.abspath(raw))
    if absolute.exists():
        return str(absolute)

    # The file may be an iCloud placeholder — try to download it
    try:
        subprocess.run(
            ["brctl", "download", str(absolute)],
            capture_output=True, timeout=30,
        )
        import time
        for _ in range(10):         # wait up to 10 s
            time.sleep(1)
            if absolute.exists():
                return str(absolute)
    except Exception:
        pass

    # Give up and return the raw path — let the OS report the real error
    return str(absolute)


def export_keynote_to_pptx(keynote_path: str) -> str:
    """
    Export a Keynote file to PPTX format using AppleScript.
    Returns the path to the exported PPTX file.
    Raises RuntimeError if export fails.
    """
    keynote_path = _resolve_path(keynote_path)
    if not os.path.exists(keynote_path):
        raise FileNotFoundError(
            f"Keynote file not found: {keynote_path}\n\n"
            "If this file is stored in iCloud Drive or a shared folder, "
            "make sure it's fully downloaded before converting.\n"
            "In Finder, right-click the file → 'Download Now' if you see a cloud icon."
        )

    # Pre-launch Keynote with `open -a` so it's running before AppleScript tries to talk to it.
    # This sidesteps the -600 "Application isn't running" error that occurs when
    # AppleScript tries to both launch AND address the app in one step.
    subprocess.run(
        ["open", "-a", _KEYNOTE_APP_PATH],
        capture_output=True,
        timeout=15,
    )
    # Give the app a moment to finish its splash/startup sequence
    import time
    time.sleep(2)

    tmp = tempfile.NamedTemporaryFile(suffix=".pptx", delete=False)
    tmp.close()
    pptx_path = tmp.name

    script_fd, script_path = tempfile.mkstemp(suffix=".applescript")
    try:
        with os.fdopen(script_fd, "w", encoding="utf-8") as f:
            f.write(_build_applescript(keynote_path, pptx_path))

        result = subprocess.run(
            ["osascript", script_path],
            capture_output=True,
            text=True,
            timeout=180,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"AppleScript export failed:\n{result.stderr.strip() or result.stdout.strip()}"
            )
        if not os.path.exists(pptx_path) or os.path.getsize(pptx_path) == 0:
            raise RuntimeError("Export produced no output file.")
        return pptx_path

    except subprocess.TimeoutExpired:
        raise RuntimeError("Keynote export timed out (>180s).")
    except Exception:
        if os.path.exists(pptx_path):
            os.unlink(pptx_path)
        raise
    finally:
        if os.path.exists(script_path):
            os.unlink(script_path)
