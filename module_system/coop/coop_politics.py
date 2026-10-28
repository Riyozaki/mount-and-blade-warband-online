# -*- coding: utf-8 -*-
# Calradia Online: Sovereign Player Factions (0..15) & Sovereign Player Kingdoms (0..15)

from header_factions import *

COOP_KINGDOM_COLORS = [
  0xFFAA3333, 0xFF3366AA, 0xFF33AA55, 0xFFDDAA22,
  0xFF8844AA, 0xFF22AAAA, 0xFFCC6622, 0xFF557799,
  0xFFAA4477, 0xFF66AA33, 0xFF4488CC, 0xFFBB8844,
  0xFF7755AA, 0xFF339988, 0xFFCC4444, 0xFF889944,
]

# Appended at the end of module_factions.py so ZERO Native faction indices move!
def get_coop_extra_factions():
  facs = []
  for i in range(16):
    facs.append((
      "coop_player_%d" % i,
      "Player Warband %d" % (i + 1),
      0, 0.9,
      [("outlaws", -0.5), ("deserters", -0.5)],
      [],
      COOP_KINGDOM_COLORS[i],
    ))
  for i in range(16):
    facs.append((
      "coop_kingdom_%d" % i,
      "Sovereign Player Kingdom %d" % (i + 1),
      0, 0.9,
      [("outlaws", -0.7), ("deserters", -0.6)],
      [],
      COOP_KINGDOM_COLORS[i],
    ))
  return facs
