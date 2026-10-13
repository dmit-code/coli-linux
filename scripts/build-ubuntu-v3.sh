#!/usr/bin/env bash
# COLI Linux — сборка на базе Ubuntu 26.10 (слоистый образ)
#
# Кладётся в репозиторий: ~/coli-linux/scripts/build-ubuntu.sh
# Нужен образ Ubuntu Desktop: ~/coli-linux/build/ubuntu.iso
#
# Использование:
#   bash scripts/build-ubuntu.sh unpack    # 1) достать слой из ISO и распаковать
#   bash scripts/build-ubuntu.sh overlay   # 2) наложить rootfs/, обои COLI, иконки COLI, логотип в «О системе»
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

  # Обои: убираем обои Ubuntu из списка выбора и добавляем COLI.
  # Сами картинки Ubuntu не удаляем: на одну из них может ссылаться настройка по умолчанию.
  local wpdir="$LROOT/usr/share/backgrounds/coli"
  local xmldir="$LROOT/usr/share/gnome-background-properties"
  if ls "$wpdir"/*.png >/dev/null 2>&1; then
    $SUDO mkdir -p "$xmldir"
    $SUDO find "$xmldir" -maxdepth 1 -name '*.xml' ! -name 'coli-*' -delete
    {
      echo '<?xml version="1.0"?>'
      echo '<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">'
      echo '<wallpapers>'
      local f b
      for f in "$wpdir"/*.png; do
        b="$(basename "$f")"
        if [ "$b" = "wallpaper.png" ]; then continue; fi   # это копия обоев по умолчанию
        echo '  <wallpaper deleted="false">'
        echo "    <name>COLI Linux - ${b%.png}</name>"
        echo "    <filename>/usr/share/backgrounds/coli/$b</filename>"
        echo "    <filename-dark>/usr/share/backgrounds/coli/$b</filename-dark>"
        echo '    <options>zoom</options>'
        echo '    <shade_type>solid</shade_type>'
        echo '    <pcolor>#05070D</pcolor>'
        echo '    <scolor>#05070D</scolor>'
        echo '  </wallpaper>'
      done
      echo '</wallpapers>'
    } | $SUDO tee "$xmldir/coli-wallpapers.xml" >/dev/null
    echo "==> Список выбора обоев: только COLI"
  else
    echo "!! В rootfs/usr/share/backgrounds/coli/ нет PNG: список обоев Ubuntu не трогаем"
  fi

  install_icons
}

# --- иконки COLI (встроены в скрипт; файлы из rootfs/ имеют приоритет) ---
write_icon_color_svg() {
cat <<'EOF_ICON_COLOR'
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#11275E"/>
      <stop offset="1" stop-color="#070C1C"/>
    </linearGradient>
  </defs>
  <rect x="20" y="20" width="472" height="472" rx="106" fill="url(#bg)"/>
  <rect x="21" y="21" width="470" height="470" rx="105" fill="none" stroke="#78AAFF" stroke-opacity="0.27" stroke-width="2"/>
  <path fill="#2F6BFF" fill-rule="evenodd" d="M144.1 387.8 L144.3 388.9 L157.3 399.0 L172.6 408.7 L183.8 414.4 L202.6 421.9 L224.5 427.5 L249.2 430.4 L275.2 429.7 L297.0 426.1 L315.4 420.4 L310.7 406.3 L295.9 410.9 L276.7 414.5 L260.2 415.6 L236.3 414.5 L211.6 409.4 L190.2 401.4 L170.4 390.6 L152.9 377.4 L151.4 378.3ZM429.9 279.8 L415.8 276.8 L414.9 277.2 L412.3 292.4 L407.2 309.6 L400.8 324.8 L391.9 341.0 L384.0 352.4 L373.8 364.4 L361.0 376.9 L345.2 388.8 L354.7 399.7 L356.2 399.9 L366.3 392.4 L384.5 375.6 L396.1 362.1 L406.3 347.2 L415.3 330.8 L423.1 311.2 L427.7 295.3 L429.7 284.7ZM104.8 171.2 L94.7 192.0 L86.9 218.0 L83.4 241.0 L83.2 268.3 L84.7 282.1 L87.6 297.0 L94.9 320.2 L105.7 342.7 L114.8 356.6 L115.9 356.6 L126.2 351.3 L127.3 350.0 L120.9 340.8 L114.3 329.3 L105.5 309.2 L99.8 288.9 L96.7 266.6 L96.7 244.8 L99.8 222.4 L106.4 199.7 L110.4 190.0 L116.5 178.3 L115.6 176.8ZM156.9 113.2 L163.7 123.4 L165.1 124.3 L175.2 117.8 L187.4 111.2 L209.4 102.6 L229.5 97.8 L251.6 95.8 L269.9 96.2 L289.5 98.9 L305.7 103.3 L322.4 109.7 L339.0 118.5 L350.0 125.8 L361.7 135.1 L376.7 150.1 L392.0 170.6 L402.3 189.6 L410.1 210.7 L413.3 223.1 L415.3 235.7 L416.4 236.1 L430.4 232.6 L429.2 223.3 L426.1 210.1 L418.2 187.4 L408.0 167.3 L394.1 147.0 L378.0 129.5 L360.6 114.8 L344.1 104.2 L326.6 95.5 L306.5 88.1 L283.8 83.2 L263.3 81.4 L246.5 81.6 L236.1 82.5 L210.8 87.4 L197.3 91.8 L174.8 101.9Z"/>
  <path fill="#5AA9FF" fill-rule="evenodd" d="M120.5 263.5 L122.3 280.5 L127.6 300.3 L165.5 325.7 L164.9 326.4 L136.0 319.5 L142.1 330.1 L147.9 338.3 L162.2 354.0 L195.8 352.2 L216.7 349.1 L228.0 346.1 L191.6 332.8 L173.7 318.2 L153.1 299.0 L140.1 285.6ZM340.3 232.0 L340.1 234.4 L347.2 269.7 L346.5 277.0 L342.1 302.4 L335.5 330.2 L328.2 354.2 L319.8 376.7 L337.4 365.9 L349.3 356.0 L351.8 353.1 L354.4 297.3 L355.5 296.4 L356.0 296.8 L367.0 334.6 L367.7 334.8 L373.2 326.8 L379.6 314.9 L386.9 296.2 L384.0 290.0 L376.7 278.3 L362.2 257.5 L350.9 243.2ZM176.3 217.6 L173.2 227.5 L171.2 244.5 L171.7 257.8 L173.2 267.3 L175.4 275.6 L179.7 286.7 L184.0 294.6 L196.2 310.3 L207.9 320.5 L208.3 320.0 L200.4 302.6 L200.6 301.2 L224.2 312.9 L245.9 344.1 L238.8 296.2 L224.4 284.0 L217.2 276.8 L206.1 263.9 L190.0 241.0 L177.0 217.8ZM325.1 217.2 L309.2 244.3 L294.4 265.0 L279.2 281.8 L262.6 296.2 L255.5 344.0 L277.2 312.9 L300.8 301.2 L301.2 301.9 L293.1 319.8 L293.7 320.2 L307.7 307.4 L314.7 298.6 L319.5 290.9 L326.0 275.6 L329.7 258.0 L330.2 244.1 L329.5 235.3 L327.5 224.5ZM332.1 142.1 L324.0 136.8 L314.1 131.7 L301.9 126.7 L292.6 124.2 L230.6 155.1 L230.2 154.1 L262.8 119.4 L245.9 119.4 L234.6 120.7 L215.6 125.3 L214.5 126.0 L206.4 140.3 L195.5 163.3 L186.1 187.4 L182.9 199.7 L212.8 173.9 L228.8 167.3 L259.5 157.1 L284.2 150.5 L308.3 145.4Z"/>
  <path fill="#FFFFFF" fill-rule="evenodd" d="M328.2 312.5 L324.0 317.8 L314.1 327.7 L304.1 335.5 L290.9 343.8 L269.9 353.8 L249.1 361.0 L232.4 365.3 L209.0 369.4 L184.9 371.6 L192.9 376.5 L203.7 381.6 L219.6 386.9 L280.1 358.6 L280.0 359.9 L241.2 391.1 L252.0 392.2 L267.5 391.9 L279.8 390.4 L290.7 388.0 L292.0 387.1 L299.0 375.4 L313.6 347.2ZM260.6 169.0 L276.7 172.3 L291.8 177.9 L312.7 189.4 L327.9 200.2 L347.8 217.6 L362.2 232.2 L381.1 254.5 L391.3 268.6 L392.4 268.8 L392.8 245.8 L389.7 225.6 L329.9 187.2 L330.2 186.5 L382.9 205.0 L380.3 197.9 L373.2 184.5 L364.4 171.9 L357.1 163.3 L342.3 162.4 L314.0 163.1 L280.7 165.9ZM188.7 137.3 L173.2 147.6 L163.1 156.2 L156.0 163.7 L149.4 228.2 L148.3 228.4 L142.1 182.7 L141.3 182.3 L137.0 189.6 L128.7 207.5 L124.5 220.9 L122.3 230.9 L128.0 241.6 L139.9 260.6 L150.7 276.3 L164.0 293.5 L159.3 277.4 L157.1 261.9 L157.1 239.4 L158.7 224.0 L162.9 202.8 L168.6 183.6 L175.0 166.2Z"/>
</svg>
EOF_ICON_COLOR
}

write_icon_symbolic_svg() {
cat <<'EOF_ICON_SYM'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path fill="#2e3436" fill-rule="evenodd" d="M3.16 13.49 L3.19 13.64 L3.78 14.11 L4.48 14.55 L4.99 14.80 L5.58 15.04 L6.64 15.32 L7.72 15.45 L8.80 15.42 L9.31 15.35 L10.01 15.20 L10.51 15.05 L10.62 14.96 L10.64 14.91 L10.64 14.82 L10.46 14.28 L10.33 14.15 L10.22 14.15 L9.49 14.37 L8.86 14.48 L8.18 14.53 L7.46 14.51 L6.55 14.37 L6.11 14.25 L5.54 14.05 L4.65 13.59 L4.14 13.26 L3.73 12.94 L3.58 12.95ZM11.02 10.36 L10.85 10.59 L10.43 11.00 L10.01 11.33 L9.46 11.67 L8.58 12.09 L7.71 12.39 L7.01 12.58 L6.03 12.74 L5.02 12.84 L5.36 13.04 L5.81 13.26 L6.48 13.48 L9.01 12.29 L9.00 12.35 L7.38 13.66 L7.83 13.70 L8.48 13.69 L8.99 13.62 L9.45 13.53 L9.51 13.49 L9.80 13.00 L10.41 11.82ZM15.36 8.86 L14.69 8.72 L14.60 8.73 L14.52 8.80 L14.37 9.58 L14.18 10.19 L13.92 10.82 L13.56 11.47 L13.23 11.95 L12.80 12.45 L12.36 12.88 L11.67 13.41 L11.59 13.50 L11.60 13.66 L12.05 14.15 L12.16 14.18 L12.28 14.15 L12.70 13.84 L13.18 13.42 L13.88 12.67 L14.42 11.90 L14.90 10.98 L15.19 10.23 L15.34 9.68 L15.45 9.06 L15.44 8.96ZM2.33 8.31 L2.41 9.03 L2.63 9.85 L4.21 10.92 L4.19 10.95 L2.98 10.66 L3.23 11.10 L3.48 11.44 L4.07 12.10 L5.48 12.03 L6.35 11.90 L6.83 11.77 L5.31 11.21 L4.56 10.60 L3.69 9.80 L3.15 9.24ZM11.53 7.00 L11.52 7.10 L11.82 8.57 L11.79 8.88 L11.60 9.94 L11.33 11.11 L11.02 12.11 L10.67 13.05 L11.41 12.60 L11.90 12.19 L12.01 12.06 L12.12 9.73 L12.16 9.69 L12.19 9.71 L12.65 11.29 L12.68 11.30 L12.91 10.96 L13.17 10.46 L13.48 9.68 L13.36 9.42 L13.05 8.93 L12.45 8.06 L11.97 7.46ZM4.66 6.39 L4.53 6.81 L4.45 7.52 L4.47 8.08 L4.53 8.47 L4.62 8.82 L4.81 9.29 L4.98 9.61 L5.50 10.27 L5.99 10.70 L6.00 10.68 L5.67 9.95 L5.68 9.89 L6.67 10.38 L7.58 11.69 L7.28 9.68 L6.68 9.17 L6.38 8.87 L5.91 8.33 L5.24 7.37 L4.69 6.40ZM10.89 6.38 L10.23 7.51 L9.61 8.38 L8.97 9.08 L8.28 9.68 L7.98 11.68 L8.89 10.38 L9.88 9.89 L9.89 9.92 L9.55 10.67 L9.58 10.69 L10.17 10.15 L10.46 9.78 L10.66 9.46 L10.93 8.82 L11.08 8.08 L11.11 7.50 L11.08 7.14 L10.99 6.68ZM1.67 4.30 L1.59 4.32 L1.53 4.37 L1.17 5.10 L0.98 5.61 L0.79 6.28 L0.71 6.68 L0.62 7.34 L0.61 8.54 L0.68 9.12 L0.80 9.74 L1.11 10.74 L1.40 11.38 L1.82 12.09 L2.01 12.34 L2.14 12.36 L2.69 12.09 L2.76 12.01 L2.77 11.90 L2.32 11.21 L1.97 10.49 L1.68 9.61 L1.53 8.82 L1.49 8.41 L1.48 7.79 L1.53 7.17 L1.59 6.78 L1.71 6.25 L1.89 5.70 L2.31 4.78 L2.31 4.66 L2.23 4.57 L1.78 4.31ZM8.19 4.36 L8.86 4.49 L9.50 4.73 L10.37 5.21 L11.01 5.67 L11.84 6.39 L12.45 7.01 L13.23 7.94 L13.66 8.53 L13.71 8.54 L13.72 7.57 L13.59 6.73 L11.09 5.12 L11.11 5.09 L13.31 5.86 L13.20 5.57 L12.91 5.01 L12.54 4.48 L12.23 4.12 L11.61 4.08 L10.43 4.11 L9.03 4.23ZM5.18 3.03 L4.53 3.46 L4.11 3.82 L3.81 4.14 L3.54 6.84 L3.49 6.84 L3.23 4.93 L3.20 4.92 L3.02 5.22 L2.67 5.97 L2.50 6.53 L2.41 6.95 L2.64 7.40 L3.14 8.19 L3.59 8.85 L4.15 9.57 L3.95 8.90 L3.86 8.24 L3.86 7.30 L3.93 6.66 L4.10 5.77 L4.34 4.97 L4.61 4.24ZM11.18 3.23 L10.85 3.01 L10.43 2.80 L9.92 2.59 L9.53 2.48 L6.94 3.78 L6.92 3.74 L8.28 2.28 L7.58 2.28 L7.10 2.34 L6.31 2.53 L6.26 2.56 L5.93 3.16 L5.47 4.12 L5.08 5.13 L4.94 5.64 L6.19 4.56 L6.86 4.29 L8.15 3.86 L9.18 3.58 L10.19 3.37ZM3.71 1.97 L3.71 2.11 L3.91 2.40 L4.09 2.62 L4.17 2.64 L4.30 2.61 L4.70 2.34 L5.15 2.10 L5.85 1.81 L6.68 1.57 L7.45 1.46 L8.47 1.46 L9.19 1.54 L9.94 1.72 L10.71 2.02 L11.54 2.47 L12.19 2.94 L12.78 3.49 L13.29 4.11 L13.73 4.79 L14.13 5.64 L14.36 6.36 L14.54 7.23 L14.61 7.30 L14.76 7.31 L15.35 7.17 L15.45 7.07 L15.40 6.60 L15.31 6.19 L15.02 5.28 L14.61 4.42 L14.40 4.05 L14.00 3.48 L13.50 2.89 L13.19 2.57 L12.46 1.96 L11.77 1.52 L11.02 1.14 L10.05 0.80 L9.16 0.61 L8.31 0.54 L7.60 0.55 L7.17 0.58 L6.06 0.80 L5.18 1.10 L4.30 1.54 L3.78 1.88Z"/>
</svg>
EOF_ICON_SYM
}

install_icons() {
  local hi="$LROOT/usr/share/icons/hicolor"
  local pix="$LROOT/usr/share/pixmaps"
  $SUDO mkdir -p "$hi/scalable/apps" "$hi/symbolic/apps" "$pix"

  # если в rootfs/ лежат свои файлы, они уже наложены и остаются
  if [ -e "$hi/scalable/apps/coli-linux.svg" ]; then
    echo "==> Иконка COLI: берём из rootfs/"
  else
    write_icon_color_svg | $SUDO tee "$hi/scalable/apps/coli-linux.svg" >/dev/null
    echo "==> Иконка COLI: встроенная"
  fi
  if [ ! -e "$hi/symbolic/apps/coli-linux-symbolic.svg" ]; then
    write_icon_symbolic_svg | $SUDO tee "$hi/symbolic/apps/coli-linux-symbolic.svg" >/dev/null
  fi

  # копии в pixmaps: там иконку находят по имени и без обновления кэша иконок
  $SUDO cp -f "$hi/scalable/apps/coli-linux.svg" "$pix/coli-linux.svg"
  if [ -f "$hi/512x512/apps/coli-linux.png" ]; then
    $SUDO cp -f "$hi/512x512/apps/coli-linux.png" "$pix/coli-linux.png"
  fi
  $SUDO chmod 644 "$hi/scalable/apps/coli-linux.svg" "$hi/symbolic/apps/coli-linux-symbolic.svg"
  $SUDO chmod 644 "$pix"/coli-linux.*

  # логотип в «Параметры -> О системе»
  local osr="$LROOT/usr/lib/os-release"
  if [ -f "$osr" ]; then
    $SUDO sed -i -e '$a\' "$osr"
    if grep -q '^LOGO=' "$osr"; then
      $SUDO sed -i 's|^LOGO=.*|LOGO=coli-linux|' "$osr"
    else
      echo 'LOGO=coli-linux' | $SUDO tee -a "$osr" >/dev/null
    fi
    echo "==> os-release: LOGO=coli-linux"
  else
    echo "!! Нет usr/lib/os-release: логотип в «О системе» не настроен"
  fi
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
