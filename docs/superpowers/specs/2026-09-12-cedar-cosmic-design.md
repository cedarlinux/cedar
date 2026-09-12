# Cedar — Design (COSMIC)

Supersedes both earlier designs, which are withdrawn:

- `2026-09-09-cedar-design.md` — Omarchy fork on Fedora bootc, Hyprland + Quickshell.
- `2026-09-12-cedar-design.md` — Debian 14 + KDE Plasma, for Windows/macOS switchers.

The second was reviewed by five agents across Debian, Plasma, theming, strategy
and omissions. Roughly forty findings came back. Most are moot now, because the
review's real conclusion was that the *audience* was wrong, not the technology.
What survives from it is recorded under "What the review established".

## What Cedar is

A bootable container image: **Fedora COSMIC Atomic, plus Cedar's branding,
layout, theme and curated apps.** It is built from a Containerfile in this
repository, published to a registry, and installed by rebasing onto it.

**Cedar is built for its author to use daily.** Other people adopting it is a
possible future, not the goal. This is the single most important line in this
document, because it is what makes everything below small enough to finish.

Explicitly out of scope, and not deferred but *declined*: an accessibility
programme, localization beyond the author's own, a hardware support matrix, a
CVE response policy, a support forum, and any comparison to Zorin or Mint.

**A Cedar ISO is in scope**, because the artifact should be future-proof even
while the audience is one person. "Install Fedora, then rebase" is fine for an
afternoon and wrong for anything meant to last. It is affordable here only
because the ISO is *generated from* the container image by existing tooling
rather than assembled by hand — the work is CI configuration and boot testing,
not installer development. Anaconda, partitioning and Secure Boot all come
inherited. That is the difference between this and the Debian design, where the
ISO would have meant live-build, Calamares, a signing story and a LUKS layout.

If Cedar turns out to be good and someone else wants it, those become real
questions then, with evidence. Taking them on now costs a year and answers
nothing.

## Why these choices

1. **Audience is the author** → no distribution obligations. This deletes about
   thirty-five of the forty review findings outright.
2. **The desktop must be mouse-first, floating, light and deeply customizable**
   → COSMIC. It is floating and mouse-first by default, Rust and iced so there
   is no libadwaita theming problem, genuinely light, and unlike Hyprland it
   ships real settings applications rather than requiring Cedar to build them.
3. **COSMIC's native layout already is the design** → a top panel plus a
   *separate* floating dock holding running and pinned apps. That is the
   apps-vs-windows split from the previous design, out of the box, with no
   forked widget and no upstream fight.
4. **COSMIC's theme format is native and Cedar generates it rather than
   inventing one** → themes are `.ron` files driven by the `cosmic-theme`
   crate. Cedar targets **schema v2 and COSMIC 1.8**; v1 files load on a v2
   reader but not the reverse, and that shim is explicitly temporary and only
   one version deep.

   An earlier draft of this spec claimed a COSMIC theme export also carries the
   wallpaper, panel layout, dock position and applet order. **That is false and
   has never been true in any version** — the export serialises a
   `ThemeBuilder` and nothing else. Cedar therefore writes four config
   namespaces, not one: `com.system76.CosmicBackground` (wallpaper),
   `com.system76.CosmicPanel` with its `Panel` and `Dock` profiles (layout),
   and `com.system76.CosmicAppList/favorites` (dock pins). All are still `v1`
   at COSMIC 1.8, so they are stable — but they are Cedar's to write.
5. **Identity comes from the desktop, not the base** → Omarchy is Arch plus
   configuration and feels entirely like Omarchy. Cedar controls every surface
   the author looks at.
6. **Atomic, because rollback was always the right instinct** → this restores
   the property the original bootc design wanted, now with none of the delivery
   burden, because there is nobody to deliver to.

### Hyprland, considered and declined

Hyprland was revisited three times. It is lighter and more configurable, and
owning every pixel would make theming trivial. It is declined because it is a
tiling compositor being run permanently in its least-supported mode, and
because it ships no settings, display, bluetooth or session plumbing — so
theming becomes cheap only after a year spent building the surfaces to theme.
COSMIC gets the same lightness and customizability with the plumbing already
present. If COSMIC disappoints, this is the decision to revisit.

## Base and delivery

