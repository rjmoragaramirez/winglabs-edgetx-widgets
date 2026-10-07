-- WL Avionics widget: INAV telemetry widget with attitude indicator + vector map for EdgeTX 2.11+ (ELRS/CRSF), LVGL UI.
--
-- Design rules (stay responsive for the whole flight):
--  * plain .lua only; EdgeTX compiles and caches it itself (no stale .luac)
--  * every module is loaded once in create(); nothing touches the SD card per frame
--  * telemetry is polled at a fixed rate; strings are formatted only on change
--  * no full collectgarbage() calls; EdgeTX's incremental GC is enough with low churn
--  * horizon drawn with LVGL lines only (no per-frame malloc'd triangle masks)

local VERSION = "0.2.1"
-- SD folder name must stay <= 13 chars (EdgeTX path buffer); display name <= 20 chars
local DEFAULT_PATH = "/WIDGETS/WLAvionics/"
local THEME_NAMES = { "Dark", "Light", "Navy", "Sunlight", "Night" }

local options = {
  { "Theme", CHOICE or VALUE, 1, CHOICE and THEME_NAMES or 1, (not CHOICE) and #THEME_NAMES or nil },
  { "Units", CHOICE or VALUE, 1, CHOICE and { "Imperial", "Metric" } or 1, (not CHOICE) and 2 or nil },
  { "Cells", VALUE, 0, 0, 14 },          -- 0 = auto-detect
  { "CellWarn", VALUE, 350, 300, 420 },  -- centivolts per cell
  { "CellCrit", VALUE, 330, 280, 400 },
  { "AltWarn", VALUE, 400, 0, 5000 },    -- in display units, 0 = off
  { "Sounds", BOOL, 1 },
  { "Haptic", BOOL, 1 },
  { "MapPhoto", BOOL, 1 },               -- satellite photo under the map (needs /WLMAP on the SD)
}

local FIELDS_FILE = "/WLMAP/fields.lua"

local function loadMod(path, name)
  local chunk, err = loadScript(path .. name .. ".lua")
  if not chunk then error(name .. ": " .. tostring(err)) end
  return chunk()
end

local function applyOptions(wgt, opts)
  wgt.options = opts
  local o = wgt.opt
  o.theme = opts.Theme or 1
  o.cellWarn = (opts.CellWarn or 350) / 100
  o.cellCrit = (opts.CellCrit or 330) / 100
  o.altWarn = opts.AltWarn or 0
  o.alerts = (opts.Sounds or 1) == 1
  o.haptic = (opts.Haptic or 1) == 1
  wgt.trail.photo = (opts.MapPhoto or 1) == 1
  wgt.telem.imperial = (opts.Units or 1) == 1
  wgt.telem.cellsOpt = opts.Cells or 0
  wgt.theme = wgt.mkTheme(o.theme)
end

local function build(wgt)
  if lvgl then
    local ok, err = pcall(wgt.buildUi, wgt)
    wgt.err = (not ok) and tostring(err) or nil
  end
end

local function create(zone, opts, path)
  path = path or DEFAULT_PATH
  local wgt = { zone = zone, path = path, opt = {} }
  wgt.mkTheme = loadMod(path, "themes")
  wgt.telem = loadMod(path, "telem")()
  wgt.alerts = loadMod(path, "alerts")()
  wgt.mkHorizon = loadMod(path, "horizon")
  wgt.trail = loadMod(path, "map")()
  wgt.buildUi = loadMod(path, "ui")
  -- Photo fields: read once; missing file = radar map only
  local chunk = loadScript(FIELDS_FILE)
  if chunk then
    local ok, fields = pcall(chunk)
    if ok and type(fields) == "table" then wgt.trail.fields = fields end
  end
  applyOptions(wgt, opts)
  build(wgt)
  return wgt
end

local function update(wgt, opts)
  applyOptions(wgt, opts)
  build(wgt)
end

local function tick(wgt)
  local now = getTime()
  wgt.telem.poll(now)
  wgt.alerts.check(wgt.telem, wgt.opt, now)
  wgt.trail.sample(wgt.telem)
end

local function refresh(wgt, event, touchState)
  tick(wgt)
  if wgt.g then wgt.g.update(wgt.telem.pitch, wgt.telem.roll) end
  if wgt.mp then wgt.mp.update(wgt.telem) end
  if not lvgl then
    -- Pre-2.11 firmware: plain message instead of a broken screen
    lcd.drawText(4, 4, "WL Avionics " .. VERSION .. " needs EdgeTX 2.11+", SMLSIZE)
  elseif wgt.err then
    lvgl.clear()
    lvgl.build({ { type = "label", x = 4, y = 4, w = wgt.zone.w - 8, text = "WL Avionics: " .. wgt.err,
                   font = SMLSIZE, color = lcd.RGB(0xFF4D4F) } })
    wgt.err = nil
  end
end

-- Runs when the widget is not visible: keep telemetry and alerts alive.
local function background(wgt)
  tick(wgt)
end

return {
  name = "WL Avionics",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background,
  useLvgl = true,
}
