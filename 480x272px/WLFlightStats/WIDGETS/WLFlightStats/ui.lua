-- WL Flight Stats widget - LVGL UI.
-- The page is static once a flight is shown, so it is rebuilt only when the shown flight,
-- theme, units or zone change. The build is split into stages (frame, then one chart per
-- stage) that main.lua runs on consecutive refresh() calls to stay far below the Lua
-- instruction limit. Only the top-bar recording status is a live closure.

local floor, max, min, ceil, log = math.floor, math.max, math.min, math.ceil, math.log
local fmt = string.format
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function clock(s)
  s = floor(s)
  if s >= 3600 then return fmt("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60) end
  return fmt("%d:%02d", s // 60, s % 60)
end

-- Smallest 1/2/2.5/5 x 10^k >= v
local function niceCeil(v)
  if v <= 0 then return 1 end
  local p = 10 ^ floor(log(v, 10))
  for _, m in ipairs({ 1, 2, 2.5, 5, 10 }) do
    if m * p >= v - 1e-9 then return m * p end
  end
  return 10 * p
end

return function(wgt)
  local T, o, rec, store = wgt.theme, wgt.opt, wgt.rec, wgt.store
  local W, H = wgt.zone.w, wgt.zone.h
  local S = lvgl.LCD_SCALE or 1
  local function px(v) return floor(v * S + 0.5) end
  local imp = o.imperial
  local sum, ser = wgt.cur, wgt.ser
  local count = #store.list

  ---------------------------------------------------------------- units
  local function altU(dm) return imp and dm * 0.328084 or dm / 10 end
  local function spdU(dk) return imp and dk * 0.0621371 or dk / 10 end
  local ALT_U, SPD_U = imp and "ft" or "m", imp and "mph" or "km/h"
  local function distS(m)
    if imp then
      if m < 305 then return fmt("%d ft", floor(m * 3.28084 + 0.5)) end
      return fmt("%.2f mi", m / 1609.344)
    end
    if m < 1000 then return fmt("%d m", m) end
    return fmt("%.2f km", m / 1000)
  end

  ---------------------------------------------------------------- helpers
  local function label(x, y, w, text, font, color, align)
    return { type = "label", x = x, y = y, w = w, text = text, font = font or 0,
             color = color or T.text, align = align or LEFT }
  end
  local function card(x, y, w, h, children)
    if T.cardLine then
      children[#children + 1] = { type = "rectangle", x = 0, y = 0, w = w, h = h, filled = false,
                                  thickness = 1, rounded = px(8), color = T.cardLine }
    end
    return { type = "rectangle", x = x, y = y, w = w, h = h, filled = true,
             rounded = px(8), color = T.surface, children = children }
  end
  local function statusText()
    if rec.active then return "REC " .. clock(rec.elapsed(getTime())) end
    return sum and "LANDED" or "READY"
  end
  local function statusColor() return rec.active and T.warn or T.muted end

  local stages = {}
  local function stage(fn) stages[#stages + 1] = fn end

  ---------------------------------------------------------------- chart
  -- k: series index 1..4, data: stored integers, a: stored -> display units factor (all linear)
  local function chart(x, y, w, h, k, title, data, a, isVolt, summary, mark)
    local col, fillCol = T["s" .. k], T["f" .. k]
    local n = #data
    local rlo, rhi, mi = data[1] or 0, data[1] or 0, 1
    for i = 2, n do
      local v = data[i]
      if v < rlo then rlo = v elseif v > rhi then rhi, mi = v, i end
    end
    local lo, hi = rlo * a, rhi * a
    if isVolt then
      lo, hi = floor(lo * 2) / 2 - 0.5, ceil(hi * 2) / 2
      if hi <= lo then hi = lo + 1 end
      if floor((hi - lo) * 2 + 0.5) % 2 == 1 then lo = lo - 0.5 end  -- mid grid line on a 0.5 V step
    else
      lo, hi = 0, niceCeil(hi * 1.05)
    end
    local x0, x1 = px(30), w - px(8)
    local y0, y1 = px(28), h - px(18)
    local pw, ph = x1 - x0, y1 - y0

    local ch = {
      label(px(8), px(4), w - px(16), title, SMLSIZE, T.muted),
      label(px(8), px(4), w - px(16), summary, SMLSIZE, col, RIGHT),
    }
    local function add(v) ch[#ch + 1] = v end
    -- grid + y labels
    for g = 0, 2 do
      local gy = floor(y1 - ph * g / 2 + 0.5)
      add({ type = "line", pts = { { x0, gy }, { x1, gy } }, thickness = 1, color = T.grid })
      local v = lo + (hi - lo) * g / 2
      add(label(0, gy - px(7), px(26), isVolt and fmt("%.1f", v) or fmt("%d", floor(v + 0.5)),
                TINSIZE, T.muted, RIGHT))
    end
    -- time axis
    local dur = sum.dur
    add(label(x0, y1 + px(1), px(40), "0:00", TINSIZE, T.muted))
    add(label(x0 + floor(pw / 2) - px(20), y1 + px(1), px(40), clock(dur / 2), TINSIZE, T.muted, CENTER))
    add(label(x1 - px(40), y1 + px(1), px(40), clock(dur), TINSIZE, T.muted, RIGHT))

    if n >= 2 then
      -- display y = y1 - (raw * a - lo) * ph / (hi - lo), clamped to the plot
      local ys, pts = {}, {}
      local ka, kb = a * ph / (hi - lo), y1 + lo * ph / (hi - lo) + 0.5
      local xs = pw / (n - 1)
      local ox = x0 + 0.5
      for i = 1, n do
        local yy = floor(kb - data[i] * ka)
        if yy < y0 then yy = y0 elseif yy > y1 then yy = y1 end
        ys[i] = yy
        pts[i] = { floor(ox + xs * (i - 1)), yy }
      end
      -- area fill: one zig-zag polyline of 2 px vertical strokes (a single LVGL object)
      local fill, step = {}, max(2, px(2))
      local c = 0
      while true do
        local fi = c * (n - 1) / pw + 1
        local i = floor(fi)
        local yt = ys[i]
        if i < n then yt = floor(yt + (ys[i + 1] - yt) * (fi - i) + 0.5) end
        if yt < y1 then yt = yt + 1 end  -- keep the fill edge under the series line
        local xx = x0 + c
        local m = #fill
        if (c // step) % 2 == 0 then
          fill[m + 1], fill[m + 2] = { xx, yt }, { xx, y1 }
        else
          fill[m + 1], fill[m + 2] = { xx, y1 }, { xx, yt }
        end
        if c >= pw then break end
        c = min(pw, c + step)
      end
      add({ type = "line", pts = fill, thickness = step + 1, color = fillCol })  -- strokes overlap: no gaps
      -- series line
      add({ type = "line", pts = pts, thickness = px(2), rounded = true, color = col })
      if mark then
        local p = pts[mi]
        add({ type = "circle", x = p[1], y = p[2], radius = px(4), filled = true, color = T.surface })
        add({ type = "circle", x = p[1], y = p[2], radius = px(3), filled = true, color = col })
      end
    else
      add(label(x0, y0 + floor(ph / 2) - px(8), pw, "no data", SMLSIZE, T.muted, CENTER))
    end
    return card(x, y, w, h, ch)
  end

  ---------------------------------------------------------------- full layout
  local function full()
    local pad, tb, ip = px(4), px(30), px(8)
    local side = floor(W * 0.23)
    local y0 = tb + pad
    local bh = H - y0 - pad

    stage(function()
      local ui = {
        { type = "rectangle", x = 0, y = 0, w = W, h = H, filled = true, color = T.bg },
      }
      local function add(v) ui[#ui + 1] = v end
      local pillW = floor(W * 0.25)
      add({ type = "rectangle", x = pad, y = pad, w = pillW, h = tb - pad, filled = true, rounded = px(13),
            color = T.accent, children = { label(0, px(4), pillW, "FLIGHT STATS", BOLD, T.onPill, CENTER) } })
      add(label(pillW + pad * 3, px(10), floor(W * 0.16), statusText, SMLSIZE, statusColor))
      if sum then
        add(label(floor(W * 0.42), px(1), floor(W * 0.16), clock(sum.dur), MIDSIZE, T.text, CENTER))
        local date = sum.year > 0 and fmt("%s %02d  %02d:%02d", MONTHS[sum.mon] or "?", sum.day, sum.hour, sum.min) or ""
        add(label(floor(W * 0.58), px(10), floor(W * 0.20), date, SMLSIZE, T.muted, RIGHT))
        add(label(W - pad - px(72), px(6), px(72),
                  count > 1 and fmt("<  %d/%d  >", wgt.pos, count) or fmt("%d/%d", wgt.pos, count), BOLD, T.accent, RIGHT))
      end
      lvgl.build(ui)
      if not sum then
        local cw = W - 2 * pad
        lvgl.build({ card(pad, y0, cw, bh, {
          label(0, floor(bh / 2) - px(30), cw, "No flights recorded yet", MIDSIZE, T.text, CENTER),
          label(0, floor(bh / 2) + px(2), cw, "Arm and fly: the stats of each flight appear here", SMLSIZE,
                T.muted, CENTER),
          label(0, floor(bh / 2) + px(18), cw, "after landing. The last " .. store.slots ..
                " flights of this model are kept.", SMLSIZE, T.muted, CENTER),
          label(ip, bh - px(22), px(100), "WingLabs", SMLSIZE, T.muted),
        }) })
        return
      end

      -- right column: peaks + summary
      local rx = W - pad - side
      local bw = side - 2 * ip
      local h1 = floor((bh - 2 * pad) * 0.31)
      local h3 = bh - 2 * h1 - 2 * pad
      local function peak(y, title, value, unit, t, col)
        return card(rx, y, side, h1, {
          label(ip, px(6), bw, title, SMLSIZE, T.muted),
          label(ip, px(18), bw, value, DBLSIZE, col),
          label(ip, px(27), bw, unit, SMLSIZE, T.muted, RIGHT),
          label(ip, h1 - px(20), bw, "at " .. clock(t), SMLSIZE, T.muted),
        })
      end
      lvgl.build({ peak(y0, "MAX ALTITUDE", fmt("%d", floor(altU(sum.maxAlt) + 0.5)), ALT_U, sum.tAlt, T.s3) })
      lvgl.build({ peak(y0 + h1 + pad, "MAX SPEED", fmt("%d", floor(spdU(sum.maxSpd) + 0.5)), SPD_U, sum.tSpd, T.s4) })
      local cells = sum.cells > 0 and sum.cells or 1
      local rows = {
        { "USED", fmt("%d mAh", sum.used) },
        { "MIN CELL", sum.minV > 0 and fmt("%.2f V", sum.minV / 100 / cells) or "--" },
        { "MAX DIST", sum.maxDist > 0 and distS(sum.maxDist) or "--" },
      }
      local ch = {}
      for i, r in ipairs(rows) do
        local yy = px(6) + (i - 1) * px(16)
        ch[#ch + 1] = label(ip, yy, bw, r[1], SMLSIZE, T.muted)
        ch[#ch + 1] = label(ip, yy, bw, r[2], SMLSIZE, T.text, RIGHT)
      end
      ch[#ch + 1] = label(ip, h3 - px(20), bw, "WingLabs", SMLSIZE, T.muted)
      lvgl.build({ card(rx, y0 + 2 * (h1 + pad), side, h3, ch) })
    end)
    if not sum then return end

    -- 2x2 charts
    local gw = W - side - 3 * pad
    local cw, chh = floor((gw - pad) / 2), floor((bh - pad) / 2)
    local function cell(k) return pad + (k % 2) * (cw + pad), y0 + (k // 2) * (chh + pad) end
    if not ser then
      stage(function()
        local x, y = cell(0)
        lvgl.build({ card(x, y, gw, bh, {
          label(0, floor(bh / 2) - px(8), gw, "Flight data file missing", SMLSIZE, T.muted, CENTER) }) })
      end)
      return
    end
    local defs = {
      { "VOLTAGE", ser.v, 0.01, true, fmt("min %.1f V", sum.minV / 100), false },
      { "CURRENT", ser.c, 0.1, false, fmt("max %.1f A", sum.maxA / 10), false },
      { "ALTITUDE", ser.a, altU(1), false, fmt("max %d %s", floor(altU(sum.maxAlt) + 0.5), ALT_U), true },
      { "GND SPEED", ser.s, spdU(1), false,
        fmt("max %d %s", floor(spdU(sum.maxSpd) + 0.5), SPD_U), true },
    }
    for k = 1, 4 do
      stage(function()
        local d = defs[k]
        local x, y = cell(k - 1)
        lvgl.build({ chart(x, y, cw, chh, k, d[1], d[2], d[3], d[4], d[5], d[6]) })
      end)
    end
  end

  ---------------------------------------------------------------- compact layout
  local function compact()
    stage(function()
      local pad = px(4)
      local ph = min(px(26), floor(H * 0.3))
      local cw, rowH = floor((W - 3 * pad) / 2), floor((H - ph - 3 * pad) / 2)
      local stacked = rowH >= px(40)
      local big = rowH >= px(56) and MIDSIZE or 0
      local function cell(col, row, title, value, color)
        local x = pad + col * (cw + pad)
        local y = ph + 2 * pad + row * (rowH + pad)
        local iw = cw - px(12)
        if stacked then
          return card(x, y, cw, rowH, {
            label(px(6), px(2), iw, title, SMLSIZE, T.muted),
            label(px(6), px(16), iw, value, big, color or T.text),
          })
        end
        local vy = max(0, floor((rowH - px(18)) / 2))
        return card(x, y, cw, rowH, {
          label(px(6), vy + px(3), iw, title, SMLSIZE, T.muted),
          label(px(6), vy, iw, value, 0, color or T.text, RIGHT),
        })
      end
      local head = function()
        if rec.active then return statusText() end
        return sum and ("LAST FLIGHT  " .. clock(sum.dur)) or "NO FLIGHTS YET"
      end
      lvgl.build({
        { type = "rectangle", x = 0, y = 0, w = W, h = H, filled = true, color = T.bg },
        { type = "rectangle", x = pad, y = pad, w = W - 2 * pad, h = ph, filled = true, rounded = floor(ph / 2),
          color = function() return rec.active and T.warn or T.accent end, children = {
            label(0, floor((ph - px(17)) / 2), W - 2 * pad, head, BOLD, T.onPill, CENTER) } },
      })
      local s = sum or { maxAlt = 0, maxSpd = 0, used = 0, minV = 0, cells = 0 }
      local cells = s.cells > 0 and s.cells or 1
      lvgl.build({
        cell(0, 0, "MAX ALT " .. ALT_U, sum and fmt("%d", floor(altU(s.maxAlt) + 0.5)) or "--", T.s3),
        cell(1, 0, "MAX SPD " .. SPD_U, sum and fmt("%d", floor(spdU(s.maxSpd) + 0.5)) or "--", T.s4),
      })
      lvgl.build({
        cell(0, 1, "USED mAh", sum and fmt("%d", s.used) or "--"),
        cell(1, 1, "MIN CELL", (sum and s.minV > 0) and fmt("%.2fV", s.minV / 100 / cells) or "--", T.s1),
      })
    end)
  end

  stage(function() lvgl.clear() end)
  if W >= 400 and H >= 220 then full() else compact() end
  return stages
end
