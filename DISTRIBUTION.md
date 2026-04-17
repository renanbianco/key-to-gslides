# Building, Signing, Notarizing, and Shipping Keynote to Slides

This document covers everything needed to go from source code to a publicly
distributable, notarized macOS `.app`.

---

## Prerequisites

| Tool | Install |
|---|---|
| Xcode 14+ | App Store or [developer.apple.com](https://developer.apple.com) |
| Xcode CLI tools | `xcode-select --install` |
| `create-dmg` (optional, for DMG packaging) | `brew install create-dmg` |

No system Python is needed — the build script downloads and embeds
[python-build-standalone](https://github.com/astral-sh/python-build-standalone).

---

## 1. Set up Google OAuth credentials

The app needs a Google Cloud OAuth 2.0 **Desktop client** to sign users in.

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a project (or use an existing one)
3. Enable the **Google Drive API** and the **Google People API**
4. Go to **APIs & Services → Credentials → Create Credentials → OAuth client ID**
5. Application type: **Desktop app**
6. Download the JSON file and save it as:
   ```
   credentials/client_secret.json
   ```
   (already in `.gitignore` — never commit this file)

> **For a public release**: Google requires you to submit the app for OAuth
> verification if it will be used by more than 100 users. During testing you
> can add up to 100 test users in the OAuth consent screen without verification.

---

## 2. Development build (no signing — local use only)

```bash
# Clone or cd into the repo
cd "key to gslides"

# Make the script executable (once)
chmod +x scripts/build_app.sh

# Build (downloads Python ~35 MB on first run, cached afterwards)
./scripts/build_app.sh
```

The `.app` is placed in `dist/`. It runs on **your Mac only** because it is
ad-hoc signed (`codesign --sign -`). Double-clicking it will show a Gatekeeper
warning — right-click → Open to bypass it during development.

---

## 3. Get an Apple Developer account

To distribute publicly without Gatekeeper warnings, you need a
**$99/year Apple Developer Program** membership:

1. Enroll at [developer.apple.com/enroll](https://developer.apple.com/enroll)
2. After approval (usually same day for individuals), open **Xcode →
   Settings → Accounts → + → Apple ID**
3. Click **Manage Certificates → + → Developer ID Application**
   - This creates the signing certificate in your Keychain
4. Note your **Team ID** — visible in Xcode Accounts or at
   [developer.apple.com/account](https://developer.apple.com/account)
   (looks like `ABCDE12345`)

---

## 4. Distribution build (Developer ID signed)

```bash
./scripts/build_app.sh \
    --sign "Developer ID Application: Your Full Name (TEAMID)"
```

Replace `Your Full Name` and `TEAMID` with your actual values. The name
must match exactly what appears in Keychain Access under your certificate.

To find it:
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

---

## 5. Notarize and staple

Notarization lets Gatekeeper approve your app on any Mac without a warning.
It requires an **app-specific password** (not your Apple ID login password):

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign In → App-Specific Passwords → Generate
3. Label it "Keynote to Slides notarytool" and copy the password

Then run:

```bash
./scripts/build_app.sh \
    --sign "Developer ID Application: Your Full Name (TEAMID)" \
    --notarize \
    --apple-id  "you@example.com" \
    --team-id   "ABCDE12345" \
    --app-password "xxxx-xxxx-xxxx-xxxx"
```

The script will:
1. Build and sign the app
2. Submit to Apple's notary service (`xcrun notarytool submit --wait`)
3. Wait for the result (typically 2–10 minutes)
4. Staple the ticket to the `.app` so it works offline
5. Repackage as a `.dmg` or `.zip`

To check the status of a previous submission manually:
```bash
xcrun notarytool history \
    --apple-id "you@example.com" \
    --team-id "ABCDE12345" \
    --password "xxxx-xxxx-xxxx-xxxx"

# Get the full log for a failed submission:
xcrun notarytool log <submission-id> \
    --apple-id "you@example.com" \
    --team-id "ABCDE12345" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

---

## 6. Verify the signed + notarized build

```bash
# Verify code signature
codesign --verify --deep --strict dist/KeynoteToSlides.app
echo $?   # must be 0

# Check Gatekeeper acceptance (simulates what a user's Mac does)
spctl --assess --verbose=4 --type exec dist/KeynoteToSlides.app

# Check stapling (should say "The file already has a ticket stapled to it")
xcrun stapler validate dist/KeynoteToSlides.app
```

---

## 7. Distribute

### Option A — Direct download (simplest)
Upload `dist/Keynote-to-Slides-1.0-arm64.dmg` (or `.zip`) to GitHub Releases,
your website, or any file host. Users download and drag to Applications.

### Option B — Mac App Store (future, requires Sandbox)
The app currently has `com.apple.security.app-sandbox = false` because it
spawns a Python subprocess and uses Apple Events. Sandboxing would require
significant architectural changes (XPC service for the Python runtime). Skip
this for now.

---

## 8. Entitlements explained

The `KeynoteToSlides.entitlements` file contains four keys. Apple accepts all
of them for notarization — they are standard for apps embedding Python:

| Key | Why it's needed |
|---|---|
| `app-sandbox: false` | App spawns Python subprocess, writes temp files, sends Apple Events to Keynote — incompatible with sandbox |
| `automation.apple-events` | Sends AppleScript to Keynote.app to trigger PPTX export |
| `cs.allow-jit` | Python's `eval()`, `ctypes`, and some Pillow operations call `mprotect(PROT_EXEC)` |
| `cs.allow-unsigned-executable-memory` | pip-installed `.so` files (lxml, Pillow native modules) load native code |
| `cs.disable-library-validation` | pip `.so` files are signed by their own build chains, not your Developer ID — without this, `dyld` refuses to load them |

---

## 9. Updating Python version

The embedded Python version is pinned in `scripts/build_app.sh`:

```bash
PY_VERSION="3.12.9"
PY_RELEASE_DATE="20250311"
```

To upgrade:
1. Browse [github.com/astral-sh/python-build-standalone/releases](https://github.com/astral-sh/python-build-standalone/releases)
2. Find a release for `cpython-X.Y.Z+DATE-aarch64-apple-darwin-install_only.tar.gz`
3. Update `PY_VERSION` and `PY_RELEASE_DATE` in `build_app.sh`
4. Delete the cached tarball in `/tmp/` and rebuild

---

## 10. Updating Python dependencies

Edit `python/requirements.txt`, then rebuild:
```bash
./scripts/build_app.sh
```

The script always runs `pip install --upgrade`, so the bundle will have the
latest compatible versions.

---

## Quick-reference cheatsheet

```bash
# Dev build (instant, no account needed)
./scripts/build_app.sh

# Signed distribution build
./scripts/build_app.sh --sign "Developer ID Application: Name (TEAM)"

# Full notarized release
./scripts/build_app.sh \
  --sign "Developer ID Application: Name (TEAM)" \
  --notarize \
  --apple-id  you@example.com \
  --team-id   ABCDE12345 \
  --app-password xxxx-xxxx-xxxx-xxxx

# Verify
codesign --verify --deep --strict dist/KeynoteToSlides.app && echo "OK"
spctl --assess --verbose=4 --type exec dist/KeynoteToSlides.app
xcrun stapler validate dist/KeynoteToSlides.app
```
