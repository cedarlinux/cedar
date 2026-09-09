# Cedar — Design

Date: 2026-09-09
Status: approved for planning (revised after three independent reviews)

## What Cedar is

Cedar is an opinionated Linux desktop in the spirit of Omarchy, built on a
stable base instead of Arch. It is a fork of Omarchy 4 "Quattro" (Hyprland
plus a Quickshell desktop shell) ported to Fedora and delivered as a bootc
image. It is public from day one.

Decisions already made:

| Decision        | Choice                                          |
|-----------------|-------------------------------------------------|
| Base            | Fedora, current stable release (44 at writing)  |
| Foundation      | Fedora Atomic via bootc (image-based)           |
| Compositor      | Hyprland 0.56+ with Lua config                  |
| Shell           | Omarchy Quattro's Quickshell shell, forked      |
| Reuse           | Fork and adapt Omarchy (MIT), diverge later     |
| Packaging       | Cedar's own COPR, no third-party COPR at rest   |
| Delivery        | `bootc switch` first, installer ISO second      |
| Hardware        | x86_64 only at launch                           |
| Repo shape      | Monorepo                                        |
| Org / domain    | `cedarlinux` on GitHub and COPR, cedarlinux.org |

## Why these choices

Fedora no longer ships Hyprland (its package is orphaned at 0.45, last built
for Fedora 42) and Debian moved it to backports and does not ship Quickshell.
No stable distribution carries the desktop stack Quattro needs, so Cedar must
own that layer regardless of base. Fedora is chosen because its fresh
toolchain (GCC 16), Qt 6.10 and Mesa make building Hyprland 0.56 and
Quickshell feasible, while its point releases and bootc tooling give the
"stable" properties Cedar wants: predictable base, atomic updates, built-in
rollback.

The stability promise is therefore: a stable, image-based OS layer from
Fedora, plus a desktop layer whose version cadence Cedar controls.

## Repository layout

```
cedar/
  desktop/     Omarchy Quattro fork, ported to Fedora (see "The Omarchy fork")
  pkgs/        one directory per RPM spec, built in COPR cedarlinux/cedar
  image/       Containerfile, build script, disk-image config
  docs/        specs, decisions, user manual source for cedarlinux.org
  Justfile     local build, test and VM recipes
  .github/     one workflow per layer, path-filtered
```

### The Omarchy fork (`desktop/`)

Upstream facts that shape this: the `omacom/omarchy` repo is ~80 MB working
tree, ~6,400 commits on `quattro`, and moves at ~80 commits/week. The name
"omarchy" appears ~5,900 times outside docs. PKGBUILDs live in a separate
`omacom/omarchy-pkgs` repo, not in the main tree. Real top level:
`agents/ applications/ bin/ config/ default/ docs/ etc/ install/ manual/
migrations/ plans/ shell/ test/ themes/` plus `version`.

- `desktop/` is a `git subtree` of upstream `quattro`, added and pulled
  **without `--squash`** so upstream history merges cleanly and conflicts
  are limited to files Cedar changed. `desktop/UPSTREAM` records the commit
  last synced.
- **Internal identifiers stay `omarchy` for now.** Paths
  (`/usr/share/omarchy`, `~/.config/omarchy`), binary names (`omarchy-*`)
  and the `OMARCHY_PATH` indirection are kept so upstream pulls keep
  applying. User-facing branding (os-release, themes, shell strings, docs,
  package names `cedar`/`cedar-settings`) says Cedar. A full internal rename
  is deferred until Cedar has diverged enough that tracking upstream stops
  paying off; that is a later, explicit decision.
- Omarchy's MIT license and attribution ("based on Omarchy") stay in
  `desktop/`. MIT does not license the name; there is no trademark policy
  upstream; Cedar uses its own name.

## Layer 1: packages (`pkgs/`)

### Mechanism

COPR `cedarlinux/cedar`, one COPR package per `pkgs/<name>/`, source type
SCM, clone URL = this repo, committish `main`, subdirectory `pkgs/<name>`,
spec `<name>.spec`, method `rpkg`. One GitHub push webhook on the repo; COPR
rebuilds a package only when a changed path starts with its subdirectory, so
pushes touching only `desktop/` or `image/` rebuild nothing.

`cedar` and `cedar-settings` are the exception: their content lives in
`desktop/`, so a path-filtered GitHub workflow builds their SRPMs (version
from `git describe --tags`, `v` stripped) and uploads with `copr-cli`.

Versions are pinned and bumped deliberately; nothing tracks upstream git.

