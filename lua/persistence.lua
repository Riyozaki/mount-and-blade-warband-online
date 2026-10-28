-- Calradia Online: Atomic Save/Load Engine with SHA-256 Envelopes & Rolling Backups
-- Protects world state and player profiles against power-loss corruption.

local json = require("json")
local sha256 = require("sha256")

local persistence = {}
persistence.__index = persistence

local SCHEMA_VERSION = 1
local IS_WINDOWS = (package.config and package.config:sub(1, 1) == "\\")

local function ensure_dir(dir_path)
  if IS_WINDOWS then
    local win_p = tostring(dir_path):gsub("/", "\\")
    os.execute(string.format('if not exist "%s" mkdir "%s" >nul 2>nul', win_p, win_p))
  else
    os.execute(string.format('mkdir -p "%s" 2>/dev/null', dir_path))
  end
end

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_all(path, content)
  local f, err = io.open(path, "wb")
  if not f then
    return false, err
  end
  f:write(content)
  f:flush()
  f:close()
  return true
end

local function wrap_envelope(kind, payload)
  local body_json = json.encode(payload, false)
  local checksum = sha256.hex(body_json)
  return json.encode({
    schema_version = SCHEMA_VERSION,
    kind = kind,
    saved_at = os.time(),
    sha256 = checksum,
    payload = payload,
  }, true)
end

local function unwrap_envelope(raw_str, expected_kind)
  if type(raw_str) ~= "string" or raw_str == "" then
    return nil, "empty_file"
  end
  local ok, env = pcall(json.decode, raw_str)
  if not ok or type(env) ~= "table" or type(env.payload) ~= "table" then
    return nil, "malformed_json"
  end
  if expected_kind and env.kind ~= expected_kind then
    return nil, "kind_mismatch"
  end
  local canonical = json.encode(env.payload, false)
  local actual_hash = sha256.hex(canonical)
  if env.sha256 ~= actual_hash then
    return nil, "checksum_mismatch"
  end
  return env.payload, nil
end

function persistence.new(base_dir_or_opts, max_backups)
  local self = setmetatable({}, persistence)
  if type(base_dir_or_opts) == "table" then
    local sdir = tostring(base_dir_or_opts.save_dir or "saves"):gsub("/+$", "")
    local wname = tostring(base_dir_or_opts.world_name or "default_world")
    self.base_dir = sdir .. "/" .. wname
    self.max_backups = base_dir_or_opts.max_backups or 5
  else
    self.base_dir = tostring(base_dir_or_opts or "saves/default_world"):gsub("/+$", "")
    self.max_backups = max_backups or 5
  end
  ensure_dir(self.base_dir .. "/players")
  return self
end

function persistence:atomic_save_file(rel_path, kind, data_tbl)
  local target = self.base_dir .. "/" .. rel_path
  local tmp = target .. ".tmp"
  local encoded = wrap_envelope(kind, data_tbl)

  -- Rotate previous valid file into rolling .bak1 .. .bakN
  local existing = read_all(target)
  if existing then
    local valid_existing = unwrap_envelope(existing, kind)
    if valid_existing then
      for i = self.max_backups - 1, 1, -1 do
        local src_b = target .. ".bak" .. tostring(i)
        local dst_b = target .. ".bak" .. tostring(i + 1)
        local b_data = read_all(src_b)
        if b_data then
          write_all(dst_b, b_data)
        end
      end
      write_all(target .. ".bak1", existing)
    end
  end

  local ok_w, err_w = write_all(tmp, encoded)
  if not ok_w then
    return false, "write_tmp_failed: " .. tostring(err_w)
  end

  -- Verify written temporary file before replacing primary file
  local verify_raw = read_all(tmp)
  local verified_payload, v_err = unwrap_envelope(verify_raw, kind)
  if not verified_payload then
    os.remove(tmp)
    return false, "verify_tmp_failed: " .. tostring(v_err)
  end

  -- On Windows os.rename fails if destination exists; remove destination first after .bak1 is safely written
  os.remove(target)
  local ok_r, err_r = os.rename(tmp, target)
  if not ok_r then
    -- Fallback copy if cross-device or OS quirk
    local ok_c, err_c = write_all(target, verify_raw)
    os.remove(tmp)
    if not ok_c then
      return false, "rename_and_copy_failed: " .. tostring(err_r) .. " / " .. tostring(err_c)
    end
  end
  return true, nil
end

function persistence:load_file_with_recovery(rel_path, kind)
  local target = self.base_dir .. "/" .. rel_path
  local raw = read_all(target)
  if raw then
    local payload, _ = unwrap_envelope(raw, kind)
    if payload then
      return payload, "primary"
    end
  end

  -- Primary missing or corrupted: try rolling backups .bak1 .. .bakN
  for i = 1, self.max_backups do
    local bak_path = target .. ".bak" .. tostring(i)
    local bak_raw = read_all(bak_path)
    if bak_raw then
      local payload, _ = unwrap_envelope(bak_raw, kind)
      if payload then
        -- Self-heal primary from valid backup
        write_all(target, bak_raw)
        return payload, target .. ".bak" .. tostring(i)
      end
    end
  end
  return nil, "not_found"
end

function persistence:save_world_bundle(bundle)
  local ok, err
  ok, err = self:atomic_save_file("world_meta.json", "world_meta", bundle.world_meta or {})
  if not ok then return false, err end

  ok, err = self:atomic_save_file("quests.json", "quests", bundle.quests or {})
  if not ok then return false, err end

  ok, err = self:atomic_save_file("enterprises.json", "enterprises", bundle.enterprises or {})
  if not ok then return false, err end

  ok, err = self:atomic_save_file("kingdoms.json", "kingdoms", bundle.kingdoms or {})
  if not ok then return false, err end

  ok, err = self:atomic_save_file("companions.json", "companions", bundle.companions or {})
  if not ok then return false, err end

  if type(bundle.players) == "table" then
    for uid, profile in pairs(bundle.players) do
      ok, err = self:atomic_save_file("players/" .. tostring(uid) .. ".json", "player_profile", profile)
      if not ok then return false, err end
    end
  end
  return true, nil
end

function persistence:load_world_bundle(known_uids)
  local world_meta, src = self:load_file_with_recovery("world_meta.json", "world_meta")
  if not world_meta then
    return nil, src
  end
  local quests = self:load_file_with_recovery("quests.json", "quests") or {}
  local enterprises = self:load_file_with_recovery("enterprises.json", "enterprises") or {}
  local kingdoms = self:load_file_with_recovery("kingdoms.json", "kingdoms") or {}
  local companions = self:load_file_with_recovery("companions.json", "companions") or {}

  local players = {}
  local uid_list = known_uids or world_meta.registered_uids or {}
  for _, uid in ipairs(uid_list) do
    local p = self:load_file_with_recovery("players/" .. tostring(uid) .. ".json", "player_profile")
    if p then
      players[uid] = p
    end
  end

  return {
    world_meta = world_meta,
    quests = quests,
    enterprises = enterprises,
    kingdoms = kingdoms,
    companions = companions,
    players = players,
  }, src
end

function persistence:save_world(world_state)
  ensure_dir(self.base_dir)
  local ok, err = self:atomic_save_file("world.json", "world_state", world_state)
  if not ok then return false, err end
  return true, { path = self.base_dir .. "/world.json" }
end

function persistence:load_world()
  return self:load_file_with_recovery("world.json", "world_state")
end

return persistence
