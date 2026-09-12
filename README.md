# Cedar

A Fedora COSMIC Atomic derivative. Mouse-first, deeply themeable.

## Install

Install Fedora COSMIC Atomic, then rebase onto Cedar. This is a two-hop
process:

```bash
# Hop 1: unverified. Cedar's signing policy and public key ship INSIDE the
# Cedar image itself, so the stock Fedora machine doing this first rebase has
# neither yet — it only has Fedora's default policy, which accepts anything.
# There is no signature to check on this hop regardless of transport used.
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/cedarlinux/cedar:44
sudo systemctl reboot

# Hop 2: verified. Now running Cedar, the machine has cedar.pub and
# policy.json in place, so every rebase from here on is signature-checked.
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/cedarlinux/cedar:44
sudo systemctl reboot
```

A Cedar ISO that installs directly, with no Fedora step, arrives in milestone 2.

## Develop

```bash
just build     # build locally (amd64; emulated and slow on Apple Silicon)
just test      # assertions plus the Secure Boot payload guard
just check     # both
```

Building locally requires the podman machine's memory raised to 4 GiB — the
2 GiB default causes intermittent `ENOMEM` on the branding `COPY` steps.

## Hard constraints

- Never rebuild or replace `shim`, `grub2` or the kernel. Secure Boot is
  inherited from Fedora and survives only while Cedar's signed EFI payload is
  byte-identical to the base. `test/boot-chain.sh` enforces this.
- GRUB branding is limited to `GRUB_BACKGROUND` and `GRUB_THEME` — `insmod` is
  prohibited under Secure Boot.
- `rpm -V` is meaningless in these images; ostree zeroes all mtimes.
