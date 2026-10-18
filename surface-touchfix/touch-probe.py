#!/usr/bin/env python3
# Measures touch quality on the iptsd virtual touchscreen.
# Usage: sudo python3 -I touch-probe.py [/dev/input/eventN] [seconds]
# Swipe around for the given time (default 30s), or stop early with Ctrl+C.
import fcntl, json, os, struct, sys, time

EV_SYN, EV_ABS = 0, 3
SYN_REPORT = 0
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
ABS_MT_TOUCH_MAJOR, ABS_MT_TOUCH_MINOR = 0x30, 0x31
EVENT = struct.Struct("llHHi")


def find_device():
    for line in open("/proc/bus/input/devices").read().split("\n\n"):
        if "IPTSD Virtual Touchscreen" in line:
            for part in line.split():
                if part.startswith("event"):
                    return "/dev/input/" + part
    sys.exit("IPTSD Virtual Touchscreen not found, pass the device path")


def resolution(fd, code):
    # EVIOCGABS(code): struct input_absinfo { value, min, max, fuzz, flat, resolution }
    buf = fcntl.ioctl(fd, (2 << 30) | (24 << 16) | (ord("E") << 8) | (0x40 + code), bytes(24))
    res = struct.unpack("6i", buf)[5]
    return res if res > 0 else 1


dev = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1].startswith("/") else find_device()
duration = float(sys.argv[-1]) if len(sys.argv) > 1 and not sys.argv[-1].startswith("/") else 30
fd = os.open(dev, os.O_RDONLY)
# resolution is units per mm -> units per cm
rx, ry = resolution(fd, ABS_MT_POSITION_X) * 10, resolution(fd, ABS_MT_POSITION_Y) * 10
print(f"Reading {dev} for {duration:.0f}s, swipe now...", flush=True)

slot = 0
slots = {}  # slot -> current contact dict
done = []  # finished contacts
frames = []
end = time.monotonic() + duration
try:
    while time.monotonic() < end:
        sec, usec, typ, code, val = EVENT.unpack(os.read(fd, EVENT.size))
        t = sec + usec / 1e6
        if typ == EV_ABS and code == ABS_MT_SLOT:
            slot = val
        elif typ == EV_ABS and code == ABS_MT_TRACKING_ID:
            if val == -1:
                c = slots.pop(slot, None)
                if c:
                    c["end"] = t
                    done.append(c)
            else:
                slots[slot] = {"start": t, "pts": [], "x": None, "y": None, "major": 0, "minor": 0, "others": len(slots)}
        elif typ == EV_ABS and code in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y) and slot in slots:
            slots[slot]["x" if code == ABS_MT_POSITION_X else "y"] = val
        elif typ == EV_ABS and code in (ABS_MT_TOUCH_MAJOR, ABS_MT_TOUCH_MINOR) and slot in slots:
            key = "major" if code == ABS_MT_TOUCH_MAJOR else "minor"
            slots[slot][key] = max(slots[slot][key], val / rx)
        elif typ == EV_SYN and code == SYN_REPORT:
            frames.append(t)
            for c in slots.values():
                if c["x"] is not None and c["y"] is not None:
                    c["pts"].append((t, c["x"] / rx, c["y"] / ry))
except KeyboardInterrupt:
    pass

contacts = [c for c in done if c["pts"]]
if not contacts:
    sys.exit("No touches recorded")


def dist(a, b):
    return ((a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


taps = swipes = 0
max_step = max_speed = 0
for c in contacts:
    pts = c["pts"]
    path = sum(dist(pts[i - 1], pts[i]) for i in range(1, len(pts)))
    c["path"] = path
    if c["end"] - c["start"] < 0.2 and path < 0.5:
        taps += 1
    elif path >= 1:
        swipes += 1
    for i in range(1, len(pts)):
        d = dist(pts[i - 1], pts[i])
        dt = pts[i][0] - pts[i - 1][0]
        max_step = max(max_step, d)
        if dt > 0:
            max_speed = max(max_speed, d / dt)

# A finger that lifts and comes back within 150ms near the same spot is a swipe that broke apart
contacts.sort(key=lambda c: c["start"])
breaks = 0
for i, c in enumerate(contacts):
    for n in contacts[i + 1:]:
        if n["start"] - c["end"] > 0.15:
            break
        if n["start"] >= c["end"] and dist(c["pts"][-1], n["pts"][0]) < 3:
            breaks += 1
            break

gaps = [frames[i] - frames[i - 1] for i in range(1, len(frames)) if frames[i] - frames[i - 1] < 0.1]
rate = 1 / (sum(gaps) / len(gaps)) if gaps else 0
print(f"""
Touches:                 {len(contacts)}
  short taps (<0.2s):    {taps}
  swipes (>=1cm):        {swipes}
Swipes that broke apart: {breaks}   <- finger lost and found again mid-swipe
Fastest movement:        {max_speed:.0f} cm/s
Biggest jump per scan:   {max_step:.2f} cm   (iptsd ignores jumps over PositionThresholdMax, default 2)
Touch report rate:       {rate:.0f} Hz""")

# Profile the short taps, these are what places blocks in Minecraft
def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else 0


short = [c for c in contacts if c["end"] - c["start"] < 0.2 and c["path"] < 0.5]
longer = [c for c in contacts if c not in short]
if short:
    w = max(p[1] for c in contacts for p in c["pts"])
    h = max(p[2] for c in contacts for p in c["pts"])
    edge = sum(1 for c in short if min(c["pts"][0][1], c["pts"][0][2], w - c["pts"][0][1], h - c["pts"][0][2]) < 2)
    during = sum(1 for c in short if c["others"] > 0)
    print(f"""
Short taps in detail:
  while another finger was down: {during} of {len(short)}
  within 2cm of the screen edge: {edge} of {len(short)}
  median duration:               {median(c["end"] - c["start"] for c in short) * 1000:.0f} ms
  median size:                   {median(c["major"] for c in short):.2f} cm  (other touches: {median(c["major"] for c in longer):.2f} cm)""")

out = os.path.splitext(os.path.abspath(sys.argv[0]))[0] + "-last.json"
with open(out, "w") as f:
    json.dump([{k: c[k] for k in ("start", "end", "major", "minor", "others", "path", "pts")} for c in contacts], f)
print(f"\nRaw data saved to {out}")
