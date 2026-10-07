"""Desktop simulator for the WL Attitude Ind widget (EdgeTX).

Runs the real widget Lua code on Lua 5.3 (lupa) against a strict EdgeTX/LVGL mock,
drives a synthetic INAV/ELRS flight, checks CPU (instruction) budget and per-frame
allocations, and renders PNG screenshots of the LVGL tree.

    python tools/sim/run_sim.py            # full report + screenshots in tools/sim/out
"""
import math
import os
import sys

from lupa import lua53
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
WIDGET = os.path.join(REPO, "WIDGETS", "WLAttitudeInd").replace("\\", "/") + "/"
OUT = os.path.join(HERE, "out")
EDGE_LIMIT = 20000  # instructions per Lua call before EdgeTX raises "CPU limit"

THEMES = ["Dark", "Light", "Navy", "Sunlight", "Night"]
# Synthetic flight home: AMA International Aeromodeling Center, Muncie, Indiana (public example).
# Override with WL_SIM_HOME="lat,lon" to fly the simulator over your own field.
HOME = tuple(float(v) for v in os.environ.get("WL_SIM_HOME", "40.1666,-85.3195").split(","))

SENSORS = {  # name: (id, unit)
    "RQly": (1, 13), "1RSS": (2, 19), "TPWR": (3, 17), "RxBt": (4, 1), "Curr": (5, 2),
    "Capa": (6, 14), "Bat%": (7, 13), "FM": (8, 0), "GPS": (9, 0), "GSpd": (10, 6),
    "Hdg": (11, 22), "Alt": (12, 9), "Sats": (13, 0), "Ptch": (14, 23), "Roll": (15, 23),
    "Yaw": (16, 23), "VSpd": (17, 5),
}


class Sim:
    def __init__(self, w=800, h=480, scale=1.375, theme=1, units=1):  # TX16S MK3 (EdgeTX LCD_SCALE 1.375)
        self.lua = lua53.LuaRuntime(unpack_returned_tuples=True)
        with open(os.path.join(HERE, "edgetx_mock.lua"), encoding="utf-8") as f:
            self.M = self.lua.execute(f.read(), WIDGET)
        self.lua.globals().lvgl.LCD_SCALE = scale
        self.sensors_on = False
        self.widget = self.lua.globals().loadScript("/WIDGETS/WLAttitudeInd/main.lua")()
        self.zone = self.lua.table_from({"x": 0, "y": 0, "w": w, "h": h})
        self.opts = self.lua.table_from({"Theme": theme, "Units": units, "Cells": 0, "CellWarn": 350,
                                         "CellCrit": 330, "AltWarn": 400, "Sounds": 1, "Haptic": 1})
        self.w, self.h, self.scale = w, h, scale
        self.ctx = self.widget.create(self.zone, self.opts, "/WIDGETS/WLAttitudeInd/")

    def set_theme(self, theme):
        self.opts.Theme = theme
        self.widget.update(self.ctx, self.opts)

    def enable_sensors(self):
        if not self.sensors_on:
            for name, (i, unit) in SENSORS.items():
                self.M.sensors[name] = self.lua.table_from({"id": i, "unit": unit})
            self.sensors_on = True

    def set(self, name, value):
        if isinstance(value, dict):
            value = self.lua.table_from(value)
        self.M.vals[SENSORS[name][0]] = value

    def frame(self):
        """One GUI cycle: refresh() then callRefs(). Returns instructions + resolved tree."""
        n_refresh = self.M.counted(self.widget.refresh, self.ctx)
        holder = {}

        def do_resolve():
            holder["t"] = self.M.resolve()
        self.M.counted(do_resolve)
        return n_refresh, self.M.cbInstr, holder["t"]


