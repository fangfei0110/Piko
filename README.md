# Piko

A native macOS menu bar system monitor and conservative maintenance workspace. SwiftUI, AppKit, Mach, libproc and IOKit; no third-party packages, daemon, administrator access, server, or persistent metric logs.

Piko was previously named PulseBar. The bundle identifier `com.fei.pulsebar`, source module, and project directory are intentionally retained to preserve existing preferences and project references. The installed app and executable are named `Piko`.

The interface uses a compact 380-point menu-bar HUD and a larger maintenance window, informed by the user's Mole 1.13.0 references. There is no large branded header: measured metrics, high-usage processes and actions get the space. Three persistent appearance themes (cold, warm and dark), Reduce Motion and Reduce Transparency are supported.

## Use

Click the waveform in the menu bar for the live dashboard. Right-click it for quick actions. The expand control opens a resizable window. Settings select menu bar readings, sampling interval (1/2/5/10 seconds), appearance and optional login launch. Labels and numbers have separate font-family, size (9-16 points) and bold controls, with a live preview and automatic saving.

The menu bar separates labels and values with a half-em space rather than dots or hyphens. Normal values stay neutral. CPU, GPU and memory usage turn yellow at 80% and red at 90%; elevated system memory pressure can also escalate the indication. Startup disk available capacity turns yellow at 15% remaining and red at 10% remaining. Network speed is not treated as a warning. Colors adapt to the system menu-bar appearance independently of the panel theme.

- CPU total, individual cores, load averages, GPU activity when available.
- Application, wired, compressed and cached memory, pressure and swap.
- Startup data volume, external volumes, available capacity and physical device I/O.
- Primary network interface throughput, all up interfaces, local IPv4 addresses and interface counters.
- Searchable process list, CPU/memory sorting, PID, thread count, Activity Monitor shortcut.
- Hardware, OS, uptime, power, battery when present, thermal pressure and low-power mode.
- Up to one hour of bounded in-memory history, pause/resume and user-requested JSON snapshot export.
- On-demand preview of user caches, logs and old disk-image/package installers; nothing is preselected.
- Directory-size analysis with drill-down treemap, partial-result notices and Finder reveal.
- Installed-application size, running state and exact bundle-ID-related data inspection (read-only).
- Session process pinning, CPU/memory sorting and one-hour keep-screen-awake with automatic release on exit.

## Cleanup Safety

The scanner considers direct children of `~/Library/Caches`, `~/Library/Logs`, and `.dmg`/`.pkg`/`.xip` files in `~/Downloads`. Cache/log items changed in the last seven days and installers changed in the last thirty days are not eligible. Apple, cloud, Steam/Dota, keychain, hidden and incomplete items are excluded or read-only. Symlinks are not traversed; hard links are counted once per scan root. Each recursive item is bounded at 150,000 entries and marks incomplete results instead of claiming a full total.

After explicit confirmation, cleanup revalidates path identity and a recursive metadata fingerprint, checks running app identifiers and open files with a time-bounded `lsof`, checks the metadata again and uses the macOS Trash API. Ambiguous checks fail closed. There is no permanent-delete mode, automatic Trash emptying or privilege escalation. Space is not freed until the user empties Trash. This release does not uninstall or update apps, alter startup items directly, or control fans; those system tasks are not implied by the Mole reference.

History starts empty and resets on exit. Network is counted on the primary interface rather than summed with tunnels. CPU is normalized to all cores; process CPU uses the Activity Monitor convention of 100% per core. Process memory prefers physical footprint and falls back to RSS when necessary. Protected processes may be absent. APFS free capacity excludes purgeable estimates. Temperature and fan RPM are explicitly unavailable in this version; the thermal state is the OS pressure signal, not a temperature reading.

## Build

The app runs on macOS 14 or later. Building requires Xcode 26 or matching Command Line Tools with the macOS 26 SDK and Swift 6, including the SDK definitions for controls guarded by availability checks.

```sh
swift test -j 4
bash Scripts/build-app.sh
open dist/Piko.app
```

To build directly into Applications:

```sh
bash Scripts/build-app.sh /Applications
open /Applications/Piko.app
```

The app is locally ad-hoc signed. Launch-at-login can require approval in macOS Login Items settings.

## Diagnostics

```sh
.build/debug/Piko --diagnose
open /Applications/Piko.app --args --show
open /Applications/Piko.app --args --popover
```

The diagnostic command takes two actual samples one second apart and prints JSON, then exits. No synthetic data is used.

Validate native CPU time against `getrusage` and 64-bit network counters against the interface MIB:

```sh
clang -I Sources/SystemProbe/include Scripts/probe-check.c Sources/SystemProbe/SystemProbe.c -framework IOKit -framework CoreFoundation -o /tmp/pulsebar-probe-check
/tmp/pulsebar-probe-check
```

Quit the installed app before rebuilding into `/Applications`.
