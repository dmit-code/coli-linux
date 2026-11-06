# COLI Linux на Arch (archiso)

Сборка образа: `bash arch/build.sh` на Arch Linux (виртуалка или установленная система). Скрипт запускай обычным пользователем, не через `sudo`.

Перед первой сборкой:

```bash
sudo pacman -Syu
sudo pacman -S --needed archiso git dconf
```

`arch/build.sh` копирует профиль `releng`, добавляет пакеты и настройки COLI, затем запускает `mkarchiso`. Готовый образ: `build/arch-out/coli-linux-*.iso`.

## Установщик

Ярлык «Установить COLI Linux» сначала показывает краткую инструкцию на русском, затем запускает официальный интерактивный Archinstall в терминале. Конфигурация остаётся управляемой мастером (`silent: false`): заранее выбраны профиль GNOME, GDM, GRUB, PipeWire и Firefox, но диск, разметка, пользователь и пароли не задаются автоматически. Перед подтверждением разметки нужно проверить выбранный диск.

При сборке `scripts/make_archinstall_defaults.py` создаёт конфиг Archinstall и вкладывает доступные фирменные ресурсы в его post-install команды. При стандартном выборе GNOME/GRUB они применяют обои COLI, логотипы из `hicolor`, настройки GNOME, фон GRUB и пересобирают `grub.cfg`.

## Загрузка и оформление

- `overlay/grub/grub.cfg` — меню GRUB для загрузки ISO через UEFI; образ `isofs/boot/grub/coli-bg.png` показывается как фон.
- Для старых BIOS оставлен Syslinux; GRUB используется для UEFI-загрузки ISO.
- GRUB в установленной системе по умолчанию также получает имеющийся COLI-фон.
- Обои берутся из `rootfs/usr/share/backgrounds/coli/*.png`.
- Для оформления GNOME используются настройки `overlay/dconf/coli.d/00-coli`; текущая системная GTK/icon theme — Adwaita, поверх неё устанавливаются имеющиеся значки приложений COLI.
- В репозитории сейчас есть фоновое изображение GRUB и логотипы COLI, но нет полного `theme.txt` GRUB, отдельной GTK-темы или полного набора системных иконок. Поэтому полная тема значков/окон не подменяется выдуманной.

## Основные файлы

- `overlay/packages.add` — пакеты live-системы, включая `archinstall` и GRUB.
- `overlay/airootfs/` — файлы и настройки live-системы, включая русскоязычный запускатель.
- `scripts/make_archinstall_defaults.py` — генерация интерактивных настроек Archinstall и упаковка имеющегося оформления для целевой системы.
- `overlay/dconf/coli.d/00-coli` — настройки GNOME по умолчанию.
