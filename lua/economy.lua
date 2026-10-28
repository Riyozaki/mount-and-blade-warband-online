-- Calradia Online: Server-Authoritative Character, Inventory, Party, Economy, Enterprises & P2P Trade Engine
-- Eliminates client-side item/gold duplication, enforces snapshot epochs, and runs living Calradian trade.

local economy = {}
economy.__index = economy

-- Starting capitals (Praven, Reyvadin, Tihr, Sargoth, Jelkala, Shariz)
economy.STARTING_TOWNS = {
  [1] = { id = "p_town_6",  name = "Praven",   x = -96.0, y = 26.4  },
  [2] = { id = "p_town_8",  name = "Reyvadin", x = 62.5,  y = 65.8  },
  [3] = { id = "p_town_2",  name = "Tihr",     x = -20.2, y = 78.6  },
  [4] = { id = "p_town_1",  name = "Sargoth",  x = -17.5, y = 79.5  },
  [5] = { id = "p_town_5",  name = "Jelkala",  x = -74.6, y = -79.5 },
  [6] = { id = "p_town_19", name = "Shariz",   x = 15.0,  y = -107.0 },
}

-- All 9 classic Warband productive enterprise types
economy.ENTERPRISE_TYPES = {
  bakery         = { name = "Mill & Bakery",      cost = 1500, base_weekly_profit = 140 },
  brewery        = { name = "Brewery",            cost = 2500, base_weekly_profit = 210 },
  tannery        = { name = "Tannery",            cost = 8000, base_weekly_profit = 430 },
  wine_press     = { name = "Wine Press",         cost = 5000, base_weekly_profit = 310 },
  oil_press      = { name = "Oil Press",          cost = 4500, base_weekly_profit = 320 },
  ironworks      = { name = "Ironworks",          cost = 3500, base_weekly_profit = 300 },
  velvet_weavery = { name = "Dyeworks & Velvet",  cost = 10000, base_weekly_profit = 550 },
  dyeworks       = { name = "Dyeworks & Velvet",  cost = 10000, base_weekly_profit = 550 },
  wool_weavery   = { name = "Wool Weavery",       cost = 6000, base_weekly_profit = 340 },
  linen_weavery  = { name = "Linen Weavery",      cost = 6000, base_weekly_profit = 350 },
}

-- Equipment slot indices: 0..3 weapons, 4 head, 5 body, 6 foot, 7 hand, 8 horse, 9 food; 10..105 bag (96 slots)
local EQUIP_SLOT_MIN = 0
local EQUIP_SLOT_MAX = 9
local BAG_SLOT_MIN   = 10
local TOTAL_SLOTS    = 106

local SKILL_GOVERNING_ATTR = {
  ironflesh = "str", power_strike = "str", power_throw = "str", power_draw = "str",
  weapon_master = "agi", shield = "agi", athletics = "agi", riding = "agi", horse_archery = "agi", looting = "agi",
  trainer = "int", tracking = "int", tactics = "int", path_finding = "int", spotting = "int",
  inventory_management = "int", wound_treatment = "int", surgery = "int", first_aid = "int",
  engineer = "int", persuasion = "int",
  prisoner_management = "cha", leadership = "cha", trade = "cha",
}

local PERSONAL_SKILLS = {
  ironflesh = true, power_strike = true, power_throw = true, power_draw = true,
  weapon_master = true, shield = true, athletics = true, riding = true, horse_archery = true, persuasion = true,
}

local LEADER_SKILLS = {
  leadership = true, prisoner_management = true, inventory_management = true,
}

function economy.new(opts)
  opts = opts or {}
  local self = setmetatable({}, economy)
  self.players = {}       -- uid -> profile table
  self.merchants = {}     -- center_id -> { [merchant_type] = { gold, slots = {} } }
  self.enterprises = {}   -- town_id -> { [uid] = { kind, built_hour, ready_hour, store_goods, stored_profit } }
  self.trades = {}        -- trade_id -> active P2P trade session
  self.next_trade_id = 1
  return self
end

