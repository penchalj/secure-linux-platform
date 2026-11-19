SUMMARY = "Secure Linux device agent (demo service with sandboxed systemd unit)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://secure-linux-agent.c \
    file://secure-linux-agent.service \
"

S = "${UNPACKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "secure-linux-agent.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Stricter hardening for our own code (distro-wide flags come from oe-core)
CFLAGS:append = " -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-clash-protection"
CFLAGS:append:x86-64 = " -fcf-protection=full"

do_compile () {
    ${CC} ${CFLAGS} ${LDFLAGS} -Wall -Wextra -Werror \
        -o secure-linux-agent ${S}/secure-linux-agent.c
}

do_install () {
    install -d ${D}${bindir} ${D}${systemd_system_unitdir}
    install -m 0755 secure-linux-agent ${D}${bindir}/
    install -m 0644 ${S}/secure-linux-agent.service ${D}${systemd_system_unitdir}/
}

# Product-level CPE so CVE scanners can match our own component
CVE_PRODUCT = "example:secure-linux-agent"
