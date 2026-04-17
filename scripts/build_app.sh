#!/usr/bin/env bash
# =============================================================================
# build_app.sh — Build, bundle, and optionally sign/notarize Keynote to Slides
#
# Usage:
#   ./scripts/build_app.sh                          # dev build (ad-hoc signed)
#   ./scripts/build_app.sh --sign "Developer ID Application: Your Name (TEAMID)"
#   ./scripts/build_app.sh --sign "..." --notarize  # full distribution build
#
# Requirements:
#   - Xcode command-line tools  (xcode-select --install)
#   - curl, tar, find (all standard on macOS)
#   - pip3  (comes with python-build-standalone — no system Python needed)
#
# What this script does (in order):
#   1. Build the Swift app with xcodebuild (Release config)
#   2. Download python-build-standalone if not cached in /tmp/
#   3. Copy the Python runtime into the .app bundle
#   4. Copy Python source (python/ and src/) into the bundle
#   5. pip install dependencies into the bundle's site-packages
#   6. Rewrite all shebang lines to use the bundled python3
#   7. Strip __pycache__ and .pyc files (reproducible builds)
#   8. Code-sign everything (ad-hoc or Developer ID)
#   9. Package as a .dmg (requires create-dmg if installed, else zip)
#  10. Notarize and staple (only with --notarize flag)
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/KeynoteToSlides"
XCODE_PROJECT="$PROJECT_DIR/KeynoteToSlides.xcodeproj"
SCHEME="KeynoteToSlides"
CONFIGURATION="Release"
DERIVED_DATA="$REPO_ROOT/.build/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_NAME="KeynoteToSlides.app"
APP_PATH="$PRODUCTS_DIR/$APP_NAME"
OUTPUT_DIR="$REPO_ROOT/dist"

# Python-build-standalone version and download URLs
# Pin to a known-good release. Update this URL to get a newer Python.
PY_VERSION="3.12.9"
PY_RELEASE_DATE="20250311"
PY_BASE_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_RELEASE_DATE}"

ARCH="$(uname -m)"   # arm64 or x86_64
if [[ "$ARCH" == "arm64" ]]; then
    PY_TARBALL="cpython-${PY_VERSION}+${PY_RELEASE_DATE}T000000-aarch64-apple-darwin-install_only.tar.gz"
else
    PY_TARBALL="cpython-${PY_VERSION}+${PY_RELEASE_DATE}T000000-x86_64-apple-darwin-install_only.tar.gz"
fi
PY_CACHE="/tmp/$PY_TARBALL"
PY_DOWNLOAD_URL="$PY_BASE_URL/$PY_TARBALL"

# Signing
SIGN_IDENTITY=""    # set via --sign flag
DO_NOTARIZE=false   # set via --notarize flag
APPLE_ID=""         # set via --apple-id flag  (needed for notarization)
TEAM_ID=""          # set via --team-id flag   (needed for notarization)
APP_PASSWORD=""     # set via --app-password flag (App-specific password)

# ── Argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)        SIGN_IDENTITY="$2"; shift 2 ;;
        --notarize)    DO_NOTARIZE=true; shift ;;
        --apple-id)    APPLE_ID="$2"; shift 2 ;;
        --team-id)     TEAM_ID="$2"; shift 2 ;;
        --app-password) APP_PASSWORD="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "▶  $*"; }
ok()   { echo "✓  $*"; }
die()  { echo "✗  $*" >&2; exit 1; }

require() { command -v "$1" &>/dev/null || die "Required tool not found: $1"; }

require xcodebuild
require curl
require python3

mkdir -p "$OUTPUT_DIR"

# ── Step 1: Build Swift app ───────────────────────────────────────────────────

log "Building Swift app ($CONFIGURATION)…"

CODE_SIGN_ARGS=""
if [[ -z "$SIGN_IDENTITY" ]]; then
    CODE_SIGN_ARGS="CODE_SIGNING_ALLOWED=NO"
    log "  No signing identity provided — using ad-hoc signing (dev build)"
fi

xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    $CODE_SIGN_ARGS \
    build | grep -E "^(error:|warning:|Build succeeded|Build FAILED)" || true

[[ -d "$APP_PATH" ]] || die "xcodebuild succeeded but .app not found at: $APP_PATH"
ok "Swift build complete → $APP_PATH"

RESOURCES="$APP_PATH/Contents/Resources"
mkdir -p "$RESOURCES"

# ── Step 2: Download python-build-standalone ──────────────────────────────────

if [[ ! -f "$PY_CACHE" ]]; then
    log "Downloading Python $PY_VERSION ($ARCH)…"
    log "  URL: $PY_DOWNLOAD_URL"
    curl -L --progress-bar -o "$PY_CACHE" "$PY_DOWNLOAD_URL"
    ok "Downloaded → $PY_CACHE"
