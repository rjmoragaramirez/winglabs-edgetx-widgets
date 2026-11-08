"""Desktop simulator for the WL Flight Stats widget (EdgeTX).

Runs the real widget Lua code on Lua 5.3 (lupa) against a strict EdgeTX/LVGL mock, flies
synthetic INAV/ELRS flights, checks the per-call instruction budget, the SD storage
(8-flight rotation, reload) and renders PNG screenshots of the LVGL tree.

    python tools/sim/run_sim.py            # report + screenshots in tools/sim/out
    WL_SIM_SIZE=800                        # TX16S MK3 layout (800x480, scale 1.375)
"""
import math
import os
import random
import shutil
import sys

from lupa import lua53
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
WIDGET = os.path.join(REPO, "WIDGETS", "WLFlightStats").replace("\\", "/") + "/"
OUT = os.path.join(HERE, "out")
EDGE_LIMIT = 20000  # instructions per Lua call before EdgeTX raises "CPU limit"
WORST = [0, ""]
BIG = os.environ.get("WL_SIM_SIZE", "480") == "800"
SCREEN = (800, 480, 1.375) if BIG else (480, 272, 1.0)
TAG = "800" if BIG else "480"

THEMES = ["Dark", "Light", "Navy", "Sunlight", "Night", "Carbon"]
HOME = tuple(float(v) for v in os.environ.get("WL_SIM_HOME", "40.1666,-85.3195").split(","))

SENSORS = {  # name: (id, unit)
    "RQly": (1, 13), "1RSS": (2, 19), "TPWR": (3, 17), "RxBt": (4, 1), "Curr": (5, 2),
    "Capa": (6, 14), "Bat%": (7, 13), "FM": (8, 0), "GPS": (9, 0), "GSpd": (10, 6),
    "Hdg": (11, 22), "Alt": (12, 9), "Sats": (13, 0), "Ptch": (14, 23), "Roll": (15, 23),
    "Yaw": (16, 23), "VSpd": (17, 5),
}


def d(p):
    return p.replace("\\", "/").rstrip("/") + "/"


class Sim:
    def __init__(self, logs, w=SCREEN[0], h=SCREEN[1], scale=SCREEN[2], theme=1, units=1):
        os.makedirs(logs, exist_ok=True)
        self.lua = lua53.LuaRuntime(unpack_returned_tuples=True)
        with open(os.path.join(HERE, "edgetx_mock.lua"), encoding="utf-8") as f:
            self.M = self.lua.execute(f.read(), WIDGET, d(logs))
        self.lua.globals().lvgl.LCD_SCALE = scale
        self.widget = self.lua.globals().loadScript("/WIDGETS/WLFlightStats/main.lua")()
        self.zone = self.lua.table_from({"x": 0, "y": 0, "w": w, "h": h})
        self.opts = self.lua.table_from({"Theme": theme, "Units": units, "Cells": 0, "MinFlight": 20})
        self.w, self.h, self.scale = w, h, scale
        self.worst = 0
        self.ctx = self.call(self.widget.create, self.zone, self.opts, "/WIDGETS/WLFlightStats/")
        for name, (i, unit) in SENSORS.items():
            self.M.sensors[name] = self.lua.table_from({"id": i, "unit": unit})

    def call(self, fn, *args):
        holder = {}

        def run():
            holder["r"] = fn(*args)
        n = self.M.counted(run)
        if n > self.worst:
            self.worst = n
            WORST[0] = max(WORST[0], n)
            if n >= WORST[0]:
                WORST[1] = f"{getattr(fn, '__name__', '?')} t={self.M.now} pos={self.ctx.pos if hasattr(self, 'ctx') else '-'}"

        return holder.get("r")

    def set(self, name, value):
        if isinstance(value, dict):
            value = self.lua.table_from(value)
        self.M.vals[SENSORS[name][0]] = value

    def refresh(self, event=None, touch=None):
        if touch is not None:
            touch = self.lua.table_from(touch)
        self.call(self.widget.refresh, self.ctx, event, touch)

    def background(self):
        self.call(self.widget.background, self.ctx)

    def settle(self, frames=12):
        """Visible frames until the staged build is complete; returns the resolved tree."""
        for _ in range(frames):
            self.M.now += 5
            self.refresh()
        holder = {}

        def res():
            holder["t"] = self.M.resolve()
        self.M.counted(res)
        self.worst = max(self.worst, self.M.cbInstr)
        return holder["t"]

    def shot(self, name):
        render(self.settle(), self.w, self.h, self.scale).save(os.path.join(OUT, f"{TAG}_{name}.png"))


