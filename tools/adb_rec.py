#!/usr/bin/env python3
"""One-key Quest / Android screen recording: records on the device, pulls the result to the Desktop on stop.

    python tools/adb_rec.py            # interactive: starts now; Enter=stop+save, s+Enter=status, q+Enter=quit but keep recording
    python tools/adb_rec.py start [--mode native|screenrecord] [--size 2560x1440] [--bitrate 20] [--fps 60]
    python tools/adb_rec.py stop
    python tools/adb_rec.py status

Two recording backends:
- native (default): drives the Quest's built-in Meta capture service (same as the controller-shortcut
  recording). Single-eye 16:9 video, 1920x1080@30fps by default, with audio, no 180s limit. The system
  writes to /sdcard/Oculus/VideoShots; the file is pulled on stop.
- screenrecord: adb's screenrecord, looped in segments on the device (180s per-file cap); segments are
  merged with ffmpeg on stop if available. Fallback for when native is unavailable.

Shared design:
- Recording runs on the device, so USB hiccups or closing the terminal do not interrupt it; state lives
  on the device, so start/stop can be called from different terminals.
- Stop finalizes cleanly (no hard kill) and only deletes the device copy after the local copy is confirmed.
"""
import argparse
import ctypes
import datetime
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

REMOTE_ROOT = "/sdcard/xrrec"
REMOTE_SH = "/data/local/tmp/xrrec.sh"
REMOTE_PID = "/data/local/tmp/xrrec.pid"
REMOTE_DIR = "/data/local/tmp/xrrec.dir"
REMOTE_WEAR = "/data/local/tmp/xrrec.wear"
REMOTE_MODE = "/data/local/tmp/xrrec.mode"      # contents: native | sr; existing means "a recording session is active"
REMOTE_BEFORE = "/data/local/tmp/xrrec.before"  # file list of VideoShots before a native recording started
NATIVE_DIR = "/sdcard/Oculus/VideoShots"
NATIVE_SVC = "com.oculus.metacam/.capture.CaptureService"
NATIVE_PROPS = {"width": "debug.oculus.capture.width", "height": "debug.oculus.capture.height",
                "bitrate": "debug.oculus.capture.bitrate", "fps": "debug.oculus.capture.fps"}

# On-device loop: 180s per segment (screenrecord cap), keeps recording until killed
LOOP_SH = """#!/system/bin/sh
dir="$1"; shift
mkdir -p "$dir"
echo $$ > @PID@
i=0
while true; do
  n=$(printf %03d $i)
  t0=$(date +%s)
  screenrecord --time-limit 180 "$@" "$dir/seg_$n.mp4" 2>>"$dir/err.log"
  rc=$?
  # Exits instantly with an error (e.g. headset asleep): stop instead of spinning out empty files
  if [ $rc -ne 0 ] && [ $(( $(date +%s) - t0 )) -lt 3 ]; then
    echo "screenrecord rc=$rc" >> "$dir/err.log"
    break
  fi
  i=$((i+1))
done
""".replace("@PID@", REMOTE_PID)


def die(msg):
    print(f"[error] {msg}", file=sys.stderr)
    sys.exit(1)


def find_adb():
    exe = shutil.which("adb")
    if exe:
        return exe
    for root in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"), r"D:\Android\Sdk"):
        if root:
            p = Path(root) / "platform-tools" / "adb.exe"
            if p.exists():
                return str(p)
    die("adb not found; add platform-tools to PATH")


def desktop_dir():
    """Resolve the real Desktop path (correct even when OneDrive redirects the Desktop)."""
    try:
        # FOLDERID_Desktop
        guid = (ctypes.c_ubyte * 16).from_buffer_copy(
            uuid.UUID("B4BFCC3A-DB2C-424C-B029-7FE99A87C641").bytes_le)
        buf = ctypes.c_wchar_p()
        hr = ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(guid), 0, None, ctypes.byref(buf))
        if hr == 0 and buf.value:
            path = Path(buf.value)
            ctypes.windll.ole32.CoTaskMemFree(buf)
            return path
    except Exception:
        pass
    return Path.home() / "Desktop"


