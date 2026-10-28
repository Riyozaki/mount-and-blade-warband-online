-- Calradia Online: Tactical Battle Coordinator, Live Drop-In Reinforcements, Surgery/Loot/Prisoner Resolver,
-- Co-op Captivity / Prison Break & Shared Multiplayer Tournament Engine

local battles = {}
battles.__index = battles

function battles.new(opts)
  opts = opts or {}
  local self = setmetatable({}, battles)
  self.next_battle_id = 1
  self.active_battles = {}     -- battle_id -> battle state on global map
  self.captives = {}           -- player_uid -> captivity record
  self.tournaments = {}        -- town_id -> active multiplayer tournament bracket
  self.rng_state = opts.seed or 13379001
  return self
end

-- Deterministic LCG/xorshift mix for reproducible battle rolls & fuzzing
function battles:rand_float()
  self.rng_state = (self.rng_state * 1103515245 + 12345) % 2147483648
  return self.rng_state / 2147483648.0
end

function battles:rand_int(lo, hi)
  if hi <= lo then return lo end
  return lo + math.floor(self:rand_float() * (hi - lo + 1))
end

-- Create an active battle node on the global map (other players can see & drop in dynamically!)
function battles:start_battle(spec)
  local bid = self.next_battle_id
  self.next_battle_id = self.next_battle_id + 1

  local node = {
    battle_id = bid,
    mission_kind = spec.mission_kind or 1, -- 1=Field, 2=SiegeAssault, 3=SiegeDefense, 4=Village, 5=Lair, 7=PrisonBreak
    scene_id = spec.scene_id or "scn_random_scene_plain",
    center_id = spec.center_id or nil,
    map_pos = spec.map_pos or { x = 0, y = 0 },
    started_hour = spec.started_hour or 0,
    assigned_slot = spec.assigned_slot or 0,
    status = "running",
    sides = {
      [0] = spec.side_a or { faction_id = "fac_neutral", parties = {} },
      [1] = spec.side_b or { faction_id = "fac_outlaws", parties = {} },
    },
  }

  -- Compute Battle Advantage from best Tactics skill on each side & numerical ratio
  local function side_strength_and_tactics(side)
    local men = 0
    local best_tac = 0
    for _, pt in ipairs(side.parties) do
      if (pt.tactics_skill or 0) > best_tac then
        best_tac = pt.tactics_skill
      end
      for _, st in ipairs(pt.stacks or {}) do
        men = men + math.max(0, (st.count or 0) - (st.wounded or 0))
      end
    end
    return math.max(1, men), best_tac
  end

  local men_a, tac_a = side_strength_and_tactics(node.sides[0])
  local men_b, tac_b = side_strength_and_tactics(node.sides[1])
  node.battle_advantage = ((men_a / men_b) - 1.0) * 4.0 + (tac_a - tac_b) * 0.5

  self.active_battles[bid] = node
  return node
end

