#!/usr/bin/env python3
"""COLI Linux graphical installer frontend for the official archinstall."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # noqa: E402

GIB = 1024 ** 3
MIN_DISK_GIB = 32


def list_install_disks() -> list[dict]:
    result = subprocess.run(
        ["lsblk", "--json", "--bytes", "--output", "PATH,NAME,SIZE,TYPE,MODEL,RM,RO,TRAN"],
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
    live_disk = None
    try:
        source = subprocess.run(
            ["findmnt", "--noheadings", "--output", "SOURCE", "/run/archiso/bootmnt"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip().split("[", 1)[0]
        if source.startswith("/dev/"):
            parent = subprocess.run(
                ["lsblk", "--noheadings", "--nodeps", "--output", "PKNAME", source],
                capture_output=True,
                text=True,
            ).stdout.strip()
            live_disk = "/dev/" + parent if parent else source
    except (OSError, subprocess.SubprocessError):
        pass

    disks = []
    for disk in data.get("blockdevices", []):
        size = int(disk.get("size") or 0)
        if disk.get("type") != "disk" or bool(disk.get("ro")) or size < MIN_DISK_GIB * GIB:
            continue
        path = disk.get("path") or ("/dev/" + str(disk.get("name", "")))
        if path == live_disk:
            continue
        model = " ".join(str(disk.get("model") or "").split()) or "Диск"
        transport = str(disk.get("tran") or "").upper()
        removable = bool(disk.get("rm"))
        label = f"{path} — {model} — {size // GIB} ГиБ"
        if removable or transport == "USB":
            label += " (USB/съёмный)"
        disks.append({"path": path, "size": size, "label": label})
    return disks


def make_size(value: int, unit: str) -> dict:
    return {
        "value": int(value),
        "unit": unit,
        "sector_size": {"value": 512, "unit": "B"},
    }


class InstallerWindow:
    def __init__(self, app: Gtk.Application) -> None:
        self.app = app
        self.window = Gtk.ApplicationWindow(application=app)
        self.window.set_title("Установка COLI Linux")
        self.window.set_default_size(760, 760)
        self.window.set_resizable(True)
        self.window.connect("close-request", self.on_close_request)
        self.process: subprocess.Popen | None = None
        self.disks: list[dict] = []
        self.tempdir: str | None = None
        self.uefi = os.path.isdir("/sys/firmware/efi")

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in (20,):
            outer.set_margin_start(side)
            outer.set_margin_end(side)
            outer.set_margin_top(18)
            outer.set_margin_bottom(18)
        self.window.set_child(outer)

        title = Gtk.Label(label="Установка COLI Linux")
        title.add_css_class("title-1")
        title.set_halign(Gtk.Align.START)
        outer.append(title)

        intro = Gtk.Label(label="Графический мастер использует официальный archinstall.")
        intro.set_halign(Gtk.Align.START)
        outer.append(intro)

        self.grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        self.grid.set_hexpand(True)
        outer.append(self.grid)

        self.disk_dropdown = Gtk.DropDown.new_from_strings([])
        self.refresh_button = Gtk.Button(label="Обновить")
        self.refresh_button.connect("clicked", self.refresh_disks)
        disk_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        disk_box.append(self.disk_dropdown)
        disk_box.append(self.refresh_button)
        disk_box.set_hexpand(True)
        self.add_row(0, "Диск для установки", disk_box)

        self.language_dropdown = Gtk.DropDown.new_from_strings(["Русский", "English"])
        self.language_dropdown.set_selected(0)
        self.add_row(1, "Язык системы", self.language_dropdown)

        self.hostname_entry = Gtk.Entry()
        self.hostname_entry.set_text("coli-linux")
        self.hostname_entry.set_placeholder_text("например, coli-linux")
        self.add_row(2, "Имя компьютера", self.hostname_entry)

        self.username_entry = Gtk.Entry()
        self.username_entry.set_text("coli")
        self.username_entry.set_placeholder_text("латиницей, без пробелов")
        self.add_row(3, "Имя пользователя", self.username_entry)

        self.password_entry = Gtk.PasswordEntry()
        self.password_entry.set_show_peek_icon(True)
        self.password_entry.set_placeholder_text("не менее 8 символов")
        self.add_row(4, "Пароль пользователя", self.password_entry)

        self.password2_entry = Gtk.PasswordEntry()
        self.password2_entry.set_show_peek_icon(True)
        self.password2_entry.set_placeholder_text("повторите пароль")
        self.add_row(5, "Повтор пароля", self.password2_entry)

        self.timezone_entry = Gtk.Entry()
        self.timezone_entry.set_text("Europe/Moscow")
        self.timezone_entry.set_placeholder_text("например, Europe/Moscow")
        self.add_row(6, "Часовой пояс", self.timezone_entry)

        self.uefi_label = Gtk.Label()
        self.uefi_label.set_halign(Gtk.Align.START)
        self.add_row(7, "Режим загрузки", self.uefi_label)

        self.warning = Gtk.Label()
        self.warning.set_wrap(True)
        self.warning.set_xalign(0)
        self.warning.add_css_class("warning")
        outer.append(self.warning)

        self.erase_check = Gtk.CheckButton.new_with_label(
            "Я понимаю: выбранный диск будет полностью очищен"
        )
        self.erase_check.connect("toggled", self.on_ack_changed)
        outer.append(self.erase_check)

        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.install_button = Gtk.Button(label="Установить COLI Linux")
        self.install_button.add_css_class("suggested-action")
        self.install_button.set_sensitive(False)
        self.install_button.connect("clicked", self.start_install)
        buttons.append(self.install_button)
        outer.append(buttons)

        self.status = Gtk.Label(label="Выбери диск и заполни данные.")
        self.status.set_wrap(True)
        self.status.set_xalign(0)
        outer.append(self.status)

        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_cursor_visible(False)
        self.log_view.set_monospace(True)
        self.log_buffer = self.log_view.get_buffer()
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_vexpand(True)
        log_scroll.set_min_content_height(180)
        log_scroll.set_child(self.log_view)
        outer.append(log_scroll)

        self.update_boot_mode()
        self.refresh_disks()

    def add_row(self, row: int, label_text: str, widget: Gtk.Widget) -> None:
        label = Gtk.Label(label=label_text)
        label.set_halign(Gtk.Align.START)
        label.set_valign(Gtk.Align.CENTER)
        widget.set_hexpand(True)
        self.grid.attach(label, 0, row, 1, 1)
        self.grid.attach(widget, 1, row, 1, 1)

    def update_boot_mode(self) -> None:
        self.uefi = os.path.isdir("/sys/firmware/efi")
        if self.uefi:
            self.uefi_label.set_text("UEFI — поддерживается")
            self.warning.set_text(
                "Важно: установка создаст раздел EFI и раздел ext4, а выбранный диск будет очищен. "
                "Нужно не менее 32 ГиБ свободного места."
            )
        else:
            self.uefi_label.set_text("Legacy BIOS — перезагрузи ISO в режиме UEFI")
            self.warning.set_text(
                "Этот мастер настраивает загрузку UEFI. Перезагрузи компьютер и выбери UEFI-запись COLI Linux."
            )
            self.install_button.set_sensitive(False)

    def refresh_disks(self, *_args) -> None:
        try:
            self.disks = list_install_disks()
            labels = [disk["label"] for disk in self.disks] or ["Подходящий диск ≥ 32 ГиБ не найден"]
            self.disk_dropdown.set_model(Gtk.StringList.new(labels))
            self.disk_dropdown.set_selected(0)
            self.disk_dropdown.set_sensitive(bool(self.disks))
            if not self.disks:
                self.status.set_text("Подключи диск объёмом не менее 32 ГиБ и нажми «Обновить».")
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
            self.disks = []
            self.disk_dropdown.set_model(Gtk.StringList.new(["Не удалось прочитать список дисков"]))
            self.disk_dropdown.set_sensitive(False)
            self.status.set_text(f"Ошибка обнаружения дисков: {exc}")
        self.on_ack_changed()

    def on_ack_changed(self, *_args) -> None:
        enabled = bool(self.disks) and self.erase_check.get_active() and self.uefi
        self.install_button.set_sensitive(enabled and self.process is None)

    def selected_disk(self) -> dict | None:
        index = self.disk_dropdown.get_selected()
        if 0 <= index < len(self.disks):
            return self.disks[index]
        return None

    def validate(self) -> tuple[dict, str, str, str, str, str] | None:
        disk = self.selected_disk()
        if not disk:
            self.status.set_text("Не найден диск для установки.")
            return None
        if not self.uefi:
            self.status.set_text("Загрузи Live ISO в режиме UEFI.")
            return None
        hostname = self.hostname_entry.get_text().strip().lower()
        username = self.username_entry.get_text().strip()
        password = self.password_entry.get_text()
        password2 = self.password2_entry.get_text()
        timezone = self.timezone_entry.get_text().strip()
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", hostname):
            self.status.set_text("Имя компьютера: латинские буквы, цифры и дефис; дефис не в начале/конце.")
            return None
        if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username):
            self.status.set_text("Имя пользователя должно быть латиницей: a-z, цифры, _ и -.")
            return None
        if len(password) < 8:
            self.status.set_text("Пароль должен содержать не менее 8 символов.")
            return None
        if password != password2:
            self.status.set_text("Пароли не совпадают.")
            return None
        try:
            ZoneInfo(timezone)
        except ZoneInfoNotFoundError:
            self.status.set_text("Неизвестный часовой пояс. Например: Europe/Moscow.")
            return None
        locale = ("ru", "ru_RU.UTF-8") if self.language_dropdown.get_selected() == 0 else ("us", "en_US.UTF-8")
        return disk, hostname, username, password, timezone, locale[0] + "|" + locale[1]

    def build_config(self, disk: dict, hostname: str, timezone: str, kb_locale: str) -> dict:
        kb_layout, sys_lang = kb_locale.split("|", 1)
        total_gib = int(disk["size"] // GIB)
        root_gib = total_gib - 2
        if root_gib < 10:
            raise ValueError("Для установки нужно не менее 32 ГиБ.")
        boot_start = make_size(1, "MiB")
        boot_size = make_size(1024, "MiB")
        root_start = make_size(1025, "MiB")
        root_size = make_size(root_gib, "GiB")
        partitions = [
            {
                "btrfs": [], "dev_path": None, "flags": ["boot"], "fs_type": "fat32",
                "size": boot_size, "mount_options": [], "mountpoint": "/boot",
                "obj_id": str(uuid.uuid4()), "start": boot_start,
                "status": "create", "type": "primary",
            },
            {
                "btrfs": [], "dev_path": None, "flags": [], "fs_type": "ext4",
                "size": root_size, "mount_options": [], "mountpoint": "/",
                "obj_id": str(uuid.uuid4()), "start": root_start,
                "status": "create", "type": "primary",
            },
        ]
        return {
            "archinstall-language": "English",
            "script": "guided",
            "disk_config": {
                "config_type": "default_layout",
                "device_modifications": [{
                    "device": disk["path"], "wipe": True, "partitions": partitions,
                }],
            },
            "bootloader_config": {"bootloader": "Systemd-boot", "uki": False, "removable": False},
            "locale_config": {"kb_layout": kb_layout, "sys_lang": sys_lang, "sys_enc": "UTF-8"},
            "network_config": {"type": "nm"},
            "hostname": hostname,
            "kernels": ["linux"],
            "ntp": True,
            "timezone": timezone,
            "profile_config": {
                "profile": {"main": "Desktop", "details": ["GNOME"]},
                "gfx_driver": "All open-source",
                "greeter": "gdm",
            },
            "services": ["NetworkManager", "gdm"],
            "swap": {"enabled": True, "algorithm": "zstd"},
            "packages": ["firefox"],
            "pacman_config": {"parallel_downloads": 5},
        }

    def start_install(self, *_args) -> None:
        validated = self.validate()
        if validated is None:
            return
        disk, hostname, username, password, timezone, locale = validated
        if not self.erase_check.get_active():
            self.status.set_text("Отметь подтверждение полного удаления данных на выбранном диске.")
            return
        self.install_button.set_sensitive(False)
        self.refresh_button.set_sensitive(False)
        self.status.set_text(
            f"Подготовка установки на {disk['path']}. Данные на выбранном диске будут удалены."
        )
        try:
            from archinstall.lib.crypt import crypt_yescrypt

            password_hash = crypt_yescrypt(password)
            config = self.build_config(disk, hostname, timezone, locale)
            self.tempdir = tempfile.mkdtemp(prefix="coli-installer-")
            os.chmod(self.tempdir, 0o700)
            config_path = os.path.join(self.tempdir, "user_configuration.json")
            creds_path = os.path.join(self.tempdir, "user_credentials.json")
            with open(config_path, "w", encoding="utf-8") as handle:
                json.dump(config, handle, ensure_ascii=False, indent=2)
            with open(creds_path, "w", encoding="utf-8") as handle:
                json.dump({"users": [{
                    "username": username,
                    "enc_password": password_hash,
                    "sudo": True,
                    "groups": ["wheel"],
                }]}, handle, ensure_ascii=False)
            os.chmod(config_path, 0o600)
            os.chmod(creds_path, 0o600)
            self.password_entry.set_text("")
            self.password2_entry.set_text("")
            self.log_buffer.set_text("")
            self.status.set_text("Установка запущена. Не выключай компьютер и не закрывай окно.")
            self.process = subprocess.Popen(
                ["sudo", "-n", "archinstall", "--config", config_path, "--creds", creds_path, "--silent", "--verbose"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            threading.Thread(target=self.read_process, daemon=True).start()
        except Exception as exc:
            self.cleanup_temp()
            self.process = None
            self.status.set_text(f"Не удалось запустить установку: {exc}")
            self.refresh_button.set_sensitive(True)
            self.install_button.set_sensitive(self.erase_check.get_active() and self.uefi)

    def read_process(self) -> None:
        assert self.process is not None
        process = self.process
        if process.stdout is not None:
            for line in process.stdout:
                GLib.idle_add(self.append_log, line.rstrip())
        code = process.wait()
        self.cleanup_temp()
        GLib.idle_add(self.finish_install, code)

    def append_log(self, text: str) -> bool:
        self.log_buffer.insert(self.log_buffer.get_end_iter(), text + "\n")
        return GLib.SOURCE_REMOVE

    def cleanup_temp(self) -> None:
        if self.tempdir:
            shutil.rmtree(self.tempdir, ignore_errors=True)
            self.tempdir = None

    def finish_install(self, code: int) -> bool:
        self.process = None
        self.refresh_button.set_sensitive(True)
        if code == 0:
            self.status.set_text("Установка завершена. Перезагрузи компьютер и извлеки установочный носитель.")
        else:
            self.status.set_text(
                f"Установка завершилась с кодом {code}. Подробности — в журнале выше; диск мог быть изменён."
            )
        return GLib.SOURCE_REMOVE

    def on_close_request(self, *_args) -> bool:
        if self.process is not None:
            self.status.set_text("Установка ещё идёт — окно нельзя закрыть до её завершения.")
            return True
        return False


class InstallerApp:
    def __init__(self) -> None:
        self.app = Gtk.Application(application_id="org.coli.linux.installer")
        self.app.connect("activate", self.on_activate)
        self.window: InstallerWindow | None = None

    def on_activate(self, app: Gtk.Application) -> None:
        if self.window is None:
            self.window = InstallerWindow(app)
        self.window.window.present()

    def run(self) -> int:
        return self.app.run(None)


if __name__ == "__main__":
    raise SystemExit(InstallerApp().run())
