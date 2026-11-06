# COLI Linux

> A custom Arch Linux live system built with `archiso`.

<p align="center">
  <a href="https://github.com/dmit-code/coli-linux/graphs/commit-activity"><img alt="Monthly commit activity" src="https://img.shields.io/github/commit-activity/m/dmit-code/coli-linux?style=for-the-badge&color=1F6FEB&label=commits%20per%20month"></a>
  <a href="https://github.com/dmit-code/coli-linux/commits/main"><img alt="Latest commit" src="https://img.shields.io/github/last-commit/dmit-code/coli-linux?style=for-the-badge&color=111827"></a>
</p>

## Overview

COLI Linux is an Arch-based live ISO customized with the GNOME desktop, COLI branding, and an interactive Archinstall flow.

## Build

Build on Arch Linux, either in a virtual machine or on an installed system.

```bash
sudo pacman -Syu
sudo pacman -S --needed archiso git dconf
bash arch/build.sh
```

Run the build script as a regular user; it requests `sudo` only where needed. The generated ISO is written to `build/arch-out/coli-linux-*.iso`.

## Installer

The “Install COLI Linux” launcher shows a short guide and then starts the official interactive Archinstall flow in a terminal. The installer keeps disk selection, partitioning, user creation, and passwords under the user's control. **Review the target disk carefully before confirming partitioning.**

Defaults include GNOME, GDM, GRUB, PipeWire, and Firefox. The build script generates the Archinstall configuration and bundles available COLI wallpapers, icons, GNOME settings, and GRUB branding for the installed system.

## Boot and branding

- GRUB boots the ISO in UEFI mode; Syslinux is retained for legacy BIOS.
- The ISO and installed system use the available COLI GRUB background and wallpapers.
- GNOME defaults are configured through `dconf`.
- The repository currently does not include a complete GRUB theme, separate GTK theme, or full system icon set; those are not represented as finished features.

## Project structure

- `arch/overlay/packages.add` — additional packages for the live system.
- `arch/overlay/airootfs/` — live-system files and settings.
- `arch/scripts/make_archinstall_defaults.py` — generates guided installer defaults and packages available branding assets.
- `arch/overlay/dconf/coli.d/00-coli` — default GNOME settings.
- `docs/INSTALL.md` — installation notes.

## Commit activity

The badges above show this repository's monthly commit activity and most recent commit. For the full history, see [Commits](https://github.com/dmit-code/coli-linux/commits/main) and [Commit activity](https://github.com/dmit-code/coli-linux/graphs/commit-activity).

## License

Original COLI scripts, configuration, and documentation in this repository are licensed under **GNU GPL-3.0-or-later**; see [`LICENSE`](LICENSE). Third-party software, packages, and assets retain their respective upstream licenses and are not relicensed by this notice. Check their notices before redistribution.

## Security

Please report security issues privately; see [`SECURITY.md`](SECURITY.md). Do not post vulnerability details in a public issue.