### Conventional split, not hermetic

The Hyprland stack is packaged as normal Fedora-style packages with `-devel`
subpackages (the way Fedora 42 did), not as one hermetic package with
vendored libraries. Reason: `hyprland-guiutils`, `hyprland-preview-share-picker`,
`hyprpicker`, `hyprsunset` and `xdg-desktop-portal-hyprland` all link the
hypr* libraries, and vendoring would force every one of them to repeat the
RPATH dance and stay version-locked. AshBuk/Hyprland-Fedora (MIT) is still
mined for patches and cmake flags.

### Initial package set

Hyprland stack: `hyprutils` (>= 0.14), `hyprlang` (>= 0.6.8), `hyprcursor`,
`hyprgraphics` (0.5), `hyprwire`, `aquamarine` (0.14), `hyprwayland-scanner`,
`hyprland-protocols`, `hyprland` (0.56.2, Lua 5.4), `xdg-desktop-portal-hyprland`
(1.4.1), `hyprland-qt-support`, `hyprland-guiutils`,
`hyprland-preview-share-picker`, `hyprpicker`, `hyprsunset`. Build deps not
in Fedora 44: `cpptrace`, `glaze`.

Shell and session: `quickshell` (>= 0.3.1, built with pipewire, polkit, pam,
bluetooth and networking enabled; `Requires: qt6-qtbase%{?_isa} = %{_qt6_version}`
because it uses private Qt APIs and must be rebuilt on every Qt bump),
`uwsm` (not in Fedora), `xdg-terminal-exec`.

Launcher: `walker` and the `elephant` providers, if Milestone 1 confirms the
Quattro menu still depends on them (upstream release notes say the launcher
was merged into the shell; the package list still pulls elephant). Verify at
Milestone 1 and record the answer here.

Fonts: JetBrains Mono Nerd (basic), Font Awesome. Licenses must be Fedora
acceptable (OFL/MIT); check every font before packaging.

Tools referenced by shell menus and scripts, decided per tool during
Milestone 3 as package / Homebrew / drop: `gpu-screen-recorder`, `voxtype`,
`tensaku`, `mise`, `omarchy-nvim`, `aether`, `cliamp`, `herdr`, `omacalc`,
`omacut`, `omawrite`, `tobi-try`, `ttfx`, `gum`, `usage`, `tzupdate`. None
are required to boot to the shell.

Already in Fedora 44 (no packaging work): `sddm` 0.21, `qt6-qtmultimedia`,
`qt6-qtwayland`, `qt6-qtsvg`, `pipewire`, `wireplumber`, `upower`, `polkit`,
`gnome-keyring`, `NetworkManager`, `bluez`, `power-profiles-daemon`,
`tailscale`, `fprintd`, `libxkbcommon-utils`, `wl-clipboard`, `jq`, `gum`,
`foot`, `kitty`, `nautilus`, `mpv`, `btop`, `lua` 5.4.

Cedar's own: `cedar-settings` (system files, `/etc/skel`, fonts, PAM edit
for SDDM, boot config) and `cedar` (`bin/`, install/finalize scripts,
migrations, themes, the shell). They reimplement the file maps of upstream's
`omarchy-settings` and `omarchy` PKGBUILDs (upstream `docs/file-layout.md`
has the full table). Migration markers are seeded under
`/etc/skel/.local/state/omarchy/migrations/` at package build, as upstream
does. Upstream's three libalpm hooks (update guard, Hyprland reload
pause/resume) are dropped. Upstream's `omarchy-settings.install`
post-install (copies os-release, nsswitch.conf, faillock.conf,
plymouthd.conf, skel `.bashrc` into place) becomes a Containerfile step.

COPR limits are not a concern: build timeout is raisable to 50 h and Fedora
44's GCC 16 builds Hyprland's C++26 without `-fpermissive`.

## Layer 2: desktop port (`desktop/`)

### Honest size

Counts on upstream `quattro` today: `bin/` has 455 scripts, 100 of which
call pacman/yay/paru or `omarchy-pkg-*` (33 `omarchy-install-*`, 25
`omarchy-remove-*`, 10 `omarchy-update-*`, 8 `omarchy-pkg-*`); 27 of 86
`install/` files and 35 of 114 migrations touch the package manager.
Package management is funnelled through a thin `omarchy-pkg-*` abstraction,
but the install-*/remove-* app scripts embed package names directly.

