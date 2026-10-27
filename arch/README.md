# COLI Linux на Arch (archiso)

Сборка образа: `bash arch/build.sh` на Arch Linux (виртуалка или установленная система). Скрипт запускай обычным пользователем, не через `sudo`.

Перед первой сборкой:

```bash
sudo pacman -Syu
sudo pacman -S --needed archiso git dconf
```

`arch/build.sh` копирует профиль `releng`, добавляет пакеты и настройки COLI, а затем запускает `mkarchiso`. Установщик в меню приложений запускает официальный текстовый `archinstall` в GNOME Console.

- `overlay/packages.add` — дополнительные пакеты live-системы, включая `archinstall` и GRUB.
- `overlay/airootfs/` — файлы и настройки live-системы.
- `overlay/grub/grub.cfg` — меню GRUB для UEFI-загрузки ISO.
- ISO использует GRUB при загрузке через UEFI; Syslinux сохранён для старых BIOS-систем, поскольку archiso поддерживает GRUB для UEFI, а Syslinux для BIOS.
- Выбор загрузчика установленной системы — отдельный параметр внутри `archinstall`; настройка загрузчика ISO сама по себе его не задаёт.
- `overlay/dconf/coli.d/00-coli` — настройки GNOME по умолчанию (тема, обои, закрепы в доке).
- Обои берутся из `rootfs/usr/share/backgrounds/coli/*.png`.
- Готовый образ: `build/arch-out/coli-linux-*.iso`.
