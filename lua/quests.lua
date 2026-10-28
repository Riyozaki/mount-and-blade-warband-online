-- Calradia Online: Instanced Quest Engine & Global 16-Companion + Specialist Officer Manager
-- Solves the Native singleton `qst_*` table limitation so N players run quests independently or in co-op.

local quests = {}
quests.__index = quests

-- All 16 iconic Native Warband companions with exact Native admiration/dislike pairs & primary specialties
quests.COMPANION_CATALOG = {
  trp_npc1  = { name = "Borcha",     cost = 300, noble = false, likes = "trp_npc8",  dislikes = { "trp_npc7", "trp_npc16" }, skills = { tracking = 3, path_finding = 3, spotting = 3, trainer = 1 } },
  trp_npc2  = { name = "Marnid",     cost = 0,   noble = false, likes = "trp_npc1",  dislikes = { "trp_npc5", "trp_npc9" },  skills = { trade = 3, inventory_management = 2, wound_treatment = 1 } },
  trp_npc3  = { name = "Ymira",      cost = 0,   noble = false, likes = "trp_npc9",  dislikes = { "trp_npc8", "trp_npc14" }, skills = { wound_treatment = 3, surgery = 1, first_aid = 3, trade = 1 } },
  trp_npc4  = { name = "Rolf",       cost = 300, noble = true,  likes = "trp_npc5",  dislikes = { "trp_npc10", "trp_npc6" }, skills = { tactics = 2, leadership = 2, athletics = 2 } },
  trp_npc5  = { name = "Baheshtur",  cost = 400, noble = true,  likes = "trp_npc4",  dislikes = { "trp_npc11", "trp_npc2" }, skills = { horse_archery = 3, power_draw = 2, riding = 3 } },
  trp_npc6  = { name = "Firentis",   cost = 0,   noble = true,  likes = "trp_npc12", dislikes = { "trp_npc11", "trp_npc4" }, skills = { trainer = 2, athletics = 2, power_strike = 2 } },
  trp_npc7  = { name = "Deshavi",    cost = 300, noble = false, likes = "trp_npc16", dislikes = { "trp_npc1", "trp_npc12" }, skills = { path_finding = 3, spotting = 3, tracking = 2, power_draw = 2 } },
  trp_npc8  = { name = "Matheld",    cost = 500, noble = true,  likes = "trp_npc13", dislikes = { "trp_npc3", "trp_npc12" }, skills = { tactics = 2, power_strike = 3, athletics = 3 } },
  trp_npc9  = { name = "Alayen",     cost = 300, noble = true,  likes = "trp_npc3",  dislikes = { "trp_npc2", "trp_npc13" }, skills = { tactics = 1, power_strike = 2, riding = 2, trainer = 1 } },
  trp_npc10 = { name = "Bunduk",     cost = 200, noble = false, likes = "trp_npc11", dislikes = { "trp_npc4", "trp_npc14" }, skills = { trainer = 2, tactics = 2, first_aid = 2, ironflesh = 3 } },
  trp_npc11 = { name = "Katrin",     cost = 100, noble = false, likes = "trp_npc10", dislikes = { "trp_npc6", "trp_npc5" },  skills = { inventory_management = 5, first_aid = 1, wound_treatment = 1, trade = 2 } },
  trp_npc12 = { name = "Jeremus",    cost = 0,   noble = false, likes = "trp_npc6",  dislikes = { "trp_npc15", "trp_npc8" }, skills = { surgery = 4, wound_treatment = 4, first_aid = 3, trade = 1 } },
  trp_npc13 = { name = "Nizar",      cost = 300, noble = false, likes = "trp_npc8",  dislikes = { "trp_npc9", "trp_npc15" }, skills = { riding = 3, power_strike = 2, leadership = 2 } },
  trp_npc14 = { name = "Lezalit",    cost = 400, noble = true,  likes = "trp_npc15", dislikes = { "trp_npc3", "trp_npc10" }, skills = { trainer = 4, tactics = 2, power_strike = 2 } },
  trp_npc15 = { name = "Artimenner", cost = 300, noble = false, likes = "trp_npc14", dislikes = { "trp_npc12", "trp_npc16" }, skills = { engineer = 4, tactics = 2, trade = 2, spotting = 1 } },
  trp_npc16 = { name = "Klethi",     cost = 200, noble = false, likes = "trp_npc7",  dislikes = { "trp_npc1", "trp_npc15" }, skills = { looting = 3, power_throw = 3, path_finding = 2, spotting = 2 } },
}

