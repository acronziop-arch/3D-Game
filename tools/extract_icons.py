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
from PIL import Image, ImageDraw, ImageFilter

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


## Маска строится в SCALE раз крупнее листа: края выходят гладкими, без «лесенки».
SCALE = 3
## Иконки, у которых внутри есть сквозные просветы.
OPEN_HOLES = {"auto"}
## Белые иконки (облака, шерсть): их светлый край — сам рисунок, его снимаем бережно.
WHITE_ICONS = {"weather_cloudy", "weather_overcast", "weather_rain", "weather_snow", "weather_storm",
               "weather_fog", "weather_blizzard", "weather_windy", "wool"}


def _grow(m, r):
    """Расширение маски на r пикселей (квадратное окно 3×3, r раз)."""
    im = Image.fromarray((m * 255).astype(np.uint8))
    for _ in range(r):
        im = im.filter(ImageFilter.MaxFilter(3))
    return np.asarray(im) > 127


def _shrink(m, r):
    return ~_grow(~m, r)


def _from_border(passable):
    """Пиксели passable, до которых можно дойти от края картинки."""
    h, w = passable.shape
    m = np.zeros((h + 2, w + 2), np.uint8)
    m[1:-1, 1:-1] = passable * 255
    m[0, :] = m[-1, :] = m[:, 0] = m[:, -1] = 255
    im = Image.fromarray(m).copy()
    ImageDraw.floodfill(im, (0, 0), 128, thresh=0)
    return np.asarray(im)[1:-1, 1:-1] == 128


def _components(mask):
    """Связные части маски (списком масок)."""
    im = Image.fromarray((mask * 255).astype(np.uint8)).copy()
    comps = []
    label = 1
    while label < 250:
        a = np.asarray(im)
        ys, xs = np.nonzero(a == 255)
        if len(ys) == 0:
            break
        ImageDraw.floodfill(im, (int(xs[0]), int(ys[0])), label, thresh=0)
        comps.append(np.asarray(im) == label)
        label += 1
    return comps


