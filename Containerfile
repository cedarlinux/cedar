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

# Wallpapers and logo
COPY branding/wallpapers/ /usr/share/backgrounds/cedar/
COPY branding/logo/cedar-logo.svg /usr/share/pixmaps/cedar-logo.svg
COPY branding/plymouth-watermark.png /tmp/cedar-watermark.png

# Two os-release keys deferred from Task 3 until the assets they name exist.
# LOGO could not be set earlier without pointing at a file that was not yet
# installed; it is set here, immediately after the logo is COPYed above.
#
# CPE_NAME is deliberately LEFT as Fedora's. It feeds CPE-based CVE and asset
# scanners, and Cedar's packages genuinely ARE Fedora 44 packages, so matching
# Fedora 44 advisories is the accurate result. A cedarlinux CPE would match no
# known vulnerability database and make Cedar silently appear vulnerability-free.
RUN set -eux; \
    sed -i 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="cedar"/' /usr/lib/os-release; \
    sed -i 's/^LOGO=.*/LOGO=cedar-logo/'                      /usr/lib/os-release; \
    grep -q '^DEFAULT_HOSTNAME="cedar"' /usr/lib/os-release; \
    grep -q '^LOGO=cedar-logo'          /usr/lib/os-release

# Plymouth. Derived from the stock spinner theme so Cedar inherits a working
# splash rather than authoring one, then renamed and re-watermarked.
RUN set -eux; \
    cp -r /usr/share/plymouth/themes/spinner /usr/share/plymouth/themes/cedar; \
    mv /usr/share/plymouth/themes/cedar/spinner.plymouth \
       /usr/share/plymouth/themes/cedar/cedar.plymouth; \
    sed -i 's/^Name=.*/Name=Cedar/;s/^Description=.*/Description=Cedar boot splash/' \
       /usr/share/plymouth/themes/cedar/cedar.plymouth; \
    sed -i 's|ImageDir=.*|ImageDir=/usr/share/plymouth/themes/cedar|' \
       /usr/share/plymouth/themes/cedar/cedar.plymouth; \
    cp /tmp/cedar-watermark.png /usr/share/plymouth/themes/cedar/watermark.png; \
    rm -f /tmp/cedar-watermark.png; \
    plymouth-set-default-theme cedar

# Regenerate the initramfs so the Plymouth theme is actually present at boot.
# MANDATORY, not optional: the base ships an initramfs containing Fedora's
# theme. Note the target path — on Atomic /boot is empty, so plain
# `dracut --force --regenerate-all` writes nowhere useful. `--add ostree` is
# required or the result cannot boot an ostree system.
RUN set -eux; \
    KV="$(rpm -q --queryformat='%{evr}.%{arch}' kernel-core)"; \
    export DRACUT_NO_XATTR=1; \
    dracut --no-hostonly --kver "$KV" --reproducible --zstd -v --add ostree \
           -f "/usr/lib/modules/${KV}/initramfs.img"; \
    chmod 0600 "/usr/lib/modules/${KV}/initramfs.img"

# Signature verification policy. Ships in the image so that `rpm-ostree rebase
# ostree-image-signed:` works on a running Cedar system.
COPY cosign.pub /usr/etc/pki/containers/cedar.pub
COPY branding/policy.json /usr/etc/containers/policy.json
COPY branding/ghcr.yaml /usr/etc/containers/registries.d/ghcr.yaml

# bootc container lint MUST be the last instruction — it validates the final
# filesystem. Anything added below it goes unlinted.
RUN bootc container lint
