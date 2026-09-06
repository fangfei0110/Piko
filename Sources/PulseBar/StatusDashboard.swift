import SwiftUI
import ServiceManagement

struct StatusDashboard: View {
    @ObservedObject var model: MonitorModel
    let compact: Bool
    let openDetail: (MonitorTab) -> Void
    let openSection: (WorkspaceSection) -> Void
    @Environment(\.monitorPalette) private var palette
    private var s: Snapshot { model.snapshot }
    private var statusColor: Color { model.paused || model.loading ? palette.secondaryInk : model.concerns.isEmpty ? palette.positive : palette.warning }

    var body: some View {
        VStack(alignment:.leading,spacing:compact ? 10 : 16) {
            if !compact {
                HStack(alignment:.firstTextBaseline) {
                    Label(model.stateTitle,systemImage:model.stateSymbol)
                        .font(.system(size:13,weight:.semibold)).foregroundStyle(statusColor)
                    Spacer()
                    Text("\(model.hardware.chip) · \(Readout.bytes(model.hardware.memory)) · \(Readout.uptime(s.uptime))")
                        .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
                }
            }
            LazyVGrid(columns:compact ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.adaptive(minimum:200),spacing:10)],spacing:10) {
                metric("CPU",symbol:"cpu",color:palette.brand,value:Readout.percent(s.cpu),
                       badge:cpuTopology,detail:s.loads.first.map { String(format:"负载 %.2f / %d 核",$0,model.hardware.cores) } ?? "等待读数",tab:.cpu) {
                    CoreActivityBars(values:s.cores,color:palette.brand)
                }
                metric("GPU",symbol:"square.3.layers.3d",color:palette.transfer,value:Readout.percent(s.gpu),
                       badge:s.gpu == nil ? "未提供" : "图形",detail:"图形处理器使用率",tab:.cpu) {
                    MetricChart(points:model.visibleHistory,key:\.gpu,color:palette.transfer,height:28,small:true)
                }
                metric("内存",symbol:"memorychip",color:palette.supporting,value:Readout.percent(s.memory?.percent),
                       badge:s.memory.map { "压力\($0.pressureName)" } ?? "未提供",
                       detail:s.memory.map { "已用 \(Readout.bytes($0.used)) · 交换 \(Readout.bytes($0.swapUsed,compact:true))" } ?? "等待读数",tab:.memory) {
                    MetricChart(points:model.visibleHistory,key:\.memory,color:palette.supporting,height:28,small:true)
                }
                metric("磁盘",symbol:"internaldrive",color:palette.brand,
                       value:s.disks.first.map { Readout.bytes($0.available) } ?? "—",
                       badge:"可用",detail:s.disks.first.map { "已用 \(Readout.percent($0.percent)) · \(Readout.bytes($0.total))" } ?? "等待读数",tab:.disks) {
                    if let disk = s.disks.first {
                        Meter(percent:disk.percent,color:disk.percent >= 90 ? palette.warning : palette.brand).frame(height:28)
                    } else { Color.clear.frame(height:28) }
                }
                metric("网络",symbol:"network",color:palette.transfer,value:Readout.rate(s.primaryNetwork?.download),
                       badge:s.primaryNetwork?.id ?? "未连接",
                       detail:"实线 ↓ 下载 · 虚线 ↑ \(Readout.rate(s.primaryNetwork?.upload))",tab:.network) {
                    MetricChart(points:model.visibleHistory,key:\.download,color:palette.transfer,secondKey:\.upload,percent:false,height:28,small:true)
                }
                metric("散热",symbol:"thermometer.medium",color:palette.warning,value:s.thermal,
                       badge:"系统状态",detail:"温度 / 风扇转速未提供",tab:.system) {
                    HStack(spacing:4) {
                        ForEach(0..<4) { index in
                            Capsule().fill(index <= thermalLevel ? thermalColor : palette.ink.opacity(0.06)).frame(height:4)
                        }
                    }.frame(height:28)
                }
                if !compact {
                    metric("电源",symbol:s.power.batteryPercent == nil ? "powerplug" : "battery.100",color:palette.positive,
                           value:s.power.batteryPercent.map { Readout.percent($0) } ?? s.power.source,
                           badge:s.lowPower ? "低电量模式" : "正常",detail:s.power.charging ? "正在充电" : s.power.batteryPercent == nil ? "未检测到内置电池" : s.power.source,tab:.system) {
                        HStack {
                            Image(systemName:s.power.charging ? "bolt.fill" : "desktopcomputer")
                            Text(model.awakeUntil == nil ? "自动休眠" : "保持屏幕唤醒")
                        }.font(.system(size:11)).foregroundStyle(palette.secondaryInk).frame(height:28)
                    }
                    metric("磁盘读写",symbol:"arrow.left.arrow.right",color:palette.brand,value:Readout.rate(s.diskRead),
                           badge:"读取",detail:"虚线 写入 \(Readout.rate(s.diskWrite))",tab:.disks) {
                        MetricChart(points:model.visibleHistory,key:\.diskRead,color:palette.brand,secondKey:\.diskWrite,percent:false,height:28,small:true)
                    }
                }
            }
            if compact {
                HStack(spacing:6) {
                    Image(systemName:s.power.batteryPercent == nil ? "powerplug" : "battery.100")
                    Text(s.power.batteryPercent.map { "\(Readout.percent($0)) · \(s.power.source)" } ?? s.power.source)
                    Spacer()
                    Text(s.lowPower ? "低电量模式" : "正常供电")
                }.font(.system(size:10)).foregroundStyle(palette.secondaryInk).padding(.horizontal,2)
            }
            processList
            HStack(spacing:8) {
                Button { model.toggleAwake() } label: {
                    Label(model.awakeUntil == nil ? "保持唤醒" : "唤醒至 \(model.awakeUntil!.formatted(date:.omitted,time:.shortened))",
                          systemImage:model.awakeUntil == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                }.help("保持屏幕唤醒一小时；再次点击关闭")
                    .foregroundStyle(model.awakeUntil == nil ? palette.secondaryInk : palette.brand)
                Spacer()
                Button { model.openActivityMonitor() } label: { Label("活动监视器",systemImage:"waveform.path") }
                if !compact {
                    Button { openSection(.analysis) } label: { Label("磁盘分析",systemImage:"chart.pie") }
                }
            }.font(.system(size:11)).buttonStyle(.plain).foregroundStyle(palette.secondaryInk).padding(.vertical,3)
        }
    }

    private var cpuTopology: String {
        if model.hardware.efficiencyCores > 0 { return "\(model.hardware.performanceCores)P · \(model.hardware.efficiencyCores)E" }
        return "\(model.hardware.cores) 核"
    }
    private var thermalLevel: Int {
        switch s.thermal { case "正常": 0; case "温热": 1; case "偏热": 2; case "过热": 3; default: -1 }
    }
    private var thermalColor: Color { thermalLevel == 0 ? palette.positive : palette.warning }

    private func metric<Content: View>(_ title: String,symbol: String,color: Color,value: String,badge: String,
                                       detail: String,tab: MonitorTab,@ViewBuilder content: () -> Content) -> some View {
        Button { openDetail(tab) } label: {
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:5) {
                    Image(systemName:symbol).foregroundStyle(color)
                    Text(title)
                    Spacer(minLength:0)
                    Text(badge).font(.system(size:9,weight:.medium)).foregroundStyle(palette.secondaryInk)
                }.font(.system(size:10,weight:.medium)).foregroundStyle(palette.secondaryInk).lineLimit(1)
                Text(value).font(.system(size:compact ? 23 : 26,weight:.medium,design:.rounded))
                    .monospacedDigit().foregroundStyle(palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                content()
                Text(detail).font(.system(size:9)).foregroundStyle(palette.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).frame(height:compact ? 116 : 134)
                .glassCard(radius:12,tint:color).contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).help("查看\(title)详情")
    }

    private var processList: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Label("高占用进程",systemImage:"list.bullet.rectangle").font(.system(size:11,weight:.medium))
                Spacer()
                Button("CPU") { model.processSort = "cpu" }
                    .foregroundStyle(model.processSort == "cpu" ? palette.brand : palette.secondaryInk)
                Button("内存") { model.processSort = "memory" }
                    .foregroundStyle(model.processSort == "memory" ? palette.brand : palette.secondaryInk)
                Button { openDetail(.processes) } label: { Image(systemName:"arrow.up.right") }
                    .help("查看全部进程").accessibilityLabel("查看全部进程")
            }.font(.system(size:10)).buttonStyle(.plain).padding(.horizontal,12).padding(.vertical,10)
            Divider().opacity(0.5)
            ForEach(Array(model.topProcesses.prefix(compact ? 5 : 8).enumerated()),id:\.element.id) { index,p in
                HStack(spacing:8) {
                    if model.pinnedProcesses.contains(p.id) { Image(systemName:"pin.fill").foregroundStyle(palette.brand).font(.system(size:8)) }
                    Text(p.name).font(.system(size:11)).lineLimit(1).help("\(p.name) · PID \(p.id)")
                        .frame(maxWidth:.infinity,alignment:.leading)
                    if !compact {
                        Text(verbatim:String(p.id)).font(.system(size:10,design:.monospaced)).foregroundStyle(palette.secondaryInk).frame(width:60,alignment:.trailing)
                        Meter(percent:p.cpu ?? 0,color:(p.cpu ?? 0) >= 100 ? palette.warning : palette.brand,height:3).frame(width:65)
                    }
                    Text(Readout.percent(p.cpu)).foregroundStyle((p.cpu ?? 0) >= 100 ? palette.warning : palette.secondaryInk)
                        .frame(width:45,alignment:.trailing)
                    Text(Readout.bytes(p.memory,compact:compact)).foregroundStyle(palette.secondaryInk).frame(width:compact ? 46 : 82,alignment:.trailing)
                }.font(.system(size:10)).monospacedDigit().padding(.horizontal,12).frame(height:compact ? 23 : 27)
                    .background(index.isMultiple(of:2) ? palette.ink.opacity(0.025) : .clear)
                    .contextMenu {
                        Button(model.pinnedProcesses.contains(p.id) ? "取消置顶" : "置顶进程") { model.togglePin(p.id) }
                        Button("复制 PID \(p.id)") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(p.id),forType:.string) }
                        Button("打开活动监视器") { model.openActivityMonitor() }
                    }
            }
            if model.snapshot.processes.isEmpty {
                Text(model.loading ? "正在读取进程…" : "暂无可读取进程").font(.system(size:11)).foregroundStyle(palette.secondaryInk).padding(16)
            }
        }.padding(.bottom,6).glassCard(radius:12)
    }
}

