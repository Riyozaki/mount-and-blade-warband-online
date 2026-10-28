-- Calradia Online: Master WSE2 Campaign Server & Client Lua Entrypoint
-- Loaded automatically by WSE2 from Modules/CalradiaOnline/lua/main.lua (and reusable headlessly in tests!)

local pkg_dir = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$")
if pkg_dir and not package.path:find(pkg_dir, 1, true) then
  package.path = pkg_dir .. "/?.lua;" .. pkg_dir .. "/msfiles/?.lua;" .. package.path
end

local json            = require("json")
local sha256          = require("sha256")
local flight_recorder = require("flight_recorder")
local auth            = require("auth")
local persistence     = require("persistence")
local economy         = require("economy")
local quests          = require("quests")
local battles         = require("battles")
local politics        = require("politics")
local ipc_bridge      = require("ipc_bridge")

local CalradiaOnline = {}
CalradiaOnline.__index = CalradiaOnline

function CalradiaOnline.new(opts)
  opts = opts or {}
  local self = setmetatable({}, CalradiaOnline)
  self.world_name    = opts.world_name or "CalradiaWorld"
  self.save_dir      = opts.save_dir or "saves"
  self.cur_hour      = 0
  self.cur_day       = 0
  self.net_epoch     = 1

  self.recorder      = flight_recorder.new({ log_path = opts.flight_log_path, max_memory_events = 2048 })
  self.auth          = auth.new({ max_online = opts.max_online or 16, max_profiles = 32, server_salt = opts.server_salt })
  self.persistence   = persistence.new({ save_dir = self.save_dir, world_name = self.world_name })
  self.economy       = economy.new({ friendly_fire_pct = opts.friendly_fire_pct or 0 })
  self.quests        = quests.new({ specialist_officers_enabled = opts.specialist_officers_enabled ~= false })
  self.battles       = battles.new({ seed = opts.seed or 20261028 })
  self.politics      = politics.new({ speed_policy = opts.speed_policy or "min_online" })
  self.ipc           = ipc_bridge.new({ spool_dir = self.save_dir .. "/ipc" })

  return self
end

-- Snapshot entire authoritative campaign state into a deterministic table for persistence & SHA-256 digest
function CalradiaOnline:export_world_state()
  return {
    cur_hour = self.cur_hour,
    cur_day = self.cur_day,
    net_epoch = self.net_epoch,
    auth = self.auth:export_state(),
    players = self.economy.players,
    town_markets = self.economy.town_markets,
    quests = {
      next_instance_id = self.quests.next_instance_id,
      instances = self.quests.instances,
      giver_cooldowns = self.quests.giver_cooldowns,
      companions = self.quests.companions,
    },
    politics = {
      kingdoms = self.politics.kingdoms,
      fiefs = self.politics.fiefs,
      sieges = self.politics.sieges,
      brotherhoods = self.politics.brotherhoods,
      player_brotherhood = self.politics.player_brotherhood,
      courtships = self.politics.courtships,
      marriages = self.politics.marriages,
      diplomacy = self.politics.diplomacy,
    },
  }
end

function CalradiaOnline:import_world_state(st)
  if type(st) ~= "table" then return false end
  self.cur_hour  = tonumber(st.cur_hour or 0)
  self.cur_day   = tonumber(st.cur_day or 0)
  self.net_epoch = tonumber(st.net_epoch or 1) + 1 -- Bump epoch on load so stale packets drop cleanly!
  self.auth:import_state(st.auth)
  if type(st.players) == "table" then self.economy.players = st.players end
  if type(st.town_markets) == "table" then self.economy.town_markets = st.town_markets end
  if type(st.quests) == "table" then
    self.quests.next_instance_id = st.quests.next_instance_id or 1
    self.quests.instances = st.quests.instances or {}
    self.quests.giver_cooldowns = st.quests.giver_cooldowns or {}
    if st.quests.companions then self.quests.companions = st.quests.companions end
  end
  if type(st.politics) == "table" then
    if st.politics.kingdoms then self.politics.kingdoms = st.politics.kingdoms end
    if st.politics.fiefs then self.politics.fiefs = st.politics.fiefs end
    if st.politics.sieges then self.politics.sieges = st.politics.sieges end
    if st.politics.brotherhoods then self.politics.brotherhoods = st.politics.brotherhoods end
    if st.politics.player_brotherhood then self.politics.player_brotherhood = st.politics.player_brotherhood end
    if st.politics.courtships then self.politics.courtships = st.politics.courtships end
    if st.politics.marriages then self.politics.marriages = st.politics.marriages end
    if st.politics.diplomacy then self.politics.diplomacy = st.politics.diplomacy end
  end
  return true
end

function CalradiaOnline:save_campaign()
  local state = self:export_world_state()
  local ok, meta = self.persistence:save_world(state)
  self.recorder:record("WORLD_SAVE", { ok = ok, digest = meta and meta.sha256 or tostring(meta), hour = self.cur_hour })
  return ok, meta
end

function CalradiaOnline:load_campaign()
  local st, source = self.persistence:load_world()
  if not st then return false, source end
  self:import_world_state(st)
  self.recorder:record("WORLD_LOAD", { source = source, hour = self.cur_hour, epoch = self.net_epoch })
  return true, source
