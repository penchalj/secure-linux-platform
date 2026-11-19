# SPDX-License-Identifier: MIT
"""Runtime security regression tests executed by testimage on QEMU."""
from oeqa.runtime.case import OERuntimeTestCase
from oeqa.core.decorator.depends import OETestDepends


class SecureLinuxHardeningTest(OERuntimeTestCase):

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    def test_service_user_has_no_shell(self):
        status, output = self.target.run("getent passwd secure-linux | cut -d: -f7")
        self.assertEqual(status, 0, msg=output)
        self.assertEqual(output.strip(), "/sbin/nologin")

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    def test_rootfs_readonly(self):
        status, output = self.target.run("touch /usr/.rw-probe")
        self.assertNotEqual(status, 0, msg="rootfs is writable")

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    def test_kernel_hardening_sysctls(self):
        for key, expected in (("kernel.kptr_restrict", "1"),
                              ("kernel.dmesg_restrict", "1"),
                              ("kernel.yama.ptrace_scope", "1")):
            status, output = self.target.run(f"sysctl -n {key}")
            self.assertEqual(status, 0, msg=f"{key} not readable")
            self.assertGreaterEqual(int(output.strip()), int(expected),
                                    msg=f"{key}={output.strip()} < {expected}")

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    def test_agent_sandbox_score(self):
        # systemd-analyze security: exposure score must be <= 3.0 ("OK")
        status, output = self.target.run(
            "systemd-analyze security secure-linux-agent.service --no-pager | tail -1")
        self.assertEqual(status, 0, msg=output)
        score = float(output.split()[-3])
        self.assertLessEqual(score, 3.0, msg=f"exposure score too high: {output}")
