#ifndef SYSTEM_PROBE_H
#define SYSTEM_PROBE_H
#include <stdint.h>

#define PB_MAX_CORES 128
#define PB_MAX_INTERFACES 64
typedef struct {
    uint32_t count;
    uint32_t ticks[PB_MAX_CORES * 4];
} PBCPU;
typedef struct {
    uint64_t total, app, wired, compressed, cached, free_bytes, swap_used, swap_total;
    int pressure;
} PBMemory;
typedef struct {
    char name[32];
    uint64_t received, sent;
} PBInterface;
typedef struct {
    int32_t pid;
    uint64_t cpu_ns, memory, start_time;
    int threads;
    char name[256];
} PBProcess;
int pb_cpu(PBCPU *out);
int pb_memory(PBMemory *out);
int pb_interfaces(PBInterface *out, int capacity);
int pb_processes(PBProcess *out, int capacity);
double pb_gpu(void);
double pb_uptime(void);
int pb_disk_io(uint64_t *read_bytes, uint64_t *write_bytes);
#endif
