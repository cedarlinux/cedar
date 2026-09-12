# Cedar Milestone 1 — "It boots and it is Cedar" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a Cedar-branded, signed, bootable container image built from Fedora COSMIC Atomic, published by CI, that a VM can rebase onto and boot with Secure Boot enabled showing Cedar everywhere.

**Architecture:** Cedar is a Containerfile layered on `quay.io/fedora-ostree-desktops/cosmic-atomic:44`. Branding is applied by editing the base's files in place, the image is signed with cosign and pushed to `ghcr.io` by GitHub Actions, and installation is `rpm-ostree rebase`. There is no application code — the deliverable is an image, so "tests" are assertions run against a built image with `podman run`.

**Tech Stack:** Podman, Containerfile, bash, `just`, GitHub Actions, cosign, rpm-ostree, bootupd, Fedora 44, COSMIC 1.8.

**Spec:** `docs/superpowers/specs/2026-09-12-cedar-cosmic-design.md`

> **This plan was rewritten after a five-agent review of its first draft.** Every reviewer found at least one defect that would have failed on first execution. The corrections are woven in; where a step looks unusually specific, it is because the obvious version of it is broken. Do not "simplify" `test/boot-chain.sh`, the `dracut` invocation, or the os-release editing without reading the notes attached to them.

## Global Constraints

Copied from the spec. Every task's requirements implicitly include these.

- **Never rebuild or replace `shim`, `grub2`, or the kernel.** Secure Boot is inherited from Fedora and survives only while Cedar's signed EFI payload is byte-identical to the base's. Task 4 enforces this.
- **The signed payload lives in `/usr/lib/bootupd/updates/EFI/` and `/usr/lib/ostree-boot/efi/EFI/`, not `/boot`.** On ostree, RPM content for shim and grub2 lands in `/usr` and never touches the ESP. It reaches the ESP only via `bootupctl` or an installer.
- **`rpm -V` is useless in these images.** OSTree normalises every file mtime to zero and rpm compares mtime unconditionally, so `rpm -V` reports every file as modified on a pristine image. Verify content with digests. `rpm -q` works fine.
- **GRUB branding is limited to `GRUB_BACKGROUND` and `GRUB_THEME`.** Since GRUB 2.06 `insmod` is prohibited under Secure Boot; a theme needing a module absent from Fedora's signed `grubx64.efi` halts the machine at an error prompt.
- **Target architecture is `x86_64`.** The base is a multi-arch manifest list, so every podman command needs `--platform=linux/amd64` or an arm64 host silently builds the wrong image with different package names.
- **Target COSMIC 1.8 and theme schema v2.** v1 files load on a v2 reader but not the reverse, and that shim is one version deep and explicitly temporary.
- **`bootc container lint` must be the final instruction in the Containerfile**, after all branding and initramfs work.
- **`bootc-image-builder` was archived in June 2026.** Milestone 2 uses Titanoboa or osbuild image-builder.

## Prerequisites

Complete all of these before Task 1. They are not optional; the plan fails at Task 1 Step 1 without the first two.

- [ ] **Install tooling.**

```bash
brew install podman just gh
podman machine init && podman machine start
podman version && just --version && gh auth status
```

ImageMagick (`brew install imagemagick`) is optional — used once in Task 5, with a stated fallback.

- [ ] **Understand the platform situation.** This repository is on Apple Silicon (`arm64`). The base image is a manifest list containing both `amd64` and `arm64`, so **podman will silently select arm64 and the aarch64 package set differs** — it has `shim` and `grub2-efi`, not `shim-x64` and `grub2-efi-x64`. Every podman command in this plan therefore carries `--platform=linux/amd64`, and every build runs under emulation at roughly a 10–20× penalty.

  **Recommended:** treat CI (Task 6) as the real build, use local builds only for fast iteration on the test scripts, and do Task 7 on the Linux VM host below. If local emulated builds prove too slow, do Tasks 2–5 directly on that host.

- [ ] **Create the GitHub repository and set the remote.** There is currently no remote; Task 6 pushes.

```bash
export NAMESPACE=<your-github-username-or-org>   # lowercase
gh repo create "$NAMESPACE/cedar" --private --source=. --remote=origin
git push -u origin main
gh api "repos/$NAMESPACE/cedar/actions/permissions"
```

**`NAMESPACE` is bound once, here. Every `<namespace>` in this plan means that value — including inside the README committed in Task 2 and the rebase commands in Task 7.** Write it at the top of your working notes.

- [ ] **Provision a Linux VM host for Task 7** with UEFI and Secure Boot support. On Apple Silicon an x86_64 VM is emulated and painfully slow, so prefer a cheap x86_64 cloud instance with nested virtualisation, or a spare PC.

- [ ] **Create the notes directory.** Task 1 writes into it and it does not exist.

```bash
mkdir -p docs/superpowers/notes
```

## File Structure

