-- WL Flight Stats widget - themes: semantic color tokens, 0xRRGGBB.
-- Same six themes as the other WingLabs widgets; s1..s4 = chart series colors
-- (voltage, current, altitude, speed). Add a theme here and append its name to THEME_NAMES in main.lua.

local THEMES = {
  { -- 1 Dark
    bg = 0x0E1116, surface = 0x1A1F27, border = 0x2A313C,
    text = 0xE8ECF1, muted = 0x8A94A3, accent = 0x3DA9FC,
    ok = 0x2ECC71, warn = 0xF5A623, crit = 0xFF4D4F, onPill = 0x0E1116,
    s1 = 0x2ECC71, s2 = 0xF5A623, s3 = 0x3DA9FC, s4 = 0xC08CFF, fill = 18,
  },
  { -- 2 Light
    bg = 0xEEF1F5, surface = 0xFFFFFF, border = 0xD5DAE1,
    text = 0x14181F, muted = 0x5E6876, accent = 0x0A6CDB,
    ok = 0x1E9E55, warn = 0xC77700, crit = 0xD62C2C, onPill = 0xFFFFFF,
    s1 = 0x1E9E55, s2 = 0xC77700, s3 = 0x0A6CDB, s4 = 0x7B4FD6, fill = 18,
  },
  { -- 3 Navy
    bg = 0x0A1628, surface = 0x11223D, border = 0x1F3A63,
    text = 0xE6EEF8, muted = 0x8FA6C4, accent = 0x4FC3F7,
    ok = 0x4ADE80, warn = 0xFBBF24, crit = 0xF87171, onPill = 0x0A1628,
    s1 = 0x4ADE80, s2 = 0xFBBF24, s3 = 0x4FC3F7, s4 = 0xC4A5FF, fill = 18,
  },
  { -- 4 Sunlight (max contrast for direct sun)
    bg = 0x000000, surface = 0x000000, border = 0xFFFFFF,
    text = 0xFFFFFF, muted = 0xFFFF00, accent = 0x00FFFF,
    ok = 0x00FF00, warn = 0xFFFF00, crit = 0xFF2020, onPill = 0x000000,
    s1 = 0x00FF00, s2 = 0xFFFF00, s3 = 0x00FFFF, s4 = 0xFF40FF, fill = 30,
    cardLine = 0xFFFFFF, grid = 0x606060,
  },
  { -- 5 Night (red only, preserves night vision)
    bg = 0x000000, surface = 0x140404, border = 0x3A0A0A,
    text = 0xE53935, muted = 0x8B1E1E, accent = 0xFF5252,
    ok = 0xC62828, warn = 0xFF6F00, crit = 0xFF1744, onPill = 0x000000,
    s1 = 0xE53935, s2 = 0xFF6F00, s3 = 0xFF5252, s4 = 0xFFAB40, fill = 18,
  },
  { -- 6 Carbon (neutral graphite, orange accent)
    bg = 0x141414, surface = 0x222222, border = 0x383838,
    text = 0xF2F2F2, muted = 0x9A9A9A, accent = 0xFF8A1F,
    ok = 0x3DDC84, warn = 0xFFC93C, crit = 0xFF5252, onPill = 0x141414,
    s1 = 0x3DDC84, s2 = 0xFFC93C, s3 = 0xFF8A1F, s4 = 0x5AB4FF, fill = 18,
  },
}

local floor = math.floor

-- a + (b - a) * pct / 100 per channel (chart area fill = series color faded into the card).
-- Plain arithmetic: EdgeTX runs Lua 5.2 (no bitwise operators).
local function mix(a, b, pct)
  local r, m = 0, 65536
  for _ = 1, 3 do
    local ca, cb = floor(a / m) % 256, floor(b / m) % 256
    r = r + floor(ca + (cb - ca) * pct / 100 + 0.5) * m
    m = m / 256
  end
  return floor(r)
end

-- Resolve a theme index into EdgeTX color flags (done once per theme change).
return function(index)
  local src = THEMES[index] or THEMES[1]
  local t = {}
  for k, v in pairs(src) do
    if k ~= "fill" then t[k] = lcd.RGB(v) end
  end
  t.grid = lcd.RGB(src.grid or src.border)
  for i = 1, 4 do
    t["f" .. i] = lcd.RGB(mix(src.surface, src["s" .. i], src.fill))
  end
  return t
end
