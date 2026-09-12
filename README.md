# Cedar

A Fedora COSMIC Atomic derivative. Mouse-first, deeply themeable.

## Install

Install Fedora COSMIC Atomic, then rebase onto Cedar:

```bash
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

## Hard constraints

- Never rebuild or replace `shim`, `grub2` or the kernel. Secure Boot is
  inherited from Fedora and survives only while Cedar's signed EFI payload is
  byte-identical to the base. `test/boot-chain.sh` enforces this.
- GRUB branding is limited to `GRUB_BACKGROUND` and `GRUB_THEME` — `insmod` is
  prohibited under Secure Boot.
- `rpm -V` is meaningless in these images; ostree zeroes all mtimes.
