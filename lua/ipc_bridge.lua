-- Calradia Online: Atomic Outbox/Inbox IPC Bridge between Campaign WSE2 Lua & CoopHostSupervisor / Battle Pool
-- Follows docs/ipc-battle-protocol.md with atomic .tmp rename guarantees.

local json = require("json")

local ipc_bridge = {}
ipc_bridge.__index = ipc_bridge

function ipc_bridge.new(opts)
  opts = opts or {}
  local self = setmetatable({}, ipc_bridge)
  self.spool_dir = opts.spool_dir or "saves/ipc"
  self.outbox_seq = 0
  self.processed_inbox = {}
  return self
end

local IS_WINDOWS = (package.config and package.config:sub(1, 1) == "\\")

function ipc_bridge:ensure_dirs()
  if IS_WINDOWS then
    local out_w = tostring(self.spool_dir .. "/outbox"):gsub("/", "\\")
    local in_w  = tostring(self.spool_dir .. "/inbox"):gsub("/", "\\")
    os.execute(string.format('if not exist "%s" mkdir "%s" >nul 2>nul', out_w, out_w))
    os.execute(string.format('if not exist "%s" mkdir "%s" >nul 2>nul', in_w, in_w))
  else
    os.execute(string.format('mkdir -p "%s/outbox" "%s/inbox" 2>/dev/null', self.spool_dir, self.spool_dir))
  end
end

local function atomic_write_json(path, payload)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return false, err end
  f:write(json.encode(payload))
  f:flush()
  f:close()
  os.remove(path)
  return os.rename(tmp, path)
end

-- Enqueue BATTLE_SPAWN_REQ or LIVE_REINFORCEMENT for CoopHostSupervisor
function ipc_bridge:send_to_supervisor(payload)
  self:ensure_dirs()
  self.outbox_seq = self.outbox_seq + 1
  local fname = string.format("%s/outbox/msg_%08d_%s.json",
    self.spool_dir, self.outbox_seq, tostring(payload.msg_type or "EVENT"))
  local ok, err = atomic_write_json(fname, payload)
  return ok, ok and fname or err
end

function ipc_bridge:request_battle_spawn(battle_node)
  local req = {
    msg_type = "BATTLE_SPAWN_REQ",
    battle_id = battle_node.battle_id,
    mission_kind = battle_node.mission_kind,
    scene_id = battle_node.scene_id,
    map_weather = battle_node.map_weather or { rain = 0, fog = 0, time_of_day = 12 },
    battle_advantage = battle_node.battle_advantage or 0.0,
    sides = { battle_node.sides[0], battle_node.sides[1] },
  }
  return self:send_to_supervisor(req)
end

-- Poll inbox messages written by CoopHostSupervisor / Dedicated Battle Servers
function ipc_bridge:poll_inbox_files(file_list)
  local messages = {}
  for _, full_path in ipairs(file_list or {}) do
    if not self.processed_inbox[full_path] and not full_path:match("%.tmp$") then
      local f = io.open(full_path, "rb")
      if f then
        local raw = f:read("*a")
        f:close()
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == "table" then
          self.processed_inbox[full_path] = true
          os.remove(full_path)
          messages[#messages + 1] = decoded
        end
      end
    end
  end
  return messages
end

return ipc_bridge