-- Quest templates covering Guild Masters, Village Elders, Lords/Kings, Marshals & Ladies
quests.TEMPLATES = {
  gm_move_cattle       = { cat = "guild_master", days = 15, gold = 350, xp = 500,  rel = 3, cooldown_h = 72,  coop_share = true  },
  gm_escort_caravan    = { cat = "guild_master", days = 20, gold = 420, xp = 650,  rel = 4, cooldown_h = 72,  coop_share = true  },
  gm_deliver_wine      = { cat = "guild_master", days = 14, gold = 280, xp = 400,  rel = 3, cooldown_h = 72,  coop_share = false },
  gm_hunt_bandits      = { cat = "guild_master", days = 20, gold = 550, xp = 900,  rel = 5, cooldown_h = 96,  coop_share = true  },
  gm_ransom_girl       = { cat = "guild_master", days = 25, gold = 700, xp = 1000, rel = 6, cooldown_h = 120, coop_share = true  },
  gm_persuade_peace    = { cat = "guild_master", days = 30, gold = 1200,xp = 1500, rel = 8, cooldown_h = 168, coop_share = false },
  gm_looters           = { cat = "guild_master", days = 15, gold = 400, xp = 600,  rel = 4, cooldown_h = 72,  coop_share = true  },
  gm_night_bandits     = { cat = "guild_master", days = 7,  gold = 350, xp = 550,  rel = 4, cooldown_h = 96,  coop_share = true  },
  elder_deliver_grain  = { cat = "village_elder",days = 14, gold = 180, xp = 450,  rel = 5, cooldown_h = 120, coop_share = false },
  elder_deliver_cattle = { cat = "village_elder",days = 18, gold = 250, xp = 600,  rel = 6, cooldown_h = 120, coop_share = true  },
  elder_train_peasants = { cat = "village_elder",days = 14, gold = 300, xp = 1100, rel = 8, cooldown_h = 168, coop_share = true  },
  tavern_save_village  = { cat = "farmer",       days = 7,  gold = 200, xp = 850,  rel = 7, cooldown_h = 168, coop_share = true  },
  lord_deliver_letter  = { cat = "lord",         days = 20, gold = 120, xp = 300,  rel = 3, cooldown_h = 48,  coop_share = false },
  lord_collect_taxes   = { cat = "lord",         days = 21, gold = 600, xp = 550,  rel = 5, cooldown_h = 168, coop_share = false },
  lord_train_troops    = { cat = "lord",         days = 30, gold = 450, xp = 800,  rel = 5, cooldown_h = 120, coop_share = false },
  lord_rescue_prisoner = { cat = "lord",         days = 30, gold = 1500,xp = 1800, rel = 10,cooldown_h = 168, coop_share = true  },
  lord_destroy_lair    = { cat = "lord",         days = 25, gold = 1000,xp = 1400, rel = 7, cooldown_h = 120, coop_share = true  },
  marshal_scout_three  = { cat = "marshal",      days = 7,  gold = 250, xp = 650,  rel = 4, cooldown_h = 48,  coop_share = true  },
  marshal_bring_cattle = { cat = "marshal",      days = 10, gold = 400, xp = 700,  rel = 5, cooldown_h = 72,  coop_share = true  },
  lady_defend_honor    = { cat = "lady",         days = 15, gold = 100, xp = 750,  rel = 8, cooldown_h = 168, coop_share = false },
}