-- Dynamic Drop-in Reinforcement while 3D battle is ALREADY running!
function battles:join_ongoing_battle(battle_id, side_index, party_descriptor)
  local b = self.active_battles[battle_id]
  if not b or b.status ~= "running" then
    return false, "battle_not_running"
  end
  if side_index ~= 0 and side_index ~= 1 then
    return false, "invalid_side"
  end
  for s = 0, 1 do
    for _, pt in ipairs(b.sides[s].parties) do
      if pt.party_id == party_descriptor.party_id then
        return false, "party_already_in_battle"
      end
    end
  end

  local side = b.sides[side_index]
  side.parties[#side.parties + 1] = party_descriptor

  local ipc_reinforcement = {
    msg_type = "LIVE_REINFORCEMENT",
    battle_id = battle_id,
    battle_slot = b.assigned_slot,
    side_index = side_index,
    party = party_descriptor,
  }
  return true, ipc_reinforcement
end

-- Apply exact Native Surgery (25% base + 4% * effective_surgery) & resolve XP, Loot, Prisoners, Lords & Captivity
function battles:resolve_battle_result(economy_mgr, companions_tbl, report)
  local b = self.active_battles[report.battle_id]
  if not b then
    return false, "unknown_battle"
  end
  b.status = "finished"

  local winning_side = tonumber(report.winning_side or 0)
  local losing_side  = (winning_side == 0) and 1 or 0
  local casualties_by_party = report.party_casualties or {}

  local summary = {
    battle_id = b.battle_id,
    winning_side = winning_side,
    party_outcomes = {},
    prisoner_pool = {},
    lord_fates = {},
    total_enemy_tier_value = 0,
  }

  -- Step 1: Process casualties & Surgery per party on BOTH sides
  for s = 0, 1 do
    for _, pt in ipairs(b.sides[s].parties) do
      local pid_str = tostring(pt.party_id)
      local cas = casualties_by_party[pid_str] or { stacks = {} }
      local owner_uid = pt.owner_player_uid
      local eff_surgery = pt.surgery_skill or 0
      local eff_first_aid = pt.first_aid_skill or 0
      if owner_uid and economy_mgr:get_player(owner_uid) then
        eff_surgery = economy_mgr:get_effective_party_skill(owner_uid, "surgery", companions_tbl)
        eff_first_aid = economy_mgr:get_effective_party_skill(owner_uid, "first_aid", companions_tbl)
      end

      -- Exact Warband Surgery save chance: 25% base + 4% per effective Surgery point (max 81%)
      local surgery_save_prob = math.min(0.81, 0.25 + 0.04 * eff_surgery)

      local party_dead = 0
      local party_saved_wounded = 0
      local personal_kills = 0

      for _, st_cas in ipairs(cas.stacks or {}) do
        personal_kills = personal_kills + (st_cas.personal_kills or 0)
        if st_cas.is_hero then
          if owner_uid and st_cas.troop_id == "hero" then
            local pl = economy_mgr:get_player(owner_uid)
            if pl then
              local raw_hp = tonumber(st_cas.final_hp_pct or 100)
              local lost = math.max(0, (pl.hp_pct or 100) - raw_hp)
              local recovered = math.floor(lost * (0.10 + 0.05 * eff_first_aid))
              pl.hp_pct = math.min(100, math.max(15, raw_hp + recovered))
            end
          elseif s == losing_side and st_cas.is_ai_lord then
            -- Native lord escape vs capture (~70% escape in Native, 30% capture)
            local escaped = (self:rand_float() < 0.65)
            summary.lord_fates[#summary.lord_fates + 1] = {
              lord_troop_id = st_cas.troop_id,
              captured = not escaped,
            }
          end
        else
          local lethal = tonumber(st_cas.dead_lethal or 0)
          local blunt  = tonumber(st_cas.knocked_blunt or 0)
          local saved = 0
          for _ = 1, lethal do
            if self:rand_float() < surgery_save_prob then
              saved = saved + 1
            end
          end
          local perm_dead = lethal - saved
          party_dead = party_dead + perm_dead
          party_saved_wounded = party_saved_wounded + saved + blunt

          if s == losing_side then
            summary.total_enemy_tier_value = summary.total_enemy_tier_value + (perm_dead + saved + blunt) * (st_cas.tier or 2)
            local capturable = blunt + saved
            if capturable > 0 then
              summary.prisoner_pool[#summary.prisoner_pool + 1] = {
                troop_id = st_cas.troop_id,
                count = capturable,
              }
            end
          end

          -- Apply casualties directly to persistent player party stacks
          if owner_uid then
            local pl = economy_mgr:get_player(owner_uid)
            if pl then
              for idx = #pl.party_stacks, 1, -1 do
                local pst = pl.party_stacks[idx]
                if pst.troop_id == st_cas.troop_id then
                  pst.count = math.max(0, pst.count - perm_dead)
                  pst.wounded = math.min(pst.count, (pst.wounded or 0) + saved + blunt)
                  if pst.count <= 0 then
                    table.remove(pl.party_stacks, idx)
                  end
                  break
                end
              end
            end
          end
        end
      end

      summary.party_outcomes[pid_str] = {
        owner_uid = owner_uid,
        side = s,
        dead = party_dead,
        wounded_saved = party_saved_wounded,
        personal_kills = personal_kills,
      }
    end
  end

  -- Step 2: Distribute Victory XP, Gold, Renown, Prisoners & Individual Looting-Scaled Item Loot
  local winners = {}
  for _, pt in ipairs(b.sides[winning_side].parties) do
    if pt.owner_player_uid and economy_mgr:get_player(pt.owner_player_uid) then
      winners[#winners + 1] = pt
    end
  end

  local loot_catalog = {
    "itm_nordic_sword", "itm_mail_with_surcoat", "itm_kettle_hat",
    "itm_heater_shield", "itm_war_bow", "itm_leather_boots", "itm_smoked_fish",
  }

  if #winners > 0 then
    local base_xp_pool   = math.max(120, summary.total_enemy_tier_value * 38)
    local base_gold_pool = math.max(60,  summary.total_enemy_tier_value * 16)
    local renown_share   = math.max(2,   math.floor(summary.total_enemy_tier_value / (4 * #winners)))

    for _, pt in ipairs(winners) do
      local uid = pt.owner_player_uid
      local pl = economy_mgr:get_player(uid)
      local out = summary.party_outcomes[tostring(pt.party_id)]
      local xp_share = math.floor(base_xp_pool / #winners) + (out.personal_kills or 0) * 45
      local gold_share = math.floor(base_gold_pool / #winners)

      pl.gold = pl.gold + gold_share
      pl.renown = (pl.renown or 0) + renown_share
      pl.morale = math.min(99, (pl.morale or 60) + 6)
      economy_mgr:grant_hero_xp(uid, xp_share)

      -- Individual server-rolled item loot scaled by effective Looting skill
      local eff_looting = economy_mgr:get_effective_party_skill(uid, "looting", companions_tbl)
      local loot_rolls = math.min(6, 1 + math.floor(eff_looting / 2) + math.floor(summary.total_enemy_tier_value / 25))
      local items_won = {}
      for _ = 1, loot_rolls do
        local free_slot = economy_mgr:find_first_free_bag_slot(uid)
        if not free_slot then break end
        local pick = loot_catalog[self:rand_int(1, #loot_catalog)]
        local itm = { item_id = pick, base_price = 180 + eff_looting * 25, modifier = 0, ammo = (pick == "itm_smoked_fish" and 30 or 0) }
        pl.inventory[tostring(free_slot)] = itm
        items_won[#items_won + 1] = pick
      end

      out.xp_gain = xp_share
      out.gold_gain = gold_share
      out.renown_gain = renown_share
      out.loot_items = items_won
      pl.snapshot_epoch = pl.snapshot_epoch + 1
    end

    -- Overflow-aware Prisoner distribution across winning players with free Prisoner Management slots
    for _, pstack in ipairs(summary.prisoner_pool) do
      local rem = pstack.count
      for _, pt in ipairs(winners) do
        if rem <= 0 then break end
        local uid = pt.owner_player_uid
        local pl = economy_mgr:get_player(uid)
        local cap = economy_mgr:get_prisoner_limit(uid)
        local cur_pris = 0
        for _, pr in ipairs(pl.prisoners) do cur_pris = cur_pris + pr.count end
        local space = math.max(0, cap - cur_pris)
        local take = math.min(rem, space)
        if take > 0 then
          pl.prisoners[#pl.prisoners + 1] = { troop_id = pstack.troop_id, count = take }
          rem = rem - take
        end
      end
    end
  end

  -- Step 3: Defeated players enter Co-op Captivity (can be rescued on map, ransomed, prison-broken, or auto-escape!)
  for _, pt in ipairs(b.sides[losing_side].parties) do
    local uid = pt.owner_player_uid
    if uid and economy_mgr:get_player(uid) and not report.retreated then
      local pl = economy_mgr:get_player(uid)
      local gold_lost = math.floor(pl.gold * 0.15)
      pl.gold = pl.gold - gold_lost
      pl.snapshot_epoch = pl.snapshot_epoch + 1
      local captor_party = b.sides[winning_side].parties[1] and b.sides[winning_side].parties[1].party_id or -1
      self.captives[uid] = {
        uid = uid,
        captor_party_id = captor_party,
        dungeon_center_id = b.center_id,
        ransom_price = math.max(250, pl.level * 120),
        escape_at_hour = (report.cur_hour or b.started_hour) + 24, -- short fun co-op window (~24 game hours)
        gold_lost = gold_lost,
      }
    end
  end

  self.active_battles[b.battle_id] = nil
  return true, summary
end

-- Honor vs Capture choice for beaten AI Lord
function battles:decide_beaten_lord_fate(economy_mgr, uid, lord_troop_id, release_with_honor)
  local pl = economy_mgr:get_player(uid)
  if not pl then return false, "unknown_player" end
  if release_with_honor then
    pl.honor = (pl.honor or 0) + 3
    pl.snapshot_epoch = pl.snapshot_epoch + 1
    return true, { action = "released", honor_gain = 3, relation_gain = 5 }
  else
    pl.prisoners[#pl.prisoners + 1] = { troop_id = lord_troop_id, count = 1, is_lord = true }
    pl.snapshot_epoch = pl.snapshot_epoch + 1
    return true, { action = "captured", ransom_value = 2200 }
  end
end

-- Co-op Rescue / Ransom / Prison Break / Timed Escape for captive player
function battles:rescue_or_ransom_captive(economy_mgr, captive_uid, rescuer_uid, method, cur_hour)
  local cap = self.captives[captive_uid]
  if not cap then return false, "player_not_captive" end

  if method == "ransom" then
    local payer = economy_mgr:get_player(rescuer_uid or captive_uid)
    if not payer or payer.gold < cap.ransom_price then
      return false, "insufficient_ransom_gold"
    end
    payer.gold = payer.gold - cap.ransom_price
    payer.snapshot_epoch = payer.snapshot_epoch + 1
    self.captives[captive_uid] = nil
    return true, { freed = captive_uid, method = "ransom", paid = cap.ransom_price }
  elseif method == "map_rescue" or method == "prison_break" then
    self.captives[captive_uid] = nil
    if rescuer_uid and economy_mgr:get_player(rescuer_uid) then
      economy_mgr:grant_hero_xp(rescuer_uid, 600)
    end
    return true, { freed = captive_uid, method = method }
  elseif method == "tick_escape" then
    if (cur_hour or 0) >= cap.escape_at_hour then
      self.captives[captive_uid] = nil
      return true, { freed = captive_uid, method = "escaped" }
    end
    return false, "still_captive"
  end
  return false, "unknown_rescue_method"
end

-- Shared Multiplayer 6-Round Tournament Engine (friends + AI champions in same bracket with self-betting!)
function battles:start_town_tournament(town_id, participant_uids, ai_count)
  ai_count = ai_count or math.max(8, 16 - #participant_uids)
  local roster = {}
  for _, uid in ipairs(participant_uids) do
    roster[#roster + 1] = { id = uid, is_player = true, eliminated = false, total_bet = 0, potential_payout = 0 }
  end
  for i = 1, ai_count do
    roster[#roster + 1] = { id = "ai_gladiator_" .. tostring(i), is_player = false, eliminated = false }
  end
  local tourney = {
    town_id = town_id,
    round = 1,
    max_rounds = 6,
    roster = roster,
    finished = false,
    winner_id = nil,
  }
  self.tournaments[town_id] = tourney
  return tourney
end

function battles:place_tournament_bet(economy_mgr, town_id, uid, amount)
  local t = self.tournaments[town_id]
  if not t or t.finished then return false, "no_active_tournament" end
  amount = math.floor(tonumber(amount or 0))
  if amount < 5 or amount > 100 then return false, "bet_out_of_limits" end
  local pl = economy_mgr:get_player(uid)
  if not pl or pl.gold < amount then return false, "insufficient_gold" end

  for _, entry in ipairs(t.roster) do
    if entry.id == uid and not entry.eliminated then
      pl.gold = pl.gold - amount
      pl.snapshot_epoch = pl.snapshot_epoch + 1
      local odds_mult = math.max(1.8, 4.2 - (t.round - 1) * 0.45)
      entry.total_bet = (entry.total_bet or 0) + amount
      entry.potential_payout = (entry.potential_payout or 0) + math.floor(amount * odds_mult)
      return true, entry.potential_payout
    end
  end
  return false, "not_active_fighter_in_tournament"
end

function battles:complete_tournament(economy_mgr, town_id, winner_uid)
  local t = self.tournaments[town_id]
  if not t or t.finished then return false, "no_active_tournament" end
  t.finished = true
  t.winner_id = winner_uid
  self.tournaments[town_id] = nil

  local pl = economy_mgr:get_player(winner_uid)
  if not pl then
    return true, { winner = winner_uid, is_player = false }
  end

  local bet_payout = 0
  for _, entry in ipairs(t.roster) do
    if entry.id == winner_uid then
      bet_payout = entry.potential_payout or 0
      break
    end
  end

  local grand_prize = 200
  pl.gold = pl.gold + grand_prize + bet_payout
  pl.renown = (pl.renown or 0) + 20
  economy_mgr:grant_hero_xp(winner_uid, 250)
  pl.snapshot_epoch = pl.snapshot_epoch + 1

  return true, {
    winner = winner_uid,
    is_player = true,
    prize_gold = grand_prize,
    bet_payout = bet_payout,
    renown_gain = 20,
  }
end

return battles
