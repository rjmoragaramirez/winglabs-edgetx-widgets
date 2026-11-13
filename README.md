# WingLabs EdgeTX Widgets: INAV telemetry, attitude indicator, moving map and flight statistics for color radios

*WingLabs · October 2026 · updated November 2026*

**Download:** [github.com/rjmoragaramirez/winglabs-edgetx-widgets](https://github.com/rjmoragaramirez/winglabs-edgetx-widgets) (free and open source, MIT license)

![WL Avionics on a TX16S MK2](article_images/wl_avionics.png)

When you fly an INAV aircraft over ELRS, your radio already receives everything that matters:
battery, link quality, GPS position, altitude, speed, heading and attitude. The WingLabs EdgeTX
widgets turn that stream into a clean, readable cockpit on the radio screen: a full-screen
dashboard with an attitude indicator, a moving map with a satellite photo of your flying field,
alerts that tell you what you need to know without nagging you, and a statistics page for every
flight once you land.

There are four widgets. The three flight widgets share the same telemetry engine, alerts and
themes and differ in what sits in the center of the screen; the fourth, WL Flight Stats, records
each flight and shows its charts after landing:

| Widget | Center of the screen | Best for |
|---|---|---|
| **WL Attitude Ind** | Large attitude indicator with ROLL/PITCH readout | Line-of-sight flying, aerobatics, checking the attitude at a glance |
| **WL Avionics** | Attitude indicator on top, moving map below | General flying: everything on one screen |
| **WL Maps** | Full-height moving map | FPV and longer flights, orientation and finding the model |
| **WL Flight Stats** | Voltage, current, altitude and speed charts of the last flight, max altitude and max speed | Reviewing each flight after landing; keeps the last 8 flights per model |

Each one comes in two builds: **TX16S MK2** (480×272) and **TX16S MK3** (800×480).

---

## 1. What is on the screen

![WL Attitude Ind](article_images/wl_attitude_ind.png)

All three flight widgets share the same frame around the center area:

- **Top bar**
  - **Flight mode pill**, colored by severity: ANGLE, HORIZON, ACRO, MANUAL, ALT HOLD, POS HOLD,
    CRUISE, COURSE HOLD, LOITER, WAYPOINT, RTH, LANDING, TURTLE, FAILSAFE, WAIT GPS, NOT READY and so on.
  - **State**: ARMED, DISARMED or NO LINK.
  - **Flight timer**: runs while armed and keeps running if the link drops.
  - **RSSI and TX power**, plus **link quality** (LQ), colored green, amber or red.
- **Battery card**: cell voltage in large digits, pack voltage, cell count (auto-detected or
  fixed), percentage with a bar, current and consumed mAh.
- **Altitude card**: altitude and vertical speed.
- **Ground speed card**.
- **Timer 1 card**: the model's Timer 1 as mm:ss (h:mm:ss after an hour), or OFF when the timer
  is disabled. A countdown timer turns amber in its last 60 seconds and red at zero, then shows the
  time over with a minus sign.
- **Home card**: distance to home, GPS satellites (green once there is a fix with 6 or more satellites) and an arrow that points
  home relative to the aircraft's heading.

Units are **imperial** (ft, mph, mi) by default, or metric.

When the link is lost, the last values stay on screen, dimmed. You keep the last known position,
distance and altitude, which is exactly what you need to walk to the model.

### The attitude indicator

![Attitude indicator poses](article_images/attitude_poses.png)

The attitude indicator has the same look as the WingLabs attitude indicator firmware:

- sky and earth with a white horizon line outlined in dark;
- a pitch ladder every 5°, with solid marks above the horizon, dashed marks below and numbers every 10°;
- a bank scale with ticks at 10, 20, 30, 45, 60 and 80°, and a gold roll pointer;
- gold reference wings with downturned tips and a center chevron;
- a heading box, and in WL Attitude Ind a ROLL/PITCH strip with large digits.

Everything is drawn with vector lines, so it stays smooth and light on the radio's processor.

### The moving map

![WL Maps](article_images/wl_maps.png)

The map is **home-centered and north-up**:

- **Home** is the green circle in the middle. It is set automatically when you arm with a GPS fix.
- **The aircraft** is a gold arrow pointing in the direction of travel, with a thin line back to home.
- **The trail** of the flight is drawn in cyan. It is cleared when you arm again.
- **Range rings** show the scale (100 ft, 200 ft, 500 ft, 1000 ft … 20 mi, or 50 m … 50 km). The map
  **zooms automatically** so the whole flight always fits. It zooms out immediately and zooms back
  in only when there is room to spare, so the scale does not flicker.
- **HDG** shows the current heading. Before arming, the map shows "HOME SET ON ARM".

### Satellite photo of your flying field

![Photo map close-up](article_images/map_photo_zoom.png)

Under the map you can show an aerial photo of your field (USA only):

- The imagery is **USGS NAIP**: US public domain, about 60 cm per pixel.
- A small PC tool downloads it once and cuts it into tiles at **exactly the screen resolution of
  every map zoom step**, so the radio never has to scale an image.
- On the radio, at most four tiles are on screen at a time. EdgeTX keeps up to eight decoded images
  in memory, so each tile is read from the SD card once and the next one is loaded only when the
  model crosses into it.
- Over the photo the rings turn white and the labels get a dark plate so they stay readable.
- Outside the photo area, with metric units or with the photo switched off, you simply get the
  vector map.

### Alerts that do not nag

![Alert states](article_images/alert_states.png)

One banner shows the most important alert at any moment, in this priority order:

| Alert | When | Sound and haptic |
|---|---|---|
| TELEMETRY LOST | The link drops after it was established | 3 short pulses |
| FAILSAFE | INAV reports failsafe | 3 short pulses |
| BATTERY CRITICAL | Cell voltage at or below *CellCrit* | 3 short pulses |
| BATTERY LOW | Cell voltage at or below *CellWarn* | Banner only |
| ALTITUDE | Armed and above *AltWarn* | High tone + altitude spoken |
| LOW ALTITUDE | Armed, back below *AltLow* after climbing above it | Low tone + altitude spoken + 2 short pulses |
| WEAK LINK | Link quality below 50 % | Banner only |
| NO GPS FIX | Armed without a GPS fix | Banner only |

- **Only four things make a sound**, so the radio stays quiet unless it matters:
  - **GPS**: a rising tone when the fix is acquired, a falling tone if it drops while armed (a fix
    change must last 2 seconds, so satellites hovering at the limit do not chatter);
  - **Battery every 10 %** while armed: "90 percent" ... "10 percent". The
    percentage comes from the flight controller (*Bat%*) or, without it, from a LiPo curve on the
    cell voltage smoothed over about 3 seconds, so a punch of throttle does not trigger a call;
  - **Altitude ceiling** (*AltWarn*): a high tone and the altitude, at most three times;
  - **Low altitude** (*AltLow*): a low tone and the altitude, once, only after you have climbed
    above it, so the take-off stays quiet.
- Everything else (arming, flight modes, telemetry lost, failsafe, battery low/critical, weak link)
  is shown on the banner and, for the important ones, felt as **short haptic pulses** of about
  80 ms: two when arming, one when disarming, three for an alert. A repeating alert pulses at most
  three times per episode; switch the model off after landing and you feel three, then nothing.
- The numbers are spoken by the **radio's own voice pack**: same language and volume as the rest
  of the radio's announcements, nothing extra to copy. *Sounds* chooses **Voice** (tones and
  numbers), **Tones** (tones only) or **Off**.