**Base image:** `quay.io/fedora-ostree-desktops/cosmic-atomic:44`

Fedora COSMIC Atomic is an official Fedora Atomic Desktop variant as of Fedora
44. Note that Atomic Desktops are **ostree-based today**, with the transition to
Bootable Containers underway and sealed images in testing. Cedar therefore uses
the ostree native-container path — the same mechanism Universal Blue's images
use — and moves to bootc proper when Fedora does.

**Shape of the repository:**

```
cedar/
  Containerfile      FROM cosmic-atomic, layer Cedar on top
  branding/          os-release, plymouth, wallpapers, logos, greeter
  desktop/           COSMIC config: panel, dock, applets, keybinds, defaults
  theme/             cedar-theme: the engine, plus shipped themes
  apps/              Flatpak manifest list, dnf layer list
  iso/               ISO build config: Titanoboa / image-builder, kickstart
  Justfile           build, test in a VM, build ISO, rebase
  .github/           build and push image on main; build ISO on tag
```

### One image, two ways to consume it

The container image is the single source of truth. It is consumed two ways:

```
Containerfile  ──CI──▶  ghcr.io/cedarlinux/cedar:latest
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
                Cedar ISO          rpm-ostree rebase
           (fresh installs)     (machines already on Cedar)
```

**Cedar ships its own ISO from the start.** Telling someone to install Fedora
first and then rebase is acceptable for one user on one afternoon and wrong for
anything meant to last. The ISO carries Cedar's bootloader entries, Cedar's
Plymouth and Cedar's branding, and it is what any future user — including the
author on a new machine — actually installs.

**The ISO is generated, not separately built.** Universal Blue's **Titanoboa**
produces live ISOs directly from bootc container images, and
`build-container-installer` produces traditional installer ISOs; Bazzite ships
both from GitHub Actions. Fedora is separately migrating Atomic Desktop ISOs
from lorax to osbuild's **image-builder**, which is the official alternative and
the one to prefer if Fedora's tooling converges there.

Note: `bootc-image-builder` was **archived in June 2026** and must not be used.

Crucially, these tools expect *all* customization — bootloader entries, kernel
arguments, branding, preinstalled Flatpaks — to live inside the container image.
So Cedar is branded once, in the Containerfile, and the ISO inherits it. There
is no second branding pipeline.

**Updates.** Machines already running Cedar do not reinstall; `rpm-ostree
upgrade` pulls the new image and a reboot applies it. A bad build is recovered
by booting the previous deployment, which Fedora Atomic keeps automatically — no
snapper, no `grub-btrfs`, none of the machinery the Debian design needed and
could not get.

### Secure Boot

Cedar's ISO boots on stock hardware with Secure Boot enabled, at no cost and
with no process, because it ships Fedora's signed shim, grub2 and kernel
unchanged. This is a **hard constraint, not a convenience.**

**The mechanism matters, and is easy to get wrong.** On an ostree system the
shim and grub2 RPM content lands in `/usr` — inside the ostree commit — and
**never touches the EFI system partition**. `rpm-ostree rebase` rewrites only
`grub.cfg` and the boot entries; every other file on the ESP is the one the
installer wrote. Cedar's signed payload therefore lives at
`/usr/lib/bootupd/updates/EFI/` and `/usr/lib/ostree-boot/efi/EFI/`, and it
reaches the ESP by exactly two routes: **`bootupctl`** (bootloader updates are
enabled by default on Fedora Atomic Desktops) and **an installer** — which is
milestone 2's ISO.

Three consequences:

- A rebase test cannot detect a broken shim or grub2, because the machine boots
  from the ESP the installer wrote. Rebasing validates the **kernel** signature
  path only.
- The payload must therefore be verified by **comparing bytes** — digests of
  those two trees plus `vmlinuz` and `initramfs.img`, against the base image.
  Comparing RPM package versions is not sufficient, and `rpm -V` is useless
  here: ostree normalises every file mtime to zero, so `rpm -V` reports every
  file as modified on a pristine image.
- **GRUB branding has a hard limit.** Since GRUB 2.06, `insmod` is prohibited
  under Secure Boot — a theme needing a module not already built into Fedora's
  signed `grubx64.efi` stops the machine at an error prompt, and `grub.cfg` is
  not RPM-owned so no artifact check covers it. Cedar restricts GRUB branding to
  `GRUB_BACKGROUND` and `GRUB_THEME`, with the module set verified first.

