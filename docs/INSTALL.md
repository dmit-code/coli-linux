# Установка и сборка COLI Linux

## Дома (Windows 10 + WSL, Ubuntu)
    cd ~ && git clone <адрес-репозитория> coli-linux
    cd coli-linux && ./build.sh deps && ./build.sh

## В колледже (ROSA МОС 12, dnf)
    git clone <адрес-репозитория> coli-linux
    cd coli-linux && ./build.sh deps && ./build.sh

## Синхронизация
    git pull          # забрать изменения
    git add -A && git commit -m "что сделал" && git push
