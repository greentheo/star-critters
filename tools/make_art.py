#!/usr/bin/env python3
"""Writes all Star Critters SVG art into assets/art/. Flat, bright, thick-outlined.
Ships are drawn white so the game can tint them with each player's colour."""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "art")
os.makedirs(OUT, exist_ok=True)
INK = "#2a2350"


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>\n'


def save(name, content):
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(content)


def eye(cx, cy, r, look=(4, 3)):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#fff" stroke="{INK}" stroke-width="6"/>'
            f'<circle cx="{cx+look[0]}" cy="{cy+look[1]}" r="{r*0.5}" fill="{INK}"/>'
            f'<circle cx="{cx+look[0]+r*0.2}" cy="{cy+look[1]-r*0.25}" r="{r*0.18}" fill="#fff"/>')


def cheeks(y, x1, x2):
    return (f'<ellipse cx="{x1}" cy="{y}" rx="12" ry="8" fill="#ff7fae" opacity="0.75"/>'
            f'<ellipse cx="{x2}" cy="{y}" rx="12" ry="8" fill="#ff7fae" opacity="0.75"/>')


def smile(x1, x2, y, depth=18):
    mid = (x1 + x2) / 2
    return f'<path d="M{x1} {y} Q{mid} {y+depth} {x2} {y}" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>'


# ------------------------------------------------------------------ critters (256)

save("critter_blorb", svg(256, 256,
    f'<line x1="128" y1="56" x2="128" y2="22" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
    f'<circle cx="128" cy="20" r="12" fill="#ffd94a" stroke="{INK}" stroke-width="6"/>'
    f'<path d="M44 206 C24 120 66 52 128 52 C190 52 232 120 212 206 C204 230 52 230 44 206 Z" fill="#5ad16a" stroke="{INK}" stroke-width="8"/>'
    f'<ellipse cx="92" cy="92" rx="24" ry="12" fill="#b4f5b9" opacity="0.8" transform="rotate(-25 92 92)"/>'
    + eye(128, 124, 38) + cheeks(176, 78, 178) + smile(102, 154, 180)))

save("critter_zibbit", svg(256, 256,
    f'<path d="M100 92 C86 60 70 40 58 22" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>'
    f'<path d="M156 92 C170 60 186 40 198 22" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>'
    f'<circle cx="56" cy="22" r="14" fill="#ffe26b" stroke="{INK}" stroke-width="6"/>'
    f'<circle cx="200" cy="22" r="14" fill="#ffe26b" stroke="{INK}" stroke-width="6"/>'
    f'<circle cx="128" cy="150" r="84" fill="#b784ff" stroke="{INK}" stroke-width="8"/>'
    f'<ellipse cx="92" cy="104" rx="22" ry="11" fill="#dcc4ff" opacity="0.85" transform="rotate(-30 92 104)"/>'
    + eye(98, 140, 24) + eye(158, 140, 24) + cheeks(186, 76, 180)
    + f'<path d="M110 190 Q119 202 128 190 Q137 202 146 190" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'))

save("critter_moxie", svg(256, 256,
    f'<path d="M58 110 L64 28 L122 72 Z" fill="#ff9a3c" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>'
    f'<path d="M198 110 L192 28 L134 72 Z" fill="#ff9a3c" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>'
    f'<path d="M72 92 L76 52 L104 74 Z" fill="#ffc3d6"/><path d="M184 92 L180 52 L152 74 Z" fill="#ffc3d6"/>'
    f'<circle cx="128" cy="146" r="86" fill="#ff9a3c" stroke="{INK}" stroke-width="8"/>'
    f'<ellipse cx="128" cy="186" rx="46" ry="32" fill="#ffe1bf"/>'
    + eye(94, 132, 22) + eye(162, 132, 22)
    + f'<path d="M118 168 L138 168 L128 180 Z" fill="#ff6f9a" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>'
    + f'<path d="M128 180 Q116 198 104 188 M128 180 Q140 198 152 188" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
    + ''.join(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>'
              for x1, y1, x2, y2 in [(74, 170, 36, 160), (74, 182, 38, 186), (182, 170, 220, 160), (182, 182, 218, 186)])))

