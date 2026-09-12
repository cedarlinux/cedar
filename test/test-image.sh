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
# NOT "does initramfs.img exist" — the untouched base already ships one, so
# that check is a tautology that stays green even if `--add ostree` were
# dropped from the Containerfile's dracut invocation and the image were left
# unbootable. This instead inspects the regenerated initramfs's actual
# contents for the ostree dracut module's binary, preferring lsinitrd (part
# of the same dracut package the Containerfile already invokes) and falling
# back to a raw content scan of the decompressed archive if lsinitrd is ever
# unavailable.
check "regenerated initramfs actually contains ostree-prepare-root" "FOUND" \
  sh -c '
    set -e
    KV="$(rpm -q --queryformat="%{evr}.%{arch}" kernel-core)"
    IMG="/usr/lib/modules/$KV/initramfs.img"
    if command -v lsinitrd >/dev/null 2>&1; then
      lsinitrd "$IMG" 2>/dev/null | grep -q ostree-prepare-root && echo FOUND
    else
      zstd -dc "$IMG" 2>/dev/null | grep -a -q ostree-prepare-root && echo FOUND
    fi
  '
check "os-release DEFAULT_HOSTNAME is cedar" 'DEFAULT_HOSTNAME="cedar"' \
  cat /usr/lib/os-release
check "os-release LOGO points at Cedar's logo" 'LOGO=cedar-logo' \
  cat /usr/lib/os-release
check "os-release CPE_NAME deliberately still Fedora" 'cpe:/o:fedoraproject' \
  cat /usr/lib/os-release

echo
echo "Signature policy"
check_file_exists "cosign public key installed" /etc/pki/containers/cedar.pub
check_file_exists "containers policy installed"  /etc/containers/policy.json
check_file_exists "ghcr registries.d installed"  /etc/containers/registries.d/ghcr.yaml
check "policy keyPath points at Cedar's key" '/etc/pki/containers/cedar.pub' \
  cat /etc/containers/policy.json

summary
