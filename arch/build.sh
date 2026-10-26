#!/usr/bin/env bash
# Сборка COLI Linux на базе Arch (archiso).
# Запускать на Arch Linux (виртуалка или установленная система), из любой папки:
#   bash arch/build.sh
# Готовый образ: build/arch-out/coli-linux-*.iso
#
# Нужны пакеты: sudo pacman -S --needed archiso dconf
# Перед сборкой обнови систему: sudo pacman -Syu
set -euo pipefail

ARCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$ARCH_DIR/.." && pwd)"
OVERLAY="$ARCH_DIR/overlay"
RELENG="${RELENG:-/usr/share/archiso/configs/releng}"
P="$ROOT/build/arch-profile"
WORKDIR="${WORKDIR:-/var/tmp/coli-archiso-work}"
OUTDIR="${OUTDIR:-$ROOT/build/arch-out}"
LIVE_USER=coli

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
die()  { echo "ОШИБКА: $*" >&2; exit 1; }
warn() { echo "!! $*" >&2; }

for c in mkarchiso pacman dconf awk sed; do
  command -v "$c" >/dev/null 2>&1 || die "нет программы $c (поставь: sudo pacman -S --needed archiso dconf)"
done
[ -d "$RELENG" ] || die "нет шаблона $RELENG (пакет archiso)"
pacman -Si bash >/dev/null 2>&1 || die "база пакетов пустая: выполни sudo pacman -Syu"
free="$(df -BG --output=avail "$(dirname "$WORKDIR")" | tail -1 | tr -dc '0-9')"
NEED_GB="${NEED_GB:-15}"
[ "${free:-0}" -ge "$NEED_GB" ] || die "мало места в $(dirname "$WORKDIR"): свободно ${free:-0} ГБ, нужно хотя бы $NEED_GB"

echo "==> [1/8] Профиль: копия releng"
rm -rf "$P"; mkdir -p "$ROOT/build"; cp -r "$RELENG" "$P"

echo "==> [2/8] Название и метка образа"
sed -i -e 's|^iso_name=.*|iso_name="coli-linux"|' \
       -e 's|^iso_label="ARCH_|iso_label="COLI_|' \
       -e 's|^iso_publisher=.*|iso_publisher="COLI Linux"|' \
       -e 's|^iso_application=.*|iso_application="COLI Linux Live"|' "$P/profiledef.sh"
grep -E '^(iso_name|iso_label|iso_publisher|iso_application)=' "$P/profiledef.sh"

echo "==> [3/8] Пакеты установщика и рабочего стола"
while IFS= read -r line; do
  pkg="${line%%#*}"; pkg="$(echo $pkg)"
  [ -n "$pkg" ] || continue
  if grep -qx -- "$pkg" "$P/packages.x86_64"; then continue; fi
  if pacman -Si "$pkg" >/dev/null 2>&1; then
    echo "$pkg" >> "$P/packages.x86_64"
  else
    warn "пакет $pkg не найден в репозиториях, пропускаю"
  fi
done < "$OVERLAY/packages.add"

# --- ФИКС КОНФЛИКТА VIRTUALBOX ---
# Удаляем "-nox" версию (она часто идет по умолчанию в archiso) и оставляем только GUI версию
sed -i '/^virtualbox-guest-utils-nox$/d' "$P/packages.x86_64"
if ! grep -qx "virtualbox-guest-utils" "$P/packages.x86_64"; then
  echo "virtualbox-guest-utils" >> "$P/packages.x86_64"
fi
# ---------------------------------

echo "   в образе будет пакетов: $(grep -c -v -e '^#' -e '^$' "$P/packages.x86_64")"