Limine/snapper/mkinitcpio-specific: `omarchy-snapshot`, `-refresh-limine`,
`-setup-direct-boot`, `-hibernation-*`, `-system-factory-reset*`,
`-plymouth-set`, `-provision-owner`, `-upgrade-to-quattro`,
`install/config/snapper.sh`, `etc/mkinitcpio.conf.d`, `etc/limine-entry-tool.d`,
`default/limine`, `default/snapper`, ~10 `hardware/*.sh` scripts that edit
mkinitcpio or the kernel cmdline, and 10 migrations.

Estimate: ~140 shell scripts to rewrite or delete, ~15 to redesign (update,
snapshot, factory reset, hibernation, provision-owner). This is the largest
milestone.

### Replacements

| Omarchy mechanism                          | Cedar replacement                                        |
|--------------------------------------------|----------------------------------------------------------|
| pacman / yay / `omarchy-pkg-*`             | none at runtime; system packages come only from the image |
| `omarchy-install-*` / `-remove-*` apps     | Flatpak (Flathub), distrobox, Homebrew (`/var/home/linuxbrew`) |
| `omarchy update` (pacman + git)            | `omarchy-update` → `bootc upgrade`; refuses and explains if rpm-ostree layering is detected (layering breaks `bootc upgrade`) |
| Limine snapshot rollback                   | `bootc rollback` (previous deployment)                   |
| mkinitcpio hooks, `hardware/*.sh` cmdline edits | removed; kernel args ship in `/usr/lib/bootc/kargs.d/*.toml` |
| Plymouth theme set at runtime              | theme baked and initramfs regenerated at image build      |
| Arch ISO configurator, archinstall         | removed; installer ISO from image-builder                 |
| libalpm hooks                              | dropped                                                   |
| snapper, hibernation, factory reset        | redesigned on bootc primitives or dropped; decided in Milestone 3 |

### Kept unchanged

- Quickshell shell (bar, launcher, notifications, OSD, panels, lock, polkit
  agent). Imports `Quickshell.Networking`, `.Bluetooth`,
  `.Services.{Pipewire,UPower,Mpris,SystemTray,Polkit,Pam,Notifications}`,
  `Quickshell.Hyprland`, `QtMultimedia`.
- Login: SDDM Wayland greeter running its own Hyprland instance
  (`default/sddm/hyprland.lua`), session `uwsm start -g -1 -e -D Hyprland`,
  autologin written to `/etc/sddm.conf.d/autologin.conf` by provision-owner.
- Themes (24-colour system), wallpapers, keybindings, Lua Hyprland config.
- `/etc/skel` seeding, `omarchy-provision-user` (needs only `OMARCHY_PATH`,
  `install/`, `omarchy-done`; portable), `omarchy-reinstall-configs`.
- Per-user login migrations: `omarchy-migrate-notify.service` user unit
  checks `/usr/share/omarchy/migrations` at login.
- Split of `~/.config/omarchy/` (user intent) vs `~/.local/state/omarchy/`
  (generated state).

System-level migrations do not exist in Cedar: a system change is a new
image. Only per-user migrations remain.

## Layer 3: image (`image/`)

### Build

- `image/Containerfile`: `FROM quay.io/fedora/fedora-bootc:44`, runs
  `image/build.sh`, ends with `bootc container lint --fatal-warnings`.
- `image/build.sh`: `dnf -y install dnf5-plugins && dnf -y copr enable
  cedarlinux/cedar`, install `cedar` and `cedar-settings` (which pull the
  rest), apply the upstream post-install file copies, enable `sddm.service`
  and required system units, regenerate initramfs with Plymouth theme into
  `/usr/lib/modules/$kver/initramfs.img`, then `dnf copr remove` (the repo
  file must not propagate to installed systems via `/etc`) and
  `dnf clean all` (no `/var` content in the image).
- Filesystem rules: defaults live in `/usr/share/omarchy`; `/etc` stays
  minimal (it is 3-way merged on every upgrade and user-edited files stop
  tracking the image); nothing shipped in `/var` (only unpacked on first
  install, use tmpfiles.d for directories); `/opt` is read-only.
- Kernel args (`quiet splash`, etc.) in `/usr/lib/bootc/kargs.d/*.toml`.

### Signing and verification

- CI signs with `cosign sign --key` in legacy sigstore-attachment mode (bootc
  cannot verify the newer bundle/referrer format).
- The image ships `/etc/pki/containers/cedar.pub`, a
  `/etc/containers/policy.json` entry for `ghcr.io/cedarlinux` with
  `sigstoreSigned`, and `/etc/containers/registries.d/cedar.yaml` with
  `use-sigstore-attachments: true`. Verification is therefore enforced from
  the second update onward.

