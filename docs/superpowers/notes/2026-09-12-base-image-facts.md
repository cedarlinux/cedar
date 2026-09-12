# Base image facts — recorded 2026-09-12

Image:  quay.io/fedora-ostree-desktops/cosmic-atomic:44

CEDAR_BASE (digest-pinned, single source of truth for Containerfile FROM,
test/boot-chain.sh CEDAR_BASE, and the CI workflow):

quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:2535cf2c9b20c4827537baa08605e6ae0254118e1b1a8ca19a1ada250e9cd293

Arch confirmed amd64: yes

```
$ podman run --rm --platform=linux/amd64 quay.io/fedora-ostree-desktops/cosmic-atomic:44 rpm -q shim-x64 grub2-efi-x64
shim-x64-16.1-5.x86_64
grub2-efi-x64-2.12-64.fc44.x86_64
```

## COSMIC version (from the composed image, not mdapi)

```
$ podman run --rm --platform=linux/amd64 quay.io/fedora-ostree-desktops/cosmic-atomic:44 rpm -q cosmic-session cosmic-comp cosmic-settings cosmic-panel
cosmic-session-1.8.0-1.fc44.x86_64
cosmic-comp-1.8.0-1.fc44.x86_64
cosmic-settings-1.8.0-1.fc44.x86_64
cosmic-panel-1.8.0-1.fc44.x86_64
```

Result: **1.8.0-1.fc44** across all four packages. This matches the
1.8.0-or-newer expectation from prior review — Fedora 44 is current with
upstream COSMIC. No staleness concern; the base choice is validated.
(Confirmed against the composed image per this task's instructions, not
against Fedora's `mdapi`, which is known to report this incorrectly.)

## EFI payload paths (Task 4 hashes these)

**IMPORTANT — this does not match the brief's expected shape.** The brief
expected "trees under `/usr/lib/bootupd/updates/EFI/` and
`/usr/lib/ostree-boot/efi/EFI/`". The actual image does not have that layout:

```
$ podman run --rm --platform=linux/amd64 quay.io/fedora-ostree-desktops/cosmic-atomic:44 \
    find /usr/lib/bootupd /usr/lib/ostree-boot -maxdepth 4
/usr/lib/bootupd
/usr/lib/bootupd/grub2-static
/usr/lib/bootupd/grub2-static/configs.d
/usr/lib/bootupd/grub2-static/configs.d/30_uefi-firmware.cfg
/usr/lib/bootupd/grub2-static/configs.d/14_menu_show_once.cfg
/usr/lib/bootupd/grub2-static/configs.d/10_blscfg.cfg
/usr/lib/bootupd/grub2-static/configs.d/01_users.cfg
/usr/lib/bootupd/grub2-static/configs.d/41_custom.cfg
/usr/lib/bootupd/grub2-static/grub-static-efi.cfg
/usr/lib/bootupd/grub2-static/grub-static-pre.cfg
/usr/lib/bootupd/updates
/usr/lib/bootupd/updates/BIOS.json
/usr/lib/bootupd/updates/EFI.json
/usr/lib/ostree-boot
/usr/lib/ostree-boot/efi
```

- `/usr/lib/bootupd/updates/EFI.json` and `BIOS.json` are **metadata files**
  (bootupd's version-tracking manifests), not directories of EFI binaries.
  `EFI.json` content: `{"timestamp":"2026-09-12T02:08:33.435454090Z","version":"grub2-1:2.12-64.fc44,shim-16.1-5","versions":[{"name":"grub2","rpm_evr":"1:2.12-64.fc44"},{"name":"shim","rpm_evr":"16.1-5"}]}`
- `/usr/lib/ostree-boot/efi` is an **empty directory** (mode `0700`, no
  children) in this composed image.

The actual EFI binary payload lives elsewhere, found via a full-image search:

```
$ podman run --rm --platform=linux/amd64 quay.io/fedora-ostree-desktops/cosmic-atomic:44 \
    find /usr/lib/efi -maxdepth 6
/usr/lib/efi
/usr/lib/efi/grub2
/usr/lib/efi/grub2/1:2.12-64.fc44
/usr/lib/efi/grub2/1:2.12-64.fc44/EFI
/usr/lib/efi/grub2/1:2.12-64.fc44/EFI/fedora
/usr/lib/efi/grub2/1:2.12-64.fc44/EFI/fedora/grubia32.efi
/usr/lib/efi/grub2/1:2.12-64.fc44/EFI/fedora/grubx64.efi
/usr/lib/efi/shim
/usr/lib/efi/shim/16.1-5
/usr/lib/efi/shim/16.1-5/EFI
/usr/lib/efi/shim/16.1-5/EFI/BOOT
/usr/lib/efi/shim/16.1-5/EFI/BOOT/BOOTX64.EFI
/usr/lib/efi/shim/16.1-5/EFI/BOOT/fbx64.efi
/usr/lib/efi/shim/16.1-5/EFI/BOOT/fbia32.efi
/usr/lib/efi/shim/16.1-5/EFI/BOOT/BOOTIA32.EFI
/usr/lib/efi/shim/16.1-5/EFI/fedora
/usr/lib/efi/shim/16.1-5/EFI/fedora/shim.efi
/usr/lib/efi/shim/16.1-5/EFI/fedora/shimx64.efi
/usr/lib/efi/shim/16.1-5/EFI/fedora/BOOTIA32.CSV
/usr/lib/efi/shim/16.1-5/EFI/fedora/mmia32.efi
/usr/lib/efi/shim/16.1-5/EFI/fedora/BOOTX64.CSV
/usr/lib/efi/shim/16.1-5/EFI/fedora/mmx64.efi
/usr/lib/efi/shim/16.1-5/EFI/fedora/shimia32.efi
```

**Task 4 must hash the real binaries under `/usr/lib/efi/grub2/<grub2-evr>/EFI/fedora/`
and `/usr/lib/efi/shim/<shim-evr>/EFI/{BOOT,fedora}/`, not paths under
`/usr/lib/bootupd/updates/` or `/usr/lib/ostree-boot/efi/`.** The
version-numbered path segments (`1:2.12-64.fc44`, `16.1-5`) come from the
rpm EVRs and will change on package updates — a hashing script should not
hardcode them literally but should glob/discover them, or re-derive them
from `rpm -q grub2-efi-x64 shim-x64` at hash time.

## Environment

/etc/os-release symlink: yes — `/etc/os-release -> ../usr/lib/os-release`

bootc present: yes — `bootc-1.16.10-1.fc44.x86_64`

`/usr/lib/os-release` line count: 23 (nonzero, confirmed populated)
