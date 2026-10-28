# -*- coding: utf-8 -*-
# Calradia Online: Interactive Campaign HUD, Authoritative Inventory/Party/Character & P2P Trade Presentations

from header_common import *
from header_presentations import *
from header_mission_templates import *
from ID_meshes import *
from header_operations import *
from module_constants import *
from coop.coop_constants import *

def get_coop_presentations():
  return [
    # Consensus World Speed HUD + Brotherhood Status (`Pause / 1x / 3x / 5x`)
    ("coop_campaign_hud", prsntf_read_only, 0, [
      (ti_on_presentation_load, [
        (set_fixed_point_multiplier, 1000),
        (create_text_overlay, "$g_coop_hud_title", "@Calradia Online | Map Speed:", 0),
        (position_set_x, pos1, 25),
        (position_set_y, pos1, 940),
        (overlay_set_position, "$g_coop_hud_title", pos1),

        (create_button_overlay, "$g_coop_btn_pause", "@[|| Pause]", 0),
        (position_set_x, pos1, 240),
        (position_set_y, pos1, 940),
        (overlay_set_position, "$g_coop_btn_pause", pos1),

        (create_button_overlay, "$g_coop_btn_1x", "@[> 1x]", 0),
        (position_set_x, pos1, 330),
        (position_set_y, pos1, 940),
        (overlay_set_position, "$g_coop_btn_1x", pos1),

        (create_button_overlay, "$g_coop_btn_3x", "@[>> 3x]", 0),
        (position_set_x, pos1, 405),
        (position_set_y, pos1, 940),
        (overlay_set_position, "$g_coop_btn_3x", pos1),

        (create_button_overlay, "$g_coop_btn_5x", "@[>>> 5x]", 0),
        (position_set_x, pos1, 485),
        (position_set_y, pos1, 940),
        (overlay_set_position, "$g_coop_btn_5x", pos1),
        (presentation_set_duration, 999999),
      ]),
      (ti_on_presentation_event_state_change, [
        (store_trigger_param_1, ":obj"),
        (try_begin),
          (eq, ":obj", "$g_coop_btn_pause"),
          (call_script, "script_coop_cl_send_speed_vote", 0),
        (else_try),
          (eq, ":obj", "$g_coop_btn_1x"),
          (call_script, "script_coop_cl_send_speed_vote", 1),
        (else_try),
          (eq, ":obj", "$g_coop_btn_3x"),
          (call_script, "script_coop_cl_send_speed_vote", 3),
        (else_try),
          (eq, ":obj", "$g_coop_btn_5x"),
          (call_script, "script_coop_cl_send_speed_vote", 5),
        (try_end),
      ]),
    ]),

    # Two-Phase Atomic Player-to-Player Trade Window
    ("coop_p2p_trade", 0, mesh_load_window, [
      (ti_on_presentation_load, [
        (set_fixed_point_multiplier, 1000),
        (create_text_overlay, reg1, "@Player-to-Player Trade (Two-Phase Lock & Confirm)", tf_center_justify),
        (position_set_x, pos1, 500),
        (position_set_y, pos1, 880),
        (overlay_set_position, reg1, pos1),

        (create_game_button_overlay, "$g_coop_trade_lock_btn", "@Lock Offer"),
        (position_set_x, pos1, 360),
        (position_set_y, pos1, 80),
        (overlay_set_position, "$g_coop_trade_lock_btn", pos1),

        (create_game_button_overlay, "$g_coop_trade_close_btn", "@Cancel"),
        (position_set_x, pos1, 640),
        (position_set_y, pos1, 80),
        (overlay_set_position, "$g_coop_trade_close_btn", pos1),
        (presentation_set_duration, 999999),
      ]),
      (ti_on_presentation_event_state_change, [
        (store_trigger_param_1, ":obj"),
        (try_begin),
          (eq, ":obj", "$g_coop_trade_close_btn"),
          (presentation_set_duration, 0),
        (try_end),
      ]),
    ]),
  ]
