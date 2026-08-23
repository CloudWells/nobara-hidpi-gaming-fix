#!/usr/bin/env bash
# Пересборка Xwayland с патчем против переполнения dotClock — на случай,
# если Нобара обновила пакет, а патч ещё не приняли.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
dnf download --source xorg-x11-server-Xwayland
sudo dnf -y builddep xorg-x11-server-Xwayland-*.src.rpm
rpm -i xorg-x11-server-Xwayland-*.src.rpm

cp "$HERE/patches/xwayland-cvt-avoid-dotclock-overflow.patch" ~/rpmbuild/SOURCES/
SPEC=~/rpmbuild/SPECS/xorg-x11-server-Xwayland.spec
grep -q dotclock "$SPEC" || \
  sed -i '/^Patch1:/a Patch2:    xwayland-cvt-avoid-dotclock-overflow.patch' "$SPEC"

rpmbuild -bb --nocheck --define "dist $(rpm -E %dist).dotclockfix" "$SPEC"
echo "Готово. Ставить: sudo dnf install ~/rpmbuild/RPMS/x86_64/xorg-x11-server-Xwayland-*dotclockfix*.rpm"
echo "Если патч не лёг (код изменился) — обнови контекст диффа по ISSUE.md."
