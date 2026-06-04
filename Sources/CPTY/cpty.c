#include "CPTY.h"

#include <unistd.h>
#include <sys/ioctl.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <string.h>

pid_t cpty_spawn(int slave_fd, int master_fd, char *const argv[], char *const envp[], const char *cwd) {
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
        if (cwd && cwd[0]) {
            chdir(cwd);                 // best effort; ignore failure (keeps default)
        }
        execve(argv[0], argv, envp);
        _exit(127);                     // reached only if exec failed
    }
    return pid;                          // parent: child PID, or -1 on error
}

int cpty_cwd(pid_t pid, char *buffer, int size) {
    struct proc_vnodepathinfo info;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info)) <= 0) {
        return 0;
    }
    strlcpy(buffer, info.pvi_cdir.vip_path, (size_t)size);
    return 1;
}
