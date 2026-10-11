#!/usr/bin/env python3
"""Cuts the SOWER trailer in the website's language: paper and one violet ink, no voiceover.

  tools/trailer/plates.py && tools/trailer/edit.py   # → build/trailer/Sower-trailer.mp4 + docs/media/teaser.gif

Footage comes from the CFR master made by record.sh, filmed in the app's SOWER look, which is
already one ink. Scenes in other looks or with maps are printed in one ink with an ordered (Bayer)
dither, which stays still from frame to frame; "color": true passes footage through untouched. Cut points live in tools/trailer/edl.json; read them off a contact sheet of cfr.mp4.
Scenes: a still plate ("duration", optional "zoom"), or footage ("in"/"out" or "segments", "speed",
optional "hold" seconds on the last frame, optional "color"). "transition" names the xfade into it.
The trailer is silent by design.
"""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDL = json.loads((ROOT / "tools/trailer/edl.json").read_text())
OUT = ROOT / "build/trailer"
PLATES = OUT / "plates"
FPS, XF = EDL["fps"], EDL["xfade"]
P = EDL["phone"]
INK, PAPER = EDL["ink"], EDL["paper"]


def run(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *map(str, args)], check=True)


def rgb(hexcolor):
    h = hexcolor.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def palette():
    path = OUT / "bw-palette.png"
    run(["-f", "lavfi", "-i", "color=c=black:s=16x8", "-f", "lavfi", "-i", "color=c=white:s=16x8",
         "-filter_complex", "[0][1]vstack", "-frames:v", 1, path])
    return path


def still(scene, path):
    d = scene["duration"]
    frames = int(round(d * FPS))
    if scene.get("zoom"):
        vf = (f"scale=2112:1188,zoompan=z='1+0.035*on/{frames}':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
              f":d={frames}:s=1920x1080:fps={FPS},format=yuv420p")
        run(["-i", PLATES / f"{scene['plate']}.png", "-vf", vf, "-frames:v", frames, "-c:v", "libx264", "-crf", 16, path])
    else:
        run(["-loop", 1, "-t", d, "-i", PLATES / f"{scene['plate']}.png",
             "-vf", f"fps={FPS},format=yuv420p", "-c:v", "libx264", "-crf", 16, path])
    return d


def footage(scene, path, pal):
    segments = scene.get("segments") or [[scene["in"], scene["out"]]]
    hold = scene.get("hold", 0)
    d = sum(b - a for a, b in segments) / scene["speed"] + hold
    parts = "".join(f"[0:v]trim={a}:{b},setpts=PTS-STARTPTS[g{k}];" for k, (a, b) in enumerate(segments))
    joined = "".join(f"[g{k}]" for k in range(len(segments))) + f"concat=n={len(segments)}:v=1:a=0[cut];"
    freeze = f",tpad=stop_mode=clone:stop_duration={hold}" if hold else ""
    phone = f"[cut]setpts=PTS/{scene['speed']},fps={FPS}{freeze},scale={P['width']}:{P['height']}:flags=lanczos"
    if scene.get("color"):
        phone += ",format=rgba[phone];"
    else:
        (ir, ig, ib), (pr, pg, pb) = rgb(INK), rgb(PAPER)
        phone += (",format=gray,eq=contrast=1.35:brightness=0.03,format=rgb24[g];"
                  "[g][3:v]paletteuse=dither=bayer:bayer_scale=2[bw];"
                  f"[bw]lutrgb=r='if(lt(val,128),{ir},{pr})':g='if(lt(val,128),{ig},{pg})':b='if(lt(val,128),{ib},{pb})',"
                  "format=rgba[phone];")
    graph = (parts + joined + phone +
             f"[2:v]format=gray,scale={P['width']}:{P['height']}[mask];[phone][mask]alphamerge[masked];"
             f"[1:v][masked]overlay={P['x']}:{P['y']}:shortest=1,format=yuv420p[v]")
    run(["-i", ROOT / EDL["source"], "-loop", 1, "-t", d, "-i", PLATES / f"{scene['plate']}.png",
         "-loop", 1, "-t", d, "-i", PLATES / "mask.png", "-i", pal,
         "-filter_complex", graph, "-map", "[v]", "-t", d, "-r", FPS, "-c:v", "libx264", "-crf", 16, path])
    return d


def main():
    pal = palette()
    clips, starts, t = [], {}, 0.0
    for i, scene in enumerate(EDL["scenes"]):
        path = OUT / f"cut-{i:02d}-{scene['name']}.mp4"
        d = still(scene, path) if "duration" in scene else footage(scene, path, pal)
        starts[scene["name"]] = t
        clips.append((path, d, scene.get("transition", "fade")))
        t += d - XF
        print(f"{scene['name']:12s} start {starts[scene['name']]:6.2f}  length {d:5.2f}")
    total = t + XF

    inputs, chain, offset = [], "", 0.0
    for path, _, _ in clips:
        inputs += ["-i", path]
    for i in range(len(clips)):
        chain += f"[{i}:v]settb=AVTB,fps={FPS},format=yuv420p[n{i}];"
    last = "[n0]"
    for i in range(1, len(clips)):
        offset += clips[i - 1][1] - XF
        chain += f"{last}[n{i}]xfade=transition={clips[i][2]}:duration={XF}:offset={offset:.3f}[x{i}];"
        last = f"[x{i}]"
    chain = chain.rstrip(";")

    final = OUT / "Sower-trailer.mp4"
    run([*inputs, "-filter_complex", chain, "-map", last, "-an",
         "-c:v", "libx264", "-preset", "slow", "-crf", 20, "-pix_fmt", "yuv420p", "-r", FPS,
         "-movflags", "+faststart", "-t", f"{total:.3f}", final])
    print(f"wrote {final} ({total:.1f} s, silent)")

    media = ROOT / "docs/media"
    media.mkdir(parents=True, exist_ok=True)
    picks = [(starts["title"] - 0.2, 2.6), (starts["card"] + 1.5, 3.2), (starts["trade"] + 4.0, 3.0), (starts["looks"] + 1.0, 3.2)]
    parts = "".join(f"[0:v]trim={a:.2f}:{a + d:.2f},setpts=PTS-STARTPTS[p{k}];" for k, (a, d) in enumerate(picks))
    graph = (parts + "".join(f"[p{k}]" for k in range(len(picks))) + f"concat=n={len(picks)}:v=1:a=0,"
             "fps=10,scale=760:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64:stats_mode=diff[pal];"
             "[s1][pal]paletteuse=dither=none:diff_mode=rectangle[g]")
    run(["-i", final, "-filter_complex", graph, "-map", "[g]", "-loop", 0, media / "teaser.gif"])
    print(f"wrote {media / 'teaser.gif'}")


if __name__ == "__main__":
    sys.exit(main())
