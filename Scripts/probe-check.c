#include "SystemProbe.h"
#include <mach/mach_time.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <stdio.h>
#include <unistd.h>

static uint64_t process_cpu(void) {
    PBProcess processes[4096];
    int count = pb_processes(processes, 4096);
    for (int i = 0; i < count; i++) if (processes[i].pid == getpid()) return processes[i].cpu_ns;
    return 0;
}

static double rusage_cpu(void) {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6 + usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
}

int main(void) {
    PBInterface interfaces[64];
    int count = pb_interfaces(interfaces, 64);
    int valid = count >= 0;
    for (int i = 0; i < count; i++) {
        int mib[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, if_nametoindex(interfaces[i].name), IFDATA_GENERAL};
        struct ifmibdata data;
        size_t length = sizeof(data);
        if (!sysctl(mib, 6, &data, &length, NULL, 0)) {
            printf("%s probe=%llu/%llu mib=%llu/%llu\n", interfaces[i].name, interfaces[i].received, interfaces[i].sent,
                data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes);
            if (data.ifmd_data.ifi_ibytes < interfaces[i].received || data.ifmd_data.ifi_obytes < interfaces[i].sent ||
                data.ifmd_data.ifi_ibytes - interfaces[i].received > 64ULL * 1024 * 1024 ||
                data.ifmd_data.ifi_obytes - interfaces[i].sent > 64ULL * 1024 * 1024) valid = 0;
        }
    }
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    uint64_t a = process_cpu();
    double reference = rusage_cpu();
    uint64_t start = mach_absolute_time();
    while ((mach_absolute_time() - start) * (double)timebase.numer / timebase.denom < 250000000) {}
    double expected = rusage_cpu() - reference;
    double reported = (process_cpu() - a) / 1e9;
    printf("CPU: probe %.6fs, getrusage %.6fs, ratio %.4f, timebase %u/%u\n", reported, expected, reported / expected, timebase.numer, timebase.denom);
    return valid && reported > expected * 0.85 && reported < expected * 1.15 ? 0 : 1;
}
