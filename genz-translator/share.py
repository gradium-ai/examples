"""Downloadable share cards for the GenZ transcript - no database.

The two transcript lines are passed as query params to /card.png, which renders
a branded 1200x630 PNG on the fly (Pillow). The page offers it as a download so
people can attach it to a post on X, LinkedIn, etc. The card is self-branded
with the Gradium wordmark and the app link, so the image stands on its own once
it leaves the app - nothing to scrape, no link preview to rely on.
"""

import functools
import os
import pathlib
import re
from io import BytesIO

from PIL import Image, ImageDraw, ImageFont

_HERE = pathlib.Path(__file__).parent
_FONTS = _HERE / "static" / "fonts"
_ASSETS = _HERE / "static" / "assets"

# Card canvas - 1200x630 (1.91:1) renders cleanly in-feed on X and LinkedIn.
W, H = 1200, 630
PAD = 70

BG = (11, 11, 16)       # --bg   #0b0b10
INK = (242, 242, 239)   # --ink  #f2f2ef
ACID = (200, 255, 46)   # --acid #c8ff2e
PINK = (255, 46, 196)   # --pink #ff2ec4
DIM = (111, 111, 125)   # --dim  #6f6f7d
CARD = (20, 20, 28)     # --card #14141c
LOGO_COLOR = (210, 210, 216)  # lifted gray so the wordmark reads on dark

# The link stamped on the share card (a downloaded image may be posted
# anywhere). Set PUBLIC_APP_URL to point it at your own deployment.
APP_LINK = os.environ.get("PUBLIC_APP_URL", "gradium.ai")

# Keep each line short enough that the card doesn't turn into a wall of text.
MAX_CHARS = 600

# Strip emoji / pictographs / control chars: the bundled fonts have no color
# glyphs, so these would render as tofu on the card.
_STRIP = re.compile(
    "[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF"
    "\U0000FE00-\U0000FE0F\U00002190-\U000021FF\U00002300-\U000023FF"
    "\U00000000-\U00000008\U0000000B-\U0000001F]"
)


def clean(text: str) -> str:
    """Normalize user text for the rendered card."""
    text = _STRIP.sub("", text or "")
    text = " ".join(text.split())  # collapse whitespace/newlines
    return text[:MAX_CHARS].strip()


@functools.lru_cache(maxsize=32)
def _font(name: str, size: int, weight: str | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(_FONTS / name), size)
    if weight:  # Unbounded is a variable font; pin a named instance
        f.set_variation_by_name(weight)
    return f


@functools.lru_cache(maxsize=8)
def _logo(height: int) -> Image.Image:
    """The Gradium wordmark, recolored to LOGO_COLOR, scaled to `height`."""
    im = Image.open(_ASSETS / "gradium-logo.png").convert("RGBA")
    w, h = im.size
    im = im.resize((round(w * height / h), height), Image.LANCZOS)
    # paint a flat color through the wordmark's alpha (keeps anti-aliased edges)
    tinted = Image.new("RGBA", im.size, LOGO_COLOR + (0,))
    tinted.putalpha(im.getchannel("A"))
    return tinted


_MEASURE = ImageDraw.Draw(Image.new("RGB", (1, 1)))


def _wrap(text: str, font: ImageFont.FreeTypeFont, max_w: int, max_lines: int) -> list[str]:
    """Greedy word-wrap to `max_w`, clamped to `max_lines` with an ellipsis."""
    words = text.split(" ")
    lines: list[str] = []
    cur = ""
    for word in words:
        trial = f"{cur} {word}".strip()
        if _MEASURE.textlength(trial, font=font) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
        if len(lines) == max_lines:
            break
    else:
        if cur:
            lines.append(cur)

    if len(lines) >= max_lines:
        lines = lines[:max_lines]
        last = lines[-1]
        while last and _MEASURE.textlength(last + " …", font=font) > max_w:
            last = last.rsplit(" ", 1)[0] if " " in last else last[:-1]
        lines[-1] = (last + " …").strip()
    return lines


def _draw_block(
    draw: ImageDraw.ImageDraw,
    label: str,
    label_color: tuple,
    text: str,
    text_font: ImageFont.FreeTypeFont,
    text_color: tuple,
    top: int,
    line_h: int,
    max_lines: int,
) -> int:
    """Draw a labelled text block; return the y just below it."""
    lbl_font = _font("IBMPlexMono-Medium.ttf", 24)
    draw.text((PAD, top), label, font=lbl_font, fill=label_color)
    y = top + 42
    for line in _wrap(text, text_font, W - 2 * PAD, max_lines):
        draw.text((PAD, y), line, font=text_font, fill=text_color)
        y += line_h
    return y


def render_card(said: str, genz: str) -> bytes:
    """Render the branded 1200x630 share card as PNG bytes."""
    said = clean(said) or "…"
    genz = clean(genz) or "…"

    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # inner panel + accent frame
    d.rounded_rectangle((24, 24, W - 24, H - 24), radius=28, fill=CARD)
    d.rounded_rectangle((24, 24, W - 24, H - 24), radius=28, outline=(35, 35, 46), width=2)

    # header: GEN(acid) Z(pink tile) TRANSLATOR(ink)
    hf = _font("Unbounded.ttf", 40, "Black")
    x = PAD
    d.text((x, 50), "GEN", font=hf, fill=ACID)
    x += d.textlength("GEN", font=hf)
    zw = d.textlength("Z", font=hf)
    d.rounded_rectangle((x - 4, 46, x + zw + 10, 46 + 56), radius=6, fill=PINK)
    d.text((x + 3, 50), "Z", font=hf, fill=BG)
    x += zw + 18
    d.text((x, 50), "TRANSLATOR", font=hf, fill=INK)
    d.line((PAD, 128, W - PAD, 128), fill=(35, 35, 46), width=2)

    # what I said - plain speech in mono
    said_font = _font("IBMPlexMono-Regular.ttf", 30)
    _draw_block(d, "WHAT I SAID", DIM, said, said_font, INK, 150, 42, 3)

    # divider
    d.line((PAD, 336, W - PAD, 336), fill=(35, 35, 46), width=2)

    # what genz hears - the punchline, big + acid
    genz_font = _font("Unbounded.ttf", 36, "Bold")
    _draw_block(d, "WHAT GENZ HEARS", ACID, genz, genz_font, ACID, 356, 46, 3)

    # footer: Gradium wordmark (left) + app link (right)
    logo = _logo(30)
    logo_y = H - 68
    img.paste(logo, (PAD, logo_y), logo)
    link_font = _font("IBMPlexMono-Regular.ttf", 24)
    link_w = d.textlength(APP_LINK, font=link_font)
    d.text((W - PAD - link_w, logo_y + 3), APP_LINK, font=link_font, fill=DIM)

    out = BytesIO()
    img.save(out, format="PNG")
    return out.getvalue()
