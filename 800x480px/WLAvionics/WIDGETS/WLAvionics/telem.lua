-- WL Avionics widget - telemetry: CRSF/ELRS sensor discovery, polling and derived values (INAV).
-- All display strings are formatted here at a fixed rate and only when the value
-- changes, so the UI callbacks just return cached strings (no per-frame garbage).

local SENSORS = {
  rqly = "RQly", rss1 = "1RSS", tpwr = "TPWR",
  volt = "RxBt", curr = "Curr", capa = "Capa", pct = "Bat%",
  fm = "FM", gps = "GPS", gspd = "GSpd", hdg = "Hdg", alt = "Alt", sats = "Sats",
  ptch = "Ptch", roll = "Roll", yaw = "Yaw", vspd = "VSpd",
}
local FALLBACK = { volt = "BtRx" }

-- INAV CRSF flight mode -> label, severity (0 ok, 1 info, 2 warn, 3 crit)
local MODES = {
  OK = { "READY", 0 }, WAIT = { "WAIT GPS", 2 }, ["!ERR"] = { "NOT READY", 3 },
  ["!FS!"] = { "FAILSAFE", 3 }, LAND = { "LANDING", 2 }, HRST = { "HOME RESET", 2 },
  MANU = { "MANUAL", 1 }, ACRO = { "ACRO", 1 }, ANGL = { "ANGLE", 1 }, HOR = { "HORIZON", 1 },
  ANGH = { "ANGLE HOLD", 1 }, AH = { "ALT HOLD", 1 }, HOLD = { "POS HOLD", 1 },
  LOTR = { "LOITER", 1 }, CRUZ = { "CRUISE", 1 }, CRSH = { "COURSE HOLD", 1 },
  WP = { "WAYPOINT", 1 }, RTH = { "RTH", 2 }, WRTH = { "WP RTH", 2 }, GEO = { "GEOZONE", 2 },
  TURT = { "TURTLE", 2 },
}
local DISARMED = { OK = true, WAIT = true, ["!ERR"] = true, [""] = true }

local PITCH_SIGN = -1   -- INAV sends pitch > 0 = nose down; we want nose up positive
local ROLL_SIGN = 1     -- verify on the bench: right wing down must read positive
local SLOW_TICKS = 10   -- 10 ms ticks -> 10 Hz for non-attitude values
local DISCOVER_TICKS = 200

local floor, abs, sqrt, cos, rad, deg, atan = math.floor, math.abs, math.sqrt, math.cos, math.rad, math.deg, math.atan
local fmt = string.format
local M_PER_DEG = 111319.5

