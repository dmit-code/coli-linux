#!/usr/bin/env python3
"""Generate an interactive archinstall config with COLI post-install branding."""
from __future__ import annotations

import argparse
import base64
import io
import json
import tarfile
from pathlib import Path, PurePosixPath


def add_tree(archive: tarfile.TarFile, source: Path, destination: str) -> None:
    if not source.is_dir():
        raise SystemExit(f"required branding directory is missing: {source}")
    for path in sorted(source.rglob("*")):
        if path.is_file():
            archive.add(path, arcname=(PurePosixPath(destination) / path.relative_to(source).as_posix()).as_posix(), recursive=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--live-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = args.repo_root
    wallpaper_dir = root / "rootfs/usr/share/backgrounds/coli"
    wallpapers = sorted(wallpaper_dir.glob("*.png"))
    if not wallpapers:
        raise SystemExit(f"no COLI wallpaper PNGs found in {wallpaper_dir}")
    grub_background = root / "isofs/boot/grub/coli-bg.png"
    if not grub_background.is_file():
        raise SystemExit(f"GRUB background is missing: {grub_background}")

    dconf_file = args.overlay / "dconf/coli.d/00-coli"
    dconf_profile = args.overlay / "airootfs/etc/dconf/profile/user"
    if not dconf_file.is_file() or not dconf_profile.is_file():
        raise SystemExit("COLI dconf settings/profile are missing from the overlay")

    bundle = io.BytesIO()
    with tarfile.open(fileobj=bundle, mode="w:gz", compresslevel=9) as archive:
        for wallpaper in wallpapers:
            archive.add(wallpaper, arcname=f"usr/share/backgrounds/coli/{wallpaper.name}", recursive=False)
        archive.add(wallpapers[0], arcname="usr/share/backgrounds/coli/wallpaper.png", recursive=False)

        add_tree(archive, root / "rootfs/usr/share/icons/hicolor", "usr/share/icons/hicolor")
        add_tree(archive, args.overlay / "airootfs/usr/share/icons/hicolor", "usr/share/icons/hicolor")
        archive.add(grub_background, arcname="usr/share/coli/branding/grub/coli-bg.png", recursive=False)
        archive.add(dconf_profile, arcname="etc/dconf/profile/user", recursive=False)

        target_dconf = dconf_file.read_text(encoding="utf-8")
        target_dconf = target_dconf.replace("'coli-install.desktop', ", "")
        dconf_info = tarfile.TarInfo("etc/dconf/db/coli.d/00-coli")
        dconf_bytes = target_dconf.encode("utf-8")
        dconf_info.size = len(dconf_bytes)
        archive.addfile(dconf_info, io.BytesIO(dconf_bytes))
        backgrounds_xml = args.live_root / "usr/share/gnome-background-properties/coli-wallpapers.xml"
        if backgrounds_xml.is_file():
            archive.add(backgrounds_xml, arcname="usr/share/gnome-background-properties/coli-wallpapers.xml", recursive=False)

    encoded = base64.b64encode(bundle.getvalue()).decode("ascii")
    post_install = "\n".join([
        "set -euo pipefail",
        "base64 -d <<'COLI_BRANDING_TAR' | tar -xz -C /",
        encoded,
        "COLI_BRANDING_TAR",
        "if command -v dconf >/dev/null 2>&1; then dconf update; fi",
        "if [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null 2>&1; then",
        "  install -Dm644 /usr/share/coli/branding/grub/coli-bg.png /boot/grub/coli-bg.png",
        "  if grep -q '^GRUB_BACKGROUND=' /etc/default/grub; then",
        "    sed -i 's|^GRUB_BACKGROUND=.*|GRUB_BACKGROUND=\"/boot/grub/coli-bg.png\"|' /etc/default/grub",
        "  else",
        "    printf '\\nGRUB_BACKGROUND=\"/boot/grub/coli-bg.png\"\\n' >> /etc/default/grub",
        "  fi",
        "  if grep -q '^GRUB_TERMINAL_OUTPUT=' /etc/default/grub; then",
        "    sed -i 's|^GRUB_TERMINAL_OUTPUT=.*|GRUB_TERMINAL_OUTPUT=\"gfxterm\"|' /etc/default/grub",
        "  else",
        "    printf 'GRUB_TERMINAL_OUTPUT=\"gfxterm\"\\n' >> /etc/default/grub",
        "  fi",
        "  grub-mkconfig -o /boot/grub/grub.cfg",
        "fi",
        "if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -f /usr/share/icons/hicolor/index.theme ]; then",
        "  gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true",
        "fi",
    ])

    config = {
        "script": "guided",
        "silent": False,
        "bootloader_config": {"bootloader": "grub", "uki": False, "removable": False},
        "kernels": ["linux"],
        "profile_config": {
            "gfx_driver": "All open-source",
            "greeter": "gdm",
            "profile": {"main": "Desktop", "details": ["GNOME"]},
        },
        "services": ["NetworkManager", "gdm"],
        "audio_config": "pipewire",
        "packages": ["firefox"],
        "custom_commands": [post_install],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated guided installer defaults: {args.output} ({args.output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
