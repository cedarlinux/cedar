# Task 7 — Boot Cedar on real hardware

The only part of milestone 1 that tests whether Cedar actually *runs*. Everything
else proved it builds.

**Target machine:** x86 mini PC, Intel HD Graphics 520 (Skylake-U), UEFI,
1.8 TB SATA SSD, currently running Omarchy (to be erased).

Intel graphics means **no NVIDIA driver, no DKMS, no MOK enrolment** — the worst
item in the spec does not apply to this machine.

---

## 0. Blocker: make the package public

The mini PC has no GitHub credentials, so it must pull anonymously. As of now it
cannot — `podman pull ghcr.io/cedarlinux/cedar:44` returns `unauthorized`.

- [ ] GitHub → profile → **Packages** → `cedar` → **Package settings** →
      **Change visibility** → **Public**
- [ ] Re-run the failed workflow: `gh run rerun --failed 34705228025`
      (the `verify-public` job exists to confirm exactly this; it should now pass)
- [ ] Confirm from any machine: `podman pull ghcr.io/cedarlinux/cedar:44`

Nothing below works until this is done.

---

## 1. Record the Secure Boot state — before installing

This decides what Task 7b actually proves, so write down what you see.

```bash
bootctl status | grep -i 'secure boot'
```

- `Secure Boot: enabled (user)` — enrolled keys, out of setup mode. **This is the goal.**
- `enabled (setup)` or `disabled (setup)` — setup mode; the PK never took.

- [ ] Recorded: `______________________`
- [ ] Which keys: **your own PK/KEK + Microsoft CA via sbctl**, or **factory keys
      restored in firmware**? Circle one.

**Why it matters.** With sbctl-enrolled keys the result proves *"Cedar boots under
Secure Boot with Microsoft's CA enrolled"* — valid, because Fedora's shim is signed
against Microsoft's CA. It does **not** prove *"Cedar boots on stock factory-key
firmware"*, which is what the spec claims. Record which one you tested so the spec
isn't overstated.

---

## 2. Install Fedora COSMIC Atomic

- [ ] Download from <https://fedoraproject.org/atomic-desktops/cosmic/>
- [ ] Install to the SSD, **Secure Boot left enabled**
- [ ] Boot it and log in

## 3. Confirm the control condition

```bash
grep PRETTY_NAME /etc/os-release          # expect Fedora
bootctl status | grep -i 'secure boot'    # expect enabled
rpm -q cosmic-session                     # expect 1.8.0-1.fc44 or newer
```

- [ ] All three as expected

If Secure Boot is **not** enabled here, stop — Task 7b cannot test anything.

---

## 4. Rebase onto Cedar — two hops, and the order matters

The signature policy and public key ship **inside** Cedar, so a stock Fedora
machine has nothing to verify against. First hop is unverified by necessity.

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/cedarlinux/cedar:44
sudo systemctl reboot
```

- [ ] Rebase succeeded and staged a deployment

**Watch the boot and record each:**

| Surface | Expected | Result |
|---|---|---|
| GRUB entry | contains `Cedar 44` — ostree appends a suffix, so `Cedar 44 (ostree:0)` is **correct**, not a failure | |
| Plymouth splash | Cedar theme, Cedar watermark — not Fedora's | |
| Greeter | reaches COSMIC's greeter | |
| Booted at all with Secure Boot on | yes | |

## 5. Verify identity from a shell

```bash
grep PRETTY_NAME /etc/os-release      # Cedar 44
rpm-ostree status                     # Cedar image, NON-EMPTY version column
bootctl status | grep -i 'secure boot'
plymouth-set-default-theme            # cedar
ls /usr/share/backgrounds/cedar/
cat /etc/containers/policy.json | grep keyPath
```

- [ ] `PRETTY_NAME="Cedar 44"`
- [ ] `rpm-ostree status` shows a **non-empty version** — this is why the branding
      seds os-release in place instead of replacing the file
- [ ] Secure Boot still enabled
- [ ] Plymouth theme is `cedar`

## 6. Now verify a *signed* rebase works

Cedar's policy is on disk now, so this should verify:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/cedarlinux/cedar:44
```

- [ ] Succeeds **with signature verification**

If this fails, the signing chain is broken in a way CI could not detect —
capture the exact error.

---

## 7. `bootupctl` — the only real Secure Boot test in this milestone

Everything so far booted from the ESP **Fedora's installer** wrote. Cedar's own
shim and grub2 have never faced the firmware. This is what puts them there.

```bash
sudo bootupctl status
```

- [ ] Recorded: updates available? auto-update enabled?

```bash
sudo bootupctl update
sudo systemctl reboot
```

- [ ] **Machine boots, Secure Boot still enabled**

**If it fails to boot here**, Cedar's EFI payload is broken. Recover by choosing
the previous deployment in the GRUB menu, and treat it as a failure of
`test/boot-chain.sh` — something got past a guard that should have caught it.

## 8. Rollback, both directions

This replaced snapper and grub-btrfs, so prove it rather than assume it.

```bash
sudo rpm-ostree rollback && sudo systemctl reboot   # expect Fedora
sudo rpm-ostree rollback && sudo systemctl reboot   # expect Cedar again
```

- [ ] Both directions work

---

## 9. Record the results

Write up: the two tables above, `bootupctl status` output, whether the
post-`bootupctl` boot succeeded, whether rollback worked both ways, and which
kind of Secure Boot keys were in use.

Then the **"still Fedora" list** — every place the running system still says
Fedora that Cedar has not claimed: greeter text, COSMIC's About panel, the
hostname, anything you notice. That list is milestone 3's input.

- [ ] Written up

---

## Known gaps this will not test

- The **ISO** — milestone 2. Cedar's own shim and grub2 populate an ESP from
  scratch there, which `boot-chain.sh` explicitly does not cover.
- **COSMIC's theming of GTK/Qt apps** — milestone 4, and Cedar's actual
  differentiator.
- **Cedar's visual identity** — the greens and logo are placeholders invented
  during drafting, not chosen. Due before the milestone 2 ISO.