-- Authentic Native Warband character background calculator
function economy.compute_background_stats(choices)
  choices = choices or {}
  local attr = { str = 5, agi = 5, int = 4, cha = 5 }
  local skills = {
    ironflesh = 0, power_strike = 0, power_throw = 0, power_draw = 0,
    weapon_master = 0, shield = 0, athletics = 0, riding = 1, horse_archery = 0, looting = 0,
    trainer = 0, tracking = 0, tactics = 0, path_finding = 0, spotting = 0,
    inventory_management = 0, wound_treatment = 0, surgery = 0, first_aid = 0,
    engineer = 0, persuasion = 0, prisoner_management = 0, leadership = 1, trade = 0,
  }
  local prof = { one_handed = 45, two_handed = 30, polearm = 35, archery = 30, crossbow = 30, throwing = 25 }
  local gold = 120
  local renown = 0
  local honor = 0
  local gear = {
    [0] = { item_id = "itm_rusty_sword", modifier = 0, ammo = 0 },
    [1] = { item_id = "itm_Hunting_crossbow", modifier = 0, ammo = 0 },
    [2] = { item_id = "itm_bolts", modifier = 0, ammo = 28 },
    [5] = { item_id = "itm_leather_jerkin", modifier = 0, ammo = 0 },
    [6] = { item_id = "itm_wrapping_boots", modifier = 0, ammo = 0 },
    [8] = { item_id = "itm_saddle_horse", modifier = 0, ammo = 0 },
    [10] = { item_id = "itm_smoked_fish", modifier = 0, ammo = 50, food_freshness = 100 },
  }

  -- Gender
  if choices.gender == 1 then -- female
    attr.agi = attr.agi + 1
    attr.int = attr.int + 1
  else -- male
    attr.str = attr.str + 1
    attr.cha = attr.cha + 1
  end

  -- Father (1=noble, 2=merchant, 3=veteran_warrior, 4=hunter, 5=nomad, 6=thief)
  local FATHER_MAP = { noble = 1, merchant = 2, veteran_warrior = 3, hunter = 4, nomad = 5, thief = 6 }
  local EARLY_MAP  = { page = 1, apprentice = 2, shop_assistant = 3, urchin = 4, steppe_child = 5 }
  local ADULT_MAP  = { squire = 1, troubadour = 2, student = 3, peddler = 4, smith = 5, poacher = 6 }
  local REASON_MAP = { revenge = 1, loss = 2, wanderlust = 3, forced_out = 4, wealth = 5 }

  local father = tonumber(choices.father) or FATHER_MAP[tostring(choices.father or "")] or 1
  if father == 1 then
    attr.int = attr.int + 1; attr.cha = attr.cha + 2
    skills.riding = skills.riding + 1; skills.leadership = skills.leadership + 1; skills.power_strike = skills.power_strike + 1
    prof.one_handed = prof.one_handed + 15; prof.polearm = prof.polearm + 15
    gold = gold + 100; renown = renown + 100; honor = honor + 3
    gear[3] = { item_id = "itm_old_tab_shield_round_a", modifier = 0, ammo = 0 }
  elseif father == 2 then
    attr.int = attr.int + 2; attr.cha = attr.cha + 1
    skills.trade = skills.trade + 2; skills.inventory_management = skills.inventory_management + 1; skills.riding = skills.riding + 1
    gold = gold + 250; renown = renown + 20
  elseif father == 3 then
    attr.str = attr.str + 2; attr.agi = attr.agi + 1
    skills.ironflesh = skills.ironflesh + 1; skills.power_strike = skills.power_strike + 1; skills.shield = skills.shield + 1; skills.trainer = skills.trainer + 1
    prof.one_handed = prof.one_handed + 15; prof.two_handed = prof.two_handed + 15; prof.polearm = prof.polearm + 15
    gold = gold + 60; renown = renown + 15
  elseif father == 4 then
    attr.str = attr.str + 1; attr.agi = attr.agi + 2
    skills.power_draw = skills.power_draw + 1; skills.tracking = skills.tracking + 1; skills.path_finding = skills.path_finding + 1; skills.spotting = skills.spotting + 1
    prof.archery = prof.archery + 30
    gear[1] = { item_id = "itm_hunting_bow", modifier = 0, ammo = 0 }
    gear[2] = { item_id = "itm_barbed_arrows", modifier = 0, ammo = 30 }
  elseif father == 5 then
    attr.str = attr.str + 1; attr.agi = attr.agi + 2
    skills.riding = skills.riding + 2; skills.horse_archery = skills.horse_archery + 1; skills.path_finding = skills.path_finding + 1
    prof.archery = prof.archery + 25; prof.one_handed = prof.one_handed + 10
  else
    attr.agi = attr.agi + 3
    skills.athletics = skills.athletics + 2; skills.power_throw = skills.power_throw + 1; skills.looting = skills.looting + 1
    prof.one_handed = prof.one_handed + 20; prof.throwing = prof.throwing + 25
    gold = gold + 40
  end

  -- Early life (1=Page, 2=Craftsman Apprentice, 3=Shop Assistant, 4=Street Urchin, 5=Steppe Child)
  local early = tonumber(choices.early_life or choices.early) or EARLY_MAP[tostring(choices.early_life or choices.early or "")] or 1
  if early == 1 then
    attr.cha = attr.cha + 1; attr.str = attr.str + 1
    skills.power_strike = skills.power_strike + 1; skills.persuasion = skills.persuasion + 1
  elseif early == 2 then
    attr.int = attr.int + 1; attr.str = attr.str + 1
    skills.engineer = skills.engineer + 1; skills.trade = skills.trade + 1
  elseif early == 3 then
    attr.int = attr.int + 1; attr.cha = attr.cha + 1
    skills.inventory_management = skills.inventory_management + 1; skills.trade = skills.trade + 1
    gold = gold + 80
  elseif early == 4 then
    attr.agi = attr.agi + 1; attr.int = attr.int + 1
    skills.spotting = skills.spotting + 1; skills.looting = skills.looting + 1
  else
    attr.str = attr.str + 1; attr.agi = attr.agi + 1
    skills.horse_archery = skills.horse_archery + 1; skills.power_throw = skills.power_throw + 1
  end

  -- Adulthood (1=Squire/Lady-in-waiting, 2=Troubadour, 3=University Student, 4=Goods Peddler, 5=Smith, 6=Poacher)
  local adult = tonumber(choices.adulthood) or ADULT_MAP[tostring(choices.adulthood or "")] or 1
  if adult == 1 then
    attr.str = attr.str + 1; attr.agi = attr.agi + 1
    skills.riding = skills.riding + 1; skills.weapon_master = skills.weapon_master + 1; skills.power_strike = skills.power_strike + 1; skills.leadership = skills.leadership + 1
    prof.one_handed = prof.one_handed + 25; prof.polearm = prof.polearm + 25
  elseif adult == 2 then
    attr.cha = attr.cha + 2
    skills.weapon_master = skills.weapon_master + 1; skills.persuasion = skills.persuasion + 2; skills.leadership = skills.leadership + 1
    gold = gold + 90
  elseif adult == 3 then
    attr.int = attr.int + 2
    skills.wound_treatment = skills.wound_treatment + 1; skills.surgery = skills.surgery + 1; skills.first_aid = skills.first_aid + 1; skills.persuasion = skills.persuasion + 1
    gear[11] = { item_id = "itm_book_wound_treatment_reference", modifier = 0, ammo = 0, read_pct = 0 }
  elseif adult == 4 then
    attr.cha = attr.cha + 1; attr.int = attr.int + 1
    skills.trade = skills.trade + 1; skills.path_finding = skills.path_finding + 1; skills.inventory_management = skills.inventory_management + 1
    gold = gold + 180
    gear[11] = { item_id = "itm_linen", modifier = 0, ammo = 0 }
  elseif adult == 5 then
    attr.str = attr.str + 2
    skills.ironflesh = skills.ironflesh + 1; skills.engineer = skills.engineer + 1; skills.tactics = skills.tactics + 1
    gold = gold + 110
  else
    attr.str = attr.str + 1; attr.agi = attr.agi + 1
    skills.power_draw = skills.power_draw + 1; skills.tracking = skills.tracking + 1; skills.spotting = skills.spotting + 1; skills.athletics = skills.athletics + 1
    prof.archery = prof.archery + 30
  end

  -- Reason for adventuring (1=Personal Revenge, 2=Loss of Loved One, 3=Wanderlust, 4=Forced Out, 5=Lust for Money)
  local reason = tonumber(choices.reason) or REASON_MAP[tostring(choices.reason or "")] or 3
  if reason == 1 then
    attr.str = attr.str + 2; skills.power_strike = skills.power_strike + 1
  elseif reason == 2 then
    attr.cha = attr.cha + 2; skills.ironflesh = skills.ironflesh + 1
  elseif reason == 3 then
    attr.agi = attr.agi + 2; skills.path_finding = skills.path_finding + 1
  elseif reason == 4 then
    attr.str = attr.str + 1; attr.int = attr.int + 1; skills.weapon_master = skills.weapon_master + 1
  else
    attr.agi = attr.agi + 1; attr.int = attr.int + 1; skills.looting = skills.looting + 1; gold = gold + 120
  end

  -- Clamp initial skills to governing attribute / 3 if needed, or raise free points cleanly
  for sk, gov in pairs(SKILL_GOVERNING_ATTR) do
    local cap = math.min(10, math.floor(attr[gov] / 3))
    if skills[sk] > cap then
      skills[sk] = cap
    end
  end

  return {
    attributes = attr,
    skills = skills,
    proficiencies = prof,
    gold = gold,
    renown = renown,
    honor = honor,
    gear = gear,
  }