class Adb:
    def __init__(self, serial=None):
        self.exe = find_adb()
        self.serial = serial or self._pick_device()

    def _base(self):
        return [self.exe] + (["-s", self.serial] if self.serial else [])

    def _pick_device(self):
        out = subprocess.run([self.exe, "devices"], capture_output=True, text=True).stdout
        devs = [l.split()[0] for l in out.splitlines()[1:] if l.strip().endswith("\tdevice")]
        bad = [l for l in out.splitlines()[1:] if l.strip() and not l.strip().endswith("\tdevice")]
        if not devs:
            hint = f" (bad state: {bad[0].strip()})" if bad else ""
            die(f"No usable device{hint}. Check the USB cable and the USB debugging authorization in the headset.")
        if len(devs) > 1:
            die(f"Multiple devices detected {devs}; pick one with --serial")
        return devs[0]

    def run(self, *args, timeout=30, check=True):
        r = subprocess.run(self._base() + list(args), capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        if check and r.returncode != 0:
            die(f"adb {' '.join(args)} failed: {(r.stderr or r.stdout).strip()}")
        return r

    def sh(self, cmd, **kw):
        return self.run("shell", cmd, **kw).stdout.strip()


def is_asleep(adb):
    return "Asleep" in adb.sh("dumpsys power | grep mWakefulness=", check=False)


def get_mode(adb):
    return adb.sh(f"cat {REMOTE_MODE} 2>/dev/null", check=False)


def sr_pids(adb):
    return adb.sh("pidof screenrecord", check=False).split()


def is_recording(adb):
    mode = get_mode(adb)
    if mode == "native":
        return True
    if mode == "sr":
        return bool(sr_pids(adb))
    return False


def native_new_files(adb):
    """mp4 files added to VideoShots since recording started."""
    before = set(adb.sh(f"cat {REMOTE_BEFORE}", check=False).split())
    now = adb.sh(f"ls {NATIVE_DIR}", check=False).split()
    return sorted(f for f in now if f.endswith(".mp4") and f not in before)


def native_intent(adb, action):
    adb.sh(f"am startservice -n {NATIVE_SVC} -a {action}", check=False)


def wear_if_needed(adb, want):
    if want and is_asleep(adb):
        # Simulate "headset worn" (proximity sensor); restored automatically on stop
        adb.sh("am broadcast -a com.oculus.vrpowermanager.prox_close", check=False)
        adb.sh("input keyevent KEYCODE_WAKEUP", check=False)
        adb.sh(f"touch {REMOTE_WEAR}", check=False)
        for _ in range(20):
            if not is_asleep(adb):
                break
            time.sleep(0.25)
    if is_asleep(adb):
        die("Headset display is asleep (not worn / proximity sensor not triggered); cannot record.\n"
            "       Put the headset on, or pass --wear to have the script simulate wearing it.")


def unwear(adb):
    if adb.sh(f"ls {REMOTE_WEAR}", check=False).endswith("xrrec.wear"):
        adb.sh("am broadcast -a com.oculus.vrpowermanager.automation_disable", check=False)
        adb.sh(f"rm -f {REMOTE_WEAR}", check=False)


def start_native(adb, args):
    props = {}
    if args.size:
        w, _, h = args.size.lower().partition("x")
        props["width"], props["height"] = w, h
    if args.bitrate:
        props["bitrate"] = str(int(args.bitrate * 1_000_000))
    if args.fps:
        props["fps"] = str(args.fps)
    for k, v in props.items():
        adb.sh(f"setprop {NATIVE_PROPS[k]} {v}")
    adb.sh(f"mkdir -p {NATIVE_DIR}; ls {NATIVE_DIR} > {REMOTE_BEFORE}", check=False)
    native_intent(adb, "START_INTERNAL_CAPTURE_TO_DISK")
    for _ in range(20):  # the file shows up 1-2s after recording starts
        time.sleep(0.5)
        if native_new_files(adb):
            adb.sh(f"echo native > {REMOTE_MODE}")
            print(f"[recording/native] device {adb.serial}  "
                  f"{args.size or '1920x1080'}  {args.fps or 30}fps  {args.bitrate or 6}Mbps")
            return
    die("Meta capture service did not respond (no new file appeared). Try --mode screenrecord as a fallback.")


def start_sr(adb, args):
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False, newline="\n") as f:
        f.write(LOOP_SH)
        local_sh = f.name
    try:
        adb.run("push", local_sh, REMOTE_SH)
    finally:
        os.unlink(local_sh)

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    rdir = f"{REMOTE_ROOT}/{ts}"
    bitrate = args.bitrate or 12
    sr_args = f"--bit-rate {int(bitrate * 1_000_000)}"
    if args.size:
        sr_args += f" --size {args.size}"
    adb.sh(f"echo {rdir} > {REMOTE_DIR}")
    # Redirect everything + background so adb shell returns immediately; nohup detaches it from the adb session
    try:
        adb.run("shell", f"nohup sh {REMOTE_SH} {rdir} {sr_args} </dev/null >/dev/null 2>&1 &", timeout=10)
    except subprocess.TimeoutExpired:
        pass

    # Confirm it actually started and survived the first seconds, rather than assuming
    time.sleep(2.5)
    if not sr_pids(adb):
        err = adb.sh(f"cat {rdir}/err.log", check=False)
        adb.sh(f"rm -rf {rdir} {REMOTE_DIR}", check=False)
        die(f"screenrecord did not start. Device output: {err or '(none)'}")
    adb.sh(f"echo sr > {REMOTE_MODE}")
    print(f"[recording/screenrecord] device {adb.serial}  {bitrate}Mbps  {args.size or 'default resolution'}")