else
    ok "Using cached Python tarball: $PY_CACHE"
fi

# ── Step 3: Extract Python runtime into bundle ────────────────────────────────

log "Extracting Python runtime into bundle…"

PY_RUNTIME_DIR="$RESOURCES/python-runtime"
rm -rf "$PY_RUNTIME_DIR"
mkdir -p "$PY_RUNTIME_DIR"

# The tarball contains a 'python/' directory at its root
tar -xzf "$PY_CACHE" -C "$PY_RUNTIME_DIR" --strip-components=1

# Confirm the binary exists
PY_BIN="$PY_RUNTIME_DIR/bin/python3"
[[ -f "$PY_BIN" ]] || die "python3 binary not found at $PY_BIN after extraction"
ok "Python runtime → $PY_RUNTIME_DIR"

# ── Step 4: Copy Python source into bundle ────────────────────────────────────

log "Copying Python source into bundle…"

PY_SRC_DIR="$RESOURCES/python"
rm -rf "$PY_SRC_DIR"
mkdir -p "$PY_SRC_DIR"

# cli.py
cp "$REPO_ROOT/python/cli.py" "$PY_SRC_DIR/cli.py"

# src/ package (business logic — no UI files)
mkdir -p "$PY_SRC_DIR/src"
cp "$REPO_ROOT/src/__init__.py"        "$PY_SRC_DIR/src/__init__.py"
cp "$REPO_ROOT/src/font_checker.py"   "$PY_SRC_DIR/src/font_checker.py"
cp "$REPO_ROOT/src/font_replacer.py"  "$PY_SRC_DIR/src/font_replacer.py"
cp "$REPO_ROOT/src/pptx_compressor.py" "$PY_SRC_DIR/src/pptx_compressor.py"
cp "$REPO_ROOT/src/config.py"         "$PY_SRC_DIR/src/config.py"
# Deliberately NOT copying: google_uploader.py, keynote_exporter.py (moved to Swift)
# Deliberately NOT copying: src/ui/ (Tkinter UI — not needed in Swift app)

ok "Python source → $PY_SRC_DIR"

# ── Step 5: Install pip dependencies into bundle ──────────────────────────────

log "Installing Python dependencies into bundle site-packages…"

SITE_PACKAGES="$PY_SRC_DIR/site-packages"
mkdir -p "$SITE_PACKAGES"

"$PY_BIN" -m pip install \
    --target "$SITE_PACKAGES" \
    --upgrade \
    --no-cache-dir \
    --quiet \
    python-pptx>=0.6.21 \
    Pillow>=10.0.0 \
    lxml>=4.9.0

ok "pip install complete → $SITE_PACKAGES"

# ── Step 6: Rewrite shebangs to use bundled Python ────────────────────────────

log "Rewriting shebangs in site-packages scripts…"

BUNDLED_PY_PATH="@executable_path/../Resources/python-runtime/bin/python3"

find "$SITE_PACKAGES" -name "*.py" -print0 | while IFS= read -r -d '' f; do
    first=$(head -c 16 "$f")
    if [[ "$first" == "#!/usr/bin/python"* ]] || [[ "$first" == "#!/usr/bin/env p"* ]]; then
        sed -i '' "1s|.*|#!$BUNDLED_PY_PATH|" "$f"
    fi
done

ok "Shebangs rewritten"

# ── Step 7: Strip __pycache__ and .pyc files ──────────────────────────────────

log "Stripping .pyc / __pycache__…"
find "$PY_SRC_DIR" -name "*.pyc" -delete
find "$PY_SRC_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
ok "Stripped"

# ── Step 8: Copy credentials (client_secret.json) ────────────────────────────

CREDS_SRC="$REPO_ROOT/credentials/client_secret.json"
if [[ -f "$CREDS_SRC" ]]; then
    log "Bundling client_secret.json…"
    cp "$CREDS_SRC" "$RESOURCES/client_secret.json"
    ok "Credentials bundled"
else
    echo "⚠  credentials/client_secret.json not found — users will see an error at sign-in."
    echo "   See DISTRIBUTION.md for how to obtain one."
fi

# ── Step 9: Code-sign ─────────────────────────────────────────────────────────

sign_item() {
    local path="$1"
    local extra_args="${2:-}"
    codesign \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        --options runtime \
        $extra_args \
        --force \
        "$path" 2>&1 | grep -v "^$" || true
}

