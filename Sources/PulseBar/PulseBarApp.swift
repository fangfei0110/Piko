import AppKit
import SwiftUI

@main
struct PikoMain {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--diagnose") {
            let sampler = SystemSampler()
            _ = await sampler.sample()
            try? await Task.sleep(for:.seconds(1))
            let sample = await sampler.sample()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(sample), let text = String(data:data,encoding:.utf8) { print(text) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private var mainWindowRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePanel)
            button.sendAction(on:[.leftMouseUp,.rightMouseUp])
            button.image = NSImage(systemSymbolName:"waveform.path.ecg",accessibilityDescription:"Piko 系统监控")
            button.image?.isTemplate = true; button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium)
            button.setAccessibilityLabel("Piko 系统监控")
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width:380,height:min(720,(NSScreen.main?.visibleFrame.height ?? 800)-50))
        popover.contentViewController = NSHostingController(rootView:DashboardView(model:model,compact:true,detach:{ [weak self] in self?.showWindow() }))
        model.onStatusChange = { [weak self] in self?.refreshStatus() }
        refreshStatus(); model.start()
        if CommandLine.arguments.contains("--show") { showWindow() }
        else if CommandLine.arguments.contains("--popover") { togglePanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window?.isVisible == true { showWindow() }
        else if !popover.isShown {
            if CommandLine.arguments.contains("--popover") { togglePanel() }
            else { showWindow() }
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        restoreMainWindowFocus()
    }

    func popoverDidClose(_ notification: Notification) {
        restoreMainWindowFocus()
    }

    private func restoreMainWindowFocus() {
        guard mainWindowRequested, !popover.isShown, NSApp.isActive, !NSApp.isHidden,
              let window, window.isVisible, !window.isMiniaturized else { return }
        if let sheet = window.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        mainWindowRequested = false
    }

    private func refreshStatus() {
        let s = model.snapshot
        statusItem.button?.attributedTitle = StatusBarTitle.make(snapshot:s,showCPU:model.showCPU,
            showMemory:model.showMemory,showGPU:model.showGPU,showNetwork:model.showNetwork,showDisk:model.showDisk,
            paused:model.paused,typography:model.statusBarTypography)
        let diskSummary = s.startupDisk.map { "启动磁盘可用 \(Readout.bytes($0.available)) / \(Readout.bytes($0.total))" } ?? "启动磁盘读数未提供"
        statusItem.button?.setAccessibilityValue("CPU \(Readout.percent(s.cpu))，内存 \(Readout.percent(s.memory?.percent))，GPU \(Readout.percent(s.gpu))，\(diskSummary)，下载 \(Readout.rate(s.primaryNetwork?.download))，上传 \(Readout.rate(s.primaryNetwork?.upload))" + (model.paused ? "，已暂停" : ""))
        statusItem.button?.toolTip = "Piko · \(model.stateTitle)\nCPU \(Readout.percent(s.cpu)) · 内存 \(Readout.percent(s.memory?.percent))\n\(diskSummary)\n点击查看详情，右键打开快捷菜单"
        let appearance = NSAppearance(named:model.appearance.nativeAppearanceName)
        if popover.appearance?.name != appearance?.name { popover.appearance = appearance }
        if window?.appearance?.name != appearance?.name { window?.appearance = appearance }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let actions: [(String,Selector,String)] = [
                ("打开监控窗口",#selector(showWindow),""),
                (model.paused ? "继续监控" : "暂停监控",#selector(pause),""),
                ("设置…",#selector(showSettings),","),
                ("活动监视器",#selector(activity),""),
                ("退出 Piko",#selector(quit),"q")
            ]
            for (title,action,key) in actions { let item = NSMenuItem(title:title,action:action,keyEquivalent:key); item.target = self; menu.addItem(item) }
            menu.popUp(positioning:nil,at:NSPoint(x:0,y:button.bounds.minY),in:button)
        } else if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
            popover.contentViewController?.view.window?.backgroundColor = .clear
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps:true)
        }
    }

    @objc private func showWindow() {
        mainWindowRequested = true
        popover.performClose(nil)
        if window == nil {
            let size = NSSize(width:min(980,(NSScreen.main?.visibleFrame.width ?? 1100)-80),height:min(760,(NSScreen.main?.visibleFrame.height ?? 840)-60))
            let w = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            w.title = "Piko · 系统监控"; w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false; w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false
            w.delegate = self
            w.minSize = NSSize(width:780,height:580)
            w.contentViewController = NSHostingController(rootView:DashboardView(model:model,detach:{ [weak self] in
                self?.mainWindowRequested = false
                self?.window?.orderOut(nil)
                self?.togglePanel()
            }))
            w.setContentSize(size)
            w.center(); window = w
            model.maintenance.presentationWindow = w
            refreshStatus()
        }
        // Activation is asynchronous. Restore ordering again when AppKit confirms it.
        NSApp.activate(ignoringOtherApps:true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        // Explicit open requests must be visible even while activation is pending.
        // This changes ordering once, not the window's level or always-on-top behavior.
        window?.orderFrontRegardless()
        restoreMainWindowFocus()
        DispatchQueue.main.async { [weak self] in self?.restoreMainWindowFocus() }
    }
    func applicationWillTerminate(_ notification: Notification) { model.stopAwake() }
    @objc private func showSettings() { model.section = .settings; model.tab = .settings; showWindow() }
    @objc private func pause() { model.togglePause() }
    @objc private func activity() { model.openActivityMonitor() }
    @objc private func quit() { NSApp.terminate(nil) }
}
