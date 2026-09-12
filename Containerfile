# Cedar — a Fedora COSMIC Atomic derivative.
#
# HARD CONSTRAINT: never rebuild or replace shim, grub2, or the kernel.
# Cedar's Secure Boot support is inherited from Fedora and survives only while
# its signed EFI payload is byte-identical to the base. test/boot-chain.sh
# enforces this. See the design spec.
#
# Pinned by digest: the :44 tag is mutable, and a moving base would make the
# boot-chain guard compare against something the build never used.
FROM quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:2535cf2c9b20c4827537baa08605e6ae0254118e1b1a8ca19a1ada250e9cd293

# bootc container lint MUST be the last instruction — it validates the final
# filesystem. Anything added below it goes unlinted.
RUN bootc container lint
