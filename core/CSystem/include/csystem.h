#ifndef OORT_CSYSTEM_H
#define OORT_CSYSTEM_H

#include <stdint.h>

int oort_rename_noreplace(const char *from, const char *to);
int oort_rename_exchange(const char *from, const char *to);
int oort_birth_time(const char *path, uint64_t device, uint64_t inode, int64_t *seconds, int32_t *nanoseconds);
int oort_spawn_chdir(void *actions, const char *path);
int oort_spawn_closefrom(void *actions, int from);
int oort_child_status(int pid, int *status);

#endif
