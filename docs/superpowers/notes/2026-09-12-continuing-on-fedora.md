# Continuing Cedar on the Fedora machine

Written 2026-09-12, on the Mac, immediately before the mini PC install.

## Where the project stands

**Milestone 1's automated half is complete, merged to `main`, and green.**
`ghcr.io/cedarlinux/cedar:44` is published, signed, and anonymously pullable.
CI builds, tests, signs and verifies on every push to `main`.

**Task 7 has never run.** Nothing has rebased onto Cedar, booted it, exercised
`bootupctl`, or tested rollback. The milestone's headline claim — *"it boots and
it is Cedar"* — is untested. That is the next work, and it is why this machine
is being installed.

Follow `docs/superpowers/notes/2026-09-12-task-7-checklist.md`. Its step 0
(package visibility) is already done.

## What travels, and what does not

**Everything that matters is in git.** Specs, the plan, the base-image facts,
the full execution ledger with all fifteen rulings, the Task 7 checklist, and
`CLAUDE.md`. Clone the repo and the project's memory comes with it.

**Left behind on the Mac, deliberately:**

- `.remember/` and `.superpowers/` — session scratch, gitignored, not needed.
- `cosign.key` — the private signing key. It exists **only** as the GitHub
  secret `SIGNING_SECRET`. Do not regenerate it casually: a new key means every
  published image must be re-signed and every installed machine re-rebased to
  trust it. If it is ever lost, generate a new pair, commit the new `cosign.pub`,
  update the secret, and republish.

## Setting up the Fedora machine

Fedora Atomic is **immutable** — `dnf install` does not work the way it does
elsewhere. Two options, in preference order:

**Toolbox (recommended for dev work)** — a mutable container sharing your home
directory, leaving the host image clean:

```bash
toolbox create cedar-dev
toolbox enter cedar-dev
sudo dnf install -y git just nodejs npm gh cosign skopeo
```

**Layering (only for things that must be on the host):**

```bash
rpm-ostree install just
sudo systemctl reboot     # layering needs a reboot
```

`podman` is preinstalled on the host and does not need either.

### Then

```bash
gh auth login                                     # as cedarlinux
git clone https://github.com/cedarlinux/cedar.git
cd cedar
just check                                        # should pass end to end
```

Install Claude Code however you prefer; point it at this directory and it will
read `CLAUDE.md` automatically.

## Two things that get better on this machine

**Builds go native.** The Mac is arm64, so every build ran x86_64 under emulation
at roughly a 10–20× penalty. On the mini PC they are native — expect builds in a
fraction of the time, and `--platform=linux/amd64` becomes a harmless no-op.

**You can test the real thing.** Rebase, boot, `bootupctl`, rollback, and
eventually the ISO all need actual hardware. This machine is the first time
Cedar can be judged as an operating system rather than a filesystem.

## One thing that gets worse

**You will be developing Cedar on the machine that runs Cedar.** A bad image
bricks your dev environment. Mitigations, in order:

1. `rpm-ostree rollback` plus a reboot recovers the previous deployment — this is
   the property the whole atomic design exists for, and Task 7 step 8 tests it.
2. Keep the Fedora COSMIC Atomic USB. If both deployments are bad, reinstall and
   rebase; nothing in the repo is lost.
3. `just check` locally before pushing. CI catches the rest.

## Open items, in priority order

1. **Task 7** — the checklist. Record which Secure Boot keys are enrolled; if the
   Fedora USB booted with Secure Boot on, factory keys with Microsoft's CA are
   present, and the spec's claim is testable as written.
2. **The "still Fedora" list** that Task 7 produces — every surface still saying
   Fedora. That is milestone 3's input.
3. **Visual identity** — the greens and logo are placeholders invented while
   drafting. Due before the milestone 2 ISO.
4. **Milestone 2's ESP check** — the boot-chain guard is necessary but not
   sufficient for an ISO. See the spec's Secure Boot section.
