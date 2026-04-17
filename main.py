#!/usr/bin/env python3
"""Entry point for the Keynote → Google Slides converter app."""
import sys
import os
import subprocess

# Ensure project root is on the path regardless of how the script is invoked
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ── Auto-install dependencies using the same Python that's running this script
_REQUIRED = [
    "pptx",
    "googleapiclient",
    "google_auth_oauthlib",
]
_missing = []
for _pkg in _REQUIRED:
    try:
        __import__(_pkg)
    except ImportError:
        _missing.append(_pkg)

if _missing:
    print(f"Installing missing dependencies: {', '.join(_missing)}", flush=True)
    _req_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "requirements.txt")
    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "-r", _req_file, "-q"],
        stdout=subprocess.DEVNULL,
    )
    print("Dependencies installed.", flush=True)

from src.ui.main_window import MainWindow


def main():
    app = MainWindow()
    app.mainloop()


if __name__ == "__main__":
    main()