return function()
  local ids, units = {}, {}
  local missing = true
  local nextDiscover, nextSlow = 0, 0
  local last = {}  -- last formatted raw value per key

  local t = {
    linked = false, everLinked = false, armed = false,
    lq = 0, rssi = 0, tpwr = 0,
    volt = 0, cells = 0, cellV = 0, curr = 0, capa = 0, pct = -1,
    fm = "", mode = "NO LINK", sev = 3,
    lat = 0, lon = 0, sats = 0, fix = false, home = nil,
    dist = 0, dn = 0, de = 0, homeRel = 0, spd = 0, alt = 0, vspd = 0, hdg = 0,
    pitch = 0, roll = 0,
    armTime = 0, flown = 0,
    -- unit settings (set from options)
    imperial = true, cellsOpt = 0,
    s = { mode = "NO LINK", lq = "LQ --", radio = "", sats = "SAT --",
          cellV = "-.--V", volt = "--.-V", cells = "", curr = "--.-A", capa = "---- mAh", pct = "",
          alt = "---", altU = "ft", vspd = "", spd = "---", spdU = "mph", dist = "---", distU = "ft",
          hdg = "---", timer = "00:00", state = "NO LINK", roll = "--.-", pitch = "--.-" },
  }

  local function discover()
    missing = false
    for k, name in pairs(SENSORS) do
      if not ids[k] then
        local fi = getFieldInfo(name) or (FALLBACK[k] and getFieldInfo(FALLBACK[k]))
        if fi then
          ids[k], units[k] = fi.id, fi.unit
        else
          missing = true
        end
      end
    end
  end

  local function get(k)
    local id = ids[k]
    if id then return getValue(id) end
    return 0
  end

  local function angle(k)
    local v = get(k)
    if type(v) ~= "number" then return 0 end
    if units[k] ~= UNIT_DEGREE then v = deg(v) end
    return v
  end

  -- Format into t.s[key] only when the change key k differs from last time.
  -- Optional display value d (defaults to k).
  local function put(key, k, pattern, d, e)
    if last[key] ~= k then
      last[key] = k
      t.s[key] = fmt(pattern, d or k, e)
    end
  end

  local function resetFlight()
    t.home, t.dist, t.dn, t.de, t.homeRel, t.flown = nil, 0, 0, 0, 0, 0
    t.flight = (t.flight or 0) + 1  -- map clears its trail when this changes
  end

  local function slow(now)
    local fm = get("fm")
    if type(fm) ~= "string" then fm = "" end
    if t.linked then t.fm = fm else fm = t.fm end  -- keep last known mode while lost

    local wasArmed = t.armed
    -- Without link the arm state is unknown: keep the last one (no false disarm/arm)
    if t.linked then t.armed = not DISARMED[fm] end
    local m = MODES[fm]
    if not t.linked then
      t.mode, t.sev = "NO LINK", 3
    elseif m then
      t.mode, t.sev = m[1], m[2]
    else
      t.mode, t.sev = fm, 1
    end
    t.s.mode = t.mode
    t.s.state = (not t.linked) and "NO LINK" or (t.armed and "ARMED" or "DISARMED")

    -- Flight timer keeps running while armed, even without link
    if t.armed and not wasArmed then
      t.armTime = now
      resetFlight()
    end
    if t.armed then t.flown = (now - t.armTime) / 100 end
    local secs = floor(t.flown)
    if last.timer ~= secs then
      last.timer = secs
      t.s.timer = fmt("%02d:%02d", secs // 60, secs % 60)
    end

    if not t.linked then
      t.lq = 0
      put("lq", 0, "LQ %d%%")
      return -- keep last known values on screen (UI dims them): you need them to find the model
    end

    -- Link
    t.lq, t.rssi, t.tpwr = get("rqly"), get("rss1"), get("tpwr")
    put("lq", t.lq, "LQ %d%%")
    put("radio", t.rssi * 100000 + t.tpwr, "%ddBm  %dmW", t.rssi, t.tpwr)

    -- Battery
    local v = get("volt")
    if v > 0 then
      t.volt = v
      if t.cellsOpt > 0 then
        t.cells = t.cellsOpt
      elseif not t.armed or t.cells == 0 then
        t.cells = math.max(1, math.ceil(v / 4.35))
      end
      t.cellV = v / t.cells
    end
    local k
    if t.cells > 0 then
      k = floor(t.cellV * 100 + 0.5)
      put("cellV", k, "%.2fV", k / 100)
      k = floor(t.volt * 10 + 0.5)
      put("volt", k, "%.1fV", k / 10)
      put("cells", t.cells, "%dS")
    end
    t.curr, t.capa = get("curr"), get("capa")
    k = floor(t.curr * 10 + 0.5)
    put("curr", k, "%.1fA", k / 10)
    put("capa", floor(t.capa), "%d mAh")
    t.pct = ids.pct and get("pct") or -1
    if t.pct >= 0 then put("pct", t.pct, "%d%%") else t.s.pct = "" end

    -- GPS
    t.sats = get("sats")
    local g = get("gps")
    if type(g) == "table" and g.lat and g.lat ~= 0 then
      t.lat, t.lon = g.lat, g.lon
      t.fix = t.sats >= 6
    else
      t.fix = false
    end
    put("sats", t.sats, "SAT %d")

    if t.armed and not t.home and t.fix then t.home = { lat = t.lat, lon = t.lon } end

    -- Home distance and direction (flat earth on deltas, float32 safe)
    if t.home and t.fix then
      local dn = (t.lat - t.home.lat) * M_PER_DEG
      local de = (t.lon - t.home.lon) * M_PER_DEG * cos(rad(t.home.lat))
      t.dn, t.de = dn, de
      t.dist = sqrt(dn * dn + de * de)
      local brgHome = (deg(atan(-de, -dn)) + 360) % 360
      t.homeRel = (brgHome - t.hdg + 360) % 360
    end

    -- Speeds and altitude (sensors: m, m/s, km/h)
    t.alt, t.vspd, t.spd = get("alt"), get("vspd"), get("gspd")
    local imp = t.imperial
    local alt = floor((imp and t.alt * 3.28084 or t.alt) + 0.5)
    put("alt", alt, "%d")
    t.s.altU = imp and "ft" or "m"
    k = floor((imp and t.vspd * 3.28084 or t.vspd) * 10 + 0.5)
    put("vspd", k, imp and "%+.1f ft/s" or "%+.1f m/s", k / 10)
    put("spd", floor((imp and t.spd * 0.621371 or t.spd) + 0.5), "%d")
    t.s.spdU = imp and "mph" or "km/h"
    if imp then
      if t.dist < 1609 then
        put("dist", floor(t.dist * 3.28084 + 0.5), "%d")
        t.s.distU = "ft"
      else
        k = floor(t.dist / 16.09344 + 0.5) + 0.5 -- +0.5 keeps keys distinct from ft
        put("dist", k, "%.2f", (k - 0.5) / 100)
        t.s.distU = "mi"
      end
    else
      if t.dist < 1000 then
        put("dist", floor(t.dist + 0.5), "%d")
        t.s.distU = "m"
      else
        k = floor(t.dist / 10 + 0.5) + 0.5
        put("dist", k, "%.2f", (k - 0.5) / 100)
        t.s.distU = "km"
      end
    end
    if not t.home then t.s.dist, last.dist = "---", nil end
  end

  -- Called every refresh/background cycle. Cheap fast path for attitude.
  function t.poll(now)
    if missing and now >= nextDiscover then
      discover()
      nextDiscover = now + DISCOVER_TICKS
    end

    t.linked = getRSSI() > 0
    if t.linked then t.everLinked = true end

    if t.linked then
      t.pitch = angle("ptch") * PITCH_SIGN
      t.roll = angle("roll") * ROLL_SIGN
      local y = ids.yaw and angle("yaw") or get("hdg")
      t.hdg = (y + 360) % 360
      put("hdg", floor(t.hdg + 0.5) % 360, "%03d")
      local k = floor(t.roll * 10 + 0.5)
      put("roll", k, "%+.1f", k / 10)
      k = floor(t.pitch * 10 + 0.5)
      put("pitch", k, "%+.1f", k / 10)
    end

    if now >= nextSlow then
      nextSlow = now + SLOW_TICKS
      slow(now)
    end
  end

  -- Force rediscovery (model change / sensors deleted)
  function t.rediscover()
    ids, units, missing, nextDiscover = {}, {}, true, 0
  end

  return t
end