```
cedar/
  Containerfile              the whole image definition
  cosign.pub                 public key; the private half is a GitHub secret
  branding/
    wallpapers/              → /usr/share/backgrounds/cedar/
    logo/cedar-logo.svg      → /usr/share/pixmaps/
    plymouth-watermark.png   → the Cedar Plymouth theme's watermark
    policy.json              → /usr/etc/containers/policy.json
    ghcr.yaml                → /usr/etc/containers/registries.d/ghcr.yaml
  test/
    lib.sh                   assert helpers
    test-image.sh            identity and branding assertions
    boot-chain.sh            Secure Boot payload guard (digest comparison)
  Justfile
  .github/workflows/
    build.yml                build, test, sign, push
    nightly.yml              weekly trigger (separate file — see Task 6)
  README.md
```

`test/lib.sh` holds helpers so `test-image.sh` reads as a list of claims about the image. `boot-chain.sh` is deliberately standalone: it compares two images, not one, and has different failure semantics.

---

### Task 1: Establish the base facts cheaply

**Why first:** the spec's highest-risk open item was which COSMIC version Fedora 44 ships. Review established that F44 has been fed every upstream release and runs **1.8.0** as of 2026-09-11 — but Fedora's `mdapi` reports this wrongly, so the only trustworthy check is against the composed image. This task also records the digest and confirms the payload paths that Task 4 depends on.

**Files:**
- Create: `docs/superpowers/notes/2026-09-12-base-image-facts.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `CEDAR_BASE` — the **digest-pinned** base reference used by `Containerfile` and by `test/boot-chain.sh`. Also the confirmed EFI payload paths.

- [ ] **Step 1: Pull the base image, for the right architecture**

```bash
podman pull --platform=linux/amd64 quay.io/fedora-ostree-desktops/cosmic-atomic:44
```

- [ ] **Step 2: Record the digest — this is the pin**

```bash
podman inspect --format '{{index .RepoDigests 0}}' \
  quay.io/fedora-ostree-desktops/cosmic-atomic:44
```

Expected: `quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:…`. Everything downstream uses this, not the mutable `:44` tag.

- [ ] **Step 3: Confirm the architecture is actually amd64**

```bash
podman run --rm --platform=linux/amd64 \
  quay.io/fedora-ostree-desktops/cosmic-atomic:44 rpm -q shim-x64 grub2-efi-x64
```

Expected: both resolve. If you see `package shim-x64 is not installed`, you are on the arm64 image — the `--platform` flag was dropped or podman ignored it. Stop and fix before continuing; nothing later in this plan works on the wrong arch.

- [ ] **Step 4: Read the COSMIC version from the composed image**

```bash
podman run --rm --platform=linux/amd64 \
  quay.io/fedora-ostree-desktops/cosmic-atomic:44 \
  rpm -q cosmic-session cosmic-comp cosmic-settings cosmic-panel
```

Expected: `1.8.0-1.fc44` or newer. If it reports `1.0.x`, the image is stale relative to Fedora's updates — record it and raise it before Task 2, but do **not** trust `mdapi` as a second opinion; use Koji (`listTagged("f44-updates", package="cosmic-session", latest=1)`).

- [ ] **Step 5: Confirm the EFI payload paths Task 4 will hash**

```bash
podman run --rm --platform=linux/amd64 \
  quay.io/fedora-ostree-desktops/cosmic-atomic:44 \
  find /usr/lib/bootupd /usr/lib/ostree-boot -maxdepth 4
```

> **Answered by Task 1, and the answer was not what this step expected.** This
> step originally predicted trees under `/usr/lib/bootupd/updates/EFI/` and
> `/usr/lib/ostree-boot/efi/EFI/`. Both are wrong: the first holds only
> `EFI.json`/`BIOS.json` metadata, and the second is an **empty directory**. The
> signed payload is at `/usr/lib/efi/grub2/<evr>/EFI/fedora/` and
> `/usr/lib/efi/shim/<evr>/EFI/{BOOT,fedora}/`. Task 4 has been corrected
> accordingly. Kept here as a record of why this verification step exists: had
> Task 4 run against the predicted paths, the guard would have hashed an empty
> directory and two metadata files, found them identical, and reported the Secure
> Boot payload verified — failing open on the one check this milestone exists to
> make.

Note the actual paths — Task 4's script walks them, and they must match.

- [ ] **Step 6: Confirm `/etc/os-release` is a symlink and `bootc` is present**

```bash
podman run --rm --platform=linux/amd64 \
  quay.io/fedora-ostree-desktops/cosmic-atomic:44 \
  sh -c 'ls -l /etc/os-release; rpm -q bootc; grep -c . /usr/lib/os-release'
```

Expected: a symlink to `../usr/lib/os-release`, a `bootc` version, and a nonzero line count. If `bootc` is absent, `bootc container lint` in Task 2 must be replaced with `ostree container commit`.

- [ ] **Step 7: Write the facts down**

Create `docs/superpowers/notes/2026-09-12-base-image-facts.md`:

```markdown
# Base image facts — recorded 2026-09-12

Image:  quay.io/fedora-ostree-desktops/cosmic-atomic:44
Digest: <paste Step 2 — this is CEDAR_BASE>
Arch confirmed amd64: <yes/no, paste Step 3>

## COSMIC version (from the composed image, not mdapi)
<paste Step 4>

## EFI payload paths (Task 4 hashes these)
<paste Step 5>

