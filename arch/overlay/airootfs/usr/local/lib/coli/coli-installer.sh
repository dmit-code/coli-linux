#!/usr/bin/env bash
set -u

CONFIG=/usr/share/coli/archinstall/defaults.json
clear 2>/dev/null || true
cat <<'TXT'
УСТАНОВКА COLI LINUX

Это официальный текстовый мастер Archinstall с подготовленными настройками COLI.
По умолчанию выбраны GNOME, GDM, GRUB и PipeWire; после установки будут
применены доступные в образе обои, значки COLI и фон GRUB. Настройки можно
проверить и изменить в мастере.

Перед запуском:
 • подключись к интернету через меню сети в правом верхнем углу;
 • внимательно выбери диск и разметку: подтверждённое форматирование может
   удалить данные на выбранных разделах;
 • диск, имя пользователя и пароли за тебя не выбираются.

TXT
if [ ! -r "$CONFIG" ]; then
  printf 'Не найден файл настроек: %s\n' "$CONFIG"
  read -r -p 'Нажми Enter для выхода... ' _ || true
  exit 1
fi
read -r -p 'Нажми Enter, чтобы открыть Archinstall, или Ctrl+C для отмены... ' _ || true
sudo archinstall --config "$CONFIG"
status=$?
printf '\nArchinstall завершился с кодом %s. Если установка прошла успешно, перезагрузи компьютер и извлеки ISO.\n' "$status"
read -r -p 'Нажми Enter для закрытия окна... ' _ || true
exit "$status"
