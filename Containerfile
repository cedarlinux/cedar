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

# Cedar identity. Edited in place rather than replaced, so that the
# OSTREE_VERSION rpm-ostree injects at build time survives. /etc/os-release is
# a symlink to this file.
RUN set -eux; \
    sed -i 's/^NAME=.*/NAME="Cedar"/'                          /usr/lib/os-release; \
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Cedar 44"/'         /usr/lib/os-release; \
    sed -i 's/^VARIANT=.*/VARIANT="COSMIC Atomic"/'            /usr/lib/os-release; \
    sed -i 's/^VARIANT_ID=.*/VARIANT_ID=cedar/'                /usr/lib/os-release; \
    sed -i 's/^ID=fedora/ID=cedar\nID_LIKE="fedora"/'          /usr/lib/os-release; \
    sed -i 's|^HOME_URL=.*|HOME_URL="https://cedarlinux.org/"|' /usr/lib/os-release; \
    sed -i 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/cedarlinux/cedar/issues"|' /usr/lib/os-release; \
    sed -i '/^REDHAT_BUGZILLA_PRODUCT/d; /^REDHAT_SUPPORT_PRODUCT/d; /^SUPPORT_URL/d; /^DOCUMENTATION_URL/d' /usr/lib/os-release; \
    echo "Cedar release 44 (COSMIC Atomic)" > /etc/system-release; \
    sed -i 's/^EFIDIR=.*/EFIDIR="fedora"/' /usr/sbin/grub2-switch-to-blscfg

# Cedar identity, continued: the ostree boot entry title comes from
# PRETTY_NAME in /usr/lib/os-release, which ostree reads in preference to
# /etc/os-release. No separate GRUB title branding is needed or possible.

# bootc container lint MUST be the last instruction — it validates the final
# filesystem. Anything added below it goes unlinted.
RUN bootc container lint