## Environment
/etc/os-release symlink: <yes/no>
bootc present: <version or absent>
```

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/notes/2026-09-12-base-image-facts.md
git commit -m "Record Fedora COSMIC Atomic base image facts

Confirms COSMIC version from the composed image, pins the base digest,
and records the EFI payload paths the boot-chain guard depends on."
```

---

### Task 2: Scaffold, minimal Containerfile, test harness, README

**Files:**
- Create: `Containerfile`, `test/lib.sh`, `test/test-image.sh`, `Justfile`, `README.md`

**Interfaces:**
- Consumes: the digest from Task 1.
- Produces: `just build` (builds `localhost/cedar:dev`), `just test`, and the helpers `check <desc> <expected-substring> <command...>` and `check_file_exists <desc> <path>` in `test/lib.sh`.

- [ ] **Step 1: Write the assertion helpers**

Create `test/lib.sh`:

```bash
#!/usr/bin/env bash
# Assertion helpers for Cedar image tests. Sourced by test-image.sh.
# NOTE: every podman run needs --platform=linux/amd64; the base is multi-arch
# and an arm64 host silently selects the wrong image.

FAILURES=0
PLATFORM="${PLATFORM:-linux/amd64}"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# check <description> <expected-substring> <command...>
check() {
  local desc=$1 expected=$2
  shift 2
  local actual rc
  actual=$(podman run --rm --platform="$PLATFORM" "$IMAGE" "$@" 2>&1); rc=$?
  if (( rc != 0 )); then
    fail "$desc (command exited $rc)"
    printf '       %s\n' "${actual:0:300}"
    return
  fi
  if [[ "$actual" == *"$expected"* ]]; then
    pass "$desc"
  else
    fail "$desc"
    printf '       expected to contain: %s\n' "$expected"
    printf '       got: %s\n' "${actual:0:400}"
  fi
}

# check_file_exists <description> <path>
check_file_exists() {
  local desc=$1 path=$2
  if podman run --rm --platform="$PLATFORM" "$IMAGE" test -e "$path" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
    printf '       missing: %s\n' "$path"
  fi
}

# summary MUST be the last line of the calling script — it sets the exit status.
summary() {
  echo
  if (( FAILURES == 0 )); then
    printf '\033[32mAll checks passed.\033[0m\n'
    return 0
  fi
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAILURES"
  return 1
}
```

Note `check` now fails on a nonzero exit code. The first draft treated a crashed command as a pass, which is how a test suite reports green while testing nothing.

- [ ] **Step 2: Write the failing test**

Create `test/test-image.sh`:

```bash
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
```

That last assertion exists because the obvious implementation — `COPY`ing a whole os-release file — silently deletes the `OSTREE_VERSION` that rpm-ostree injects, leaving every Cedar deployment with a blank version in `rpm-ostree status` and a boot entry missing its version suffix.

- [ ] **Step 3: Write the minimal Containerfile**

Create `Containerfile`, substituting the digest from Task 1:

```dockerfile
# Cedar — a Fedora COSMIC Atomic derivative.
#
# HARD CONSTRAINT: never rebuild or replace shim, grub2, or the kernel.
# Cedar's Secure Boot support is inherited from Fedora and survives only while
# its signed EFI payload is byte-identical to the base. test/boot-chain.sh
# enforces this. See the design spec.
#
# Pinned by digest: the :44 tag is mutable, and a moving base would make the
# boot-chain guard compare against something the build never used.
FROM quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:<DIGEST_FROM_TASK_1>

# bootc container lint MUST be the last instruction — it validates the final
# filesystem. Anything added below it goes unlinted.
RUN bootc container lint
```

- [ ] **Step 4: Write the Justfile**

Create `Justfile`:

```make
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
```

The `test` recipe is a single bash script rather than two lines because `just` runs recipe lines separately and aborts on the first failure — which would mean a red image test silently skips the Secure Boot guard entirely.

`boot-chain.sh` does not exist until Task 4; `just test` will report it missing until then. That is expected.

- [ ] **Step 5: Build**

```bash
chmod +x test/test-image.sh test/lib.sh
just build
```

Expected: build succeeds, `bootc container lint` passes. Emulated on Apple Silicon this is slow — several minutes is normal.

- [ ] **Step 6: Run the test to verify it fails for the right reason**

```bash
./test/test-image.sh localhost/cedar:dev
```

Expected: the three identity checks FAIL (the base still says Fedora); `OSTREE_VERSION` passes, since the base has it. Do not continue until you have seen this.

- [ ] **Step 7: Write the README**

Create `README.md`, substituting `NAMESPACE`:

````markdown
# Cedar

A Fedora COSMIC Atomic derivative. Mouse-first, deeply themeable.

## Install

Install Fedora COSMIC Atomic, then rebase onto Cedar:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<namespace>/cedar:44
sudo systemctl reboot
```

A Cedar ISO that installs directly, with no Fedora step, arrives in milestone 2.

## Develop

```bash
just build     # build locally (amd64; emulated and slow on Apple Silicon)
just test      # assertions plus the Secure Boot payload guard
just check     # both
```

## Hard constraints

- Never rebuild or replace `shim`, `grub2` or the kernel. Secure Boot is
  inherited from Fedora and survives only while Cedar's signed EFI payload is
  byte-identical to the base. `test/boot-chain.sh` enforces this.
- GRUB branding is limited to `GRUB_BACKGROUND` and `GRUB_THEME` — `insmod` is
  prohibited under Secure Boot.
- `rpm -V` is meaningless in these images; ostree zeroes all mtimes.
````

- [ ] **Step 8: Commit**

```bash
git add Containerfile Justfile test/ README.md
git commit -m "Add Containerfile scaffold, image test harness and README

