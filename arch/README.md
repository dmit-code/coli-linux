# COLI Linux на Arch (archiso)

Сборка образа: `bash arch/build.sh` на Arch Linux (виртуалка или установленная система). Скрипт запускай обычным пользователем, не через `sudo`.

Перед первой сборкой:

```bash
sudo pacman -Syu
sudo pacman -S --needed archiso git dconf base-devel pacman-contrib
```

`arch/build.sh` копирует профиль `releng`, накладывает настройки COLI и запускает `mkarchiso`. Во время сборки он скачивает PKGBUILD `calamares-git` из AUR, собирает пакет от имени текущего пользователя и временно подключает его через локальный pacman-репозиторий. AUR — пользовательский источник: перед сборкой можно просмотреть PKGBUILD в каталоге `build/aur/calamares-git`.

- `overlay/packages.add` — пакеты поверх базового набора.
- `overlay/airootfs/` — файлы live-системы; настройки Calamares лежат в `etc/calamares/`.
- Calamares использует `airootfs.sfs` с live-образа и настраивает GRUB для установленной системы.
- `overlay/dconf/coli.d/00-coli` — настройки GNOME по умолчанию (тема, обои, закрепы в доке).
- Обои берутся из `rootfs/usr/share/backgrounds/coli/*.png`.
- Готовый образ: `build/arch-out/coli-linux-*.iso`.
