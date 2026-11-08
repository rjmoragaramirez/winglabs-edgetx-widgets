-- WL Flight Stats widget - SD card storage of the last SLOTS flights per model.
--   logs/<model>.idx      one summary line per saved flight (small, read once at create)
--   logs/<model>_<k>.txt  series of flight slot k (read only when that flight is shown)
-- Slots rotate by sequence number, so a save writes one flight file plus the tiny index:
-- nothing large is serialized or parsed in a single Lua call.

local SLOTS = 8
local FIELDS = { "seq", "year", "mon", "day", "hour", "min", "dur", "maxAlt", "tAlt", "maxSpd", "tSpd",
                 "minV", "maxA", "used", "maxDist", "cells", "n" }
local SERIES = { "v", "c", "a", "s" }

local floor, concat, sort = math.floor, table.concat, table.sort

local function readAll(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local parts = {}
  while true do
    local chunk = io.read(f, 512)
    if not chunk or #chunk == 0 then break end
    parts[#parts + 1] = chunk
  end
  io.close(f)
  return concat(parts)
end

local function writeAll(path, text)
  local f = io.open(path, "w")
  if not f then return false end
  io.write(f, text)
  io.close(f)
  return true
end

-- Model name -> short file-safe key (letters/digits only)
local function modelKey()
  local name = ""
  if model and model.getInfo then
    local info = model.getInfo()
    name = info and info.name or ""
  end
  local key = name:gsub("[^%w]", ""):sub(1, 12)
  if key == "" then key = "MODEL" end
  return key
end

return function(dir)
  local st = { list = {}, key = modelKey(), slots = SLOTS }
  local base = dir .. st.key

  local function sortList()
    sort(st.list, function(a, b) return a.seq < b.seq end)
  end

  local function load()
    st.list = {}
    local txt = readAll(base .. ".idx")
    if not txt then return end
    for line in txt:gmatch("[^\n]+") do
      local f, i = {}, 0
      for num in line:gmatch("%-?%d+") do
        i = i + 1
        local k = FIELDS[i]
        if k then f[k] = tonumber(num) end
      end
      if i >= #FIELDS then st.list[#st.list + 1] = f end
    end
    sortList()
    while #st.list > SLOTS do table.remove(st.list, 1) end
  end

  local function saveIndex()
    local lines = {}
    for j, f in ipairs(st.list) do
      local row = {}
      for i, k in ipairs(FIELDS) do row[i] = floor(f[k] or 0) end
      lines[j] = concat(row, " ")
    end
    return writeAll(base .. ".idx", concat(lines, "\n") .. "\n")
  end

  local function slotPath(seq)
    return base .. "_" .. ((seq - 1) % SLOTS + 1) .. ".txt"
  end

  -- Save a finished flight (recorder output). Returns its summary entry.
  function st.save(fl)
    local last = st.list[#st.list]
    fl.seq = last and last.seq + 1 or 1
    local lines = {}
    for i, k in ipairs(SERIES) do lines[i] = concat(fl[k], ",") end
    -- the seq on top lets a stale slot file (index lost/rewritten) be detected
    writeAll(slotPath(fl.seq), fl.seq .. "\n" .. concat(lines, "\n") .. "\n")
    local sum = {}
    for _, k in ipairs(FIELDS) do sum[k] = fl[k] end
    st.list[#st.list + 1] = sum
    while #st.list > SLOTS do table.remove(st.list, 1) end
    saveIndex()
    return sum
  end

  -- Series of a saved flight: { v = {...}, c = {...}, a = {...}, s = {...} } or nil
  function st.series(sum)
    local txt = readAll(slotPath(sum.seq))
    if not txt then return nil end
    local out, row = {}, 0
    for line in txt:gmatch("[^\n]+") do
      if row == 0 then
        if tonumber(line) ~= sum.seq then return nil end
      else
        local k = SERIES[row]
        if not k then break end
        local s, i = {}, 0
        for num in line:gmatch("%-?%d+") do i = i + 1; s[i] = tonumber(num) end
        out[k] = s
      end
      row = row + 1
    end
    if not (out.v and out.c and out.a and out.s) then return nil end
    return out
  end

  load()
  return st
end