### Themes

![Themes](article_images/themes.png)

There are six themes:

- **Dark**: the default.
- **Light**.
- **Navy**.
- **Sunlight**: black and white with saturated colors, for direct sun.
- **Night**: red only, to preserve night vision.
- **Carbon**: neutral graphite with an orange accent.

Dark, Light, Navy and Carbon use the same sky and earth colors as the WingLabs attitude indicator.

In a small screen zone the widget switches to a compact layout with flight mode, cell voltage,
altitude, link quality and home distance:

![Compact layout](article_images/compact.png)

### Flight statistics

![WL Flight Stats](article_images/wl_flight_stats.png)

**WL Flight Stats** records the flight in the background while the model is armed, even while
another screen is shown. When you disarm, its page shows:

- four charts over the flight time: **voltage** (with the sag under load), **current**,
  **altitude** and **ground speed**, with a dot on the altitude and speed peaks;
- **max altitude** and **max speed**, with the moment they were reached;
- used mAh, the minimum cell voltage and the maximum distance from home;
- the flight time, date and time of the landing.

The last **8 flights of each model** are kept on the SD card. Open the widget in full screen and
turn the roller, or tap the left or right half of the screen, to browse older flights. Arming on
the bench for less than 20 seconds (the *MinFlight* option) is not saved. If the link is lost
while armed for 20 seconds, for example when you unplug the battery without disarming, the
flight is saved up to that point.

