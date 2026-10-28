#!/usr/bin/env python3
"""Generate `pelican-on-bicycle.svg` — a pelican riding a bicycle.

Pure-Python generator (no deps) so the artwork stays easy to tweak:
all the important coordinates live in the GEOMETRY block below.

Usage:  python3 generate_svg.py
"""

import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pelican-on-bicycle.svg")

# ---------------------------------------------------------------- GEOMETRY
W, H = 900, 620
HORIZON = 470          # where grass starts
ROAD_TOP = 500         # where asphalt starts

REAR_HUB = (250, 430)
FRONT_HUB = (620, 430)
TIRE_R = 95            # outer tyre radius -> touches road at y = 525
RIM_R = 80
HUB_R = 10
SPOKES = 18

BB = (430, 430)        # bottom bracket
PEDAL_NEAR = (BB[0] + 36, BB[1] + 20)   # forward / down pedal
PEDAL_FAR = (BB[0] - 36, BB[1] - 20)    # back / up pedal

SEAT_TOP = (388, 312)  # seat cluster (saddle sits just above)
HEAD_TOP = (574, 288)
HEAD_BOT = (592, 342)


def spokes(cx, cy):
    """Straight laced spokes from hub to rim."""
    out = []
    for i in range(SPOKES):
        a = math.tau * i / SPOKES
        x1, y1 = cx + HUB_R * math.cos(a), cy + HUB_R * math.sin(a)
        x2, y2 = cx + (RIM_R - 3) * math.cos(a), cy + (RIM_R - 3) * math.sin(a)
        out.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}"/>')
    return "\n      ".join(out)


def wheel(cx, cy):
    return f'''
    <g class="wheel">
      <circle cx="{cx}" cy="{cy}" r="{TIRE_R}" fill="#2c3038"/>
      <circle cx="{cx}" cy="{cy}" r="{TIRE_R - 13}" fill="#e9edf1"/>
      <circle cx="{cx}" cy="{cy}" r="{RIM_R}" fill="#c3ccd4"/>
      <circle cx="{cx}" cy="{cy}" r="{RIM_R - 7}" fill="#f2f6f9"/>
      <g stroke="#9aa6b0" stroke-width="2.4" stroke-linecap="round">
      {spokes(cx, cy)}
      </g>
      <circle cx="{cx}" cy="{cy}" r="{HUB_R}" fill="#6f7b86"/>
      <circle cx="{cx}" cy="{cy}" r="4" fill="#39414a"/>
    </g>'''


def tube(x1, y1, x2, y2, w=13):
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
            f'stroke="url(#frame)" stroke-width="{w}" stroke-linecap="round"/>')


