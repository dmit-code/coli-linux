#!/usr/bin/env bash
# Ставит зависимости сборки (списки лежат в packages/deps-*.txt)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

PM="$(detect_pm)"
echo "==> Менеджер пакетов: $PM"

case "$PM" in
  apt)
    $SUDO apt-get update
    read_list "$ROOT/packages/deps-apt.txt" | xargs $SUDO apt-get install -y
    ;;
  dnf)
    read_list "$ROOT/packages/deps-dnf.txt" | xargs $SUDO dnf install -y
    ;;
  *)
    echo "Не найден ни apt, ни dnf" >&2
    exit 1
    ;;
esac

echo "==> Готово"
