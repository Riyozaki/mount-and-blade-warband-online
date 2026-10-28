# -*- coding: utf-8 -*-
# Calradia Online: Server-Authoritative Inventory & Two-Phase P2P Trade Scripts

from header_common import *
from header_operations import *
from module_constants import *
from coop.coop_constants import *

coop_inventory_scripts = [
  # Server-side validation of inventory equip/move request on player's persistent hero troop
  ("coop_sv_handle_move_item", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":from_slot", 2),
    (store_script_param, ":to_slot", 3),

    (player_get_slot, ":is_auth", ":player_no", slot_player_coop_authenticated),
    (try_begin),
      (eq, ":is_auth", 1),
      (player_get_troop_id, ":troop_no", ":player_no"),
      (ge, ":troop_no", 0),
      (is_between, ":from_slot", 0, 96),
      (is_between, ":to_slot", 0, 96),
      (neq, ":from_slot", ":to_slot"),

      (troop_get_inventory_slot, ":itm_a", ":troop_no", ":from_slot"),
      (troop_get_inventory_slot_modifier, ":mod_a", ":troop_no", ":from_slot"),
      (troop_get_inventory_slot, ":itm_b", ":troop_no", ":to_slot"),
      (troop_get_inventory_slot_modifier, ":mod_b", ":troop_no", ":to_slot"),

      (troop_set_inventory_slot, ":troop_no", ":to_slot", ":itm_a"),
      (troop_set_inventory_slot_modifier, ":troop_no", ":to_slot", ":mod_a"),
      (troop_set_inventory_slot, ":troop_no", ":from_slot", ":itm_b"),
      (troop_set_inventory_slot_modifier, ":troop_no", ":from_slot", ":mod_b"),

      (val_max, ":itm_a", 0),
      (val_max, ":itm_b", 0),
      (val_max, ":mod_a", 0),
      (val_max, ":mod_b", 0),
      (call_script, "script_coop_sv_send_inv_slot", ":player_no", ":to_slot", ":itm_a", ":mod_a"),
      (call_script, "script_coop_sv_send_inv_slot", ":player_no", ":from_slot", ":itm_b", ":mod_b"),
    (try_end),
  ]),
]
