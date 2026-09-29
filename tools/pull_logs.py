#!/usr/bin/env python3
"""Copy the River Harpoon trial logs from the Quest into this repo's logs/quest/ folder.

    python tools/pull_logs.py                 # pull into logs/quest/
    python tools/pull_logs.py --out D:/study  # pull somewhere else

The game writes to user://trial_logs, which on Android is the app's private folder.
Debug builds (what Remote Deploy / one-click deploy installs) can be read with
`run-as`; if that fails, the app's external folder is tried. Files already on the PC
are overwritten: sessions.csv and trials.csv only ever grow on the device.
"""
import argparse
import io
import subprocess
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from adb_rec import Adb, die  # noqa: E402

PACKAGE = "com.example.vratmitgodotxrtemplate"


def pull_private(adb, package, out):
    """Stream files/trial_logs out of the app's private storage as a tar."""
    probe = adb.run("shell", f"run-as {package} ls files/trial_logs", check=False)
    if probe.returncode != 0:
        return False
    data = subprocess.run(adb._base() + ["exec-out", f"run-as {package} tar -cf - -C files trial_logs"],
                          capture_output=True, timeout=300).stdout
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            target = out / Path(member.name).relative_to("trial_logs")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tar.extractfile(member).read())
    return True


def pull_external(adb, package, out):
    remote = f"/sdcard/Android/data/{package}/files/trial_logs"
    if adb.run("shell", f"ls {remote}", check=False).returncode != 0:
        return False
    out.mkdir(parents=True, exist_ok=True)
    adb.run("pull", remote + "/.", str(out), timeout=300)
    return True


def main():
    ap = argparse.ArgumentParser(description="Copy trial logs from the Quest to the PC")
    ap.add_argument("--serial", "-s", help="device serial when several are connected")
    ap.add_argument("--package", default=PACKAGE)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "logs" / "quest"))
    args = ap.parse_args()
    adb = Adb(args.serial)
    out = Path(args.out)
    if not (pull_private(adb, args.package, out) or pull_external(adb, args.package, out)):
        die(f"No trial_logs found for {args.package}. Has an experiment been run? Is it a debug build?")
    print(f"Logs copied to {out}")
    sessions = out / "sessions.csv"
    if sessions.exists():
        rows = sessions.read_text(encoding="utf-8").splitlines()[1:]
        print(f"{len(rows)} runs in sessions.csv; last: {rows[-1] if rows else '-'}")


if __name__ == "__main__":
    main()
