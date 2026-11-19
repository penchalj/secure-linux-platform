SUMMARY = "Secure Linux Platform kernel runtime hardening sysctls"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://90-secure-linux-hardening.conf"
S = "${UNPACKDIR}"

do_install () {
    install -d ${D}${sysconfdir}/sysctl.d
    install -m 0644 ${S}/90-secure-linux-hardening.conf ${D}${sysconfdir}/sysctl.d/
}
FILES:${PN} = "${sysconfdir}/sysctl.d"