struct CoreActivityBars: View {
    let values: [Double]
    let color: Color
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
            let count = CGFloat(max(1,values.count))
            let barWidth = min(6,max(1,(geometry.size.width-(count-1)*3)/count))
            HStack(alignment:.bottom,spacing:3) {
                ForEach(Array(values.enumerated()),id:\.offset) { index,value in
                    ZStack(alignment:.bottom) {
                        Capsule().fill(palette.ink.opacity(0.045))
                        Capsule().fill(color)
                            .frame(height:max(1.5,geometry.size.height * min(1,max(0,value / 100))))
                    }.frame(width:barWidth)
                        .frame(maxWidth:.infinity)
                        .help("核心 \(index+1) · \(Readout.percent(value))")
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
        }.frame(height:28).accessibilityElement(children:.ignore)
            .accessibilityLabel(values.isEmpty ? "等待核心读数" : "\(values.count) 个核心的实际负载")
    }
}

struct ToolsView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            WorkspaceHeading(title:"日常工具",detail:"按需操作，不在后台自动更改系统")
            PanelSection(title:"屏幕与电源",symbol:"display",color:palette.brand) {
                HStack {
                    VStack(alignment:.leading,spacing:5) {
                        Text("保持屏幕唤醒").font(.system(size:13,weight:.medium))
                        Text(model.awakeUntil.map { "持续至 \($0.formatted(date:.omitted,time:.shortened))，退出 Piko 后自动恢复" } ?? "开启后持续一小时，不更改系统电源设置")
                            .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
                    }
                    Spacer()
                    Toggle("保持屏幕唤醒",isOn:Binding(get:{ model.awakeUntil != nil },set:{ _ in model.toggleAwake() })).labelsHidden().toggleStyle(.switch)
                }
            }
            PanelSection(title:"系统工具",symbol:"wrench.and.screwdriver",color:palette.supporting) {
                tool("活动监视器",detail:"检查进程、能耗与内存压力",action:model.openActivityMonitor)
                Divider()
                tool("储存空间",detail:"查看 macOS 的储存分类与清理建议",action:model.openStorageSettings)
                Divider()
                tool("登录项与后台项目",detail:"在系统设置中管理启动和后台权限") { SMAppService.openSystemSettingsLoginItems() }
                Divider()
                tool("磁盘工具",detail:"检查磁盘状态与急救") { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Utilities/Disk Utility.app")) }
            }
            PanelSection(title:"诊断",symbol:"doc.text.magnifyingglass",color:palette.transfer) {
                tool("导出系统快照",detail:"仅在你选择位置后保存 JSON，不上传数据",action:model.exportSnapshot)
            }
        }
    }
    private func tool(_ title: String,detail: String,action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.system(size:12,weight:.medium))
                Text(detail).font(.system(size:11)).foregroundStyle(palette.secondaryInk)
            }
            Spacer()
            Button("打开",action:action).controlSize(.small)
        }.padding(.vertical,4)
    }
}

struct WorkspaceHeading: View {
    let title: String
    let detail: String
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.system(size:21,weight:.semibold))
            Text(detail).font(.system(size:12)).foregroundStyle(palette.secondaryInk)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
