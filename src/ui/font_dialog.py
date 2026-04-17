"""Font replacement dialog for the Keynote → Google Slides converter."""
from __future__ import annotations

import tkinter as tk
import tkinter.font as tkfont
from src.font_checker import GOOGLE_SLIDES_FONTS, _FONTS_LOWER
from src.config import get_font_replacements, set_font_replacements

# ── Palette ───────────────────────────────────────────────────────────────────
BG      = "#F0F0F5"
CARD    = "#FFFFFF"
CARD2   = "#F2F2F7"
BORDER  = "#D1D1D6"
ACCENT  = "#007AFF"
ACCENT_H= "#0062CC"
TEXT    = "#1C1C1E"
SUBTEXT = "#8E8E93"
SEP     = "#E5E5EA"
HOVER   = "#EBF3FF"

ROW_H     = 32   # dropdown row height
MAX_ROWS  = 10   # max visible dropdown rows


def _get_sorted_fonts() -> list[str]:
    return sorted(GOOGLE_SLIDES_FONTS)


def _resolve_font_name(typed: str) -> str:
    """
    Resolve a typed font name to the canonical Google Fonts casing.

    Resolution order:
      1. Exact case-insensitive match  → return canonical name (e.g. "arial" → "Arial")
      2. The typed string is a unique prefix of exactly ONE font → use that font
         (e.g. "tenor" → "Tenor Sans" when that's the only match)
      3. Otherwise use the typed value as-is (user knows what they want).
    """
    if not typed:
        return "Arial"
    t = typed.strip()
    t_low = t.lower()

    # 1. exact case-insensitive match
    if t_low in _FONTS_LOWER:
        for f in GOOGLE_SLIDES_FONTS:
            if f.lower() == t_low:
                return f

    # 2. unique prefix / contains match
    starts = [f for f in GOOGLE_SLIDES_FONTS if f.lower().startswith(t_low)]
    if len(starts) == 1:
        return starts[0]
    contains = [f for f in GOOGLE_SLIDES_FONTS if t_low in f.lower()]
    if len(contains) == 1:
        return contains[0]

    return t  # use as-is


def _try_font(family: str, size: int) -> tkfont.Font:
    try:
        f = tkfont.Font(family=family, size=size)
        f.measure("A")
        return f
    except Exception:
        return tkfont.Font(family="Helvetica", size=size)


# ── Autocomplete Entry ────────────────────────────────────────────────────────

