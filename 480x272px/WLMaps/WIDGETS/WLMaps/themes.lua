-- WL Maps widget - themes: semantic color tokens, 0xRRGGBB.
-- Horizon colors of Dark/Light/Navy match the WingLabs attitude indicator firmware.
-- Add a theme here and append its name to THEME_NAMES in main.lua.

local THEMES = {
  { -- 1 Dark
    bg = 0x0E1116, surface = 0x1A1F27, border = 0x2A313C,
    text = 0xE8ECF1, muted = 0x8A94A3, accent = 0x3DA9FC,
    ok = 0x2ECC71, warn = 0xF5A623, crit = 0xFF4D4F, onPill = 0x0E1116,
    sky = 0x0078D2, ground = 0x915028, horizon = 0xF0F6FA, ladder = 0xF0F6FA,
    aircraft = 0xFFD642, ink = 0x070F17,
    stripBg = 0x0A141E, stripLine = 0x49CBE1, stripDiv = 0x2A3E4D, stripMuted = 0x9AB8C8,
    mapBg = 0x0B1620, mapRing = 0x2A3E4D, mapTrail = 0x49CBE1,
  },
  { -- 2 Light
    bg = 0xEEF1F5, surface = 0xFFFFFF, border = 0xD5DAE1,
    text = 0x14181F, muted = 0x5E6876, accent = 0x0A6CDB,
    ok = 0x1E9E55, warn = 0xC77700, crit = 0xD62C2C, onPill = 0xFFFFFF,
    sky = 0x0078D2, ground = 0x915028, horizon = 0xF0F6FA, ladder = 0xF0F6FA,
    aircraft = 0xFFD642, ink = 0x070F17,
    mapBg = 0xF4F7FA, mapRing = 0xC9D2DC, mapTrail = 0x0A6CDB,
  },
  { -- 3 Navy
    bg = 0x0A1628, surface = 0x11223D, border = 0x1F3A63,
    text = 0xE6EEF8, muted = 0x8FA6C4, accent = 0x4FC3F7,
    ok = 0x4ADE80, warn = 0xFBBF24, crit = 0xF87171, onPill = 0x0A1628,
    sky = 0x0078D2, ground = 0x915028, horizon = 0xF0F6FA, ladder = 0xF0F6FA,
    aircraft = 0xFFD642, ink = 0x070F17,
    stripBg = 0x0A141E, stripLine = 0x49CBE1, stripDiv = 0x2A3E4D, stripMuted = 0x9AB8C8,
    mapBg = 0x0C1B30, mapRing = 0x264A78, mapTrail = 0x4FC3F7,
  },
  { -- 4 Sunlight (max contrast for direct sun)
    bg = 0x000000, surface = 0x000000, border = 0xFFFFFF,
    text = 0xFFFFFF, muted = 0xFFFF00, accent = 0x00FFFF,
    ok = 0x00FF00, warn = 0xFFFF00, crit = 0xFF2020, onPill = 0x000000,
    sky = 0x0050FF, ground = 0x8B4513, horizon = 0xFFFFFF, ladder = 0xFFFFFF,
    aircraft = 0xFFFF00, cardLine = 0xFFFFFF, ink = 0x000000,
    mapBg = 0x000000, mapRing = 0x9A9A9A, mapTrail = 0x00FFFF,
  },
  { -- 5 Night (red only, preserves night vision)
    bg = 0x000000, surface = 0x140404, border = 0x3A0A0A,
    text = 0xE53935, muted = 0x8B1E1E, accent = 0xFF5252,
    ok = 0xC62828, warn = 0xFF6F00, crit = 0xFF1744, onPill = 0x000000,
    sky = 0x2A0808, ground = 0x120303, horizon = 0xFF5252, ladder = 0xB71C1C,
    aircraft = 0xFFAB40, ink = 0x000000,
    mapBg = 0x000000, mapRing = 0x3A0A0A, mapTrail = 0xFF5252,
  },
  { -- 6 Carbon (neutral graphite, orange accent)
    bg = 0x141414, surface = 0x222222, border = 0x383838,
    text = 0xF2F2F2, muted = 0x9A9A9A, accent = 0xFF8A1F,
    ok = 0x3DDC84, warn = 0xFFC93C, crit = 0xFF5252, onPill = 0x141414,
    sky = 0x0078D2, ground = 0x915028, horizon = 0xF0F6FA, ladder = 0xF0F6FA,
    aircraft = 0xFFD642, ink = 0x070F17,
    stripBg = 0x0F0F0F, stripLine = 0xFF8A1F, stripDiv = 0x383838, stripMuted = 0xB5B5B5,
    mapBg = 0x101010, mapRing = 0x3A3A3A, mapTrail = 0xFF8A1F,
  },
}

-- Resolve a theme index into EdgeTX color flags (done once per theme change).
return function(index)
  local src = THEMES[index] or THEMES[1]
  local t = {}
  for k, v in pairs(src) do
    t[k] = lcd.RGB(v)
  end
  return t
end
