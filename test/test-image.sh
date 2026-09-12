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

summary
