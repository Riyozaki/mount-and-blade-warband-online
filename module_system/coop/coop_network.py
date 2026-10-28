# -*- coding: utf-8 -*-
# Calradia Online: Bit-Exact WSE2 Composite Packet Senders & Dispatcher

from header_common import *
from header_operations import *
from module_constants import *
from coop.coop_constants import *

coop_network_scripts = [
  # Server -> Client: Send cryptographic challenge nonce on Channel 110
  ("coop_sv_send_auth_challenge", [
    (store_script_param, ":player_no", 1),
    (lua_push_int, ":player_no"),
    (lua_call, "@coop_issue_challenge", 1),
    (lua_pop, 1),

    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_AUTH_SV_CHALLENGE, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_string, coop_msg_reg, s0),
    (multiplayer_send_composite_message_to_player, ":player_no", COOP_CHAN_AUTH_SESSION, coop_msg_reg),
  ]),

  # Client -> Server: Respond to challenge with UID, Nickname, Public Token & HMAC
  ("coop_cl_send_auth_response", [
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_AUTH_CL_RESPONSE, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_string, coop_msg_reg, s0), # player_uid
    (multiplayer_message_put_string, coop_msg_reg, s1), # nickname
    (multiplayer_message_put_string, coop_msg_reg, s2), # public_token
    (multiplayer_message_put_string, coop_msg_reg, s3), # hmac_hex
    (multiplayer_send_composite_message_to_server, COOP_CHAN_AUTH_SESSION, coop_msg_reg),
  ]),

  # Server -> Client: Send Welcome + Hero Slot + Reconnect Flag
  ("coop_sv_send_auth_welcome", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":hero_slot", 2),
    (store_script_param, ":is_reconnect", 3),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_AUTH_SV_WELCOME, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_int, coop_msg_reg, ":hero_slot", COOP_BITS_SLOT),
    (multiplayer_message_put_int, coop_msg_reg, ":is_reconnect", COOP_BITS_BOOL),
    (multiplayer_send_composite_message_to_player, ":player_no", COOP_CHAN_AUTH_SESSION, coop_msg_reg),
  ]),

  # Client -> Server: Vote for Consensus World Map Speed (0=Pause, 1=1x, 3=3x, 5=5x)
  ("coop_cl_send_speed_vote", [
    (store_script_param, ":speed_val", 1),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_TIME_CL_SPEED_VOTE, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_int, coop_msg_reg, ":speed_val", COOP_BITS_SPEED),
    (multiplayer_send_composite_message_to_server, COOP_CHAN_WORLD_TIME, coop_msg_reg),
  ]),

  # Server -> All Clients: Broadcast Effective Consensus Map Speed
  ("coop_sv_broadcast_speed_state", [
    (store_script_param, ":eff_speed", 1),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_TIME_SV_SPEED_STATE, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_int, coop_msg_reg, ":eff_speed", COOP_BITS_SPEED),
    (try_for_players, ":cur_player", 1),
      (multiplayer_send_composite_message_to_player, ":cur_player", COOP_CHAN_WORLD_TIME, coop_msg_reg),
    (try_end),
  ]),

  # Server -> Client: Handoff to 3D Tactical Battle Server via WSE2 multiplayer_connect_to_server
  ("coop_sv_send_battle_handoff", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":battle_id", 2),
    (store_script_param, ":battle_port", 3),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_BTL_SV_HANDOFF_3D, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_int, coop_msg_reg, ":battle_id", COOP_BITS_BATTLE_ID),
    (multiplayer_message_put_int, coop_msg_reg, ":battle_port", COOP_BITS_PORT),
    (multiplayer_message_put_string, coop_msg_reg, s0), # address:port or mux endpoint
    (multiplayer_message_put_string, coop_msg_reg, s1), # one-time battle session token
    (multiplayer_send_composite_message_to_player, ":player_no", COOP_CHAN_BATTLE_BRIDGE, coop_msg_reg),
  ]),

  # Server -> Client: Return from 3D Battle Server back to Strategic Campaign Map
  ("coop_sv_send_return_to_campaign", [
    (store_script_param, ":player_no", 1),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_BTL_SV_RETURN_MAP, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_string, coop_msg_reg, s0), # campaign address:port
    (multiplayer_message_put_string, coop_msg_reg, s1), # session reconnect token
    (multiplayer_send_composite_message_to_player, ":player_no", COOP_CHAN_BATTLE_BRIDGE, coop_msg_reg),
  ]),

  # Client -> Server: Inventory Move/Equip Request
  ("coop_cl_send_move_item", [
    (store_script_param, ":from_slot", 1),
    (store_script_param, ":to_slot", 2),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_ECON_CL_MOVE_ITEM, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_int, coop_msg_reg, ":from_slot", COOP_BITS_SLOT),
    (multiplayer_message_put_int, coop_msg_reg, ":to_slot", COOP_BITS_SLOT),
    (multiplayer_send_composite_message_to_server, COOP_CHAN_ECONOMY_TOWNS, coop_msg_reg),
  ]),

  # Server -> Client: Authoritative Single-Slot Inventory Sync
  ("coop_sv_send_inv_slot", [
    (store_script_param, ":player_no", 1),
    (store_script_param, ":slot_no", 2),
    (store_script_param, ":item_id", 3),
    (store_script_param, ":imod", 4),
    (multiplayer_message_init, coop_msg_reg),
    (multiplayer_message_put_int, coop_msg_reg, COOP_ECON_SV_INV_SLOT, COOP_BITS_SUB_EVENT),
    (multiplayer_message_put_int, coop_msg_reg, "$g_coop_net_epoch", COOP_BITS_EPOCH),
    (multiplayer_message_put_int, coop_msg_reg, ":slot_no", COOP_BITS_SLOT),
    (multiplayer_message_put_int, coop_msg_reg, ":item_id", COOP_BITS_ITEM),
    (multiplayer_message_put_int, coop_msg_reg, ":imod", COOP_BITS_MODIFIER),
    (multiplayer_send_composite_message_to_player, ":player_no", COOP_CHAN_ECONOMY_TOWNS, coop_msg_reg),
  ]),

  # Master WSE2 Composite Packet Dispatcher (called from script_wse_multiplayer_message_received)
  ("coop_receive_composite_message", [
    (store_script_param, ":sender_no", 1),
    (store_script_param, ":event_no", 2),

    (try_begin),
      (is_between, ":event_no", COOP_CHAN_AUTH_SESSION, COOP_CHAN_QUESTS_POLITICS + 1),
      (multiplayer_cur_message_get_int, ":sub_event", COOP_BITS_SUB_EVENT),
      (multiplayer_cur_message_get_int, ":pkt_epoch", COOP_BITS_EPOCH),

      (try_begin),
        (eq, ":event_no", COOP_CHAN_AUTH_SESSION),
        (try_begin),
          (eq, ":sub_event", COOP_AUTH_SV_CHALLENGE),
          (multiplayer_cur_message_get_string, s0),
          (assign, "$g_coop_net_epoch", ":pkt_epoch"),
        (else_try),
          (eq, ":sub_event", COOP_AUTH_CL_RESPONSE),
          (multiplayer_is_server),
          (multiplayer_cur_message_get_string, s0),
          (multiplayer_cur_message_get_string, s1),
          (multiplayer_cur_message_get_string, s2),
          (multiplayer_cur_message_get_string, s3),
          (lua_push_int, ":sender_no"),
          (lua_call, "@coop_verify_login", 1),
          (lua_to_int, ":auth_ok", 1),
          (lua_pop, 1),
          (try_begin),
            (eq, ":auth_ok", 1),
            (assign, ":hero_slot", reg0),
            (assign, ":is_reconn", reg1),
            (player_set_slot, ":sender_no", slot_player_coop_authenticated, 1),
            (player_set_slot, ":sender_no", slot_player_coop_hero_slot, ":hero_slot"),
            (call_script, "script_coop_bind_player_to_hero_party", ":sender_no", ":hero_slot"),
            (call_script, "script_coop_sv_send_auth_welcome", ":sender_no", ":hero_slot", ":is_reconn"),
          (try_end),
        (else_try),
          (eq, ":sub_event", COOP_AUTH_SV_WELCOME),
          (multiplayer_cur_message_get_int, ":my_hero_slot", COOP_BITS_SLOT),
          (multiplayer_cur_message_get_int, ":was_reconn", COOP_BITS_BOOL),
          (assign, "$g_coop_my_hero_slot", ":my_hero_slot"),
          (assign, "$g_coop_is_authenticated", 1),
        (try_end),

      (else_try),
        (eq, ":event_no", COOP_CHAN_WORLD_TIME),
        (try_begin),
          (eq, ":sub_event", COOP_TIME_CL_SPEED_VOTE),
          (multiplayer_is_server),
          (multiplayer_cur_message_get_int, ":vote_spd", COOP_BITS_SPEED),
          (player_set_slot, ":sender_no", slot_player_coop_speed_vote, ":vote_spd"),
          (lua_push_int, ":sender_no"),
          (lua_push_int, ":vote_spd"),
          (lua_call, "@coop_set_speed_vote", 2),
          (lua_to_int, ":vote_ok", 1),
          (lua_pop, 1),
          (try_begin),
            (eq, ":vote_ok", 1),
            (assign, ":eff_spd", reg0),
            (call_script, "script_coop_apply_campaign_speed", ":eff_spd"),
            (call_script, "script_coop_sv_broadcast_speed_state", ":eff_spd"),
          (try_end),
        (else_try),
          (eq, ":sub_event", COOP_TIME_SV_SPEED_STATE),
          (multiplayer_cur_message_get_int, ":eff_spd", COOP_BITS_SPEED),
          (assign, "$g_coop_effective_speed", ":eff_spd"),
        (try_end),

      (else_try),
        (eq, ":event_no", COOP_CHAN_ECONOMY_TOWNS),
        (try_begin),
          (eq, ":sub_event", COOP_ECON_CL_MOVE_ITEM),
          (multiplayer_is_server),
          (multiplayer_cur_message_get_int, ":from_slot", COOP_BITS_SLOT),
          (multiplayer_cur_message_get_int, ":to_slot", COOP_BITS_SLOT),
          (call_script, "script_coop_sv_handle_move_item", ":sender_no", ":from_slot", ":to_slot"),
        (else_try),
          (eq, ":sub_event", COOP_ECON_SV_INV_SLOT),
          (multiplayer_cur_message_get_int, ":slot_no", COOP_BITS_SLOT),
          (multiplayer_cur_message_get_int, ":item_id", COOP_BITS_ITEM),
          (multiplayer_cur_message_get_int, ":imod", COOP_BITS_MODIFIER),
          (assign, "$g_coop_last_synced_slot", ":slot_no"),
          (assign, "$g_coop_last_synced_item", ":item_id"),
          (assign, "$g_coop_last_synced_imod", ":imod"),
        (try_end),

      (else_try),
        (eq, ":event_no", COOP_CHAN_BATTLE_BRIDGE),
        (try_begin),
          (eq, ":sub_event", COOP_BTL_SV_HANDOFF_3D),
          (neg|multiplayer_is_server),
          (multiplayer_cur_message_get_int, ":btl_id", COOP_BITS_BATTLE_ID),
          (multiplayer_cur_message_get_int, ":btl_port", COOP_BITS_PORT),
          (multiplayer_cur_message_get_string, s0),
          (multiplayer_cur_message_get_string, s1),
          (assign, "$g_coop_active_battle_id", ":btl_id"),
          (assign, "$g_coop_active_battle_port", ":btl_port"),
          (multiplayer_connect_to_server, s0, s1, 0), # Seamless WSE2 switch to Tactical 3D Battle Server!
        (else_try),
          (eq, ":sub_event", COOP_BTL_SV_RETURN_MAP),
          (neg|multiplayer_is_server),
          (multiplayer_cur_message_get_string, s0),
          (multiplayer_cur_message_get_string, s1),
          (multiplayer_connect_to_server, s0, s1, 1), # Seamless WSE2 return to Strategic Campaign Server!
        (try_end),
      (try_end),
    (try_end),
  ]),
]
