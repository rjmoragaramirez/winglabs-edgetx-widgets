-- WL Avionics widget - LVGL UI (attitude indicator over a vector map). Built once per update() (theme/zone/options change).
-- Dynamic values are small closures returning cached strings/tables from telem,
-- so LVGL only redraws objects whose value actually changed.

local floor, max, min = math.floor, math.max, math.min
local sin, cos, rad = math.sin, math.cos, math.rad

return function(wgt)
  local T, t, a, o = wgt.theme, wgt.telem, wgt.alerts, wgt.opt
  local W, H = wgt.zone.w, wgt.zone.h
  local S = lvgl.LCD_SCALE or 1
  local function px(v) return floor(v * S + 0.5) end

  ---------------------------------------------------------------- colors
  local function sevColor(sev)
    if sev >= 3 then return T.crit elseif sev == 2 then return T.warn elseif sev == 1 then return T.accent end
    return T.ok
  end
  local function battColor()
    if not t.linked or t.cellV <= 0 then return T.muted end
    if t.cellV <= o.cellCrit then return T.crit end
    if t.cellV <= o.cellWarn then return T.warn end
    return T.ok
  end
  local function lqColor()
    if not t.linked then return T.crit end
    if t.lq < 50 then return T.crit elseif t.lq < 80 then return T.warn end
    return T.ok
  end
  local function stateColor()
    if not t.linked then return T.crit end
    return t.armed and T.warn or T.muted
  end
  local function satColor() return t.fix and T.ok or T.warn end
  local function live() return t.linked and T.text or T.muted end  -- last-known values dim
  local function battFrac()
    local f
    if t.pct >= 0 and t.linked then f = t.pct / 100
    else f = (t.cellV - 3.3) / 0.9 end
    return max(0, min(1, f))
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
  local function str(key) return function() return t.s[key] end end

  -- Home arrow: two polylines rotated by t.homeRel, preallocated, 5 deg steps
  local function homeArrow(cx, cy, r)
    local head = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
    local shaft = { { 0, 0 }, { 0, 0 } }
    local lastQ
    -- EdgeTX 2.11.0/2.11.1 redraw a line only when its first point moves: if a rotation step
    -- leaves the first point on the same pixel, reverse the polyline so the other end leads;
    -- if that one did not move either, nudge the first point by 1 px.
    local function leadMoved(pts, fx, fy)
      local n = #pts
      if pts[1][1] ~= fx or pts[1][2] ~= fy then return end
      if pts[n][1] ~= fx or pts[n][2] ~= fy then
        for i = 1, n // 2 do pts[i], pts[n - i + 1] = pts[n - i + 1], pts[i] end
      else
        pts[1][1] = fx + 1
      end
    end
    local function rot(p, ang, dist)
      p[1] = floor(cx + sin(ang) * dist + 0.5)
      p[2] = floor(cy - cos(ang) * dist + 0.5)
    end
    local function upd()
      local q = floor(t.homeRel / 5 + 0.5) * 5
      if q == lastQ then return end
      lastQ = q
      local hx, hy, sx, sy = head[1][1], head[1][2], shaft[1][1], shaft[1][2]
      local ang = rad(q)
      rot(head[2], ang, r * 0.8)                -- tip
      rot(head[1], ang - rad(150), r * 0.55)    -- left barb
      rot(head[3], ang + rad(150), r * 0.55)    -- right barb
      rot(shaft[1], ang, r * 0.8)               -- tip
      rot(shaft[2], ang + rad(180), r * 0.7)    -- tail
      leadMoved(head, hx, hy)
      leadMoved(shaft, sx, sy)
    end
    upd()
    local vis = function() return t.home ~= nil end
    return
      { type = "circle", x = cx, y = cy, radius = r, filled = false, thickness = px(2), color = T.border },
      { type = "line", pts = function() upd(); return head end, thickness = px(3), rounded = true,
        color = T.accent, visible = vis },
      { type = "line", pts = function() return shaft end, thickness = px(3), rounded = true,
        color = T.accent, visible = vis }
  end

  ---------------------------------------------------------------- horizon
  -- Same look as the WingLabs attitude indicator firmware (WingUI::Renderer): white horizon
  -- and ladder with dark outlines, gold outlined wings and roll pointer, ROLL/PITCH strip.
  local DEG = "\194\176"  -- UTF-8 degree sign (Lua 5.2 has no \u{} escape)
  local function horizonView(x, y, w, h, strip)
    local stripH = strip and px(50) or 0
    local ph = h - stripH
    local k = min(w / 240, (floor(ph / 2) - 3) / 86)
    local g = wgt.mkHorizon(w, ph, k, S)
    wgt.g = g
    local cx, cy = floor(g.cx), g.cy
    local function kp(v) return max(1, floor(v * k + 0.5)) end
    local function seg(s) return function() return s end end
    local ink = T.ink or T.bg

    local cc = {
      { type = "line", pts = seg(g.band), thickness = g.bandThick, color = T.ground },
      { type = "line", pts = seg(g.line), thickness = kp(4), color = ink },
      { type = "line", pts = seg(g.line), thickness = kp(2), color = T.horizon },
    }
    local function addC(v) cc[#cc + 1] = v end
    for i = 1, #g.marks do
      local m = g.marks[i]
      local vis = function() return m.show end
      for j = 1, #m.segs do
        addC({ type = "line", pts = seg(m.segs[j]), thickness = kp(m.thick), color = T.ladder, visible = vis })
      end
    end
    for i = 1, #g.ticks do
      addC({ type = "line", pts = g.ticks[i], thickness = kp(4), color = ink })
      addC({ type = "line", pts = g.ticks[i], thickness = kp(2), color = T.horizon })
    end
    addC({ type = "line", pts = seg(g.ptr), thickness = kp(2), color = T.aircraft })

    local ch = {
      { type = "rectangle", x = 0, y = 0, w = w, h = ph, filled = true, color = T.sky },
      { type = "box", x = -g.M, y = -g.M, w = g.size, h = g.size, scrollDir = 0, scrollBar = false,
        children = cc },
    }
    local function add(v) ch[#ch + 1] = v end
    for i = 1, #g.marks do
      local m = g.marks[i]
      if m.text then
        add({ type = "label", w = 2 * floor(20 * S + 0.5), text = m.text, font = 0, color = T.ladder, align = CENTER,
              pos = function() return m.lx, m.ly end, visible = function() return m.showL end })
        add({ type = "label", w = 2 * floor(20 * S + 0.5), text = m.text, font = 0, color = T.ladder, align = CENTER,
              pos = function() return m.rx, m.ry end, visible = function() return m.showR end })
      end
    end

    -- Reference wings: outlined, short downturned tips, open center with a chevron
    local wl, wi, wt = kp(49), kp(14), kp(7)
    local left = { { cx - wl, cy }, { cx - wi, cy }, { cx - wi, cy + wt } }
    local right = { { cx + wl, cy }, { cx + wi, cy }, { cx + wi, cy + wt } }
    local chev = { { cx - kp(4), cy }, { cx, cy - kp(4) }, { cx + kp(4), cy } }
    for pass = 1, 2 do
      local col, th = pass == 1 and ink or T.aircraft, pass == 1 and kp(5) or kp(3)
      add({ type = "line", pts = left, thickness = th, color = col })
      add({ type = "line", pts = right, thickness = th, color = col })
      add({ type = "line", pts = chev, thickness = th, color = col })
    end

    if strip then
      -- Heading box (bottom of the panel, firmware "LIMIT" box style)
      local hdgW, hdgH = px(52), px(20)
      add({ type = "rectangle", x = cx - floor(hdgW / 2), y = ph - hdgH - kp(4), w = hdgW, h = hdgH,
            filled = true, color = ink, children = {
              label(0, px(1), hdgW, str("hdg"), 0, T.aircraft, CENTER) } })
    end
    -- Alert banner (firmware "IMU LOST" box style); at the bottom edge when the panel is short
    local banW, banH = w - px(24), px(26)
    local banY = strip and cy + kp(31) or ph - banH - px(3)
    add({ type = "rectangle", x = px(12), y = banY, w = banW, h = banH, filled = true, color = ink,
          visible = function() return a.show end, children = {
            label(0, px(3), banW, function() return a.banner end, BOLD, function() return sevColor(a.sev) end,
                  CENTER) } })

    -- Data strip (optional)
    if not strip then
      add({ type = "rectangle", x = 0, y = 0, w = w, h = h, filled = false, thickness = 1, color = T.border })
      return { type = "box", x = x, y = y, w = w, h = h, scrollDir = 0, scrollBar = false, children = ch }
    end
    local sb, sl, sd, sm = T.stripBg or T.surface, T.stripLine or T.accent, T.stripDiv or T.border,
      T.stripMuted or T.muted
    local half = floor(w / 2)
    local x1, x2 = px(4), half - px(4)
    add({ type = "rectangle", x = 0, y = ph, w = w, h = stripH, filled = true, color = sb })
    add({ type = "line", pts = { { px(18), ph }, { w - px(19), ph } }, thickness = 1, color = sl })
    add({ type = "line", pts = { { half, ph + px(8) }, { half, h - px(12) } }, thickness = 1, color = sd })
    add(label(x1, ph + px(3), half, "ROLL " .. DEG, SMLSIZE, sm, CENTER))
    add(label(x2, ph + px(3), half, "PITCH " .. DEG, SMLSIZE, sm, CENTER))
    add(label(x1, ph + px(13), half, str("roll"), DBLSIZE, live, CENTER))
    add(label(x2, ph + px(13), half, str("pitch"), DBLSIZE, live, CENTER))
    -- frame
    add({ type = "rectangle", x = 0, y = 0, w = w, h = h, filled = false, thickness = 1, color = T.border })

    return { type = "box", x = x, y = y, w = w, h = h, scrollDir = 0, scrollBar = false, children = ch }
  end

  ---------------------------------------------------------------- map
  -- Vector map: home at the center, north up, range rings, trail and aircraft arrow.
  local function mapView(x, y, w, h)
    local v = wgt.trail.view(w, h, S)
    wgt.mp = v
    local cx, cy, r = v.cx, v.cy, v.r
    local ink = T.ink or T.bg
    local ring = T.mapRing or T.border
    local hasHome = function() return t.home ~= nil end
    local noHome = function() return t.home == nil end
    local planeColor = function() return t.linked and T.aircraft or T.muted end

    local canvas = { type = "box", x = -v.M, y = -v.M, w = v.size, h = v.size, scrollDir = 0, scrollBar = false,
                     children = {
      { type = "line", pts = function() return v.homeLine end, thickness = 1, color = T.muted, opacity = 170,
        visible = hasHome },
      { type = "line", pts = function() return v.trail end, thickness = px(2), color = T.mapTrail or T.accent,
        visible = function() return v.trailOn end },
      { type = "line", pts = function() return v.plane end, thickness = px(5), color = ink, visible = hasHome },
      { type = "line", pts = function() return v.plane end, thickness = px(3), color = planeColor,
        visible = hasHome },
    } }

    local nx, ny = px(12), px(6)  -- north arrow
    -- scale label right of the outer ring, or under the HDG plate when the ring fills the width
    local sx, sy = cx + r + px(2), cy - px(15)
    if sx + px(52) > w then sx, sy = w - px(54), px(21) end
    local scaleLbl = label(sx + px(2), sy - px(1), px(70), function() return v.scaleText end, SMLSIZE, T.text)
    scaleLbl.visible = hasHome
    -- rings turn light over the photo
    local ringColor = function() return v.photoOn and T.horizon or ring end
    local ch = {
      { type = "rectangle", x = 0, y = 0, w = w, h = h, filled = true, color = T.mapBg or T.surface },
    }
    for i = 1, #v.slots do
      local sl = v.slots[i]
      ch[#ch + 1] = { type = "image", x = 0, y = 0, w = v.tile, h = v.tile, file = function() return sl.file end,
                      pos = function() return sl.x, sl.y end, visible = function() return sl.on end }
    end
    local rest = {
      { type = "line", pts = { { cx, 0 }, { cx, h } }, thickness = 1, color = ringColor, opacity = 120 },
      { type = "line", pts = { { 0, cy }, { w, cy } }, thickness = 1, color = ringColor, opacity = 120 },
      { type = "circle", x = cx, y = cy, radius = r, filled = false, thickness = 1, color = ringColor },
      { type = "circle", x = cx, y = cy, radius = floor(r / 2), filled = false, thickness = 1, color = ringColor },
      { type = "circle", x = cx, y = cy, radius = px(5), filled = false, thickness = px(2), color = T.ok },
      canvas,
      -- ring scale (dark plate keeps it readable over the photo)
      { type = "rectangle", x = sx, y = sy, w = px(50), h = px(14), filled = true,
        color = ink, opacity = 170, visible = hasHome },
      scaleLbl,
      -- north arrow
      { type = "rectangle", x = px(4), y = px(2), w = px(28), h = px(22), filled = true, color = ink, opacity = 170 },
      { type = "line", pts = { { nx, ny + px(14) }, { nx, ny } }, thickness = px(2), color = T.text },
      { type = "line", pts = { { nx - px(4), ny + px(5) }, { nx, ny }, { nx + px(4), ny + px(5) } },
        thickness = px(2), color = T.text },
      label(nx + px(6), ny - px(2), px(14), "N", SMLSIZE, T.text),
      -- heading
      { type = "rectangle", x = w - px(70), y = px(2), w = px(66), h = px(16), filled = true, color = ink,
        opacity = 170 },
      label(w - px(76), px(3), px(40), "HDG", SMLSIZE, T.muted, RIGHT),
      label(w - px(34), px(3), px(30), str("hdg"), SMLSIZE, live, RIGHT),
      -- waiting for home
      { type = "rectangle", x = cx - px(70), y = cy + px(10), w = px(140), h = px(20), filled = true, color = ink,
        visible = noHome, children = {
          label(0, px(2), px(140), "HOME SET ON ARM", SMLSIZE, T.muted, CENTER) } },
      { type = "rectangle", x = 0, y = 0, w = w, h = h, filled = false, thickness = 1, color = T.border },
    }
    for i = 1, #rest do ch[#ch + 1] = rest[i] end
    return { type = "box", x = x, y = y, w = w, h = h, scrollDir = 0, scrollBar = false, children = ch }
  end

  ---------------------------------------------------------------- layouts
  local function buildFull()
    local pad, tb, ip = px(4), px(30), px(8)
    local side = floor(W * 0.23)
    local y0 = tb + pad
    local bh = H - y0 - pad
    local ui = {}
    local function add(v) ui[#ui + 1] = v end

    add({ type = "rectangle", x = 0, y = 0, w = W, h = H, filled = true, color = T.bg })

    -- Top bar: mode pill | state | timer | link
    local pillW = floor(W * 0.25)
    add({ type = "rectangle", x = pad, y = pad, w = pillW, h = tb - pad, filled = true, rounded = px(13),
          color = function() return sevColor(t.sev) end, children = {
            label(0, px(4), pillW, str("mode"), BOLD, T.onPill, CENTER) } })
    add(label(pillW + pad * 3, px(10), floor(W * 0.15), str("state"), SMLSIZE, stateColor))
    add(label(floor(W * 0.42), px(1), floor(W * 0.16), str("timer"), MIDSIZE, T.text, CENTER))
    add(label(floor(W * 0.58), px(10), floor(W * 0.27), str("radio"), SMLSIZE, T.muted, RIGHT))
    add(label(W - pad - floor(W * 0.14), px(6), floor(W * 0.14), str("lq"), BOLD, lqColor, RIGHT))

    -- Battery card
    local bw = side - 2 * ip
    add(card(pad, y0, side, bh, {
      label(ip, ip - 2, bw, "BATTERY", SMLSIZE, T.muted),
      label(ip, ip - 2, bw, str("cells"), SMLSIZE, T.muted, RIGHT),
      label(ip, px(22), bw, str("cellV"), DBLSIZE, battColor),
      label(ip, px(60), bw, str("volt"), 0, live),
      label(ip, px(60), bw, str("pct"), 0, T.muted, RIGHT),
      { type = "rectangle", x = ip, y = px(84), w = bw, h = px(10), filled = true, rounded = px(5), color = T.border },
      { type = "rectangle", x = ip, y = px(84), w = bw, h = px(10), filled = true, rounded = px(5),
        color = battColor, size = function() return max(px(10), floor(bw * battFrac())), px(10) end },
      label(ip, px(104), bw, "CURRENT", SMLSIZE, T.muted),
      label(ip, px(118), bw, str("curr"), MIDSIZE, live),
      label(ip, px(150), bw, "USED", SMLSIZE, T.muted),
      label(ip, px(164), bw, str("capa"), 0, live),
      label(ip, bh - px(22), bw, "WingLabs", SMLSIZE, T.muted),   -- brand mark, bottom left
    }))

    -- Center column: attitude indicator on top, map below
    local hx = pad * 2 + side
    local cw = W - 2 * side - 4 * pad
    local ah = floor(bh * 0.56)
    add(horizonView(hx, y0, cw, ah, false))
    add(mapView(hx, y0 + ah + pad, cw, bh - ah - pad))

    -- Right column
    local rx = W - pad - side
    local altH = floor(bh * 0.40)
    local spdH = floor(bh * 0.26)
    local homeH = bh - altH - spdH - 2 * pad
    add(card(rx, y0, side, altH, {
      label(ip, ip - 2, bw, "ALTITUDE", SMLSIZE, T.muted),
      label(ip, ip - 2, bw, str("altU"), SMLSIZE, T.muted, RIGHT),
      label(ip, px(20), bw, str("alt"), DBLSIZE, live),
      label(ip, altH - px(20), bw, str("vspd"), SMLSIZE, T.muted),
    }))
    add(card(rx, y0 + altH + pad, side, spdH, {
      label(ip, ip - 2, bw, "GND SPEED", SMLSIZE, T.muted),
      label(ip, ip - 2, bw, str("spdU"), SMLSIZE, T.muted, RIGHT),
      label(ip, px(20), bw, str("spd"), MIDSIZE, live),
    }))
    local ar = max(px(10), min(px(16), floor((homeH - px(24)) / 2)))
    local hc = {
      label(ip, ip - 2, bw, "HOME", SMLSIZE, T.muted),
      label(ip, ip - 2, bw, str("sats"), SMLSIZE, satColor, RIGHT),
      label(ip, px(24), bw, str("dist"), MIDSIZE, live),
      label(ip, homeH - px(18), bw, str("distU"), SMLSIZE, T.muted),
    }
    local c1, c2, c3 = homeArrow(side - ip - ar, homeH - ip - ar, ar)
    hc[#hc + 1], hc[#hc + 2], hc[#hc + 3] = c1, c2, c3
    add(card(rx, y0 + altH + spdH + 2 * pad, side, homeH, hc))

    -- Split into several build calls (very large tables can fail when compiled)
    for i = 1, #ui do lvgl.build({ ui[i] }) end
  end

  local function buildCompact()
    wgt.g, wgt.mp = nil, nil
    local pad = px(4)
    local ph = min(px(26), floor(H * 0.3))
    local cw, rowH = floor((W - 3 * pad) / 2), floor((H - ph - 3 * pad) / 2)
    local stacked = rowH >= px(40)          -- title above value, else title | value inline
    local big = rowH >= px(56) and MIDSIZE or 0
    local function cell(col, row, title, key, color)
      local x = pad + col * (cw + pad)
      local y = ph + 2 * pad + row * (rowH + pad)
      local iw = cw - px(12)
      if stacked then
        return card(x, y, cw, rowH, {
          label(px(6), px(2), iw, title, SMLSIZE, T.muted),
          label(px(6), px(16), iw, str(key), big, color or live),
        })
      end
      local vy = max(0, floor((rowH - px(18)) / 2))
      return card(x, y, cw, rowH, {
        label(px(6), vy + px(3), iw, title, SMLSIZE, T.muted),
        label(px(6), vy, iw, str(key), 0, color or live, RIGHT),
      })
    end
    lvgl.build({
      { type = "rectangle", x = 0, y = 0, w = W, h = H, filled = true, color = T.bg },
      { type = "rectangle", x = pad, y = pad, w = W - 2 * pad, h = ph, filled = true, rounded = floor(ph / 2),
        color = function() return a.show and sevColor(a.sev) or sevColor(t.sev) end, children = {
          label(0, floor((ph - px(17)) / 2), W - 2 * pad,
            function() return a.show and a.banner or t.s.mode end, BOLD, T.onPill, CENTER) } },
    })
    lvgl.build({
      cell(0, 0, "CELL", "cellV", battColor),
      cell(1, 0, t.imperial and "ALT ft" or "ALT m", "alt"),
    })
    lvgl.build({
      cell(0, 1, "LINK", "lq", lqColor),
      cell(1, 1, "HOME", "dist"),
    })
  end

  lvgl.clear()
  if W >= 400 and H >= 220 then buildFull() else buildCompact() end
end
