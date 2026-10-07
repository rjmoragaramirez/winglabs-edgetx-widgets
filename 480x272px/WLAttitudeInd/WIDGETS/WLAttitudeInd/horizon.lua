-- WL Attitude Ind widget - attitude indicator geometry (lines only), same layout as the
-- WingLabs attitude indicator firmware (WingUI::Renderer, 240 px wide reference, scale k):
-- 5 deg pitch ladder (negative marks dashed, labels on the tens), bank ticks, gold roll pointer.
--
-- Why lines: an LVGL triangle in EdgeTX frees/mallocs a bbox-sized mask and recreates
-- its canvas every time its points change, which at 20 Hz fragments the heap. Lines
-- only rewrite their point array. The ground is one very thick line (a band).
--
-- LVGL reads line points as unsigned, so all points live in a "canvas" box placed at
-- (-M, -M) inside the W x H viewport; canvas coords = viewport coords + M stay >= 0.
-- Output tables are preallocated and mutated in place (no per-frame garbage).

local sin, cos, rad, floor, sqrt, max, min, abs = math.sin, math.cos, math.rad, math.floor, math.sqrt,
  math.max, math.min, math.abs

local function newSeg() return { { 0, 0 }, { 0, 0 } } end

-- W x H: attitude panel (data strip excluded). k: pixel scale vs. the 240 px firmware layout.
-- S: lvgl.LCD_SCALE (radio fonts grow with it: 1.0 on 480x272, 1.375 on 800x480).
return function(W, H, k, S)
  local diag = floor(sqrt(W * W + H * H)) + 1
  local M = floor(diag * 2.5)          -- canvas margin
  local vx, vy = W / 2, floor(H / 2)    -- panel center (viewport coords)
  local cx, cy = vx + M, vy + M         -- same in canvas coords
  local ppd = 2.25 * k                  -- pixels per degree of pitch
  S = S or 1
  local FH = floor(16 * S + 0.5)        -- label font height (STD), for centering
  local LW2 = floor(20 * S + 0.5)       -- half the label box width (ui.lua: 40 * S)

  local g = {
    M = M, size = W + 2 * M, cx = vx, cy = vy, k = k,
    bandThick = 2 * diag,
    band = newSeg(), line = newSeg(),
    ptr = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
    marks = {},
  }

  -- Ladder: one entry per 5 deg mark, segments as local x ranges along the horizon
  for mark = -50, 50, 5 do
    if mark ~= 0 then
      local major = mark % 10 == 0
      local outer, inner = (major and 30 or 19) * k, (major and 10 or 7) * k
      local m = { deg = mark, major = major, show = false, xs = {}, segs = {},
                  thick = (mark > 0 and major) and 2 or 1 }
      local function add(x0, x1)
        m.xs[#m.xs + 1] = { x0, x1 }
        m.segs[#m.segs + 1] = newSeg()
      end
      for side = -1, 1, 2 do
        if mark < 0 then
          local j = inner
          while j < outer - 0.01 do
            add(side * j, side * min(j + 4 * k, outer))
            j = j + 7 * k
          end
        else
          add(side * inner, side * outer)
        end
      end
      if major then
        m.text = tostring(mark)
        m.tw = (#m.text * 6 - 1) * 2 * k   -- label width in the firmware font (sets the position)
        m.lw = #m.text * 9 * S             -- approx. width in the radio STD font (sets the clipping)
        m.lx, m.ly, m.rx, m.ry = 0, 0, 0, 0
        m.showL, m.showR = false, false
      end
      g.marks[#g.marks + 1] = m
    end
  end

  -- Static bank scale (canvas coords): ticks every 10/15/20 deg, long at 0/30/60
  g.ticks = {}
  local R = 84 * k
  for _, a in ipairs({ -80, -60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60, 80 }) do
    local t = rad(a)
    local len = ((a == 0 or abs(a) == 30 or abs(a) == 60) and 10 or 6) * k
    g.ticks[#g.ticks + 1] = {
      { floor(cx + sin(t) * R + 0.5), floor(cy - cos(t) * R + 0.5) },
      { floor(cx + sin(t) * (R - len) + 0.5), floor(cy - cos(t) * (R - len) + 0.5) },
    }
  end

  local function setPt(p, x, y) p[1], p[2] = floor(x + 0.5), floor(y + 0.5) end

  local lastP, lastR
  local topY, botY = vy - 55 * k, H - 8 * k          -- ladder kept clear of bank arc / panel bottom
  local lblX0, lblX1, lblY0, lblY1 = 14 * k, W - 15 * k, vy - 54 * k, H - 7 * k

  -- pitch: deg, nose up positive. roll: deg, right wing down positive.
  -- Returns true when the geometry changed.
  function g.update(pitch, roll)
    pitch = floor(pitch * 2 + 0.5) / 2   -- 0.5 deg steps: no sub-pixel churn
    roll = floor(roll * 2 + 0.5) / 2
    if pitch == lastP and roll == lastR then return false end
    lastP, lastR = pitch, roll

    local r = rad(roll)
    local ux, uy = cos(r), -sin(r)     -- along the horizon; right end rises when banking right
    local nx, ny = sin(r), cos(r)      -- normal toward the ground
    local off = max(-diag, min(diag, pitch * ppd))  -- beyond diag the view is all sky/ground
    local hx, hy = cx + nx * off, cy + ny * off

    -- Ground band: covers [0, 2*diag] from the horizon toward the ground
    local bx, by = hx + nx * diag, hy + ny * diag
    setPt(g.band[1], bx - ux * diag, by - uy * diag)
    setPt(g.band[2], bx + ux * diag, by + uy * diag)

    -- Horizon line spans the viewport
    setPt(g.line[1], hx - ux * diag, hy - uy * diag)
    setPt(g.line[2], hx + ux * diag, hy + uy * diag)

    -- Ladder: local v = (pitch - mark) * ppd toward the ground, measured from the panel center
    for i = 1, #g.marks do
      local m = g.marks[i]
      local v = (pitch - m.deg) * ppd
      local show = abs(v) <= 145 * k
      if show then
        local yc = vy + ny * v
        local ya, yb = yc - uy * 30 * k, yc + uy * 30 * k
        show = min(ya, yb) >= topY and max(ya, yb) <= botY
      end
      m.show = show
      if show then
        local px, py = cx + nx * v, cy + ny * v
        for j = 1, #m.segs do
          local s, x = m.segs[j], m.xs[j]
          setPt(s[1], px + ux * x[1], py + uy * x[1])
          setPt(s[2], px + ux * x[2], py + uy * x[2])
        end
      end
      if m.text then
        -- labels stay upright (LVGL labels cannot rotate); centered where the firmware puts them,
        -- shown only when the whole upright text box (radio font) fits
        local hw, hh = m.lw / 2, FH / 2
        local qx, qy = vx + nx * v, vy + ny * v
        local d = 39 * k + m.tw / 2
        local lx, ly = qx - ux * d, qy - uy * d
        local rx, ry = qx + ux * (d + k), qy + uy * (d + k)
        m.showL = lx - hw >= lblX0 and lx + hw <= lblX1 and ly - hh >= lblY0 and ly + hh <= lblY1
        m.showR = rx - hw >= lblX0 and rx + hw <= lblX1 and ry - hh >= lblY0 and ry + hh <= lblY1
        m.lx, m.ly = floor(lx + 0.5) - LW2, floor(ly + 0.5) - FH // 2 - 1
        m.rx, m.ry = floor(rx + 0.5) - LW2, floor(ry + 0.5) - FH // 2 - 1
      end
    end

    -- Roll pointer: gold triangle under the bank scale, turns with the horizon
    local a = rad(-roll)
    local dx, dy = sin(a), -cos(a)      -- radial
    local tx, ty = cos(a), sin(a)       -- tangential
    local p = g.ptr
    setPt(p[1], cx + dx * 71 * k, cy + dy * 71 * k)
    setPt(p[2], cx + dx * 62 * k - tx * 5 * k, cy + dy * 62 * k - ty * 5 * k)
    setPt(p[3], cx + dx * 62 * k + tx * 5 * k, cy + dy * 62 * k + ty * 5 * k)
    p[4][1], p[4][2] = p[1][1], p[1][2]
    return true
  end

  g.update(0, 0)
  return g
end
