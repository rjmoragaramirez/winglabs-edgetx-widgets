-- Minimal EdgeTX 2.11 Lua API mock for desktop testing of the WL Attitude Ind widget.
-- Mirrors the strictness of the firmware where it matters:
--  * integer-only coordinates (luaL_checkinteger), unsigned line/triangle points
--  * unknown LVGL properties raise "Invalid property"
--  * per-call instruction limit (EdgeTX: 100 hook ticks x 200 instructions)

local M = { log = {}, now = 0, sensors = {}, vals = {}, linked = false, lq = 0 }
local ROOT = ...  -- local folder that maps to /WIDGETS/WLAttitudeInd/

-- constants -----------------------------------------------------------------
LEFT, RIGHT, CENTER, VCENTER = 0, 0x04, 0x08, 0x10
BOLD, SMLSIZE, MIDSIZE, DBLSIZE, XXLSIZE, TINSIZE = 0x100, 0x200, 0x300, 0x400, 0x500, 0x700
PREC1, PREC2 = 0x10, 0x20
COLOR, BOOL, VALUE, SOURCE, STRING, CHOICE = 1, 2, 3, 4, 5, 6
PLAY_NOW, PLAY_BACKGROUND = 1, 2
UNIT_RAW, UNIT_VOLTS, UNIT_METERS, UNIT_FEET, UNIT_DEGREE, UNIT_RADIANS, UNIT_DB = 0, 1, 9, 10, 22, 23, 18

-- api -----------------------------------------------------------------------
function getTime() return M.now end
function getRSSI() return M.linked and M.lq or 0, 45, 42 end
function getFieldInfo(name)
  local s = M.sensors[name]
  if not s then return nil end
  return { id = s.id, name = name, unit = s.unit }
end
function getValue(id)
  if not M.linked then
    local v = M.vals[id]
    if type(v) == "table" then return 0 end
    if type(v) == "string" then return "" end
    return 0
  end
  local v = M.vals[id]
  if v == nil then return 0 end
  return v