end

function economy:create_character(uid, hero_slot, nickname, choices, friend_pos)
  local bg = economy.compute_background_stats(choices)
  local town_idx = tonumber(choices and choices.start_town_idx or 1)
  local town = economy.STARTING_TOWNS[town_idx] or economy.STARTING_TOWNS[1]
  local spawn_x, spawn_y = town.x, town.y
  if type(friend_pos) == "table" and friend_pos.x and friend_pos.y then
    spawn_x = friend_pos.x + 0.8
    spawn_y = friend_pos.y + 0.8
  end

  local inventory = {}
  for slot_idx, item in pairs(bg.gear) do
    inventory[tostring(slot_idx)] = item
  end

  local profile = {
    uid = uid,
    hero_slot = hero_slot,
    nickname = nickname or "Adventurer",
    gender = tonumber(choices and choices.gender or 0),
    banner_id = tonumber(choices and choices.banner_id or (hero_slot + 1)),
    level = 1,
    xp = 0,
    free_attr_points = 4,
    free_skill_points = 4,
    free_prof_points = 10,
    attributes = bg.attributes,
    skills = bg.skills,
    proficiencies = bg.proficiencies,
    gold = bg.gold,
    wage_debt = 0,
    renown = bg.renown,
    honor = bg.honor,
    right_to_rule = 0,
    morale = 75,
    hp_pct = 100,
    pos = { x = spawn_x, y = spawn_y },
    current_center = town.id,
    in_camp = false,
    reading_book_slot = nil,
    snapshot_epoch = 1,
    inventory = inventory,
    -- Party stacks: array of { troop_id, count, wounded, num_upgradeable, xp_pool }
    party_stacks = {
      { troop_id = "trp_swadian_recruit", count = 5, wounded = 0, num_upgradeable = 0, xp_pool = 0 },
    },
    prisoners = {},
    companions = {}, -- companion troop_ids in party
    fiefs = {},      -- owned center_ids
    allegiance_faction = "fac_coop_player_" .. tostring(hero_slot % 16),
    mercenary_faction = nil,
    mercenary_end_hour = 0,
    spouse_id = nil,
    food_last_tick_hour = 0,
  }

  self.players[uid] = profile
  return profile
end

function economy:get_player(uid)
  return self.players[uid]
end

function economy:get_bag_capacity(uid)
  local p = self.players[uid]
  if not p then return 30 end
  local im = tonumber(p.skills.inventory_management or 0)
  return math.min(96, 30 + im * 6)
end

function economy:get_party_size_limit(uid)
  local p = self.players[uid]
  if not p then return 30 end
  local lead = tonumber(p.skills.leadership or 0)
  local cha = tonumber(p.attributes.cha or 5)
  local renown = tonumber(p.renown or 0)
  local castle_bonus = 0
  for _, fief_id in ipairs(p.fiefs or {}) do
    if tostring(fief_id):find("castle") or tostring(fief_id):find("town") then
      castle_bonus = castle_bonus + 20
    end
  end
  return 30 + lead * 5 + cha + math.floor(renown / 25) + castle_bonus
end

function economy:get_prisoner_limit(uid)
  local p = self.players[uid]
  if not p then return 0 end
  return tonumber(p.skills.prisoner_management or 0) * 5
end

