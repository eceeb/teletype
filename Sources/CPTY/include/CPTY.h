#ifndef CPTY_H
#define CPTY_H

#include <sys/types.h>

/// Forks and execs `argv[0]` with environment `envp`, making `slave_fd` the
/// child's controlling terminal (setsid + TIOCSCTTY) so that Ctrl-C / Ctrl-Z
/// and job control work. Returns the child PID to the parent, or -1 on failure.
pid_t cpty_spawn(int slave_fd, int master_fd, char *const argv[], char *const envp[]);

#endif /* CPTY_H */
