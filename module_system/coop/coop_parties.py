# -*- coding: utf-8 -*-
# Calradia Online: Multi-Party Binding, Consensus Map Speed & Anti-Combat-Log

from header_common import *
from header_operations import *
from header_parties import *
from module_constants import *
from coop.coop_constants import *

coop_party_scripts = [
  # Bind an authenticated network player to their persistent hero_slot (0..31) troop & map party!
  # Replaces vanilla Native-Coop's naive `player_no` indexing so reconnecting friends ALWAYS get their own hero & army!
  ("coop_bind_player_to_hero_party", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":hero_slot", 2),

    (val_clamp, ":hero_slot", 0, COOP_MAX_PERSISTENT_HEROES),
    (store_add, ":troop_no", multiplayer_campaign_player_troops_begin, ":hero_slot"),
    (store_add, ":party_no", multiplayer_campaign_player_parties_begin, ":hero_slot"),

    (str_store_player_username, s0, ":player_no"),
    (troop_set_name, ":troop_no", s0),
    (player_set_troop_id, ":player_no", ":troop_no"),

    (party_set_name, ":party_no", s0),
    (party_set_slot, ":party_no", slot_party_coop_owner_slot, ":hero_slot"),
    (party_set_slot, ":party_no", slot_party_coop_logout_grace, 0),
    (player_set_party_id, ":player_no", ":party_no"),
    (enable_party, ":party_no"),

    (multiplayer_send_2_int_to_player, ":player_no",
      multiplayer_event_multiplayer_campaign_server_events,
      multiplayer_event_multiplayer_campaign_server_event_camera_follow_party, ":party_no"),
  ]),

  # Apply consensus speed on WSE2 dedicated campaign server (0 = stop_time 1, >0 = stop_time 0 + time multiplier)
  ("coop_apply_campaign_speed", [
    (store_script_param, ":eff_spd", 1),
    (try_begin),
      (le, ":eff_spd", 0),
      (stop_time, 1),
    (else_try),
      (stop_time, 0),
    (try_end),
    (assign, "$g_coop_effective_speed", ":eff_spd"),
  ]),

  # Anti-combat-log disconnect handler: if enemy lord/bandit is right next to party, delay despawn for 30s!
  ("coop_handle_player_disconnect", [
    (store_script_param, ":player_no", 1),
    (player_get_party_id, ":party_no", ":player_no"),
    (try_begin),
      (gt, ":party_no", 0),
      (party_is_active, ":party_no"),
      (party_get_battle_opponent, ":opponent", ":party_no"),
      (try_begin),
        (gt, ":opponent", 0),
        (party_set_slot, ":party_no", slot_party_coop_logout_grace, 30),
      (else_try),
        (disable_party, ":party_no"),
      (try_end),
    (try_end),
  ]),
]
