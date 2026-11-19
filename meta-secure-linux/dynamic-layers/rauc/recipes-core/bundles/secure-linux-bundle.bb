SUMMARY = "Signed RAUC A/B update bundle for Secure Linux Platform (CRA: secure updates)"
LICENSE = "MIT"

inherit bundle

RAUC_BUNDLE_COMPATIBLE = "secure-linux-${MACHINE}"
RAUC_BUNDLE_VERSION = "${DISTRO_VERSION}"
RAUC_BUNDLE_FORMAT = "verity"
RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs = "secure-linux-image"
RAUC_SLOT_rootfs[fstype] = "ext4"
