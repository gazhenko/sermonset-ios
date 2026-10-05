#!/usr/bin/env python3
"""Build fictional sample audio and exact transcript timings, entirely offline.

Uses the existing Kokoro environment read-only. No package or model installation.
Falls back to the installed Samantha voice. Intermediates stay under build/.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
VENV_PYTHON = Path.home() / 'Documents/GitHub/redwall/Tools/voice/.venv/bin/python'
OFFLINE = dict(os.environ, HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1', PYTHONDONTWRITEBYTECODE='1', TOKENIZERS_PARALLELISM='false', OMP_NUM_THREADS='2', MPLCONFIGDIR=str(ROOT / 'build/samples/matplotlib'))


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, env=OFFLINE, **kwargs)


def validate(doc):
    slugs = set()
    for sermon in doc['sermons']:
        slug = sermon['slug']
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', slug) or slug in slugs:
            raise ValueError(f'Invalid or duplicate slug: {slug}')
        slugs.add(slug)
        segments = sermon['segments']
        if not segments or any(not isinstance(s, str) or not s.strip() for s in segments):
            raise ValueError(f'{slug}: empty narration segment')
        indexes = list(sermon.get('lowConfidenceSegments', []))
        indexes += [o['segment'] for o in sermon.get('outline', [])]
        indexes += [m['segment'] for m in sermon.get('sampleMoments', [])]
        indexes += [i for t in sermon.get('takeaways', []) for i in t['segments']]
        if any(not isinstance(i, int) or not 0 <= i < len(segments) for i in indexes):
            raise ValueError(f'{slug}: invalid evidence index')


def kokoro_worker(source, work):
    import numpy as np
    import soundfile as sf
    import torch
    from kokoro import KPipeline
    torch.set_num_threads(2)
    pipeline = KPipeline(lang_code='a', repo_id='hexgrad/Kokoro-82M', device='cpu')
    doc = json.loads(source.read_text())
    for sermon in doc['sermons']:
        slug = sermon['slug']
        voice = sermon.get('voice', 'am_michael')
        for i, text in enumerate(sermon['segments']):
            path = work / slug / f'{i:03d}-tts.wav'
            if path.exists():
                continue
            chunks = [result.audio.detach().cpu().numpy() for result in pipeline(text, voice=voice) if result.audio is not None]
            if not chunks:
                raise ValueError(f'{slug}:{i}: Kokoro produced no audio')
            sf.write(path, np.concatenate(chunks), 24000, subtype='PCM_16')
        print(f'Kokoro narration: {slug}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'Fixtures/sample-sermons.source.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples')
    parser.add_argument('--say', action='store_true', help='Use the installed macOS Samantha voice')
    parser.add_argument('--kokoro-worker', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--work', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.kokoro_worker:
        kokoro_worker(args.source, args.work)
        return
    source = args.source.resolve()
    doc = json.loads(source.read_text())
    validate(doc)
    if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
        raise RuntimeError('The existing ffmpeg and ffprobe executables are required.')
    digest = hashlib.sha256(source.read_bytes()).hexdigest()[:16]
    work = ROOT / 'build/samples' / digest
    work.mkdir(parents=True, exist_ok=True)
    for sermon in doc['sermons']:
        (work / sermon['slug']).mkdir(exist_ok=True)
    kokoro = not args.say and VENV_PYTHON.exists()
    if kokoro:
        try:
            run([VENV_PYTHON, '-B', __file__, '--kokoro-worker', '--source', source, '--work', work])
        except subprocess.CalledProcessError:
            print('Cached Kokoro assets unavailable; using installed Samantha voice.', file=sys.stderr)
            kokoro = False
    args.output.mkdir(parents=True, exist_ok=True)
    output = {'sermons': [], 'schemaVersion': 1, 'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(), 'narrator': 'Kokoro' if kokoro else 'macOS Samantha'}
    for sermon in doc['sermons']:
        fixture = copy.deepcopy(sermon)
        slug = sermon['slug']
        combined = work / slug / 'combined.wav'
        timing = []
        total_frames = 0
        with wave.open(str(combined), 'wb') as writer:
            writer.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
            for i, text in enumerate(sermon['segments']):
                wav = work / slug / f'{i:03d}.wav'
                raw = work / slug / f'{i:03d}-tts.wav'
                if not kokoro:
                    raw = work / slug / f'{i:03d}-say.aiff'
                    run(['say', '-v', 'Samantha', '-r', '100', '-o', raw, text])
                run(['ffmpeg', '-v', 'error', '-y', '-i', raw, '-ar', '48000', '-ac', '1', '-c:a', 'pcm_s16le', wav])
                with wave.open(str(wav), 'rb') as reader:
                    frames = reader.getnframes()
                    writer.writeframes(reader.readframes(frames))
                start, end = total_frames / 48000, (total_frames + frames) / 48000
                timing.append({'start': start, 'end': end, 'text': text, 'confidence': 0.48 if i in sermon.get('lowConfidenceSegments', []) else 0.98})
                total_frames += frames
        audio = args.output / f'{slug}.m4a'
        temporary = work / slug / f'{slug}.m4a'
        run(['ffmpeg', '-v', 'error', '-y', '-i', combined, '-ar', '48000', '-ac', '1', '-c:a', 'aac', '-b:a', '64k', '-movflags', '+faststart', temporary])
        probe = json.loads(run(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', temporary], capture_output=True, text=True).stdout)
        stream = probe['streams'][0]
        if stream['codec_name'] != 'aac' or stream['channels'] != 1 or stream['sample_rate'] != '48000':
            raise ValueError(f'{slug}: unexpected encoding')
        duration = float(probe['format']['duration'])
        if abs(duration - total_frames / 48000) > 0.05:
            raise ValueError(f'{slug}: transcript timing drift')
        shutil.copyfile(temporary, audio)
        fixture.update(segments=timing, duration=duration, byteCount=audio.stat().st_size, checksumSHA256=hashlib.sha256(audio.read_bytes()).hexdigest(), audioFile=audio.name)
        output['sermons'].append(fixture)
        print(f'{slug}: {duration:.2f}s, {audio.stat().st_size:,} bytes, {len(timing)} timed segments', flush=True)
    metadata = args.output / 'samples.json'
    temporary = work / 'samples.json'
    temporary.write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n')
    shutil.copyfile(temporary, metadata)
    print(f'Wrote {len(output["sermons"])} samples to {args.output}', flush=True)


if __name__ == '__main__':
    main()
