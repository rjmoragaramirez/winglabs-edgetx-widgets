-- WL Avionics widget - alerts: one prioritized banner for the UI plus edge-triggered audio/haptic
-- with per-alert cooldowns (never more than one sound burst per cycle).
-- A repeating alert fires at most MAX_REPEAT times per episode; it re-arms when its
-- condition clears (e.g. telemetry lost after the model is switched off stops after 3).

local floor = math.floor
local MAX_REPEAT = 3
-- playHaptic units: duration in 10 ms steps (+ radio "haptic length" offset), pause in 5 ms steps
local PULSE, GAP = 8, 30   -- ~80 ms buzz, ~150 ms gap

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
    local buzz = o.haptic
    local armed = t.armed
    local lost = t.everLinked and not t.linked
    local cell = t.cellV
    local haveBatt = t.linked and t.volt > 0
    local crit = haveBatt and cell > 0 and cell <= o.cellCrit
    local low = haveBatt and cell > 0 and cell <= o.cellWarn
    local fs = t.fm == "!FS!"
    local high = armed and o.altWarn > 0 and floor(t.alt * (t.imperial and 3.28084 or 1)) >= o.altWarn
    local weak = t.linked and t.lq > 0 and t.lq < 50

    -- Banner (highest priority wins)
    if lost then a.banner, a.sev = "TELEMETRY LOST", 3
    elseif fs then a.banner, a.sev = "FAILSAFE", 3
    elseif crit then a.banner, a.sev = "BATTERY CRITICAL", 3
    elseif low then a.banner, a.sev = "BATTERY LOW", 2
    elseif high then a.banner, a.sev = "ALTITUDE", 2
    elseif weak then a.banner, a.sev = "WEAK LINK", 2
    elseif armed and not t.fix then a.banner, a.sev = "NO GPS FIX", 2
    else a.banner, a.sev = "", 0 end
    a.show = a.sev > 0

    -- Arm / disarm
    local wasArmed = was.armed or false
    if armed ~= wasArmed then
      if sound then
        if armed then playTone(800, 120, 40, PLAY_NOW, 400) else playTone(1200, 120, 40, PLAY_NOW, -400) end
      end
      if buzz then pulses(armed and 2 or 1) end
      was.armed = armed
    end

    -- Flight mode change while armed: short chirp
    if armed and wasArmed and was.mode ~= t.fm and sound then
      playTone(1500, 60, 30, PLAY_NOW)
    end
    was.mode = t.fm

    -- Telemetry lost / regained
    if lost then
      if due("lost", now, 500) then
        if sound then playTone(400, 300, 100, PLAY_NOW) end
        if buzz then pulses(3) end
      end
    elseif was.lost then
      clear("lost")
      if sound then playTone(1800, 80, 20, PLAY_NOW) end
    end
    was.lost = lost
    if lost then return end -- remaining alerts need live data

    if fs then
      if due("fs", now, 300) then
        if sound then playTone(2500, 200, 100, PLAY_NOW) end
        if buzz then pulses(3) end
      end
    else
      clear("fs")
    end

    -- Battery: speak cell voltage (radio voice) with cooldowns
    if crit then
      if due("crit", now, 1000) then
        if sound then playNumber(floor(cell * 100 + 0.5), UNIT_VOLTS, PREC2) end
        if buzz then pulses(3) end
      end
    elseif low then
      clear("crit")
      if due("low", now, 3000) and sound then
        playNumber(floor(cell * 100 + 0.5), UNIT_VOLTS, PREC2)
      end
    else
      clear("crit"); clear("low")
    end

    if high then
      if due("alt", now, 1000) and sound then
        playNumber(floor(t.alt * (t.imperial and 3.28084 or 1) + 0.5), t.imperial and UNIT_FEET or UNIT_METERS)
      end
    else
      clear("alt")
    end

    if weak then
      if due("weak", now, 500) and sound then playTone(600, 80, 40, PLAY_NOW) end
    else
      clear("weak")
    end
  end

  return a
end