Base pinned by digest. Test asserts Cedar identity and currently fails
against the unmodified Fedora base, which is the expected starting state."
```

---

### Task 3: Cedar identity

**Files:**
- Modify: `Containerfile`

**Interfaces:**
- Consumes: `check` from `test/lib.sh`.
- Produces: `/usr/lib/os-release` with Cedar identity and `OSTREE_VERSION` intact; `/etc/system-release`; a pinned `EFIDIR` in `grub2-switch-to-blscfg`.

**Why this edits in place rather than copying a file:** rpm-ostree injects `OSTREE_VERSION=` into os-release during the build. A wholesale `COPY` deletes it. Bazzite seds for exactly this reason.

- [ ] **Step 1: Add the branding layer**

Modify `Containerfile`, inserting **before** the `bootc container lint` line:

```dockerfile
# Cedar identity. Edited in place rather than replaced, so that the
# OSTREE_VERSION rpm-ostree injects at build time survives. /etc/os-release is
# a symlink to this file.
RUN set -eux; \
    sed -i 's/^NAME=.*/NAME="Cedar"/'                          /usr/lib/os-release; \
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Cedar 44"/'         /usr/lib/os-release; \
    sed -i 's/^VARIANT=.*/VARIANT="COSMIC Atomic"/'            /usr/lib/os-release; \
    sed -i 's/^VARIANT_ID=.*/VARIANT_ID=cedar/'                /usr/lib/os-release; \
    sed -i 's/^ID=fedora/ID=cedar\nID_LIKE="fedora"/'          /usr/lib/os-release; \
    sed -i 's|^HOME_URL=.*|HOME_URL="https://cedarlinux.org/"|' /usr/lib/os-release; \
    sed -i 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/cedarlinux/cedar/issues"|' /usr/lib/os-release; \
    sed -i '/^REDHAT_BUGZILLA_PRODUCT/d; /^REDHAT_SUPPORT_PRODUCT/d; /^SUPPORT_URL/d; /^DOCUMENTATION_URL/d' /usr/lib/os-release; \
    echo "Cedar release 44 (COSMIC Atomic)" > /etc/system-release; \
    sed -i 's/^EFIDIR=.*/EFIDIR="fedora"/' /usr/sbin/grub2-switch-to-blscfg

# Cedar identity, continued: the ostree boot entry title comes from
# PRETTY_NAME in /usr/lib/os-release, which ostree reads in preference to
# /etc/os-release. No separate GRUB title branding is needed or possible.
```

Three lines are load-bearing and must not be simplified:

- `ID_LIKE="fedora"` — third-party installers detect Fedora compatibility through it.
- `/etc/system-release` — `grub2-mkconfig` derives `GRUB_DISTRIBUTOR` from it, and the base enables `bootupctl migrate-static-grub-config`, so it does run.
- **`EFIDIR="fedora"`** — `grub2-switch-to-blscfg` computes its EFI directory as `EFIDIR=$(grep ^ID= /etc/os-release | sed 's/^ID=//')` and then looks in `/boot/efi/EFI/${EFIDIR}/`. Setting `ID=cedar` points it at a directory that does not exist. Bazzite carries the identical fix, commented "Fix issues caused by ID no longer being fedora." Without this the bootloader path breaks in a way that is miserable to diagnose.

- [ ] **Step 2: Rebuild and verify the tests pass**

```bash
just build
./test/test-image.sh localhost/cedar:dev
```

Expected: all four identity checks pass, `OSTREE_VERSION` included.

- [ ] **Step 3: Confirm the symlink and the EFIDIR fix**

```bash
podman run --rm --platform=linux/amd64 localhost/cedar:dev sh -c \
  'head -3 /etc/os-release; cat /etc/system-release; grep ^EFIDIR= /usr/sbin/grub2-switch-to-blscfg'
```

Expected: Cedar in `/etc/os-release`, the Cedar release string, and `EFIDIR="fedora"`.

- [ ] **Step 4: Commit**

```bash
git add Containerfile
git commit -m "Brand Cedar identity

