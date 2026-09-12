# Cedar

A Fedora COSMIC Atomic derivative shipped as a bootable container image.
Mouse-first, deeply themeable. Built for its author to use daily.

**Design spec (binding):** `docs/superpowers/specs/2026-09-12-cedar-cosmic-design.md`
Two earlier specs in that directory are marked SUPERSEDED — read the header
before using either.

The deliverable is an **image**, not application code. "Tests" are assertions
executed against a built image with `podman run`.

```bash
just build     # build localhost/cedar:dev
just test      # assertions + the Secure Boot payload guard
just check     # both
```

## Hard constraints

Each of these was learned the expensive way. The reasoning is in
`docs/superpowers/notes/2026-09-12-milestone-1-execution-ledger.md`.

- **Never rebuild or replace `shim`, `grub2`, or the kernel.** Cedar boots under
  Secure Boot only by inheriting Fedora's signed payload byte-for-byte.
  `test/boot-chain.sh` enforces it. If that guard fails, stop — do not weaken it.
- **`bootc container lint` must be the LAST instruction in the Containerfile.**
  Anything after it goes unlinted.
- **Never write to `/usr/etc`.** `bootc container lint` rejects it outright.
  Image content in `/etc` becomes `/usr/etc` at deploy time on its own.
- **`rpm -V` is meaningless in these images.** OSTree normalises every file mtime
  to zero and rpm compares mtime unconditionally, so it reports every file as
  modified on a pristine image. Verify content with digests. `rpm -q` is fine.
- **Edit os-release in place with `sed`, never `COPY` a replacement.** A wholesale
  copy deletes the `OSTREE_VERSION` rpm-ostree injects, blanking the version
  column in `rpm-ostree status` and stripping the boot entry's version suffix.
- **`EFIDIR="fedora"` must stay pinned** in `/usr/sbin/grub2-switch-to-blscfg`.
  That script derives its ESP directory from os-release's `ID=`, so `ID=cedar`
  sends it to `/boot/efi/EFI/cedar/`, which does not exist.
- **GRUB branding is limited to `GRUB_BACKGROUND` and `GRUB_THEME`.** Since GRUB
  2.06 `insmod` is prohibited under Secure Boot; a theme needing a module absent
  from Fedora's signed `grubx64.efi` halts the machine at an error prompt.
- **The base is pinned by digest, never by the `:44` tag.** `test/boot-chain.sh`
  derives its comparison base from the Containerfile's own `FROM` line, so it
  cannot compare against an image the build did not use. Do not add a second
  place where that digest is written.
- **Cosign must stay pinned to v2.4.3.** v3.x attaches signatures as OCI
  referrers; `containers/image` — which `rpm-ostree rebase ostree-image-signed:`
  uses — reads the legacy `sha256-<digest>.sig` tag. Unpinning silently publishes
  images no Cedar machine can verify.

## Things that look wrong and are deliberate

Do not "fix" these. Each has a test asserting it.

- **`CPE_NAME` still says Fedora.** It feeds CPE-based CVE and asset scanners, and
  Cedar's packages genuinely *are* Fedora 44 packages. A `cedarlinux` CPE would
  match no vulnerability database and make Cedar appear vulnerability-free.
- **`initramfs.img` is excluded from the boot-chain hash set.** Cedar legitimately
  regenerates it for the Plymouth theme, and it is not a signed EFI binary.
  `vmlinuz` stays guarded.
- **`/etc/issue` is untouched.** It contains `\S`, which agetty expands from
  `PRETTY_NAME`, so it already reads "Cedar 44".
- **The first rebase must be `ostree-unverified-registry:`.** Cedar's signature
  policy and public key ship *inside* Cedar, so a stock Fedora machine has nothing
  to verify against. `ostree-image-signed:` works from the second hop onward.

## What the boot-chain guard cannot see

It validates the bytes in the image, never how they reach an ESP. Blind spots,
each confirmed to report a passing check while broken: `grub2-switch-to-blscfg`
(covered instead by a content assertion), `/usr/lib/bootupd/grub2-static/*` —
which *becomes* the ESP's `grub.cfg` — and unsigned kernel modules under
`extra/`. Acceptable for a rebase, where the machine boots from the ESP its
installer wrote. **Milestone 2's ISO removes that margin** and needs a second
check that mounts the generated ESP and hash-matches it against `/usr/lib/efi/`.

## Visual identity is NOT decided

The greens (`#1B3A34`, `#5D8A6B`, `#7FC9A6`), the logo and the wallpaper were
invented while drafting, not chosen. They are placeholders proving the plumbing.
**Due before the milestone 2 ISO**, after which changing them means republishing
the image, the Plymouth theme and the installer.

## Working notes

- On an arm64 host every podman command needs `--platform=linux/amd64`; the base
  is a multi-arch manifest and the aarch64 package set differs (`shim`, not
  `shim-x64`). On x86_64 it is a harmless no-op. Scripts honour `$PLATFORM`.
- Local builds need podman machine memory at 4 GiB; the 2 GiB default causes
  intermittent ENOMEM on the branding COPY steps.
- **Never `git add -A`** — stage explicit paths. Subagents share the working tree,
  and a blanket stage has already swept one agent's work into another's commit.
