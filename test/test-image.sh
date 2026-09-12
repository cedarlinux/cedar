#!/usr/bin/env bash
# Assertions about a built Cedar image.
# Usage: test/test-image.sh [image-tag]
set -uo pipefail

IMAGE="${1:-localhost/cedar:dev}"
export IMAGE

cd "$(dirname "$0")"
# shellcheck source=lib.sh
source ./lib.sh

echo "Testing image: $IMAGE"
echo
echo "Identity"
check "os-release NAME is Cedar"          'NAME="Cedar"'      cat /usr/lib/os-release
check "os-release ID is cedar"            'ID=cedar'          cat /usr/lib/os-release
check "os-release keeps ID_LIKE=fedora"   'ID_LIKE="fedora"'  cat /usr/lib/os-release
check "OSTREE_VERSION survived branding"  'OSTREE_VERSION'    cat /usr/lib/os-release

# EFIDIR picks the ESP vendor directory (EFI/fedora/) that the boot payload
# installs under. boot-chain.sh can't verify this: Cedar deliberately edits
# it (Task 3), so it isn't expected to match the base. A wrong value here is
# invisible to that guard and unbootable anyway — shim would hunt in
# EFI/fedora/ for a grub that landed somewhere else — so it's asserted here
# instead.
check "EFIDIR pinned to fedora (Cedar edits this; boot-chain cannot diff it)" \
  'EFIDIR="fedora"' grep '^EFIDIR=' /usr/sbin/grub2-switch-to-blscfg

echo
echo "Branding"
check_file_exists "Cedar wallpaper installed" \
  /usr/share/backgrounds/cedar/cedar-default.jpg
check_file_exists "Cedar logo installed" \
  /usr/share/pixmaps/cedar-logo.svg
check_file_exists "Cedar plymouth theme exists" \
  /usr/share/plymouth/themes/cedar/cedar.plymouth
check "plymouth default theme is cedar" "cedar" plymouth-set-default-theme
check "initramfs regenerated in /usr/lib/modules" "initramfs.img" \
  sh -c 'ls /usr/lib/modules/*/initramfs.img'
check "os-release DEFAULT_HOSTNAME is cedar" 'DEFAULT_HOSTNAME="cedar"' \
  cat /usr/lib/os-release
check "os-release LOGO points at Cedar's logo" 'LOGO=cedar-logo' \
  cat /usr/lib/os-release
check "os-release CPE_NAME deliberately still Fedora" 'cpe:/o:fedoraproject' \
  cat /usr/lib/os-release

summary