In a small zone it shows max altitude, max speed, used mAh and minimum cell of the last flight.

---

## 2. Requirements

| | TX16S MK2 build | TX16S MK3 build |
|---|---|---|
| Screen | 480×272 | 800×480 |
| Firmware | **EdgeTX 2.11 or later** (2.11.2+ recommended) | **EdgeTX 2.12 or later** (first release supporting the MK3) |
| Project folder | `widgets_edgetx\480x272px\` | `widgets_edgetx\800x480px\` |

- **Link**: ExpressLRS (CRSF telemetry).
- **Flight controller**: INAV, sending CRSF telemetry: attitude, GPS, battery, flight mode and so on.
- **SD card**: a few hundred KB for the widgets. The optional photo map needs about 25 MB on the MK2
  and about 70 MB on the MK3 per field (5-mile radius).

The widget reads these sensors, which INAV creates over CRSF: RQly, 1RSS, TPWR, RxBt, Curr, Capa,
Bat%, FM, GPS, GSpd, Hdg, Alt, Sats, Ptch, Roll, Yaw and VSpd.

---

## 3. Installing on the radio

### Step 1: copy the widgets to the SD card

Connect the radio to the PC in USB storage mode, or take the SD card out, and copy the widget
folders into `/WIDGETS/` on the card. Use the build for your radio:

| Widget | Copy this folder (from `480x272px\` or `800x480px\`) | To the SD card |
|---|---|---|
| WL Attitude Ind | `WLAttitudeInd\WIDGETS\WLAttitudeInd` | `/WIDGETS/WLAttitudeInd/` |
| WL Avionics | `WLAvionics\WIDGETS\WLAvionics` | `/WIDGETS/WLAvionics/` |
| WL Maps | `WLMaps\WIDGETS\WLMaps` | `/WIDGETS/WLMaps/` |
| WL Flight Stats | `WLFlightStats\WIDGETS\WLFlightStats` | `/WIDGETS/WLFlightStats/` |

Install any combination. Do not rename the folders to anything longer: EdgeTX
silently ignores widget folders with names over 13 characters. Copy WL Flight Stats together with
its `logs` folder: the flights are saved there, and EdgeTX Lua scripts cannot create folders.

### Step 2: discover the telemetry sensors

With the model powered and the link up, open *Model → Telemetry* and run **Discover new sensors**.
Wait until the list stops growing (GPS and attitude sensors appear too), then stop discovery.
If a sensor is missing later, the widget looks for it again every 2 seconds, so you do not need
to restart anything.

### Step 3: create a full-screen page

1. Open *Model → Screens* (*Screens setup*) and add a screen, or pick an existing one.
2. Choose the layout **Full screen** (one zone).
3. In the layout options, **turn off Top bar, Sliders, Trims and Flight mode**.
   This matters: with the top bar on, or with the "App mode" layout, EdgeTX draws its own menu
   button (the EdgeTX logo) over the top-left corner of the widget. You still reach the menus with
   the SYS and MDL keys.
4. Tap the zone and select **WL Attitude Ind**, **WL Avionics**, **WL Maps** or **WL Flight Stats**.

Repeat with more screens if you want more than one widget; swipe between them in flight.

### Step 4: set the widget options

Open *Screens setup*, select the widget's zone and choose *Widget settings*:

| Option | Values | Default | Notes |
|---|---|---|---|
| Theme | Dark, Light, Navy, Sunlight, Night, Carbon | Dark | |
| Units | Imperial, Metric | Imperial | Metric map scales are 30 m, 61 m, 152 m... (the same rings as 100, 200, 500 ft, so the photo works in both) |
| Cells | 0 = auto, 1–14 | 0 | Auto-detects the cell count when disarmed |
| CellWarn | 300–420 | 350 | Centivolts per cell: 350 = 3.50 V (BATTERY LOW) |
| CellCrit | 280–400 | 330 | 330 = 3.30 V (BATTERY CRITICAL) |
| AltWarn | 0–5000 | 400 | In ft or m; 0 = off |
| Sounds | Voice, Tones, Off | Voice | GPS, battery %, altitude ceiling and low altitude only. Voice = tones + numbers in the radio's voice; Tones = tones only |
| Haptic | on/off | on | Vibration pulses |
| MapPhoto | on/off | on | WL Avionics and WL Maps only |
| AltLow | 0–1000 | 50 | In ft or m (15 for metric); low-altitude call after climbing above it; 0 = off |

WL Flight Stats has fewer options: Theme, Units and Cells as above, plus **MinFlight** (5–300 s,
default 20): how long the model must be armed for the flight to be saved.

How strongly the radio vibrates also depends on *Radio Setup → Haptic* (length and strength).

### Step 5 (optional): the satellite photo map

Photo tiles are made on a PC for the fields you fly at (anywhere in the USA). You need Python 3
with the Pillow package. From the `WLAvionics` folder of your build (`480x272px\WLAvionics` for the
MK2, `800x480px\WLAvionics` for the MK3), run, with your field's coordinates:

```
python tools/maptiles/make_field.py --name ama --lat 40.1666 --lon -85.3195 --radius-mi 5
```

(The example is the AMA International Aeromodeling Center in Muncie, Indiana.)

- The name can be up to 8 letters or digits.
- It makes the tile sets for both map widgets of that screen size and downloads only what is
  missing, so it can be stopped and restarted.
- Run it once per field.
- For a small field you want sharp at every zoom, add `--fine-mi 2`: the three closest zoom
  steps then cover 2 miles around the field instead of the default radius.
- A 5-mile radius takes about 25 MB on the MK2 and about 70 MB on the MK3.

Then copy `tools\maptiles\out\WLMAP` to the **root** of the SD card, so it ends up as `/WLMAP/`.
WL Avionics and WL Maps share this folder.

On the radio, the widget picks the field automatically: when you arm, it uses the nearest field
whose photo area contains home. At each zoom it uses the nearest step whose photo fills the whole
map, so you never see half a photo.

---

## 4. In flight

1. **Power up and wait for GPS.** The pill shows WAIT GPS and the home card shows the satellite count.
2. **Arm.** You feel two pulses; the timer starts and home is set with the
   current GPS position.
3. **Fly.** The map zooms out as you go farther, the trail draws your path and the home arrow and
   distance guide you back.
4. **Alerts** appear as a banner, with voice and pulses for the important ones, at most three
   times each.
5. **Land and disarm.** One pulse. Switch the model off: three "telemetry lost"
   pulses and then nothing. The last position stays on screen.
6. **Review the flight.** Swipe to the WL Flight Stats screen: the flight you just landed is
   already there.

---

## 5. Troubleshooting

| Symptom | Fix |
|---|---|
| The EdgeTX logo covers the top-left corner | Use the *Full screen* layout with Top bar off, not *App mode* (see step 3). |
| The widget is not in the list | Check the folder is `/WIDGETS/<name>/main.lua` and that the name is not longer than 13 characters. |
| "--" everywhere, NO LINK | No telemetry: check the ELRS link and run *Discover new sensors* again. |
| No attitude or map | INAV is not sending attitude/GPS over CRSF, or the sensors were not discovered. |
| Horizon moves the wrong way | Pitch/roll signs can be flipped in `telem.lua` (`PITCH_SIGN`, `ROLL_SIGN`). |
| No satellite photo | `/WLMAP/` missing or in the wrong place (it must be at the SD root), MapPhoto off, metric units, home outside the photo area, or tiles made for the other radio model. |
| The MK3 widgets do not appear | The MK3 build needs EdgeTX 2.12 or later. |
| WL Flight Stats does not save flights | The `logs` folder must exist in `/WIDGETS/WLFlightStats/`, the flight must last longer than *MinFlight*, and the FM sensor must be discovered (it gives the arm state). |
| Older flights cannot be selected | EdgeTX only passes touch and roller events to a widget in full screen: open it full screen first. |

---

## 6. Under the hood

The widgets are written in Lua for EdgeTX's LVGL user interface and are built to stay responsive
for a whole flight:

- Plain `.lua` files: EdgeTX compiles and caches them itself.
- Every module is loaded once at start-up; nothing is read from the SD card during normal flight
  (photo tiles excepted, and only when crossing into a new tile). WL Flight Stats writes one small
  file when a flight ends.
- No manual garbage collection and almost no garbage per frame (under 1 KB).
- Telemetry is polled at a fixed rate and screen text is formatted only when a value changes.
- The attitude indicator and map use vector lines only, with preallocated tables.
- Colors come from semantic theme tokens, so new themes are easy to add.
- WL Flight Stats keeps memory bounded on flights of any length: samples are grouped into
  intervals that keep the lowest voltage and the highest current, altitude and speed, and the
  intervals double in length when the buffer fills. Its page is built in stages, one chart per
  frame, so no call comes near the processor limit.
- No global variables, and the model's timers are only read (for the Timer 1 card), never changed.

Every build has a **desktop simulator**: `tools/sim/run_sim.py`, which needs Python with lupa and
Pillow. It runs the real widget code against a strict model of the EdgeTX API and flies a
synthetic mission: no link, waiting for GPS, armed, RTH, link lost, failsafe and battery critical.
It checks:

- the processor budget per frame (EdgeTX allows 20,000 instructions per call; the widgets use
  well under half);
- memory allocation per frame;
- how often photo tiles are loaded;
- that the aircraft arrow keeps its shape;
- the "model switched off" alert sequence.

It also renders screenshots like the ones in this article.

![WL Avionics on the TX16S MK3](article_images/mk3_avionics.png)

*WL Avionics on the TX16S MK3 (800×480).*

---

## 7. Project status

| Widget | Version | Status |
|---|---|---|
| WL Attitude Ind | 0.4.0 | Version 0.2 flown on a TX16S MK2; sound call-outs and the Timer 1 card confirmed on a TX16S MK2 |
| WL Avionics | 0.4.0 | Flown on a TX16S MK2; sound call-outs, the satellite photo (imperial and metric) and the Timer 1 card confirmed on a TX16S MK2 |
| WL Maps | 0.3.0 | Flown on a TX16S MK2; sound call-outs, the satellite photo (imperial and metric) and the Timer 1 card confirmed on a TX16S MK2 |
| WL Flight Stats | 0.1.0 | Flown on a TX16S MK2: flights saved after landing, charts, history browsing and reload after a power cycle confirmed |
| MK3 builds | same versions | Validated in the simulator at 800×480; waiting for hardware |

Still to confirm on the radio: the exact font sizes, how the vibration pulses feel, tile loading
time when crossing photo tiles, and that the aircraft position over the photo matches the ground.

Ideas for next versions: log playback.

---

## Repository layout

```
480x272px/              TX16S MK2 builds (EdgeTX 2.11+)
  WLAttitudeInd/        WIDGETS/WLAttitudeInd  + tools/sim
  WLAvionics/           WIDGETS/WLAvionics     + tools/sim + tools/maptiles (photo tile generator)
  WLMaps/               WIDGETS/WLMaps         + tools/sim
  WLFlightStats/        WIDGETS/WLFlightStats  + tools/sim
800x480px/              TX16S MK3 builds (EdgeTX 2.12+), same structure
article_images/         images used in this document
```

Each project folder has its own README with the details of that widget.

## License

MIT, see [LICENSE](LICENSE). Satellite imagery used by the photo map is USGS NAIP (US public
domain); it is downloaded by the tile generator and not included in this repository.