Edits os-release in place so rpm-ostree's injected OSTREE_VERSION
survives. Pins EFIDIR=fedora in grub2-switch-to-blscfg, which otherwise
derives it from ID= and looks in a directory that does not exist."
```

---

### Task 4: Guard the Secure Boot payload

**This is not TDD and does not pretend to be.** A guard is green on a correct image; there is no red phase to write first. Step 3 is what proves it can go red.

**Files:**
- Create: `test/boot-chain.sh`

**Interfaces:**
- Consumes: the base digest from Task 1, passed as `CEDAR_BASE`.
- Produces: `test/boot-chain.sh`, exiting **0** when the payload matches, **1** when Cedar broke it, and **2** when the guard itself is broken.

**Why it compares digests rather than package metadata:** `rpm -V` can never pass here, because ostree normalises every file mtime to zero and rpm compares mtime unconditionally. And package NVRs would miss replaced binaries, *added* files, and same-version rebuilds. Hashing the actual payload catches all three.

- [ ] **Step 1: Write the guard**

Create `test/boot-chain.sh`:

```bash
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
```

- [ ] **Step 2: Run it — expect green on a correct image**

```bash
chmod +x test/boot-chain.sh
export CEDAR_BASE="quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:<DIGEST_FROM_TASK_1>"
./test/boot-chain.sh localhost/cedar:dev
```

Expected: `ok   signed boot payload byte-identical to base (N files)` with N comfortably above 6. If it exits 2, the paths from Task 1 Step 5 do not match what the script hardcodes — fix the script's `find` paths, not the floor.

- [ ] **Step 3: Prove the guard can go red**

A guard that has never failed is untested. Temporarily add to `Containerfile`, before `bootc container lint`:

```dockerfile
RUN KV="$(rpm -q --queryformat='%{evr}.%{arch}' kernel-core)"; \
    printf '\n# cedar violated the boot chain\n' >> "/usr/lib/modules/${KV}/initramfs.img"
```

Then:

```bash
just build
./test/boot-chain.sh localhost/cedar:dev; echo "exit=$?"
```

Expected: **exit 1**, with a diff naming the `initramfs.img` line. If it exits 0, the guard is broken — fix it before continuing. This mutation is chosen because it changes file *content*, which digests always catch; a `dnf install` would not work here, since these images have no meaningful package-install path and the package may already be present.

- [ ] **Step 4: Remove the violation and confirm green**

Delete the `RUN` block added in Step 3, then:

```bash
just build
./test/boot-chain.sh localhost/cedar:dev; echo "exit=$?"
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add test/boot-chain.sh
git commit -m "Add Secure Boot payload guard

Compares sha256 of the EFI payload trees and kernel pair against the
digest-pinned base. Uses content digests because rpm -V is meaningless
under ostree (all mtimes are zeroed) and package NVRs miss replaced or
added files. Exit 2 distinguishes a broken guard from a broken image so
it can never fail open."
```

---

### Task 5: Visual branding — wallpaper, logo, Plymouth

**Files:**
- Create: `branding/wallpapers/cedar-default.jpg`, `branding/logo/cedar-logo.svg`, `branding/plymouth-watermark.png`
- Modify: `Containerfile`, `test/test-image.sh`

**Interfaces:**
- Consumes: `check`, `check_file_exists`.
- Produces: wallpaper and logo on disk, and a `cedar` Plymouth theme set as default with a regenerated initramfs.

> ### ⚠ Cedar's visual identity is NOT decided
>
> The greens (`#1B3A34`, `#5D8A6B`, `#7FC9A6`), the logo, and the `ANSI_COLOR`
> value in os-release were **invented by the assistant while drafting**, not
> chosen by the project owner. They are placeholders carried forward only so
> the plumbing can be built and tested.
>
> **Do not treat them as settled, and do not add more artwork derived from
> them.** The identity is a separate decision, to be taken deliberately before
> the milestone 2 ISO — after which changing it means republishing the image,
> the Plymouth theme and the installer. Every file below is intentionally
> trivial to replace.

Wallpaper *design* is not this milestone's job — a solid colour placeholder is fine. This task proves the plumbing.

- [ ] **Step 1: Write the failing tests**

Modify `test/test-image.sh`, appending **before** the `summary` call (which must remain last — it sets the exit status):

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

```bash
just build && ./test/test-image.sh localhost/cedar:dev
```

Expected: the branding checks FAIL except the initramfs one, which passes because the base ships one. Identity checks still pass.

- [ ] **Step 3: Create the placeholder assets**

```bash
mkdir -p branding/wallpapers branding/logo
magick -size 3840x2160 xc:'#5D8A6B' branding/wallpapers/cedar-default.jpg
magick -size 256x256 xc:none -fill '#7FC9A6' \
  -draw 'polygon 128,32 176,112 144,112 180,176 76,176 112,112 80,112' \
  branding/plymouth-watermark.png
```

If ImageMagick is unavailable, any 16:9 JPEG at the first path and any PNG with transparency at the second will do.

Create `branding/logo/cedar-logo.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <rect width="64" height="64" rx="14" fill="#1B3A34"/>
  <path d="M32 12 L44 30 L36 30 L45 46 L19 46 L28 30 L20 30 Z" fill="#7FC9A6"/>
  <rect x="29" y="44" width="6" height="10" rx="2" fill="#4A7C59"/>
</svg>
```

- [ ] **Step 4: Add the branding layer**

Modify `Containerfile`, inserting after the identity layer and **before** `bootc container lint`:

```dockerfile
# Wallpapers and logo
COPY branding/wallpapers/ /usr/share/backgrounds/cedar/
COPY branding/logo/cedar-logo.svg /usr/share/pixmaps/cedar-logo.svg
COPY branding/plymouth-watermark.png /tmp/cedar-watermark.png

# Plymouth. Derived from the stock spinner theme so Cedar inherits a working
# splash rather than authoring one, then renamed and re-watermarked.
RUN set -eux; \
    cp -r /usr/share/plymouth/themes/spinner /usr/share/plymouth/themes/cedar; \
    mv /usr/share/plymouth/themes/cedar/spinner.plymouth \
       /usr/share/plymouth/themes/cedar/cedar.plymouth; \
    sed -i 's/^Name=.*/Name=Cedar/;s/^Description=.*/Description=Cedar boot splash/' \
       /usr/share/plymouth/themes/cedar/cedar.plymouth; \
    sed -i 's|ImageDir=.*|ImageDir=/usr/share/plymouth/themes/cedar|' \
       /usr/share/plymouth/themes/cedar/cedar.plymouth; \
    cp /tmp/cedar-watermark.png /usr/share/plymouth/themes/cedar/watermark.png; \
    rm -f /tmp/cedar-watermark.png; \
    plymouth-set-default-theme cedar

# Regenerate the initramfs so the Plymouth theme is actually present at boot.
# MANDATORY, not optional: the base ships an initramfs containing Fedora's
# theme. Note the target path — on Atomic /boot is empty, so plain
# `dracut --force --regenerate-all` writes nowhere useful. `--add ostree` is
# required or the result cannot boot an ostree system.
RUN set -eux; \
    KV="$(rpm -q --queryformat='%{evr}.%{arch}' kernel-core)"; \
    export DRACUT_NO_XATTR=1; \
    dracut --no-hostonly --kver "$KV" --reproducible --zstd -v --add ostree \
           -f "/usr/lib/modules/${KV}/initramfs.img"; \
    chmod 0600 "/usr/lib/modules/${KV}/initramfs.img"
```

- [ ] **Step 5: Rebuild and verify branding tests pass**

```bash
just build && ./test/test-image.sh localhost/cedar:dev
```

Expected: all identity and branding checks pass.

- [ ] **Step 6: Confirm the boot-chain guard now fails, and understand why**

```bash
./test/boot-chain.sh localhost/cedar:dev; echo "exit=$?"
```

Expected: **exit 1**, diffing on `initramfs.img`. This is correct and expected — Cedar deliberately regenerated it. The initramfs is *not* a signed EFI binary and regenerating it does not affect Secure Boot, so it must be excluded from the comparison while shim, grub2 and `vmlinuz` remain guarded.

Modify `test/boot-chain.sh`, changing the kernel loop inside `manifest()` from:

```bash
      sha256sum "$k"vmlinuz "$k"initramfs.img
```

to:

```bash
      # initramfs.img is deliberately regenerated by Cedar (Plymouth theme) and
      # is not a signed EFI binary. vmlinuz stays guarded.
      sha256sum "$k"vmlinuz
```

Then re-run: expected exit 0.

- [ ] **Step 7: Commit**

```bash
git add branding/ Containerfile test/test-image.sh test/boot-chain.sh
git commit -m "Add Cedar wallpaper, logo and Plymouth theme

Plymouth derives from the stock spinner theme rather than being authored,
and the initramfs is regenerated at /usr/lib/modules/<kver>/ with --add
ostree, since /boot is empty on Atomic and the base initramfs carries
Fedora's theme. Boot-chain guard now excludes initramfs.img, which Cedar
legitimately regenerates and which is not a signed EFI binary."
```

---

### Task 6: CI builds, signs and publishes

**Files:**
- Create: `.github/workflows/build.yml`, `.github/workflows/nightly.yml`, `cosign.pub`
- Modify: `Containerfile`, `branding/policy.json`, `branding/ghcr.yaml`

**Interfaces:**
- Consumes: everything above.
- Produces: a cosign-signed `ghcr.io/<namespace>/cedar:44` and `:latest`.

**Why signing is in milestone 1 rather than later:** the rebase string is the product — it goes in the README now and the ISO in milestone 2 — and the signature policy must already be present *in the image the user is running*. Retrofitting forces every existing install to re-rebase to a new URL.

- [ ] **Step 1: Generate the signing key**

```bash
cosign generate-key-pair
```

Enter an empty password when prompted. This writes `cosign.key` and `cosign.pub`.

**`cosign.key` is secret and must never be committed.** Store it as a GitHub secret and delete the local copy:

```bash
gh secret set SIGNING_SECRET < cosign.key
rm cosign.key
echo "cosign.key" >> .gitignore
```

- [ ] **Step 2: Add the policy files**

Create `branding/policy.json`:

```json
{
  "default": [{ "type": "insecureAcceptAnything" }],
  "transports": {
    "docker": {
      "ghcr.io/<namespace>/cedar": [
        {
          "type": "sigstoreSigned",
          "keyPath": "/usr/etc/pki/containers/cedar.pub",
          "signedIdentity": { "type": "matchRepository" }
        }
      ]
    },
    "docker-daemon": { "": [{ "type": "insecureAcceptAnything" }] }
  }
}
```

Create `branding/ghcr.yaml` — the step everyone forgets, without which signature lookup fails:

```yaml
docker:
  ghcr.io:
    use-sigstore-attachments: true
```

- [ ] **Step 3: Bake the policy into the image**

