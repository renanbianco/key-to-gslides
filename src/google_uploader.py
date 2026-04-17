"""Upload a PPTX to Google Drive, converting it to Google Slides."""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Optional, Callable

# Human-readable explanations for known Google Drive API error reasons
_DRIVE_ERRORS = {
    "uploadTooLarge":       "The file is too large for Google to convert (limit: 100 MB). "
                            "Try splitting the presentation into smaller files.",
    "storageQuotaExceeded": "Your Google Drive storage is full. "
                            "Free up space at drive.google.com and try again.",
    "rateLimitExceeded":    "Google API rate limit hit. Please wait a minute and try again.",
    "userRateLimitExceeded":"Too many requests. Please wait a moment and try again.",
    "forbidden":            "Access denied. Make sure your Google account has Drive access.",
    "notFound":             "Upload session expired. Please try again.",
}

import requests as _requests

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = [
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
    "openid",
]

_PPTX_MIME = (
    "application/vnd.openxmlformats-officedocument"
    ".presentationml.presentation"
)
_SLIDES_MIME = "application/vnd.google-apps.presentation"
_UPLOAD_URL  = "https://www.googleapis.com/upload/drive/v3/files"

_CREDENTIALS_FILE = Path(__file__).parent.parent / "credentials" / "client_secret.json"
_TOKEN_FILE       = Path(__file__).parent.parent / "credentials" / "token.json"

# 5 MB — must be a multiple of 256 KB per Google's spec
_CHUNK_SIZE = 5 * 1024 * 1024


# ── Auth ──────────────────────────────────────────────────────────────────────

def _get_credentials(force_new: bool = False) -> Credentials:
    creds = None
    if not force_new and _TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(_TOKEN_FILE), SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not _CREDENTIALS_FILE.exists():
                raise FileNotFoundError(
                    f"Google credentials file not found at:\n{_CREDENTIALS_FILE}\n\n"
                    "Please download your OAuth2 client_secret.json from Google Cloud Console\n"
                    "and place it at the path above.\n\n"
                    "See setup_google_credentials.md for step-by-step instructions."
                )
            flow = InstalledAppFlow.from_client_secrets_file(
                str(_CREDENTIALS_FILE), SCOPES
            )
            creds = flow.run_local_server(port=0)

        _TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        _TOKEN_FILE.write_text(creds.to_json())

    return creds


def sign_in(force_new: bool = False) -> dict:
    creds = _get_credentials(force_new=force_new)
    service = build("oauth2", "v2", credentials=creds)
    info = service.userinfo().get().execute()
    return {
        "email": info.get("email", ""),
        "name":  info.get("name",  ""),
        "picture": info.get("picture", ""),
    }


def get_signed_in_user() -> Optional[dict]:
    if not _TOKEN_FILE.exists():
        return None
    try:
        creds = Credentials.from_authorized_user_file(str(_TOKEN_FILE), SCOPES)
        if creds and (creds.valid or (creds.expired and creds.refresh_token)):
            if creds.expired:
                creds.refresh(Request())
                _TOKEN_FILE.write_text(creds.to_json())
            service = build("oauth2", "v2", credentials=creds)
            info = service.userinfo().get().execute()
            return {
                "email": info.get("email", ""),
                "name":  info.get("name",  ""),
                "picture": info.get("picture", ""),
            }
    except Exception:
        pass
    return None


def sign_out() -> None:
    if _TOKEN_FILE.exists():
        _TOKEN_FILE.unlink()


# ── Upload ────────────────────────────────────────────────────────────────────

def _initiate_resumable_session(access_token: str, title: str, file_size: int) -> str:
    """
    POST to Drive to open a resumable upload session.
    Returns the upload URI (Location header).
    """
    resp = _requests.post(
        _UPLOAD_URL,
        params={"uploadType": "resumable", "fields": "id,webViewLink"},
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Type": _PPTX_MIME,
            "X-Upload-Content-Length": str(file_size),
        },
        data=json.dumps({
            "name": title,
            "mimeType": _SLIDES_MIME,
        }),
        timeout=30,
    )
    resp.raise_for_status()
    return resp.headers["Location"]


