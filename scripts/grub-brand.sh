#!/usr/bin/env bash
# Фирменное меню загрузки COLI Linux в готовом ISO:
#  - пункты меню «Ubuntu» -> «COLI Linux»
#  - фон isofs/boot/grub/coli-bg.png
#  - пересчёт md5sum.txt (проверка диска в меню не ругается)
# sudo не нужен. Запускать ПОСЛЕ сборки образа (build-ubuntu.sh all).
#
# Использование:
#   bash scripts/grub-brand.sh                      # build/coli.iso -> build/coli-grub.iso
#   bash scripts/grub-brand.sh вход.iso выход.iso
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IN="${1:-$ROOT/build/coli.iso}"
OUT="${2:-$ROOT/build/coli-grub.iso}"
BG="$ROOT/isofs/boot/grub/coli-bg.png"
WORK="$ROOT/build/grub-work"

die() { echo "ОШИБКА: $*" >&2; exit 1; }

command -v xorriso >/dev/null 2>&1 || die "нет xorriso (поставь: ./build.sh deps)"
command -v md5sum  >/dev/null 2>&1 || die "нет md5sum"
[ -s "$IN" ] || die "нет файла $IN (сначала собери образ: bash scripts/build-ubuntu.sh all)"
[ -s "$BG" ] || die "нет фона $BG (распакуй coli-grub.zip в корень репозитория)"
[ "$IN" != "$OUT" ] || die "входной и выходной файл должны отличаться"

rm -rf "$WORK"; mkdir -p "$WORK"

echo "==> Достаём файлы меню из $IN"
xorriso -osirrox on -indev "$IN" \
  -extract /boot/grub/grub.cfg "$WORK/grub.cfg" \
  -extract /boot/grub/loopback.cfg "$WORK/loopback.cfg" \
  -extract /md5sum.txt "$WORK/md5sum.txt" >/dev/null 2>&1 || true

[ -s "$WORK/grub.cfg" ] || die "не удалось достать /boot/grub/grub.cfg из образа"
chmod u+w "$WORK"/* 2>/dev/null || true

echo "==> Меняем названия пунктов и добавляем фон"
for f in grub.cfg loopback.cfg; do
  [ -s "$WORK/$f" ] || continue
  sed -i '/^[[:space:]]*menuentry /s/Ubuntu/COLI Linux/g' "$WORK/$f"
done

grep -q '^loadfont unicode' "$WORK/grub.cfg" \
  || die "в grub.cfg нет строки 'loadfont unicode': образ другой версии, пришли мне содержимое файла"

sed -i '/^loadfont unicode/a\
set gfxmode=auto\
insmod all_video\
insmod gfxterm\
insmod png\
terminal_output gfxterm\
background_color 5,7,13\
background_image -m normal /boot/grub/coli-bg.png' "$WORK/grub.cfg"
sed -i 's|black/light-gray|black/light-blue|' "$WORK/grub.cfg"

echo "==> Новый grub.cfg:"
sed -n '1,40p' "$WORK/grub.cfg"

# --- md5sum.txt ---
md5_set() {   # $1 путь внутри образа вида ./boot/grub/grub.cfg, $2 локальный файл
  local sum; sum="$(md5sum "$2" | cut -d' ' -f1)"
  if grep -q "  $1\$" "$WORK/md5sum.txt"; then
    sed -i "s|^[0-9a-f]\{32\}  $1\$|$sum  $1|" "$WORK/md5sum.txt"
  else
    echo "$sum  $1" >> "$WORK/md5sum.txt"
  fi
}

args=(-map "$WORK/grub.cfg" /boot/grub/grub.cfg
      -map "$BG" /boot/grub/coli-bg.png)
[ -s "$WORK/loopback.cfg" ] && args+=(-map "$WORK/loopback.cfg" /boot/grub/loopback.cfg)

if [ -s "$WORK/md5sum.txt" ]; then
  md5_set ./boot/grub/grub.cfg "$WORK/grub.cfg"
  md5_set ./boot/grub/coli-bg.png "$BG"
  [ -s "$WORK/loopback.cfg" ] && md5_set ./boot/grub/loopback.cfg "$WORK/loopback.cfg"
  args+=(-map "$WORK/md5sum.txt" /md5sum.txt)
  echo "==> md5sum.txt обновлён"
else
  echo "!! md5sum.txt не найден: проверка диска в меню покажет ошибку (на загрузку не влияет)"
fi

echo "==> Собираем $OUT"
rm -f "$OUT"
xorriso -indev "$IN" -outdev "$OUT" \
  -boot_image any replay -overwrite on \
  "${args[@]}" -commit

echo "==> Проверка: файлы в новом образе"
xorriso -indev "$OUT" -lsl /boot/grub/grub.cfg /boot/grub/coli-bg.png 2>&1 | grep '/boot/grub/'
ls -lh "$OUT"
echo "==> Готово: $OUT"
echo "    Запусти его в виртуалке: меню должно называться COLI Linux, внизу логотип."
