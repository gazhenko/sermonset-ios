#!/usr/bin/env python3
"""Renders the trailer's plates in the website's language, using site/assets/site.css itself.

  tools/trailer/plates.py      # → build/trailer/plates/*.png (1920×1080)

Plates are paper with the violet frame, or full violet panels with a dithered painting. Scenes with
footage leave a phone-shaped window on the right; edit.py drops the (one-ink) footage into it.
"""
import os, subprocess
from pathlib import Path
from html import escape

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/trailer/plates"
CSS = (ROOT / "site/assets/site.css").as_uri()
HS = Path.home() / "Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell"

# The phone window, shared with edit.py (edl.json "phone").
PX, PY, PW, PH = 1300, 40, 460, 1000

BASE = f"""<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="{CSS}"><style>
html,body{{margin:0;width:1920px;height:1080px;overflow:hidden}}
body::before{{border-width:8px}}
.plate{{position:relative;width:1920px;height:1080px;box-sizing:border-box}}
.copy{{position:absolute;left:150px;top:0;bottom:0;width:980px;display:grid;align-content:center;gap:30px}}
.copy .label{{font-size:24px}}
.copy .title{{font-size:150px;line-height:.93}}
.copy p.body{{font-size:34px;line-height:1.35;max-width:880px}}
.phone{{position:absolute;left:{PX - 5}px;top:{PY - 5}px;width:{PW + 10}px;height:{PH + 10}px;border:3px solid var(--ink);border-radius:69px;box-sizing:border-box}}
.panel-full{{position:absolute;inset:0;background:var(--panel);color:var(--on-panel);display:grid;align-content:center;justify-items:center;gap:30px;padding:0 120px}}
.panel-full .art{{width:1500px;max-height:600px;background:var(--on-panel)}}
.panel-full .word{{font-size:230px;line-height:.84;text-align:center}}
.center{{position:absolute;inset:0;display:grid;align-content:center;justify-items:center;text-align:center;gap:28px}}
.center .word{{font-size:520px;line-height:.8}}
.center .label{{font-size:26px}}
.center .tag{{font:300 74px/1 var(--display);text-transform:uppercase}}
.plate .field{{position:absolute;left:8px;right:8px;bottom:8px;width:auto;height:300px;aspect-ratio:auto;margin:0;-webkit-mask-size:cover;mask-size:cover;-webkit-mask-position:center 70%;mask-position:center 70%}}
</style></head><body>"""


def page(name, inner, panel=False):
    body_bg = ' style="background:var(--panel)"' if panel else ""
    html = BASE.replace("<body>", f"<body{body_bg}>") + f'<div class="plate">{inner}</div></body></html>'
    path = OUT / f"{name}.html"
    path.write_text(html)
    png = OUT / f"{name}.png"
    subprocess.run([str(HS), "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                    "--force-device-scale-factor=1", "--window-size=1920,1080", "--virtual-time-budget=4000",
                    f"--screenshot={png}", path.as_uri()], capture_output=True, check=True)
    print("wrote", png.relative_to(ROOT))


def plate(name, label, title, body):
    page(name, f'<div class="copy"><p class="label">{escape(label)}</p><h1 class="title">{escape(title)}</h1>'
               f'<p class="body">{escape(body)}</p></div><div class="phone"></div>')


def panel(name, art, word):
    page(name, f'<div class="panel-full"><div class="art {art}"></div><p class="word">{escape(word)}</p></div>', panel=True)


def mask():
    """White rounded phone window on black, for alphamerge."""
    path = OUT / "mask.html"
    path.write_text(f'<!doctype html><html><body style="margin:0;background:#000"><div style="width:{PW}px;height:{PH}px;'
                    f'border-radius:64px;background:#fff"></div></body></html>')
    subprocess.run([str(HS), "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={PW},{PH}", f"--screenshot={OUT / 'mask.png'}", path.as_uri()], capture_output=True, check=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    mask()
    page("blank", "")
    page("title", '<div class="center"><p class="label">Free · Private · For iPhone</p><p class="word">SOWER</p></div>')
    panel("panel-hear", "art-millet-sower", "Hear it. Keep it. Pass it on.")
    plate("record", "Hear it", "Record from the pew", "One button to record. Another to mark the moment it lands.")
    plate("play", "Hear it", "Your moments, on the timeline", "Listen back and jump straight to the part that mattered.")
    plate("takeaways", "Keep it", "Takeaways from the words actually said", "Drafted on your iPhone. Each one plays the passage it came from.")
    panel("panel-pass", "art-vangogh-sower", "Pass it on.")
    plate("card", "Pass it on", "Every sermon becomes a card", "Tilt it, turn it over, listen. It points back to the message.")
    plate("discover", "Pass it on", "Keep sermons other churches shared", "Free to keep. Audio only with the church’s permission.")
    page("trade-word", '<div class="center"><p class="label">Keep the message</p><p class="word" style="font-size:300px">Trade the card</p></div>')
    plate("trade", "Keep the message", "Give or swap by QR, nearby, or link", "The card moves. The sermon stays in both libraries. Your notes never travel.")
    plate("pack", "Every Sunday", "A free Sunday Pack", "Five sermons from other churches. No purchases, no odds.")
    plate("atlas", "Places, not people", "See where the messages were preached", "City-level pins, never where you were.")
    plate("looks", "Five looks, one app", "Pick the one that feels like yours", "SOWER’s own one-ink look, plus Riso, Rubric, Vespers, and Lumen.")
    page("end", '<div class="center" style="bottom:240px"><p class="label">Free · Private · For iPhone</p><p class="word" style="font-size:380px">SOWER</p>'
                '<p class="tag">Hear it. Keep it. Pass it on.</p><p class="label">gazhenko.dev/sower</p></div>'
                '<div class="art field art-wheatfield"></div>')


if __name__ == "__main__":
    main()
