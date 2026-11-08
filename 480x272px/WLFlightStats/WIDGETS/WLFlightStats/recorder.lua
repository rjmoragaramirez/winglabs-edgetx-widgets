-- WL Flight Stats widget - flight recorder.
-- While armed, telemetry is aggregated into fixed-interval buckets (min voltage, max current,
-- max altitude, max speed per bucket) so sags and peaks survive any decimation. The series is
-- bounded: when it reaches MAX_PTS, pairs are merged and the interval doubles, so a flight of
-- any length uses the same memory. Peaks and their times are tracked at the full poll rate.
--
-- Stored units (integers): volt cV, curr dA, alt dm, speed d(km/h), dist m, times s.

local MAX_PTS = 240        -- recorded buckets before a 2:1 merge
local PLOT_PTS = 120       -- points saved per series
local AGG_TICKS = 10       -- aggregate at 10 Hz (telemetry slow rate)
local START_INTERVAL = 100 -- first bucket length, 10 ms ticks (1 s)
local LOST_TICKS = 2000    -- armed without link this long = flight over (model off / lost)

local floor, max, min = math.floor, math.max, math.min

return function()
  local r = { active = false, needDisarm = false, done = nil, minFlight = 20 }
  local V, C, A, S, n, interval, t0, nextBucket, nextAgg
  local bv, bc, ba, bs, bn    -- current bucket aggregates, samples in bucket
  local st                    -- running stats
  local lostSince

  local function start(now, t)
    V, C, A, S, n = {}, {}, {}, {}, 0
    interval, t0 = START_INTERVAL, now
    nextBucket, nextAgg = now + interval, now
    bv, bc, ba, bs, bn = nil, 0, 0, 0, 0
    st = { maxAlt = 0, tAlt = 0, maxSpd = 0, tSpd = 0, minV = nil, maxA = 0, maxDist = 0, cells = 0 }
    lostSince = nil
    r.active = true
  end

  local function merge()
    local h = floor(n / 2)
    for i = 1, h do
      local a, b = 2 * i - 1, 2 * i
      V[i], C[i], A[i], S[i] = min(V[a], V[b]), max(C[a], C[b]), max(A[a], A[b]), max(S[a], S[b])
    end
    for i = h + 1, n do V[i], C[i], A[i], S[i] = nil, nil, nil, nil end
    n = h
    interval = interval * 2
  end

  local function closeBucket()
    n = n + 1
    if bn > 0 then
      V[n], C[n], A[n], S[n] = bv or (V[n - 1] or 0), bc, ba, bs
    else  -- no telemetry in this bucket (link lost): hold the last values
      V[n], C[n], A[n], S[n] = V[n - 1] or 0, C[n - 1] or 0, A[n - 1] or 0, S[n - 1] or 0
    end
    bv, bc, ba, bs, bn = nil, 0, 0, 0, 0
    if n >= MAX_PTS then merge() end
  end

  -- Resample into at most PLOT_PTS points with the same min/max aggregation
  local function resample(src, useMin)
    if n <= PLOT_PTS then
      local out = {}
      for i = 1, n do out[i] = src[i] end
      return out
    end
    local out = {}
    for j = 1, PLOT_PTS do
      local i0, i1 = floor((j - 1) * n / PLOT_PTS) + 1, floor(j * n / PLOT_PTS)
      local v = src[i0]
      for i = i0 + 1, i1 do
        if useMin then v = min(v, src[i]) else v = max(v, src[i]) end
      end
      out[j] = v
    end
    return out
  end

  local function finish(endTime, t)
    r.active = false
    if bn > 0 then closeBucket() end
    local dur = floor((endTime - t0) / 100)
    if dur < r.minFlight or n < 2 then V, C, A, S = nil, nil, nil, nil; return end
    local dt = getDateTime and getDateTime() or {}
    r.final = {
      year = dt.year or 0, mon = dt.mon or 0, day = dt.day or 0, hour = dt.hour or 0, min = dt.min or 0,
      dur = dur, maxAlt = st.maxAlt, tAlt = st.tAlt, maxSpd = st.maxSpd, tSpd = st.tSpd,
      minV = st.minV or 0, maxA = st.maxA, used = floor(t.capa or 0), maxDist = st.maxDist,
      cells = st.cells, step = 1,
    }
  end

  -- Resample one series per call after a flight ended (spreads the CPU cost over 4 ticks)
  local function finalize()
    local f = r.final
    local k = f.step
    if k == 1 then f.v = resample(V, true)
    elseif k == 2 then f.c = resample(C)
    elseif k == 3 then f.a = resample(A)
    else
      f.s = resample(S)
      f.n, f.step = #f.v, nil
      V, C, A, S = nil, nil, nil, nil
      r.final, r.done = nil, f
      return
    end
    f.step = k + 1
  end

  -- Called every tick with the shared telemetry table. Sets r.done when a flight is saved.
  function r.update(t, now)
    if r.final then return finalize() end
    if not r.active then
      if t.linked and not t.armed then r.needDisarm = false end
      if t.armed and t.linked and not r.needDisarm then start(now, t) end
      return
    end
    if not t.armed then return finish(now, t) end
    if not t.linked then
      lostSince = lostSince or now
      if now - lostSince >= LOST_TICKS then
        r.needDisarm = true
        return finish(lostSince, t)
      end
    else
      lostSince = nil
    end

    if now < nextAgg then return end
    nextAgg = now + AGG_TICKS
    if t.linked then
      local sec = floor((now - t0) / 100)
      local v = floor(t.volt * 100 + 0.5)
      local c = floor(t.curr * 10 + 0.5)
      local a = floor(max(0, t.alt) * 10 + 0.5)
      local s = floor(t.spd * 10 + 0.5)
      bn = bn + 1
      if v > 0 then
        bv = bv and min(bv, v) or v
        if not st.minV or v < st.minV then st.minV = v end
      end
      if c > bc then bc = c end
      if a > ba then ba = a end
      if s > bs then bs = s end
      if c > st.maxA then st.maxA = c end
      if a > st.maxAlt then st.maxAlt, st.tAlt = a, sec end
      if s > st.maxSpd then st.maxSpd, st.tSpd = s, sec end
      if t.home and t.dist > st.maxDist then st.maxDist = floor(t.dist + 0.5) end
      if t.cells > 0 then st.cells = t.cells end
    end
    if now >= nextBucket then
      closeBucket()
      nextBucket = t0 + (n + 1) * interval  -- exact edge, also right after a 2:1 merge
    end
  end

  -- Live recording time in seconds (0 when idle)
  function r.elapsed(now)
    return r.active and floor((now - t0) / 100) or 0
  end

  return r
end
