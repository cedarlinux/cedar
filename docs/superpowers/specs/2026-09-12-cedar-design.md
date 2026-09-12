# Cedar — Design

Supersedes `2026-09-09-cedar-design.md`, which described Cedar as an Omarchy
fork on Fedora bootc. That design is withdrawn in full: the base, the desktop,
the delivery mechanism and the audience have all changed.

## What Cedar is

A Debian-based desktop Linux distribution for people arriving from Windows and
macOS. Mouse-first, conventional in its interaction model, and deeply
themeable — one theme switch restyles the entire system, every app included.

Cedar's product is **curation, theming and assembly**. It does not write a
desktop environment, package one, or fork one. Everything Cedar ships that is
Cedar's own is small: a theme engine, a set of themes, a default
configuration, and branding.

**Audience.** General-purpose daily driver. A graphical installer, complete
settings GUIs, working hardware, an app store, and nothing that requires a
terminal. This is the constraint that decides most of what follows.

**Not Omarchy.** Cedar keeps the philosophy of the withdrawn design — one
opinionated curated system, a first-class theme engine, sane defaults — and
none of its code, keybindings, tiling, or scripts. There is no upstream fork
to track.

## Why these choices

The reasoning chain matters more than the conclusions, because if a premise
changes the conclusion should be revisited.

1. **Audience is general-purpose switchers** → Cedar cannot build a desktop
   shell. Display arrangement, bluetooth, printing, audio routing, an app
   store, lock screen and settings represent decades of work. Cedar adopts a
   complete desktop environment.
2. **"Fully skinnable" is Cedar's core promise** → this eliminates the
   GTK/GNOME family. libadwaita is deliberately un-themeable and its
   maintainers intend to keep it that way; Linux Mint had to fork it
   (LibAdapta) and downgrade apps to GTK3 to preserve theming. Any
   GTK-based desktop signs Cedar up for permanent upstream combat over its
   central feature.
3. **Qt has no equivalent hostility** → KDE Plasma. Theming is supported and
   first-class. Plasma is also mouse-first, Wayland-native, and complete.
4. **Plasma's complexity is configuration surface** → which is how Cedar
   imposes an opinion. Cedar presets it; it does not lock it (see below).
5. **Debian for apt, stability, hardware breadth and long support life** →
   but Debian 13 ships Plasma 6.3.6, which predates Wayland becoming Plasma's
   default in 6.4, while Plasma 6.8 (October 2026) removes the X11 session
   entirely. Shipping 6.3.6 in 2027 means launching into a Wayland-only world
   on a pre-Wayland-default desktop.
6. **Debian already packages current Plasma** — `plasma-desktop` 4:6.7.4-1 is
   in unstable — → Cedar targets **Debian 14 "forky"**, developing against
   testing and launching when forky goes stable. No packaging pipeline, no
   sid, current Plasma on a frozen base.

### Opinionated, not locked

Cedar ships an opinion and the user may discard it. Plasma's panels, widgets
and layouts stay rearrangeable exactly as upstream ships them.

This is a deliberate reversal of the Zorin-style lockdown model. Caging Plasma
means fighting upstream at every release, and that recurring cost was the main
argument against choosing Plasma at all. Dropping the cage removes it. A
switcher gets Cedar's opinion on first boot and never needs to touch it;
anyone who wants to rearrange simply does.

The cost accepted: a user who rearranges can make Cedar look unlike Cedar.
Cedar declines to prevent that.

## The three layers

Cedar separates the system by update speed. Each layer has a different source
and a different cadence, and this is what lets a frozen base carry a modern
desktop.

| Layer | Source | Moves |
|---|---|---|
| Base — kernel, drivers, systemd, apt | Debian stable | Only at Debian releases |
| Desktop — Plasma, KDE Frameworks, Qt | Debian stable | Only at Debian releases |
| Apps — browser, office, media | Flatpak / Flathub | Continuously |

The browser is the load-bearing case for layer three. A Cedar release from
2027 must still browse the web in 2029 without anyone backporting anything.
Flatpak delivers that without unfreezing the base.

## Layer: the desktop

KDE Plasma, Wayland session only. X11 is not offered; Plasma 6.8 removes it
upstream and Cedar has no reason to carry it.

### Layout

The default arrangement is a top bar plus a floating dock, splitting **apps**
from **windows**. Every other desktop merges these into one strip that shifts
under the cursor; Cedar separates them because they are different mental
objects with different stability.

**Top bar** — full width, always visible. Holds:

- **Start** at far left, opening downward. Windows switchers already reach
  for this corner.
- **Window buttons** — one per window, labelled, ungrouped. Two Firefox
  windows appear as two distinct buttons. Grouping engages only when the bar
  fills up (Plasma's task manager supports this natively; it is a setting,
  not something Cedar builds).