**Branding also breaks the bootloader path if done naively.** `grub2-switch-to-blscfg`
derives its EFI directory from os-release (`EFIDIR=$(grep ^ID= …)`) and looks in
`/boot/efi/EFI/${EFIDIR}/`. Setting `ID=cedar` points it at a directory that does
not exist, so Cedar must pin `EFIDIR="fedora"`. Bazzite carries the same fix.

NVIDIA's DKMS modules remain the exception — unsigned, and still requiring MOK
enrollment at a firmware prompt. A one-time annoyance for a single user, and a
real problem if Cedar ever has general ones.

**Branding.** Baked into the image rather than patched onto a running system:
`/etc/os-release`, `/etc/issue`, `GRUB_DISTRIBUTOR`, the Plymouth theme, the
greeter, wallpapers and logos. Because the image is built rather than modified,
there is no `cedar-release` package and no conflict with `fedora-release` on
upgrade — the Containerfile simply writes the files it wants. This is the
Bazzite and Bluefin model.

## The desktop

COSMIC's defaults are close to correct, so Cedar configures rather than builds.

- **Top panel** — launcher, workspace and window controls, tray, clock.
- **Dock** — bottom, floating, running and pinned applications. Cedar accepts
  COSMIC's behaviour of showing running unpinned apps; this is macOS's
  behaviour, and the apps-vs-windows split survives it since an app with three
  windows appears once in the dock.
- **Floating windows by default.** COSMIC's tiling is available per-workspace
  and stays off by default.
- Cedar ships these as `.ron` config in `desktop/`, baked into the image.

Cedar does not lock any of this. COSMIC's own settings remain fully available;
Cedar's configuration is a starting point, not a cage.

## The theme engine

The one piece of real software Cedar writes, and it is small because COSMIC
does most of the work.

**The problem worth solving:** COSMIC themes its *own* applications very well.
Its weak spot — with open upstream issues — is that GTK and Qt applications do
not reliably follow system colours or light/dark. So:

> **COSMIC styles COSMIC. Cedar makes everything else match.**

**What COSMIC already does, and what is therefore Cedar's.** At 1.8,
`cosmic-settings-daemon` watches the `Theme` config and generates **GTK4 CSS**
from the palette and **qt5ct/qt6ct** config edits. It used to write kdeglobals
colour schemes; that was deleted as dead code because it cannot reach Flatpaks.
So the gap is precise:

| | Owner |
|---|---|
| COSMIC's own apps, GTK4 CSS, qt56ct config | COSMIC, free |
| **GTK3** — upstream writes GTK4 only | **Cedar** |
| **Qt platform theme** — CuteCosmic, pinned; qt6ct as fallback. Neither is preinstalled | **Cedar** |
| **`QT_QPA_PLATFORMTHEME` for host and Flatpak** | **Cedar** |
| **An icon theme with a dark variant** — COSMIC's own icons have none, so upstream falls back to Breeze | **Cedar** |
| Wallpaper, panel, dock, dock pins | **Cedar** — four `v1` config namespaces |

**Design.** One palette file (colours, accent, three font choices, corner
radius, wallpaper) is the source of truth. `cedar-theme apply <name>` renders it
to the COSMIC `.ron` theme (schema **v2**), the four layout namespaces above,
GTK3, the Qt platform theme configuration, terminal and editor config, and
Flatpak theme extensions written as plain local directories.

**One trap to design around.** `cosmic-settings-daemon` watches the derived
`Theme` object, not `ThemeBuilder`, and it is what triggers the GTK4 and qt56ct
exports — so Cedar must write `Theme`. But writing only `Theme` leaves the
newer `transparent_*` keys falling through to Fedora's shipped defaults, which
mismatches the palette as soon as frosted glass is on. **Cedar generates both,
consistently.**

**Two constraints carried over from the review, both verified:**

- Flatpak theming costs nothing to publish. GTK3 theme extensions build against
  the single branch `3.22` and can be plain directories under
  `~/.local/share/flatpak/extension/`. The real limit is that Flatpak apps pick
  up a theme change on next launch, never live, and that is unfixable.
- **Colour is parameterizable; geometry is not.** Cedar generates colour and
  typography into themes other people maintain. It does not author widget art.
  This is what keeps the engine a month rather than a year.

