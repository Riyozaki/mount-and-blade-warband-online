-- Calradia Online: Steam-Independent Cryptographic Authentication & Anti-Spoof Session Manager
-- Protects player profiles in LAN, Radmin VPN, Direct IP, GOG, Standalone, and Steam alike.

local sha256 = require("sha256")

local auth = {}
auth.__index = auth

local MAX_HERO_SLOTS = 32 -- trp_coop_hero_0 .. trp_coop_hero_31

function auth.derive_player_uid(secret_hex)
  return "p_" .. sha256.hex("calradia_uid_v1:" .. tostring(secret_hex):lower()):sub(1, 24)
end

function auth.derive_verifier_key(secret_hex)
  return sha256.hex("calradia_auth_key_v1:" .. tostring(secret_hex):lower())
end

function auth.compute_client_signature(secret_hex, nonce, player_uid)
  local auth_key = auth.derive_verifier_key(secret_hex)
  return sha256.hmac_hex(auth_key, tostring(nonce) .. ":" .. tostring(player_uid))
end

function auth:derive_identity(secret_hex)
  local sec = tostring(secret_hex):lower()
  local uid = auth.derive_player_uid(sec)
  local akey = auth.derive_verifier_key(sec)
  return {
    secret_hex = sec,
    uid = uid,
    auth_key = akey,
    public_token = akey,
  }
end

function auth:sign_challenge(auth_key, nonce, player_uid, _nickname)
  return sha256.hmac_hex(tostring(auth_key):lower(), tostring(nonce) .. ":" .. tostring(player_uid))
end

function auth.new(opts)
  opts = opts or {}
  local self = setmetatable({}, auth)
  self.max_profiles = opts.max_profiles or MAX_HERO_SLOTS
  self.server_salt = opts.server_salt or sha256.hex(tostring(os.time()) .. ":calradia_online")
  self.nonce_counter = 0
  self.registered = {}
  self.nick_owner = {}
  self.pending = {}
  self.sessions = {}
  self.sessions_by_net = self.sessions
  self.uid_to_player_no = {}
  return self
end

function auth:export_registry()
  local out = {}
  for uid, rec in pairs(self.registered) do
    out[uid] = {
      auth_key = rec.auth_key,
      hero_slot = rec.hero_slot,
      nickname = rec.nickname,
      created_at = rec.created_at,
    }
  end
  return out
end

auth.export_state = auth.export_registry

function auth:import_registry(tbl)
  self.registered = {}
  self.nick_owner = {}
  if type(tbl) ~= "table" then
    return
  end
  for uid, rec in pairs(tbl) do
    self.registered[uid] = {
      auth_key = rec.auth_key,
      hero_slot = tonumber(rec.hero_slot),
      nickname = tostring(rec.nickname or ""),
      created_at = tonumber(rec.created_at or 0),
    }
    if rec.nickname and rec.nickname ~= "" then
      self.nick_owner[rec.nickname:lower()] = uid
    end
  end
end

auth.import_state = auth.import_registry

function auth:allocate_hero_slot()
  local used = {}
  for _, rec in pairs(self.registered) do
    if rec.hero_slot ~= nil then
      used[rec.hero_slot] = true
    end
  end
  for slot = 0, self.max_profiles - 1 do
    if not used[slot] then
      return slot
    end
  end
  return nil
end

function auth:issue_challenge(player_no, now_ts)
  self.nonce_counter = self.nonce_counter + 1
  now_ts = now_ts or os.time()
  local nonce = sha256.hex(
    self.server_salt .. ":" .. tostring(player_no) .. ":" .. tostring(now_ts) .. ":" .. tostring(self.nonce_counter)
  ):sub(1, 32)
  self.pending[player_no] = {
    nonce = nonce,
    issued_at = now_ts,
  }
  return nonce
end

-- Accepts either `(player_no, payload_table, now_ts)` OR `(player_no, uid, nickname, auth_key, sig_hex, now_ts)`
function auth:verify_response(player_no, a, b, c, d, e)
  local payload
  local now_ts
  if type(a) == "table" then
    payload = a
    now_ts = tonumber(b) or os.time()
  else
    payload = {
      player_uid = a,
      nickname = b,
      auth_key = c,
      signature_hex = d,
    }
    now_ts = tonumber(e) or os.time()
  end

  local ch = self.pending[player_no]
  if not ch then
    return false, "no_pending_challenge"
  end
  if now_ts - ch.issued_at > 60 then
    self.pending[player_no] = nil
    return false, "challenge_expired"
  end

  local uid = tostring(payload.player_uid or "")
  local sig = tostring(payload.signature_hex or ""):lower()
  local nickname = tostring(payload.nickname or "Adventurer"):gsub("^%s+", ""):gsub("%s+$", "")
  if nickname == "" then
    nickname = "Adventurer"
  end
  if not uid:match("^p_%x+$") or #uid ~= 26 then
    return false, "invalid_player_uid"
  end

  local nick_key = nickname:lower()
  if self.nick_owner[nick_key] and self.nick_owner[nick_key] ~= uid then
    return false, "nickname_taken_by_another_key"
  end

  local rec = self.registered[uid]
  local is_reconnect = (rec ~= nil)
  local auth_key
  if rec then
    local presented = tostring(payload.auth_key or ""):lower()
    if presented ~= "" and #presented == 64 and presented ~= rec.auth_key then
      return false, "impersonation_detected"
    end
    auth_key = rec.auth_key
  else
    local presented_key = tostring(payload.auth_key or ""):lower()
    if not presented_key:match("^%x+$") or #presented_key ~= 64 then
      return false, "missing_enrollment_auth_key"
    end
    auth_key = presented_key
  end

  local expected_sig = sha256.hmac_hex(auth_key, ch.nonce .. ":" .. uid)
  if not sha256.constant_time_eq(sig, expected_sig) then
    return false, "impersonation_detected"
  end

  local prev_pno = self.uid_to_player_no[uid]
  if prev_pno and prev_pno ~= player_no then
    self.sessions[prev_pno] = nil
  end

  if not rec then
    local slot = self:allocate_hero_slot()
    if slot == nil then
      return false, "world_hero_slots_full"
    end
    rec = {
      auth_key = auth_key,
      hero_slot = slot,
      nickname = nickname,
      created_at = now_ts,
    }
    self.registered[uid] = rec
  else
    if rec.nickname ~= "" and self.nick_owner[rec.nickname:lower()] == uid then
      self.nick_owner[rec.nickname:lower()] = nil
    end
    rec.nickname = nickname
  end

  self.nick_owner[nick_key] = uid
  self.pending[player_no] = nil

  local session = {
    player_no = player_no,
    authenticated = true,
    reconnect = is_reconnect,
    uid = uid,
    hero_slot = rec.hero_slot,
    nickname = nickname,
    combat_lock_until = 0,
    connected_at = now_ts,
  }
  self.sessions[player_no] = session
  self.uid_to_player_no[uid] = player_no
  return true, session
end

function auth:get_session_by_net(player_no)
  return self.sessions[player_no]
end

function auth:on_disconnect(player_no, in_combat, now_ts)
  now_ts = now_ts or os.time()
  local sess = self.sessions[player_no]
  if not sess then return nil end
  self.sessions[player_no] = nil
  if self.uid_to_player_no[sess.uid] == player_no then
    self.uid_to_player_no[sess.uid] = nil
  end
  return {
    uid = sess.uid,
    grace_despawn_at = in_combat and (now_ts + 30) or now_ts,
  }
end

return auth