save("critter_ploot", svg(256, 256,
    ''.join(f'<path d="M{x} 180 C{x-8} 214 {x+18} 228 {x+8} 244" fill="none" stroke="{INK}" stroke-width="22" stroke-linecap="round"/>'
            f'<path d="M{x} 180 C{x-8} 214 {x+18} 228 {x+8} 244" fill="none" stroke="#4cc3ff" stroke-width="10" stroke-linecap="round"/>'
            for x in (66, 104, 146, 186))
    + f'<path d="M36 186 C36 90 76 40 128 40 C180 40 220 90 220 186 Q128 214 36 186 Z" fill="#4cc3ff" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>'
    + f'<ellipse cx="88" cy="84" rx="24" ry="12" fill="#bdeeff" opacity="0.85" transform="rotate(-35 88 84)"/>'
    + eye(98, 128, 28, (3, 4)) + eye(160, 128, 28, (3, 4)) + cheeks(168, 70, 188) + smile(108, 150, 166, 16)))

# ------------------------------------------------------------------ planets (160)


def planet(fill, shade, extra, ring=None):
    back = front = ""
    if ring:
        back = f'<path d="M14 92 A70 20 0 0 1 146 80" fill="none" stroke="{INK}" stroke-width="14"/><path d="M14 92 A70 20 0 0 1 146 80" fill="none" stroke="{ring}" stroke-width="7"/>'
        front = f'<path d="M146 80 A70 20 0 0 1 14 92" fill="none" stroke="{INK}" stroke-width="14"/><path d="M146 80 A70 20 0 0 1 14 92" fill="none" stroke="{ring}" stroke-width="7"/>'
    return svg(160, 160,
        back +
        f'<defs><clipPath id="c"><circle cx="80" cy="80" r="58"/></clipPath></defs>'
        f'<circle cx="80" cy="80" r="58" fill="{fill}"/>'
        f'<g clip-path="url(#c)">{extra}<circle cx="108" cy="104" r="62" fill="{shade}" opacity="0.35"/></g>'
        f'<circle cx="80" cy="80" r="58" fill="none" stroke="{INK}" stroke-width="7"/>'
        f'<path d="M44 58 A42 42 0 0 1 70 34" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" opacity="0.7"/>'
        + front)


save("planet_0", planet("#d9ac7e", "#6b4a3a",
    '<circle cx="60" cy="98" r="13" fill="#b98a60" stroke="#8a6448" stroke-width="3"/>'
    '<circle cx="104" cy="62" r="9" fill="#b98a60" stroke="#8a6448" stroke-width="3"/>'
    '<circle cx="96" cy="112" r="6" fill="#b98a60"/>'))
save("planet_1", planet("#a6e7ff", "#3a5f8a",
    '<path d="M10 66 Q80 52 150 70 L150 82 Q80 66 10 80 Z" fill="#fff" opacity="0.85"/>'
    '<path d="M10 104 Q80 92 150 108 L150 116 Q80 102 10 114 Z" fill="#fff" opacity="0.7"/>'))
save("planet_2", planet("#7fd47a", "#2f5f3a",
    '<path d="M40 70 q14 -16 32 -4 q10 14 -6 22 q-22 6 -26 -18 Z" fill="#4aa6e8"/>'
    '<path d="M92 100 q18 -10 30 4 q2 16 -18 16 q-16 -4 -12 -20 Z" fill="#4aa6e8"/>'
    '<circle cx="104" cy="58" r="6" fill="#3f9e46"/><circle cx="114" cy="66" r="5" fill="#3f9e46"/><circle cx="58" cy="112" r="6" fill="#3f9e46"/>'))
save("planet_3", planet("#ff9fd4", "#7a3a6a",
    '<path d="M10 72 Q80 60 150 74 L150 90 Q80 76 10 88 Z" fill="#ffd3ec"/>'
    '<circle cx="62" cy="108" r="5" fill="#fff"/><circle cx="100" cy="50" r="4" fill="#fff"/>', ring="#ffe27a"))

