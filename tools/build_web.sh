#!/bin/bash
# Сборка браузерной версии в web/:
#   web/index.*     — обычная сборка движка (без потоков) и общие данные игры index.pck;
#   web/mt/index.*  — многопоточная сборка движка (те же данные игры из web/index.pck);
#   web/coi.sw.js   — помощник, который даёт странице «изоляцию» для потоков.
# Какую сборку запустить, страница решает сама (см. tools/web_shell.html).
# Запуск из папки проекта: bash tools/build_web.sh
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}

"$GODOT" --headless --path . --export-release "Web" web/index.html
mkdir -p web/mt
"$GODOT" --headless --path . --export-release "Web Threads" web/mt/index.html
# От многопоточной сборки нужен только сам движок: страница и данные игры — общие.
rm -f web/mt/index.html web/mt/index.pck web/mt/index.png web/mt/index.icon.png web/mt/index.apple-touch-icon.png
cp tools/web_coi_sw.js web/coi.sw.js

# Размер движка многопоточной сборки — для полосы загрузки.
python3 - <<'PY'
import os, re
size = os.path.getsize("web/mt/index.wasm")
path = "web/index.html"
html = open(path, encoding="utf-8").read()
html = re.sub(r'"fileSizes":\{("mt/index\.wasm":\d+,)?', '"fileSizes":{"mt/index.wasm":%d,' % size, html, count=1)
open(path, "w", encoding="utf-8").write(html)
print("web/index.html: mt/index.wasm =", size)
PY
