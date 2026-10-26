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


def arc_arrow(cx, cy, r, a0, a1, color, w=5.0, head=9.0):
    """Дуга по часовой стрелке (экранные координаты) от a0 до a1 градусов
    и наконечник на конце, направленный по ходу дуги."""
    import math
    t0, t1 = math.radians(a0), math.radians(a1)
    x0, y0 = cx + r * math.cos(t0), cy + r * math.sin(t0)
    x1, y1 = cx + r * math.cos(t1), cy + r * math.sin(t1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    # Дугу не доводим до конца: там наконечник.
    back = math.radians(a1) - head * 0.55 / r
    xb, yb = cx + r * math.cos(back), cy + r * math.sin(back)
    arc = f'<path d="M{x0:.1f} {y0:.1f} A{r} {r} 0 {large} 1 {xb:.1f} {yb:.1f}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round"/>'
    tx, ty = -math.sin(t1), math.cos(t1)
    nx, ny = math.cos(t1), math.sin(t1)
    tip = (x1 + tx * head * 0.6, y1 + ty * head * 0.6)
    l = (x1 - tx * head * 0.5 + nx * head * 0.75, y1 - ty * head * 0.5 + ny * head * 0.75)
    rr = (x1 - tx * head * 0.5 - nx * head * 0.75, y1 - ty * head * 0.5 - ny * head * 0.75)
    tri = f'<path d="M{tip[0]:.1f} {tip[1]:.1f} L{l[0]:.1f} {l[1]:.1f} L{rr[0]:.1f} {rr[1]:.1f} Z" fill="{color}" stroke="{color}" stroke-width="1.5" stroke-linejoin="round"/>'
    return arc + tri


def pin(inner, color):
    """Метка на карте: капля цвета color с рисунком внутри (рисунок в квадрате 16..48)."""
    return (shape("M32 60 Q14 40 14 26 A18 18 0 1 1 50 26 Q50 40 32 60 Z", color, "#3E342B", 'stroke-width="2.2"')
            + circle(32, 26, 13.5, "#FFFFFF") + f'<g transform="translate(32 26) scale(0.42) translate(-32 -32)">{inner}</g>')


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
    # Пень с воткнутым топором и щепками.
    shape("M12 40 L12 54 Q32 62 52 54 L52 40 Z", "#9C6A3E", "#5E3A1E")
    + ellipse(32, 40, 20, 7, "#E2B47C", "#5E3A1E", 2.4) + ellipse(32, 40, 12, 4, "none", "#B98552", 1.6)
    + line("M24 40 L40 12", "#6E4024", 6.0) + line("M24 40 L40 12", "#C08650", 3.0)
    + shape("M33 10 Q42 2 52 8 Q50 18 44 22 Q40 16 33 10 Z", "#B9C0CB", "#4D535E")
    + shape("M8 30 L14 26 L16 32 Z", "#E2B47C", "#8E5A30", 'stroke-width="1.6"') + shape("M52 26 L58 24 L56 31 Z", "#E2B47C", "#8E5A30", 'stroke-width="1.6"'))
ICONS["tool_build"] = svg(
    # Домик и «плюс» — построить новое.
    shape("M8 32 L28 14 L48 32", "#D06C49", "#6C2E1E") + shape("M12 30 L44 30 L44 56 L12 56 Z", "#F0D3A6", "#7A5634")
    + shape("M23 56 L23 42 L33 42 L33 56", "#A86C3E", "#5A361C")
    + circle(48, 46, 12, "#5E9C4A", "#2F5A22", 2.4) + line("M48 39 L48 53 M41 46 L55 46", "#FFFFFF", 4.0))
