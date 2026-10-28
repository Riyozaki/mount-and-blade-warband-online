# -*- coding: utf-8 -*-
# Calradia Online: Persistent Hero Profiles (0..31) & Specialist Mercenary Captains

from header_common import *
from header_items import *
from header_troops import *
from header_skills import *
from ID_factions import *
from ID_items import *
from ID_scenes import *

no_scene = 0
reserved = 0
knows_common = knows_riding_1 | knows_trade_2 | knows_inventory_management_2 | knows_prisoner_management_1 | knows_leadership_1


def _wp(x):
  return wp_one_handed(x) | wp_two_handed(x) | wp_polearm(x) | wp_archery(x) | wp_crossbow(x) | wp_throwing(x)


# Added at the end of module_troops.py (after hardwired & Native troops so ZERO Native IDs shift!)
def get_coop_extra_troops():
  extra = []
  for idx in range(32):
    extra.append([
      "coop_hero_%d" % idx,
      "Calradian Adventurer %d" % (idx + 1),
      "Calradian Adventurers",
      tf_hero | tf_unmoveable_in_party_window,
      no_scene,
      reserved,
      fac_commoners,
      [itm_hunter, itm_ragged_outfit, itm_wrapping_boots, itm_sword_medieval_a, itm_smoked_fish],
      str_7 | agi_7 | int_6 | cha_6 | level(1),
      _wp(65),
      knows_common | knows_riding_2 | knows_leadership_1 | knows_inventory_management_2,
      0x000000018000000136db6db6db6db6db00000000001db6db0000000000000000,
    ])

  officers = [
    ("coop_officer_surgeon",       "Master Field Surgeon",  knows_common | knows_surgery_4 | knows_wound_treatment_4 | knows_first_aid_4),
    ("coop_officer_engineer",      "Royal Siege Engineer",  knows_common | knows_engineer_5 | knows_tactics_3),
    ("coop_officer_scout",         "Border Pathfinder",     knows_common | knows_pathfinding_4 | knows_spotting_4 | knows_tracking_4),
    ("coop_officer_quartermaster", "Guild Quartermaster",   knows_common | knows_trade_4 | knows_trainer_3 | knows_looting_2),
  ]
  for tid, label, sk in officers:
    extra.append([
      tid, label, label,
      tf_hero,
      no_scene,
      reserved,
      fac_commoners,
      [itm_courser, itm_leather_jerkin, itm_nomad_boots, itm_sword_medieval_b],
      str_9 | agi_9 | int_12 | cha_9 | level(8),
      _wp(95),
      sk,
      0x00000004bf00210636db6db6db6db6db00000000001db6db0000000000000000,
    ])
  return extra
