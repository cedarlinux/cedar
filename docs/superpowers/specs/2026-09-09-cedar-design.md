# Cedar — Design

Date: 2026-09-09
Status: approved for planning

## What Cedar is

Cedar is an opinionated Linux desktop in the spirit of Omarchy, built on a
stable base instead of Arch. It is a fork of Omarchy 4 "Quattro" (Hyprland
plus a Quickshell desktop shell) ported to Fedora and delivered as a bootc
image. It is public from day one.

Decisions already made:

| Decision        | Choice                                         |
|-----------------|------------------------------------------------|
| Base            | Fedora, current stable release (44 at writing) |
| Foundation      | Fedora Atomic via bootc (image-based)          |
| Compositor      | Hyprland 0.56+ with Lua config                 |
| Shell           | Omarchy Quattro's Quickshell shell, forked     |
| Reuse           | Fork and adapt Omarchy (MIT), diverge later    |
| Packaging       | Cedar's own COPR, no third-party COPR at rest  |
| Delivery        | `bootc switch` first, ISO second               |
| Hardware        | x86_64 only at launch                          |
| Repo shape      | Monorepo                                       |
| Org / domain    | `cedarlinux` on GitHub and COPR, cedarlinux.org|

## Why these choices

Fedora no longer ships Hyprland (dropped after Fedora 42) and Debian moved it
to backports and does not ship Quickshell. No stable distribution carries the
desktop stack Quattro needs, so Cedar must own that layer regardless of base.
Fedora is chosen because its fresh toolchain, Qt and Mesa make building
Hyprland 0.56 and Quickshell feasible, while its point releases and bootc
tooling give the "stable" properties Cedar wants: predictable base, atomic
updates, built-in rollback.

The stability promise is therefore: a stable, image-based OS layer from
Fedora, plus a desktop layer whose version cadence Cedar controls.

## Repository layout

```
cedar/
  desktop/     Omarchy Quattro as a git subtree, ported to Fedora
  pkgs/        one directory per RPM spec, built in COPR cedarlinux/cedar
  image/       Containerfile, build script, disk-image config
  docs/        specs, decisions, user manual source for cedarlinux.org
  Justfile     local build, test and VM recipes
  .github/     one workflow per layer, path-filtered
```

### The Omarchy fork (`desktop/`)

- Added with `git subtree add --prefix=desktop <omarchy-remote> quattro --squash`.
- Upstream changes are pulled with `git subtree pull`; Cedar's changes live in
  the monorepo history. `desktop/UPSTREAM` records the upstream commit last
  synced.
- Omarchy's MIT license and attribution stay in `desktop/`.
- Omarchy's Arch packaging (`pkgbuilds/`) is left in place for reference but
  is not built.

## Layer 1: packages (`pkgs/`)

Built in COPR `cedarlinux/cedar` using COPR's SCM integration pointed at
`pkgs/<name>` in this repo, triggered by a push webhook. Cedar pins versions
and bumps deliberately; nothing tracks upstream git automatically.

Initial package set:

- `hyprland` — hermetic build with vendored hypr* libraries under
  `/usr/libexec/hyprland/vendor/`, forked from the MIT-licensed
  AshBuk/Hyprland-Fedora specs. Subpackages: `hyprlock`, `hypridle` (kept for
  compatibility even though the shell replaces them).
- `xdg-desktop-portal-hyprland`
- `quickshell`
- Any other tool Quattro requires that Fedora lacks (discovered during the
  port; each gets its own `pkgs/<name>/`).
- `cedar-settings` — system files, `/etc/skel`, fonts, boot-related config.
  Mirrors Omarchy's `omarchy-settings`.
- `cedar` — binaries (`bin/`), install/finalize scripts, migrations, themes,
  the Quickshell shell. Mirrors Omarchy's `omarchy` package.

The two Cedar packages are built from `desktop/` by a spec that packs the
tree, so `desktop/` remains the single source of truth.

## Layer 2: desktop port (`desktop/`)

Replace Arch-specific machinery; keep everything else.

