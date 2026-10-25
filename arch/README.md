# COLI Linux на Arch (archiso)

Сборка образа: `bash arch/build.sh` на Arch Linux (виртуалка или установленная система).
Перед первой сборкой: `sudo pacman -Syu && sudo pacman -S --needed archiso git dconf`.

- `build.sh` берёт шаблон `releng` из пакета archiso, накладывает наши правки и запускает `mkarchiso`.
- `overlay/packages.add` — пакеты поверх базового набора.
- `overlay/airootfs/` — файлы, которые попадут в систему (Plymouth, иконки, звук, настройки).
- `overlay/dconf/coli.d/00-coli` — настройки GNOME по умолчанию (тема, обои, закрепы в доке).
- Обои берутся из `rootfs/usr/share/backgrounds/coli/*.png` репозитория.
- Готовый образ: `build/arch-out/coli-linux-*.iso`.