def cmd_start(adb, args):
    if is_recording(adb):
        die("Already recording on the device; run stop first")
    wear_if_needed(adb, args.wear)
    (start_native if args.mode == "native" else start_sr)(adb, args)


def collect(adb, remote_paths, stamp):
    """Pull and merge/organize onto the Desktop. Returns only if every pull succeeded, otherwise dies (device files are kept)."""
    out_dir = desktop_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    base, n = stamp, 1
    while (out_dir / f"quest_{stamp}.mp4").exists() or (out_dir / f"quest_{stamp}").exists():
        stamp, n = f"{base}_{n}", n + 1  # never overwrite an existing recording on the Desktop
    with tempfile.TemporaryDirectory() as tmp:
        segs = []
        for rp in remote_paths:
            local = Path(tmp) / rp.rsplit("/", 1)[-1]
            adb.run("pull", rp, str(local), timeout=600)
            if local.exists() and local.stat().st_size > 0:
                segs.append(local)
        if len(segs) != len(remote_paths):
            die("Incomplete pull; files kept on the device at " + ", ".join(remote_paths))

        result = None
        if len(segs) == 1:
            result = out_dir / f"quest_{stamp}.mp4"
            shutil.move(str(segs[0]), result)
        elif shutil.which("ffmpeg"):
            lst = Path(tmp) / "list.txt"
            lst.write_text("".join(f"file '{s.as_posix()}'\n" for s in segs), encoding="utf-8")
            final = out_dir / f"quest_{stamp}.mp4"
            r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
                                "-i", str(lst), "-c", "copy", str(final)])
            if r.returncode == 0:
                result = final
            else:
                print("[warning] ffmpeg merge failed; keeping the segments instead")
        if result is None:  # no ffmpeg / merge failed: put segments in a Desktop folder
            folder = out_dir / f"quest_{stamp}"
            folder.mkdir(exist_ok=True)
            for s in segs:
                shutil.move(str(s), folder / s.name)
            result = folder
    size = (result.stat().st_size if result.is_file()
            else sum(p.stat().st_size for p in result.iterdir())) / 1e6
    print(f"[saved] {result}  ({size:.1f} MB, {len(segs)} segment(s))")


