# cli.spec
# PyInstaller spec for the KeynoteToSlides Python CLI.
#
# Produces a one-directory bundle: dist/cli/
#   dist/cli/cli          ← main executable
#   dist/cli/_internal/   ← Python runtime, .so files, packages
#
# The directory layout allows every .so/.dylib to be individually codesigned,
# which is required for Mac App Store (cs.disable-library-validation not needed).
#
# Build from the project root:
#   bash scripts/build_python_cli.sh

import sys
from pathlib import Path

block_cipher = None

# Project root is the directory this spec lives in.
PROJECT_ROOT = str(Path(SPECPATH))

a = Analysis(
    [str(Path(PROJECT_ROOT) / "python" / "cli.py")],
    pathex=[PROJECT_ROOT],          # makes `src` package importable during analysis
    binaries=[],
    datas=[],
    hiddenimports=[
        "src",
        "src.config",
        "src.font_checker",
        "src.font_replacer",
        "src.pptx_compressor",
        "src.google_uploader",
        "src.keynote_exporter",
        # pptx/lxml sub-packages that PyInstaller may miss
        "lxml._elementpath",
        "lxml.etree",
        "PIL._tkinter_finder",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "tkinter", "_tkinter",
        "PyQt5", "PyQt6", "PySide2", "PySide6",
        "wx", "gi",
        "matplotlib", "numpy", "pandas",
        "IPython", "jupyter",
        "scipy", "sklearn",
        "src.ui",
        "src.google_uploader",
        "src.keynote_exporter",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# One-DIRECTORY build: EXE is just the launcher; binaries/datas go into COLLECT.
# This means every .so and .dylib is a separate file that can be individually
# codesigned — required for Mac App Store (no cs.disable-library-validation).
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,          # binaries go to COLLECT, not baked into EXE
    name="cli",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="cli",
)
