# Speech-to-text evaluation (2026-10-10)

Why: the owner's first real recording (a 27-minute group Bible study, phone in the room) produced a transcript
full of mishearings, and every downstream feature (sermon notes, key phrases, search) inherits those errors.

## What the field uses

- **Granola, Otter**: cloud recognizers (Deepgram, AssemblyAI). Off the table: SOWER never uploads recordings.
- **MacWhisper, Aiko, Whisper Transcription**: OpenAI Whisper run locally (whisper.cpp or WhisperKit).
- **VoiceInk, Spokenly, Slipbox, Paraspeech**: NVIDIA Parakeet TDT run locally through FluidAudio (Core ML on the
  Neural Engine), often with Silero VAD and pyannote-based speaker diarization.
- **Apple Voice Memos / SOWER today**: Apple `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26).

## Method

Word error rate with a Whisper-style English normalizer (case, punctuation, fillers, numbers, contractions).
All engines on the same Mac (M1 Pro), the Apple engine configured exactly as `SpeechAnalyzerAdapter`.

- **AMI SDM** (`edinburghcstr/ami`, single distant microphone): far-field, multi-speaker meetings — the closest public
  proxy for a phone recording a room. 50 utterances of 3–20 s (4.6 min, 809 words).
- **LibriSpeech test-other**: harder read speech. 50 utterances (6.7 min, 1,150 words).
- **Long-form**: each set joined into one continuous file (4.6 and 6.7 minutes), to exercise chunking seams the way a
  30-minute sermon does.

Harness and data live in `build/asr-lab/` (ignored): `apple_stt.swift`, `run_parakeet.sh`, `run_whisper.sh`, `wer.py`.

## Results (WER, lower is better)

| Engine | AMI clips | LibriSpeech clips | AMI long-form | LibriSpeech long-form |
|---|---|---|---|---|
| Apple SpeechTranscriber (current) | 24.6 % | 4.0 % | 28.6 % | 4.7 % |
| Whisper large-v3-turbo (WhisperKit) | 23.7 % | 3.2 % | 23.6 % | 4.3 % |
| Parakeet TDT v3 | 16.8 % | 4.1 % | — | — |
| Parakeet TDT v2 (English only) | 15.1 % | **2.4 %** | 21.8 % | 3.6 % |
| **Parakeet Ultra** (25 languages) | **15.1 %** | 3.7 % | **18.3 %** | **3.5 %** |

Parakeet Ultra cuts long-form errors by 36 % (far-field) and 26 % (read speech) relative to the current Apple setup and
beats Whisper large-v3-turbo, the engine behind the local Whisper apps. Speed: about 0.1 s per clip on the Mac; FluidAudio
reports ~140× real time for Ultra on Apple silicon.

## Things that did not help

- **Speech enhancement before ASR** (FluidAudio LocalVQE noise suppression + dereverberation): Parakeet 18.3 → 27.3 %,
  Apple 28.6 → 33.6 %. Recognizers are trained on noisy audio; enhancement artifacts hurt. Always transcribe the
  original recording, never the Voice Focus copy.
- **Generic vocabulary boosting** (CTC keyword rescoring with a sermon word list): with 109 Bible names it replaced
  ordinary words ("power" → "Peter", "like" → "Luke", "money" → "Moses"): 3.5 → 8.0 %. With only 39 long distinctive
  terms and the conservative thresholds: 3.5 → 4.4 % and 18.3 → 19.7 %. Off by default.
- **Apple contextual strings** with the same list: no change on AMI (24.6 → 24.6 %); harmless, so per-sermon names may
  be passed to the Apple fallback.

## Also found

- `SpeechAnalyzerAdapter` drops earlier final results whose time range overlaps a later one
  (`accumulated.removeAll { overlap }`), which can silently delete stretches of words.
- Offline speaker diarization (FluidAudio, pyannote segmentation + WeSpeaker + VBx) processed 4.6 minutes in about
  4 seconds and separated 5 speakers — useful for studies with questions from the room.

## On the owner's iPhone 17 Pro (iOS 27.0), 2026-10-10

A private 27-minute recording (a group Bible study recorded from the room), both engines via
`-SermonSetCompareTranscripts latest`:

| Engine | Time | Words | Peak memory | Speakers |
|---|---|---|---|---|
| Apple SpeechTranscriber | 14.9 s | 4,148 | 371 MB | — |
| Parakeet Ultra + diarization | 59.6 s (27× real time) | 4,421 | 1.04 GB | main voice + room |

Parakeet's encoder and decoder run on the Neural Engine (preprocessor on CPU). Its phone transcript matches the Mac run
on 99.2 % of words. Reviewed side by side, it corrected the passages Apple garbled worst on this recording: a misheard
phrase that turned "lesson" into nonsense, a participant's name heard as a different name with the wrong verb, and an
opening sentence Apple rendered as unrelated words. Apple's transcript was 6 % shorter, consistent with dropped words.
(The recording is private; no transcript text is kept in the repository.)

The first device load failed ("models could not be loaded"); the loader now records per-model diagnostics and falls
back Neural Engine → GPU → CPU per component, and loaded on the Neural Engine on the next run. Model download moved from
one-at-a-time background transfers (8–18 minutes between files) to four parallel foreground transfers: 654 MB in 11 s
on the Mac's connection in the Simulator.