# --------------------------------------------------------------------------- flights
def profile(t, dur, peak_alt=125.0):
    """Throttle / alt (m) / speed (km/h) of a typical fixed-wing flight of length dur s."""
    if t < 6:
        thr = 0.0
    elif t < 25:
        thr = 0.85
    elif t > dur - 2:
        thr = 0.0
    elif t > dur - 47:
        thr = 0.22
    else:
        thr = 0.42 + 0.08 * math.sin(t / 23)
        for f, w in ((0.26, 9), (0.45, 7), (0.65, 12), (0.73, 6)):
            if abs(t - f * dur) < w:
                thr = 0.92
    climb = 0.41 * dur
    if t < 6:
        alt = 0.0
    elif t < climb:
        alt = peak_alt * (t - 6) / (climb - 6)
    elif t < dur - 62:
        alt = 0.73 * peak_alt + 0.17 * peak_alt * math.sin((t - climb) / 30)
        if abs(t - 0.72 * dur) < 12:
            alt += 0.15 * peak_alt
    elif t < dur - 22:
        alt = 0.73 * peak_alt * (dur - 22 - t) / 40
    else:
        alt = 0.0
    if t < 6 or t > dur - 17:
        spd = 0.0
    elif t < 25:
        spd = 55 * (t - 6) / 19
    else:
        spd = 74 + 10 * math.sin(t / 17)
        if abs(t - 0.73 * dur) < 12:
            spd = 74 + 36 * math.cos((t - 0.73 * dur) / 12 * math.pi / 2)
        if t > dur - 47:
            spd = max(0.0, 74 * (dur - 17 - t) / 30)
    return thr, alt, spd


class Flight:
    def __init__(self, dur, cap=3300.0, peak_alt=125.0, lost=None, off_at=None, seed=1):
        self.dur, self.cap, self.peak_alt, self.lost, self.off_at = dur, cap, peak_alt, lost, off_at
        self.used, self.last = 0.0, 0.0
        self.rng = random.Random(seed)

    def apply(self, sim, t, armed):
        """Set all sensors for flight time t (s since the flight sequence started)."""
        linked = True
        if self.lost and self.lost[0] <= t < self.lost[1]:
            linked = False
        if self.off_at is not None and t >= self.off_at:
            linked = False
        sim.M.linked = linked
        sim.M.lq = 100
        thr, alt, spd = profile(t, self.dur, self.peak_alt) if armed else (0.0, 0.0, 0.0)
        cur = 0.8 + thr * 32 + (self.rng.uniform(-1.2, 1.2) if thr > 0 else 0)
        self.used += cur * (t - self.last) / 3.6
        self.last = t
        soc = max(0.0, 1 - self.used / self.cap)
        volt = 4 * (3.62 + 0.55 * soc ** 1.3) - cur * 0.022
        sim.set("RQly", 100); sim.set("1RSS", -60); sim.set("TPWR", 250)
        sim.set("FM", "ANGL" if armed else "OK"); sim.set("Sats", 14)
        sim.set("RxBt", round(volt, 2)); sim.set("Curr", round(cur, 1)); sim.set("Capa", int(self.used))
        sim.set("Bat%", int(soc * 100))
        sim.set("Alt", round(max(0.0, alt + (self.rng.uniform(-1.2, 1.2) if alt > 3 else 0)), 1))
        sim.set("GSpd", round(max(0.0, spd + (self.rng.uniform(-2, 2) if spd > 0 else 0)), 1))
        sim.set("VSpd", 0.0)
        r = 600 * math.sin(math.pi * min(t, self.dur) / self.dur) if armed else 0
        dn = r * math.cos(t / 60) / 111319.5
        de = r * math.sin(t / 60) / (111319.5 * math.cos(math.radians(HOME[0])))
        sim.set("GPS", {"lat": HOME[0] + dn, "lon": HOME[1] + de})


def fly(sim, fl, visible=False, step=10, pre=3, post=4):
    """Disarmed pre s, armed fl.dur s, disarmed post s. Widget hidden (background) unless visible."""
    t = -pre
    while t < fl.dur + post:
        armed = 0 <= t < fl.dur
        fl.apply(sim, max(0.0, t), armed)
        sim.M.now += step
        if visible:
            sim.refresh()
        else:
            sim.background()
        t += step / 100


# --------------------------------------------------------------------------- render
FONT_DIR = "C:/Windows/Fonts/"
FONT_PX = {0x000: 15, 0x100: 15, 0x200: 12, 0x300: 21, 0x400: 30, 0x500: 48, 0x700: 10}
_font_cache = {}


def font(flags, scale):
    size_key = flags & 0xF00
    bold = size_key in (0x100, 0x400, 0x500)
    px = int(FONT_PX.get(size_key, 15) * scale)
    key = (px, bold)
    if key not in _font_cache:
        name = "segoeuib.ttf" if bold else "segoeui.ttf"
        try:
            _font_cache[key] = ImageFont.truetype(FONT_DIR + name, px)
        except OSError:
            _font_cache[key] = ImageFont.load_default()
    return _font_cache[key]


