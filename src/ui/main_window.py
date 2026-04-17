"""Main application window."""
from __future__ import annotations

import io
import os
import threading
import tempfile
import urllib.request
import webbrowser
import zipfile
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from pathlib import Path

from src.keynote_exporter import export_keynote_to_pptx
from src.font_checker import find_unsupported_fonts
from src.font_replacer import replace_fonts_in_pptx
from src.pptx_compressor import compress_pptx, needs_compression, has_videos
from src.google_uploader import upload_pptx_as_slides, sign_in, sign_out, get_signed_in_user
from src.ui.font_dialog import FontReplacementDialog
from src.config import clear_font_replacements, has_font_replacements

_SENTINEL = object()

# ── Palette ───────────────────────────────────────────────────────────────────
BG       = "#F0F0F5"
CARD     = "#FFFFFF"
CARD2    = "#F2F2F7"
BORDER   = "#D1D1D6"
ACCENT   = "#007AFF"
ACCENT_H = "#0062CC"
TEXT     = "#1C1C1E"
SUBTEXT  = "#8E8E93"
SUCCESS  = "#34C759"
SUCCESS_H= "#248A3D"
ERROR    = "#FF3B30"
GOOGLE   = "#4285F4"
GOOGLE_H = "#2A75F3"

W, H = 640, 720


