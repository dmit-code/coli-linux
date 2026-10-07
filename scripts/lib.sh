#!/usr/bin/env bash
# Общие функции для скриптов COLI Linux

# Определяет менеджер пакетов: apt (Debian/Ubuntu/Mint) или dnf (Fedora/МОС)
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  else
    echo unknown
  fi
}

# sudo нужен, только если мы не root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# Читает список пакетов из файла, убирая комментарии и пустые строки
read_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}