def scenario(sim, t):
    """Synthetic flight. t in seconds."""
    if t < 2:
        sim.M.linked = False
        return
    sim.enable_sensors()
    sim.M.linked = not (50 <= t < 53)
    sim.M.lq = 100 if t < 45 else 62 if t < 50 else 41
    sim.set("RQly", sim.M.lq); sim.set("1RSS", -48 - int(t * 0.6)); sim.set("TPWR", 250)
    armed = 8 <= t < 75
    if t < 4:
        fm, sats = "WAIT", 4
    elif not armed:
        fm, sats = "OK", 14
    elif t < 40:
        fm, sats = "ANGL" if t < 25 else "CRUZ", 14
    elif t < 50:
        fm, sats = "RTH", 13
    elif t < 56:
        fm, sats = "!FS!", 12
    else:
        fm, sats = "HOLD", 13
    sim.set("FM", fm); sim.set("Sats", sats)
    ft = max(0.0, t - 8) if armed else 0.0
    # battery 4S: 16.6V -> 13.0V over the flight
    v = 16.6 - min(3.7, ft * 0.055)
    sim.set("RxBt", round(v, 1)); sim.set("Curr", 18.5 if armed else 0.4)
    sim.set("Capa", int(ft * 28)); sim.set("Bat%", max(0, int(100 - ft * 1.4)))
    # attitude (radians, INAV pitch > 0 = nose down)
    roll = 35 * math.sin(ft * 0.5) if armed else 0
    pitch = -8 * math.sin(ft * 0.3) if armed else 0
    sim.set("Roll", math.radians(roll)); sim.set("Ptch", math.radians(pitch))
    hdg = (45 + ft * 4) % 360
    sim.set("Yaw", math.radians(hdg if hdg <= 180 else hdg - 360)); sim.set("Hdg", hdg)
    # position: moves out 45 deg then back
    dist = min(ft, 32) * 25 - max(0, ft - 32) * 18
    dist = max(0.0, dist)
    dn = dist * math.cos(math.radians(45)) / 111319.5
    de = dist * math.sin(math.radians(45)) / (111319.5 * math.cos(math.radians(HOME[0])))
    sim.set("GPS", {"lat": HOME[0] + dn, "lon": HOME[1] + de})
    sim.set("Alt", min(150.0, ft * 4.0)); sim.set("VSpd", 4.0 if ft * 4 < 150 else 0.2)
    sim.set("GSpd", 72.0 if armed else 0.0)


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
            d = ImageDraw.Draw(layer)
            col = rgba(lget(n, "color", 0xFFFFFF), lget(n, "opacity", 255))
            nw, nh = lget(n, "w", 0), lget(n, "h", 0)
            if ty == "rectangle":
                r = lget(n, "rounded", 0) or 0
                if lget(n, "filled", False):
                    d.rounded_rectangle([x, y, x + nw - 1, y + nh - 1], radius=r, fill=col)
                else:
                    d.rounded_rectangle([x, y, x + nw - 1, y + nh - 1], radius=r, outline=col,
                                        width=lget(n, "thickness", 1))
            elif ty == "label":
                f = font(lget(n, "font", 0), scale)
                text = n["text"]
                tw = d.textlength(text, font=f)
                al = lget(n, "align", 0)
                tx = x + (nw - tw if al & 0x04 else (nw - tw) / 2 if al & 0x08 else 0) if nw else x
                d.text((tx, y), text, font=f, fill=col)
            elif ty == "line":
                pts = n["pts"]
                p = [(ox + lget(n, "x", 0) + pts[k][1], oy + lget(n, "y", 0) + pts[k][2]) for k in range(1, len(pts) + 1)]
                t = lget(n, "thickness", 1)
                d.line(p, fill=col, width=t, joint="curve")
                if lget(n, "rounded", False):
                    for px_, py_ in p:
                        d.ellipse([px_ - t / 2, py_ - t / 2, px_ + t / 2, py_ + t / 2], fill=col)
            elif ty == "circle":
                r = n["radius"]
                bb = [x - r, y - r, x + r, y + r]
                if lget(n, "filled", False):
                    d.ellipse(bb, fill=col)
                else:
                    d.ellipse(bb, outline=col, width=lget(n, "thickness", 1))
            elif ty == "arc":
                r = n["radius"]
                d.arc([x - r, y - r, x + r, y + r], n["startAngle"], n["endAngle"], fill=col,
                      width=lget(n, "thickness", 1))
            # composite with clip
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
def run():
    os.makedirs(OUT, exist_ok=True)
    sim = Sim()
    worst_ref, worst_refs, worst_alloc = 0, 0, 0
    allocs = []
    shots = {1.0: "no_link", 3.0: "wait_gps", 20.0: "flying", 47.0: "rth_weak", 51.0: "lost",
             54.0: "failsafe", 70.0: "batt_crit"}
    tick = 5  # 20 Hz GUI
    t_ticks = 0
    while t_ticks <= 80 * 100:
        t = t_ticks / 100
        sim.M.now = t_ticks
        scenario(sim, t)
        a = sim.M.alloc(sim.widget.refresh, sim.ctx)
        n_ref, n_refs, tree = sim.frame()
        if t > 3:
            allocs.append(a)
        worst_ref, worst_refs = max(worst_ref, n_ref), max(worst_refs, n_refs)
        worst_alloc = max(worst_alloc, a)
        for st, name in shots.items():
            if abs(t - st) < 1e-6:
                render(tree, sim.w, sim.h, sim.scale).save(os.path.join(OUT, f"800_dark_{name}.png"))
        t_ticks += tick

    print(f"frames: {len(allocs)}  worst refresh: {worst_ref} instr  worst callRefs (widget callbacks): {worst_refs} instr "
          f"(EdgeTX limit {EDGE_LIMIT})")
    print(f"alloc per refresh: avg {sum(allocs) / len(allocs):.0f} B  max {worst_alloc:.0f} B")
    print("audio/haptic log:")
    for line in list(sim.M.log.values()):
        print("  ", line)

    # theme gallery at the 'flying' moment
    for i, name in enumerate(THEMES, start=1):
        s = Sim(theme=i)
        tt = 0
        while tt <= 2000:
            s.M.now = tt
            scenario(s, tt / 100)
            s.widget.refresh(s.ctx)
            tt += 5
        render(s.frame()[2], s.w, s.h, s.scale).save(os.path.join(OUT, f"800_theme_{name.lower()}.png"))

    # other zone sizes
    for (w, h, sc, tag) in [(800, 480, 1.375, "800_navy"), (225, 98, 1.0, "compact_dark"), (392, 170, 1.0, "half_light")]:
        theme = 3 if "navy" in tag else 2 if "light" in tag else 1
        s = Sim(w, h, sc, theme=theme)
        tt = 0
        while tt <= 2000:
            s.M.now = tt
            scenario(s, tt / 100)
            s.widget.refresh(s.ctx)
            tt += 5
        render(s.frame()[2], w, h, sc).save(os.path.join(OUT, f"{tag}.png"))
    # attitude poses (like the firmware mockup: level, +25/+8, -45/-15, steep)
    for roll, pitch, tag in [(0, 0, "level"), (25, 8, "r25_p8"), (-45, -15, "rm45_pm15"), (80, 30, "r80_p30")]:
        s = Sim()
        tt = 0
        while tt <= 1000:
            s.M.now = tt
            scenario(s, tt / 100)
            s.widget.refresh(s.ctx)
            tt += 5
        s.set("Roll", math.radians(roll)); s.set("Ptch", math.radians(-pitch))
        s.widget.refresh(s.ctx)
        render(s.frame()[2], s.w, s.h, s.scale).save(os.path.join(OUT, f"att_{tag}.png"))

    ok = power_off_test()
    print("screenshots:", OUT)
    return 0 if max(worst_ref, worst_refs) < EDGE_LIMIT and ok else 1


def power_off_test():
    """Model switched off after landing: telemetry-lost alert must stop after 3 bursts."""
    s = Sim()
    tt = 0
    while tt <= 90 * 100:
        s.M.now = tt
        if tt <= 20 * 100:
            scenario(s, tt / 100)
        else:
            s.M.linked = False
        s.widget.refresh(s.ctx)
        tt += 5
    log = [l for l in s.M.log.values() if float(l.split("s ")[0]) > 20]
    tones = [l for l in log if "tone 400" in l]
    buzz = [l for l in log if "haptic" in l]
    ok = len(tones) == 3 and len(buzz) == 9 and all(l.split("haptic ")[1].startswith("8/30") for l in buzz)
    print(f"power-off test: {len(tones)} lost alerts, {len(buzz)} haptic pulses in 70 s -> {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    sys.exit(run())