save("home", svg(160, 160,
    f'<defs><clipPath id="c"><circle cx="80" cy="92" r="56"/></clipPath></defs>'
    f'<circle cx="80" cy="92" r="56" fill="#e3dcff"/>'
    f'<g clip-path="url(#c)"><circle cx="108" cy="118" r="60" fill="#5a4a9a" opacity="0.3"/>'
    f'<rect x="20" y="96" width="120" height="10" fill="#c8bdf5"/></g>'
    f'<circle cx="80" cy="92" r="56" fill="none" stroke="{INK}" stroke-width="7"/>'
    f'<path d="M40 66 A44 44 0 0 1 120 66 Z" fill="#bff3ff" stroke="{INK}" stroke-width="6" opacity="0.95"/>'
    f'<path d="M56 56 A26 26 0 0 1 76 44" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round"/>'
    f'<line x1="80" y1="24" x2="80" y2="4" stroke="{INK}" stroke-width="5"/>'
    f'<path d="M80 4 L104 10 L80 17 Z" fill="#fff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'))

save("asteroid", svg(160, 160,
    ''.join(f'<path d="{d}" fill="{c}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/>' for d, c in [
        ("M30 92 L44 70 L70 72 L78 98 L58 116 L34 110 Z", "#a39cb8"),
        ("M84 56 L106 40 L130 52 L128 78 L104 86 L86 76 Z", "#8f88a8"),
        ("M88 104 L110 94 L132 106 L126 128 L102 132 Z", "#b4aecb"),
        ("M56 36 L70 30 L78 44 L66 52 Z", "#8f88a8"),
    ])
    + ''.join(f'<path d="M{x} {y} l7 -14 l7 14 l-7 10 Z" fill="#6ff2ff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
              for x, y in [(48, 92), (100, 62), (104, 112), (118, 70)])))

save("mystery", svg(160, 160,
    f'<defs><clipPath id="c"><circle cx="80" cy="80" r="58"/></clipPath></defs>'
    f'<circle cx="80" cy="80" r="58" fill="#8b6cf0"/>'
    f'<g clip-path="url(#c)"><path d="M10 60 Q60 40 150 70" stroke="#b9a4ff" stroke-width="12" fill="none"/>'
    f'<path d="M10 110 Q90 86 150 118" stroke="#b9a4ff" stroke-width="10" fill="none"/>'
    f'<circle cx="108" cy="104" r="62" fill="#2a1a60" opacity="0.3"/></g>'
    f'<circle cx="80" cy="80" r="58" fill="none" stroke="{INK}" stroke-width="7"/>'
    f'<path d="M60 64 C60 40 100 40 100 62 C100 78 80 80 80 98" fill="none" stroke="{INK}" stroke-width="24" stroke-linecap="round"/>'
    f'<path d="M60 64 C60 40 100 40 100 62 C100 78 80 80 80 98" fill="none" stroke="#ffe96b" stroke-width="12" stroke-linecap="round"/>'
    f'<circle cx="80" cy="120" r="11" fill="#ffe96b" stroke="{INK}" stroke-width="6"/>'))

save("lantern", svg(160, 160,
    ''.join(f'<line x1="80" y1="80" x2="{80+76*c}" y2="{80+76*s}" stroke="#ffe27a" stroke-width="8" stroke-linecap="round" opacity="0.55"/>'
            for c, s in [(1, 0), (-1, 0), (0, 1), (0, -1), (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7)])
    + f'<defs><clipPath id="c"><circle cx="80" cy="80" r="56"/></clipPath></defs>'
    + f'<circle cx="80" cy="80" r="56" fill="#ffcf3f"/>'
    + f'<g clip-path="url(#c)"><circle cx="108" cy="106" r="60" fill="#b5701a" opacity="0.35"/></g>'
    + f'<circle cx="80" cy="80" r="56" fill="none" stroke="{INK}" stroke-width="7"/>'
    + f'<path d="M80 42 l10 22 l24 2 l-18 16 l6 24 l-22 -13 l-22 13 l6 -24 l-18 -16 l24 -2 Z" fill="#fff6c8" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>'))