if [[ -n "$SIGN_IDENTITY" ]]; then
    log "Code-signing with: $SIGN_IDENTITY"
    ENTITLEMENTS="$PROJECT_DIR/KeynoteToSlides/KeynoteToSlides.entitlements"

    # Sign all .dylib files first (deepest first — codesign requires inside-out order)
    log "  Signing .dylib files…"
    find "$APP_PATH" -name "*.dylib" -print0 | while IFS= read -r -d '' f; do
        sign_item "$f"
    done

    # Sign all .so extension modules (pip-installed native extensions)
    log "  Signing .so extension modules…"
    find "$APP_PATH" -name "*.so" -print0 | while IFS= read -r -d '' f; do
        sign_item "$f"
    done

    # Sign the Python binary itself
    log "  Signing Python binary…"
    sign_item "$PY_RUNTIME_DIR/bin/python3"
    # Also sign versioned binary if present
    for pybinary in "$PY_RUNTIME_DIR"/bin/python3.*; do
        [[ -f "$pybinary" ]] && sign_item "$pybinary"
    done

    # Sign the .app bundle last, with entitlements
    log "  Signing .app bundle…"
    codesign \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --deep \
        --force \
        "$APP_PATH"

    # Verify
    codesign --verify --deep --strict "$APP_PATH" && ok "Signature verified"
    spctl --assess --verbose=4 --type exec "$APP_PATH" 2>&1 | head -5 || true

else
    log "Applying ad-hoc signature (no Developer ID)…"
    codesign --sign - --deep --force "$APP_PATH"
    ok "Ad-hoc signature applied (local use only — cannot be notarized)"
fi

# ── Step 10: Package as .dmg or .zip ─────────────────────────────────────────

APP_DISPLAY_NAME="Keynote to Slides"
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
OUTPUT_BASE="$OUTPUT_DIR/${APP_DISPLAY_NAME// /-}-${VERSION}-${ARCH}"

if command -v create-dmg &>/dev/null; then
    log "Creating .dmg with create-dmg…"
    DMG_PATH="${OUTPUT_BASE}.dmg"
    create-dmg \
        --volname "$APP_DISPLAY_NAME $VERSION" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME" 175 190 \
        --hide-extension "$APP_NAME" \
        --app-drop-link 425 190 \
        "$DMG_PATH" \
        "$PRODUCTS_DIR/" 2>/dev/null || true
    ok "DMG → $DMG_PATH"
else
    log "create-dmg not found — packaging as .zip (install: brew install create-dmg)"
    ZIP_PATH="${OUTPUT_BASE}.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    ok "ZIP → $ZIP_PATH"
fi

# ── Step 11: Notarize and staple ──────────────────────────────────────────────

if $DO_NOTARIZE; then
    [[ -z "$APPLE_ID" ]]     && die "--apple-id required for notarization"
    [[ -z "$TEAM_ID" ]]      && die "--team-id required for notarization"
    [[ -z "$APP_PASSWORD" ]] && die "--app-password required for notarization"
    [[ -z "$SIGN_IDENTITY" ]] && die "--sign required for notarization"

    SUBMIT_PATH="${OUTPUT_BASE}.zip"
    if [[ ! -f "$SUBMIT_PATH" ]]; then
        log "Creating zip for notarization submission…"
        ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_PATH"
    fi

    log "Submitting for notarization (this takes 2–10 minutes)…"
    NOTARIZE_OUTPUT=$(xcrun notarytool submit \
        "$SUBMIT_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait \
        2>&1)

    echo "$NOTARIZE_OUTPUT"

    if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
        ok "Notarization accepted!"

        log "Stapling notarization ticket to .app…"
        xcrun stapler staple "$APP_PATH"
        ok "Stapled"

        # Repackage with the stapled .app
        if command -v create-dmg &>/dev/null; then
            DMG_PATH="${OUTPUT_BASE}.dmg"
            create-dmg \
                --volname "$APP_DISPLAY_NAME $VERSION" \
                --window-pos 200 120 \
                --window-size 600 400 \
                --icon-size 100 \
                --icon "$APP_NAME" 175 190 \
                --hide-extension "$APP_NAME" \
                --app-drop-link 425 190 \
                "$DMG_PATH" \
                "$PRODUCTS_DIR/" 2>/dev/null || true
            log "Signing DMG…"
            codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
            ok "Final notarized DMG → $DMG_PATH"
        else
            rm -f "$SUBMIT_PATH"
            ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_PATH"
            ok "Final notarized ZIP → $SUBMIT_PATH"
        fi
    else
        echo "$NOTARIZE_OUTPUT" | grep "status:" || true
        die "Notarization failed. Run: xcrun notarytool log <submission-id> --apple-id $APPLE_ID --team-id $TEAM_ID --password $APP_PASSWORD"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Build complete"
echo "   App:    $APP_PATH"
echo "   Output: $OUTPUT_DIR"
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo ""
    echo "   ⚠  Ad-hoc signed — runs on THIS Mac only."
    echo "      To distribute, get a Developer ID and run:"
    echo "      ./scripts/build_app.sh --sign \"Developer ID Application: Your Name (TEAMID)\""
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
