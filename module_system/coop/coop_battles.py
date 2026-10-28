# -*- coding: utf-8 -*-
# Calradia Online: Tactical 3D Battle Bridge, Per-Commander Divisions & Live Drop-in Reinforcements

from header_common import *
from header_operations import *
from header_mission_templates import *
from module_constants import *
from coop.coop_constants import *

coop_battle_scripts = [
  # Assign spawned AI soldier to its owner player's personal tactical division block!
  # Commander 0 controls divisions 0..2 (Infantry/Archers/Cavalry), Commander 1 controls 3..5, Commander 2 controls 6..8.
  ("coop_assign_agent_commander_division", [
    (store_script_param, ":agent_no", 1),
    (store_script_param, ":commander_index", 2),
    (store_script_param, ":base_class", 3), # 0=Infantry, 1=Archers, 2=Cavalry

    (val_clamp, ":commander_index", 0, 2),
    (val_clamp, ":base_class", 0, 2),
    (store_mul, ":div_ofs", ":commander_index", 3),
    (store_add, ":final_div", ":div_ofs", ":base_class"),
    (agent_set_division, ":agent_no", ":final_div"),
  ]),

  # Bind local commander's F1/F2/F3 order listener strictly to their own 3 divisions so friends never steal orders!
  ("coop_bind_commander_order_listener", [
    (store_script_param, ":team_no", 1),
    (store_script_param, ":commander_index", 2),

    (val_clamp, ":commander_index", 0, 2),
    (store_mul, ":div_base", ":commander_index", 3),
    (store_add, ":div_arch", ":div_base", 1),
    (store_add, ":div_cav", ":div_base", 2),
    (team_set_order_listener, ":team_no", -1, 0),
    (team_set_order_listener, ":team_no", ":div_base", 1),
    (team_set_order_listener, ":team_no", ":div_arch", 1),
    (team_set_order_listener, ":team_no", ":div_cav", 1),
  ]),

  # Emergency brake when any player enters an encounter during 3x/5x map fast-forward
  ("coop_on_player_encounter_started", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":enemy_party", 2),
    (try_begin),
      (gt, "$g_coop_effective_speed", 1),
      (call_script, "script_coop_apply_campaign_speed", 1),
      (call_script, "script_coop_sv_broadcast_speed_state", 1),
    (try_end),
    (player_get_party_id, ":party_no", ":player_no"),
    (try_begin),
      (gt, ":party_no", 0),
      (party_set_slot, ":party_no", slot_party_coop_active_battle, ":enemy_party"),
    (try_end),
  ]),
]