def matte(crop, bg, name=""):
    """Маска иконки без фона листа, его тени, белой каймы вокруг рисунка и белых
    звёздочек-бликов. Возвращает (rgb, alpha) в SCALE раз крупнее вырезки."""
    h, w, _ = crop.shape
    big = np.asarray(Image.fromarray(crop.clip(0, 255).astype(np.uint8)).resize((w * SCALE, h * SCALE), Image.BICUBIC)).astype(np.float32)
    H, W, _ = big.shape
    diff = big - bg
    dist = np.abs(diff).max(axis=2)
    lum = big.mean(axis=2)
    bg_lum = bg.mean()
    sat = big.max(axis=2) - big.min(axis=2)
    ys = np.nonzero((dist > 40).any(axis=1))[0]
    cy = ys.mean() if len(ys) else H / 2
    yy = np.arange(H)[:, None].repeat(W, axis=1)
    # 1. Фон, связанный с краем: цвет листа и серая тень под иконкой. Фон тёплый,
    #    а белые облака и шерсть — холодные: по этому их и различаем. Тень на листе
    #    размытая (яркость меняется плавно), а светлые стены и бока иконок отделены
    #    от фона резким краем — заливка тени на них не переходит.
    warm = (big[:, :, 0] - big[:, :, 2]) > (bg[0] - bg[2]) - 3.0
    near_bg = (dist < 8) & (diff[:, :, 2] < 5) & warm
    src = np.asarray(Image.fromarray(crop.mean(axis=2).clip(0, 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(1))).astype(np.float32)
    grad = np.zeros_like(src)
    grad[1:-1, :] = np.abs(src[2:, :] - src[:-2, :]) * 0.5
    grad[:, 1:-1] = np.maximum(grad[:, 1:-1], np.abs(src[:, 2:] - src[:, :-2]) * 0.5)
    grad = np.asarray(Image.fromarray(grad.clip(0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)).astype(np.float32)
    shadow_like = (lum < bg_lum - 2) & (lum > 170) & (sat < 18) & (grad < 6.5) & (yy > cy - H * 0.1)
    obj = ~_from_border(near_bg | shadow_like)
    # 2. Просветы внутри рисунка (между буквой и кольцом) — фон листа, окружённый
    #    иконкой: прозрачные. Только у иконок из OPEN_HOLES — у остальных такие же
    #    светлые места внутри — это сам рисунок (белые кольца мишени, облака).
    if name in OPEN_HOLES:
        area = obj.sum()
        for hole in _components(obj & near_bg):
            if hole.sum() > area * 0.012:
                obj &= ~_grow(hole, 1)
    # 3. Кайма по краю — снимаем слой за слоем снаружи внутрь:
    #    совсем белое (белее листа: звёздочки-блики, прилипшие к рисунку) — до 6 px листа;
    #    серая тень с листа, прилипшая снизу к рисунку, — до 4 px;
    #    светлый ореол и бледная обводка-«наклейка» — до 3 px.
    lower = yy > cy
    passes = [
        (6, (lum > bg_lum - 3) & (sat < 16)),
        (4, (lum > 185) & (lum < bg_lum - 2) & (sat < 14) & lower),
        (3, (lum > bg_lum - 14) & (sat < 26)),
        (2, (lum > bg_lum - 10) & (sat < 45)),
    ]
    if name in WHITE_ICONS:
        passes = passes[2:3]
    for depth, light in passes:
        for _ in range(depth * SCALE):
            peel = obj & _grow(~obj, 1) & light
            if not peel.any():
                break
            obj &= ~peel
    # 4. Отдельные кусочки: белые звёздочки-блики и обрывки подписей убираем,
    #    части рисунка (три точки, капли дождя, снежинки) оставляем.
    comps = _components(obj)
    if comps:
        largest = max(int(c.sum()) for c in comps)
        keep = np.zeros_like(obj)
        for c in comps:
            n = int(c.sum())
            pale = lum[c].mean() > bg_lum - 30 and sat[c].mean() < 34
            if n >= largest * 0.04 and not (pale and n < largest * 0.3):
                keep |= c
        obj = keep
    # 5. Цвет у самого края — из глубины рисунка, если край светлее (остатки фона).
    inner = _shrink(obj, 2 * SCALE)
    band = obj & ~inner
    col = np.where(inner[:, :, None], big, 0.0)
    known = inner.copy()
    for _ in range(2 * SCALE + 2):
        acc = np.zeros_like(big)
        cnt = np.zeros((H, W), np.float32)
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
            k = np.roll(known, (dy, dx), axis=(0, 1))
            c = np.roll(col, (dy, dx), axis=(0, 1))
            acc += c * k[:, :, None]
            cnt += k
        new = band & ~known & (cnt > 0)
        col[new] = acc[new] / cnt[new][:, None]
        known |= new
    rgb = big.copy()
    use = band & known & (lum > col.mean(axis=2) + 4)
    rgb[use] = col[use]
    return rgb, obj.astype(np.float32)


def save_icon(rgb, alpha, path, size=128):
    ys, xs = np.nonzero(alpha > 0.1)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([rgb, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
    side = int(max(img.size) * 1.12)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2))
    # Уменьшение с предумножением альфы (усреднение) — гладкий край без каймы.
    pre = np.asarray(canvas).astype(np.float32)
    pre[:, :, :3] *= pre[:, :, 3:4] / 255.0
    small = Image.fromarray(pre.clip(0, 255).astype(np.uint8), "RGBA").resize((size, size), Image.BOX)
    arr = np.asarray(small).astype(np.float32)
    a = arr[:, :, 3:4] / 255.0
    arr[:, :, :3] = np.where(a > 0.003, arr[:, :, :3] / np.maximum(a, 0.003), 0)
    out = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
    # Чёткость — только цвету: резкость по альфе дала бы светлый ореол.
    sharp = out.convert("RGB").filter(ImageFilter.UnsharpMask(radius=1.0, percent=55, threshold=2))
    out = Image.merge("RGBA", (*sharp.split(), out.getchannel("A")))
    finish(out).save(path)


def finish(out):
    """Мягкая тень: размытый силуэт чуть ниже рисунка."""
    size = out.size[0]
    sil = out.getchannel("A").point(lambda v: int(v * 0.32))
    shadow_a = Image.new("L", out.size, 0)
    shadow_a.paste(sil, (0, int(size * 0.035)))
    shadow_a = shadow_a.filter(ImageFilter.GaussianBlur(size * 0.03))
    shadow = Image.new("RGBA", out.size, (46, 36, 28, 0))
    shadow.putalpha(shadow_a)
    return Image.alpha_composite(shadow, out)


def badge_icon(base_path, out_path, up, color, size=128):
    """Иконка со значком в правом нижнем углу (как у «Стройки» — домик с плюсом):
    кружок цвета color с белой стрелкой вверх (up) или вниз."""
    s = 4
    n = size * s
    canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    base = Image.open(base_path).convert("RGBA").resize((int(n * 0.86), int(n * 0.86)), Image.LANCZOS)
    canvas.alpha_composite(base, (0, 0))
    d = int(n * 0.5)
    x0, y0 = n - d - 2 * s, n - d - 4 * s
    c = np.array(color, np.float32)
    dark = tuple(int(v) for v in c * 0.72)
    light = tuple(int(v) for v in np.minimum(c * 1.18 + 20, 255))
    shade = Image.new("L", (n, n), 0)
    ImageDraw.Draw(shade).ellipse((x0, y0 + 3 * s, x0 + d, y0 + d + 3 * s), fill=90)
    shade = shade.filter(ImageFilter.GaussianBlur(4 * s))
    shadow = Image.new("RGBA", (n, n), (46, 36, 28, 0))
    shadow.putalpha(shade)
    canvas.alpha_composite(shadow)
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((x0, y0, x0 + d, y0 + d), fill=(255, 255, 255, 255))
    rim = 3 * s
    draw.ellipse((x0 + rim, y0 + rim, x0 + d - rim, y0 + d - rim), fill=dark + (255,))
    draw.ellipse((x0 + rim + 2 * s, y0 + rim, x0 + d - rim - 2 * s, y0 + d - rim - 4 * s), fill=tuple(int(v) for v in c) + (255,))
    draw.ellipse((x0 + d * 0.3, y0 + rim + 2 * s, x0 + d * 0.7, y0 + d * 0.36), fill=light + (150,))
    # Белая стрелка: древко и наконечник.
    cx, cy = x0 + d / 2, y0 + d / 2
    w, head, length = d * 0.13, d * 0.25, d * 0.25
    sign = -1 if up else 1
    tip = cy + sign * length
    base_y = tip - sign * head
    draw.rectangle((cx - w, min(base_y, cy - sign * length), cx + w, max(base_y, cy - sign * length)), fill=(255, 255, 255, 255))
    draw.polygon([(cx, tip), (cx - head, base_y), (cx + head, base_y)], fill=(255, 255, 255, 255))
    canvas.resize((size, size), Image.LANCZOS).save(out_path)


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
            rgb, alpha = matte(crop, bg, name)
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
    # «Поделиться миром» и «Мир от друга» — свиток со значком-стрелкой.
    badge_icon(os.path.join(out, "scroll.png"), os.path.join(out, "share.png"), True, (92, 172, 74))
    badge_icon(os.path.join(out, "scroll.png"), os.path.join(out, "import.png"), False, (70, 138, 214))
    print("   share, import")
