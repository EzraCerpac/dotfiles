---
name: audio-diarization
description: Transcribe audio or video files with ElevenLabs Scribe v2 diarization, producing speaker-labeled JSON and Markdown meeting notes. Use when the user asks for transcription, diarization, speaker labels, meeting notes from audio, interview transcripts, or action items from recordings.
---

# ElevenLabs Audio Diarization Skill

Use this skill when the task involves transcribing an audio/video recording and identifying who spoke when.

## Default approach

1. Locate the input recording. ElevenLabs supports major audio and video formats.
2. Use ElevenLabs Scribe v2 with `model_id="scribe_v2"`.
3. Set `diarize=true` and `timestamps_granularity="word"` so words include `speaker_id`.
4. Before transcribing, collect likely keyterms from the user prompt, filename, nearby meeting notes, provided speaker hints, and project context. Use keyterms for exact spelling bias: technical terms, acronyms, solver names, people, institutions, project names, and rare words.
5. Pass short keyterm lists with repeated `--keyterm` flags. Use `--keyterms-file` for longer or reusable glossaries.
6. Use language hints and speaker-count hints when helpful for meeting audio.

## Commands

From the skill directory:

```bash
uv run scripts/transcribe_diarize.py path/to/recording.m4a
```

From anywhere:

```bash
uv run ~/.codex/skills/audio-diarization/scripts/transcribe_diarize.py path/to/recording.m4a
```

With language hints:

```bash
uv run ~/.codex/skills/audio-diarization/scripts/transcribe_diarize.py meeting.m4a --language en
uv run ~/.codex/skills/audio-diarization/scripts/transcribe_diarize.py meeting.m4a --language nl
```

With keyterms and likely speaker names:

```bash
uv run ~/.codex/skills/audio-diarization/scripts/transcribe_diarize.py meeting.m4a \
  --keyterm "Anderson acceleration" \
  --keyterm "pseudo-transient continuation" \
  --speaker-hints "Ezra, Alexander, Sandra, Peter"
```

With a reusable glossary:

```bash
uv run ~/.codex/skills/audio-diarization/scripts/transcribe_diarize.py meeting.m4a \
  --keyterms-file thesis-keyterms.txt \
  --speaker-hints "Ezra, Alexander, Sandra, Peter"
```

Good thesis/research keyterms include:

## Keyterm rules

- Infer keyterms from available context before running transcription. Ask only when important domain vocabulary cannot be inferred.
- Do not invent private names or affiliations. If spelling is uncertain, leave the person as a speaker hint instead of a keyterm.
- Use keyterms to bias exact words and spellings, not to assign speaker identities after the fact.
- Keep terms short and literal. Prefer `Anderson acceleration` over a long explanatory phrase.

## Environment

Requires:

```bash
export ELEVENLABS_API_KEY="..."
```

## Output convention

For an input file `meeting.m4a`, write outputs next to the input by default: `meeting.diarized.md`

## Quality checks

Before claiming the transcript is complete, check that:

- the output has a top-level transcript text;
- the output has `words` with `speaker_id`, `start`, `end`, and `text` fields;
- the normalized output has `segments` with `speaker`, `start`, `end`, and `text` fields;
- the Markdown transcript contains all non-empty segments;
- expected keyterms appear with correct spelling where they are audibly present;
- the language hint was correct, if one was provided.

If important terms are missed or misspelled, rerun with a stronger or more complete keyterm list before writing final notes.

Diarization is probabilistic. Mention when speaker attribution is uncertain, especially with overlapping speech, poor microphone quality, short interjections, or more than four speakers.