- **System tray and clock** at far right, out of the way of the window list
  as it grows.

**Dock** — bottom centre, floating, always visible. Holds **pinned apps
only**. Never running windows, never an app grid. Clicking an entry focuses
the app if running and launches it if not; Ctrl-click or middle-click always
opens a new window. A subtle dot marks running apps.

The dock recenters when apps are pinned or unpinned. This is accepted, as
macOS has the same behaviour and pinning is rare.

**Show Desktop** — bottom-right screen corner, outside the dock, permanently
fixed. A true minimise-all toggle: click to minimise everything, click again
to restore. It sits in the corner rather than the dock precisely because the
dock moves and this must not.

**Desktop** — displays the contents of `~/Desktop`, with Trash present.
Plasma's icon-free wallpaper mode would read as broken to this audience.

**No global menu.** A Mac-style top bar earns its height only by carrying the
active app's menus, and Plasma's global menu coverage is uneven — good for Qt
and KDE apps, shimmed for GTK, largely absent for Electron. Cedar does not
ship a feature that works for some apps and not others.

### Start menu

Compact, two-column, anchored top-left beneath the Start button. Search at the
top, favourites list on the left, places and power on the right, with
`All apps ›` leading to the full list. This is the Windows 7 shape and close
to Plasma's stock Kickoff, so it is mostly configuration.

A Windows 11-style pinned grid was considered and rejected: it would duplicate
the dock's job, holding pinned apps in two places that must be kept in sync in
the user's head.

## Layer: the theme engine

Cedar's differentiator, and the only substantial software Cedar writes.

### Design

**A Cedar theme is one declarative file.** A palette in light and dark, three
font choices (UI, monospace, document), shape tokens (corner radius, density,
border weight), a wallpaper, and references to an icon and cursor set. Small
enough that a person can write one by hand — which is what makes the
skinnability promise real rather than decorative.

**`cedar-theme apply <name>` is a generator, not a runtime hook.** It renders
the theme file out to every surface and restarts what needs restarting.
Idempotent, inspectable, no daemon watching anything.

**Themes have three origins, all producing the same file format:** the
designed set Cedar ships, wallpaper extraction for users who want their
desktop to match an image, and hand-authoring. The engine does not care which
produced a given file.

### Render targets

- **Plasma surfaces** — colour scheme, Look-and-Feel package, Aurorae window
  decoration, Plasma desktop theme, splash, lock screen, SDDM
- **Qt apps** — a Kvantum SVG theme, with qt5ct/qt6ct as fallback
- **Host GTK apps** — generated GTK 2/3/4 theme, plus `kde-gtk-config`
  pushing colours into dconf so GTK picks them up under Wayland
- **Flatpak apps** — see below
- **Everything else** — Konsole scheme, Kate theme, generated Firefox theme,
  GRUB and Plymouth

### Flatpak theming is not optional

Flatpak apps cannot see host themes. They read theme *extensions* from the
remote, matched to the specific runtime branch each app uses —
`org.gtk.Gtk3theme.*` and `org.kde.KStyle.*`. Absent a matching extension, an
app silently falls back to Adwaita or stock Qt.

Cedar must therefore publish every shipped theme as Flatpak extensions across
each runtime branch in use, and keep republishing as branches turn over. Since
Flatpak is also Cedar's app-store answer, skipping this breaks coordinated
theming the first time a user installs anything — which for this audience is
day one.

This is recurring maintenance, not a one-time build, and it is the largest
ongoing cost in the theme engine.

### Known limit

libadwaita GTK4 apps remain unthemeable. Choosing Plasma contains the problem
to apps the user opts into rather than baking it into the desktop's own
software, but does not solve it. Cedar will not fork libadwaita.

## Layer: apps and curation

**The curation rule follows from the theme promise: prefer Qt/KDE-native apps
wherever a credible option exists,** because those are the apps that obey the
theme engine. Not tribalism — theming. GTK4 apps run fine and remain available
in the app store; they are simply not what Cedar ships as its own face.

**One app per job**, configured, with no duplicates and no demo software:

| Job | App |
|---|---|
| Web | Firefox (Flatpak) |
| Documents | LibreOffice, Qt/KF6 backend |
| Mail | Thunderbird |
| Files | Dolphin |
| Terminal | Konsole |
| Text | Kate |
| Images | Gwenview |
| Video | Haruna |
| App store | Discover, Flathub enabled |

Firefox ships as a Flatpak because a browser frozen for two years is not
usable. Everything else ships as `.deb` from Debian, because integration with
the desktop matters more than currency and Debian's QA is the reason Debian
was chosen. Flatpak is the default for anything the *user* installs later.

