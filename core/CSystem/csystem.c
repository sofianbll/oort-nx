#define _GNU_SOURCE
#include "csystem.h"

#if defined(__linux__)
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>

int oort_rename_noreplace(const char *from, const char *to) {
    return renameat2(AT_FDCWD, from, AT_FDCWD, to, RENAME_NOREPLACE);
}

int oort_rename_exchange(const char *from, const char *to) {
    return renameat2(AT_FDCWD, from, AT_FDCWD, to, RENAME_EXCHANGE);
}

int oort_birth_time(const char *path, uint64_t device, uint64_t inode, int64_t *seconds, int32_t *nanoseconds) {
    struct statx info;
    if (statx(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW, STATX_BTIME | STATX_INO, &info) != 0 ||
        (info.stx_mask & (STATX_BTIME | STATX_INO)) != (STATX_BTIME | STATX_INO) ||
        makedev(info.stx_dev_major, info.stx_dev_minor) != device || info.stx_ino != inode)
        return 0;
    *seconds = info.stx_btime.tv_sec;
    *nanoseconds = info.stx_btime.tv_nsec;
    return 1;
}

int oort_spawn_chdir(void *actions, const char *path) {
    return posix_spawn_file_actions_addchdir_np(actions, path);
}

int oort_spawn_closefrom(void *actions, int from) {
#if defined(__GLIBC__)
#if __GLIBC_PREREQ(2, 34)
    return posix_spawn_file_actions_addclosefrom_np(actions, from);
#endif
#endif
    return ENOSYS;
}

int oort_child_status(int pid, int *status) {
    siginfo_t info = {0};
    if (waitid(P_PID, pid, &info, WEXITED | WNOWAIT | WNOHANG) != 0 || info.si_pid == 0) return 0;
    switch (info.si_code) {
    case CLD_EXITED: *status = info.si_status; return 1;
    case CLD_KILLED:
    case CLD_DUMPED: *status = 128 + info.si_status; return 1;
    default: return 0;
    }
}
#endif