-- Effective party skill calculation: max(healthy heroes in party) + leader bonus (+1..+4)
function economy:get_effective_party_skill(uid, skill_name, companion_lookup)
  local p = self.players[uid]
  if not p then return 0 end
  local own_val = (p.hp_pct or 100) >= 20 and tonumber(p.skills[skill_name] or 0) or 0
  if PERSONAL_SKILLS[skill_name] or LEADER_SKILLS[skill_name] then
    return own_val
  end
  local best = own_val
  if type(companion_lookup) == "table" then
    for _, comp_id in ipairs(p.companions or {}) do
      local c = companion_lookup[comp_id]
      if c and (c.hp_pct or 100) >= 20 then
        local cv = tonumber(c.skills and c.skills[skill_name] or 0)
        if cv > best then
          best = cv
        end
      end
    end
  end
  local leader_bonus = 0
  if own_val >= 10 then leader_bonus = 4
  elseif own_val >= 8 then leader_bonus = 3
  elseif own_val >= 5 then leader_bonus = 2
  elseif own_val >= 2 then leader_bonus = 1
  end
  return math.min(14, best + leader_bonus)
end

-- Spend character attribute / skill / weapon proficiency point (server-validated)
function economy:spend_stat_point(uid, kind, stat_name)
  local p = self.players[uid]
  if not p then return false, "unknown_player" end

  if kind == "attr" then
    if p.free_attr_points < 1 then return false, "no_free_attr_points" end
    if p.attributes[stat_name] == nil then return false, "invalid_attribute" end
    if p.attributes[stat_name] >= 63 then return false, "attribute_at_cap" end
    p.attributes[stat_name] = p.attributes[stat_name] + 1
    p.free_attr_points = p.free_attr_points - 1
    if stat_name == "int" then
      p.free_skill_points = p.free_skill_points + 1
    end
    p.snapshot_epoch = p.snapshot_epoch + 1
    return true, p.attributes[stat_name]
  elseif kind == "skill" then
    if p.free_skill_points < 1 then return false, "no_free_skill_points" end
    local gov = SKILL_GOVERNING_ATTR[stat_name]
    if not gov then return false, "invalid_skill" end
    local cur = tonumber(p.skills[stat_name] or 0)
    local cap = math.min(10, math.floor(p.attributes[gov] / 3))
    if cur >= cap then return false, "skill_at_attribute_cap" end
    p.skills[stat_name] = cur + 1
    p.free_skill_points = p.free_skill_points - 1
    p.snapshot_epoch = p.snapshot_epoch + 1
    return true, p.skills[stat_name]
  elseif kind == "prof" then
    if p.proficiencies[stat_name] == nil then return false, "invalid_proficiency" end
    local wm = tonumber(p.skills.weapon_master or 0)
    local cap = 60 + wm * 40
    local cur = p.proficiencies[stat_name]
    if cur >= cap then return false, "proficiency_at_weapon_master_cap" end
    local cost = math.max(1, math.floor(cur / 60))
    if p.free_prof_points < cost then return false, "insufficient_prof_points" end
    p.proficiencies[stat_name] = cur + 1
    p.free_prof_points = p.free_prof_points - cost
    p.snapshot_epoch = p.snapshot_epoch + 1
    return true, p.proficiencies[stat_name]
  end
  return false, "invalid_stat_kind"
end

-- Grant character XP with automatic level-up calculation
function economy:grant_hero_xp(uid, xp_amount)
  local p = self.players[uid]
  if not p or xp_amount <= 0 then return 0 end
  p.xp = p.xp + math.floor(xp_amount)
  local levels_gained = 0
  while p.level < 62 do
    local needed = math.floor(600 * (p.level ^ 1.85))
    if p.xp >= needed then
      p.level = p.level + 1
      p.free_attr_points = p.free_attr_points + 1
      p.free_skill_points = p.free_skill_points + 1
      p.free_prof_points = p.free_prof_points + 10
      levels_gained = levels_gained + 1
    else
      break
    end
  end
  if levels_gained > 0 then
    p.snapshot_epoch = p.snapshot_epoch + 1
  end
  return levels_gained
end

-- Server-authoritative inventory swap with snapshot_epoch optimistic concurrency check
function economy:swap_inventory_slots(uid, client_epoch, from_slot, to_slot)
  local p = self.players[uid]
  if not p then return false, "unknown_player" end
  if client_epoch ~= p.snapshot_epoch then
    return false, "stale_snapshot_epoch"
  end
  local max_slot = BAG_SLOT_MIN + self:get_bag_capacity(uid) - 1
  if from_slot < EQUIP_SLOT_MIN or from_slot > max_slot or to_slot < EQUIP_SLOT_MIN or to_slot > max_slot then
    return false, "slot_out_of_bounds"
  end
  local k_from = tostring(from_slot)
  local k_to   = tostring(to_slot)
  p.inventory[k_from], p.inventory[k_to] = p.inventory[k_to], p.inventory[k_from]
  p.snapshot_epoch = p.snapshot_epoch + 1
  return true, p.snapshot_epoch
end

function economy:find_first_free_bag_slot(uid)
  local p = self.players[uid]
  if not p then return nil end
  local max_slot = BAG_SLOT_MIN + self:get_bag_capacity(uid) - 1
  for s = BAG_SLOT_MIN, max_slot do
    if p.inventory[tostring(s)] == nil then
      return s
    end
  end
  return nil
end