Modify `Containerfile`, inserting before `bootc container lint`:

```dockerfile
# Signature verification policy. Ships in the image so that `rpm-ostree rebase
# ostree-image-signed:` works on a running Cedar system.
COPY cosign.pub /usr/etc/pki/containers/cedar.pub
COPY branding/policy.json /usr/etc/containers/policy.json
COPY branding/ghcr.yaml /usr/etc/containers/registries.d/ghcr.yaml
```

- [ ] **Step 4: Write the build workflow**

Create `.github/workflows/build.yml`:

```yaml
name: Build Cedar image

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true

env:
  IMAGE_NAME: cedar

jobs:
  build:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v5

      - name: Free disk space
        uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: true
          large-packages: false

      # ghcr.io requires a lowercase namespace; github.repository_owner
      # preserves the account's original casing, so a capitalised username
      # would fail at push time with "repository name must be lowercase".
      - name: Compute registry
        env:
          OWNER: ${{ github.repository_owner }}
        run: echo "IMAGE_REGISTRY=ghcr.io/${OWNER,,}" >> "$GITHUB_ENV"

      - name: Build image
        run: podman build --platform=linux/amd64 --pull=always -t "${IMAGE_NAME}:ci" .

      - name: Run image tests
        env:
          CEDAR_BASE: quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:<DIGEST_FROM_TASK_1>
        run: |
          ./test/test-image.sh "${IMAGE_NAME}:ci"
          ./test/boot-chain.sh "${IMAGE_NAME}:ci"

      - name: Log in to ghcr.io
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push
        if: github.event_name != 'pull_request'
        id: push
        run: |
          podman tag "${IMAGE_NAME}:ci" "${IMAGE_REGISTRY}/${IMAGE_NAME}:44"
          podman tag "${IMAGE_NAME}:ci" "${IMAGE_REGISTRY}/${IMAGE_NAME}:latest"
          podman push "${IMAGE_REGISTRY}/${IMAGE_NAME}:44"
          podman push "${IMAGE_REGISTRY}/${IMAGE_NAME}:latest"
          digest=$(skopeo inspect --format '{{.Digest}}' \
            "docker://${IMAGE_REGISTRY}/${IMAGE_NAME}:44")
          echo "digest=$digest" >> "$GITHUB_OUTPUT"

      - uses: sigstore/cosign-installer@v3
        if: github.event_name != 'pull_request'

      - name: Sign by digest
        if: github.event_name != 'pull_request'
        env:
          COSIGN_PRIVATE_KEY: ${{ secrets.SIGNING_SECRET }}
        run: |
          cosign sign --yes --key env://COSIGN_PRIVATE_KEY \
            "${IMAGE_REGISTRY}/${IMAGE_NAME}@${{ steps.push.outputs.digest }}"

  # A reset of the package's visibility is silent and breaks every user's
  # rebase. Catch it here instead.
  verify-public:
    needs: build
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-24.04
    steps:
      - env:
          OWNER: ${{ github.repository_owner }}
        run: |
          REG="ghcr.io/${OWNER,,}"
          skopeo inspect "docker://${REG}/cedar:44" > /dev/null
          echo "Anonymous pull works."
```

`docker/login-action` is used rather than `podman login -p`, which would place the token in the process argument list. Podman reads the resulting config.

- [ ] **Step 5: Write the nightly workflow separately**

Create `.github/workflows/nightly.yml`:

```yaml
name: Nightly rebuild

# In its own file deliberately: GitHub disables a workflow after 60 days of
# repository inactivity, and it disables the ENTIRE FILE. Keeping the schedule
# here means a lapse stops the weekly rebuild but never stops push builds.
# The minute is off-the-hour because on-the-hour slots are frequently dropped.
on:
  schedule:
    - cron: "17 5 * * 1"
  workflow_dispatch:

jobs:
  trigger:
    runs-on: ubuntu-24.04
    permissions:
      actions: write
    steps:
      - uses: actions/checkout@v5
      - run: gh workflow run build.yml --ref main
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 6: Commit and push**

```bash
git add .github/ cosign.pub branding/policy.json branding/ghcr.yaml Containerfile .gitignore
git commit -m "Build, test, sign and publish Cedar from CI

Signing is in milestone 1 because the rebase string is the product and
the verification policy must already be inside the image the user runs;
retrofitting would force every install to re-rebase. Nightly schedule
lives in its own file so GitHub's 60-day inactivity disable cannot take
push builds down with it."
git push
```

- [ ] **Step 7: Trigger the workflow and watch it**

The workflow triggers on `push` to `main`, and this work is on `milestone-1`, so
pushing will not fire it. Merging an unverified CI workflow into `main` purely to
test it is backwards, so use the `workflow_dispatch` trigger the workflow already
declares — it exercises the identical job graph:

```bash
gh workflow run build.yml --ref milestone-1
sleep 5 && gh run watch
```

Expected: build, both test suites, login, push, sign, and the `verify-public`
job. The `on: push` trigger needs no change and starts working naturally once
`milestone-1` merges to `main`.

- [ ] **Step 8: Make the package public**