def stop_native(adb):
    native_intent(adb, "STOP_INTERNAL_CAPTURE_TO_DISK")
    files, last = [], None
    for _ in range(60):  # wait up to 30s: done when the size is unchanged across two polls and not a tiny placeholder
        time.sleep(0.5)
        files = native_new_files(adb)
        sizes = [adb.sh(f"stat -c %s {NATIVE_DIR}/{f}", check=False) for f in files]
        if files and all(s.isdigit() and int(s) > 4096 for s in sizes) and sizes == last:
            break
        last = sizes
    else:
        print("[warning] file size still changing after 30s; pulling as-is")
    if not files:
        die("No new recording file found (it may have been stopped and deleted in the headset)")
    # the headset clock is unreliable; name the file with the PC's current time
    collect(adb, [f"{NATIVE_DIR}/{f}" for f in files], datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    for f in files:  # local copy confirmed, delete the device copy
        adb.sh(f"rm -f {NATIVE_DIR}/{f}", check=False)
    for prop in NATIVE_PROPS.values():  # restore quality props so later manual recordings are unaffected
        adb.sh(f'setprop {prop} ""', check=False)


def stop_sr(adb):
    rdir = adb.sh(f"cat {REMOTE_DIR}", check=False)
    if not rdir.startswith(REMOTE_ROOT):
        die("No recording record found on the device (did you run start?)")
    # Kill the loop script first (otherwise a new segment starts when screenrecord exits), then SIGINT screenrecord
    adb.sh(f"kill $(cat {REMOTE_PID}) 2>/dev/null; "
           "for p in $(pidof screenrecord); do kill -2 $p; done", check=False)
    for _ in range(60):  # wait up to 15s for the mp4 moov atom to be written
        if not sr_pids(adb):
            break
        time.sleep(0.25)
    else:
        adb.sh("for p in $(pidof screenrecord); do kill -9 $p; done", check=False)
        print("[warning] screenrecord did not exit within 15s and was force-killed; the last segment may be corrupt")
    files = sorted(f for f in adb.sh(f"ls {rdir}", check=False).split() if f.endswith(".mp4"))
    if not files:
        die(f"No recording files in {rdir}")
    collect(adb, [f"{rdir}/{f}" for f in files], rdir.rsplit("/", 1)[-1])
    adb.sh(f"rm -rf {rdir} {REMOTE_DIR} {REMOTE_PID}", check=False)


def cmd_stop(adb, args):
    mode = get_mode(adb)
    if mode not in ("native", "sr"):
        die("No recording in progress on the device (did you run start?)")
    (stop_native if mode == "native" else stop_sr)(adb)
    unwear(adb)
    adb.sh(f"rm -f {REMOTE_MODE} {REMOTE_BEFORE}", check=False)


def cmd_status(adb, args, since=None):
    if not is_recording(adb):
        print(f"device {adb.serial}: idle")
        return
    mode = get_mode(adb)
    info = f"device {adb.serial}: recording ({mode})"
    if since:
        sec = int(time.time() - since)
        info += f"  elapsed {sec // 60:02d}:{sec % 60:02d}"
    if mode == "native":
        files = native_new_files(adb)
        if files:
            size = adb.sh(f"stat -c %s {NATIVE_DIR}/{files[0]}", check=False)
            if size.isdigit():  # the system writes in chunks, so size does not grow every second
                info += f"  written on device {int(size) / 1e6:.1f} MB"
    else:
        rdir = adb.sh(f"cat {REMOTE_DIR}", check=False)
        kb = adb.sh(f"du -sk {rdir} | cut -f1", check=False)
        if kb.isdigit():
            info += f"  written on device {int(kb) / 1024:.1f} MB"
    print(info)


def cmd_interactive(adb, args):
    """No arguments: start recording, then wait for keys. Enter stops, s shows status, q quits without stopping."""
    since = time.time()
    if is_recording(adb):
        print("[attach] Already recording on the device; taking over")
        since = None
    else:
        cmd_start(adb, args)
    print("Enter = stop and save to Desktop | s+Enter = status | q+Enter = quit (keeps recording; run this script again to take over)")
    while True:
        try:
            cmd = input("> ").strip().lower()
        except (EOFError, KeyboardInterrupt):  # Ctrl+C also counts as stop, so the file is never lost
            print()
            cmd = ""
        if cmd == "s":
            cmd_status(adb, args, since)
        elif cmd == "q":
            print("Exited; the device is still recording. Run this script again to take over and stop.")
            return
        elif cmd == "":
            cmd_stop(adb, args)
            return
        else:
            print("Unknown input. Enter=stop, s=status, q=quit")


def main():
    ap = argparse.ArgumentParser(description="One-key adb screen recording for Quest/Android, saved to the Desktop")
    ap.add_argument("action", nargs="?", choices=["start", "stop", "status"],
                    help="omit for interactive mode")
    ap.add_argument("--serial", "-s", help="device serial when several are connected")
    ap.add_argument("--mode", choices=["native", "screenrecord"], default="native",
                    help="native = Quest built-in capture (single-eye 16:9, default); screenrecord = adb fallback")
    ap.add_argument("--size", help="e.g. 2560x1440. native default is 1920x1080")
    ap.add_argument("--bitrate", type=float, help="Mbps. native default ~6, screenrecord default 12")
    ap.add_argument("--fps", type=int, help="native only, default 30")
    ap.add_argument("--wear", action=argparse.BooleanOptionalAction, default=None,
                    help="simulate wearing the headset (proximity sensor) if it is asleep; restored on stop. On by default in interactive mode, disable with --no-wear")
    args = ap.parse_args()
    args.mode = "sr" if args.mode == "screenrecord" else "native"
    adb = Adb(args.serial)
    if args.action is None:
        if args.wear is None:
            args.wear = True
        cmd_interactive(adb, args)
    else:
        {"start": cmd_start, "stop": cmd_stop, "status": cmd_status}[args.action](adb, args)


if __name__ == "__main__":
    main()
