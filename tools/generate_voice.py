#!/usr/bin/env python3
"""Read every task's question out loud with the Windows voice Microsoft Zira.

    python tools/generate_voice.py
    python tools/generate_voice.py --voice "Microsoft David Desktop"

Collects each `question_text` from river/experiments/*.tres (plus the default one from
river/scripts/river_task.gd) and writes river/audio/voice/q_<md5 of the text>.wav. The
game plays RiverTask.get_question_audio() when a trial starts. Identical questions share
one file. Run it again after adding or changing a question; it clears the folder first,
and the Godot editor imports the new .wav files by itself. Windows only.
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPERIMENTS = ROOT / "river" / "experiments"
TASK_SCRIPT = ROOT / "river" / "scripts" / "river_task.gd"
OUT = ROOT / "river" / "audio" / "voice"

# Written forms that a speech engine reads badly.
SPOKEN = [
    (r"\b[A-Z]{3,}\b", lambda m: m.group(0).lower()),  # FASTEST is a word, not letters
    (r"(\d)\s*m/s\b", r"\1 meters per second"),
    (r"\s/\s", " or "),
    (r"[`*_]", ""),
]

SYNTH = r"""
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice($env:VOICE_NAME)
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, 'Sixteen', 'Mono')
$s.SetOutputToWaveFile($env:VOICE_OUT, $format)
$s.Speak([IO.File]::ReadAllText($env:VOICE_TEXT, [Text.Encoding]::UTF8))
$s.Dispose()
"""

STRING = r'"((?:[^"\\]|\\.)*)"'


def unescape(text: str) -> str:
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) == "n" else m.group(1), text)


def questions() -> list[str]:
    """Every question text, in first-seen order, without duplicates."""
    found = []
    default = re.search(r"var question_text\s*:?=\s*" + STRING, TASK_SCRIPT.read_text(encoding="utf-8"))
    if default:
        found.append(unescape(default.group(1)))
    for tres in sorted(EXPERIMENTS.glob("*.tres")):
        text = tres.read_text(encoding="utf-8")
        for match in re.finditer(r"^question_text = " + STRING, text, re.MULTILINE | re.DOTALL):
            found.append(unescape(match.group(1)))
    return list(dict.fromkeys(q for q in found if q.strip()))


def to_spoken(text: str) -> str:
    for pattern, replacement in SPOKEN:
        text = re.sub(pattern, replacement, text)
    return re.sub(r"\s+", " ", text).strip()


def synthesize(text: str, out: Path, voice: str) -> None:
    text_file = out.with_suffix(".txt.tmp")
    text_file.write_text(text, encoding="utf-8")
    env = dict(os.environ, VOICE_NAME=voice, VOICE_OUT=str(out), VOICE_TEXT=str(text_file))
    try:
        subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", SYNTH],
                       env=env, check=True)
    finally:
        text_file.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--voice", default="Microsoft Zira Desktop")
    args = parser.parse_args()

    if sys.platform != "win32":
        sys.exit("generate_voice.py needs Windows (System.Speech).")
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        if old.suffix in (".wav", ".import"):
            old.unlink()
    for question in questions():
        # Same key as RiverTask.get_question_audio(): md5 of the raw question_text.
        out = OUT / f"q_{hashlib.md5(question.encode('utf-8')).hexdigest()}.wav"
        synthesize(to_spoken(question), out, args.voice)
        print(f"wrote  {out.name}  <-  {question}")


if __name__ == "__main__":
    main()