| Omarchy mechanism                        | Cedar replacement                              |
|------------------------------------------|------------------------------------------------|
| pacman / yay / pacman guard              | none; system packages come only from the image |
| TUI app installers (pacman-backed)       | Flatpak (Flathub), distrobox, Homebrew         |
| `omarchy update` (pacman + git)          | `cedar update` → `bootc upgrade`               |
| Limine snapshot rollback                 | bootc previous-deployment rollback             |
| mkinitcpio hooks                         | removed (dracut is handled by the base image)  |
| Arch ISO configurator, archinstall       | removed (ISO comes from bootc-image-builder)   |
| iwd → NetworkManager (already in Quattro)| NetworkManager, unchanged                      |

Kept unchanged:

- Quickshell shell (bar, launcher, notifications, OSD, panels, lock, polkit).
- Themes (24-colour system), wallpapers, keybindings, Lua Hyprland config.
- `/etc/skel` seeding, `provision-user` finalize step, `reinstall-configs`.
- Per-user login migrations tracked in `~/.local/state/cedar/migrations/`.
- Split of `~/.config/cedar/` (user intent) vs `~/.local/state/cedar/`
  (generated state).

Renaming `omarchy` → `cedar` in paths, binaries, env vars and package names
is part of the port, done once and recorded so subtree pulls can be
re-applied.

System-level migrations do not exist in Cedar: a system change is a new
image. Only per-user migrations remain.

## Layer 3: image (`image/`)

- `image/Containerfile` starts `FROM quay.io/fedora/fedora-bootc:44`,
  enables COPR `cedarlinux/cedar`, installs `cedar` and `cedar-settings` (which
  pull the rest), enables greeter and session units, and runs
  `bootc container lint`.
- `image/build.sh` holds the package and unit steps so the Containerfile stays
  declarative.
- `image/disk/iso.toml` and `image/disk/qcow2.toml` configure
  bootc-image-builder.
- CI (`.github/workflows/image.yml`): build on push to `main`, sign with
  cosign, push to `ghcr.io/cedarlinux/cedar`. A second workflow
  (`disk.yml`) produces ISO and qcow2 on tags and on manual dispatch.
- Users on any Fedora Atomic system switch with:
  `sudo bootc switch ghcr.io/cedarlinux/cedar:stable`

## Channels and versioning

- `latest` — every push to `main`.
- `stable` — git tags `vX.Y.Z`; the tag also produces the ISO.
- Cedar version is the git tag; `cedar` and `cedar-settings` RPM versions are
  set from it at build time.

## Testing

1. Package: COPR build success per spec; `rpmlint` in CI on changed specs.
2. Image: container smoke test in CI — start the built image, assert that
   `Hyprland`, `quickshell`, `cedar` binaries exist and that the session and
   greeter units are enabled.
3. Desktop: `just vm` boots the qcow2 in QEMU locally for manual checks. A
   scripted boot test (login, Hyprland responds to `hyprctl`) is added once
   the session is stable.

## Milestones

1. **Boot to shell.** Image from `fedora-bootc` using existing third-party
   COPRs (sdegler/hyprland, errornointernet/quickshell) as a temporary
   bootstrap, with `desktop/` minimally ported so a user logs into Hyprland
   with the Omarchy shell running. Output: what actually breaks in the port.
2. **Own the packages.** `pkgs/` builds the Hyprland stack and Quickshell in
   COPR `cedarlinux/cedar`; the image switches to it and third-party COPRs are
   removed.
3. **Full port.** Update, app install, rollback, migrations and rename are
   complete; `latest` channel is usable daily.
4. **ISO and `stable`.** First tagged release with an ISO on cedarlinux.org.

Themes, plugins, app-default changes and aarch64 are out of scope until
milestone 3 is done.

## Open items (not blocking)

- COPR owner: a personal Fedora account initially; moving to a `@cedarlinux`
  group later is cheap because COPR URLs only appear inside the image build.
- The `ghcr.io/cedarlinux/cedar` image URL is baked into every installed
  system, so the org name must be final before milestone 4.
