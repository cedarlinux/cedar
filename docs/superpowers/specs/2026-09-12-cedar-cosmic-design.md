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
4. **COSMIC's native config already is the format** → themes are `.ron` files
   driven by the `cosmic-theme` crate, and an exported theme carries the
   wallpaper, panel layout, dock position and applet order. Cedar does not
   invent a format; it generates one.
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
with no process. Fedora's own documentation states that a remix shipping
Fedora's shim, grub2 and kernel **unchanged** will boot on Secure Boot machines.
Cedar never rebuilds any of the three.

This is therefore a **hard constraint, not merely a convenience**: Cedar must
never rebuild or replace shim, grub2 or the kernel. Branding may change GRUB's
appearance through theme files and configuration, never by rebuilding the signed
EFI binary. Secure Boot was a blocker in the Debian design; here it is
inherited, and the only way to lose it is to break this rule.

NVIDIA's DKMS modules remain the exception — they are unsigned and still require
MOK enrollment at a firmware prompt. That is a one-time annoyance for a single
user and a real problem if Cedar ever has general users.

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

**Design.** One palette file (colours, accent, three font choices, corner
radius, wallpaper) is the source of truth. `cedar-theme apply <name>` renders it
to:

| Target | Mechanism |
|---|---|
| COSMIC | generated `.ron`, the native format |
| GTK 3/4 | generated colour definitions into a maintained upstream theme |
| Qt | CuteCosmic's Qt platform theme, or Kvantum if that proves insufficient |
| Terminal, editor | generated config |
| Flatpak apps | theme extensions written as plain local directories |

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

- **Which COSMIC version Fedora 44 currently ships.** It released in April 2026
  with 1.0.8 while upstream is now at 1.3–1.5. Whether Fedora has updated COSMIC
  within the release is not documented publicly and must be checked against the
  repository directly (`dnf info cosmic-desktop`) at milestone 1. This is the
  same staleness trap that killed the Debian design, so it is worth checking
  early — but it is far less dangerous here for two reasons: Fedora releases
  every six months rather than every two years, so the worst case is months of
  lag rather than years; and the `ryanabx/cosmic-epoch` COPR packages COSMIC for
  Fedora, giving a fallback that Debian simply did not have for Plasma. If the
  COPR turns out to be necessary, note that the first design was abandoned partly
  for depending on third-party COPRs — acceptable for one user, not for a
  distribution.
- Whether CuteCosmic is maintained and sufficient for Qt theming, or whether
  Kvantum is needed.
- Whether COSMIC's exported `.ron` is a stable enough format to generate
  against, or whether it changes shape between COSMIC releases.
- NVIDIA on Fedora Atomic still requires MOK enrollment under Secure Boot. This
  is a one-time annoyance for a single user rather than a blocker, but it should
  be confirmed before choosing hardware.
- `cedarlinux` GitHub organisation and `ghcr.io` namespace are not yet claimed.