end

-- Advance Campaign World by 1 simulated game hour (called by WSE2 world trigger or headless test harness)
function CalradiaOnline:step_world_hour()
  local online_uids = {}
  for net_id, sess in pairs(self.auth.sessions_by_net) do
    if sess.authenticated and sess.uid then
      online_uids[#online_uids + 1] = sess.uid
    end
  end

  local speed = self.politics:recompute_effective_speed(online_uids)
  self.recorder:tick(1)
  if speed == 0 and #online_uids == 0 then
    return { paused = true, cur_hour = self.cur_hour }
  end

  self.cur_hour = self.cur_hour + 1
  local report = {
    cur_hour = self.cur_hour,
    effective_speed = speed,
    siege_events = self.politics:tick_sieges(self.cur_hour, 1),
    fief_events = self.politics:tick_fief_improvements(self.cur_hour),
    companion_returns = self.quests:tick_companions_and_taverns(self.economy, self.cur_hour),
    expired_quests = self.quests:tick_quest_deadlines(self.economy, self.cur_hour),
  }

  -- Captivity auto-escape & Wound Treatment hero/troop map regeneration every hour
  for uid, pl in pairs(self.economy.players) do
    self.battles:rescue_or_ransom_captive(self.economy, uid, nil, "tick_escape", self.cur_hour)
    local wt = self.economy:get_effective_party_skill(uid, "wound_treatment", self.quests.companions)
    if (pl.hp_pct or 100) < 100 then
      pl.hp_pct = math.min(100, pl.hp_pct + 2 + wt)
    end
    for _, st in ipairs(pl.party_stacks) do
      if (st.wounded or 0) > 0 and (self.cur_hour % math.max(2, 8 - math.floor(wt / 2)) == 0) then
        st.wounded = math.max(0, st.wounded - 1)
      end
    end
  end

  -- Native 14-hour Food Consumption cycle
  if self.cur_hour % 14 == 0 then
    for uid, _ in pairs(self.economy.players) do
      self.economy:tick_food_consumption(uid, self.cur_hour)
      self.quests:update_companion_morale(self.economy, uid)
    end
  end

  -- Daily Midnight Trainer XP & Town Trade Refresh (24h)
  if self.cur_hour % 24 == 0 then
    self.cur_day = self.cur_day + 1
    for uid, _ in pairs(self.economy.players) do
      self.economy:tick_daily_trainer(uid, self.quests.companions)
    end
  end

  -- Weekly Budget: Wages, Enterprise Profits, Mercenary Stipends, Fief Rents & Autosave (168h)
  if self.cur_hour % 168 == 0 then
    report.weekly_budgets = {}
    for uid, _ in pairs(self.economy.players) do
      local _, b = self.economy:tick_weekly_budget(uid, self.cur_hour)
      report.weekly_budgets[uid] = b
    end
    self:save_campaign()
  end

  return report
end

-- ============================================================================
-- WSE2 Runtime Binding (Automatically activates when running inside WSE2 `game` host)
-- ============================================================================
if rawget(_G, "game") ~= nil then
  local instance = CalradiaOnline.new({
    save_dir = "Modules/CalradiaOnline/saves",
    flight_log_path = "Modules/CalradiaOnline/logs/flight_recorder.cofr",
  })
  instance:load_campaign()
  _G.COOP = instance

  -- Expose global RPC functions callable from Module System via `(lua_call, "@coop_*", nargs)`
  function _G.coop_on_server_init()
    instance.recorder:record("WSE2_SERVER_INIT", { hour = instance.cur_hour })
    return 1
  end

  function _G.coop_issue_challenge(net_player_id)
    local nonce = instance.auth:issue_challenge(tonumber(net_player_id), os.time())
    game.sreg[0] = nonce
    return 1
  end

  function _G.coop_verify_login(net_player_id)
    local uid = game.sreg[0]
    local nick = game.sreg[1]
    local pub_token = game.sreg[2]
    local hmac_hex = game.sreg[3]
    local ok, res = instance.auth:verify_response(tonumber(net_player_id), uid, nick, pub_token, hmac_hex, os.time())
    if not ok then
      game.sreg[0] = tostring(res)
      return 0
    end
    instance.economy:ensure_player(res.uid, res.hero_slot, res.nickname)
    game.reg[0] = res.hero_slot
    game.reg[1] = res.reconnect and 1 or 0
    return 1
  end

  function _G.coop_set_speed_vote(net_player_id, speed_val)
    local sess = instance.auth:get_session_by_net(tonumber(net_player_id))
    if not sess or not sess.authenticated then return 0 end
    local ok, eff = instance.politics:set_speed_vote(sess.uid, tonumber(speed_val))
    if ok then
      game.reg[0] = eff
      return 1
    end
    return 0
  end

  function _G.coop_tick_hour()
    local rep = instance:step_world_hour()
    game.reg[0] = instance.politics.effective_speed
    return rep.paused and 0 or 1
  end

  -- Hook WSE2 Native Save/Load events so both layers stay synchronized
  if game.OnSave then
    game.OnSave = function()
      instance:save_campaign()
    end
  end
end

return CalradiaOnline