local TAVERN_TOWNS = {
  "p_town_1", "p_town_2", "p_town_3", "p_town_4", "p_town_5", "p_town_6",
  "p_town_7", "p_town_8", "p_town_9", "p_town_10", "p_town_11", "p_town_12",
  "p_town_13", "p_town_14", "p_town_15", "p_town_16", "p_town_17", "p_town_18",
  "p_town_19", "p_town_20", "p_town_21", "p_town_22",
}

function quests.new(opts)
  opts = opts or {}
  local self = setmetatable({}, quests)
  self.next_instance_id = 1
  self.instances = {}          -- id -> quest record
  self.giver_cooldowns = {}    -- "giver_id:template_id" -> unlock_hour
  self.companions = {}         -- comp_id -> state record
  self.specialist_officers_enabled = opts.specialist_officers_enabled ~= false
  self.next_officer_id = 1
  self:init_companions()
  return self
end

function quests:init_companions()
  local idx = 1
  for comp_id, spec in pairs(quests.COMPANION_CATALOG) do
    local skills_copy = {}
    for k, v in pairs(spec.skills) do
      skills_copy[k] = v
    end
    self.companions[comp_id] = {
      id = comp_id,
      name = spec.name,
      cost = spec.cost,
      noble = spec.noble,
      owner_uid = nil,
      tavern_town = TAVERN_TOWNS[((idx - 1) % #TAVERN_TOWNS) + 1],
      mission_type = nil,       -- "rtr" | "intel" | nil
      mission_return_hour = 0,
      promoted_to_lord = false,
      rtr_granted_by = {},      -- uid -> true (each companion grants RtR once per sovereign)
      level = 4,
      xp = 0,
      hp_pct = 100,
      morale = 75,
      skills = skills_copy,
      equipment = {},
    }
    idx = idx + 1
  end
end

-- Hire unique named companion (guarantees strictly 1 owner across the entire world!)
function quests:hire_companion(economy_mgr, uid, comp_id, town_id)
  local p = economy_mgr:get_player(uid)
  if not p then return false, "unknown_player" end
  local c = self.companions[comp_id]
  if not c then return false, "unknown_companion" end
  if c.promoted_to_lord then return false, "companion_is_now_a_lord" end
  if c.owner_uid ~= nil then return false, "companion_already_hired" end
  if c.mission_type ~= nil then return false, "companion_on_mission" end
  if town_id and c.tavern_town ~= town_id then
    return false, "companion_not_in_this_tavern"
  end
  if #p.companions + 1 > economy_mgr:get_party_size_limit(uid) then
    return false, "party_full"
  end
  if p.gold < c.cost then
    return false, "insufficient_gold"
  end

  p.gold = p.gold - c.cost
  c.cost = 0 -- Re-hiring previously met companion is free unless ransomed
  c.owner_uid = uid
  c.tavern_town = nil
  p.companions[#p.companions + 1] = comp_id
  p.snapshot_epoch = p.snapshot_epoch + 1
  return true, c
end

-- Spawn optional procedural Specialist Officer for large multiplayer groups (4-16 players)
function quests:hire_specialist_officer(economy_mgr, uid, specialty)
  if not self.specialist_officers_enabled then
    return false, "specialist_officers_disabled"
  end
  local p = economy_mgr:get_player(uid)
  if not p then return false, "unknown_player" end
  local templates = {
    surgeon       = { name = "Master Surgeon",       cost = 800, skills = { surgery = 4, wound_treatment = 4, first_aid = 4 } },
    engineer      = { name = "Siege Engineer",       cost = 800, skills = { engineer = 5, tactics = 3 } },
    scout         = { name = "Border Pathfinder",    cost = 700, skills = { path_finding = 4, spotting = 4, tracking = 4 } },
    quartermaster = { name = "Guild Quartermaster",  cost = 750, skills = { trade = 4, trainer = 3, looting = 2 } },
  }
  local tpl = templates[specialty]
  if not tpl then return false, "invalid_specialty" end
  if p.gold < tpl.cost then return false, "insufficient_gold" end

  local oid = "trp_coop_officer_" .. tostring(self.next_officer_id)
  self.next_officer_id = self.next_officer_id + 1
  p.gold = p.gold - tpl.cost

  local skills_copy = {}
  for k, v in pairs(tpl.skills) do skills_copy[k] = v end
  self.companions[oid] = {
    id = oid,
    name = tpl.name,
    cost = 0,
    noble = false,
    is_specialist = true,
    owner_uid = uid,
    tavern_town = nil,
    level = 6,
    xp = 0,
    hp_pct = 100,
    morale = 80,
    skills = skills_copy,
    equipment = {},
  }
  p.companions[#p.companions + 1] = oid
  p.snapshot_epoch = p.snapshot_epoch + 1
  return true, self.companions[oid]
end

-- Evaluate companion compatibility morale (likes +10, dislikes -12 each)
function quests:update_companion_morale(economy_mgr, uid)
  local p = economy_mgr:get_player(uid)
  if not p then return end
  local in_party = {}
  for _, cid in ipairs(p.companions) do
    in_party[cid] = true
  end
  for _, cid in ipairs(p.companions) do
    local c = self.companions[cid]
    local cat = quests.COMPANION_CATALOG[cid]
    if c and cat then
      local m = p.morale or 60
      if cat.likes and in_party[cat.likes] then
        m = m + 12
      end
      for _, hated in ipairs(cat.dislikes or {}) do
        if in_party[hated] then
          m = m - 15
        end
      end
      c.morale = math.max(0, math.min(99, m))
    end
  end
end

-- Send companion on Right-to-Rule emissary mission (returns in 7 days with +3 Right to Rule)
function quests:send_companion_rtr_mission(economy_mgr, uid, comp_id, cur_hour)
  local p = economy_mgr:get_player(uid)
  local c = self.companions[comp_id]
  if not p or not c or c.owner_uid ~= uid then
    return false, "companion_not_in_party"
  end
  if c.rtr_granted_by and c.rtr_granted_by[uid] then
    return false, "already_spread_word_for_this_ruler"
  end
  for i, cid in ipairs(p.companions) do
    if cid == comp_id then
      table.remove(p.companions, i)
      break
    end
  end
  c.mission_type = "rtr"
  c.mission_return_hour = cur_hour + (7 * 24)
  return true, c.mission_return_hour
end

function quests:tick_companions_and_taverns(economy_mgr, cur_hour)
  local returned = {}
  for cid, c in pairs(self.companions) do
    if c.mission_type == "rtr" and cur_hour >= (c.mission_return_hour or 0) then
      c.mission_type = nil
      local p = c.owner_uid and economy_mgr:get_player(c.owner_uid) or nil
      if p then
        p.companions[#p.companions + 1] = cid
        c.rtr_granted_by = c.rtr_granted_by or {}
        c.rtr_granted_by[p.uid] = true
        p.right_to_rule = math.min(99, (p.right_to_rule or 0) + 3)
        p.snapshot_epoch = p.snapshot_epoch + 1
        returned[#returned + 1] = { uid = p.uid, comp_id = cid, new_rtr = p.right_to_rule }
      else
        c.owner_uid = nil
        c.tavern_town = TAVERN_TOWNS[(cur_hour % #TAVERN_TOWNS) + 1]
      end
    end
  end
  return returned
end

-- Instanced Quest Lifecycle
function quests:accept_quest(uid, template_id, giver_id, target_id, cur_hour)
  local tpl = quests.TEMPLATES[template_id]
  if not tpl then return nil, "unknown_quest_template" end

  local cd_key = tostring(giver_id) .. ":" .. tostring(template_id)
  local cd_until = self.giver_cooldowns[cd_key] or 0
  if cur_hour < cd_until then
    return nil, "giver_quest_on_cooldown"
  end

  -- Prevent same player taking duplicate active quest from same giver
  for _, q in pairs(self.instances) do
    if q.state == "active" and q.owner_uid == uid and q.template_id == template_id and q.giver_id == giver_id then
      return nil, "already_active_for_player"
    end
  end

  local qid = self.next_instance_id
  self.next_instance_id = self.next_instance_id + 1
  local inst = {
    id = qid,
    template_id = template_id,
    category = tpl.cat,
    owner_uid = uid,
    co_helpers = {},
    giver_id = tostring(giver_id),
    target_id = tostring(target_id or ""),
    accepted_hour = cur_hour,
    deadline_hour = cur_hour + tpl.days * 24,
    reward_gold = tpl.gold,
    reward_xp = tpl.xp,
    reward_rel = tpl.rel,
    coop_share = tpl.coop_share,
    state = "active",
  }
  self.instances[qid] = inst
  self.giver_cooldowns[cd_key] = cur_hour + tpl.cooldown_h
  return inst, nil
end

function quests:add_coop_helper(quest_id, helper_uid)
  local q = self.instances[quest_id]
  if not q or q.state ~= "active" or not q.coop_share then
    return false, "quest_not_shareable"
  end
  if helper_uid == q.owner_uid then
    return true, nil
  end
  for _, h in ipairs(q.co_helpers) do
    if h == helper_uid then return true, nil end
  end
  q.co_helpers[#q.co_helpers + 1] = helper_uid
  return true, nil
end

function quests:complete_quest(economy_mgr, quest_id, actor_uid, allied_helpers)
  local q = self.instances[quest_id]
  if not q or q.state ~= "active" then
    return false, "quest_not_active"
  end
  -- Guard against random unallied player stealing kill credit (fixes the classic hunt-bandits bug!)
  local authorized = (actor_uid == q.owner_uid)
  if not authorized then
    for _, h in ipairs(q.co_helpers) do
      if h == actor_uid then authorized = true; break end
    end
  end
  if not authorized then
    return false, "actor_not_authorized_for_quest"
  end

  q.state = "completed"
  local owner = economy_mgr:get_player(q.owner_uid)
  local payouts = {}
  if owner then
    owner.gold = owner.gold + q.reward_gold
    economy_mgr:grant_hero_xp(q.owner_uid, q.reward_xp)
    owner.snapshot_epoch = owner.snapshot_epoch + 1
    payouts[q.owner_uid] = { gold = q.reward_gold, xp = q.reward_xp, rel_gain = q.reward_rel }
  end

  -- Co-op Brotherhood assist bonus (35% bonus gold & 50% XP minted by guild/lord patron, without penalizing owner!)
  if q.coop_share then
    local helper_set = {}
    for _, h in ipairs(q.co_helpers) do helper_set[h] = true end
    for _, h in ipairs(allied_helpers or {}) do
      if h ~= q.owner_uid then helper_set[h] = true end
    end
    for huid, _ in pairs(helper_set) do
      local hp = economy_mgr:get_player(huid)
      if hp then
        local b_gold = math.floor(q.reward_gold * 0.35)
        local b_xp   = math.floor(q.reward_xp * 0.50)
        hp.gold = hp.gold + b_gold
        economy_mgr:grant_hero_xp(huid, b_xp)
        hp.snapshot_epoch = hp.snapshot_epoch + 1
        payouts[huid] = { gold = b_gold, xp = b_xp, rel_gain = math.max(1, math.floor(q.reward_rel / 2)) }
      end
    end
  end

  return true, payouts
end

function quests:tick_quest_deadlines(economy_mgr, cur_hour)
  local expired = {}
  for qid, q in pairs(self.instances) do
    if q.state == "active" and cur_hour >= q.deadline_hour then
      q.state = "failed_timeout"
      local owner = economy_mgr:get_player(q.owner_uid)
      if owner and q.category == "guild_master" then
        -- Failing a guild delivery incurs guild debt penalty just like Native
        owner.wage_debt = (owner.wage_debt or 0) + math.floor(q.reward_gold * 0.25)
      end
      expired[#expired + 1] = qid
    end
  end
  return expired
end

function quests:get_player_active_quests(uid)
  local list = {}
  for _, q in pairs(self.instances) do
    if q.state == "active" then
      local is_mine = (q.owner_uid == uid)
      if not is_mine then
        for _, h in ipairs(q.co_helpers) do
          if h == uid then is_mine = true; break end
        end
      end
      if is_mine then
        list[#list + 1] = q
      end
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

return quests