### CI

- `.github/workflows/image.yml`: build on push to `main`, sign, push to
  `ghcr.io/cedarlinux/cedar:latest`; tags push `:stable` and `:vX.Y.Z`.
- `.github/workflows/disk.yml`: on tags and manual dispatch, run
  image-builder (formerly bootc-image-builder; the container
  `quay.io/centos-bootc/bootc-image-builder` still works) with type
  `bootc-installer` for the interactive Anaconda ISO and `qcow2` for the
  test VM (with `[[customizations.user]]`). Build host must be x86_64;
  Fedora needs an explicit `--rootfs`. Kickstart customizations cannot be
  combined with `[[customizations.user]]`. Fedora 45 moves Atomic ISOs to
  the Anaconda WebUI, so the installer UI may change under us.

### Delivery

For users on Fedora Silverblue/Kinoite 44 (ostree-mirrored images with bootc
installed):

```
sudo rpm-ostree reset                        # only if packages were layered
sudo bootc switch --transport registry ghcr.io/cedarlinux/cedar:stable
```

The first switch is unverified because the host lacks Cedar's key; the
policy files in the image enforce signatures from then on. Do not promise
"any Atomic system": Fedora's bootc-native sealed/UKI Atomic images target
Fedora 45+ and are still in testing.

Anaconda gives LUKS full-disk encryption and real dual-boot in the installer
path, matching what Omarchy users expect. TPM auto-unlock waits for the
sealed/UKI path.

### Base bump policy

Move to Fedora N+1 within ~2 months of its release (Fedora N is EOL ~13
months after release). Fedora 45 is due 2026-10-20.

## Channels and versioning

- `latest` — every push to `main`.
- `stable` — git tags `vX.Y.Z`; the tag also produces the ISO.
- Cedar version is the git tag; `cedar` and `cedar-settings` RPM versions are
  derived from it at SRPM build time.

## Testing

1. Package: COPR build success per spec; `rpmlint` in CI on changed specs.
2. Image: container smoke test in CI — start the built image, assert that
   `Hyprland`, `quickshell`, `uwsm`, `sddm` and `omarchy-*` binaries exist
   and that `sddm.service` is enabled.
3. Desktop: `just vm` boots the qcow2 in QEMU locally for manual checks. A
   scripted boot test (login, Hyprland responds to `hyprctl`) is added once
   the session is stable.

## Milestones

1. **Boot to shell.** Image from `fedora-bootc:44` with third-party COPRs
   as a temporary bootstrap: `sdegler/hyprland` (hyprland 0.56.2,
   xdg-desktop-portal-hyprland, hyprland-guiutils, hyprland-qt-support) and
   `errornointernet/quickshell` (0.3.1). Things neither provides that the
   shell needs to come up — `uwsm`, fonts, and `walker`/`elephant` if
   required — are built from source inside the Containerfile for this
   milestone only. Everything else (hyprpicker, hyprsunset, share picker,
   DHH tools) is stubbed. `desktop/` is minimally ported: package-manager
   calls no-op'd, Limine/mkinitcpio scripts disabled, SDDM + uwsm session
   working. Output: a VM where a user logs into Hyprland with the Omarchy
   shell running, plus the real list of what broke.
2. **Own the packages.** `pkgs/` builds the conventional Hyprland split,
   Quickshell and uwsm in COPR `cedarlinux/cedar`; the image switches to it;
   third-party COPRs and in-Containerfile source builds are removed.
3. **Full port.** The ~140-script rewrite: update, app install, rollback,
   migrations, per-tool package/brew/drop decisions, snapshot/hibernation/
   factory-reset redesign. `latest` is usable daily.
4. **ISO and `stable`.** Signing enforced, first tagged release with a
   `bootc-installer` ISO on cedarlinux.org.

Themes, plugins, app-default changes and aarch64 are out of scope until
milestone 3 is done.

## Open items (not blocking)

- COPR owner: a personal Fedora account initially; moving to a `@cedarlinux`
  group later is cheap because COPR URLs only appear inside the image build.
- The `ghcr.io/cedarlinux/cedar` image URL is baked into every installed
  system, so the org name must be final before milestone 4.
- Whether the shell's Networking module needs a minimum NetworkManager
  version was not verified.
- Upstream moved from `basecamp/omarchy` to `omacom/omarchy`; current tag is
  v4.0.3. `omarchy-pkgs` `_commit` pins are the release truth.