save("nest", svg(160, 160,
    f'<path d="M24 100 C8 70 34 34 62 42 C70 18 112 16 120 44 C150 40 160 80 140 100 C150 128 112 146 96 132 C80 150 40 144 40 124 C24 124 18 110 24 100 Z" fill="#4a3d6e" stroke="{INK}" stroke-width="7"/>'
    f'<path d="M80 90 m-30 0 a30 30 0 1 1 60 0 a20 20 0 1 1 -40 0 a10 10 0 1 1 20 0" fill="none" stroke="#7c6aa8" stroke-width="7" stroke-linecap="round"/>'
    f'<path d="M50 62 q10 6 20 0 M92 62 q10 6 20 0" fill="none" stroke="#d8ccff" stroke-width="6" stroke-linecap="round"/>'))

save("gloom", svg(160, 160,
    f'<path d="M22 96 C6 64 36 30 62 40 C72 16 112 18 118 42 C150 36 160 78 140 98 C152 128 112 146 96 132 C80 150 38 146 40 124 C20 124 14 108 22 96 Z" fill="#3b3060" opacity="0.88"/>'
    f'<path d="M52 84 q10 6 20 0 M90 84 q10 6 20 0" fill="none" stroke="#c9bdf0" stroke-width="6" stroke-linecap="round"/>'
    f'<path d="M66 108 q15 -8 30 0" fill="none" stroke="#c9bdf0" stroke-width="5" stroke-linecap="round"/>'))

# ------------------------------------------------------------------ ships (96, white for tinting)
W = "#ffffff"
L = "#d7dbe8"
S = f'stroke="{INK}" stroke-width="5" stroke-linejoin="round"'

save("ship_scout", svg(96, 96,
    f'<path d="M30 70 L18 86 L38 80 Z" fill="{L}" {S}/><path d="M66 70 L78 86 L58 80 Z" fill="{L}" {S}/>'
    f'<path d="M48 8 C66 26 66 58 60 80 L36 80 C30 58 30 26 48 8 Z" fill="{W}" {S}/>'
    f'<circle cx="48" cy="42" r="9" fill="{L}" {S}/>'
    f'<path d="M40 82 L48 94 L56 82" fill="#ffd34a" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'))

save("ship_harvester", svg(96, 96,
    f'<rect x="20" y="30" width="46" height="40" rx="10" fill="{W}" {S}/>'
    f'<path d="M66 38 L86 30 L88 70 L66 62 Z" fill="{L}" {S}/>'
    f'<path d="M30 50 l6 -12 l6 12 l-6 9 Z" fill="#6ff2ff" stroke="{INK}" stroke-width="3"/>'
    f'<path d="M44 52 l5 -10 l5 10 l-5 8 Z" fill="#6ff2ff" stroke="{INK}" stroke-width="3"/>'
    f'<rect x="10" y="40" width="10" height="20" rx="3" fill="{L}" {S}/>'))

save("ship_builder", svg(96, 96,
    f'<path d="M14 62 L82 62 L74 82 L22 82 Z" fill="{W}" {S}/>'
    f'<path d="M28 62 L28 40 L48 24 L68 40 L68 62 Z" fill="{L}" {S}/>'
    f'<rect x="42" y="44" width="12" height="18" fill="{W}" stroke="{INK}" stroke-width="4"/>'
    f'<circle cx="30" cy="72" r="4" fill="{INK}"/><circle cx="48" cy="72" r="4" fill="{INK}"/><circle cx="66" cy="72" r="4" fill="{INK}"/>'))

save("ship_envoy", svg(96, 96,
    f'<ellipse cx="48" cy="56" rx="38" ry="18" fill="{W}" {S}/>'
    f'<path d="M26 52 A22 22 0 0 1 70 52 Z" fill="{L}" {S}/>'
    f'<path d="M48 48 C40 38 28 44 34 54 L48 66 L62 54 C68 44 56 38 48 48 Z" fill="#ff6f9a" stroke="{INK}" stroke-width="4" stroke-linejoin="round" transform="translate(0 -14) scale(1)"/>'
    f'<circle cx="22" cy="60" r="3" fill="{INK}"/><circle cx="74" cy="60" r="3" fill="{INK}"/>'))