SVG = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}"
     role="img" aria-label="Pelican riding a bicycle">
  <title>Pelican on a bicycle</title>

  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#eaf7ff"/>
      <stop offset="1" stop-color="#b6dff5"/>
    </linearGradient>
    <linearGradient id="grass" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8cc63f"/>
      <stop offset="1" stop-color="#6aa632"/>
    </linearGradient>
    <linearGradient id="road" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#9fa6ad"/>
      <stop offset="1" stop-color="#c3c8cd"/>
    </linearGradient>
    <linearGradient id="frame" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ef5d4c"/>
      <stop offset="1" stop-color="#c62f27"/>
    </linearGradient>
    <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="0.62" stop-color="#f6f4ef"/>
      <stop offset="1" stop-color="#dcdcd4"/>
    </linearGradient>
    <linearGradient id="wing" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#e4e9ee"/>
      <stop offset="1" stop-color="#b9c4ce"/>
    </linearGradient>
    <linearGradient id="bill" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#f9b233"/>
      <stop offset="1" stop-color="#f4891f"/>
    </linearGradient>
    <linearGradient id="pouch" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fbd38a"/>
      <stop offset="1" stop-color="#f2a341"/>
    </linearGradient>
    <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#fff3c4"/>
      <stop offset="0.55" stop-color="#ffd166"/>
      <stop offset="1" stop-color="#ffd166" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="helmet" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#4aa3e8"/>
      <stop offset="1" stop-color="#1f6fb2"/>
    </linearGradient>
  </defs>

  <!-- ============================================================ SKY -->
  <rect width="{W}" height="{ROAD_TOP}" fill="url(#sky)"/>
  <circle cx="780" cy="96" r="86" fill="url(#sun)"/>
  <circle cx="780" cy="96" r="40" fill="#ffe08a"/>

  <g fill="#ffffff" opacity="0.9">
    <ellipse cx="140" cy="112" rx="66" ry="26"/>
    <ellipse cx="188" cy="98" rx="44" ry="30"/>
    <ellipse cx="96" cy="102" rx="38" ry="22"/>
    <ellipse cx="470" cy="66" rx="54" ry="20"/>
    <ellipse cx="510" cy="56" rx="36" ry="24"/>
    <ellipse cx="620" cy="176" rx="42" ry="15" opacity="0.65"/>
  </g>

  <!-- distant hills -->
  <path d="M0,{HORIZON} L0,{HORIZON - 52} Q120,{HORIZON - 118} 250,{HORIZON - 46}
           Q350,{HORIZON - 100} 470,{HORIZON - 40} Q600,{HORIZON - 96} 720,{HORIZON - 44}
           Q810,{HORIZON - 84} 900,{HORIZON - 38} L900,{HORIZON} Z"
        fill="#a8d8b9" opacity="0.85"/>

  <!-- ========================================================== GROUND -->
  <rect y="{HORIZON}" width="{W}" height="{ROAD_TOP - HORIZON}" fill="url(#grass)"/>
  <rect y="{ROAD_TOP}" width="{W}" height="{H - ROAD_TOP}" fill="url(#road)"/>
  <rect y="{ROAD_TOP}" width="{W}" height="7" fill="#7f868d" opacity="0.55"/>
  <g stroke="#f4f6f7" stroke-width="9" stroke-linecap="round" opacity="0.85">
    <line x1="40" y1="586" x2="140" y2="586"/>
    <line x1="230" y1="586" x2="330" y2="586"/>
    <line x1="420" y1="586" x2="520" y2="586"/>
    <line x1="610" y1="586" x2="710" y2="586"/>
    <line x1="800" y1="586" x2="880" y2="586"/>
  </g>

  <!-- speed lines -->
  <g stroke="#ffffff" stroke-linecap="round" opacity="0.75">
    <line x1="52" y1="248" x2="176" y2="248" stroke-width="9"/>
    <line x1="20" y1="286" x2="128" y2="286" stroke-width="7"/>
    <line x1="70" y1="324" x2="158" y2="324" stroke-width="6"/>
  </g>

  <!-- shadow -->
  <ellipse cx="440" cy="529" rx="268" ry="19" fill="#3f4a52" opacity="0.28"/>

  <!-- ========================================================= BICYCLE -->
  {wheel(*REAR_HUB)}
  {wheel(*FRONT_HUB)}

  <!-- far leg: behind the frame -->
  <g fill="none" stroke="#d9821f" stroke-linecap="round">
    <path d="M392,266 Q376,320 380,368" stroke-width="14"/>
    <path d="M380,368 L392,398" stroke-width="11"/>
  </g>

  <g class="frame">
    {tube(*BB, *REAR_HUB, 11)}                                   <!-- chainstay -->
    {tube(*SEAT_TOP, *REAR_HUB, 10)}                             <!-- seat stay -->
    {tube(*BB, *SEAT_TOP, 14)}                                   <!-- seat tube -->
    {tube(*SEAT_TOP, *HEAD_TOP, 13)}                             <!-- top tube -->
    {tube(*BB, *HEAD_BOT, 15)}                                   <!-- down tube -->
    {tube(*HEAD_TOP, *HEAD_BOT, 17)}                             <!-- head tube -->
    {tube(*HEAD_BOT, *FRONT_HUB, 11)}                            <!-- fork -->
  </g>

  <!-- drivetrain -->
  <g fill="none" stroke="#4a5158" stroke-width="6">
    <path d="M{BB[0]},{BB[1] - 28} L{REAR_HUB[0]},{REAR_HUB[1] - 14}"/>
    <path d="M{BB[0]},{BB[1] + 28} L{REAR_HUB[0]},{REAR_HUB[1] + 14}"/>
  </g>
  <circle cx="{REAR_HUB[0]}" cy="{REAR_HUB[1]}" r="15" fill="#5b636b"/>
  <circle cx="{BB[0]}" cy="{BB[1]}" r="29" fill="#5b636b"/>
  <circle cx="{BB[0]}" cy="{BB[1]}" r="20" fill="#8b949c"/>
  <circle cx="{BB[0]}" cy="{BB[1]}" r="7" fill="#39414a"/>
  <g stroke="#39414a" stroke-width="10" stroke-linecap="round">
    <line x1="{PEDAL_FAR[0]}" y1="{PEDAL_FAR[1]}" x2="{BB[0]}" y2="{BB[1]}"/>
  </g>
  <g stroke="#575f67" stroke-width="11" stroke-linecap="round">
    <line x1="{BB[0]}" y1="{BB[1]}" x2="{PEDAL_NEAR[0]}" y2="{PEDAL_NEAR[1]}"/>
  </g>
  <g fill="#2f343a">
    <rect x="{PEDAL_FAR[0] - 20}" y="{PEDAL_FAR[1] - 8}" width="40" height="15" rx="6"/>
    <rect x="{PEDAL_NEAR[0] - 21}" y="{PEDAL_NEAR[1] - 8}" width="42" height="16" rx="6"/>
  </g>
  <path d="M374,396 L414,394 L402,406 L372,406 Z" fill="#d9821f"/>   <!-- far foot on pedal -->

  <!-- ========================================================= PELICAN -->
  <!-- tail feathers -->
  <path d="M300,226 Q232,208 186,230 Q236,232 258,248 Q214,248 190,266
           Q258,266 306,256 Z" fill="#c9d1d9"/>
  <path d="M300,226 Q240,214 198,232 Q244,234 266,246" fill="none" stroke="#aeb8c2"
        stroke-width="3"/>

  <!-- saddle: tucked under the bird, only nose and tail peeking out -->
  <g stroke="#39414a" stroke-width="9" stroke-linecap="round">
    <line x1="384" y1="300" x2="388" y2="316"/>
  </g>
  <path d="M344,292 Q346,285 360,285 L418,289 Q432,291 433,296
           Q412,303 380,303 Q352,302 344,292 Z" fill="#34393f"/>

  <!-- body -->
  <ellipse cx="372" cy="222" rx="103" ry="67" fill="url(#body)"
           transform="rotate(-8 372 222)"/>
  <path d="M296,252 Q372,292 448,248 Q430,282 372,286 Q316,284 296,252 Z"
        fill="#e2e2da" opacity="0.9"/>

  <!-- handlebar + bell -->
  <g stroke="#39414a" stroke-width="10" stroke-linecap="round" fill="none">
    <path d="M{HEAD_TOP[0]},{HEAD_TOP[1]} L564,264"/>
    <path d="M564,264 Q604,256 630,272"/>
  </g>
  <circle cx="630" cy="272" r="9" fill="#2b2f34"/>
  <circle cx="612" cy="254" r="8" fill="#f2c14e"/>
  <circle cx="610" cy="252" r="3" fill="#ffe9ad"/>

  <!-- neck -->
  <path d="M436,202 C466,176 478,162 500,146" fill="none" stroke="#f6f4ef"
        stroke-width="48" stroke-linecap="round"/>

  <!-- head -->
  <ellipse cx="524" cy="132" rx="43" ry="34" fill="#fbfaf7" transform="rotate(-12 524 132)"/>

  <!-- bill + gular pouch -->
  <path d="M552,134 C604,142 654,152 700,158 C662,202 592,208 554,174 Z"
        fill="url(#pouch)"/>
  <path d="M550,112 C612,116 664,130 704,146 Q712,152 702,157
           C656,144 600,135 550,134 Z" fill="url(#bill)"/>
  <path d="M704,146 Q716,151 704,158" fill="none" stroke="#d9761a" stroke-width="4"
        stroke-linecap="round"/>
  <g stroke="#e0912f" stroke-width="2.6" opacity="0.7" fill="none">
    <path d="M572,144 Q592,170 588,192"/>
    <path d="M608,150 Q626,174 622,194"/>
    <path d="M646,156 Q660,174 656,187"/>
  </g>

  <!-- eye -->
  <circle cx="536" cy="118" r="9.5" fill="#2b2b33"/>
  <circle cx="539" cy="115" r="3.2" fill="#ffffff"/>
  <path d="M520,102 Q538,96 554,104" fill="none" stroke="#c9c6bd" stroke-width="4"
        stroke-linecap="round"/>

  <!-- helmet -->
  <path d="M486,114 C490,74 556,68 572,106 Q540,90 486,114 Z" fill="url(#helmet)"/>
  <path d="M566,102 L606,114 L566,118 Z" fill="#1f6fb2"/>
  <g fill="#16548a" opacity="0.85">
    <ellipse cx="508" cy="99" rx="3.4" ry="7" transform="rotate(-24 508 99)"/>
    <ellipse cx="528" cy="92" rx="3.4" ry="7" transform="rotate(-14 528 92)"/>
    <ellipse cx="548" cy="95" rx="3.4" ry="7" transform="rotate(-6 548 95)"/>
  </g>

  <!-- near wing: folded along the body, reaching to the handlebar grip -->
  <path d="M302,230 C348,204 412,198 452,208 C508,220 556,242 598,260
           C604,272 594,284 578,278 C520,258 470,246 438,246
           C424,264 386,272 348,266 C314,260 296,248 302,230 Z"
        fill="url(#wing)"/>
  <g fill="none" stroke="#9fadba" stroke-width="3.4" stroke-linecap="round" opacity="0.85">
    <path d="M330,228 C360,244 396,250 430,244"/>
    <path d="M322,246 C352,262 390,268 420,262"/>
    <path d="M470,232 C512,244 552,258 584,270"/>
    <path d="M462,246 C502,256 540,266 566,276"/>
  </g>
  <path d="M578,278 C596,280 606,266 598,256" fill="none" stroke="#9fadba"
        stroke-width="4" stroke-linecap="round"/>

  <!-- near leg -->
  <g fill="none" stroke="#f09128" stroke-linecap="round">
    <path d="M428,264 Q466,314 468,362" stroke-width="17"/>
    <path d="M468,362 L{PEDAL_NEAR[0] + 2},{PEDAL_NEAR[1] - 16}" stroke-width="13"/>
  </g>
  <path d="M{PEDAL_NEAR[0] - 20},{PEDAL_NEAR[1] - 14} L{PEDAL_NEAR[0] + 22},{PEDAL_NEAR[1] - 16}
           L{PEDAL_NEAR[0] + 10},{PEDAL_NEAR[1] - 2} L{PEDAL_NEAR[0] - 22},{PEDAL_NEAR[1] - 2} Z"
        fill="#f09128"/>
  <g stroke="#d9821f" stroke-width="2.6" opacity="0.9">
    <line x1="{PEDAL_NEAR[0] - 8}" y1="{PEDAL_NEAR[1] - 14}" x2="{PEDAL_NEAR[0] - 10}" y2="{PEDAL_NEAR[1] - 3}"/>
    <line x1="{PEDAL_NEAR[0] + 6}" y1="{PEDAL_NEAR[1] - 15}" x2="{PEDAL_NEAR[0] + 4}" y2="{PEDAL_NEAR[1] - 3}"/>
  </g>

  <!-- ================================================ FOREGROUND GRASS -->
  <g stroke="#5f9c2c" stroke-width="5" stroke-linecap="round" fill="none">
    <path d="M60,500 q6,-26 16,-32"/>
    <path d="M76,500 q-2,-22 -12,-30"/>
    <path d="M760,500 q8,-28 20,-34"/>
    <path d="M778,500 q-2,-20 -12,-28"/>
    <path d="M300,498 q6,-20 14,-26"/>
  </g>
</svg>
'''

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write(SVG)

print(f"wrote {OUT} ({len(SVG):,} bytes)")