-- Merchant registration & trade transaction (server computes exact price; client cannot spoof gold)
function economy:ensure_merchant(center_id, merchant_type, initial_gold, initial_items)
  self.merchants[center_id] = self.merchants[center_id] or {}
  if not self.merchants[center_id][merchant_type] then
    local slots = {}
    for i, itm in ipairs(initial_items or {}) do
      slots[tostring(i)] = {
        item_id = itm.item_id,
        base_price = itm.base_price or 100,
        modifier = itm.modifier or 0,
        ammo = itm.ammo or 0,
        food_freshness = itm.food_freshness,
      }
    end
    self.merchants[center_id][merchant_type] = {
      gold = initial_gold or 1500,
      demand_factor = 1.0,
      slots = slots,
    }
  end
  return self.merchants[center_id][merchant_type]
end

function economy:compute_trade_price(base_price, is_buy, trade_skill, demand_factor)
  demand_factor = demand_factor or 1.0
  local penalty = math.max(0.05, 1.0 - 0.05 * math.min(14, trade_skill or 0))
  if is_buy then
    local markup = 1.0 + 0.45 * penalty
    return math.max(1, math.floor(base_price * demand_factor * markup + 0.5))
  else
    local markdown = math.max(0.20, 0.75 - 0.30 * penalty)
    return math.max(1, math.floor(base_price * demand_factor * markdown + 0.5))
  end
end

function economy:merchant_transaction(uid, center_id, merchant_type, is_buy, slot_no, expected_item_id, companion_lookup)
  local p = self.players[uid]
  if not p then return false, "unknown_player" end
  local m = self.merchants[center_id] and self.merchants[center_id][merchant_type]
  if not m then return false, "unknown_merchant" end

  local trade_skill = self:get_effective_party_skill(uid, "trade", companion_lookup)
  local skey = tostring(slot_no)

  if is_buy then
    local offer = m.slots[skey]
    if not offer or offer.item_id ~= expected_item_id then
      return false, "merchant_item_mismatch"
    end
    local dst_slot = self:find_first_free_bag_slot(uid)
    if not dst_slot then
      return false, "inventory_full"
    end
    local price = self:compute_trade_price(offer.base_price or 100, true, trade_skill, m.demand_factor)
    if p.gold < price then
      return false, "insufficient_gold"
    end
    p.gold = p.gold - price
    m.gold = m.gold + price
    m.slots[skey] = nil
    m.demand_factor = math.min(1.60, (m.demand_factor or 1.0) + 0.03)
    p.inventory[tostring(dst_slot)] = offer
    p.snapshot_epoch = p.snapshot_epoch + 1
    return true, { price = price, bag_slot = dst_slot, new_gold = p.gold, epoch = p.snapshot_epoch }
  else
    local item = p.inventory[skey]
    if not item or item.item_id ~= expected_item_id then
      return false, "player_item_mismatch"
    end
    local price = self:compute_trade_price(item.base_price or 100, false, trade_skill, m.demand_factor)
    if m.gold < price then
      return false, "merchant_insufficient_gold"
    end
    -- Place into merchant free slot
    local m_free = 1
    while m.slots[tostring(m_free)] ~= nil do
      m_free = m_free + 1
    end
    p.inventory[skey] = nil
    p.gold = p.gold + price
    m.gold = m.gold - price
    m.slots[tostring(m_free)] = item
    m.demand_factor = math.max(0.65, (m.demand_factor or 1.0) - 0.03)
    p.snapshot_epoch = p.snapshot_epoch + 1
    return true, { price = price, merchant_slot = m_free, new_gold = p.gold, epoch = p.snapshot_epoch }
  end
end

-- Per-player productive enterprises in towns
function economy:buy_enterprise(uid, town_id, enterprise_kind, cur_campaign_hour, lord_relation)
  local p = self.players[uid]
  if not p then return false, "unknown_player" end
  local spec = economy.ENTERPRISE_TYPES[enterprise_kind]
  if not spec then return false, "invalid_enterprise_type" end
  if (lord_relation or 0) < 0 then
    return false, "negative_lord_relation"
  end
  self.enterprises[town_id] = self.enterprises[town_id] or {}
  if self.enterprises[town_id][uid] then
    return false, "already_owns_enterprise_in_town"
  end
  if p.gold < spec.cost then
    return false, "insufficient_gold"
  end
  p.gold = p.gold - spec.cost
  p.snapshot_epoch = p.snapshot_epoch + 1
  local ent = {
    kind = enterprise_kind,
    built_hour = cur_campaign_hour,
    ready_hour = cur_campaign_hour + (7 * 24), -- 7 days construction
    weekly_profit = spec.base_weekly_profit,
    store_goods = false,
    stored_goods_count = 0,
  }
  self.enterprises[town_id][uid] = ent
  return true, ent
end

-- Troop upgrades & midnight Trainer XP
function economy:upgrade_troop_stack(uid, stack_idx, target_troop_id, count, cost_per_unit)
  local p = self.players[uid]
  if not p then return false, "unknown_player" end
  local st = p.party_stacks[stack_idx]
  if not st then return false, "invalid_stack" end
  count = math.max(1, math.floor(count or 1))
  local avail = math.min(st.count - (st.wounded or 0), st.num_upgradeable or 0)
  if avail < count then
    return false, "not_enough_upgradeable_troops"
  end
  local total_cost = count * math.max(0, cost_per_unit or 20)
  if p.gold < total_cost then
    return false, "insufficient_gold"
  end

  p.gold = p.gold - total_cost
  st.count = st.count - count
  st.num_upgradeable = st.num_upgradeable - count
  if st.count <= 0 then
    table.remove(p.party_stacks, stack_idx)
  end

  -- Merge into existing stack of target_troop_id or append
  local merged = false
  for _, existing in ipairs(p.party_stacks) do
    if existing.troop_id == target_troop_id then
      existing.count = existing.count + count
      merged = true
      break
    end
  end
  if not merged then
    p.party_stacks[#p.party_stacks + 1] = {
      troop_id = target_troop_id,
      count = count,
      wounded = 0,
      num_upgradeable = 0,
      xp_pool = 0,
    }
  end
  p.snapshot_epoch = p.snapshot_epoch + 1
  return true, { cost = total_cost, new_gold = p.gold }
