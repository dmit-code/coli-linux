#!/usr/bin/env bash
# COLI Linux — главный скрипт сборки
# Использование: ./build.sh [deps|check|all]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/scripts/lib.sh"

BUILD_DIR="$ROOT/build"
PM="$(detect_pm)"

check_deps() {
  local missing=0
  for cmd in git rsync mksquashfs xorriso; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "   нет: $cmd"
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then
    echo "Поставь зависимости: ./build.sh deps" >&2
    exit 1
  fi
  echo "==> Зависимости на месте ($PM)"
}

stage_prepare() {
  echo "==> Подготовка: $BUILD_DIR"
  mkdir -p "$BUILD_DIR"
}

stage_overlay() {
  echo "==> Накладываем rootfs/ (свои файлы поверх системы)"
  rsync -a --exclude .gitkeep "$ROOT/rootfs/" "$BUILD_DIR/overlay/"
}

stage_iso() {
  echo "==> TODO: сборка ISO (squashfs + xorriso) — допишем"
}

case "${1:-all}" in
  deps)  "$ROOT/scripts/install-deps.sh" ;;
  check) check_deps ;;
  all)
    check_deps
    stage_prepare
    stage_overlay
    stage_iso
    ;;
  *)
    echo "Использование: $0 [deps|check|all]" >&2
    exit 1
    ;;
esac
