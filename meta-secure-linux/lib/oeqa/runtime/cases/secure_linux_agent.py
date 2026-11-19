# SPDX-License-Identifier: MIT
from oeqa.runtime.case import OERuntimeTestCase
from oeqa.core.decorator.depends import OETestDepends


class SecureLinuxAgentTest(OERuntimeTestCase):

    @OETestDepends(['ssh.SSHTest.test_ssh'])
    def test_agent_running_as_unprivileged_user(self):
        # pgrep -u: process name exceeds the 15-char comm limit, so match on -f
        status, output = self.target.run("pgrep -u secure-linux -f /usr/bin/secure-linux-agent")
        self.assertEqual(status, 0,
                         msg="secure-linux-agent not running as user secure-linux")