## Apps

Atomic makes Flatpak the default path, which suits Cedar: the base image stays
thin and applications stay current. Packages are layered with `dnf` in the
Containerfile only when they must be part of the system.

One app per job, chosen by the author, recorded in `apps/`. No curation
philosophy is needed beyond that, because there is no one else to serve.

## Milestones

1. **It boots and it is Cedar.** Containerfile builds from `cosmic-atomic:44`,
   branding baked in, CI publishing to `ghcr.io`, rebased onto a VM. Output: a
   system that says Cedar and that the author can log into. Also the moment to
   check which COSMIC version Fedora 44 actually ships (see Open items).
2. **It installs from a Cedar ISO.** CI generates the ISO from the image via
   Titanoboa or image-builder, published to GitHub releases with checksums.
   Verified to boot **with Secure Boot enabled** on real hardware, and to
   install cleanly. Output: Cedar installs on a blank machine with no mention
   of Fedora anywhere the user looks.
3. **It is the desktop.** `desktop/` carries the panel, dock, applet and
   keybinding configuration. Output: the layout is right on first login without
   touching settings.
4. **It is themed.** `cedar-theme` generates COSMIC, GTK and Qt from one
   palette; two or three themes ship; switching works. Output: everything on
   screen matches, including non-COSMIC apps.
5. **It is the daily driver.** The author uses Cedar as their primary desktop
   for a month and fixes what that reveals.

The ISO comes second deliberately. It is the piece most likely to rot if left
until the end, it is what makes Cedar reinstallable on a whim while the design
is still moving, and getting Secure Boot verified early means discovering any
violation of the never-rebuild-the-boot-chain rule while there is little to
unpick.

Only after milestone 5 is it worth asking whether anyone else should have it.

## What the review established

Findings from the five-agent review of the previous design that still apply:

- Generate colour and typography into maintained upstream themes; never author
  widget art. Corner radius and border weight are paths, not fills.
- Flatpak theme extensions are local directories, not a publishing pipeline.
- Theme changes never reach running Flatpak apps.
- Icons are referenced, not generated — a generated palette paired with a stock
  icon set is the most visible mismatch, and Cedar should choose icons per theme
  deliberately.
- Firefox theming has a supported path (a static theme WebExtension via
  enterprise policy) but requires AMO signing, so hand-authored themes degrade
  to light/dark plus accent.
- Trademark: "Cedar" is a weak mark and should be cleared before the domain and
  GitHub organisation are claimed.

## Open items

**Resolved during review, kept here because the reasoning matters:**

- **COSMIC version — no longer a risk.** Fedora 44 released with COSMIC 1.0.8
  but has been fed every upstream release since as ordinary updates; **1.8.0
  went stable on 2026-09-11**. There is no staleness trap and nothing to wait
  for at Fedora 45. Note that Fedora's `mdapi` reports this wrongly (its
  branch-to-repo mapping is scrambled) — Koji is the build system of record, and
  the check that actually settles it is `rpm -q` against the composed image.
- **CuteCosmic is maintained and is the right choice.** System76 now maintains
  its packaging and it is in Fedora. Upstream deleted kdeglobals generation
  precisely because a real Qt platform theme supersedes it. Pin the version —
  it is still `0.1^git` with no API stability promise — and keep qt6ct as
  fallback. Kvantum is not needed.
- **The theme schema is stable enough, in one direction.** `cosmic-theme` went
  v1→v2 between 1.0.9 and 1.3 (hex colours, a `frosted` subsystem, a new config
  path), then moved +9 lines across 52 commits to 1.8. Target v2.

**Still open:**

- Upstream COSMIC releases roughly weekly. The churn is in `cosmic-comp` rather
  than the schemas Cedar writes, but the mitigation should be built early: pin
  the base image by digest, and add a CI check that diffs the shipped
  `/usr/share/cosmic/**/default_schema` key names against what Cedar generates,
  so a schema bump fails the build rather than the desktop.
- NVIDIA on Fedora Atomic still requires MOK enrollment under Secure Boot. This
  is a one-time annoyance for a single user rather than a blocker, but it should
  be confirmed before choosing hardware.
- `cedarlinux` GitHub organisation and `ghcr.io` namespace are not yet claimed.