end

function economy:apply_daily_trainer_xp(uid, companion_lookup, troop_tier_lookup)
  local p = self.players[uid]
  if not p then return 0 end
  local total_xp_awarded = 0
  local trainers = {
    { level = p.level, skill = tonumber(p.skills.trainer or 0), healthy = (p.hp_pct or 100) >= 20 },
  }
  if type(companion_lookup) == "table" then
    for _, cid in ipairs(p.companions or {}) do
      local c = companion_lookup[cid]
      if c then
        trainers[#trainers + 1] = {
          level = c.level or 1,
          skill = tonumber(c.skills and c.skills.trainer or 0),
          healthy = (c.hp_pct or 100) >= 20,
        }
      end
    end
  end

  local xp_per_skill = { [0] = 0, 4, 10, 16, 23, 30, 38, 46, 55, 65, 80 }
  for _, st in ipairs(p.party_stacks) do
    local tier = (troop_tier_lookup and troop_tier_lookup[st.troop_id]) or 1
    local troop_lvl = tier * 5
    local stack_xp = 0
    for _, tr in ipairs(trainers) do
      if tr.healthy and tr.skill > 0 and tr.level > troop_lvl then
        stack_xp = stack_xp + (xp_per_skill[math.min(10, tr.skill)] or 0) * st.count
      end
    end
    if stack_xp > 0 then
      st.xp_pool = (st.xp_pool or 0) + stack_xp
      local xp_per_upgrade = tier * 150
      local newly_ready = math.floor(st.xp_pool / xp_per_upgrade)
      if newly_ready > 0 and tier < 5 then
        local max_new = st.count - (st.num_upgradeable or 0)
        local add_u = math.min(max_new, newly_ready)
        st.num_upgradeable = (st.num_upgradeable or 0) + add_u
        st.xp_pool = st.xp_pool - add_u * xp_per_upgrade
      end
      total_xp_awarded = total_xp_awarded + stack_xp
    end
  end
  return total_xp_awarded
end

