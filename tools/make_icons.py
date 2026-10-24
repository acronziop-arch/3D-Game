#!/usr/bin/env python3
"""Генерирует SVG-иконки интерфейса в assets/icons/.

Запуск: python3 tools/make_icons.py
Иконки рисуются кодом, чтобы стиль был единым: мягкие формы, 2–3 тона,
тёмная обводка того же оттенка. Размер холста 64×64.
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
SW = 2.6  # толщина обводки


def svg(body, size=64):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64">'
            f'<g stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>\n')


def shape(d, fill, stroke, extra=""):
    width = SW
    if extra.startswith('stroke-width="'):
        width = float(extra.split('"')[1])
        extra = ""
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" {extra}/>'


def line(d, stroke, w=2.2, opacity=1.0):
    return f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{w}" opacity="{opacity}"/>'


def circle(cx, cy, r, fill, stroke="none", w=SW):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{w}"/>'


def ellipse(cx, cy, rx, ry, fill, stroke="none", w=SW):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{w}"/>'


def rock(main, light, dark):
    return (shape("M10 44 L16 26 L30 16 L46 20 L56 34 L52 48 L34 54 L18 52 Z", main, dark)
            + shape("M16 26 L30 16 L46 20 L36 30 L22 32 Z", light, "none")
            + line("M22 32 L36 30 L46 20 M36 30 L40 46", dark, 1.6, 0.55))


ICONS = {}

# --- Ресурсы -----------------------------------------------------------------------------
ICONS["log"] = svg(
    shape("M10 40 L42 18 Q50 14 54 22 Q58 30 50 34 L18 56 Q10 58 7 50 Q5 44 10 40 Z", "#B87442", "#6E4024")
    + ellipse(49, 26, 7.5, 9.5, "#E8C08A", "#6E4024", 2.2).replace("/>", ' transform="rotate(-34 49 26)"/>')
    + ellipse(49, 26, 4, 5.4, "none", "#C48A52", 1.6).replace("/>", ' transform="rotate(-34 49 26)"/>')
    + line("M17 46 L37 32 M14 51 L26 43 M25 47 L41 36", "#7E4A2A", 1.8, 0.6))
ICONS["stone"] = svg(rock("#A3A3A8", "#C6C6CB", "#5F5F68"))
ICONS["clay"] = svg(
    shape("M8 46 Q10 30 26 28 Q30 16 44 20 Q58 24 56 40 Q56 52 40 52 L18 52 Q8 52 8 46 Z", "#C97E58", "#7A4630")
    + shape("M26 28 Q30 18 42 22 Q36 26 34 32 Q30 30 26 28 Z", "#E0A07C", "none")
    + line("M18 44 Q28 40 36 46 M38 36 Q46 34 50 40", "#8E5238", 1.8, 0.6))
ICONS["sand"] = svg(
    shape("M6 50 Q20 22 32 20 Q44 22 58 50 Z", "#EDD49A", "#A88A4E")
    + shape("M22 30 Q30 22 36 23 Q30 30 28 40 Q24 36 22 30 Z", "#F7E6B8", "none")
    + "".join(circle(x, y, 1.3, "#B8995A") for x, y in [(24, 44), (34, 38), (42, 46), (30, 48), (46, 40), (18, 47)]))
ICONS["coal"] = svg(
    shape("M8 46 L14 30 L26 26 L32 34 L26 48 Z", "#3B3C44", "#17181C")
    + shape("M28 44 L34 22 L48 16 L58 30 L50 48 Z", "#44464F", "#17181C")
    + shape("M34 22 L48 16 L44 28 Z", "#6F7385", "none") + shape("M14 30 L26 26 L22 34 Z", "#666A7A", "none"))
ICONS["copper_ore"] = svg(rock("#A09C98", "#C3BFBA", "#5E5A56")
    + shape("M24 40 L28 28 L33 38 Z", "#F0A04A", "#9A5420", 'stroke-width="1.8"')
    + shape("M34 44 L40 30 L45 42 Z", "#E8873A", "#9A5420", 'stroke-width="1.8"')
    + shape("M40 26 L44 18 L47 27 Z", "#F6B866", "#9A5420", 'stroke-width="1.8"'))
ICONS["iron_ore"] = svg(rock("#9B999C", "#BFBDC0", "#58565A")
    + "".join(ellipse(x, y, rx, ry, "#B4513E", "#6E2A1E", 1.6) for x, y, rx, ry in [(26, 38, 5, 3.5), (40, 42, 4, 3), (40, 28, 3.5, 2.6)]))
ICONS["hide"] = svg(
    shape("M20 10 Q32 16 44 10 Q46 20 54 22 Q50 32 56 42 Q46 44 44 54 Q32 48 20 54 Q18 44 8 42 Q14 32 10 22 Q18 20 20 10 Z", "#C99562", "#6E4A2C")
    + "".join(ellipse(x, y, rx, ry, "#9C6B3E") for x, y, rx, ry in [(26, 26, 4, 3), (38, 34, 5, 3.5), (28, 40, 3, 2.4), (40, 22, 2.6, 2)]))
ICONS["wool"] = svg(
    shape("M14 40 Q6 34 12 26 Q12 16 24 16 Q30 8 40 14 Q52 12 54 24 Q60 32 52 40 Q52 52 38 50 Q30 56 22 50 Q12 50 14 40 Z", "#F4EFE4", "#A89E8A")
    + line("M22 30 Q28 24 34 30 Q40 36 46 30 M20 40 Q28 36 32 42 Q38 46 44 40", "#CBBFA8", 2.0))
ICONS["wax"] = svg("".join(
    shape(f"M{x} {y-9} L{x+8} {y-4.5} L{x+8} {y+4.5} L{x} {y+9} L{x-8} {y+4.5} L{x-8} {y-4.5} Z", "#F3C452", "#9E7414")
    for x, y in [(24, 22), (40, 22), (16, 38), (32, 38), (48, 38), (24, 52), (40, 52)])
    + "".join(circle(x, y, 2.4, "#FBE39A") for x, y in [(24, 22), (32, 38), (40, 52)]))
ICONS["plank"] = svg(
    shape("M6 44 L46 30 L58 36 L18 50 Z", "#C98A50", "#6E4626")
    + shape("M6 36 L46 22 L58 28 L18 42 Z", "#DCA265", "#6E4626")
    + shape("M6 28 L46 14 L58 20 L18 34 Z", "#E8B47A", "#6E4626")
    + line("M16 30 L40 22 M18 38 L38 31 M20 46 L42 38", "#A8703E", 1.5, 0.7))
ICONS["stone_block"] = svg(
    shape("M32 10 L54 21 L32 32 L10 21 Z", "#C2C0C0", "#5F5D60")
    + shape("M10 21 L32 32 L32 56 L10 45 Z", "#A3A0A1", "#5F5D60")
    + shape("M54 21 L32 32 L32 56 L54 45 Z", "#8B8889", "#5F5D60")
    + line("M18 26 L26 30 M42 40 L48 37", "#6E6C6F", 1.4, 0.5))
ICONS["brick"] = svg(
    shape("M6 40 L34 40 L34 54 L6 54 Z", "#C5603F", "#6C2E1E")
    + shape("M30 40 L58 40 L58 54 L30 54 Z", "#B85538", "#6C2E1E")
    + shape("M18 24 L46 24 L46 38 L18 38 Z", "#D06C49", "#6C2E1E")
    + line("M22 28 L40 28 M10 44 L28 44 M36 44 L52 44", "#E89A7A", 1.5, 0.7))
ICONS["glass"] = svg(
    shape("M12 10 L52 10 L52 54 L12 54 Z", "#86B9EA", "#3F5F86")
    + line("M32 10 L32 54 M12 32 L52 32", "#3F5F86", 2.4)
    + line("M17 26 L26 15 M17 20 L21 15 M37 48 L47 37", "#E6F3FF", 2.4, 0.9))
ICONS["iron_ingot"] = svg(
    shape("M8 46 L18 28 L54 28 L58 46 Z", "#8E949E", "#4A4E57")
    + shape("M18 28 L54 28 L50 22 L22 22 Z", "#B5BBC6", "#4A4E57")
    + line("M16 40 L30 40", "#D3D8E0", 2.0, 0.8))
ICONS["copper_ingot"] = svg(
    shape("M8 46 L18 28 L54 28 L58 46 Z", "#D98A4C", "#7C4420")
    + shape("M18 28 L54 28 L50 22 L22 22 Z", "#F0AE74", "#7C4420")
    + line("M16 40 L30 40", "#F8CFA4", 2.0, 0.8))
ICONS["leather"] = svg(
    shape("M10 20 Q32 14 54 20 L54 44 Q32 50 10 44 Z", "#A0673A", "#5A361C")
    + ellipse(54, 32, 6, 12, "#8A5530", "#5A361C", 2.2)
    + line("M14 25 Q32 20 50 25 M14 39 Q32 44 50 39", "#E2B27E", 1.6, 0.9).replace('opacity="0.9"', 'opacity="0.9" stroke-dasharray="3 3"'))
ICONS["cloth"] = svg(
    shape("M8 42 L32 50 L56 42 L56 48 L32 56 L8 48 Z", "#E2D5BE", "#8C7D63")
    + shape("M8 34 L32 42 L56 34 L56 42 L32 50 L8 42 Z", "#F2E9D8", "#8C7D63")
    + shape("M8 26 L32 34 L56 26 L56 34 L32 42 L8 34 Z", "#D9786A", "#7A3A30")
    + shape("M8 26 L32 18 L56 26 L32 34 Z", "#F7F1E4", "#8C7D63"))

# --- Инструменты и общие --------------------------------------------------------------------
ICONS["tool_harvest"] = svg(
    line("M18 54 L42 18", "#7A4A28", 6.5) + line("M18 54 L42 18", "#B87A48", 3.5)
    + shape("M34 14 Q44 6 54 12 Q52 22 46 28 Q42 22 34 14 Z", "#B9C0CB", "#4D535E")
    + line("M44 11 Q50 14 50 20", "#E8EDF3", 1.8))
ICONS["tool_build"] = svg(
    line("M16 54 L38 26", "#7A4A28", 6.5) + line("M16 54 L38 26", "#B87A48", 3.5)
    + shape("M30 14 L46 30 L54 22 L38 6 Z", "#9AA1AD", "#4D535E")
    + shape("M30 14 L38 6 L42 10 L34 18 Z", "#C7CDD6", "none"))
ICONS["tool_flatten"] = svg(
    line("M44 8 L30 34", "#7A4A28", 6.0) + line("M44 8 L30 34", "#B87A48", 3.2)
    + shape("M22 30 L38 38 L32 54 Q20 58 14 50 Z", "#A8AFBA", "#4D535E")
    + line("M8 58 L58 58", "#8C6A48", 3.0))
ICONS["tool_demolish"] = svg(
    shape("M8 34 L26 34 L26 46 L8 46 Z", "#C5603F", "#6C2E1E") + shape("M8 48 L30 48 L30 58 L8 58 Z", "#B85538", "#6C2E1E")
    + shape("M34 48 L56 48 L56 58 L34 58 Z", "#C5603F", "#6C2E1E")
    + line("M30 26 L52 8", "#7A4A28", 6.0) + line("M30 26 L52 8", "#B87A48", 3.2)
    + shape("M22 22 L32 14 L40 24 L30 32 Z", "#7D8592", "#3E434C")
    + line("M36 36 L40 42 L36 46", "#E04A3A", 2.4))
ICONS["tool_craft"] = svg(
    shape("M10 22 L50 22 Q58 22 58 28 L42 32 L42 40 L48 46 L48 52 L18 52 L18 46 L24 40 L24 32 L10 30 Z", "#6F7682", "#30343B")
    + shape("M10 22 L50 22 Q58 22 58 28 L42 28 L10 26 Z", "#A3AAB5", "none")
    + line("M22 18 L28 8 M34 16 L34 6 M44 18 L40 8", "#F2A23A", 2.4))
ICONS["settings"] = svg(
    "".join(f'<rect x="28" y="6" width="8" height="12" rx="2" fill="#8C7A68" transform="rotate({a} 32 32)"/>' for a in range(0, 360, 45))
    + circle(32, 32, 17, "#8C7A68") + circle(32, 32, 7, "#F5F3EF"))
ICONS["more"] = svg(circle(16, 32, 5, "#6B5B4D") + circle(32, 32, 5, "#6B5B4D") + circle(48, 32, 5, "#6B5B4D"))
ICONS["close"] = svg(line("M18 18 L46 46 M46 18 L18 46", "#6B5B4D", 5.0))
ICONS["timer"] = svg(
    shape("M18 8 L46 8 M18 56 L46 56", "none", "#6B5B4D")
    + shape("M20 10 L44 10 Q44 24 32 32 Q44 40 44 54 L20 54 Q20 40 32 32 Q20 24 20 10 Z", "#F3EEE6", "#6B5B4D")
    + shape("M24 50 Q26 42 32 40 Q38 42 40 50 Z", "#E2B86A", "none") + shape("M26 18 L38 18 L32 26 Z", "#E2B86A", "none"))
ICONS["warning"] = svg(shape("M32 8 L58 54 L6 54 Z", "#F2C14E", "#8A6512") + line("M32 24 L32 38", "#5A4310", 4.5) + circle(32, 46, 2.8, "#5A4310"))

# --- Крестик над водой (для 3D) ---------------------------------------------------------------
ICONS["cross"] = svg(circle(32, 32, 26, "#FFFFFF", "#E04A3A", 4) + line("M20 20 L44 44 M44 20 L20 44", "#E04A3A", 7.5))

# --- Погода --------------------------------------------------------------------------------------
SUN = circle(32, 32, 11, "#F6C445", "#B9851A") + "".join(
    line(f"M{32 + 16 * c:.1f} {32 + 16 * s:.1f} L{32 + 23 * c:.1f} {32 + 23 * s:.1f}", "#E8A92A", 3.2)
    for c, s in [(1, 0), (0.707, 0.707), (0, 1), (-0.707, 0.707), (-1, 0), (-0.707, -0.707), (0, -1), (0.707, -0.707)])
CLOUD = shape("M14 46 Q6 46 7 38 Q8 31 16 31 Q18 21 29 21 Q38 21 41 29 Q44 26 49 28 Q57 30 56 38 Q57 46 48 46 Z", "#FFFFFF", "#8A97A8")
CLOUD_DARK = shape("M14 42 Q6 42 7 34 Q8 27 16 27 Q18 17 29 17 Q38 17 41 25 Q44 22 49 24 Q57 26 56 34 Q57 42 48 42 Z", "#C3CAD4", "#6B7686")
ICONS["weather_clear"] = svg(SUN)
ICONS["weather_cloudy"] = svg(f'<g transform="translate(8 -8) scale(0.8)">{SUN}</g>' + CLOUD)
ICONS["weather_overcast"] = svg(f'<g transform="translate(6 -10) scale(0.85)">{CLOUD_DARK}</g>' + CLOUD)
ICONS["weather_windy"] = svg(line("M8 24 L40 24 Q50 24 50 16 Q50 10 44 10", "#7C8DA4", 3.6) + line("M8 36 L50 36 Q58 36 58 44 Q58 50 52 50", "#7C8DA4", 3.6)
    + line("M14 48 L34 48", "#7C8DA4", 3.6))
ICONS["weather_rain"] = svg(f'<g transform="translate(0 -6)">{CLOUD_DARK}</g>' + "".join(line(f"M{x} {44} L{x - 4} {56}", "#4E8FD6", 3.2) for x in [20, 32, 44]))
ICONS["weather_storm"] = svg(f'<g transform="translate(0 -8)">{CLOUD_DARK}</g>'
    + shape("M34 34 L24 48 L32 48 L28 60 L42 42 L34 42 L38 34 Z", "#F6C445", "#9E7414") + line("M16 42 L13 50 M50 42 L47 50", "#4E8FD6", 3.0))
FLAKE = lambda x, y, r: "".join(line(f"M{x - r * c:.1f} {y - r * s:.1f} L{x + r * c:.1f} {y + r * s:.1f}", "#6FA5DD", 2.2) for c, s in [(1, 0), (0.5, 0.866), (-0.5, 0.866)])
ICONS["weather_snow"] = svg(f'<g transform="translate(0 -8)">{CLOUD}</g>' + FLAKE(20, 50, 5) + FLAKE(34, 54, 5) + FLAKE(46, 46, 4))
ICONS["weather_blizzard"] = svg(FLAKE(26, 28, 14).replace('2.2', '3.4') + line("M34 44 L54 44 Q60 44 60 50 M38 54 L56 54", "#7C8DA4", 3.2) + line("M6 14 L18 14", "#7C8DA4", 3.2))
ICONS["weather_fog"] = svg("".join(line(f"M{x0} {y} L{x1} {y}", "#8C9AAB", 4.2) for x0, x1, y in [(10, 46, 18), (18, 56, 28), (8, 50, 38), (16, 54, 48)]))
ICONS["auto"] = svg(shape("M32 8 A24 24 0 1 1 10 42", "none", "#8C7A68").replace(f'stroke-width="{SW}"', 'stroke-width="4"')
    + shape("M4 36 L10 44 L18 38", "none", "#8C7A68").replace(f'stroke-width="{SW}"', 'stroke-width="4"')
    + f'<text x="32" y="40" font-family="Arial, sans-serif" font-size="22" font-weight="bold" fill="#8C7A68" text-anchor="middle">A</text>')

ICONS["clock_day"] = svg(circle(32, 32, 24, "#FFF6DD", "#C9973A", 3.2) + line("M32 32 L32 16 M32 32 L42 38", "#7A5A2A", 3.6)
    + circle(32, 32, 2.6, "#7A5A2A") + "".join(circle(32 + 18 * c, 32 + 18 * s, 1.6, "#C9973A") for c, s in [(1, 0), (0, 1), (-1, 0), (0, -1)]))
ICONS["clock_night"] = svg(circle(32, 32, 24, "#2E3A5A", "#8A97C8", 3.2) + line("M32 32 L32 16 M32 32 L42 38", "#E6EAF8", 3.6)
    + circle(32, 32, 2.6, "#E6EAF8") + "".join(circle(32 + 18 * c, 32 + 18 * s, 1.6, "#8A97C8") for c, s in [(1, 0), (0, 1), (-1, 0), (0, -1)]))

# --- Время суток и сезоны -------------------------------------------------------------------------
ICONS["day"] = ICONS["weather_clear"]
ICONS["night"] = svg(shape("M40 8 Q22 12 20 32 Q22 52 42 56 Q28 58 18 50 Q8 42 8 30 Q10 14 24 8 Q32 6 40 8 Z", "#F3E2A4", "#A88E3A")
    + "".join(circle(x, y, r, "#F3E2A4") for x, y, r in [(46, 20, 2.5), (54, 34, 1.8), (44, 44, 1.5)]))
ICONS["season_spring"] = svg(line("M32 58 L32 34", "#5C9A3A", 3.4) + shape("M32 46 Q20 44 16 36 Q26 34 32 42 Z", "#7CC04C", "#3E7424")
    + "".join(ellipse(32 + 9 * c, 22 + 9 * s, 6.5, 6.5, "#F4A5C0", "#B25878", 2.0) for c, s in [(1, 0), (0.31, 0.95), (-0.81, 0.59), (-0.81, -0.59), (0.31, -0.95)])
    + circle(32, 22, 5, "#F6C445", "#B9851A", 2))
ICONS["season_summer"] = svg(line("M32 58 L32 34", "#7A4A28", 5.0)
    + shape("M32 6 Q46 8 50 20 Q58 26 54 36 Q52 46 40 44 Q32 50 24 44 Q12 46 10 36 Q6 26 14 20 Q18 8 32 6 Z", "#6DB04A", "#3E7424")
    + shape("M22 16 Q30 10 38 14 Q30 18 26 26 Q22 22 22 16 Z", "#98D06E", "none"))
ICONS["season_autumn"] = svg(shape("M32 6 Q36 16 46 14 Q44 24 54 28 Q46 34 50 42 Q40 42 36 50 L32 44 L28 50 Q24 42 14 42 Q18 34 10 28 Q20 24 18 14 Q28 16 32 6 Z", "#E68A2E", "#8E4A12")
    + line("M32 14 L32 58 M32 30 L42 22 M32 36 L22 28", "#8E4A12", 2.2))
ICONS["season_winter"] = svg(FLAKE(32, 32, 22).replace('2.2', '4.2')
    + "".join(line(f"M{32 + 14 * c - 5 * s:.1f} {32 + 14 * s + 5 * c:.1f} L{32 + 14 * c:.1f} {32 + 14 * s:.1f} L{32 + 14 * c + 5 * s:.1f} {32 + 14 * s - 5 * c:.1f}", "#6FA5DD", 3.0)
            for c, s in [(1, 0), (0.5, 0.866), (-0.5, 0.866), (-1, 0), (-0.5, -0.866), (0.5, -0.866)]))

# --- Категории зданий --------------------------------------------------------------------------------
ICONS["cat_production"] = svg(
    "".join(f'<rect x="28" y="6" width="8" height="10" rx="2" fill="#B07B4E" stroke="#6A4628" stroke-width="2" transform="rotate({a} 32 32)"/>' for a in range(0, 360, 60))
    + circle(32, 32, 16, "#C99263", "#6A4628") + circle(32, 32, 6, "#F5F3EF", "#6A4628", 2))
ICONS["cat_housing"] = svg(shape("M10 30 L32 10 L54 30", "#D06C49", "#6C2E1E") + shape("M14 28 L50 28 L50 54 L14 54 Z", "#E8C394", "#7A5634")
    + shape("M27 54 L27 40 L37 40 L37 54", "#9C6438", "#5A361C") + shape("M40 34 L46 34 L46 40 L40 40 Z", "#86B9EA", "#3F5F86", 'stroke-width="1.8"'))
ICONS["cat_special"] = svg(shape("M32 6 L39 23 L57 24 L43 36 L48 54 L32 44 L16 54 L21 36 L7 24 L25 23 Z", "#F6C445", "#9E7414"))
ICONS["cat_defense"] = svg(shape("M32 6 L54 14 Q54 42 32 58 Q10 42 10 14 Z", "#A3A3A8", "#4D4D55") + shape("M32 6 L54 14 Q54 42 32 58 Z", "#BDBDC2", "none")
    + shape("M32 18 L42 22 Q42 38 32 46 Q22 38 22 22 Z", "#C9B8A6", "#6B5B4D", 'stroke-width="2"'))
ICONS["cat_water"] = svg(line("M6 26 Q14 18 22 26 Q30 34 38 26 Q46 18 54 26 Q58 30 60 28", "#4E8FD6", 4.0)
    + line("M6 40 Q14 32 22 40 Q30 48 38 40 Q46 32 54 40 Q58 44 60 42", "#6FA5DD", 4.0)
    + line("M6 54 Q14 46 22 54 Q30 62 38 54 Q46 46 54 54", "#8FBDE6", 4.0))

os.makedirs(OUT, exist_ok=True)
for name, data in ICONS.items():
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(data)
print(f"{len(ICONS)} иконок → {os.path.normpath(OUT)}")
