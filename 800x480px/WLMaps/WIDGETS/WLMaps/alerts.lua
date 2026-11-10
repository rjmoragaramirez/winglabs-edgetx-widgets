-- WL Maps widget - alerts: one prioritized banner for the UI, haptic pulses for the important
-- states, and only four sound call-outs: GPS fix/lost, battery every 10 %, altitude ceiling
-- (AltWarn) and low altitude (AltLow). Everything else is banner + haptic only.
-- A repeating alert fires at most MAX_REPEAT times per episode; it re-arms when its
-- condition clears (e.g. telemetry lost after the model is switched off stops after 3).
--
-- Numbers are spoken with the radio's own voice pack (playNumber): same language and volume as
-- the radio's other announcements. Sounds = Tones plays the tones only, without numbers.

local floor, ceil, max = math.floor, math.ceil, math.max
local MAX_REPEAT = 3
-- playHaptic units: duration in 10 ms steps (+ radio "haptic length" offset), pause in 5 ms steps
local PULSE, GAP = 8, 30   -- ~80 ms buzz, ~150 ms gap

local GPS_HOLD = 200       -- ticks a GPS fix change must stay (sats hover around the 6-sat line)
local BATT_HOLD = 300      -- ticks the battery must stay under a 10 % step (throttle sag)
local BATT_EVERY = 10      -- battery smoothing update period, ticks
local BATT_ALPHA = 0.03    -- ~3 s time constant at 10 Hz

-- LiPo per-cell voltage -> remaining %, used only when the FC sends no Bat%
local CURVE = {
  { 4.20, 100 }, { 4.15, 95 }, { 4.11, 90 }, { 4.08, 85 }, { 4.02, 80 }, { 3.98, 75 },
  { 3.95, 70 }, { 3.91, 65 }, { 3.87, 60 }, { 3.85, 55 }, { 3.84, 50 }, { 3.82, 45 },
  { 3.80, 40 }, { 3.79, 35 }, { 3.77, 30 }, { 3.75, 25 }, { 3.73, 20 }, { 3.71, 15 },
  { 3.69, 10 }, { 3.61, 5 }, { 3.27, 0 },
}

local function cellPct(v)
  if v >= CURVE[1][1] then return 100 end
  for i = 2, #CURVE do
    local hi, lo = CURVE[i - 1], CURVE[i]
    if v >= lo[1] then
      return lo[2] + (v - lo[1]) * (hi[2] - lo[2]) / (hi[1] - lo[1])
    end
  end
  return 0
end

-- n short pulses; PLAY_NOW on the first one drops whatever was still queued
local function pulses(n)
  playHaptic(PULSE, GAP, PLAY_NOW)
  for _ = 2, n do playHaptic(PULSE, GAP) end
end

