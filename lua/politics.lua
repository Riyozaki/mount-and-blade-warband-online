-- Calradia Online: Consensus Map Time-Scale, Brotherhoods, Sieges, Diplomacy,
-- Courtship/Marriage/Feasts, Claimants & Sovereign Player Kingdoms (with Human Vassals!)

local politics = {}
politics.__index = politics

politics.VALID_SPEEDS = { [0] = true, [1] = true, [3] = true, [5] = true }

politics.FIEF_IMPROVEMENTS = {
  manor          = { cost = 8000,  days = 40, center_type = "village" },
  mill           = { cost = 6000,  days = 35, center_type = "village" },
  watch_tower    = { cost = 5000,  days = 25, center_type = "village" },
  school         = { cost = 9000,  days = 45, center_type = "village" },
  messenger_post = { cost = 4000,  days = 20, center_type = "all"     },
  prison_tower   = { cost = 11000, days = 50, center_type = "walled"  },
}

politics.CLAIMANTS = {
  trp_kingdom_1_pretender = { name = "Lady Isolla of Suno",      target_faction = "fac_kingdom_1" },
  trp_kingdom_2_pretender = { name = "Prince Valdym the Bastard",target_faction = "fac_kingdom_2" },
  trp_kingdom_3_pretender = { name = "Dustum Khan",              target_faction = "fac_kingdom_3" },
  trp_kingdom_4_pretender = { name = "Lethwin Far-Seeker",       target_faction = "fac_kingdom_4" },
  trp_kingdom_5_pretender = { name = "Lord Kastor of Veluca",    target_faction = "fac_kingdom_5" },
  trp_kingdom_6_pretender = { name = "Arwa the Pearled One",     target_faction = "fac_kingdom_6" },
}

function politics.new(opts)
  opts = opts or {}
  local self = setmetatable({}, politics)
  self.speed_policy = opts.speed_policy or "min_online" -- "min_online" | "majority"
  self.speed_votes = {}         -- uid -> 0 | 1 | 3 | 5
  self.effective_speed = 1

  self.brotherhoods = {}        -- bh_id -> { id, name, leader_uid, members = {uid=true} }
  self.player_brotherhood = {}  -- uid -> bh_id
  self.next_bh_id = 1

  self.kingdoms = {}            -- fac_id -> kingdom record (6 Native + up to 16 Player Kingdoms)
  self.fiefs = {}               -- center_id -> { id, type, faction_id, owner_uid_or_lord, prosperity, improvements, build_job }
  self.sieges = {}              -- center_id -> active siege record
  self.courtships = {}          -- "uid:target_id" -> relation, poems_recited, married
  self.marriages = {}           -- uid -> spouse_id
  self.feasts = {}              -- fac_id -> { center_id, host_uid, ends_hour }
  self.diplomacy = {}           -- "facA|facB" -> "peace" | "war" | "truce"

  self:init_native_kingdoms()
  return self
end

function politics:init_native_kingdoms()
  local native = {
    { id = "fac_kingdom_1", name = "Kingdom of Swadia",   ruler = "trp_kingdom_1_lord", culture = "swadia"   },
    { id = "fac_kingdom_2", name = "Kingdom of Vaegirs",  ruler = "trp_kingdom_2_lord", culture = "vaegirs"  },
    { id = "fac_kingdom_3", name = "Khergit Khanate",     ruler = "trp_kingdom_3_lord", culture = "khergit"  },
    { id = "fac_kingdom_4", name = "Kingdom of Nords",    ruler = "trp_kingdom_4_lord", culture = "nords"    },
    { id = "fac_kingdom_5", name = "Kingdom of Rhodoks",  ruler = "trp_kingdom_5_lord", culture = "rhodoks"  },
    { id = "fac_kingdom_6", name = "Sarranid Sultanate",  ruler = "trp_kingdom_6_lord", culture = "sarranid" },
  }
  for _, k in ipairs(native) do
    self.kingdoms[k.id] = {
      id = k.id,
      name = k.name,
      is_player_kingdom = false,
      ruler_id = k.ruler,
      marshal_id = nil,
      culture = k.culture,
      minister_id = nil,
      vassals = {},        -- uid_or_troop -> true
      mercenaries = {},    -- uid -> stipend_bonus
      claimant_id = nil,
    }
  end
  for slot = 0, 15 do
    local fid = "fac_coop_kingdom_" .. tostring(slot)
    self.kingdoms[fid] = {
      id = fid,
      slot = slot,
      active = false,
      is_player_kingdom = true,
      name = "Free Sovereign Realm " .. tostring(slot + 1),
      ruler_id = nil,
      marshal_id = nil,
      culture = "swadia",
      minister_id = "trp_temporary_minister",
      vassals = {},
      mercenaries = {},
      claimant_id = nil,
    }
  end