ICONS["tool_flatten"] = svg(
    # Холм, срезанный в ровную площадку, и стрелки вниз.
    shape("M4 56 Q14 30 26 28 L40 28 Q52 30 60 56 Z", "#8DBE5A", "#3E6A26")
    + shape("M18 28 L46 28 L46 34 L18 34 Z", "#C9A06A", "#7A5634", 'stroke-width="1.8"')
    + line("M24 6 L24 20 M18 14 L24 21 L30 14", "#4E7FC0", 3.6) + line("M40 6 L40 20 M34 14 L40 21 L46 14", "#4E7FC0", 3.6))
ICONS["tool_nature"] = svg(
    # Росток с двумя листьями над горкой земли.
    shape("M10 56 Q32 42 54 56 Z", "#9C6A3E", "#5E3A1E")
    + line("M32 50 L32 24", "#4F8A2E", 4.2)
    + shape("M32 34 Q14 34 10 18 Q28 16 32 34 Z", "#7CC04C", "#3E7424")
    + shape("M32 26 Q48 26 54 10 Q36 8 32 26 Z", "#8FD45A", "#3E7424"))
ICONS["tool_edit"] = svg(
    # Домик с перекрёстными стрелками — передвинуть и повернуть.
    shape("M10 30 L28 14 L46 30", "#7B8EC0", "#36446A") + shape("M14 28 L42 28 L42 52 L14 52 Z", "#E8E2D6", "#5A5A6A")
    + circle(46, 46, 13, "#F2C14E", "#8A6512", 2.4)
    + line("M46 37 L46 55 M37 46 L55 46", "#5A4310", 3.2)
    + shape("M46 34 L42 39 L50 39 Z", "#5A4310", "#5A4310", 'stroke-width="1"') + shape("M46 58 L42 53 L50 53 Z", "#5A4310", "#5A4310", 'stroke-width="1"')
    + shape("M34 46 L39 42 L39 50 Z", "#5A4310", "#5A4310", 'stroke-width="1"') + shape("M58 46 L53 42 L53 50 Z", "#5A4310", "#5A4310", 'stroke-width="1"'))
ICONS["tool_demolish"] = svg(
    shape("M8 34 L26 34 L26 46 L8 46 Z", "#C5603F", "#6C2E1E") + shape("M8 48 L30 48 L30 58 L8 58 Z", "#B85538", "#6C2E1E")
    + shape("M34 48 L56 48 L56 58 L34 58 Z", "#C5603F", "#6C2E1E")
    + line("M30 26 L52 8", "#7A4A28", 6.0) + line("M30 26 L52 8", "#B87A48", 3.2)
    + shape("M22 22 L32 14 L40 24 L30 32 Z", "#7D8592", "#3E434C"))
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
# Кнопки действий для сенсорного управления.
ICONS["check"] = svg(line("M14 34 L27 47 L50 18", "#4E7A3A", 6.5))
ICONS["rotate"] = svg(arc_arrow(32, 33, 19, -60, 210, "#6B5B4D", 5.0, 11.0))
ICONS["plus"] = svg(line("M32 14 L32 50 M14 32 L50 32", "#6B5B4D", 6.0))
ICONS["minus"] = svg(line("M14 32 L50 32", "#6B5B4D", 6.0))
# Стрелка «превращается в» (в шрифте Nunito её нет, а в браузере нет системных шрифтов).
ICONS["arrow"] = svg(line("M10 32 L50 32 M37 19 L51 32 L37 45", "#8C7A68", 5.5))
ICONS["mow"] = svg(
    # Коса.
    line("M14 58 L40 10", "#7A4A28", 5.0) + line("M14 58 L40 10", "#B87A48", 2.6)
    + shape("M40 10 Q60 14 62 34 Q52 22 36 20 Z", "#B9C0CB", "#4D535E") + line("M22 40 L30 44", "#7A4A28", 4.0)
    + line("M4 60 L22 60 M30 60 L44 60", "#7CC04C", 3.0))
ICONS["grass_short"] = svg("".join(line(f"M{x} 56 Q{x + d} {44} {x + d * 2} {y}", "#5E9C3A", 3.6) for x, d, y in
    [(14, 2, 30), (22, -2, 22), (30, 3, 26), (38, -3, 20), (46, 2, 30)]) + line("M8 58 L56 58", "#8C6A48", 3.0))