### Departing from Debian's defaults

Debian's defaults serve software freedom, not someone arriving from Windows.
Out of the box that means no NVIDIA proprietary driver and some Wi-Fi and GPU
firmware missing. Debian 12 onward enables `non-free-firmware` by default,
which covers much of the hardware case; Cedar goes further:

- **contrib and non-free enabled by default**
- **NVIDIA proprietary driver offered as a one-click first-run step** when the
  hardware calls for it
- **Microsoft-metric fonts** (Carlito, Caladea, Liberation) so documents from
  Office render with correct layout

This is a deliberate ideological departure from Debian, made with open eyes.
Every Debian-derived consumer distribution — Mint's LMDE, MX, Zorin — makes
the same one, because the alternative is a desktop that looks finished and
fails at the first video.

Firefox fetches Widevine itself at runtime, so Cedar need not redistribute it;
Cedar's obligation is only to not block that. A Chromium-based browser would
require more, which is one reason Firefox is the default.

## Delivery

**ISO.** `live-build` produces a live ISO; **Calamares** installs it.
Calamares rather than debian-installer: graphical, standard among Debian
derivatives, and debian-installer regresses between releases. The ISO builds
in CI on every tag, so cutting a release is pushing a tag.

**Filesystem.** btrfs, with a subvolume layout designed for snapshots. This is
a load-bearing choice, not a default to drift into.

**Updates and rollback.** Plain `apt`, surfaced graphically through Discover
alongside Flatpak updates, with `unattended-upgrades` handling security
patches silently. Around that, **snapper takes a snapshot before and after
every apt transaction and `grub-btrfs` exposes those snapshots in the boot
menu**. A bad update becomes a reboot and a menu selection.

This is not atomicity. An update is not a single transaction that either lands
or does not, and a power failure can still catch the system mid-upgrade. It
delivers the property that actually mattered in the withdrawn bootc design —
*undo* — using stock Debian components, on a system where every Debian
tutorial on the internet still applies. For this audience that is better than
atomic, not merely cheaper: atomic desktops require learning a new model for
installing anything system-level, and these users do not want a new model.

**Cedar's apt repository is four packages**, signed static files hosted on
anything (GitHub Pages or object storage), with the key shipped in
`cedar-keyring`:

- `cedar-desktop` — metapackage defining the system
- `cedar-theme` — engine plus shipped themes
- `cedar-settings` — Plasma defaults as kconfig
- `cedar-branding` — Plymouth, GRUB, wallpapers, os-release

**One channel.** `stable`, tracking Debian stable plus Cedar's point releases.
A `testing` channel is easy to add later and impossible to un-promise.

**First run.** A welcome app that offers the NVIDIA driver if the hardware
wants it, lets the user pick a theme, and gets out of the way. This screen
decides whether a switcher ever sees the desktop working.

## Milestones

1. **It looks like Cedar.** Debian testing plus Plasma, with `cedar-settings`
   producing the layout above and `cedar-theme` applying one theme by hand. A
   VM that looks and behaves like Cedar. Proves the layout and the engine's
   shape, and produces the real list of what Plasma will not preset cleanly.
2. **The theme engine, for real.** `cedar-theme` renders every surface
   including Flatpak extensions; three or more shipped themes; live switching.
   The Cedar apt repository exists and is signed. Theme authoring is
   documented well enough that someone else can write one.
3. **It installs.** `live-build` plus Calamares, btrfs with snapper and
   `grub-btrfs`, first-run welcome, contrib/non-free, the curated app set, CI
   building the ISO on tag. Output: an ISO a stranger can install on real
   hardware.
4. **Cedar 1.0 on Debian 14.** Rebase to forky when it goes stable, hardware
   testing across a real matrix, documentation, cedarlinux.org.

Milestones 1–3 run against Debian testing. Milestone 4 is gated on Debian's
release schedule, roughly mid-2027.

## Open items

- The `cedarlinux` GitHub organisation does not exist yet and neither does a
  hosting account for the apt repository. Neither blocks milestone 1.
- Debian 14's release date is not announced; mid-2027 is inferred from
  Debian's roughly two-year cadence. Cedar's 1.0 date moves with it.
- Whether Debian packages LibreOffice's Qt/KF6 VCL backend, and whether it is
  good enough to be the default, is unverified.
- The mechanism for the one-click NVIDIA install in the welcome app is
  undecided.
- Whether Plasma can place a fixed Show Desktop widget in a screen corner
  independent of a panel needs verifying; if not, it moves to the top bar's
  far right.
- Snapshot disk headroom on small SSDs, and what Calamares should default to,
  is unsized.
