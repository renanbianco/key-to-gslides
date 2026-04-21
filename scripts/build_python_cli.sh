#!/usr/bin/env bash
# scripts/build_python_cli.sh
# ──────────────────────────────────────────────────────────────────────────────
# Builds the one-directory Python CLI bundle used by KeynoteToSlides.
#
# Usage:
#   bash scripts/build_python_cli.sh [--identity "Developer ID Application: ..."]
#
# Output:
#   dist/cli/          ← directory containing cli executable + _internal/
#   dist/cli/cli       ← main executable (point Xcode at this directory)
#
# After the build, add dist/cli/ to Xcode as a FOLDER REFERENCE:
#   File → Add Files to Target → select the dist/cli folder
#   → choose "Create folder references" (blue folder, NOT yellow group)
#   → Target: KeynoteToSlides ✓
# Confirm it appears in Build Phases → Copy Bundle Resources as a folder.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# ── Parse arguments ───────────────────────────────────────────────────────────
SIGN_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity) SIGN_IDENTITY="$2"; shift 2 ;;
        --python)   PYTHON="$2";        shift 2 ;;
        *)          shift ;;
    esac
done

# ── Python executable ─────────────────────────────────────────────────────────
PYTHON="${PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
    for candidate in \
        "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3" \
        "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3" \
        "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3" \
        "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3" \
        "$(which python3 2>/dev/null || true)"
    do
        if [[ -x "$candidate" ]] && "$candidate" -c "import PyInstaller" 2>/dev/null; then
            PYTHON="$candidate"; break
        fi
    done
fi

if [[ -z "$PYTHON" ]]; then
    echo "❌  Could not find a Python with PyInstaller installed."
    echo "    Install it: python3 -m pip install pyinstaller"
    exit 1
fi

echo "✓ Python  : $PYTHON ($("$PYTHON" --version))"
echo "✓ PyInstaller: $("$PYTHON" -m PyInstaller --version 2>/dev/null)"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "→ Cleaning previous build..."
rm -rf build/ dist/

echo "→ Running PyInstaller (one-directory mode)..."
"$PYTHON" -m PyInstaller cli.spec

# ── Verify output ─────────────────────────────────────────────────────────────
CLI_DIR="$PROJECT_ROOT/dist/cli"
CLI_BIN="$CLI_DIR/cli"

if [[ ! -f "$CLI_BIN" ]]; then
    echo "❌  Build failed — dist/cli/cli not found."
    exit 1
fi

SIZE=$(du -sh "$CLI_DIR" | cut -f1)
echo "✓ Bundle size: $SIZE  →  $CLI_DIR"

# ── Codesign all libraries (required for App Store / sandbox) ─────────────────
# If no identity is supplied, auto-detect from keychain.
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E "Apple Development|Developer ID Application|Apple Distribution|3rd Party Mac" \
        | head -1 \
        | sed 's/.*"\(.*\)"/\1/' || true)
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
    echo ""
    echo "⚠️  No codesigning identity found — skipping library signing."
    echo "   For App Store submission, re-run with:"
    echo "   bash scripts/build_python_cli.sh --identity \"Apple Distribution: Your Name\""
else
    echo "→ Codesigning with: $SIGN_IDENTITY"

    # Sign all .so and .dylib files first (leaf nodes), then the main binary.
    # find order matters: sign dependencies before the binary that links them.
    while IFS= read -r -d '' lib; do
        codesign --force --sign "$SIGN_IDENTITY" \
                 --options runtime \
                 --timestamp \
                 "$lib" 2>/dev/null && echo "  signed: $(basename "$lib")" || true
    done < <(find "$CLI_DIR" \( -name "*.so" -o -name "*.dylib" \) -print0)

    # Sign the main executable
    codesign --force --sign "$SIGN_IDENTITY" \
             --options runtime \
             --timestamp \
             "$CLI_BIN"
    echo "  signed: cli (main executable)"

    # Sign the entire bundle directory
    codesign --force --sign "$SIGN_IDENTITY" \
             --options runtime \
             --timestamp \
             "$CLI_DIR"
    echo "  signed: cli/ (bundle)"

    echo "✓ All libraries signed."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "✅  Build succeeded!"
echo "    Directory : $CLI_DIR"
echo "    Executable: $CLI_BIN"
echo "    Size      : $SIZE"
echo ""
echo "Next steps in Xcode:"
echo "  1. Remove the old 'cli' file from the Resources group (if present)"
echo "  2. File → Add Files to Target → select dist/cli folder"
echo "     → 'Create folder references' (blue folder icon)"
echo "     → Target: KeynoteToSlides ✓"
echo "  3. Build Phases → Copy Bundle Resources → confirm 'cli' folder is listed"
echo "  4. Build & run — PythonRunner will find Contents/Resources/cli/cli automatically"