-- Food consumption (every 14h), variety morale & fresh meat spoilage
function economy:tick_party_food_and_morale(uid, cur_hour)
  local p = self.players[uid]
  if not p then return nil end
  if cur_hour - (p.food_last_tick_hour or 0) < 14 then
    return p.morale
  end
  p.food_last_tick_hour = cur_hour

  local total_men = 1 + #(p.companions or {})
  for _, st in ipairs(p.party_stacks) do
    total_men = total_men + st.count
  end
  local needed_units = math.max(1, math.ceil(total_men / 3))

  local distinct_foods = {}
  local fed_units = 0
  for s = EQUIP_SLOT_MAX, BAG_SLOT_MIN + 95 do
    if s == 9 or s >= BAG_SLOT_MIN then
      local k = tostring(s)
      local itm = p.inventory[k]
      if itm and (itm.ammo or 0) > 0 and tostring(itm.item_id):match("fish|bread|grain|meat|cheese|honey|sausages|fruit|cabbage|butter|chicken|pork") then
        -- Spoilage for perishable meats
        if itm.food_freshness ~= nil and tostring(itm.item_id):match("meat|chicken|pork") then
          itm.food_freshness = itm.food_freshness - 15
          if itm.food_freshness <= 0 then
            p.inventory[k] = nil
            itm = nil
          end
        end
        if itm then
          distinct_foods[itm.item_id] = true
          if fed_units < needed_units then
            local eat = math.min(itm.ammo, needed_units - fed_units)
            itm.ammo = itm.ammo - eat
            fed_units = fed_units + eat
            if itm.ammo <= 0 then
              p.inventory[k] = nil
            end
          end
        end
      end
    end
  end

  local variety_count = 0
  for _ in pairs(distinct_foods) do
    variety_count = variety_count + 1
  end

  local base_morale = 50
  local lead_bonus = tonumber(p.skills.leadership or 0) * 12
  local food_bonus = (fed_units >= needed_units) and (variety_count * 5) or -30
  local size_penalty = total_men
  local debt_penalty = math.min(30, math.floor((p.wage_debt or 0) / 100))
  local target_morale = math.max(0, math.min(99, base_morale + lead_bonus + food_bonus - size_penalty - debt_penalty))
  p.morale = math.floor((p.morale * 2 + target_morale) / 3)

  -- Low morale desertion
  local deserted = 0
  if p.morale < 20 and #p.party_stacks > 0 then
    local st = p.party_stacks[#p.party_stacks]
    deserted = math.min(st.count, math.max(1, math.floor((20 - p.morale) / 5)))
    st.count = st.count - deserted
    if st.count <= 0 then
      table.remove(p.party_stacks, #p.party_stacks)
    end
  end
  p.snapshot_epoch = p.snapshot_epoch + 1
  return p.morale, deserted
end

-- Weekly 7-day budget settlement
function economy:settle_weekly_budget(uid, cur_hour, world_ctx)
  local p = self.players[uid]
  if not p then return nil end
  world_ctx = world_ctx or {}

  local lead = tonumber(p.skills.leadership or 0)
  local wage_mult = math.max(0.30, 1.0 - 0.05 * lead)

  local raw_party_wages = 0
  for _, st in ipairs(p.party_stacks) do
    local unit_wage = (world_ctx.troop_wages and world_ctx.troop_wages[st.troop_id]) or 7
    raw_party_wages = raw_party_wages + st.count * unit_wage
  end
  raw_party_wages = raw_party_wages + #(p.companions or {}) * 25
  local party_wages = math.floor(raw_party_wages * wage_mult)
  local garrison_wages = math.floor((world_ctx.garrison_raw_wages or 0) * 0.5 * wage_mult)

  local fief_gross = 0
  local num_fiefs = #(p.fiefs or {})
  for _, fief_id in ipairs(p.fiefs or {}) do
    local rent = (world_ctx.fief_rents and world_ctx.fief_rents[fief_id]) or 350
    fief_gross = fief_gross + rent
  end

  -- Tax inefficiency above 2 fiefs (exact Warband spirit: 4% per extra fief, capped at 65%)
  local tax_loss = 0
  if num_fiefs > 2 then
    local ineff_pct = math.min(0.65, (num_fiefs - 2) * 0.04)
    tax_loss = math.floor(fief_gross * ineff_pct)
  end
  local fief_net = fief_gross - tax_loss

  -- Productive enterprises across all towns (sequestered if at war with town's faction!)
  local ent_net = 0
  for town_id, owners in pairs(self.enterprises) do
    local ent = owners[uid]
    if ent and cur_hour >= ent.ready_hour then
      local at_war = world_ctx.war_towns and world_ctx.war_towns[town_id]
      if not at_war then
        local spec = economy.ENTERPRISE_TYPES[ent.kind]
        if spec then
          if ent.store_goods then
            ent.stored_goods_count = (ent.stored_goods_count or 0) + 1
          else
            ent_net = ent_net + spec.base_weekly_profit
          end
        end
      end
    end
  end

  local merc_pay = 0
  if p.mercenary_faction and cur_hour < (p.mercenary_end_hour or 0) then
    merc_pay = math.floor(party_wages * 0.85) + 100
  end

  local total_income = fief_net + ent_net + merc_pay
  local total_expenses = party_wages + garrison_wages
  local net_delta = total_income - total_expenses

  p.gold = p.gold + net_delta
  if p.gold < 0 then
    p.wage_debt = (p.wage_debt or 0) + (-p.gold)
    p.gold = 0
    p.morale = math.max(0, p.morale - 10)
  elseif p.wage_debt > 0 and p.gold > 0 then
    local pay_debt = math.min(p.gold, p.wage_debt)
    p.gold = p.gold - pay_debt
    p.wage_debt = p.wage_debt - pay_debt
  end
  p.snapshot_epoch = p.snapshot_epoch + 1

  return {
    party_wages = party_wages,
    garrison_wages = garrison_wages,
    fief_net = fief_net,
    tax_loss = tax_loss,
    enterprise_net = ent_net,
    mercenary_pay = merc_pay,
    net_delta = net_delta,
    new_gold = p.gold,
    wage_debt = p.wage_debt,
  }
end

-- Two-Phase Atomic Player-to-Player Trade (immune to item/gold duplication & bait-and-switch scams)
function economy:open_p2p_trade(uid_a, uid_b)
  if uid_a == uid_b then return nil, "cannot_trade_with_self" end
  if not self.players[uid_a] or not self.players[uid_b] then
    return nil, "unknown_participant"
  end
  local tid = self.next_trade_id
  self.next_trade_id = self.next_trade_id + 1
  local session = {
    trade_id = tid,
    uid_a = uid_a,
    uid_b = uid_b,
    offers = {
      [uid_a] = { gold = 0, item_slots = {}, locked = false, confirmed = false },
      [uid_b] = { gold = 0, item_slots = {}, locked = false, confirmed = false },
    },
    completed = false,
  }
  self.trades[tid] = session
  return session, nil
end

local function reset_trade_locks(session)
  session.offers[session.uid_a].locked = false
  session.offers[session.uid_a].confirmed = false
  session.offers[session.uid_b].locked = false
  session.offers[session.uid_b].confirmed = false
end

function economy:p2p_set_offer(trade_id, uid, gold_amount, slot_list)
  local s = self.trades[trade_id]
  if not s or s.completed then return false, "invalid_trade" end
  local side = s.offers[uid]
  if not side then return false, "not_in_trade" end
  local p = self.players[uid]
  gold_amount = math.max(0, math.floor(gold_amount or 0))
  if gold_amount > p.gold then
    return false, "insufficient_gold"
  end

  local seen = {}
  local clean_slots = {}
  for _, sl in ipairs(slot_list or {}) do
    local s_num = tonumber(sl)
    if not s_num or seen[s_num] or not p.inventory[tostring(s_num)] then
      return false, "invalid_or_duplicate_item_slot"
    end
    seen[s_num] = true
    clean_slots[#clean_slots + 1] = s_num
  end

  -- Any edit immediately unlocks both participants to prevent last-millisecond scamming
  reset_trade_locks(s)
  side.gold = gold_amount
  side.item_slots = clean_slots
  return true, nil
end

function economy:p2p_lock(trade_id, uid)
  local s = self.trades[trade_id]
  if not s or s.completed then return false, "invalid_trade" end
  if not s.offers[uid] then return false, "not_in_trade" end
  s.offers[uid].locked = true
  return true, nil
end

function economy:p2p_confirm(trade_id, uid)
  local s = self.trades[trade_id]
  if not s or s.completed then return false, "invalid_trade" end
  local oa = s.offers[s.uid_a]
  local ob = s.offers[s.uid_b]
  if not s.offers[uid] then return false, "not_in_trade" end
  if not (oa.locked and ob.locked) then
    return false, "both_sides_must_lock_first"
  end
  s.offers[uid].confirmed = true
  if not (oa.confirmed and ob.confirmed) then
    return true, "waiting_other_party"
  end

  -- ATOMIC PRE-FLIGHT VERIFICATION & COMMIT
  local pa = self.players[s.uid_a]
  local pb = self.players[s.uid_b]
  if pa.gold < oa.gold or pb.gold < ob.gold then
    self.trades[trade_id] = nil
    return false, "gold_changed_abort"
  end

  local items_from_a = {}
  for _, sl in ipairs(oa.item_slots) do
    local itm = pa.inventory[tostring(sl)]
    if not itm then
      self.trades[trade_id] = nil
      return false, "item_missing_abort"
    end
    items_from_a[#items_from_a + 1] = { slot = sl, item = itm }
  end

  local items_from_b = {}
  for _, sl in ipairs(ob.item_slots) do
    local itm = pb.inventory[tostring(sl)]
    if not itm then
      self.trades[trade_id] = nil
      return false, "item_missing_abort"
    end
    items_from_b[#items_from_b + 1] = { slot = sl, item = itm }
  end

  -- Verify free bag slots on both receivers AFTER removing their outgoing items
  local function count_free_after_remove(p_uid, outgoing_count)
    local p = self.players[p_uid]
    local cap = self:get_bag_capacity(p_uid)
    local free = 0
    for sl = BAG_SLOT_MIN, BAG_SLOT_MIN + cap - 1 do
      if p.inventory[tostring(sl)] == nil then
        free = free + 1
      end
    end
    return free + outgoing_count
  end

  if count_free_after_remove(s.uid_a, #items_from_a) < #items_from_b then
    return false, "receiver_a_bag_full"
  end
  if count_free_after_remove(s.uid_b, #items_from_b) < #items_from_a then
    return false, "receiver_b_bag_full"
  end

  -- Execute atomic transfer
  for _, rec in ipairs(items_from_a) do
    pa.inventory[tostring(rec.slot)] = nil
  end
  for _, rec in ipairs(items_from_b) do
    pb.inventory[tostring(rec.slot)] = nil
  end

  for _, rec in ipairs(items_from_b) do
    local dst = self:find_first_free_bag_slot(s.uid_a)
    pa.inventory[tostring(dst)] = rec.item
  end
  for _, rec in ipairs(items_from_a) do
    local dst = self:find_first_free_bag_slot(s.uid_b)
    pb.inventory[tostring(dst)] = rec.item
  end

  pa.gold = pa.gold - oa.gold + ob.gold
  pb.gold = pb.gold - ob.gold + oa.gold
  pa.snapshot_epoch = pa.snapshot_epoch + 1
  pb.snapshot_epoch = pb.snapshot_epoch + 1

  s.completed = true
  self.trades[trade_id] = nil
  return true, "committed"
end

function economy:cancel_p2p_trade(trade_id)
  self.trades[trade_id] = nil
  return true
end

-- Ergonomic helper methods & unified aliases used across main.lua, quests.lua, battles.lua & test suites
function economy:ensure_player(uid, hero_slot, nickname)
  if self.players[uid] then
    return self.players[uid]
  end
  local p = self:create_character(uid, hero_slot or 0, nickname or "Adventurer", {})
  p.name = p.nickname
  return p
end

function economy:move_inventory_item(uid, from_slot, to_slot, client_epoch)
  return self:swap_inventory_slots(uid, client_epoch, from_slot, to_slot)
end

function economy:recruit_troops(uid, troop_id, count, cost_per_man)
  local p = self.players[uid]
  if not p then return false, "unknown_player" end
  count = math.max(1, math.floor(count or 1))
  local free = self:get_party_size_limit(uid)
  for _, st in ipairs(p.party_stacks) do free = free - st.count end
  count = math.min(count, math.max(0, free))
  if count <= 0 then return false, "party_full" end
  local cost = count * math.max(0, cost_per_man or 10)
  if p.gold < cost then return false, "insufficient_gold" end
  p.gold = p.gold - cost
  for _, st in ipairs(p.party_stacks) do
    if st.troop_id == troop_id then
      st.count = st.count + count
      p.snapshot_epoch = p.snapshot_epoch + 1
      return true, st.count
    end
  end
  p.party_stacks[#p.party_stacks + 1] = { troop_id = troop_id, count = count, wounded = 0, num_upgradeable = 0, xp_pool = 0 }
  p.snapshot_epoch = p.snapshot_epoch + 1
  return true, count
end

function economy:merchant_buy(uid, center_id, item_spec, companion_lookup)
  local m = self:ensure_merchant(center_id, "goods", 2500, { item_spec })
  local slot_no = 1
  while m.slots[tostring(slot_no)] ~= nil do slot_no = slot_no + 1 end
  m.slots[tostring(slot_no)] = {
    item_id = item_spec.item_id,
    base_price = item_spec.base_price or 50,
    ammo = item_spec.food_amount or item_spec.ammo or 0,
    modifier = 0,
  }
  return self:merchant_transaction(uid, center_id, "goods", true, slot_no, item_spec.item_id, companion_lookup)
end

function economy:update_p2p_offer(trade_id, uid, gold_amount, slot_list)
  return self:p2p_set_offer(trade_id, uid, gold_amount, slot_list)
end

function economy:lock_p2p_trade(trade_id, uid)
  return self:p2p_lock(trade_id, uid)
end

function economy:confirm_p2p_trade(trade_id, uid)
  local ok, res = self:p2p_confirm(trade_id, uid)
  if not ok and res == "both_sides_must_lock_first" then
    return false, "both_must_lock_first"
  end
  return ok, res
end

function economy:tick_food_consumption(uid, cur_hour)
  return self:tick_party_food_and_morale(uid, cur_hour or 14)
end

function economy:tick_daily_trainer(uid, companion_lookup)
  return self:apply_daily_trainer_xp(uid, companion_lookup)
end

function economy:tick_weekly_budget(uid, cur_hour)
  local rep = self:settle_weekly_budget(uid, cur_hour or 168)
  return true, rep
end

return economy
