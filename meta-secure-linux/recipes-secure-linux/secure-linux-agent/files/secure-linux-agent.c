// SPDX-License-Identifier: MIT
// Minimal heartbeat agent - stands in for a real device service.
#include <signal.h>
#include <stdio.h>
#include <syslog.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void on_term(int sig)
{
    (void)sig;
    running = 0;
}

int main(void)
{
    struct sigaction sa = {0};
    sa.sa_handler = on_term;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    openlog("secure-linux-agent", LOG_PID, LOG_DAEMON);
    syslog(LOG_INFO, "started");
    while (running) {
        syslog(LOG_DEBUG, "heartbeat");
        sleep(30);
    }
    syslog(LOG_INFO, "stopped");
    closelog();
    return 0;
}
