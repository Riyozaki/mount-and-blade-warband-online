# -*- coding: utf-8 -*-
# Calradia Online: Protocol Channels, Bit-Widths, Slot Indices & Pool Bounds

coop_msg_reg = 0

# WSE2 Composite Message Channels (110..115) — matches docs/network-protocol.md
COOP_CHAN_AUTH_SESSION    = 110
COOP_CHAN_WORLD_TIME      = 111
COOP_CHAN_CHAR_PARTY      = 112
COOP_CHAN_ECONOMY_TOWNS   = 113
COOP_CHAN_BATTLE_BRIDGE   = 114
COOP_CHAN_QUESTS_POLITICS = 115

# Exact Bit-Width Contract (enforced by tests/test_module_build_and_lint.py!)
COOP_BITS_SUB_EVENT = 8
COOP_BITS_EPOCH     = 16
COOP_BITS_SLOT      = 8
COOP_BITS_BOOL      = 1
COOP_BITS_SPEED     = 4
COOP_BITS_TROOP     = 16
COOP_BITS_ITEM      = 16
COOP_BITS_MODIFIER  = 8
COOP_BITS_COUNT     = 16
COOP_BITS_PARTY     = 16
COOP_BITS_FACTION   = 8
COOP_BITS_GOLD      = 32
COOP_BITS_XP        = 32
COOP_BITS_PORT      = 16
COOP_BITS_BATTLE_ID = 16
COOP_BITS_QUEST_ID  = 16

# Channel 110 (AUTH_SESSION) sub-events
COOP_AUTH_SV_CHALLENGE   = 1
COOP_AUTH_CL_RESPONSE    = 2
COOP_AUTH_SV_WELCOME     = 3
COOP_AUTH_SV_REJECT      = 4

# Channel 111 (WORLD_TIME) sub-events
COOP_TIME_CL_SPEED_VOTE  = 1
COOP_TIME_SV_SPEED_STATE = 2
COOP_TIME_SV_THREAT_STOP = 3

# Channel 112 (CHAR_PARTY) sub-events
COOP_CHAR_CL_SPEND_STAT  = 1
COOP_CHAR_SV_HERO_SYNC   = 2
COOP_CHAR_CL_UPGRADE_TRP = 3
COOP_CHAR_SV_PARTY_SYNC  = 4

# Channel 113 (ECONOMY_TOWNS) sub-events
COOP_ECON_CL_MOVE_ITEM   = 1
COOP_ECON_SV_INV_SLOT    = 2
COOP_ECON_CL_TOWN_ACTION = 3
COOP_ECON_CL_P2P_OFFER   = 4
COOP_ECON_SV_P2P_STATE   = 5

# Channel 114 (BATTLE_BRIDGE) sub-events
COOP_BTL_CL_ENCOUNTER_OP = 1
COOP_BTL_SV_HANDOFF_3D   = 2
COOP_BTL_SV_RETURN_MAP   = 3
COOP_BTL_CL_JOIN_ONGOING = 4

# Channel 115 (QUESTS_POLITICS) sub-events
COOP_POL_CL_QUEST_OP     = 1
COOP_POL_SV_QUEST_SYNC   = 2
COOP_POL_CL_FEUDAL_OP    = 3
COOP_POL_SV_FEUDAL_SYNC  = 4

# Player & Party Co-op Slots (high non-overlapping indices >= 420)
slot_player_coop_authenticated = 420
slot_player_coop_hero_slot     = 421
slot_player_coop_speed_vote    = 422
slot_player_coop_brotherhood   = 423
slot_player_coop_battle_id     = 424
slot_player_coop_division_ofs  = 425

slot_party_coop_owner_slot     = 420
slot_party_coop_active_battle  = 421
slot_party_coop_logout_grace   = 422
slot_party_coop_siege_ready    = 423

COOP_MAX_ONLINE_PLAYERS        = 16
COOP_MAX_PERSISTENT_HEROES     = 32
COOP_MAX_PLAYER_KINGDOMS       = 16
