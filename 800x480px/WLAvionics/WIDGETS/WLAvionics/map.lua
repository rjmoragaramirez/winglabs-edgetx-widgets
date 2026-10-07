-- WL Avionics widget - vector "radar" map: home at the center, north up, aircraft arrow,
-- flight trail, range rings with automatic zoom. Optional satellite photo underneath: tiles
-- made on the PC by tools/maptiles/make_field.py at exactly the pixel size of each zoom step
-- (no scaling on the radio), listed in /WLMAP/fields.lua (read once at start). Each map size
-- (ring radius in px) has its own tile set: /WLMAP/<field>/<ring>/<level>/<col>_<row>.jpg
--
-- Photo tiles: 4 fixed image slots chosen by tile parity (col % 2, row % 2), so adjacent
-- tiles never share a slot and crossing a tile edge swaps only 2 files. EdgeTX's LVGL keeps
-- 8 decoded images cached, so a tile is read from the SD card once, not every frame.
--
-- Two parts:
--  * trail store (created once in create()): samples the position in meters from home at
--    telemetry rate, also while the widget is hidden; survives theme/option rebuilds.
--  * view (created per UI build): projects the trail to pixels for a W x H map area.
--
-- EdgeTX 2.11.0/2.11.1 only redraws a line when its FIRST point changes (bug fixed in 2.11.2),
-- so every dynamic polyline here starts with the aircraft position, which moves whenever the
-- line content changes. A line must also never get fewer than 2 points.

local floor, max, min, abs, sin, cos, rad = math.floor, math.max, math.min, math.abs, math.sin, math.cos, math.rad
local fmt = string.format
local M_PER_DEG = 111319.5
local PHOTO_ROOT = "/WLMAP/"

local ARROW = { { 9, 0 }, { -6, 6 }, { -3, 0 }, { -6, -6 } }  -- forward, right offsets (px)
local MAXP = 60          -- stored trail samples; when full, older half is thinned out
local FT = 0.3048
local STEPS = {
  imperial = { { 100 * FT, "100 ft" }, { 200 * FT, "200 ft" }, { 500 * FT, "500 ft" },
               { 1000 * FT, "1000 ft" }, { 2000 * FT, "2000 ft" }, { 804.672, "0.5 mi" },
               { 1609.344, "1 mi" }, { 3218.688, "2 mi" }, { 8046.72, "5 mi" }, { 16093.44, "10 mi" },
               { 32186.88, "20 mi" } },
  metric = { { 50, "50 m" }, { 100, "100 m" }, { 200, "200 m" }, { 500, "500 m" }, { 1000, "1 km" },
             { 2000, "2 km" }, { 5000, "5 km" }, { 10000, "10 km" }, { 20000, "20 km" },
             { 50000, "50 km" } },
}