def rgba(c, opacity=255):
    c = int(c) & 0xFFFFFF
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255, int(opacity))


def lget(node, key, default=None):
    v = node[key]
    return default if v is None else v


def render(tree, w, h, scale):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))

    def draw_nodes(nodes, ox, oy, clip):
        for i in range(1, len(nodes) + 1):
            n = nodes[i]
            if n is None or lget(n, "hidden", False):
                continue
            ty = n["type"]
            x = ox + lget(n, "x", 0)
            y = oy + lget(n, "y", 0)
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            dr = ImageDraw.Draw(layer)
            col = rgba(lget(n, "color", 0xFFFFFF), lget(n, "opacity", 255))
            nw, nh = lget(n, "w", 0), lget(n, "h", 0)
            if ty == "rectangle":
                r = lget(n, "rounded", 0) or 0
                if lget(n, "filled", False):
                    dr.rounded_rectangle([x, y, x + nw - 1, y + nh - 1], radius=r, fill=col)
                else:
                    dr.rounded_rectangle([x, y, x + nw - 1, y + nh - 1], radius=r, outline=col,
                                         width=lget(n, "thickness", 1))
            elif ty == "label":
                f = font(lget(n, "font", 0), scale)
                text = n["text"]
                tw = dr.textlength(text, font=f)
                al = lget(n, "align", 0)
                tx = x + (nw - tw if al & 0x04 else (nw - tw) / 2 if al & 0x08 else 0) if nw else x
                dr.text((tx, y), text, font=f, fill=col)
            elif ty == "line":
                pts = n["pts"]
                p = [(x + pts[k][1], y + pts[k][2]) for k in range(1, len(pts) + 1)]
                t = lget(n, "thickness", 1)
                dr.line(p, fill=col, width=t, joint="curve")
                if lget(n, "rounded", False):
                    for px_, py_ in p:
                        dr.ellipse([px_ - t / 2, py_ - t / 2, px_ + t / 2, py_ + t / 2], fill=col)
            elif ty == "circle":
                r = n["radius"]
                bb = [x - r, y - r, x + r, y + r]
                if lget(n, "filled", False):
                    dr.ellipse(bb, fill=col)
                else:
                    dr.ellipse(bb, outline=col, width=lget(n, "thickness", 1))
            cx0, cy0, cx1, cy1 = clip
            if cx1 > cx0 and cy1 > cy0:
                region = layer.crop((cx0, cy0, cx1, cy1))
                img.alpha_composite(region, (cx0, cy0))
            if len(n["children"]) and ty in ("rectangle", "box"):
                nclip = (max(clip[0], x), max(clip[1], y), min(clip[2], x + nw), min(clip[3], y + nh))
                draw_nodes(n["children"], x, y, nclip)

    draw_nodes(tree, 0, 0, (0, 0, w, h))
    return img.convert("RGB")


# --------------------------------------------------------------------------- main
def lst(sim):
    L = sim.ctx.store.list
    return [L[i] for i in range(1, len(L) + 1)]


def check(cond, msg, fails):
    print(("  PASS " if cond else "  FAIL ") + msg)
    if not cond:
        fails.append(msg)


