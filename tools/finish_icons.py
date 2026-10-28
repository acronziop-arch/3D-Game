#!/usr/bin/env python3
"""Доделывает иконки, снятые tools/render_icons.gd: обрезает по рисунку, уменьшает
до 128×128 и добавляет такую же мягкую тень, как у иконок с листов (extract_icons.py).

Запуск из папки проекта:
  python3 -I tools/finish_icons.py <папка со снимками> assets/icons
"""
import os, sys
import numpy as np
from PIL import Image, ImageEnhance

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_icons import save_icon


def main(src, dst):
    for name in sorted(os.listdir(src)):
        if not name.endswith(".png"):
            continue
        im = Image.open(os.path.join(src, name)).convert("RGBA")
        # Сочнее и контрастнее — в тон глянцевым иконкам с листов.
        rgb = ImageEnhance.Color(im.convert("RGB")).enhance(1.35)
        rgb = ImageEnhance.Contrast(rgb).enhance(1.18)
        arr = np.dstack([np.asarray(rgb), np.asarray(im.getchannel("A"))]).astype(np.float32)
        save_icon(arr[:, :, :3], arr[:, :, 3] / 255.0, os.path.join(dst, name))
        print(name)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