end
function playTone(f, d, p, fl, inc) M.log[#M.log + 1] = string.format("%.2fs tone %d", M.now / 100, f) end
function playNumber(v, u, fl) M.log[#M.log + 1] = string.format("%.2fs number %s u%d", M.now / 100, tostring(v), u) end
function playHaptic(d, p, fl) M.log[#M.log + 1] = string.format("%.2fs haptic %d/%d%s", M.now / 100, d, p, fl == PLAY_NOW and " NOW" or "") end
function playFile(f) M.log[#M.log + 1] = "file " .. f end

lcd = {}
function lcd.RGB(r, g, b)
  if g then r = r * 65536 + g * 256 + b end
  assert(math.type(r) == "integer", "lcd.RGB expects integer")
  return 0x1000000 | r
end
function lcd.drawText() end

function loadScript(path, mode)
  local rel = path:gsub("^/WIDGETS/WLAttitudeInd/", "")
  return loadfile(ROOT .. rel, "t")
end

-- lvgl mock -------------------------------------------------------------------
local COMMON = { x = 1, y = 1, w = 1, h = 1, color = 1, opacity = 1, visible = 1, size = 1, pos = 1,
                 floating = 1, children = 1, type = 1, name = 1 }
local EXTRA = {
  label = { text = 1, font = 1, align = 1 },
  rectangle = { filled = 1, thickness = 1, rounded = 1 },
  circle = { radius = 1, filled = 1, thickness = 1 },
  arc = { radius = 1, thickness = 1, startAngle = 1, endAngle = 1, rounded = 1, bgColor = 1, bgOpacity = 1,
          bgStartAngle = 1, bgEndAngle = 1 },
  line = { pts = 1, thickness = 1, rounded = 1, dashGap = 1, dashWidth = 1 },
  triangle = { pts = 1 },
  box = { scrollDir = 1, scrollBar = 1, scrollTo = 1, scrolled = 1, align = 1, flexFlow = 1, flexPad = 1 },
}
local INT_KEYS = { x = 1, y = 1, w = 1, h = 1, radius = 1, thickness = 1, rounded = 1, startAngle = 1,
                   endAngle = 1, opacity = 1, bgOpacity = 1, scrollDir = 1 }

lvgl = { LCD_SCALE = 1 }
M.tree = {}

local function checkPts(pts, where)
  assert(type(pts) == "table", where .. ": pts must be a table")
  for i, p in ipairs(pts) do
    for k = 1, 2 do
      local v = p[k]
      assert(math.type(v) == "integer", where .. ": point " .. i .. " not integer: " .. tostring(v))
      assert(v >= 0, where .. ": negative point (LVGL reads unsigned) " .. v)
    end
  end
end

local function mk(spec, path)
  local ty = spec.type
  assert(EXTRA[ty], path .. ": unknown type " .. tostring(ty))
  local node = { type = ty, props = {}, children = {} }
  for k, v in pairs(spec) do
    if not COMMON[k] and not EXTRA[ty][k] then error(path .. ": Invalid property '" .. k .. "'") end
    if INT_KEYS[k] and type(v) ~= "function" and type(v) ~= "boolean" then
      assert(math.type(v) == "integer", path .. ": " .. k .. " must be integer, got " .. tostring(v))
    end
    if k ~= "children" then node.props[k] = v end
  end
  if ty == "line" and type(spec.pts) == "table" then checkPts(spec.pts, path) end
  if spec.children then
    for i, c in ipairs(spec.children) do node.children[i] = mk(c, path .. "/" .. ty .. i) end
  end
  return node
end

function lvgl.clear() M.tree = {} end
function lvgl.build(parent, tbl)
  if tbl == nil then tbl = parent end
  for i, spec in ipairs(tbl) do M.tree[#M.tree + 1] = mk(spec, "root" .. (#M.tree + 1)) end
end
function lvgl.isFullScreen() return true end

-- Evaluate every dynamic property like EdgeTX's callRefs(); returns resolved tree.
-- M.cbInstr counts only instructions spent inside the widget's callbacks: on the radio the
-- tree walk is C code, so only the Lua callbacks count against the instruction limit.
M.cbInstr = 0
local function call(v)
  local hook, mask, cnt = debug.gethook()
  debug.sethook(function() M.cbInstr = M.cbInstr + 1 end, "", 1)
  local a, b = v()
  debug.sethook(hook, mask, cnt)
  return a, b
end
local function resolve(node, path)
  local r = { type = node.type, children = {} }
  for k, v in pairs(node.props) do
    if type(v) == "function" and k ~= "scrolled" then
      if k == "size" or k == "pos" then
        local a, b = call(v)
        assert(math.type(a) == "integer" and math.type(b) == "integer", path .. ": " .. k .. " fn must return integers")
        if k == "size" then r.w, r.h = a, b else r.x, r.y = a, b end
      else
        v = call(v)
        r[k] = v
      end
    elseif r[k] == nil then
      r[k] = v
    end
  end
  if r.visible == false then r.hidden = true end
  if r.type == "line" then checkPts(r.pts, path) end
  if r.type == "label" then assert(type(r.text) == "string", path .. ": label text must be string, got " .. type(r.text)) end
  if r.color ~= nil then assert(math.type(r.color) == "integer", path .. ": color must be integer") end
  for i, c in ipairs(node.children) do r.children[i] = resolve(c, path .. "/" .. c.type .. i) end
  return r
end
function M.resolve()
  M.cbInstr = 0
  local out = {}
  for i, n in ipairs(M.tree) do out[i] = resolve(n, "root" .. i) end
  return out
end

-- instruction counting --------------------------------------------------------
function M.counted(fn, ...)
  local n = 0
  debug.sethook(function() n = n + 1 end, "", 100)
  local ok, err = pcall(fn, ...)
  debug.sethook()
  if not ok then error(err, 0) end
  return n * 100
end

-- bytes allocated by fn (GC stopped while it runs)
function M.alloc(fn, ...)
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  fn(...)
  local after = collectgarbage("count")
  collectgarbage("restart")
  return (after - before) * 1024
end

return M
