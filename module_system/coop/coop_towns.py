# -*- coding: utf-8 -*-
# Calradia Online: Live Town Markets, Per-Player Productive Enterprises & Shared Tournaments

from header_common import *
from header_operations import *
from module_constants import *
from coop.coop_constants import *

coop_town_scripts = [
  # Server-side village volunteer recruitment for an individual player party (isolated per player!)
  ("coop_sv_recruit_village_volunteers", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":village_no", 2),
    (store_script_param, ":recruit_troop", 3),
    (store_script_param, ":amount", 4),

    (player_get_party_id, ":party_no", ":player_no"),
    (player_get_troop_id, ":hero_trp", ":player_no"),
    (try_begin),
      (gt, ":party_no", 0),
      (ge, ":hero_trp", 0),
      (gt, ":amount", 0),
      (is_between, ":village_no", villages_begin, villages_end),
      (party_get_free_companions_capacity, ":free_cap", ":party_no"),
      (val_min, ":amount", ":free_cap"),
      (gt, ":amount", 0),
      (store_mul, ":cost", ":amount", 10),
      (store_troop_gold, ":cur_gold", ":hero_trp"),
      (ge, ":cur_gold", ":cost"),
      (troop_remove_gold, ":hero_trp", ":cost"),
      (party_add_members, ":party_no", ":recruit_troop", ":amount"),
    (try_end),
  ]),
]