ICONS["grass_tall"] = svg("".join(line(f"M{x} 58 Q{x + d} 34 {x + d * 2} {y}", "#6EA844", 3.4) for x, d, y in
    [(16, 3, 12), (26, -2, 6), (36, 2, 10), (46, -3, 16)])
    + "".join(ellipse(x, y, 3, 6, "#D9B860", "#8A6E2A", 1.4) for x, y in [(22, 12), (32, 8), (40, 13)]))
ICONS["flower"] = svg(line("M32 58 L32 30", "#4F8A2E", 3.6) + shape("M32 44 Q20 42 18 34 Q28 34 32 44 Z", "#7CC04C", "#3E7424")
    + "".join(circle(32 + 9 * c, 22 + 9 * s_, 7, "#F27A9A", "#A33A5C", 2.0) for c, s_ in
              [(1, 0), (0.31, 0.95), (-0.81, 0.59), (-0.81, -0.59), (0.31, -0.95)])
    + circle(32, 22, 5.5, "#F6C445", "#9E7414", 2.0))
ICONS["arrow_up"] = svg(shape("M32 8 L54 32 L40 32 L40 56 L24 56 L24 32 L10 32 Z", "#7CC04C", "#3E7424"))
ICONS["arrow_down"] = svg(shape("M32 56 L54 32 L40 32 L40 8 L24 8 L24 32 L10 32 Z", "#E8A24E", "#8A5A12"))
ICONS["move"] = svg(line("M32 8 L32 56 M8 32 L56 32", "#6B5B4D", 4.4)
    + "".join(shape(d, "#6B5B4D", "#6B5B4D", 'stroke-width="1.5"') for d in
              ["M32 4 L24 14 L40 14 Z", "M32 60 L24 50 L40 50 Z", "M4 32 L14 24 L14 40 Z", "M60 32 L50 24 L50 40 Z"]))
ICONS["trash"] = svg(shape("M16 18 L48 18 L44 58 L20 58 Z", "#E8E2D6", "#6B5B4D") + line("M10 16 L54 16 M26 10 L38 10", "#6B5B4D", 4.0)
    + line("M26 26 L27 50 M32 26 L32 50 M38 26 L37 50", "#B9AE9C", 3.0))
ICONS["map"] = svg(shape("M6 14 L22 8 L42 14 L58 8 L58 52 L42 58 L22 52 L6 58 Z", "#F3E7C8", "#7A6448")
    + line("M22 8 L22 52 M42 14 L42 58", "#C9B48A", 2.0) + line("M12 44 Q22 30 30 38 Q40 46 50 22", "#C4554A", 2.8)
    + circle(50, 22, 3.5, "#C4554A"))
ICONS["target"] = svg(circle(32, 32, 20, "none", "#6B5B4D", 4.0) + circle(32, 32, 6, "#6B5B4D")
    + line("M32 4 L32 14 M32 50 L32 60 M4 32 L14 32 M50 32 L60 32", "#6B5B4D", 4.0))
ICONS["eye_off"] = svg(shape("M6 32 Q32 8 58 32 Q32 56 6 32 Z", "#FFFFFF", "#6B5B4D") + circle(32, 32, 9, "#6B5B4D")
    + line("M12 52 L52 12", "#C4554A", 5.0))
