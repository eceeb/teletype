#include "CPTY.h"

#include <unistd.h>
#include <sys/ioctl.h>

pid_t cpty_spawn(int slave_fd, int master_fd, char *const argv[], char *const envp[]) {
    pid_t pid = fork();
    if (pid == 0) {
        // Child: only async-signal-safe calls until exec.
        setsid();                       // new session, no controlling tty
        ioctl(slave_fd, TIOCSCTTY, 0);  // make the slave our controlling tty
        dup2(slave_fd, 0);
        dup2(slave_fd, 1);
        dup2(slave_fd, 2);
        if (slave_fd > 2) {
            close(slave_fd);
        }
        close(master_fd);
        execve(argv[0], argv, envp);
        _exit(127);                     // reached only if exec failed
    }
    return pid;                          // parent: child PID, or -1 on error
}
