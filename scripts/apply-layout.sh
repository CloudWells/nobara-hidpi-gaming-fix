#!/usr/bin/env bash
# Samsung 200% основной на верхней кромке, Xiaomi 133% по бокам (правый вертикальный).
set -euo pipefail
gdctl set -P \
  -L -M DP-4 -m 2560x1440@180.000 -x 0 -y 60 -s 1.3333333730697632 \
  -L -M DP-6 -m 3840x2160@239.996 -x 1920 -y 0 -s 2 -p \
  -L -M DP-5 -m 2560x1440@180.000 -x 3840 -y 60 -s 1.3333333730697632 -t 270
echo "OK. Проверка: DISPLAY=:0 xrandr | grep -E 'connected|\*'"