class MainWindow(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Keynote \u2192 Google Slides")
        self.geometry(f"{W}x{H}")
        self.resizable(False, False)
        self.configure(bg=BG)

        self._keynote_path: str | None = None
        self._slides_url:   str | None = None
        self._user_info:    dict | None = None
        self._avatar_image: tk.PhotoImage | None = None

        self._build()
        self._center()

        threading.Thread(target=self._restore_session, daemon=True).start()

    # ── Build UI ───────────────────────────────────────────────────────────────

    def _build(self):
        self._build_hero()
        # Thin separator after hero
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")
        self._build_account_bar()
        self._build_drop_zone()
        self._build_convert_btn()
        self._build_status_area()
        self._build_utility_bar()
        self._build_footer()

    # ── Hero ───────────────────────────────────────────────────────────────────

    def _build_hero(self):
        hero = tk.Canvas(self, bg="#FFFFFF", highlightthickness=0, height=200)
        hero.pack(fill="x")

        # 200 horizontal lines: top #FFFFFF → bottom #EAF0FF
        r0, g0, b0 = 0xFF, 0xFF, 0xFF
        r1, g1, b1 = 0xEA, 0xF0, 0xFF
        for i in range(200):
            t = i / 199
            r = int(r0 + (r1 - r0) * t)
            g = int(g0 + (g1 - g0) * t)
            b = int(b0 + (b1 - b0) * t)
            hero.create_line(0, i, W, i, fill=f"#{r:02x}{g:02x}{b:02x}")

        # Emoji
        hero.create_text(
            W // 2, 62,
            text="\U0001f4ca",
            font=("Apple Color Emoji", 48),
            anchor="center",
        )

        # Title
        hero.create_text(
            W // 2, 122,
            text="Keynote  \u2192  Google Slides",
            font=("SF Pro Display", 23, "bold"),
            fill=TEXT,
            anchor="center",
        )

        # Subtitle
        hero.create_text(
            W // 2, 158,
            text="Convert presentations and open them directly in Google Slides.",
            font=("SF Pro Text", 13),
            fill=SUBTEXT,
            anchor="center",
            width=480,
        )

    # ── Account bar ────────────────────────────────────────────────────────────

    def _build_account_bar(self):
        self._account_outer = tk.Frame(self, bg=CARD)
        self._account_outer.pack(fill="x")
        self._render_signed_out()

    def _clear_account(self):
        for w in self._account_outer.winfo_children():
            w.destroy()

    def _render_signed_out(self):
        self._clear_account()

        # Top separator
        tk.Frame(self._account_outer, bg=BORDER, height=1).pack(fill="x")

        bar = tk.Frame(self._account_outer, bg=CARD, padx=32, pady=18)
        bar.pack(fill="x")

        tk.Label(
            bar,
            text="Connect your Google account to get started",
            font=("SF Pro Text", 13),
            fg=SUBTEXT,
            bg=CARD,
        ).pack(side="left")

        sign_in_btn = tk.Button(
            bar,
            text="  Sign in with Google  ",
            font=("SF Pro Text", 13, "bold"),
            fg="white",
            bg=GOOGLE,
            activebackground=GOOGLE_H,
            activeforeground="white",
            relief="flat",
            bd=0,
            padx=18,
            pady=9,
            cursor="hand2",
            command=self._do_sign_in,
        )
        sign_in_btn.pack(side="right")
        sign_in_btn.bind("<Enter>", lambda e: sign_in_btn.config(bg=GOOGLE_H))
        sign_in_btn.bind("<Leave>", lambda e: sign_in_btn.config(bg=GOOGLE))

        # Bottom separator
        tk.Frame(self._account_outer, bg=BORDER, height=1).pack(fill="x")

    def _render_signed_in(self, user: dict):
        self._clear_account()

        # Top separator
        tk.Frame(self._account_outer, bg=BORDER, height=1).pack(fill="x")

        bar = tk.Frame(self._account_outer, bg=CARD, padx=32, pady=18)
        bar.pack(fill="x")

        # Avatar placeholder (replaced async)
        self._avatar_label = tk.Label(
            bar,
            text="\U0001f464",
            font=("Apple Color Emoji", 26),
            bg=CARD,
        )
        self._avatar_label.pack(side="left", padx=(0, 12))
        threading.Thread(
            target=self._load_avatar,
            args=(user.get("picture", ""),),
            daemon=True,
        ).start()

        # Name + email column
        info = tk.Frame(bar, bg=CARD)
        info.pack(side="left")
        tk.Label(
            info,
            text=user.get("name", ""),
            font=("SF Pro Text", 13, "bold"),
            fg=TEXT,
            bg=CARD,
            anchor="w",
        ).pack(fill="x")
        tk.Label(
            info,
            text=user.get("email", ""),
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg=CARD,
            anchor="w",
        ).pack(fill="x")

        # Sign out link
        sign_out_btn = tk.Button(
            bar,
            text="Sign out",
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg=CARD,
            activebackground=CARD,
            activeforeground=TEXT,
            relief="flat",
            bd=0,
            cursor="hand2",
            command=self._do_sign_out,
        )
        sign_out_btn.pack(side="right")

        # Bottom separator
        tk.Frame(self._account_outer, bg=BORDER, height=1).pack(fill="x")

    def _render_account_status(self, msg: str):
        self._clear_account()
        tk.Frame(self._account_outer, bg=BORDER, height=1).pack(fill="x")
        bar = tk.Frame(self._account_outer, bg=CARD, padx=32, pady=18)
        bar.pack(fill="x")
        tk.Label(
            bar,
            text=msg,
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg=CARD,
        ).pack(side="left")
        tk.Frame(self._account_outer, bg=BORDER, height=1).pack(fill="x")

    # ── File drop zone ─────────────────────────────────────────────────────────

    def _build_drop_zone(self):
        outer = tk.Frame(self, bg=BG, padx=32, pady=16)
        outer.pack(fill="x")

        self._drop_canvas = tk.Canvas(
            outer,
            bg="#FAFAFA",
            highlightthickness=0,
            height=130,
            cursor="hand2",
        )
        self._drop_canvas.pack(fill="x")
        self._drop_canvas.bind("<Configure>", self._draw_drop_zone)
        self._drop_canvas.bind("<Button-1>", lambda e: self._pick_file())

        # Labels placed as canvas windows
        self._drop_main_lbl = tk.Label(
            self._drop_canvas,
            text="Drop a .key file here",
            font=("SF Pro Text", 14),
            fg=SUBTEXT,
            bg="#FAFAFA",
            cursor="hand2",
        )
        self._drop_sub_lbl = tk.Label(
            self._drop_canvas,
            text="or click to browse",
            font=("SF Pro Text", 12),
            fg="#C7C7CC",
            bg="#FAFAFA",
            cursor="hand2",
        )
        self._drop_main_lbl.bind("<Button-1>", lambda e: self._pick_file())
        self._drop_sub_lbl.bind("<Button-1>", lambda e: self._pick_file())

        # File-selected labels (hidden initially)
        self._file_icon_lbl = tk.Label(
            self._drop_canvas,
            text="\U0001f4cb",
            font=("Apple Color Emoji", 22),
            bg="#FAFAFA",
            cursor="hand2",
        )
        self._file_name_lbl = tk.Label(
            self._drop_canvas,
            text="",
            font=("SF Pro Text", 13, "bold"),
            fg=ACCENT,
            bg="#FAFAFA",
            cursor="hand2",
        )
        self._file_size_lbl = tk.Label(
            self._drop_canvas,
            text="",
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg="#FAFAFA",
            cursor="hand2",
        )
        for lbl in (self._file_icon_lbl, self._file_name_lbl, self._file_size_lbl):
            lbl.bind("<Button-1>", lambda e: self._pick_file())

        self._file_selected = False

        # Drag-and-drop support (tkinterdnd2, optional)
        try:
            self.drop_target_register("DND_Files")  # type: ignore
            self.dnd_bind("<<Drop>>", self._on_drop)  # type: ignore
        except Exception:
            pass

    def _draw_drop_zone(self, event=None):
        c = self._drop_canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        r = 12

        # Background fill (rounded rect approximation via overlapping rects + arcs)
        bg = "#FAFAFA"
        c.create_rectangle(r, 0, w - r, h, fill=bg, outline="")
        c.create_rectangle(0, r, w, h - r, fill=bg, outline="")
        c.create_arc(0, 0, 2 * r, 2 * r, start=90, extent=90, fill=bg, outline="")
        c.create_arc(w - 2 * r, 0, w, 2 * r, start=0, extent=90, fill=bg, outline="")
        c.create_arc(0, h - 2 * r, 2 * r, h, start=180, extent=90, fill=bg, outline="")
        c.create_arc(w - 2 * r, h - 2 * r, w, h, start=270, extent=90, fill=bg, outline="")

        # Dashed border
        dash = (8, 5)
        bc = "#C7C7CC"
        c.create_arc(1, 1, 2 * r + 1, 2 * r + 1, start=90, extent=90,
                     outline=bc, dash=dash, style="arc")
        c.create_arc(w - 2 * r - 1, 1, w - 1, 2 * r + 1, start=0, extent=90,
                     outline=bc, dash=dash, style="arc")
        c.create_arc(1, h - 2 * r - 1, 2 * r + 1, h - 1, start=180, extent=90,
                     outline=bc, dash=dash, style="arc")
        c.create_arc(w - 2 * r - 1, h - 2 * r - 1, w - 1, h - 1, start=270, extent=90,
                     outline=bc, dash=dash, style="arc")
        c.create_line(r, 1, w - r, 1, dash=dash, fill=bc)
        c.create_line(r, h - 1, w - r, h - 1, dash=dash, fill=bc)
        c.create_line(1, r, 1, h - r, dash=dash, fill=bc)
        c.create_line(w - 1, r, w - 1, h - r, dash=dash, fill=bc)

        cx = w // 2
        cy = h // 2

        if not self._file_selected:
            c.create_window(cx, cy - 14, window=self._drop_main_lbl)
            c.create_window(cx, cy + 14, window=self._drop_sub_lbl)
            # Hide file labels
            for lbl in (self._file_icon_lbl, self._file_name_lbl, self._file_size_lbl):
                lbl.place_forget()
        else:
            # Hide default labels
            for lbl in (self._drop_main_lbl, self._drop_sub_lbl):
                lbl.place_forget()
            c.create_window(cx, cy - 26, window=self._file_icon_lbl)
            c.create_window(cx, cy + 2, window=self._file_name_lbl)
            c.create_window(cx, cy + 26, window=self._file_size_lbl)

    # ── Convert button ─────────────────────────────────────────────────────────

    def _build_convert_btn(self):
        self._btn_frame = tk.Frame(self, bg=BG, padx=32)
        self._btn_frame.pack(fill="x", pady=(4, 0))

        self._convert_btn = tk.Button(
            self._btn_frame,
            text="Convert to Google Slides",
            font=("SF Pro Display", 15, "bold"),
            fg="white",
            bg=BORDER,
            activebackground=ACCENT_H,
            activeforeground="white",
            relief="flat",
            bd=0,
            pady=14,
            state="disabled",
            command=self._start_conversion,
        )
        self._convert_btn.pack(fill="x")

    # ── Status / progress / open button ───────────────────────────────────────

    def _build_status_area(self):
        self._status_frame = tk.Frame(self, bg=BG, padx=32)
        self._status_frame.pack(fill="x", pady=(8, 0))

        self._status_var = tk.StringVar(value="")
        self._status_lbl = tk.Label(
            self._status_frame,
            textvariable=self._status_var,
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg=BG,
            wraplength=580,
            justify="center",
        )
        self._status_lbl.pack()

        # Progress bar (slim, hidden until needed)
        style = ttk.Style()
        style.theme_use("default")
        style.configure(
            "Accent.Horizontal.TProgressbar",
            troughcolor=CARD2,
            background=ACCENT,
            borderwidth=0,
            thickness=5,
        )
        self._progress = ttk.Progressbar(
            self._status_frame,
            mode="indeterminate",
            style="Accent.Horizontal.TProgressbar",
            length=W - 64,
        )
        # Not packed yet — shown via _show_progress

        # Open in Google Slides button (hidden until success)
        self._open_btn = tk.Button(
            self._status_frame,
            text="Open in Google Slides",
            font=("SF Pro Display", 15, "bold"),
            fg="white",
            bg=SUCCESS,
            activebackground=SUCCESS_H,
            activeforeground="white",
            relief="flat",
            bd=0,
            pady=14,
            cursor="hand2",
            command=self._open_slides,
        )
        self._open_btn.bind("<Enter>", lambda e: self._open_btn.config(bg=SUCCESS_H))
        self._open_btn.bind("<Leave>", lambda e: self._open_btn.config(bg=SUCCESS))
        # Not packed yet — shown via _finish_success

    # ── Utility bar ────────────────────────────────────────────────────────────

    def _build_utility_bar(self):
        """Two secondary action buttons: sign-out and reset font replacements."""
        bar = tk.Frame(self, bg=BG, padx=32)
        bar.pack(fill="x", pady=(12, 0))

        # ── Reset font replacements ─────────────────────────────────────────
        self._reset_fonts_btn = tk.Button(
            bar,
            text="↺  Reset font replacements",
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg=BG,
            activebackground=BG,
            activeforeground=TEXT,
            relief="flat",
            bd=0,
            cursor="hand2",
            command=self._do_reset_fonts,
        )
        self._reset_fonts_btn.pack(side="left")
        self._reset_fonts_btn.bind("<Enter>", lambda e: self._reset_fonts_btn.config(fg=TEXT))
        self._reset_fonts_btn.bind("<Leave>", lambda e: self._reset_fonts_btn.config(fg=SUBTEXT))
        self._update_reset_fonts_btn()

        # ── Sign out ────────────────────────────────────────────────────────
        self._signout_main_btn = tk.Button(
            bar,
            text="Sign out from Google",
            font=("SF Pro Text", 12),
            fg=SUBTEXT,
            bg=BG,
            activebackground=BG,
            activeforeground=ERROR,
            relief="flat",
            bd=0,
            cursor="hand2",
            command=self._do_sign_out,
        )
        self._signout_main_btn.pack(side="right")
        self._signout_main_btn.bind("<Enter>", lambda e: self._signout_main_btn.config(fg=ERROR))
        self._signout_main_btn.bind("<Leave>", lambda e: self._signout_main_btn.config(fg=SUBTEXT))
        self._update_signout_main_btn()

    def _update_signout_main_btn(self):
        """Show/hide the sign-out button depending on auth state."""
        try:
            if self._user_info:
                self._signout_main_btn.pack(side="right")
            else:
                self._signout_main_btn.pack_forget()
        except Exception:
            pass

    def _update_reset_fonts_btn(self):
        """Dim the reset button when there are no saved replacements."""
        try:
            if has_font_replacements():
                self._reset_fonts_btn.config(fg=SUBTEXT, cursor="hand2", state="normal")
            else:
                self._reset_fonts_btn.config(fg="#C7C7CC", cursor="arrow", state="disabled")
        except Exception:
            pass

    def _do_reset_fonts(self):
        answer = messagebox.askyesno(
            "Reset font replacements",
            "This will forget all your saved font replacement choices.\n\n"
            "Next time an unsupported font is found, you will be asked again.\n\n"
            "Continue?",
            parent=self,
        )
        if answer:
            clear_font_replacements()
            self._update_reset_fonts_btn()

    # ── Footer ─────────────────────────────────────────────────────────────────

    def _build_footer(self):
        tk.Label(
            self,
            text="Requires Keynote installed on this Mac",
            font=("SF Pro Text", 11),
            fg=SUBTEXT,
            bg=BG,
            pady=12,
        ).pack(side="bottom")

    # ── Center window ──────────────────────────────────────────────────────────

    def _center(self):
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry(f"{W}x{H}+{(sw - W) // 2}+{(sh - H) // 2}")

    # ── Auth ───────────────────────────────────────────────────────────────────

    def _restore_session(self):
        try:
            user = get_signed_in_user()
            if user:
                self.after(0, lambda u=user: self._on_signed_in(u))
        except Exception:
            pass

    def _do_sign_in(self):
        self._render_account_status("Signing in\u2026 (check your browser)")
        threading.Thread(target=self._sign_in_thread, daemon=True).start()

    def _sign_in_thread(self):
        try:
            user = sign_in()
            self.after(0, lambda u=user: self._on_signed_in(u))
        except Exception as e:
            msg = str(e)
            self.after(0, lambda m=msg: self._on_sign_in_error(m))

    def _on_signed_in(self, user: dict):
        self._user_info = user
        self._render_signed_in(user)
        self._update_convert_btn()
        self._update_signout_main_btn()

    def _on_sign_in_error(self, msg: str):
        self._render_signed_out()
        messagebox.showerror("Sign-in failed", msg, parent=self)

    def _do_sign_out(self):
        sign_out()
        self._user_info = None
        self._avatar_image = None
        self._render_signed_out()
        self._update_convert_btn()
        self._update_signout_main_btn()

    def _load_avatar(self, url: str):
        try:
            if not url:
                return
            with urllib.request.urlopen(url, timeout=5) as r:
                data = r.read()
            from PIL import Image, ImageDraw, ImageTk
            img = Image.open(io.BytesIO(data)).convert("RGBA").resize((38, 38))
            mask = Image.new("L", (38, 38), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, 37, 37), fill=255)
            img.putalpha(mask)
            photo = ImageTk.PhotoImage(img)
            self._avatar_image = photo
            self.after(0, lambda: self._avatar_label.config(image=photo, text=""))
        except Exception:
            pass

    # ── File selection ─────────────────────────────────────────────────────────

    def _pick_file(self):
        """Open the native macOS file picker via AppleScript (NSOpenPanel).

        The tkinter filedialog uses an old Carbon dialog that cannot access
        the Shared sidebar, iCloud shared folders, or network locations.
        The AppleScript chooser is the exact same panel macOS apps use —
        it shows every location the user can reach in Finder.
        """
        # Use the native macOS file picker via AppleScript.
        # We intentionally omit `of type` so shared iCloud files are never
        # grayed out (their UTI differs depending on how iCloud exposes them).
        # Extension validation is done after selection instead.
        script = '''
tell application "System Events"
    activate
end tell
try
    set chosen to choose file with prompt "Select a Keynote presentation (.key):" with invisibles
    return POSIX path of chosen
on error errMsg number errNum
    return "ERROR:" & errNum & ":" & errMsg
end try
'''
        try:
            import subprocess as _sp
            result = _sp.run(
                ["osascript", "-e", script],
                capture_output=True, text=True, timeout=120,
            )
            path = result.stdout.strip()

            if path.startswith("ERROR:-128"):
                return  # user cancelled — silent

            if path.startswith("ERROR:"):
                raise RuntimeError(path)

            if not path:
                return

            self._set_file(path)

        except Exception:
            # Fallback to tkinter dialog
            path = filedialog.askopenfilename(
                title="Select Keynote presentation",
                filetypes=[("Keynote", "*.key"), ("All files", "*.*")],
            )
            if path:
                self._set_file(path)

    def _on_drop(self, event):
        path = event.data.strip().strip("{}")
        if path.lower().endswith(".key"):
            self._set_file(path)
        else:
            messagebox.showwarning("Wrong file type", "Please drop a .key Keynote file.")

    def _set_file(self, path: str):
        self._keynote_path = path
        # Shared / iCloud placeholder files may report 0 bytes until downloaded
        try:
            size_mb = os.path.getsize(path) / (1024 * 1024)
        except OSError:
            size_mb = 0

        self._file_selected = True
        self._file_name_lbl.config(text=Path(path).name)
        self._file_size_lbl.config(text=f"{size_mb:.1f} MB")

        # Redraw drop zone with file info
        self._draw_drop_zone()

        self._update_convert_btn()
        self._status_var.set("")
        self._status_lbl.config(fg=SUBTEXT)
        self._open_btn.pack_forget()
        self._slides_url = None

    def _update_convert_btn(self):
        ready = bool(self._keynote_path and self._user_info)
        if ready:
            self._convert_btn.config(
                state="normal",
                bg=ACCENT,
                activebackground=ACCENT_H,
                cursor="hand2",
            )
            self._convert_btn.bind("<Enter>", lambda e: self._convert_btn.config(bg=ACCENT_H))
            self._convert_btn.bind("<Leave>", lambda e: self._convert_btn.config(bg=ACCENT))
        else:
            self._convert_btn.config(
                state="disabled",
                bg=BORDER,
                activebackground=BORDER,
                cursor="arrow",
            )
            self._convert_btn.unbind("<Enter>")
            self._convert_btn.unbind("<Leave>")

    # ── Conversion ─────────────────────────────────────────────────────────────

    def _start_conversion(self):
        if not self._keynote_path or not self._user_info:
            return
        self._convert_btn.config(state="disabled", bg=BORDER, cursor="arrow")
        self._open_btn.pack_forget()
        self._slides_url = None
        self._show_progress("Exporting Keynote to PowerPoint\u2026")
        threading.Thread(target=self._convert_thread, daemon=True).start()

    def _convert_thread(self):
        pptx_tmp = compressed_tmp = fixed_tmp = None
        try:
            # 1. Export
            pptx_tmp = export_keynote_to_pptx(self._keynote_path)

            # 2. Font check
            self._update_status("Checking font compatibility\u2026")
            unsupported = find_unsupported_fonts(pptx_tmp)
            font_map: dict[str, str] = {}
            if unsupported:
                font_map = self._ask_font_replacements(unsupported)
                if font_map is None:
                    self._finish_cancelled()
                    return

            # 3. Font replace
            if font_map:
                self._update_status("Replacing fonts\u2026")
                fixed_fd, fixed_tmp = tempfile.mkstemp(suffix=".pptx")
                os.close(fixed_fd)
                replace_fonts_in_pptx(pptx_tmp, font_map, fixed_tmp)
                upload_source = fixed_tmp
            else:
                upload_source = pptx_tmp

            # 4. Video check
            file_mb = os.path.getsize(upload_source) / (1024 * 1024)
            has_vid = has_videos(upload_source)

            if has_vid:
                if not self._confirm_video_strip(upload_source):
                    self._finish_cancelled()
                    return

            # 5. Compress if needed
            if needs_compression(upload_source) or has_vid:
                compressed_fd, compressed_tmp = tempfile.mkstemp(suffix=".pptx")
                os.close(compressed_fd)
                self._update_status(f"File is {file_mb:.0f} MB \u2014 compressing\u2026")

                def _cp(done: int, total: int, msg: str):
                    self._update_status(msg)

                result = compress_pptx(upload_source, compressed_tmp, progress_callback=_cp)
                saved = (result.original_size - result.final_size) / (1024 * 1024)

                if result.videos_stripped:
                    self._update_status(
                        f"Compressed ({saved:.0f} MB saved) \u00b7 "
                        f"\u26a0\ufe0f {len(result.videos_stripped)} video(s) removed."
                    )

                if not result.under_limit:
                    final_mb = result.final_size / (1024 * 1024)
                    raise RuntimeError(
                        f"The file is {final_mb:.0f} MB after maximum compression and "
                        "video removal \u2014 still above Google\u2019s 100 MB import limit.\n\n"
                        "Please split the presentation or remove large images and try again."
                    )

                upload_source = compressed_tmp

            # 6. Upload
            self._update_status("Uploading to Google Drive\u2026")
            title = Path(self._keynote_path).stem

            def _up(sent: int, total: int):
                if total:
                    pct = int(sent / total * 100)
                    self._update_status(
                        f"Uploading\u2026 {pct}%  "
                        f"({sent // (1024 * 1024)} / {total // (1024 * 1024)} MB)"
                    )

            url = upload_pptx_as_slides(upload_source, title=title, progress_callback=_up)
            self._finish_success(url)

        except Exception as exc:
            self._finish_error(str(exc))
        finally:
            for p in (pptx_tmp, fixed_tmp, compressed_tmp):
                if p and os.path.exists(p):
                    try:
                        os.unlink(p)
                    except OSError:
                        pass

    # ── Dialogs ────────────────────────────────────────────────────────────────

    def _confirm_video_strip(self, pptx_path: str) -> bool:
        _VID = {".mp4", ".mov", ".avi", ".wmv", ".m4v", ".mkv", ".ogv", ".webm"}
        try:
            with zipfile.ZipFile(pptx_path) as z:
                vids = [Path(n).name for n in z.namelist() if Path(n).suffix.lower() in _VID]
        except Exception:
            vids = []

        event = threading.Event()
        result = [False]

        def _ask():
            names = "\n\u2022 ".join(vids[:10])
            extra = f"\n\u2026and {len(vids) - 10} more" if len(vids) > 10 else ""
            answer = messagebox.askyesno(
                "Videos detected",
                f"This presentation contains {len(vids)} embedded video(s):\n\n"
                f"\u2022 {names}{extra}\n\n"
                "Google Slides doesn\u2019t support embedded video import.\n"
                "Videos will be removed to reduce file size.\n\n"
                "Continue without videos?",
                parent=self,
            )
            result[0] = answer
            event.set()

        self.after(0, _ask)
        event.wait()
        return result[0]

    def _ask_font_replacements(self, unsupported: list[str]) -> dict[str, str] | None:
        event = threading.Event()
        result = [_SENTINEL]

        def _show():
            dlg = FontReplacementDialog(self, unsupported)
            self.wait_window(dlg)
            result[0] = dlg.result
            # Refresh the reset button — user may have just saved choices
            self.after(0, self._update_reset_fonts_btn)
            event.set()

        self.after(0, _show)
        event.wait()
        return result[0]

    # ── Status helpers ─────────────────────────────────────────────────────────

    def _show_progress(self, msg: str):
        def _ui():
            self._status_lbl.config(fg=SUBTEXT)
            self._status_var.set(msg)
            self._progress.pack(pady=(8, 0))
            self._progress.start(10)
        self.after(0, _ui)

    def _update_status(self, msg: str):
        self.after(0, lambda m=msg: self._status_var.set(m))

    def _finish_success(self, url: str):
        self._slides_url = url

        def _ui():
            self._progress.stop()
            self._progress.pack_forget()
            self._status_lbl.config(fg=SUCCESS)
            self._status_var.set("\u2713  Conversion complete!")
            self._update_convert_btn()
            self._open_btn.pack(fill="x", pady=(10, 0))

        self.after(0, _ui)

    def _finish_error(self, msg: str):
        def _ui():
            self._progress.stop()
            self._progress.pack_forget()
            self._status_lbl.config(fg=ERROR)
            self._status_var.set(f"Error: {msg}")
            self._update_convert_btn()

        self.after(0, _ui)

    def _finish_cancelled(self):
        def _ui():
            self._progress.stop()
            self._progress.pack_forget()
            self._status_lbl.config(fg=SUBTEXT)
            self._status_var.set("Conversion cancelled.")
            self._update_convert_btn()

        self.after(0, _ui)

    def _open_slides(self):
        if self._slides_url:
            webbrowser.open(self._slides_url)
