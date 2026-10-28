-- Calradia Online: Flight Recorder (`cofr` JSONL trace + deterministic world digest)
-- Inspired by cranebeaker/coop-anything/tools/flight for instant desync pinpointing.

local json = require("json")
local sha256 = require("sha256")

local flight = {}
flight.__index = flight

function flight.new(opts)
  opts = opts or {}
  local self = setmetatable({}, flight)
  self.role = opts.role or "campaign_server"
  self.log_path = opts.log_path or nil
  self.max_ring = opts.max_ring or 512
  self.seq = 0
  self.ring = {}
  self.enabled = opts.enabled ~= false
  return self
end

function flight:record(category, event_name, payload, state_digest)
  if not self.enabled then
    return nil
  end
  self.seq = self.seq + 1
  local entry = {
    seq = self.seq,
    role = self.role,
    ts = os.time(),
    cat = tostring(category),
    ev = tostring(event_name),
    data = payload or {},
    digest = state_digest or "",
  }
  self.ring[#self.ring + 1] = entry
  if #self.ring > self.max_ring then
    table.remove(self.ring, 1)
  end
  if self.log_path then
    local f = io.open(self.log_path, "a")
    if f then
      f:write(json.encode(entry) .. "\n")
      f:close()
    end
  end
  return entry
end

function flight.compute_world_digest(summary_tbl)
  local canonical = json.encode(summary_tbl, false)
  return sha256.hex(canonical):sub(1, 16)
end

function flight:world_digest(summary_tbl)
  return flight.compute_world_digest(summary_tbl)
end

function flight:tick(dt)
  self.cur_tick = (self.cur_tick or 0) + (dt or 1)
  return self.cur_tick
end

function flight:get_recent(count)
  count = count or 20
  local out = {}
  local start_idx = math.max(1, #self.ring - count + 1)
  for i = start_idx, #self.ring do
    out[#out + 1] = self.ring[i]
  end
  return out
end

function flight.find_first_divergence(trace_a, trace_b)
  local n = math.min(#trace_a, #trace_b)
  for i = 1, n do
    local a, b = trace_a[i], trace_b[i]
    if a.ev ~= b.ev or (a.digest ~= "" and b.digest ~= "" and a.digest ~= b.digest) then
      return i, a, b
    end
  end
  if #trace_a ~= #trace_b then
    return n + 1, trace_a[n + 1], trace_b[n + 1]
  end
  return nil, nil, nil
end

return flight