# Значки меток (внутренний рисунок 0..64, его кладут в «каплю» pin()).
MARKER_ART = {
    "home": shape("M10 32 L32 12 L54 32", "#D06C49", "#6C2E1E") + shape("M16 30 L48 30 L48 56 L16 56 Z", "#E8C394", "#7A5634"),
    "star": shape("M32 6 L39 23 L57 24 L43 36 L48 54 L32 44 L16 54 L21 36 L7 24 L25 23 Z", "#F6C445", "#9E7414"),
    "flag": line("M18 58 L18 8", "#6B5B4D", 5.0) + shape("M18 8 L52 16 L18 30 Z", "#C4554A", "#7A2A22"),
    "tree": shape("M32 4 L52 40 L12 40 Z", "#4F8A3E", "#2F5A22") + shape("M28 40 L36 40 L36 58 L28 58 Z", "#8C5A34", "#5A361C"),
    "pick": line("M14 54 L46 22", "#7A4A28", 6.0) + shape("M30 10 Q52 8 58 32 Q48 18 30 18 Z", "#9AA1AD", "#4D535E"),
    "heart": shape("M32 56 Q8 38 10 22 Q12 10 24 10 Q30 10 32 18 Q34 10 40 10 Q52 10 54 22 Q56 38 32 56 Z", "#E8506A", "#8E2238"),
    "castle": shape("M10 58 L10 22 L18 22 L18 30 L26 30 L26 22 L38 22 L38 30 L46 30 L46 22 L54 22 L54 58 Z", "#A3A3A8", "#4D4D55")
              + shape("M28 58 L28 44 Q32 38 36 44 L36 58 Z", "#6B5B4D", "none"),
    "camp": shape("M8 56 L32 14 L56 56 Z", "#E8A24E", "#8A5A12") + shape("M26 56 L32 40 L38 56 Z", "#6B4A2A", "none"),
}
MARKER_COLORS = {"red": "#E05A4E", "orange": "#F09A3E", "yellow": "#F2C94C", "green": "#62B04E", "blue": "#4E8FD6", "purple": "#9B6BD8"}
for name, art in MARKER_ART.items():
    ICONS["marker_" + name] = svg(art)
ICONS["marker_pin"] = svg(pin(MARKER_ART["flag"], "#C9B8A6"))
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
ICONS["auto"] = svg(arc_arrow(32, 32, 24, -80, 200, "#8C7A68", 4.0, 9.0)
    + shape("M23 43 L32 19 L41 43 M26.5 35 L37.5 35", "none", "#8C7A68", 'stroke-width="4"'))

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


FLAME = ("M32 8 Q40 20 44 30 Q48 40 42 48 Q36 54 32 54 Q22 54 20 44 Q18 36 24 28 Q26 36 30 36 Q26 24 32 8 Z")
ICONS["cat_yard"] = svg(shape(FLAME, "#F59A3A", "#A34A12")
    + shape("M32 26 Q38 36 38 44 Q36 50 32 50 Q26 50 26 44 Q26 38 32 26 Z", "#FFD25E", "none")
    + shape("M10 56 L54 46 L56 52 L12 62 Z", "#9C6438", "#5A361C", 'stroke-width="2"')
    + shape("M54 56 L10 46 L8 52 L52 62 Z", "#B07B4E", "#5A361C", 'stroke-width="2"'))
ICONS["cat_garden"] = svg(shape("M8 44 L56 44 L52 56 L12 56 Z", "#8A5A36", "#4E301A")
    + line("M20 44 L20 30 M32 44 L32 24 M44 44 L44 30", "#4E8A2E", 3.0)
    + "".join(shape(f"M{x} {y} Q{x - 9} {y - 4} {x - 10} {y - 12} Q{x - 2} {y - 10} {x} {y} Z", "#7CC04C", "#3E7424", 'stroke-width="1.8"')
              + shape(f"M{x} {y} Q{x + 9} {y - 4} {x + 10} {y - 12} Q{x + 2} {y - 10} {x} {y} Z", "#98D06E", "#3E7424", 'stroke-width="1.8"')
              for x, y in [(20, 34), (32, 28), (44, 34)]))
ICONS["crop_wheat"] = svg(line("M32 60 L32 14", "#B68A2E", 3.0)
    + "".join(ellipse(32 + dx, y, 4, 7, "#E8C15A", "#9A6E1E", 1.8) for y in [16, 26, 36] for dx in [-6, 6])
    + ellipse(32, 9, 3.5, 6, "#E8C15A", "#9A6E1E", 1.8))
