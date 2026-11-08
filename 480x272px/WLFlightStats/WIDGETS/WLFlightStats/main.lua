-- WL Flight Stats widget: end-of-flight statistics for EdgeTX 2.11+ (ELRS/CRSF + INAV), LVGL UI.
-- Records voltage, current, altitude and ground speed while armed (also in the background,
-- while another screen is shown) and, after landing (disarm), shows the four charts plus
-- max altitude / max speed. The last 8 flights of each model are kept on the SD card.
--
-- Design rules (same as the other WingLabs widgets):
--  * plain .lua only; every module is loaded once in create()
--  * telemetry polled at a fixed rate, bounded memory per flight (see recorder.lua)
--  * the page is static: rebuilt only when the shown flight / options change, in stages
--  * SD access only at create, when a flight is saved, and when another flight is selected

local VERSION = "0.1.0"
-- SD folder name must stay <= 13 chars (EdgeTX path buffer); display name <= 20 chars
local DEFAULT_PATH = "/WIDGETS/WLFlightStats/"
local THEME_NAMES = { "Dark", "Light", "Navy", "Sunlight", "Night", "Carbon" }

local options = {
  { "Theme", CHOICE or VALUE, 1, CHOICE and THEME_NAMES or 1, (not CHOICE) and #THEME_NAMES or nil },
  { "Units", CHOICE or VALUE, 1, CHOICE and { "Imperial", "Metric" } or 1, (not CHOICE) and 2 or nil },
  { "Cells", VALUE, 0, 0, 14 },        -- 0 = auto-detect
  { "MinFlight", VALUE, 20, 5, 300 },  -- seconds armed before a flight is saved
}

local function loadMod(path, name)
  local chunk, err = loadScript(path .. name .. ".lua")
  if not chunk then error(name .. ": " .. tostring(err)) end
  return chunk()
end

local function applyOptions(wgt, opts)
  wgt.options = opts
  local o = wgt.opt
  o.theme = opts.Theme or 1
  o.imperial = (opts.Units or 1) == 1
  wgt.telem.imperial = o.imperial
  wgt.telem.cellsOpt = opts.Cells or 0
  wgt.rec.minFlight = opts.MinFlight or 20
  wgt.theme = wgt.mkTheme(o.theme)
end

-- Select flight number pos (1 = oldest .. #list = newest) and load its series from the SD
local function select(wgt, pos)
  local list = wgt.store.list
  if #list == 0 then
    wgt.pos, wgt.cur, wgt.ser = 0, nil, nil
  else
    pos = math.max(1, math.min(#list, pos))
    wgt.pos, wgt.cur = pos, list[pos]
    wgt.ser = wgt.store.series(wgt.cur)
  end
  wgt.dirty = true
end

-- Run one pending build stage per call; a new request restarts the build.
local function buildStep(wgt)
  if not lvgl then return end
  if wgt.dirty then
    wgt.dirty = false
    local ok, res = pcall(wgt.buildUi, wgt)
    if ok then wgt.stages, wgt.stage = res, 1 else wgt.err, wgt.stages = tostring(res), nil end
  end
  local st = wgt.stages
  if st and wgt.stage <= #st then
    local ok, err = pcall(st[wgt.stage])
    wgt.stage = wgt.stage + 1
    if not ok then wgt.err, wgt.stages = tostring(err), nil end
  end
end

local function create(zone, opts, path)
  path = path or DEFAULT_PATH
  local wgt = { zone = zone, path = path, opt = {}, pos = 0 }
  wgt.mkTheme = loadMod(path, "themes")
  wgt.telem = loadMod(path, "telem")()
  wgt.rec = loadMod(path, "recorder")()
  wgt.store = loadMod(path, "store")(path .. "logs/")
  wgt.buildUi = loadMod(path, "ui")
  applyOptions(wgt, opts)
  select(wgt, #wgt.store.list)
  return wgt
end

local function update(wgt, opts)
  applyOptions(wgt, opts)
  wgt.dirty = true
end

local function tick(wgt)
  local now = getTime()
  local t = wgt.telem
  t.poll(now)
  wgt.rec.update(t, now)
  local fl = wgt.rec.done
  if fl then
    wgt.rec.done = nil
    -- show the flight that just ended, with the series already in memory (no SD read back)
    wgt.cur = wgt.store.save(fl)
    wgt.pos, wgt.ser = #wgt.store.list, { v = fl.v, c = fl.c, a = fl.a, s = fl.s }
    wgt.dirty = true
  end
end

-- Touch / rotary navigation (EdgeTX only passes events in full screen mode)
local function navigate(wgt, event, touchState)
  if not event or event == 0 or #wgt.store.list < 2 then return end
  local step = 0
  if event == EVT_ROTARY_LEFT or event == EVT_VIRTUAL_PREV then step = -1
  elseif event == EVT_ROTARY_RIGHT or event == EVT_VIRTUAL_NEXT then step = 1
  elseif event == EVT_TOUCH_TAP and touchState and touchState.x then
    -- tap the left / right half of the screen: older / newer flight
    step = touchState.x < (wgt.zone.x or 0) + wgt.zone.w / 2 and -1 or 1
  end
  if step ~= 0 then
    local p = wgt.pos + step
    if p >= 1 and p <= #wgt.store.list then select(wgt, p) end
  end
end

local function refresh(wgt, event, touchState)
  tick(wgt)
  navigate(wgt, event, touchState)
  if not lvgl then
    lcd.drawText(4, 4, "WL Flight Stats " .. VERSION .. " needs EdgeTX 2.11+", SMLSIZE)
    return
  end
  if wgt.err then
    lvgl.clear()
    lvgl.build({ { type = "label", x = 4, y = 4, w = wgt.zone.w - 8, text = "WL Flight Stats: " .. wgt.err,
                   font = SMLSIZE, color = lcd.RGB(0xFF4D4F) } })
    wgt.err = nil
    return
  end
  buildStep(wgt)
end

-- Runs when the widget is not visible: keep recording.
local function background(wgt)
  tick(wgt)
end

return {
  name = "WL Flight Stats",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background,
  useLvgl = true,
}