echo "==> [4/8] Меню загрузки: названия и заставка"
for f in "$P"/grub/*.cfg "$P"/syslinux/*.cfg "$P"/efiboot/loader/entries/*.conf "$P"/efiboot/loader/loader.conf; do
  [ -f "$f" ] && sed -i 's/Arch Linux/COLI Linux/g' "$f"
done
for f in "$P"/grub/*.cfg "$P"/syslinux/*.cfg "$P"/efiboot/loader/entries/*.conf; do
  [ -f "$f" ] && sed -i '/archisosearchuuid=%ARCHISO_UUID%/ { /splash/! s/archisosearchuuid=%ARCHISO_UUID%/& quiet splash/ }' "$f"
done
echo "   пунктов с quiet splash: $(cat "$P"/grub/*.cfg "$P"/syslinux/*.cfg "$P"/efiboot/loader/entries/*.conf 2>/dev/null | grep -c 'quiet splash' || true)"
if [ -f "$OVERLAY/syslinux/splash.png" ] && [ -d "$P/syslinux" ]; then
  cp "$OVERLAY/syslinux/splash.png" "$P/syslinux/splash.png"
fi

echo "==> [5/8] Файлы COLI поверх системы (airootfs)"
cp -a "$OVERLAY/airootfs/." "$P/airootfs/"

# обои пользователя берём из rootfs/ репозитория
WP_SRC="$ROOT/rootfs/usr/share/backgrounds/coli"
WP_DST="$P/airootfs/usr/share/backgrounds/coli"
if ls "$WP_SRC"/*.png >/dev/null 2>&1; then
  mkdir -p "$WP_DST" "$P/airootfs/usr/share/gnome-background-properties"
  cp "$WP_SRC"/*.png "$WP_DST/"
  [ -f "$WP_DST/wallpaper.png" ] || cp "$(ls "$WP_DST"/*.png | head -1)" "$WP_DST/wallpaper.png"
  {
    echo '<?xml version="1.0"?>'
    echo '<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">'
    echo '<wallpapers>'
    for f in "$WP_DST"/*.png; do
      b="$(basename "$f")"
      [ "$b" = "wallpaper.png" ] && continue
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
  } > "$P/airootfs/usr/share/gnome-background-properties/coli-wallpapers.xml"
  echo "   обои: $(ls "$WP_SRC"/*.png | wc -l) шт."
else
  warn "в rootfs/usr/share/backgrounds/coli нет PNG: останется стандартный фон"
fi

echo "==> [6/8] Настройки GNOME по умолчанию (dconf)"
mkdir -p "$P/airootfs/etc/dconf/db"
dconf compile "$P/airootfs/etc/dconf/db/coli" "$OVERLAY/dconf/coli.d"

echo "==> [7/8] Живой пользователь, службы, заставка"
A="$P/airootfs/etc"
grep -q "^$LIVE_USER:" "$A/passwd"  || echo "$LIVE_USER:x:1000:1000:COLI Live:/home/$LIVE_USER:/bin/bash" >> "$A/passwd"
grep -q "^$LIVE_USER:" "$A/group"   || echo "$LIVE_USER:x:1000:" >> "$A/group"
grep -q "^wheel:" "$A/group"        || echo "wheel:x:998:" >> "$A/group"
grep -q "^$LIVE_USER:" "$A/shadow"  || echo "$LIVE_USER::14871::::::" >> "$A/shadow"
grep -q "^$LIVE_USER:" "$A/gshadow" || echo "$LIVE_USER:!::" >> "$A/gshadow"
grep -q "^wheel:" "$A/gshadow"      || echo "wheel:!::" >> "$A/gshadow"
for f in group gshadow; do
  awk -F: -v OFS=: -v u="$LIVE_USER" '
    $1 ~ /^(wheel|audio|video|storage|optical|power|network|input)$/ { if ($4 == "") $4 = u; else if (index("," $4 ",", "," u ",") == 0) $4 = $4 "," u }
    { print }' "$A/$f" > "$A/$f.new" && mv "$A/$f.new" "$A/$f"
done

SD="$A/systemd/system"
mkdir -p "$SD/multi-user.target.wants" "$SD/network-online.target.wants" "$SD/bluetooth.target.wants"
# сетевые службы releng (systemd-networkd, iwd) заменяем на NetworkManager
find "$SD" -type l \( -name 'systemd-networkd*' -o -name 'iwd.service' \) -delete 2>/dev/null || true
ln -sfn /usr/lib/systemd/system/gdm.service                         "$SD/display-manager.service"
ln -sfn /usr/lib/systemd/system/NetworkManager.service              "$SD/multi-user.target.wants/NetworkManager.service"
ln -sfn /usr/lib/systemd/system/NetworkManager-dispatcher.service   "$SD/dbus-org.freedesktop.nm-dispatcher.service"
ln -sfn /usr/lib/systemd/system/NetworkManager-wait-online.service  "$SD/network-online.target.wants/NetworkManager-wait-online.service"
ln -sfn /usr/lib/systemd/system/bluetooth.service                   "$SD/bluetooth.target.wants/bluetooth.service"
ln -sfn /usr/lib/systemd/system/vboxservice.service                 "$SD/multi-user.target.wants/vboxservice.service"
ln -sfn /usr/lib/systemd/system/graphical.target                    "$SD/default.target"

MK="$A/mkinitcpio.conf.d/archiso.conf"
if [ -f "$MK" ]; then
  if ! grep -q 'plymouth' "$MK"; then
    if grep -q -E '^HOOKS=.*\bkms\b' "$MK"; then
      sed -i -E '/^HOOKS=/ s/\bkms\b/kms plymouth/' "$MK"
    else
      sed -i -E '/^HOOKS=/ s/\budev\b/udev plymouth/' "$MK"
    fi
  fi
  grep '^HOOKS' "$MK"
else
  warn "нет $MK: заставка Plymouth в initramfs не подключена"
fi

sed -i '/^file_permissions=(/a\
  ["/etc/sudoers.d/g_wheel"]="0:0:0440"\
  ["/usr/lib/coli/play-startup-sound"]="0:0:0755"' "$P/profiledef.sh"
grep -q 'g_wheel' "$P/profiledef.sh" || warn "не удалось добавить права в profiledef.sh (file_permissions)"

echo "==> [8/8] Сборка образа (долго: 15-30 минут)"
$SUDO rm -rf "$WORKDIR"
mkdir -p "$OUTDIR"
$SUDO mkarchiso -v -w "$WORKDIR" -o "$OUTDIR" "$P"
[ -z "$SUDO" ] || $SUDO chown -R "$(id -un):$(id -gn)" "$OUTDIR"
$SUDO rm -rf "$WORKDIR"

echo
ls -lh "$OUTDIR"
echo "Готово. Запусти образ в VirtualBox (включи EFI) и проверь вход, обои и анимацию загрузки."