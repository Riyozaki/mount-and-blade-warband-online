# -*- coding: utf-8 -*-
# Calradia Online: Instanced Quests & Co-op Brotherhood Quest Sharing Scripts

from header_common import *
from header_operations import *
from module_constants import *
from coop.coop_constants import *

coop_quest_scripts = [
  # Hourly world tick hook bridged directly into WSE2 LuaJIT campaign engine (`@coop_tick_hour`)
  ("coop_world_hourly_tick", [
    (try_begin),
      (multiplayer_is_server),
      (lua_call, "@coop_tick_hour", 0),
      (lua_to_int, ":world_active", 1),
      (lua_pop, 1),
      (try_begin),
        (eq, ":world_active", 1),
        (assign, ":eff_spd", reg0),
        (call_script, "script_coop_apply_campaign_speed", ":eff_spd"),
      (try_end),
    (try_end),
  ]),
]