return function()
  local a = { banner = "", sev = 0, show = false }
  local nextAt = {}
  local count = {}
  local was = {}

  -- GPS debounce, battery steps, low-altitude latch
  local gpsState, gpsSince = false, nil
  local battAvg, battNext, battStep, battSince = 0, 0, nil, nil
  local lowArmed, lowAlt = false, false

  local function due(key, now, every)
    local c = count[key] or 0
    if c >= MAX_REPEAT then return false end
    local n = nextAt[key]
    if n == nil or now >= n then
      nextAt[key] = now + every
      count[key] = c + 1
      return true
    end
    return false
  end

  local function clear(key) nextAt[key], count[key] = nil, nil end

  -- t: telemetry state, o: options, now: getTime() ticks (10 ms)
  function a.check(t, o, now)
    local sound = o.alerts
    local talk = sound and o.voice -- Sounds = Voice: numbers in the radio's voice
    local buzz = o.haptic
    local armed = t.armed
    local lost = t.everLinked and not t.linked
    local haveBatt = t.linked and t.volt > 0
    -- Smoothed cell voltage (~3 s): throttle sag must not trip the battery alerts or the 10 % calls
    if haveBatt and t.cellV > 0 and now >= battNext then
      battNext = now + BATT_EVERY
      if battAvg == 0 then battAvg = t.cellV else battAvg = battAvg + (t.cellV - battAvg) * BATT_ALPHA end
    end
    local cell = (battAvg > 0) and battAvg or t.cellV
    local crit = haveBatt and cell > 0 and cell <= o.cellCrit
    local low = haveBatt and cell > 0 and cell <= o.cellWarn
    local fs = t.fm == "!FS!"
    local altD = floor(t.alt * (t.imperial and 3.28084 or 1))
    local high = armed and o.altWarn > 0 and altD >= o.altWarn
    local weak = t.linked and t.lq > 0 and t.lq < 50

    -- Low altitude: latched only after climbing clear of the floor, so take-off stays quiet
    local altLow = o.altLow or 0
    if armed and altLow > 0 and t.linked then
      if altD >= altLow + max(5, altLow // 5) then
        lowArmed, lowAlt = true, false
      elseif lowArmed and altD < altLow then
        lowArmed, lowAlt = false, true
        if sound then playTone(700, 250, 50, PLAY_NOW, -300) end
        if talk then playNumber(altD, t.imperial and UNIT_FEET or UNIT_METERS) end
        if buzz then pulses(2) end
      end
    elseif not armed then
      lowArmed, lowAlt = false, false
    end

    -- Banner (highest priority wins)
    if lost then a.banner, a.sev = "TELEMETRY LOST", 3
    elseif fs then a.banner, a.sev = "FAILSAFE", 3
    elseif crit then a.banner, a.sev = "BATTERY CRITICAL", 3
    elseif low then a.banner, a.sev = "BATTERY LOW", 2
    elseif high then a.banner, a.sev = "ALTITUDE", 2
    elseif lowAlt then a.banner, a.sev = "LOW ALTITUDE", 2
    elseif weak then a.banner, a.sev = "WEAK LINK", 2
    elseif armed and not t.fix then a.banner, a.sev = "NO GPS FIX", 2
    else a.banner, a.sev = "", 0 end
    a.show = a.sev > 0

    -- Arm / disarm: haptic only
    local wasArmed = was.armed or false
    if armed ~= wasArmed then
      if buzz then pulses(armed and 2 or 1) end
      was.armed = armed
      if armed then battStep, battSince = nil, nil end
    end

    -- Telemetry lost: haptic only, at most 3 times
    if lost then
      if due("lost", now, 500) and buzz then pulses(3) end
    else
      clear("lost")
    end
    if lost then return end -- remaining alerts need live data

    if fs then
      if due("fs", now, 300) and buzz then pulses(3) end
    else
      clear("fs")
    end

    -- GPS fix gained / lost (lost is only called while armed)
    if t.linked then
      if t.fix ~= gpsState then
        if not gpsSince then
          gpsSince = now
        elseif now - gpsSince >= GPS_HOLD then
          gpsState, gpsSince = t.fix, nil
          -- rising tone = fix, falling tone = lost
          if t.fix then
            if sound then playTone(1000, 100, 30, PLAY_NOW, 500) end
          elseif armed then
            if sound then playTone(1000, 200, 30, PLAY_NOW, -500) end
          end
        end
      else
        gpsSince = nil
      end
    end

    -- Battery critical: haptic only (the 10 % calls give the sound)
    if crit then
      if due("crit", now, 1000) and buzz then pulses(3) end
    else
      clear("crit")
    end

    -- Battery remaining every 10 %: FC Bat% when present, else smoothed cell voltage estimate
    if armed and haveBatt then
      local pct = t.pct
      if pct < 0 then pct = (battAvg > 0) and cellPct(battAvg) or -1 end
      if pct >= 0 then
        local step = ceil(pct / 10) * 10 -- 100 at 91-100 %, 90 at 81-90 %, ...
        if not battStep then
          battStep = step
        elseif step < battStep then
          if not battSince then
            battSince = now
          elseif now - battSince >= BATT_HOLD then
            battStep, battSince = step, nil
            if step >= 10 and step <= 90 and sound then
              if talk then playNumber(step, UNIT_PERCENT) else playTone(900, 150, 40, PLAY_NOW, -200) end
            end
          end
        else
          battSince = nil
        end
      end
    end

    -- Altitude ceiling (AltWarn): high tone + altitude, at most 3 times per climb above it
    if high then
      if due("alt", now, 1000) and sound then
        playTone(1500, 150, 40, PLAY_NOW, 300)
        if talk then playNumber(altD, t.imperial and UNIT_FEET or UNIT_METERS) end
      end
    else
      clear("alt")
    end
  end

  return a
end