class AutocompleteEntry(tk.Frame):
    """
    An Entry with a live dropdown suggestion list.

    - Type anything — the typed value is ALWAYS used as-is when confirmed.
    - Suggestions filter as you type; click one or press ↑↓ + Enter to pick.
    - Works entirely within the dialog window (no Toplevel tricks).
    """

    def __init__(self, parent, font_list: list[str], initial: str = "Arial",
                 width: int = 28, **kw):
        super().__init__(parent, bg=CARD, **kw)

        self._all   = font_list
        self._shown: list[str] = []
        self._sel   = -1          # highlighted index in dropdown
        self._open  = False
        self._fcache: dict[str, tkfont.Font] = {}

        # ── Entry ─────────────────────────────────────────────────────────────
        self._var = tk.StringVar(value=initial)
        self._var.trace_add("write", self._on_type)

        self._entry = tk.Entry(
            self, textvariable=self._var,
            font=("SF Pro Text", 13),
            relief="flat", bd=0,
            bg=CARD2, fg=TEXT,
            insertbackground=ACCENT,
            width=width,
        )
        self._entry.pack(fill="x", ipady=7, ipadx=8)
        self._entry.bind("<KeyPress-Up>",    self._move_up)
        self._entry.bind("<KeyPress-Down>",  self._move_down)
        self._entry.bind("<Return>",         self._pick_selected)
        self._entry.bind("<Escape>",         self._close_dropdown)
        self._entry.bind("<Tab>",            self._pick_selected)
        self._entry.bind("<FocusOut>",       lambda e: self.after(150, self._close_dropdown))

        # ── Dropdown (hidden until needed) ────────────────────────────────────
        self._drop_frame = tk.Frame(self, bg=CARD,
                                    highlightbackground=BORDER,
                                    highlightthickness=1)

        self._canvas = tk.Canvas(self._drop_frame, bg=CARD,
                                 highlightthickness=0)
        self._sb = tk.Scrollbar(self._drop_frame, orient="vertical",
                                command=self._canvas.yview, width=10)
        self._canvas.configure(yscrollcommand=self._sb.set)
        self._sb.pack(side="right", fill="y")
        self._canvas.pack(side="left", fill="both", expand=True)

        self._canvas.bind("<Motion>",   self._on_hover)
        self._canvas.bind("<Leave>",    self._on_leave)
        self._canvas.bind("<Button-1>", self._on_click)
        # Scroll bindings on canvas
        self._canvas.bind("<MouseWheel>",
                          lambda e: self._canvas.yview_scroll(int(-e.delta/20), "units"))
        self._canvas.bind("<Button-4>",
                          lambda e: self._canvas.yview_scroll(-1, "units"))
        self._canvas.bind("<Button-5>",
                          lambda e: self._canvas.yview_scroll(1, "units"))

    # ── Value ─────────────────────────────────────────────────────────────────

    def get(self) -> str:
        """Return whatever the user typed or selected — always used as-is."""
        return self._var.get().strip()

    def set(self, value: str):
        self._var.set(value)

    # ── Typing ────────────────────────────────────────────────────────────────

    def _on_type(self, *_):
        q = self._var.get().strip().lower()
        if not q:
            self._shown = self._all[:MAX_ROWS * 3]
        else:
            self._shown = [f for f in self._all if q in f.lower()]
        self._sel = -1
        self._render_dropdown()
        self._show_dropdown()

    # ── Dropdown render ───────────────────────────────────────────────────────

    def _font(self, name: str) -> tkfont.Font:
        if name not in self._fcache:
            self._fcache[name] = _try_font(name, 13)
        return self._fcache[name]

    def _render_dropdown(self):
        self._canvas.delete("all")
        cw = 280
        for i, name in enumerate(self._shown):
            y0, y1 = i * ROW_H, (i + 1) * ROW_H
            bg = ACCENT if i == self._sel else (HOVER if i % 2 == 0 and i != self._sel else CARD)
            bg = ACCENT if i == self._sel else CARD
            fg = "white" if i == self._sel else TEXT
            self._canvas.create_rectangle(0, y0, cw, y1, fill=bg, outline="", tags=f"r{i}")
            self._canvas.create_text(10, y0 + ROW_H // 2, text=name,
                                     font=self._font(name), fill=fg,
                                     anchor="w", tags=f"t{i}")
        total = len(self._shown) * ROW_H
        self._canvas.configure(scrollregion=(0, 0, cw, total))

    def _show_dropdown(self):
        if not self._shown:
            self._close_dropdown()
            return
        h = min(len(self._shown), MAX_ROWS) * ROW_H
        self._canvas.configure(height=h, width=280)
        self._drop_frame.place(
            in_=self, x=0,
            y=self._entry.winfo_height(),
            width=296,
        )
        self._drop_frame.lift()
        self._open = True

    def _close_dropdown(self, *_):
        self._drop_frame.place_forget()
        self._open = False

    # ── Keyboard nav ──────────────────────────────────────────────────────────

    def _move_up(self, _=None):
        if not self._open: return
        self._sel = max(self._sel - 1, 0)
        self._render_dropdown()

    def _move_down(self, _=None):
        if not self._open:
            self._on_type()
            return
        self._sel = min(self._sel + 1, len(self._shown) - 1)
        self._render_dropdown()
        # Scroll into view
        self._canvas.yview_moveto(self._sel * ROW_H /
                                  max(len(self._shown) * ROW_H, 1))

    def _pick_selected(self, _=None):
        if self._open and 0 <= self._sel < len(self._shown):
            self._var.set(self._shown[self._sel])
        self._close_dropdown()
        return "break"

    # ── Mouse ─────────────────────────────────────────────────────────────────

    def _y_to_idx(self, ey: int) -> int | None:
        top   = self._canvas.yview()[0]
        total = len(self._shown) * ROW_H
        idx   = int((ey + top * total) // ROW_H)
        return idx if 0 <= idx < len(self._shown) else None

    def _on_hover(self, e):
        idx = self._y_to_idx(e.y)
        if idx == self._sel: return
        self._sel = idx if idx is not None else -1
        self._render_dropdown()

    def _on_leave(self, _=None):
        self._sel = -1
        self._render_dropdown()

    def _on_click(self, e):
        idx = self._y_to_idx(e.y)
        if idx is not None:
            self._var.set(self._shown[idx])
            self._close_dropdown()


# ── Font Replacement Dialog ───────────────────────────────────────────────────

class FontReplacementDialog(tk.Toplevel):
    """
    Modal — one row per unsupported font.
    Left: font name in its own typeface.
    Right: AutocompleteEntry — type freely or pick from dropdown.
    Top: "Replace all" field.
    result: dict[str, str] | None  (None = cancelled)
    """

    _W        = 820
    _ROW_H    = 64
    _MAX_ROWS = 8
    _LEFT_W   = 340
    _PAD      = 32

    def __init__(self, parent: tk.Tk, unsupported: list[str]):
        super().__init__(parent)
        self.title("Font Replacement")
        self.resizable(False, False)
        self.configure(bg=BG)
        self.grab_set()

        self.result: dict[str, str] | None = None
        self._entries:    dict[str, AutocompleteEntry] = {}
        self._font_list   = _get_sorted_fonts()
        self._unsupported = unsupported
        self._saved       = get_font_replacements()   # previously saved choices

        self._build(unsupported)
        self.protocol("WM_DELETE_WINDOW", self._cancel)

        # Global scroll binding — routes to whichever canvas is under cursor
        self.bind_all("<MouseWheel>", self._global_scroll)
        self.bind_all("<Button-4>",   self._global_scroll)
        self.bind_all("<Button-5>",   self._global_scroll)

        self._center(parent)

    def _global_scroll(self, e):
        """Forward scroll to the rows canvas."""
        delta = int(-e.delta / 20) if e.num not in (4, 5) else (-1 if e.num == 4 else 1)
        try:
            self._canvas.yview_scroll(delta, "units")
        except Exception:
            pass

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build(self, unsupported: list[str]):
        # Header
        hdr = tk.Frame(self, bg=CARD, padx=self._PAD, pady=22)
        hdr.pack(fill="x")
        tk.Label(hdr, text="Some fonts need replacing",
                 font=("SF Pro Display", 18, "bold"), fg=TEXT, bg=CARD,
                 anchor="w").pack(fill="x")
        tk.Label(hdr,
                 text="Type any Google Font name or pick from the list. "
                      "Whatever you type will be used — even if it's not in the list.",
                 font=("SF Pro Text", 13), fg=SUBTEXT, bg=CARD, anchor="w",
                 wraplength=self._W - self._PAD * 2).pack(fill="x", pady=(4, 0))

        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # ── Replace ALL strip ─────────────────────────────────────────────────
        all_bar = tk.Frame(self, bg=CARD2, padx=self._PAD, pady=14)
        all_bar.pack(fill="x")

        tk.Label(all_bar, text="Replace ALL with one font:",
                 font=("SF Pro Text", 13, "bold"), fg=TEXT, bg=CARD2).pack(side="left")

        self._all_entry = AutocompleteEntry(
            all_bar, self._font_list, initial="", width=24
        )
        self._all_entry.pack(side="left", padx=(14, 0))

        apply_all_btn = tk.Button(
            all_bar, text="Apply to all",
            font=("SF Pro Text", 12, "bold"),
            fg="white", bg=ACCENT, activebackground=ACCENT_H,
            relief="flat", bd=0, cursor="hand2", padx=12, pady=6,
            command=self._apply_all,
        )
        apply_all_btn.pack(side="left", padx=(10, 0))
        apply_all_btn.bind("<Enter>", lambda e: apply_all_btn.config(bg=ACCENT_H))
        apply_all_btn.bind("<Leave>", lambda e: apply_all_btn.config(bg=ACCENT))

        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # ── Column headers ────────────────────────────────────────────────────
        col_hdr = tk.Frame(self, bg=CARD2, padx=self._PAD, pady=6)
        col_hdr.pack(fill="x")
        tk.Label(col_hdr, text="Font in your presentation",
                 font=("SF Pro Text", 11), fg=SUBTEXT, bg=CARD2,
                 width=28, anchor="w").pack(side="left")
        tk.Label(col_hdr, text="Replace with (type any Google Font name)",
                 font=("SF Pro Text", 11), fg=SUBTEXT, bg=CARD2,
                 anchor="w").pack(side="left", padx=(16, 0))

        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # ── Scrollable rows ───────────────────────────────────────────────────
        n_vis    = min(len(unsupported), self._MAX_ROWS)
        canvas_h = n_vis * self._ROW_H

        wrap = tk.Frame(self, bg=CARD)
        wrap.pack(fill="x")

        sb = tk.Scrollbar(wrap, orient="vertical", width=10)
        self._canvas = tk.Canvas(
            wrap, bg=CARD, highlightthickness=0,
            height=canvas_h, width=self._W,
            yscrollcommand=sb.set,
        )
        sb.config(command=self._canvas.yview)
        if len(unsupported) > self._MAX_ROWS:
            sb.pack(side="right", fill="y")
        self._canvas.pack(side="left", fill="x")

        self._inner = tk.Frame(self._canvas, bg=CARD)
        self._canvas.create_window(0, 0, window=self._inner,
                                   anchor="nw", width=self._W)
        self._inner.bind("<Configure>",
                         lambda e: self._canvas.configure(
                             scrollregion=self._canvas.bbox("all")))

        for i, name in enumerate(unsupported):
            self._add_row(name, add_sep=(i < len(unsupported) - 1))

        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # ── Footer ────────────────────────────────────────────────────────────
        ftr = tk.Frame(self, bg=CARD, padx=self._PAD, pady=20)
        ftr.pack(fill="x", side="bottom")

        # Save checkbox (left side of footer)
        self._save_var = tk.BooleanVar(value=bool(self._saved))
        save_cb = tk.Checkbutton(
            ftr,
            text="Remember these replacements for future conversions",
            variable=self._save_var,
            font=("SF Pro Text", 12),
            fg=TEXT, bg=CARD,
            activebackground=CARD,
            selectcolor=CARD,
            relief="flat", bd=0,
            cursor="hand2",
        )
        save_cb.pack(side="left")

        cancel = tk.Button(ftr, text="Cancel",
                           font=("SF Pro Text", 13), fg=SUBTEXT, bg=CARD,
                           activebackground=CARD, activeforeground=TEXT,
                           relief="flat", bd=0, cursor="hand2",
                           command=self._cancel)
        cancel.pack(side="right", padx=(12, 0))

        apply = tk.Button(ftr, text="Apply & Convert",
                          font=("SF Pro Text", 13, "bold"),
                          fg="white", bg=ACCENT, activebackground=ACCENT_H,
                          activeforeground="white", relief="flat", bd=0,
                          cursor="hand2", padx=24, pady=10,
                          command=self._confirm)
        apply.pack(side="right")
        apply.bind("<Enter>", lambda e: apply.config(bg=ACCENT_H))
        apply.bind("<Leave>", lambda e: apply.config(bg=ACCENT))

    def _add_row(self, font_name: str, add_sep: bool):
        row = tk.Frame(self._inner, bg=CARD, height=self._ROW_H)
        row.pack(fill="x")
        row.pack_propagate(False)

        content = tk.Frame(row, bg=CARD)
        content.pack(fill="both", expand=True, padx=self._PAD)

        # Left: name in its own typeface
        left = tk.Frame(content, bg=CARD, width=self._LEFT_W)
        left.pack(side="left", fill="y")
        left.pack_propagate(False)
        tk.Label(left, text=font_name, font=_try_font(font_name, 15),
                 fg=TEXT, bg=CARD, anchor="w").pack(side="left", fill="y")

        # Right: autocomplete entry
        right = tk.Frame(content, bg=CARD)
        right.pack(side="right", fill="y", expand=True)

        # Pre-fill with saved replacement if one exists, otherwise default to Arial
        saved_val = self._saved.get(font_name, "Arial")
        entry = AutocompleteEntry(right, self._font_list, initial=saved_val, width=26)
        entry.pack(side="right", anchor="center",
                   pady=(self._ROW_H - 36) // 2)
        self._entries[font_name] = entry

        if add_sep:
            tk.Frame(self._inner, bg=SEP, height=1).pack(fill="x")

    # ── Replace all ───────────────────────────────────────────────────────────

    def _apply_all(self):
        val = _resolve_font_name(self._all_entry.get())
        if not val:
            return
        self._all_entry.set(val)          # show resolved name in the "all" field
        for entry in self._entries.values():
            entry.set(val)
            entry._close_dropdown()

    # ── Confirm / Cancel ──────────────────────────────────────────────────────

    def _confirm(self):
        self.result = {
            font: _resolve_font_name(entry.get())
            for font, entry in self._entries.items()
        }
        if self._save_var.get():
            set_font_replacements(self.result)
        self.destroy()

    def _cancel(self):
        self.result = None
        self.destroy()

    # ── Center ────────────────────────────────────────────────────────────────

    def _center(self, parent: tk.Tk):
        self.update_idletasks()
        w, h = self._W, self.winfo_reqheight()
        px = parent.winfo_rootx() + parent.winfo_width()  // 2
        py = parent.winfo_rooty() + parent.winfo_height() // 2
        self.geometry(f"{w}x{h}+{px - w//2}+{py - h//2}")
