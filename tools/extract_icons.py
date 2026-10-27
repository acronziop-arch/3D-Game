#!/usr/bin/env python3
"""Иконки интерфейса — объёмные «игровые» картинки с двух листов в tools/icon_sheets.
Скрипт вырезает каждую иконку, убирает фон, добавляет ровную мягкую тень и
сохраняет PNG 128×128 в assets/icons. Почти все иконки берутся со второго листа,
несколько (FROM_SHEET1) — с первого, где они нарисованы точнее.

Запуск из папки проекта:
  python3 -I tools/extract_icons.py tools/icon_sheets/sheet1.jpg tools/icon_sheets/sheet2.jpg assets/icons
Нужны Python 3, numpy и Pillow.
"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter

NAMES = """arrow arrow_down arrow_up auto brick cat_decor cat_defense cat_garden cat_housing cat_production
cat_special cat_water cat_yard check clay clock_day clock_night close cloth coal
copper_ingot copper_ore crop_cabbage crop_carrot crop_pumpkin crop_rice crop_sunflower crop_wheat cross day
eye_off flower glass grass_short grass_tall hide iron_ingot iron_ore leather log
map marker_camp marker_castle marker_flag marker_heart marker_home marker_pick marker_pin marker_star marker_tree
minus more move mow night path_smooth path_tiles plank plus rotate
sand season_autumn season_spring season_summer season_winter settings stone stone_block target timer
tool_build tool_craft tool_demolish tool_edit tool_flatten tool_harvest tool_nature trash tree_apple warning
wax weather_blizzard weather_clear weather_cloudy weather_fog weather_overcast weather_rain weather_snow weather_storm weather_windy""".split("\n")
ROWS = [r.split() for r in NAMES]
# Со второго листа почти всё; с первого — то, что там нарисовано правильнее.
FROM_SHEET1 = {"cat_decor", "cat_defense", "cat_production", "tool_demolish"}
EXTRA_SHEET1 = ["wool", "help", "scroll", "compass", "lantern", "potion", "flower_pot", "house_blue"]


def load(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    bg = np.median(np.concatenate([im[:3].reshape(-1, 3), im[-3:].reshape(-1, 3), im[:, :3].reshape(-1, 3)]), axis=0)
    return im, bg


def bands(proj, thr, minlen, merge=0):
    out = []
    on = False
    for i, v in enumerate(proj):
        if v > thr and not on:
            start = i
            on = True
        elif v <= thr and on:
            out.append([start, i])
            on = False
    if on:
        out.append([start, len(proj)])
    merged = []
    for b in out:
        if merged and b[0] - merged[-1][1] <= merge:
            merged[-1][1] = b[1]
        else:
            merged.append(b)
    return [b for b in merged if b[1] - b[0] >= minlen]


def _dilate(m, r):
    out = m.copy()
    for _ in range(r):
        g = out.copy()
        g[1:, :] |= out[:-1, :]
        g[:-1, :] |= out[1:, :]
        g[:, 1:] |= out[:, :-1]
        g[:, :-1] |= out[:, 1:]
        out = g
    return out


def _erode(m, r):
    return ~_dilate(~m, r)


def matte(crop, bg):
    """Альфа: фон, связанный с краем, — прозрачный; мягкая тень под иконкой — полупрозрачная тёмная."""
    h, w, _ = crop.shape
    diff = crop - bg
    dist = np.abs(diff).max(axis=2)
    lum = crop.mean(axis=2)
    bg_lum = bg.mean()
    sat = crop.max(axis=2) - crop.min(axis=2)
    strong = dist > 40
    ys = np.nonzero(strong.any(axis=1))[0]
    cy = ys.mean() if len(ys) else h / 2
    yy = np.arange(h)[:, None].repeat(w, axis=1)
    # Фон тёплый (жёлтоватый), а белые облака и шерсть — холодные: по этому их и различаем.
    warm = (crop[:, :, 0] - crop[:, :, 2]) > (bg[0] - bg[2]) - 3.0
    near_bg = (dist < 13) & (diff[:, :, 2] < 5) & warm
    shadow_like = (lum < bg_lum - 3) & (lum > 175) & (sat < 16) & (yy > cy)
    passable = near_bg | shadow_like
    region = np.zeros((h, w), bool)
    region[0, :] = passable[0, :]
    region[-1, :] = passable[-1, :]
    region[:, 0] = passable[:, 0]
    region[:, -1] = passable[:, -1]
    for _ in range(400):
        grown = region.copy()
        grown[1:, :] |= region[:-1, :]
        grown[:-1, :] |= region[1:, :]
        grown[:, 1:] |= region[:, :-1]
        grown[:, :-1] |= region[:, 1:]
        grown &= passable
        if (grown == region).all():
            break
        region = grown
    alpha = np.ones((h, w), np.float32)
    rgb = crop.copy()
    # Тень: чем темнее, тем плотнее; цвет — тёплый тёмный.
    shade = np.clip((bg_lum - lum) / 70.0, 0.0, 1.0) * 0.75
    alpha[region] = 0.0
    rgb[region] = np.array([46, 38, 30], np.float32)
    # Кромка иконки (1–2 px у фона): частичная прозрачность и очистка от светлого ореола.
    edge = np.zeros((h, w), bool)
    for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
        shifted = np.zeros((h, w), bool)
        shifted[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = region[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
        edge |= shifted
    edge &= ~region
    # Внутренние «дыры» — фон, до которого от края не добраться, если закрыть
    # узкие щели (так просачивается белое облако). Выемки по контуру не трогаем.
    closed = _erode(_dilate(~region, 3), 3)
    open_bg = region & ~closed
    reach = np.zeros((h, w), bool)
    reach[0, :] = open_bg[0, :]
    reach[-1, :] = open_bg[-1, :]
    reach[:, 0] = open_bg[:, 0]
    reach[:, -1] = open_bg[:, -1]
    for _ in range(400):
        g = _dilate(reach, 1) & open_bg
        if (g == reach).all():
            break
        reach = g
    holes = open_bg & ~reach
    alpha[holes] = 1.0
    rgb[holes] = crop[holes]
    region = region & ~holes
    edge &= ~holes
    a_edge = np.clip(dist / 80.0, 0.25, 1.0)
    alpha[edge] = a_edge[edge]
    un = (crop - (1.0 - a_edge[:, :, None]) * bg) / a_edge[:, :, None]
    rgb[edge] = np.clip(un[edge], 0, 255)
    return rgb, alpha


def keep_main(alpha):
    """Оставляет только основной рисунок: всё, что не связано с ним (обрывки подписей), убирается."""
    from collections import deque
    h, w = alpha.shape
    solid = alpha > 0.05
    seen = np.zeros((h, w), bool)
    comps = []
    for y0 in range(h):
        for x0 in range(w):
            if not solid[y0, x0] or seen[y0, x0]:
                continue
            comp = []
            q = deque([(y0, x0)])
            seen[y0, x0] = True
            while q:
                y, x = q.popleft()
                comp.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            comps.append(comp)
    largest = max(len(c) for c in comps)
    keep = np.zeros((h, w), bool)
    # Несколько частей рисунка (три точки, капли дождя) остаются; мелкие обрывки — нет.
    for comp in comps:
        if len(comp) >= largest * 0.05:
            for y, x in comp:
                keep[y, x] = True
    return np.where(keep, alpha, 0.0)


def save_icon(rgb, alpha, path, size=128):
    alpha = keep_main(alpha)
    ys, xs = np.nonzero(alpha > 0.1)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([rgb, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
    side = int(max(img.size) * 1.12)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2))
    # Масштаб с предумножением альфы — без тёмной или светлой каймы.
    pre = np.asarray(canvas).astype(np.float32)
    pre[:, :, :3] *= pre[:, :, 3:4] / 255.0
    big = Image.fromarray(pre.clip(0, 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)
    arr = np.asarray(big).astype(np.float32)
    a = arr[:, :, 3:4] / 255.0
    arr[:, :, :3] = np.where(a > 0.003, arr[:, :, :3] / np.maximum(a, 0.003), 0)
    out = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
    out = out.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    # Мягкая тень: размытый силуэт чуть ниже рисунка.
    sil = out.getchannel("A").point(lambda v: int(v * 0.32))
    shadow_a = Image.new("L", out.size, 0)
    shadow_a.paste(sil, (0, int(size * 0.035)))
    shadow_a = shadow_a.filter(ImageFilter.GaussianBlur(size * 0.03))
    shadow = Image.new("RGBA", out.size, (46, 36, 28, 0))
    shadow.putalpha(shadow_a)
    final = Image.alpha_composite(shadow, out)
    final.save(path)


def icons_in_band(im, bg, y0, y1, expected):
    region = im[y0:y1]
    dist = np.abs(region - bg).max(axis=2)
    proj = (dist > 40).sum(axis=0)
    segs = bands(proj, 1, 8, merge=14)
    if len(segs) != expected:
        print("  band", y0, y1, "segments", len(segs), "expected", expected, segs)
    return segs


def run(sheet_path, rows, pick, out_dir, label_cut, row_bands):
    im, bg = load(sheet_path)
    print(sheet_path, "bg", bg)
    for r, names in enumerate(rows):
        if r >= len(row_bands):
            break
        y0, y1 = row_bands[r]
        y1i = y1 - label_cut
        segs = icons_in_band(im, bg, y0, y1i, len(names))
        for i, name in enumerate(names):
            if name not in pick or i >= len(segs):
                continue
            x0, x1 = segs[i]
            cx0 = max(0, x0 - 14)
            cx1 = min(im.shape[1], x1 + 14)
            cy0 = max(0, y0 - 8)
            cy1 = min(im.shape[0], y1i + (4 if label_cut == 0 else 2))
            crop = im[cy0:cy1, cx0:cx1]
            rgb, alpha = matte(crop, bg)
            save_icon(rgb, alpha, os.path.join(out_dir, name + ".png"))
            print("  ", name)


if __name__ == "__main__":
    s1, s2, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    all_names = {n for row in ROWS for n in row}
    # Лист 2: строки иконок отделены от подписей.
    bands2 = [(14, 98), (144, 225), (269, 352), (392, 480), (518, 608), (653, 726), (761, 844), (889, 970), (1006, 1088), (1124, 1162)]
    run(s2, ROWS + [["wool"]], (all_names - FROM_SHEET1) | {"wool"}, out, 0, bands2)
    bands1 = [(4, 94), (99, 192), (197, 290), (293, 388), (392, 490), (498, 581), (585, 676), (683, 769), (773, 862), (865, 960)]
    run(s1, ROWS + [EXTRA_SHEET1], FROM_SHEET1 | set(EXTRA_SHEET1) - {"wool"}, out, 15, bands1)
