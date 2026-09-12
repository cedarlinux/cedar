image := "localhost/cedar:dev"

# Build the Cedar image locally (amd64 — the base is multi-arch)
build:
    podman build --platform=linux/amd64 --pull=always -t {{image}} .

# Run every check; both suites run even if the first fails
test:
    #!/usr/bin/env bash
    set -uo pipefail
    rc=0
    ./test/test-image.sh {{image}} || rc=1
    ./test/boot-chain.sh {{image}} || rc=1
    exit $rc

check: build test

identity:
    podman run --rm --platform=linux/amd64 {{image}} cat /usr/lib/os-release