save("ship_tractor", svg(96, 96,
    f'<path d="M34 54 L18 92 L78 92 L62 54 Z" fill="#fff6a8" opacity="0.6"/>'
    f'<ellipse cx="48" cy="50" rx="40" ry="14" fill="{W}" {S}/>'
    f'<path d="M30 46 A18 18 0 0 1 66 46 Z" fill="{L}" {S}/>'
    f'<circle cx="28" cy="52" r="3.5" fill="{INK}"/><circle cx="48" cy="56" r="3.5" fill="{INK}"/><circle cx="68" cy="52" r="3.5" fill="{INK}"/>'
    f'<line x1="48" y1="28" x2="48" y2="16" stroke="{INK}" stroke-width="4"/><circle cx="48" cy="14" r="5" fill="#ffd34a" stroke="{INK}" stroke-width="3"/>'))

# ------------------------------------------------------------------ icons (64)
save("icon_star", svg(64, 64,
    f'<path d="M32 4 l8 18 l20 2 l-15 13 l5 20 l-18 -11 l-18 11 l5 -20 l-15 -13 l20 -2 Z" fill="#ffd94a" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'))
save("icon_dust", svg(64, 64,
    f'<path d="M32 4 C35 22 42 29 60 32 C42 35 35 42 32 60 C29 42 22 35 4 32 C22 29 29 22 32 4 Z" fill="#7ff0ff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    f'<circle cx="52" cy="12" r="4" fill="#7ff0ff" stroke="{INK}" stroke-width="2.5"/>'))
save("icon_beacon", svg(64, 64,
    f'<circle cx="32" cy="16" r="14" fill="#fff3a0" opacity="0.7"/>'
    f'<path d="M22 60 L28 24 L36 24 L42 60 Z" fill="#fff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    f'<circle cx="32" cy="16" r="8" fill="#ffd94a" stroke="{INK}" stroke-width="4"/>'
    f'<line x1="25" y1="42" x2="39" y2="42" stroke="{INK}" stroke-width="3"/>'))
save("icon_heart", svg(64, 64,
    f'<path d="M32 20 C24 4 4 10 8 28 C12 42 32 56 32 56 C32 56 52 42 56 28 C60 10 40 4 32 20 Z" fill="#ff6f9a" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'))
save("icon_bulb", svg(64, 64,
    f'<path d="M32 6 C18 6 10 16 10 28 C10 38 18 42 22 50 L42 50 C46 42 54 38 54 28 C54 16 46 6 32 6 Z" fill="#ffe96b" stroke="{INK}" stroke-width="4"/>'
    f'<rect x="22" y="50" width="20" height="8" rx="2" fill="#c9c3dd" stroke="{INK}" stroke-width="4"/>'))
save("icon_warn", svg(64, 64,
    f'<path d="M32 4 L60 56 L4 56 Z" fill="#ffb13b" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    f'<rect x="29" y="22" width="6" height="18" rx="3" fill="{INK}"/><circle cx="32" cy="48" r="3.5" fill="{INK}"/>'))

# ---- Lucky Cards and new icons
save("icon_rocket", svg(64, 64,
    f'<path d="M20 46 L10 58 L24 54 Z" fill="#ff8a5c" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>'
    f'<path d="M44 46 L54 58 L40 54 Z" fill="#ff8a5c" stroke="{INK}" stroke-width="3.5" stroke-linejoin="round"/>'
    f'<path d="M32 4 C46 16 46 40 42 54 L22 54 C18 40 18 16 32 4 Z" fill="#ffffff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    f'<circle cx="32" cy="26" r="7" fill="#7fd8ff" stroke="{INK}" stroke-width="3.5"/>'
    f'<path d="M26 56 L32 64 L38 56" fill="#ffd34a" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'))
save("icon_dice", svg(64, 64,
    f'<rect x="6" y="6" width="52" height="52" rx="12" fill="#ffffff" stroke="{INK}" stroke-width="4.5"/>'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="5.5" fill="{INK}"/>' for x, y in [(20, 20), (44, 20), (32, 32), (20, 44), (44, 44)])))
save("icon_shield", svg(64, 64,
    f'<path d="M32 4 L56 14 C56 36 46 52 32 60 C18 52 8 36 8 14 Z" fill="#7ff0ff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    f'<path d="M32 12 L48 19 C48 34 42 45 32 51 Z" fill="#c8fbff"/>'))
save("icon_wormhole", svg(64, 64,
    f'<circle cx="32" cy="32" r="28" fill="#5b3fb0" stroke="{INK}" stroke-width="4"/>'
    f'<path d="M32 32 m-20 0 a20 20 0 1 1 40 0 a14 14 0 1 1 -28 0 a8 8 0 1 1 16 0" fill="none" stroke="#e2c9ff" stroke-width="4.5" stroke-linecap="round"/>'
    f'<circle cx="32" cy="32" r="4" fill="#ffffff"/>'))
save("icon_clock", svg(64, 64,
    f'<circle cx="32" cy="34" r="26" fill="#ffe96b" stroke="{INK}" stroke-width="4"/>'
    f'<circle cx="32" cy="34" r="19" fill="#fffbe0"/>'
    f'<path d="M32 20 L32 34 L42 40" fill="none" stroke="{INK}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>'
    f'<rect x="26" y="2" width="12" height="7" rx="3" fill="#ffe96b" stroke="{INK}" stroke-width="3.5"/>'))
save("icon_card", svg(64, 64,
    f'<rect x="10" y="4" width="44" height="56" rx="8" fill="#6a55d8" stroke="{INK}" stroke-width="4"/>'
    f'<rect x="16" y="10" width="32" height="44" rx="5" fill="none" stroke="#b9a8ff" stroke-width="2.5"/>'
    f'<path d="M32 18 l5 10 l11 1 l-8 7 l3 11 l-11 -6 l-11 6 l3 -11 l-8 -7 l11 -1 Z" fill="#ffd94a" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'))
save("icon_pinky", svg(64, 64,
    f'<path d="M32 22 C26 10 10 14 12 28 C14 40 32 52 32 52 C32 52 50 40 52 28 C54 14 38 10 32 22 Z" fill="#ff8fb5" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    f'<path d="M22 30 q10 -8 20 0" fill="none" stroke="#ffffff" stroke-width="4" stroke-linecap="round"/>'))
save("icon_critter", svg(64, 64,
    f'<path d="M10 52 C4 28 16 10 32 10 C48 10 60 28 54 52 C52 60 12 60 10 52 Z" fill="#ffffff" stroke="{INK}" stroke-width="4.5"/>'
    f'<circle cx="24" cy="32" r="6" fill="{INK}"/><circle cx="40" cy="32" r="6" fill="{INK}"/>'
    f'<circle cx="26" cy="30" r="2" fill="#fff"/><circle cx="42" cy="30" r="2" fill="#fff"/>'
    f'<path d="M24 44 Q32 50 40 44" fill="none" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>'))

save("icon_city", svg(64, 64,
    f'<rect x="6" y="30" width="18" height="28" rx="3" fill="#ffb86b" stroke="{INK}" stroke-width="4"/>'
    f'<rect x="22" y="12" width="20" height="46" rx="3" fill="#7fd8ff" stroke="{INK}" stroke-width="4"/>'
    f'<path d="M32 2 L32 12" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>'
    f'<circle cx="32" cy="3" r="3" fill="#ff6f9a" stroke="{INK}" stroke-width="2"/>'
    f'<path d="M40 58 L40 28 L50 20 L60 28 L60 58 Z" fill="#ffe96b" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    + ''.join(f'<rect x="{x}" y="{y}" width="5" height="6" rx="1" fill="#fffbe0" stroke="{INK}" stroke-width="1.5"/>'
              for x, y in [(12, 37), (12, 47), (27, 20), (34, 20), (27, 32), (34, 32), (27, 44), (34, 44), (47, 34), (47, 46)])))

print("art written to", os.path.abspath(OUT))