end

function politics:register_fief(center_id, center_type, faction_id, owner_id, prosperity)
  self.fiefs[center_id] = {
    id = center_id,
    center_type = center_type or "village", -- "town" | "castle" | "village"
    faction_id = faction_id or "fac_kingdom_1",
    owner_id = owner_id,
    prosperity = prosperity or 50,
    food_days = (center_type == "town" and 30 or 20),
    improvements = {},
    build_job = nil,
  }
  return self.fiefs[center_id]
end

-- ============================================================================
-- 1. Consensus World Map Time-Scale (Pause / 1x / 3x / 5x)
-- ============================================================================
function politics:set_speed_vote(uid, speed, online_uids)
  speed = tonumber(speed)
  if not politics.VALID_SPEEDS[speed] then
    return false, "invalid_speed_multiplier"
  end
  self.speed_votes[uid] = speed
  return true, self:recompute_effective_speed(online_uids)
end

function politics:recompute_effective_speed(online_uids)
  local votes = {}
  if online_uids and #online_uids > 0 then
    for _, uid in ipairs(online_uids) do
      votes[#votes + 1] = (self.speed_votes[uid] ~= nil) and self.speed_votes[uid] or 1
    end
  else
    for _, v in pairs(self.speed_votes) do
      votes[#votes + 1] = v
    end
  end

  if #votes == 0 then
    self.effective_speed = 0 -- Pause campaign clock when 0 players are online!
    return self.effective_speed
  end

  -- Any player requesting Pause (0) or engaged in crisis immediately drops speed unless majority mode overrides >1x
  local min_v = 5
  for _, v in ipairs(votes) do
    if v < min_v then min_v = v end
  end

  if self.speed_policy == "majority" and min_v > 0 then
    table.sort(votes)
    self.effective_speed = votes[math.ceil(#votes / 2)]
  else
    self.effective_speed = min_v
  end
  return self.effective_speed
end

-- Automatic emergency brake when a bandit/lord intercepts any player during 3x/5x fast-forward!
function politics:interrupt_fast_forward(uid, online_uids)
  if (self.speed_votes[uid] or 1) > 1 then
    self.speed_votes[uid] = 1
  end
  for k, v in pairs(self.speed_votes) do
    if v > 1 then self.speed_votes[k] = 1 end
  end
  self.effective_speed = self:recompute_effective_speed(online_uids)
  return self.effective_speed
end

-- ============================================================================
-- 2. Brotherhoods (Player Co-op Alliances)
-- ============================================================================
function politics:create_brotherhood(leader_uid, name)
  if self.player_brotherhood[leader_uid] then
    return nil, "already_in_brotherhood"
  end
  local bid = self.next_bh_id
  self.next_bh_id = self.next_bh_id + 1
  local bh = {
    id = bid,
    name = tostring(name or ("Brotherhood #" .. bid)),
    leader_uid = leader_uid,
    members = { [leader_uid] = true },
  }
  self.brotherhoods[bid] = bh
  self.player_brotherhood[leader_uid] = bid
  return bh, nil
end

function politics:join_brotherhood(bid, uid)
  local bh = self.brotherhoods[bid]
  if not bh then return false, "unknown_brotherhood" end
  if self.player_brotherhood[uid] then return false, "already_in_brotherhood" end
  bh.members[uid] = true
  self.player_brotherhood[uid] = bid
  return true, bh
end

function politics:are_allied(uid_a, uid_b)
  if uid_a == uid_b then return true end
  local ba = self.player_brotherhood[uid_a]
  return (ba ~= nil) and (ba == self.player_brotherhood[uid_b])
end

-- ============================================================================
-- 3. Sieges (Engineer Build Time, Starvation, Sally-Out & Capture)
-- ============================================================================
function politics:begin_siege(center_id, leader_uid, effective_engineer, equipment_type, cur_hour)
  local fief = self.fiefs[center_id]
  if not fief or fief.center_type == "village" then
    return nil, "target_not_walled_center"
  end
  if self.sieges[center_id] then
    return nil, "center_already_besieged"
  end

  -- Native Warband: Ladders take base 12h, Siege Towers take base 60h, reduced by Engineer skill!
  local is_tower = (equipment_type == "siege_tower")
  local base_hours = is_tower and 60 or 12
  local speed_factor = math.max(0.30, 1.0 - 0.06 * math.min(14, effective_engineer or 0))
  local build_hours = math.max(2, math.ceil(base_hours * speed_factor))

  local sg = {
    center_id = center_id,
    leader_uid = leader_uid,
    co_attackers = { [leader_uid] = true },
    equipment_type = is_tower and "siege_tower" or "ladders",
    started_hour = cur_hour,
    ready_at_hour = cur_hour + build_hours,
    food_hours_left = (fief.food_days or 20) * 24,
    starving = false,
  }
  self.sieges[center_id] = sg
  return sg, nil
end

function politics:tick_sieges(cur_hour, elapsed_hours)
  elapsed_hours = elapsed_hours or 1
  local events = {}
  for cid, sg in pairs(self.sieges) do
    sg.food_hours_left = math.max(0, sg.food_hours_left - elapsed_hours)
    if sg.food_hours_left == 0 and not sg.starving then
      sg.starving = true
      events[#events + 1] = { type = "garrison_starving", center_id = cid }
    end
    if not sg.assault_ready and cur_hour >= sg.ready_at_hour then
      sg.assault_ready = true
      events[#events + 1] = { type = "siege_equipment_ready", center_id = cid, equipment = sg.equipment_type }
    end
  end
  return events
end

-- ============================================================================
-- 4. Mercenary Contracts, Vassalage, Player Kingdoms, Marshals & Fiefs
-- ============================================================================
function politics:sign_mercenary_contract(economy_mgr, uid, faction_id)
  local pl = economy_mgr:get_player(uid)
  local k = self.kingdoms[faction_id]
  if not pl or not k or (k.is_player_kingdom and not k.active) then
    return false, "invalid_kingdom"
  end
  pl.faction_id = faction_id
  k.mercenaries[uid] = true
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return true, nil
end

-- Swear fealty to EITHER an AI King OR a Human Player King!
function politics:swear_vassal_oath(economy_mgr, uid, faction_id)
  local pl = economy_mgr:get_player(uid)
  local k = self.kingdoms[faction_id]
  if not pl or not k or (k.is_player_kingdom and not k.active) then
    return false, "invalid_kingdom"
  end
  if (pl.renown or 0) < 150 and not k.is_player_kingdom then
    return false, "insufficient_renown_for_vassalage"
  end
  k.mercenaries[uid] = nil
  k.vassals[uid] = true
  pl.faction_id = faction_id
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return true, k
end

-- Found a Sovereign Player Kingdom (`fac_coop_kingdom_0..15`)
function politics:found_player_kingdom(economy_mgr, uid, kingdom_name, capital_center_id, culture)
  local pl = economy_mgr:get_player(uid)
  if not pl then return nil, "unknown_player" end

  local chosen = nil
  for slot = 0, 15 do
    local k = self.kingdoms["fac_coop_kingdom_" .. tostring(slot)]
    if k and not k.active then
      chosen = k
      break
    end
  end
  if not chosen then return nil, "no_free_player_kingdom_slots" end

  chosen.active = true
  chosen.name = tostring(kingdom_name or (pl.name .. "'s Kingdom"))
  chosen.ruler_id = uid
  chosen.marshal_id = uid
  chosen.culture = culture or "swadia"
  chosen.vassals = { [uid] = true }

  pl.faction_id = chosen.id
  pl.right_to_rule = math.min(99, (pl.right_to_rule or 0) + 5)

  if capital_center_id and self.fiefs[capital_center_id] then
    self.fiefs[capital_center_id].faction_id = chosen.id
    self.fiefs[capital_center_id].owner_id = uid
    pl.fiefs[capital_center_id] = { rent = 1400 }
  end
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return chosen, nil
end

function politics:appoint_marshal(actor_uid, faction_id, marshal_uid_or_lord)
  local k = self.kingdoms[faction_id]
  if not k then return false, "unknown_kingdom" end
  if k.ruler_id ~= actor_uid then return false, "not_kingdom_ruler" end
  k.marshal_id = marshal_uid_or_lord
  return true, k.marshal_id
end

function politics:grant_fief(economy_mgr, actor_uid, faction_id, center_id, recipient_uid)
  local k = self.kingdoms[faction_id]
  local fief = self.fiefs[center_id]
  if not k or not fief or fief.faction_id ~= faction_id then
    return false, "fief_not_owned_by_kingdom"
  end
  if k.is_player_kingdom and k.ruler_id ~= actor_uid then
    return false, "only_ruler_can_grant_fief"
  end

  -- Remove from old player owner if applicable
  if fief.owner_id and economy_mgr:get_player(fief.owner_id) then
    economy_mgr:get_player(fief.owner_id).fiefs[center_id] = nil
  end

  fief.owner_id = recipient_uid
  local rec = economy_mgr:get_player(recipient_uid)
  if rec then
    local base_rent = (fief.center_type == "town" and 1600) or (fief.center_type == "castle" and 650) or 450
    rec.fiefs[center_id] = { rent = math.floor(base_rent * (fief.prosperity / 50.0)) }
    rec.snapshot_epoch = rec.snapshot_epoch + 1
  end
  return true, fief
end

-- Promote a Party Companion into a Feudal Vassal Lord of the Player's Kingdom!
function politics:promote_companion_to_vassal(economy_mgr, quests_mgr, ruler_uid, comp_id, center_id)
  local pl = economy_mgr:get_player(ruler_uid)
  local k = pl and self.kingdoms[pl.faction_id] or nil
  local comp = quests_mgr.companions[comp_id]
  local fief = self.fiefs[center_id]

  if not k or not k.is_player_kingdom or k.ruler_id ~= ruler_uid then
    return false, "must_be_sovereign_ruler"
  end
  if not comp or comp.owner_uid ~= ruler_uid then
    return false, "companion_not_in_ruler_party"
  end
  if not fief or fief.faction_id ~= k.id then
    return false, "fief_not_in_kingdom"
  end

  for i, cid in ipairs(pl.companions) do
    if cid == comp_id then table.remove(pl.companions, i); break end
  end
  comp.owner_uid = nil
  comp.promoted_to_lord = true
  k.vassals[comp_id] = true
  fief.owner_id = comp_id
  pl.fiefs[center_id] = nil

  -- Native rule: Promoting a commoner (non-noble) companion upsets traditional nobles, whereas noble companions please them
  local noble_reaction = comp.noble and "approved" or "commoner_scandal"
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return true, { lord_id = comp_id, fief = center_id, noble_reaction = noble_reaction }
end

-- Build Fief Improvements scaled by effective Engineer skill
function politics:start_fief_improvement(economy_mgr, uid, center_id, imp_type, effective_engineer, cur_hour)
  local pl = economy_mgr:get_player(uid)
  local fief = self.fiefs[center_id]
  local spec = politics.FIEF_IMPROVEMENTS[imp_type]
  if not pl or not fief or fief.owner_id ~= uid or not spec then
    return false, "cannot_improve_fief"
  end
  if fief.improvements[imp_type] or fief.build_job then
    return false, "already_built_or_busy"
  end
  local discount = math.max(0.50, 1.0 - 0.05 * math.min(10, effective_engineer or 0))
  local cost = math.floor(spec.cost * discount)
  local hours = math.max(24, math.floor(spec.days * 24 * discount))
  if pl.gold < cost then
    return false, "insufficient_gold"
  end
  pl.gold = pl.gold - cost
  fief.build_job = { imp_type = imp_type, ready_hour = cur_hour + hours }
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return true, fief.build_job
end

function politics:tick_fief_improvements(cur_hour)
  local finished = {}
  for cid, fief in pairs(self.fiefs) do
    if fief.build_job and cur_hour >= fief.build_job.ready_hour then
      local itype = fief.build_job.imp_type
      fief.improvements[itype] = true
      fief.prosperity = math.min(100, fief.prosperity + 6)
      fief.build_job = nil
      finished[#finished + 1] = { center_id = cid, improvement = itype }
    end
  end
  return finished
end

-- ============================================================================
-- 5. Diplomacy, Claimants, Courtship, Marriage & Feasts
-- ============================================================================
local function diplo_key(a, b)
  return (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
end

function politics:set_diplomacy(fac_a, fac_b, state)
  if fac_a == fac_b then return false, "same_faction" end
  self.diplomacy[diplo_key(fac_a, fac_b)] = state
  return true, state
end

function politics:are_at_war(fac_a, fac_b)
  if not fac_a or not fac_b or fac_a == fac_b then return false end
  return self.diplomacy[diplo_key(fac_a, fac_b)] == "war"
end

function politics:support_claimant(economy_mgr, uid, claimant_id)
  local pl = economy_mgr:get_player(uid)
  local cl = politics.CLAIMANTS[claimant_id]
  if not pl or not cl then return nil, "unknown_claimant" end
  if (pl.renown or 0) < 200 then return nil, "insufficient_renown_for_claimant" end

  local k, err = self:found_player_kingdom(economy_mgr, uid, cl.name .. " Rebels", nil, "swadia")
  if not k then return nil, err end
  k.claimant_id = claimant_id
  self:set_diplomacy(k.id, cl.target_faction, "war")
  return k, nil
end

function politics:court_spouse(uid, target_id, poem_bonus)
  local key = tostring(uid) .. ":" .. tostring(target_id)
  local c = self.courtships[key] or { relation = 5, poems = 0 }
  c.relation = math.min(100, c.relation + 4 + (poem_bonus or 0))
  c.poems = c.poems + ((poem_bonus and poem_bonus > 0) and 1 or 0)
  self.courtships[key] = c
  return c
end

-- Supports marrying Noble Ladies, Lords (for female heroes), OR Royal Player-to-Player Marriages!
function politics:marry(economy_mgr, uid, spouse_id)
  local pl = economy_mgr:get_player(uid)
  if not pl then return false, "unknown_player" end
  if self.marriages[uid] then return false, "already_married" end

  -- Ensure target isn't already married to another player!
  for other_uid, sp in pairs(self.marriages) do
    if sp == spouse_id and other_uid ~= uid then
      return false, "spouse_already_wed"
    end
  end

  local key = tostring(uid) .. ":" .. tostring(spouse_id)
  local c = self.courtships[key]
  local is_player_spouse = (economy_mgr:get_player(spouse_id) ~= nil)
  if not is_player_spouse and ((not c) or c.relation < 20) then
    return false, "insufficient_courtship_relation"
  end

  self.marriages[uid] = spouse_id
  if is_player_spouse then
    self.marriages[spouse_id] = uid
    local sp_pl = economy_mgr:get_player(spouse_id)
    sp_pl.right_to_rule = math.min(99, (sp_pl.right_to_rule or 0) + 3)
  end
  pl.right_to_rule = math.min(99, (pl.right_to_rule or 0) + 3)
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return true, { uid = uid, spouse = spouse_id, new_rtr = pl.right_to_rule }
end

function politics:host_feast(economy_mgr, uid, center_id, cur_hour)
  local pl = economy_mgr:get_player(uid)
  local fief = self.fiefs[center_id]
  if not pl or not fief or fief.owner_id ~= uid then
    return false, "must_own_hall_to_host_feast"
  end
  self.feasts[pl.faction_id] = {
    faction_id = pl.faction_id,
    center_id = center_id,
    host_uid = uid,
    ends_hour = cur_hour + 72,
  }
  pl.renown = (pl.renown or 0) + 25
  pl.snapshot_epoch = pl.snapshot_epoch + 1
  return true, self.feasts[pl.faction_id]
end

return politics
