#include "CPTY.h"

#include <unistd.h>
#include <sys/ioctl.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <stdlib.h>
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

static void basename_into(const char *path, char *out, int out_size) {
    const char *slash = strrchr(path, '/');
    strlcpy(out, slash ? slash + 1 : path, (size_t)out_size);
}

int cpty_foreground_name(int master_fd, pid_t shell_pid, char *out, int out_size) {
    pid_t pgid = tcgetpgrp(master_fd);
    if (pgid <= 0 || pgid == shell_pid) {
        return 0;   // no foreground command — the shell itself is in front
    }
    out[0] = '\0';

    // Prefer the actual command line (argv) so a *script* shows as its own name
    // rather than its interpreter ("zsh"). Layout of KERN_PROCARGS2:
    //   [int argc][exec_path\0][\0 padding][argv0\0][argv1\0]…[env…]
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, pgid };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) == 0 && size > sizeof(int)) {
        char *buf = malloc(size);
        if (buf) {
            if (sysctl(mib, 3, buf, &size, NULL, 0) == 0) {
                char *end = buf + size;
                char *p = buf + sizeof(int);                 // skip argc
                while (p < end && *p != '\0') p++;           // skip exec path
                while (p < end && *p == '\0') p++;           // skip padding
                if (p < end) {
                    char *argv0 = p;
                    char *e0 = argv0;
                    while (e0 < end && *e0 != '\0') e0++;     // end of argv0
                    char *argv1 = (e0 + 1 < end && *(e0 + 1) != '\0') ? e0 + 1 : NULL;
                    char base0[64];
                    basename_into(argv0, base0, sizeof(base0));
                    // If argv0 is a shell running a script, prefer the script.
                    const char *chosen = argv0;
                    if (argv1 && argv1[0] != '-' &&
                        (strcmp(base0, "zsh") == 0 || strcmp(base0, "bash") == 0 ||
                         strcmp(base0, "sh") == 0 || strcmp(base0, "fish") == 0 ||
                         strcmp(base0, "dash") == 0)) {
                        chosen = argv1;
                    }
                    basename_into(chosen, out, out_size);
                }
            }
            free(buf);
        }
    }
    if (out[0] != '\0') return 1;

    // Fallback: the process's own name.
    return (proc_name(pgid, out, (uint32_t)out_size) > 0 && out[0] != '\0') ? 1 : 0;
}