return function()
  local tr = { n = {}, e = {}, count = 0, flight = nil, maxN = 0, maxE = 0, minD = 3,
               fields = {}, photo = true, field = nil, fieldFlight = nil }

  local function reset()
    tr.count, tr.maxN, tr.maxE = 0, 0, 0
  end

  -- Keep every other sample (oldest first), always keeping the newest one
  local function thin()
    local n, e, c = tr.n, tr.e, tr.count
    local j = 0
    for i = 1, c - 1, 2 do
      j = j + 1
      n[j], e[j] = n[i], e[i]
    end
    j = j + 1
    n[j], e[j] = n[c], e[c]
    for i = j + 1, c do n[i], e[i] = nil, nil end
    tr.count = j
  end

  -- t: telemetry state. Called every tick (refresh and background).
  function tr.sample(t)
    if t.flight ~= tr.flight then
      tr.flight = t.flight
      reset()
    end
    if not t.home or not t.linked then return end
    local dn, de = t.dn, t.de
    local c = tr.count
    if c > 0 then
      local a, b = dn - tr.n[c], de - tr.e[c]
      if a * a + b * b < tr.minD * tr.minD then return end
    end
    if c >= MAXP then
      thin()
      c = tr.count
    end
    c = c + 1
    tr.n[c], tr.e[c], tr.count = dn, de, c
    tr.maxN, tr.maxE = max(tr.maxN, abs(dn)), max(tr.maxE, abs(de))
  end

  -- W x H map area, LS = lvgl.LCD_SCALE. Returns the view: geometry tables mutated in place + update(t).
  function tr.view(W, H, LS)
    LS = LS or 1
    local M = max(W, H)                       -- canvas margin (line points are unsigned)
    local cx, cy = floor(W / 2), floor(H / 2)  -- home, viewport coords
    local r = max(10, cy - 6)                  -- outer range ring radius
    local fitX, fitY = max(10, cx - 8), max(10, cy - 8)

    local v = {
      M = M, size = W + 2 * M, cx = cx, cy = cy, r = r,
      trail = {}, trailOn = false,
      homeLine = { { 0, 0 }, { 0, 0 } },
      plane = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
      scaleText = "",
    }
    local pool = {}
    for i = 1, MAXP + 1 do pool[i] = { 0, 0 } end
    v.slots, v.photoOn = {}, false
    v.tile = 256                               -- image object size = tile size (no LVGL zoom)
    for _, f in ipairs(tr.fields) do
      local rl = f.rings and f.rings[r]
      if rl then v.tile = rl.tile or f.tile or 256 break end
    end
    for i = 1, 4 do v.slots[i] = { file = "", x = 0, y = 0, on = false, key = nil } end

    -- Nearest field whose photo area contains home (chosen once per flight)
    local function pickField(t)
      if tr.fieldFlight == tr.flight then return tr.field end
      tr.fieldFlight, tr.field = tr.flight, nil
      local best
      for _, f in ipairs(tr.fields) do
        local dn = (t.home.lat - f.lat) * M_PER_DEG
        local de = (t.home.lon - f.lon) * M_PER_DEG * cos(rad(f.lat))
        local d = dn * dn + de * de
        if d <= f.radius * f.radius and (not best or d < best) then best, tr.field = d, f end
      end
      return tr.field
    end

    -- Place the photo tiles for zoom level `lvl` (meters per pixel mpp); false = no photo here
    local function photo(t, lvl, mpp)
      local sl = v.slots
      for i = 1, 4 do sl[i].on = false end
      if not (tr.photo and t.home and t.imperial) then return false end
      local f = pickField(t)
      local rl = f and f.rings and f.rings[r]          -- tiles made for this map size (ring px)
      if not rl then return false end
      local L = rl[lvl]
      if not L then return false end
      local T, n = rl.tile or f.tile, L.n
      local hn = (t.home.lat - f.lat) * M_PER_DEG
      local he = (t.home.lon - f.lon) * M_PER_DEG * cos(rad(f.lat))
      local ox = cx - he / mpp - n * T / 2            -- tile grid origin on screen
      local oy = cy + hn / mpp - n * T / 2
      local i0, i1 = max(0, floor(-ox / T)), min(n - 1, floor((W - 1 - ox) / T))
      local j0, j1 = max(0, floor(-oy / T)), min(n - 1, floor((H - 1 - oy) / T))
      local any = false
      for j = j0, j1 do
        for i = i0, i1 do
          local s = sl[(i % 2) + 2 * (j % 2) + 1]
          s.x, s.y, s.on = floor(ox + i * T + 0.5), floor(oy + j * T + 0.5), true
          local key = ((lvl * 512 + i) * 512 + j)
          if s.key ~= key or s.f ~= f then         -- format the path only when the tile changes
            s.key, s.f = key, f
            s.file = fmt("%s%s/%d/%d/%d_%d.jpg", PHOTO_ROOT, f.name, r, lvl, i, j)
          end
          any = true
        end
      end
      return any
    end

    local ax, ay = {}, {}
    local trailFirst, lead = { -1, -1 }, { 0, 0 }
    local steps, cur = nil, 1
    local lastKey = {}

    local function clampC(x) return max(1, min(W + 2 * M - 1, floor(x + M + 0.5))) end

    function v.update(t)
      local imperial = t.imperial
      local st = imperial and STEPS.imperial or STEPS.metric
      if st ~= steps then steps, cur = st, 1 end
      if tr.count == 0 then cur = 1 end

      -- Automatic zoom: smallest step that fits the whole trail and the aircraft;
      -- zoom out at once, zoom in only with 25 % spare room (no flicker at a boundary)
      local need = max(max(tr.maxE, abs(t.de)) * r / fitX, max(tr.maxN, abs(t.dn)) * r / fitY)
      local i = #steps
      for k = 1, #steps do
        if steps[k][1] >= need then i = k break end
      end
      if i > cur or (i < cur and need * 1.25 <= steps[i][1]) then cur = i end
      local S = steps[cur][1]
      local ppm = r / S
      tr.minD = max(3, 3 / ppm)              -- new sample every ~3 px on screen
      v.scaleText = steps[cur][2]

      v.photoOn = photo(t, cur, S / r)

      local px, py = cx + t.de * ppm, cy - t.dn * ppm
      local hq = floor(t.hdg / 5 + 0.5) * 5
      local qx, qy = floor(px + 0.5), floor(py + 0.5)
      local k = lastKey
      if k.x == qx and k.y == qy and k.h == hq and k.s == cur and k.c == tr.count and k.f == tr.flight then
        return false
      end
      k.x, k.y, k.h, k.s, k.c, k.f = qx, qy, hq, cur, tr.count, tr.flight

      -- Aircraft arrow (north up, rotated by heading): nose, right wing, notch, left wing, nose
      local a = rad(hq)
      local fx, fy = sin(a), -cos(a)   -- forward
      local rx, ry = -fy, fx           -- right
      -- closed polygon: start at a vertex that differs from the current first point
      local p = v.plane
      for j = 1, 4 do
        local f, s = ARROW[j][1] * LS, ARROW[j][2] * LS
        ax[j], ay[j] = clampC(px + fx * f + rx * s), clampC(py + fy * f + ry * s)
      end
      local st = 1
      for j = 1, 4 do
        if ax[j] ~= p[1][1] or ay[j] ~= p[1][2] then st = j break end
      end
      for j = 0, 3 do
        local q = (st + j - 1) % 4 + 1
        p[j + 1][1], p[j + 1][2] = ax[q], ay[q]
      end
      p[5][1], p[5][2] = p[1][1], p[1][2]

      -- Line to home (aircraft first, see header)
      local h = v.homeLine
      h[1][1], h[1][2] = clampC(px), clampC(py)
      h[2][1], h[2][2] = cx + M, cy + M

      -- Trail newest -> oldest, starting at the aircraft
      local tp, c = v.trail, tr.count
      pool[1][1], pool[1][2] = h[1][1], h[1][2]
      tp[1] = pool[1]
      local n, e = tr.n, tr.e
      for j = 1, c do
        local q = pool[j + 1]
        q[1] = clampC(cx + e[c - j + 1] * ppm)
        q[2] = clampC(cy - n[c - j + 1] * ppm)
        tp[j + 1] = q
      end
      if c == 0 then tp[2] = pool[1] end   -- never fewer than 2 points
      for j = max(c, 1) + 2, #tp do tp[j] = nil end
      -- aircraft did not move a pixel (rescale, new sample on the same pixel): lead with a copy
      -- of it nudged by 1 px (hidden under the arrow) so EdgeTX sees the first point change
      if tp[1][1] == trailFirst[1] and tp[1][2] == trailFirst[2] then
        lead[1], lead[2] = tp[1][1] + ((tp[1][1] > 1) and -1 or 1), tp[1][2]
        tp[1] = lead
      end
      trailFirst[1], trailFirst[2] = tp[1][1], tp[1][2]
      v.trailOn = c > 0
      return true
    end

    return v
  end

  return tr
end