ICONS["crop_rice"] = svg(shape("M6 50 L58 50 L58 60 L6 60 Z", "#6FA5DD", "#3F6E9E", 'stroke-width="2"')
    + "".join(line(f"M{x} 52 Q{x - 2} 30 {x - 8} 14", "#5C9A3A", 3.0) + line(f"M{x} 52 Q{x + 3} 32 {x + 9} 18", "#7CC04C", 3.0) for x in [18, 32, 46]))
ICONS["crop_cabbage"] = svg(circle(32, 36, 20, "#A6D27A", "#4E7A2E") + shape("M14 34 Q20 18 32 16 Q26 26 28 40 Q20 42 14 34 Z", "#7CB84C", "#4E7A2E", 'stroke-width="2"')
    + shape("M50 34 Q44 18 32 16 Q38 26 36 40 Q44 42 50 34 Z", "#8CC45C", "#4E7A2E", 'stroke-width="2"') + circle(32, 38, 8, "#CBE6A6", "#6E9A4A", 2))
ICONS["crop_carrot"] = svg(shape("M24 22 L40 22 L33 60 Z", "#F08A2C", "#A34E12")
    + line("M28 32 L34 31 M29 42 L33 41", "#A34E12", 1.8)
    + shape("M32 22 Q26 10 22 6 Q30 8 32 18 Q34 8 42 6 Q38 12 32 22 Z", "#6DB04A", "#3E7424", 'stroke-width="2"'))
ICONS["crop_pumpkin"] = svg(ellipse(32, 38, 24, 18, "#F08A2C", "#A34E12") + ellipse(32, 38, 9, 18, "#F5A44C", "#A34E12", 2)
    + shape("M30 20 L32 10 L36 11 L34 21 Z", "#6B8A3A", "#3E5A1E", 'stroke-width="2"'))
ICONS["crop_sunflower"] = svg(line("M32 60 L32 30", "#5C9A3A", 3.4)
    + "".join(ellipse(32 + 13 * c, 24 + 13 * s, 5, 5, "#F6C445", "#B9851A", 1.8) for c, s in
              [(1, 0), (0.71, 0.71), (0, 1), (-0.71, 0.71), (-1, 0), (-0.71, -0.71), (0, -1), (0.71, -0.71)])
    + circle(32, 24, 9, "#6E4426", "#3E2414", 2))
ICONS["tree_apple"] = svg(line("M32 60 L32 36", "#7A4A28", 5.0)
    + shape("M32 8 Q46 10 50 22 Q56 30 50 38 Q44 46 32 42 Q20 46 14 38 Q8 30 14 22 Q18 10 32 8 Z", "#6DB04A", "#3E7424")
    + "".join(circle(x, y, 4.2, "#E0443A", "#8E1E16", 1.8) for x, y in [(24, 22), (40, 20), (34, 32), (20, 34), (44, 34)]))

ICONS["path_tiles"] = svg("".join(shape(f"M{x} {y} L{x + 14} {y} L{x + 14} {y + 14} L{x} {y + 14} Z", "#C9B8A6", "#6B5B4D", 'stroke-width="2.2"')
    for x, y in [(10, 40), (25, 40), (25, 25), (40, 25), (40, 10)]))
ICONS["path_smooth"] = svg(line("M10 54 Q14 34 30 32 Q48 30 54 10", "#6B5B4D", 15.0)
    + line("M10 54 Q14 34 30 32 Q48 30 54 10", "#C9B8A6", 10.0)
    + line("M10 54 Q14 34 30 32 Q48 30 54 10", "#E8DCCB", 2.4, 0.9))

os.makedirs(OUT, exist_ok=True)
for name, data in ICONS.items():
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(data)
print(f"{len(ICONS)} иконок → {os.path.normpath(OUT)}")