def run():
    for sub in ("logs", "logs_gallery", "logs_none"):
        dd = os.path.join(OUT, sub)
        for fn in (os.listdir(dd) if os.path.isdir(dd) else []):
            os.remove(os.path.join(dd, fn))  # OneDrive keeps folders locked: empty them
    os.makedirs(OUT, exist_ok=True)
    logs, gal = os.path.join(OUT, "logs"), os.path.join(OUT, "logs_gallery")
    fails, worst = [], 0

    sim = Sim(logs)
    sim.shot("empty")
    check(len(lst(sim)) == 0, "no flights at first start", fails)

    # bench: armed 8 s (< MinFlight 20 s) -> not saved
    fly(sim, Flight(8), visible=True)
    check(len(lst(sim)) == 0, "8 s bench arm is not saved", fails)

    # flight 1: 7:42, widget hidden (another screen shown) the whole flight
    fly(sim, Flight(462, seed=7))
    L = lst(sim)
    check(len(L) == 1, "7:42 flight saved", fails)
    f = L[0]
    print(f"    dur {f.dur}s maxAlt {f.maxAlt / 10:.1f} m @{f.tAlt}s maxSpd {f.maxSpd / 10:.1f} km/h @{f.tSpd}s "
          f"minV {f.minV / 100:.2f} maxA {f.maxA / 10:.1f} used {f.used} dist {f.maxDist} m cells {f.cells} n {f.n}")
    check(f.dur == 462 and f.cells == 4 and f.n == 120, "duration, cells, 120 plot points", fails)
    ta = max(range(4620), key=lambda i: profile(i / 10, 462)[1]) / 10
    ts = max(range(4620), key=lambda i: profile(i / 10, 462)[2]) / 10
    pa, ps = profile(ta, 462)[1], profile(ts, 462)[2]
    check(abs(f.maxAlt / 10 - pa) < 3 and abs(f.maxSpd / 10 - ps) < 4 and abs(f.tAlt - ta) < 3
          and abs(f.tSpd - ts) < 3, f"peaks + times recorded (profile {pa:.1f} m @{ta}s, {ps:.1f} km/h @{ts}s)", fails)
    sim.shot("landed")
    shutil.copytree(logs, gal, dirs_exist_ok=True)
    # recording state on screen (start a flight, visible)
    fl = Flight(120, seed=3)
    t = -1.0
    while t < 65:
        fl.apply(sim, max(0.0, t), t >= 0)
        sim.M.now += 10
        sim.background()
        t += 0.1
    sim.shot("recording")
    while t < 125:
        fl.apply(sim, max(0.0, t), t < 120)
        sim.M.now += 10
        sim.background()
        t += 0.1
    check(len(lst(sim)) == 2, "2nd flight saved", fails)

    # flight 3: 25 min with a 6 s link loss (tests 2:1 merges and held values)
    fly(sim, Flight(1500, cap=8000, lost=(700, 706), seed=11))
    f = lst(sim)[-1]
    check(len(lst(sim)) == 3 and f.dur == 1500 and f.n == 120, "25 min flight saved with 120 points", fails)
    ser = sim.ctx.ser
    check(ser is not None and min(ser.v[i] for i in range(1, 121)) > 1000, "no voltage dropouts in the series", fails)

    # flight 4: model switched off while armed -> saved after 20 s without link
    fly(sim, Flight(300, off_at=200, seed=5), post=30)
    f = lst(sim)[-1]
    check(len(lst(sim)) == 4 and f.dur == 200, "armed + link lost 20 s -> flight saved up to the loss", fails)
    sim.shot("long")

    # fill the rotation: 6 more flights -> 10 flown, 8 kept
    for k in range(6):
        fly(sim, Flight(60 + 10 * k, seed=20 + k))
    L = lst(sim)
    check(len(L) == 8 and L[0].seq == 3 and L[-1].seq == 10, "8 flights kept (seq 3..10)", fails)
    files = sorted(os.listdir(logs))
    check(len([x for x in files if x.endswith(".txt")]) == 8, "8 slot files on the SD", fails)
    worst = max(worst, sim.worst)

    # reload (radio power cycle) and navigate
    s2 = Sim(logs)
    check(len(lst(s2)) == 8 and s2.ctx.pos == 8, "reload: 8 flights, newest shown", fails)
    s2.settle()
    s2.refresh(0x1001)              # rotary left -> older
    check(s2.ctx.pos == 7, "rotary left selects the previous flight", fails)
    s2.refresh(0x1003, {"x": 400, "y": 100})  # tap right half -> newer
    check(s2.ctx.pos == 8, "tap right half selects the next flight", fails)
    for _ in range(9):
        s2.refresh(0x1001)
    check(s2.ctx.pos == 1, "stops at the oldest flight", fails)
    s2.shot("oldest")
    worst = max(worst, s2.worst)

    # theme gallery + compact zone + metric
    shots = []
    for i, name in enumerate(THEMES, start=1):
        s = Sim(gal, theme=i)
        img = render(s.settle(), s.w, s.h, s.scale)
        img.save(os.path.join(OUT, f"{TAG}_theme_{name.lower()}.png"))
        shots.append(img)
        worst = max(worst, s.worst)
    W, H = shots[0].size
    g = Image.new("RGB", (W * 3 + 8, H * 2 + 4), (60, 60, 60))
    for i, im in enumerate(shots):
        g.paste(im, ((i % 3) * (W + 4), (i // 3) * (H + 4)))
    g.save(os.path.join(OUT, f"{TAG}_gallery_themes.png"))
    s = Sim(gal, units=2, theme=6)
    s.shot("metric_carbon")
    if not BIG:
        s = Sim(gal, 225, 98, 1.0, theme=1)
        s.shot("compact_dark")
        s = Sim(os.path.join(OUT, "logs_none"), 225, 98, 1.0, theme=2)
        s.shot("compact_empty_light")

    print(f"worst Lua call: {worst} instructions (EdgeTX limit {EDGE_LIMIT}) at {WORST[1]}")
    check(worst < EDGE_LIMIT * 0.75, "instruction budget (< 75 % of the limit)", fails)
    print("screenshots:", OUT)
    print("RESULT:", "PASS" if not fails else f"FAIL ({len(fails)})")
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(run())
