#!/usr/bin/env python3
"""Cuts the SermonSet trailer from the filmed tour.

  tools/trailer/edit.py            # build/trailer/SermonSet-trailer.mp4 + docs/media/teaser.gif

Inputs: tools/trailer/edl.json, the CFR master from record.sh (converted with
`ffmpeg -i raw.mov -vf fps=30 cfr.mp4`), plates from cards.swift in build/trailer/cards,
and the sample narration in the core package. Narration lines are sample sermons whose
timings come from samples.json, so in-app playback and the soundtrack line up.
"""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDL = json.loads((ROOT / "tools/trailer/edl.json").read_text())
OUT = ROOT / "build/trailer"
CARDS = OUT / "cards"
SAMPLES = ROOT / "Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples"
FPS, XF = EDL["fps"], EDL["xfade"]
P = EDL["phone"]


def run(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *map(str, args)], check=True)


def scene_clip(scene, path):
    if "card" in scene:
        run(["-loop", 1, "-t", scene["duration"], "-i", CARDS / scene["card"],
             "-vf", f"fps={FPS},format=yuv420p", "-c:v", "libx264", "-crf", 16, path])
        return scene["duration"]
    duration = (scene["out"] - scene["in"]) / scene["speed"]
    graph = (
        f"[0:v]trim={scene['in']}:{scene['out']},setpts=(PTS-STARTPTS)/{scene['speed']},fps={FPS},"
        f"scale={P['width']}:{P['height']}:flags=lanczos,format=rgba[phone];"
        f"[2:v]format=gray,scale={P['width']}:{P['height']}[mask];"
        f"[phone][mask]alphamerge[masked];"
        f"[1:v][masked]overlay={P['x']}:{P['y']}:shortest=1,format=yuv420p[v]"
    )
    run(["-i", ROOT / EDL["source"], "-loop", 1, "-t", duration, "-i", CARDS / f"plate-{scene['name']}.png",
         "-loop", 1, "-t", duration, "-i", CARDS / "mask.png",
         "-filter_complex", graph, "-map", "[v]", "-t", duration, "-c:v", "libx264", "-crf", 16, path])
    return duration


def main():
    clips, starts, t = [], {}, 0.0
    for i, scene in enumerate(EDL["scenes"]):
        path = OUT / f"scene-{i:02d}-{scene['name']}.mp4"
        d = scene_clip(scene, path)
        starts[scene["name"]] = t
        clips.append((path, d))
        t += d - XF
        print(f"{scene['name']:10s} start {starts[scene['name']]:6.2f}  length {d:5.2f}")
    total = t + XF

    # Video: crossfade every clip into the next.
    inputs, chain, offset = [], "", 0.0
    for path, _ in clips:
        inputs += ["-i", path]
    # xfade needs every input on the same timebase and frame rate.
    for i in range(len(clips)):
        chain += f"[{i}:v]settb=AVTB,fps={FPS},format=yuv420p[n{i}];"
    last = "[n0]"
    for i in range(1, len(clips)):
        offset += clips[i - 1][1] - XF
        out = f"[x{i}]"
        chain += f"{last}[n{i}]xfade=transition=fade:duration={XF}:offset={offset:.3f}{out};"
        last = out

    # Audio: each narration line placed at its scene's start plus an offset.
    a_inputs, a_chain, labels = [], "", []
    for j, line in enumerate(EDL["narration"]):
        at = starts[line["scene"]] + line["offset"]
        length = line["out"] - line["in"]
        idx = len(clips) + j
        a_inputs += ["-i", SAMPLES / line["file"]]
        a_chain += (f"[{idx}:a]atrim={line['in']}:{line['out']},asetpts=PTS-STARTPTS,"
                    f"afade=t=in:d=0.05,afade=t=out:st={length - 0.2:.2f}:d=0.2,"
                    f"adelay={int(at * 1000)}|{int(at * 1000)},aformat=channel_layouts=stereo[a{j}];")
        labels.append(f"[a{j}]")
        print(f"narration {line['file']:28s} {at:6.2f} → {at + length:6.2f}")
    a_chain += (f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0,apad,atrim=0:{total:.3f},"
                f"loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st={total - 1.2:.2f}:d=1.2[aout]")

    final = OUT / "SermonSet-trailer.mp4"
    run([*inputs, *a_inputs, "-filter_complex", chain + a_chain, "-map", last, "-map", "[aout]",
         "-c:v", "libx264", "-preset", "slow", "-crf", 20, "-pix_fmt", "yuv420p", "-r", FPS,
         "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-movflags", "+faststart", "-t", f"{total:.3f}", final])
    print(f"wrote {final} ({total:.1f} s)")

    # Teaser GIF for the README: card tilt and flip, the pack reveal, and the looks switching.
    media = ROOT / "docs/media"
    media.mkdir(parents=True, exist_ok=True)
    picks = [(starts["card"] + 2.0, 4.2), (starts["pack"] + 3.0, 4.5), (starts["looks"] + 0.4, 3.2)]
    parts = "".join(f"[0:v]trim={a:.2f}:{a + d:.2f},setpts=PTS-STARTPTS[p{k}];" for k, (a, d) in enumerate(picks))
    graph = (parts + "".join(f"[p{k}]" for k in range(len(picks))) + f"concat=n={len(picks)}:v=1:a=0,"
             "fps=10,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[pal];"
             "[s1][pal]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle[g]")
    run(["-i", final, "-filter_complex", graph, "-map", "[g]", "-loop", 0, media / "teaser.gif"])
    print(f"wrote {media / 'teaser.gif'}")


if __name__ == "__main__":
    sys.exit(main())
