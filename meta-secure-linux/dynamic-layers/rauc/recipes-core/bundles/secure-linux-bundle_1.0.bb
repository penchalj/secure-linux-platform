# nooelint: oelint.var.mandatoryvar.SRC_URI - bundle.bbclass packs the built image, the recipe has no sources
SUMMARY = "Signed RAUC A/B update bundle for Secure Linux Platform (CRA: secure updates)"
DESCRIPTION = "RAUC A/B update bundle for secure-linux-image, signed with the platform \
update key (secure software updates, EU CRA / UNECE R156)."
HOMEPAGE = "https://gitlab.com/secure-linux/secure-linux-platform"
LICENSE = "MIT"

inherit bundle

RAUC_BUNDLE_COMPATIBLE = "secure-linux-${MACHINE}"
RAUC_BUNDLE_VERSION = "${DISTRO_VERSION}"
RAUC_BUNDLE_FORMAT = "verity"
RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs = "secure-linux-image"
RAUC_SLOT_rootfs[fstype] = "ext4"
