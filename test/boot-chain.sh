#!/usr/bin/env bash
# Cedar boots under Secure Boot only if its signed EFI payload and kernel are
# byte-identical to the base's. Compares content digests, not package metadata.
#
# Exit 0 = payload matches. Exit 1 = Cedar broke it. Exit 2 = the guard is
# broken (which must never be reported as success).
set -euo pipefail

IMAGE="${1:?usage: boot-chain.sh <image>}"
BASE="${CEDAR_BASE:?set CEDAR_BASE to the digest-pinned base from Task 1}"
PLATFORM="${PLATFORM:-linux/amd64}"
MIN_FILES=12   # observed count is ~26; this floor catches a partial result

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# Paths verified against the real image in Task 1. Do NOT substitute the
# "obvious" ones: /usr/lib/ostree-boot/efi is EMPTY in this image, and
# /usr/lib/bootupd/updates/{EFI,BIOS}.json are metadata, not binaries. The
# signed payload lives under /usr/lib/efi/{grub2,shim}/<rpm-evr>/EFI/, where
# the <rpm-evr> segment drifts with package updates — which is why this walks
# the whole /usr/lib/efi tree rather than globbing a version into a path.
#
# /usr/lib/bootupd/updates/*.json IS hashed: it is bootupd's manifest and
# records the payload versions (grub2-1:2.12-64.fc44,shim-16.1-5), so a
# version change trips the guard even if a binary somehow hashed the same.
#
# /usr/lib/bootupd/grub2-static/ is deliberately NOT hashed: those are GRUB
# config fragments, not signed binaries, and Cedar may legitimately edit them.
manifest() {
  podman run --rm --platform="$PLATFORM" --entrypoint "" "$1" sh -c '
    set -e
    find /usr/lib/efi -type f -exec sha256sum {} +
    sha256sum /usr/lib/bootupd/updates/*.json
    for k in /usr/lib/modules/*/; do
      sha256sum "$k"vmlinuz "$k"initramfs.img
    done
  ' | sort -k2
}

for side in base cedar; do
  img=$([ "$side" = base ] && echo "$BASE" || echo "$IMAGE")
  if ! manifest "$img" > "$WORK/$side" 2>"$WORK/$side.err"; then
    echo "FAIL: could not build manifest for $img" >&2
    sed 's/^/       /' "$WORK/$side.err" >&2
    exit 2
  fi
  n=$(wc -l < "$WORK/$side")
  if (( n < MIN_FILES )); then
    echo "FAIL: $img yielded only $n boot files (expected >= $MIN_FILES)" >&2
    echo "      the guard is broken, not the image" >&2
    exit 2
  fi
done

echo "Boot chain guard"
if diff -u "$WORK/base" "$WORK/cedar"; then
  echo "  ok   signed boot payload byte-identical to base ($(wc -l < "$WORK/cedar") files)"
else
  echo "  FAIL Cedar's signed boot payload differs from the base"
  exit 1
fi
