#!/usr/bin/env bash
# COLI Linux — сборка на базе Ubuntu 26.10 (слоистый образ)
#
# Кладётся в репозиторий: ~/coli-linux/scripts/build-ubuntu.sh
# Нужен образ Ubuntu Desktop: ~/coli-linux/build/ubuntu.iso
#
# Использование:
#   bash scripts/build-ubuntu.sh unpack    # 1) достать слой из ISO и распаковать
#   bash scripts/build-ubuntu.sh overlay   # 2) наложить rootfs/
#   bash scripts/build-ubuntu.sh pack      # 3) собрать слой и новый ISO
#   bash scripts/build-ubuntu.sh all       # все три шага подряд (по умолчанию)
#   bash scripts/build-ubuntu.sh clean     # удалить рабочие файлы (освободить место)
#
# Переменные (необязательно): ISO=путь/к/образу.iso  OUT=путь/к/coli.iso  NEED_GB=30
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
ISO="${ISO:-$BUILD/ubuntu.iso}"
OUT="${OUT:-$BUILD/coli.iso}"
LAYER="minimal.squashfs"          # базовый слой: есть в Live и во всех установках
WORK="$BUILD/ubuntu-work"
LROOT="$WORK/layer-root"
NEED_GB="${NEED_GB:-30}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

die() { echo "ОШИБКА: $*" >&2; exit 1; }

preflight() {
  for c in xorriso unsquashfs mksquashfs rsync md5sum; do
    command -v "$c" >/dev/null 2>&1 || die "нет программы $c (поставь: ./build.sh deps)"
  done
  [ -s "$ISO" ] || die "нет файла $ISO или он пустой"
  mkdir -p "$BUILD" "$WORK"

  local info
  info="$(xorriso -indev "$ISO" -lsl "/casper/$LAYER" 2>&1 || true)"
  echo "$info" | grep -i 'Volume id' || true
  echo "$info" | grep -q "/casper/$LAYER" \
    || die "в образе нет /casper/$LAYER — это точно Ubuntu Desktop 26.10?"

  local free
  free="$(df -BG --output=avail "$BUILD" | tail -1 | tr -dc '0-9')"
  [ "${free:-0}" -ge "$NEED_GB" ] \
    || die "мало места: свободно ${free:-0} ГБ, нужно хотя бы $NEED_GB ГБ"
  echo "==> Проверки пройдены (свободно ${free} ГБ)"

  if [ -n "$SUDO" ]; then $SUDO -v; fi
}

step_unpack() {
  echo "==> [1/3] Достаём $LAYER из ISO"
  rm -f "$WORK/$LAYER"
  xorriso -osirrox on -indev "$ISO" -extract "/casper/$LAYER" "$WORK/$LAYER"
  [ -s "$WORK/$LAYER" ] || die "слой не извлёкся"
  ls -lh "$WORK/$LAYER"

  echo "==> Параметры сжатия слоя (запоминаем, чтобы собрать так же):"
  unsquashfs -s "$WORK/$LAYER" | grep -E '^(Compression|Block size)'

  echo "==> Распаковываем (несколько минут)"
  $SUDO rm -rf "$LROOT"
  $SUDO unsquashfs -d "$LROOT" "$WORK/$LAYER"
  [ -d "$LROOT/usr" ] || die "после распаковки нет папки usr — что-то пошло не так"
  echo "==> Готово: $($SUDO du -sh "$LROOT" | cut -f1) в $LROOT"
}

step_overlay() {
  echo "==> [2/3] Накладываем rootfs/"
  [ -d "$LROOT/usr" ] || die "сначала выполни шаг unpack"

  local files
  files="$(cd "$ROOT/rootfs" && find . -type f ! -name .gitkeep | sort)"
  if [ -z "$files" ]; then
    echo "!! В rootfs/ пока пусто, кроме .gitkeep: образ останется без изменений"
  else
    echo "$files" | head -50
  fi

  # владелец root:root, группа и остальные без права записи; бит запуска сохраняется
  $SUDO rsync -a --chown=root:root --chmod=go-w \
    --exclude .gitkeep "$ROOT/rootfs/" "$LROOT/"
  echo "==> rootfs/ наложен"
}

step_pack() {
  echo "==> [3/3] Собираем слой и ISO"
  [ -d "$LROOT/usr" ] || die "сначала выполни шаги unpack и overlay"
  [ -s "$WORK/$LAYER" ] || die "нет исходного слоя $WORK/$LAYER (шаг unpack)"

  local comp bs new newmd5
  comp="$(unsquashfs -s "$WORK/$LAYER" | awk '/^Compression/ {print $2}')"
  bs="$(unsquashfs -s "$WORK/$LAYER" | awk '/^Block size/ {print $3}')"
  [ -n "$comp" ] && [ -n "$bs" ] || die "не удалось определить сжатие слоя"
  echo "==> Сжатие: $comp, блок: $bs"

  new="$WORK/$LAYER.new"
  $SUDO rm -f "$new"
  $SUDO mksquashfs "$LROOT" "$new" -comp "$comp" -b "$bs" -noappend
  [ -s "$new" ] || die "mksquashfs не создал файл"

  # обновляем md5sum.txt, чтобы проверка диска в меню загрузки не ругалась
  local extra=()
  rm -f "$WORK/md5sum.txt"
  xorriso -osirrox on -indev "$ISO" -extract /md5sum.txt "$WORK/md5sum.txt" >/dev/null 2>&1 || true
  if [ -s "$WORK/md5sum.txt" ] && grep -q "  ./casper/$LAYER\$" "$WORK/md5sum.txt"; then
    newmd5="$(md5sum "$new" | cut -d' ' -f1)"
    chmod u+w "$WORK/md5sum.txt"
    sed -i "s|^[0-9a-f]\{32\}  \./casper/$LAYER\$|$newmd5  ./casper/$LAYER|" "$WORK/md5sum.txt"
    extra=(-map "$WORK/md5sum.txt" /md5sum.txt)
    echo "==> md5sum.txt обновлён"
  else
    echo "!! Строка слоя в md5sum.txt не найдена: проверка диска покажет ошибку (это не мешает загрузке)"
  fi

  rm -f "$OUT"
  xorriso -indev "$ISO" -outdev "$OUT" \
    -boot_image any replay -overwrite on \
    -map "$new" "/casper/$LAYER" \
    ${extra[@]+"${extra[@]}"} -commit

  echo "==> Проверка: слой внутри нового ISO и на диске должны совпасть по размеру"
  xorriso -indev "$OUT" -lsl "/casper/$LAYER" 2>&1 | grep "/casper/$LAYER"
  ls -l "$new"
  ls -lh "$OUT"
  echo "==> Готово: $OUT"
  echo "    Запусти его в виртуалке и проверь логотип и обои."
}

step_clean() {
  echo "==> Удаляем рабочие файлы: $WORK"
  $SUDO rm -rf "$WORK"
}

case "${1:-all}" in
  unpack)  preflight; step_unpack ;;
  overlay) preflight; step_overlay ;;
  pack)    preflight; step_pack ;;
  all)     preflight; step_unpack; step_overlay; step_pack ;;
  clean)   step_clean ;;
  *)       die "использование: bash $0 [unpack|overlay|pack|all|clean]" ;;
esac
