SUMMARY = "Secure Linux Platform hardened reference image"
DESCRIPTION = "Minimal, hardened image with SBOM, CVE analysis and test hooks."
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "ssh-server-openssh read-only-rootfs"
IMAGE_INSTALL:append = " \
    packagegroup-core-boot \
    secure-linux-agent \
    secure-linux-sysctl \
    nftables \
    audit \
    ${@bb.utils.contains('DISTRO_FEATURES', 'rauc', 'rauc', '', d)} \
"

# Non-root service user; root account locked (CRA: secure by default)
EXTRA_USERS_PARAMS = " \
    useradd -r -s /sbin/nologin secure-linux; \
    ${@'' if d.getVar('SLP_TEST_IMAGE') == '1' else 'usermod -L root;'} \
"

# --- Test integration (ci: test:qemu) ----------------------------------------
IMAGE_CLASSES += "testimage"
TEST_SUITES = "ping ssh systemd secure_linux_hardening secure_linux_agent"
TEST_RUNQEMUPARAMS = "nographic slirp"
QB_MEM = "-m 1024"
TESTIMAGE_AUTO ?= "0"
SLP_TEST_IMAGE ??= "0"

# --- Image-level security gate ------------------------------------------------
ROOTFS_POSTPROCESS_COMMAND:append = " secure_linux_rootfs_audit"

secure_linux_rootfs_audit () {
    # 1. No world-writable files outside tmp dirs
    ww=$(find ${IMAGE_ROOTFS} -xdev -type f -perm -0002 \
         ! -path '*/tmp/*' ! -path '*/var/volatile/*' 2>/dev/null || true)
    if [ -n "$ww" ]; then
        bbfatal "World-writable files found in rootfs: $ww"
    fi
    # 2. No empty password hashes (test images opt out via kas/features/test.yml)
    if [ "${SLP_TEST_IMAGE}" != "1" ] && \
       grep -qE '^[^:]+::' ${IMAGE_ROOTFS}${sysconfdir}/shadow; then
        bbfatal "Account with empty password found in /etc/shadow"
    fi
    # 3. Unexpected setuid binaries
    find ${IMAGE_ROOTFS} -xdev -perm -4000 -type f \
        > ${WORKDIR}/setuid-inventory.txt 2>/dev/null || true
    bbnote "setuid inventory: $(wc -l < ${WORKDIR}/setuid-inventory.txt) files"
}
