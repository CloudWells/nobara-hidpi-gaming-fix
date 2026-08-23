# nobara-hidpi-gaming-fix

Фиксы для мультимониторного HiDPI-гейминга на Nobara 44 (GNOME Wayland).
Разбор бага и математика: [ISSUE.md](ISSUE.md), апстрим-репорт:
[Nobara-Project/nobara-core-packages#133](https://github.com/Nobara-Project/nobara-core-packages/issues/133).

**Сетап:** Samsung Odyssey G81SF 4K@240 (основной) + 2× Xiaomi 1440p@180
(правый вертикальный), RTX 5070 Ti, NVIDIA 595.

## Что чинится

1. **X11/Proton-игры видят 19.92 Гц вместо 240** на 4K@240 при дробном масштабе —
   переполнение CARD32 dotClock в эмулированных RandR-режимах Xwayland.
   Патч: `patches/xwayland-cvt-avoid-dotclock-overflow.patch` (проверен: 19.92 → 239.96 Гц).
2. **mutter: дробный масштаб в физическом режиме раскладки** —
   экспериментальный патч, снимает валидацию (`patches/mutter-allow-fractional-scale-physical-layout.patch`).
   Итог исследования: рендер дробного масштаба в physical mode в mutter отсутствует,
   UI рисуется как 100% — патч оставлен как материал для GNOME, ставить не обязательно.
3. **Игры запускаются не на основном мониторе** — лечится геометрией:
   основной монитор должен быть единственным на верхней кромке (y=0) виртуального стола.

## Накатить фулл

```bash
# 1. Патченные пакеты (главный — Xwayland; mutter — опционально)
sudo dnf install rpms/xorg-x11-server-Xwayland-*.rpm
sudo dnf install rpms/mutter-*.rpm rpms/mutter-common-*.rpm   # опционально

# 2. Защита от затирания обновлением (до принятия патча в Нобару)
sudo dnf install python3-dnf-plugin-versionlock
sudo dnf versionlock add xorg-x11-server-Xwayland mutter mutter-common

# 3. Раскладка мониторов: Samsung 200% основной на верхней кромке,
#    Xiaomi 133% по бокам (правый вертикальный)
scripts/apply-layout.sh

# 4. Перезайти в сессию (или перезагрузиться)
```

После обновления Нобары до новой версии Xwayland/mutter — пересборка:

```bash
scripts/rebuild-xwayland.sh   # качает srpm, накладывает патч, собирает, ставит
```

## Проверка

```bash
DISPLAY=:0 xrandr   # у всех мониторов частоты должны быть честные (240/180),
                    # никаких ~20 Гц
```

## Раскладка (что делает apply-layout.sh)

| Монитор | Разрешение | Масштаб | Позиция |
|---|---|---|---|
| Xiaomi слева (DP-4) | 2560×1440@180 | 133.33% | (0, 60) |
| Samsung (DP-6), **основной** | 3840×2160@240 | 200% | (1920, 0) — верхняя кромка |
| Xiaomi справа (DP-5), вертикальный | 2560×1440@180 | 133.33% | (3840, 60) |

Сдвиг боковых на 60 логических пикселей вниз делает Samsung единственным
«верхним» монитором — туда и открываются игры (эвристика Wine/Proton,
см. Proton issues #720, #7717).