def upload_pptx_as_slides(
    pptx_path: str,
    title: Optional[str] = None,
    progress_callback: Optional[Callable[[int, int], None]] = None,
) -> str:
    """
    Upload a PPTX to Google Drive using a fully-manual resumable upload,
    converting it to Google Slides on the fly.

    Uses raw requests + RFC 7233 range headers so every chunk is exactly
    _CHUNK_SIZE bytes — the Python client library is bypassed entirely for
    the upload itself, which avoids the 413 the googleapis client can trigger.

    Args:
        pptx_path:         Local .pptx file.
        title:             Google Slides presentation title.
        progress_callback: Optional callable(bytes_uploaded, total_bytes).

    Returns:
        Google Slides web URL.
    """
    if title is None:
        title = Path(pptx_path).stem

    creds = _get_credentials()
    # Ensure token is fresh
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())

    file_size = os.path.getsize(pptx_path)
    upload_uri = _initiate_resumable_session(creds.token, title, file_size)

    offset = 0
    file_id = None
    web_link = None

    def _friendly_error(resp: _requests.Response) -> str:
        """Convert a Drive API error response into a readable message."""
        try:
            body = resp.json()
            reason = (
                body.get("error", {})
                    .get("errors", [{}])[0]
                    .get("reason", "")
            )
            if reason in _DRIVE_ERRORS:
                return _DRIVE_ERRORS[reason]
            message = body.get("error", {}).get("message", resp.text)
            return f"Google Drive error ({resp.status_code}): {message}"
        except Exception:
            return f"Google Drive error {resp.status_code}: {resp.text[:300]}"

    def _query_resume_offset(uri: str, token: str) -> Optional[int]:
        """Ask Drive where it left off; returns byte offset or None."""
        try:
            qr = _requests.put(
                uri,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Range": f"bytes */{file_size}",
                    "Content-Length": "0",
                },
                timeout=30,
            )
            if "Range" in qr.headers:
                return int(qr.headers["Range"].split("-")[1]) + 1
        except Exception:
            pass
        return None

    with open(pptx_path, "rb") as fh:
        while offset < file_size:
            # Refresh token if it expired mid-upload
            if creds.expired:
                creds.refresh(Request())

            chunk = fh.read(_CHUNK_SIZE)
            chunk_len = len(chunk)
            end = offset + chunk_len - 1

            headers = {
                "Authorization": f"Bearer {creds.token}",
                "Content-Type": _PPTX_MIME,
                "Content-Length": str(chunk_len),
                "Content-Range": f"bytes {offset}-{end}/{file_size}",
            }

            last_error = None
            for attempt in range(5):
                try:
                    resp = _requests.put(
                        upload_uri, headers=headers, data=chunk, timeout=120
                    )
                except (_requests.ConnectionError, _requests.Timeout) as e:
                    # Network hiccup — wait and retry from last confirmed offset
                    wait = 2 ** attempt
                    time.sleep(wait)
                    resumed = _query_resume_offset(upload_uri, creds.token)
                    if resumed is not None:
                        offset = resumed
                        fh.seek(offset)
                    last_error = f"Network error: {e}"
                    continue

                if resp.status_code in (200, 201):
                    data = resp.json()
                    file_id  = data.get("id")
                    web_link = data.get("webViewLink")
                    offset   = file_size
                    break

                elif resp.status_code == 308:
                    # Chunk accepted — advance
                    offset += chunk_len
                    if progress_callback:
                        progress_callback(offset, file_size)
                    break

                elif resp.status_code == 429:
                    # Rate limited — back off
                    retry_after = int(resp.headers.get("Retry-After", 2 ** attempt))
                    time.sleep(retry_after)
                    last_error = _DRIVE_ERRORS["rateLimitExceeded"]
                    continue

                elif resp.status_code in (500, 502, 503, 504):
                    # Transient server error — resume
                    time.sleep(2 ** attempt)
                    resumed = _query_resume_offset(upload_uri, creds.token)
                    if resumed is not None:
                        offset = resumed
                        fh.seek(offset)
                    last_error = f"Server error {resp.status_code}, retrying…"
                    continue

                elif resp.status_code == 404:
                    # Upload session expired (Drive sessions last 7 days but can drop)
                    raise RuntimeError(
                        "Upload session expired. Please try again. "
                        f"({_DRIVE_ERRORS['notFound']})"
                    )

                else:
                    # Non-retryable error (413, 403, etc.)
                    raise RuntimeError(_friendly_error(resp))

            else:
                raise RuntimeError(
                    f"Upload failed after 5 attempts. Last error: {last_error}"
                )

    if file_id:
        return web_link or f"https://docs.google.com/presentation/d/{file_id}/edit"
    raise RuntimeError("Upload completed but no file ID was returned by Google Drive.")
