#include "SystemProbe.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <net/if.h>
#include <net/if_mib.h>
#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int pb_cpu(PBCPU *out) {
    memset(out, 0, sizeof(*out));
    natural_t count = 0;
    processor_info_array_t info;
    mach_msg_type_number_t size;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &size) != KERN_SUCCESS) return 0;
    out->count = count < PB_MAX_CORES ? count : PB_MAX_CORES;
    for (unsigned int i = 0; i < out->count * 4; i++) out->ticks[i] = (uint32_t)info[i];
    vm_deallocate(mach_task_self(), (vm_address_t)info, size * sizeof(integer_t));
    return 1;
}

int pb_memory(PBMemory *out) {
    memset(out, 0, sizeof(*out));
    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) != KERN_SUCCESS) return 0;
    size_t size = sizeof(out->total);
    if (sysctlbyname("hw.memsize", &out->total, &size, NULL, 0)) return 0;
    vm_size_t page;
    host_page_size(mach_host_self(), &page);
    out->app = (uint64_t)(vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0) * page;
    out->wired = (uint64_t)vm.wire_count * page;
    out->compressed = (uint64_t)vm.compressor_page_count * page;
    out->cached = ((uint64_t)vm.external_page_count + vm.purgeable_count) * page;
    out->free_bytes = (uint64_t)vm.free_count * page;
    struct xsw_usage swap;
    size = sizeof(swap);
    if (!sysctlbyname("vm.swapusage", &swap, &size, NULL, 0)) {
        out->swap_used = swap.xsu_used;
        out->swap_total = swap.xsu_total;
    }
    out->pressure = -1;
    size = sizeof(out->pressure);
    sysctlbyname("kern.memorystatus_vm_pressure_level", &out->pressure, &size, NULL, 0);
    return 1;
}

int pb_interfaces(PBInterface *out, int capacity) {
    struct if_nameindex *interfaces = if_nameindex();
    if (!interfaces) return -1;
    int count = 0;
    for (struct if_nameindex *entry = interfaces; entry->if_index && count < capacity; entry++) {
        // The route-list API can return truncated, KiB-quantized counters on macOS.
        int mib[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, (int)entry->if_index, IFDATA_GENERAL};
        struct ifmibdata data;
        size_t length = sizeof(data);
        if (sysctl(mib, 6, &data, &length, NULL, 0) || length < sizeof(data)) continue;
        if (!(data.ifmd_flags & IFF_UP) || (data.ifmd_flags & IFF_LOOPBACK)) continue;
        PBInterface *item = &out[count++];
        memset(item, 0, sizeof(*item));
        strlcpy(item->name, entry->if_name, sizeof(item->name));
        item->received = data.ifmd_data.ifi_ibytes;
        item->sent = data.ifmd_data.ifi_obytes;
    }
    if_freenameindex(interfaces);
    return count;
}

int pb_processes(PBProcess *out, int capacity) {
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) return 0;
    int estimate = proc_listallpids(NULL, 0);
    if (estimate <= 0) return 0;
    int slots = estimate + 256;
    pid_t *pids = calloc((size_t)slots, sizeof(pid_t));
    if (!pids) return 0;
    int n = proc_listallpids(pids, slots * (int)sizeof(pid_t));
    if (n > slots) n = slots;
    int count = 0;
    for (int i = 0; i < n && count < capacity; i++) {
        if (pids[i] <= 0) continue;
        struct proc_taskinfo task;
        if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof(task)) != sizeof(task)) continue;
        PBProcess *p = &out[count++];
        memset(p, 0, sizeof(*p));
        p->pid = pids[i];
        // proc_taskinfo uses Mach absolute ticks, not nanoseconds on Apple Silicon.
        __uint128_t ticks = (__uint128_t)task.pti_total_user + task.pti_total_system;
        p->cpu_ns = (uint64_t)(ticks * timebase.numer / timebase.denom);
        p->memory = task.pti_resident_size;
        p->threads = task.pti_threadnum;
        struct rusage_info_v2 usage;
        if (!proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage)) {
            p->memory = usage.ri_phys_footprint;
            p->start_time = usage.ri_proc_start_abstime;
        }
        if (proc_name(pids[i], p->name, sizeof(p->name)) <= 0) strlcpy(p->name, "Process", sizeof(p->name));
    }
    free(pids);
    return count;
}

static double number(CFDictionaryRef dict, CFStringRef key) {
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    double result = -1;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    return result;
}

double pb_gpu(void) {
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) != KERN_SUCCESS) return -1;
    double result = -1;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef stats = IORegistryEntryCreateCFProperty(service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            double value = number((CFDictionaryRef)stats, CFSTR("Device Utilization %"));
            if (value >= 0 && value <= 100 && value > result) result = value;
        }
        if (stats) CFRelease(stats);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return result;
}

int pb_disk_io(uint64_t *read_bytes, uint64_t *write_bytes) {
    *read_bytes = 0; *write_bytes = 0;
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) != KERN_SUCCESS) return 0;
    io_object_t service;
    int found = 0;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef stats = IORegistryEntryCreateCFProperty(service, CFSTR("Statistics"), kCFAllocatorDefault, 0);
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            double r = number((CFDictionaryRef)stats, CFSTR("Bytes (Read)"));
            double w = number((CFDictionaryRef)stats, CFSTR("Bytes (Write)"));
            if (r >= 0 && w >= 0) { *read_bytes += (uint64_t)r; *write_bytes += (uint64_t)w; found = 1; }
        }
        if (stats) CFRelease(stats);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return found;
}

double pb_uptime(void) {
    struct timeval boot;
    size_t size = sizeof(boot);
    if (sysctlbyname("kern.boottime", &boot, &size, NULL, 0)) return 0;
    return difftime(time(NULL), boot.tv_sec);
}
