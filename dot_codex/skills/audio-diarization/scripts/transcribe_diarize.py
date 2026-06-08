#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests>=2.32.0",
# ]
# ///
"""Transcribe an audio/video file with ElevenLabs Scribe v2 diarization.

Writes two files by default:
  <input-stem>.diarized.json
  <input-stem>.diarized.md

Example:
  uv run transcribe_diarize.py meeting.m4a --language en
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

import requests


ELEVENLABS_STT_URL = "https://api.elevenlabs.io/v1/speech-to-text"


def fmt_time(seconds: Any) -> str:
    try:
        total_ms = int(round(float(seconds) * 1000))
    except (TypeError, ValueError):
        return "??:??.???"
    ms = total_ms % 1000
    total_s = total_ms // 1000
    s = total_s % 60
    total_m = total_s // 60
    m = total_m % 60
    h = total_m // 60
    if h:
        return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"
    return f"{m:02d}:{s:02d}.{ms:03d}"


def load_keyterms(values: list[str], path: Path | None) -> list[str]:
    keyterms = [term.strip() for term in values if term.strip()]
    if path:
        for line in path.expanduser().read_text(encoding="utf-8").splitlines():
            term = line.strip()
            if term and not term.startswith("#"):
                keyterms.append(term)
    return keyterms


def truthy_form(value: bool) -> str:
    return "true" if value else "false"


def add_optional_form(data: dict[str, str], name: str, value: Any) -> None:
    if value is not None:
        data[name] = str(value)


def word_speaker(word: dict[str, Any]) -> str:
    return str(word.get("speaker_id") or word.get("speaker") or "Speaker ?")


def word_text(word: dict[str, Any]) -> str:
    return str(word.get("text") or word.get("word") or "").strip()


def group_words_into_segments(words: list[Any]) -> list[dict[str, Any]]:
    segments: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    for item in words:
        if not isinstance(item, dict):
            continue
        text = word_text(item)
        if not text:
            continue

        speaker = word_speaker(item)
        start = item.get("start")
        end = item.get("end")

        if current is None or current["speaker"] != speaker:
            current = {"speaker": speaker, "start": start, "end": end, "text": text}
            segments.append(current)
            continue

        current["end"] = end
        if text in {".", ",", "!", "?", ":", ";"}:
            current["text"] = f"{current['text']}{text}"
        else:
            current["text"] = f"{current['text']} {text}"

    return segments


def normalize_scribe_response(data: dict[str, Any]) -> dict[str, Any]:
    words = data.get("words") or []
    segments = group_words_into_segments(words if isinstance(words, list) else [])
    return {
        **data,
        "provider": "elevenlabs",
        "model": data.get("model_id", "scribe_v2"),
        "segments": segments,
    }


def diarized_markdown(data: dict[str, Any], source: Path, speaker_hints: str | None = None) -> str:
    lines: list[str] = []
    lines.append(f"# Diarized transcript: {source.name}")
    lines.append("")

    if speaker_hints:
        lines.append(f"Speaker-name hints provided by user: {speaker_hints}")
        lines.append("")

    full_text = str(data.get("text", "")).strip()
    if full_text:
        lines.append("## Full transcript")
        lines.append("")
        lines.append(full_text)
        lines.append("")

    segments = data.get("segments") or []
    lines.append("## Speaker segments")
    lines.append("")

    if not segments:
        lines.append("> No speaker segments were returned. Check that `diarize` was enabled.")
        lines.append("")
        return "\n".join(lines)

    for seg in segments:
        if not isinstance(seg, dict):
            continue
        speaker = seg.get("speaker", "Speaker ?")
        start = fmt_time(seg.get("start"))
        end = fmt_time(seg.get("end"))
        text = str(seg.get("text", "")).strip()
        if not text:
            continue
        lines.append(f"**{speaker}** [{start}–{end}]: {text}")
        lines.append("")

    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Transcribe audio with ElevenLabs Scribe v2 diarization.")
    parser.add_argument("input", type=Path, help="Audio/video file to transcribe")
    parser.add_argument("--model", default="scribe_v2", help="ElevenLabs transcription model")
    parser.add_argument("--language", default=None, help="Optional ISO-639-1 or ISO-639-3 language hint, e.g. en, eng, nl, nld")
    parser.add_argument("--speaker-hints", default=None, help="Optional human note used only in Markdown output")
    parser.add_argument("--num-speakers", type=int, default=None, help="Optional speaker count hint, 1-32")
    parser.add_argument("--diarization-threshold", type=float, default=None, help="Optional threshold, 0.1-0.4; only without --num-speakers")
    parser.add_argument("--keyterm", action="append", default=[], help="Bias transcription toward a term; repeatable")
    parser.add_argument("--keyterms-file", type=Path, default=None, help="One keyterm per line; # comments ignored")
    parser.add_argument("--no-audio-events", action="store_true", help="Disable tags like laughter or footsteps")
    parser.add_argument("--no-verbatim", action="store_true", help="Remove filler words, false starts, non-speech sounds")
    parser.add_argument("--temperature", type=float, default=None, help="Optional transcription temperature, 0-2")
    parser.add_argument("--seed", type=int, default=None, help="Optional best-effort deterministic seed")
    parser.add_argument("--outdir", type=Path, default=None, help="Output directory; default: input file directory")
    args = parser.parse_args()

    audio_path = args.input.expanduser().resolve()
    if not audio_path.exists():
        raise SystemExit(f"Input file not found: {audio_path}")
    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY is not set.")

    outdir = (args.outdir.expanduser().resolve() if args.outdir else audio_path.parent)
    outdir.mkdir(parents=True, exist_ok=True)

    json_path = outdir / f"{audio_path.stem}.diarized.json"
    md_path = outdir / f"{audio_path.stem}.diarized.md"

    request: dict[str, str] = {
        "model_id": args.model,
        "diarize": "true",
        "tag_audio_events": truthy_form(not args.no_audio_events),
        "timestamps_granularity": "word",
    }
    if args.language:
        request["language_code"] = args.language
    add_optional_form(request, "num_speakers", args.num_speakers)
    add_optional_form(request, "diarization_threshold", args.diarization_threshold)
    add_optional_form(request, "temperature", args.temperature)
    add_optional_form(request, "seed", args.seed)
    if args.no_verbatim:
        request["no_verbatim"] = "true"
    form_fields = list(request.items())
    form_fields.extend(("keyterms", keyterm) for keyterm in load_keyterms(args.keyterm, args.keyterms_file))

    with audio_path.open("rb") as audio_file:
        response = requests.post(
            ELEVENLABS_STT_URL,
            headers={"xi-api-key": api_key},
            data=form_fields,
            files={"file": (audio_path.name, audio_file, "application/octet-stream")},
        )

    try:
        response.raise_for_status()
    except requests.HTTPError as exc:
        raise SystemExit(f"ElevenLabs transcription failed: HTTP {response.status_code} {response.text}") from exc

    data = normalize_scribe_response(response.json())
    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    md_path.write_text(diarized_markdown(data, audio_path, args.speaker_hints), encoding="utf-8")

    segments = data.get("segments") or []
    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    print(f"Segments: {len(segments)}")


if __name__ == "__main__":
    main()