New ghcr.io packages are private, **packages do not inherit repository visibility**, and there is no supported API to change it. On GitHub: **Profile → Packages → cedar → Package settings → Change visibility → Public.**

Then re-run the workflow; `verify-public` should pass. If it fails, the visibility change did not take.

---

### Task 7a: Rebase a VM and verify identity

**Files:**
- None; this task produces evidence for 7b.

- [ ] **Step 1: Install Fedora COSMIC Atomic in a VM**

Download from <https://fedoraproject.org/atomic-desktops/cosmic/>. Allocate 4 GB RAM, 2 vCPUs, 40 GB disk, UEFI firmware, and **Secure Boot enabled** — verifying under Secure Boot is the point.

- [ ] **Step 2: Confirm the control condition**

```bash
grep PRETTY_NAME /etc/os-release
bootctl status | grep -i 'secure boot'
```

Expected: Fedora, and Secure Boot reported enabled. If Secure Boot is off here, 7b's central claim cannot be tested — fix the VM firmware first.

- [ ] **Step 3: Rebase onto Cedar**

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<namespace>/cedar:44
```

Expected: pull succeeds, signature verifies, a new deployment is staged.

If it fails on **signature verification**, the stock Fedora system has no Cedar policy yet — that only ships *inside* Cedar. Rebase unsigned this once, and verify signed rebases on the second hop:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/<namespace>/cedar:44
```

If it fails with **401**, the package is still private — return to Task 6 Step 8.

- [ ] **Step 4: Reboot and verify identity from a shell**

```bash
sudo systemctl reboot
# after login:
grep PRETTY_NAME /etc/os-release
rpm-ostree status
bootctl status | grep -i 'secure boot'
ls /usr/share/backgrounds/cedar/
plymouth-set-default-theme
rpm -q cosmic-session
```

Expected: `PRETTY_NAME="Cedar 44"`; `rpm-ostree status` shows the Cedar image booted **with a non-empty version column** (that column is why Task 3 seds rather than copies); Secure Boot still enabled; wallpaper present; `cedar` as the Plymouth theme; COSMIC 1.8.

- [ ] **Step 5: Verify a signed rebase works from Cedar**

Now that Cedar's policy is on disk:

```bash
sudo rpm-ostree upgrade
```

Expected: succeeds with signature verification.

---

### Task 7b: Observe the boot, exercise bootupd, verify rollback

- [ ] **Step 1: Record what the boot sequence shows**

Reboot and watch. Fill in:

| Surface | Expected | Result |
|---|---|---|
| GRUB menu entry | contains `Cedar 44` — ostree appends a commit suffix, so `Cedar 44 (ostree:0)` is correct, not a failure | |
| Plymouth splash | Cedar theme with Cedar watermark, not Fedora's | |
| Greeter | reaches COSMIC's greeter | |
| Boots under Secure Boot | yes | |

- [ ] **Step 2: Exercise bootupd — the only real Secure Boot test in this milestone**

Everything so far booted from the ESP *Fedora's installer* wrote. Cedar's own shim and grub2 have never been in front of the firmware. This is what puts them there:

```bash
sudo bootupctl status
```

Record whether it reports updates available and whether auto-update is enabled. Then:

```bash
sudo bootupctl update
sudo systemctl reboot
```

Expected: the machine boots, with Secure Boot still enabled. **If it fails to boot here, Cedar's EFI payload is broken** — recover by booting the previous deployment from the GRUB menu, and treat it as a Task 4 failure: the guard did not catch something it should have.

- [ ] **Step 3: Verify rollback in both directions**

This is the property that replaced snapper and `grub-btrfs`, so prove it:

```bash
sudo rpm-ostree rollback && sudo systemctl reboot
# expect Fedora; then:
sudo rpm-ostree rollback && sudo systemctl reboot
# expect Cedar again
```

- [ ] **Step 4: Record the results**

Create `docs/superpowers/notes/2026-09-12-milestone-1-boot-verification.md` containing the Step 1 table, the `bootupctl status` output, whether the post-`bootupctl` boot succeeded, whether rollback worked both ways, and a **"still Fedora"** list — every place the system still says Fedora that Cedar has not claimed (greeter text, COSMIC's About panel, `/etc/issue`, hostname, anything else). That list is milestone 3's input.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/2026-09-12-milestone-1-boot-verification.md
git commit -m "Record milestone 1 boot verification

Cedar boots with Secure Boot enabled, survives bootupctl update onto
Cedar's own EFI payload, and rolls back in both directions."
git push
```

---

## Milestone 1 complete when

- `just check` passes locally: identity, branding, and the boot-chain guard.
- The guard has been **observed failing** (Task 4 Step 3) and then passing.
- CI builds, tests, signs and publishes on every push; `verify-public` passes.
- A VM rebased onto Cedar boots **with Secure Boot enabled**, shows `Cedar 44` in the GRUB menu, and reaches COSMIC's greeter.
- **`bootupctl update` has been run and the machine still boots** — the only step that puts Cedar's own EFI payload in front of the firmware.
- `rpm-ostree status` shows a non-empty version for Cedar deployments.
- `rpm-ostree rollback` works in both directions.
- The COSMIC version is recorded from the composed image.
- The "still Fedora" list exists for milestone 3.
