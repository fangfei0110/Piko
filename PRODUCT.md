# Piko

## Register

product

## Platform

macOS native, SwiftUI and AppKit. This is a desktop menu bar application.

## Users and Purpose

A Mac mini owner who develops, trades and runs local services. Surface resource bottlenecks immediately and provide conservative, local tools for understanding disk and application usage.

## Implementation Brief

Build a standalone, local-only, dependency-free app. Monitor CPU and individual cores, GPU when exposed by IOKit, memory pressure and swap, mounted disks, network interfaces and throughput, accessible processes, uptime and power state. Add on-demand cleanup previews, directory size analysis, application size and exact related-data inspection, and one-hour keep-awake. Preserve bounded session history, configurable menu bar modules, refresh interval, three appearance choices and launch at login.

## Design Principles

Show measured values and distinguish unavailable data from zero. Preserve native keyboard and window behavior. The user supplied Mole 1.13.0 desktop/HUD references and explicitly rejected the large branded header. Favor compact instrument tiles, restrained materials, small semantic accents and a process table over notification-card decoration. The menu-bar HUD and larger maintenance window serve different densities. Retain cold, warm and dark themes.

Never infer deletion consent from scanning or selecting a directory. Cleanup defaults to no selection, freezes the reviewed paths in a confirmation, checks identity/content changes and open files, and only moves approved items to Trash. It never empties Trash, elevates permissions, kills user processes, uninstalls apps, modifies fan controls or guesses shared-data ownership. A Trash move is not reclaimed disk space.

## Accessibility

Use native controls, descriptive accessibility labels, scalable window layout, explicit status text, and system reduced-motion behavior.
