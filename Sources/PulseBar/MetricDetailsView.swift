import SwiftUI
import ServiceManagement

struct MetricDetailsView: View {
    @ObservedObject var model: MonitorModel
    var compact = false
    @Environment(\.monitorPalette) private var palette
    private var accent: Color { palette.brand }
    private var s: Snapshot { model.snapshot }

    var body: some View {
        Group {
            switch model.tab {
            case .cpu: processors
            case .memory: memory
            case .disks: storage
            case .network: network
            case .processes: processes
            case .system: system
            case .settings: settings
            case .overview: EmptyView()
            }
        }
    }

    private var processors: some View {
        VStack(spacing:14) {
            sectionHeading("处理器活动",detail:"CPU 按全部核心归一化至 100%")
            rangePicker
            PanelSection(title:"CPU",subtitle:"当前 \(Readout.percent(s.cpu))") {
                MetricChart(points:model.visibleHistory,key:\.cpu,color:accent,height:130)
                HStack {
                    ForEach(Array(s.loads.enumerated()),id:\.offset) { i,load in
                        VStack(alignment:.leading,spacing:4) {
                            Text(["1 分钟负载","5 分钟负载","15 分钟负载"][i]).font(.system(size:10)).foregroundStyle(palette.secondaryInk)
                            Text(String(format:"%.2f",load)).font(.system(size:15,weight:.medium)).monospacedDigit()
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
            }
            PanelSection(title:"核心活动",subtitle:"\(s.cores.count) 个逻辑核心") {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:104),spacing:12)],spacing:14) {
                    ForEach(Array(s.cores.enumerated()),id:\.offset) { index,value in
                        VStack(alignment:.leading,spacing:7) {
                            HStack { Text("核心 \(index+1)").foregroundStyle(palette.secondaryInk); Spacer(); Text(Readout.percent(value)).monospacedDigit() }.font(.system(size:10))
                            Meter(percent:value,color:value >= 90 ? palette.warning : accent)
                        }
                    }
                }
            }
            PanelSection(title:"GPU",subtitle:s.gpu == nil ? "当前不可用" : "当前 \(Readout.percent(s.gpu))") {
                if s.gpu != nil { MetricChart(points:model.visibleHistory,key:\.gpu,color:palette.transfer,height:110) }
                else { unavailable("系统没有提供 GPU 利用率",symbol:"cpu") }
            }
        }
    }

    private var memory: some View {
        VStack(spacing:14) {
            sectionHeading("内存与交换",detail:"关注内存压力，比单看已用比例更有意义")
            if let m = s.memory {
                PanelSection(title:"物理内存",subtitle:"\(Readout.bytes(m.total))") {
                    HStack(alignment:.firstTextBaseline) {
                        Text(Readout.bytes(m.used)).font(.system(size:28,weight:.medium,design:.rounded)).monospacedDigit()
                        Text("已用").font(.system(size:12)).foregroundStyle(palette.secondaryInk)
                        Spacer()
                        Label("压力\(m.pressureName)",systemImage:m.pressure == 1 ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                            .font(.system(size:12,weight:.medium)).foregroundStyle(m.pressure == 1 ? palette.positive : palette.warning)
                    }
                    GeometryReader { geo in
                        HStack(spacing:0) {
                            Rectangle().fill(accent).frame(width:geo.size.width*Double(m.app)/Double(m.total))
                            Rectangle().fill(palette.warning).frame(width:geo.size.width*Double(m.wired)/Double(m.total))
                            Rectangle().fill(palette.supporting).frame(width:geo.size.width*Double(m.compressed)/Double(m.total))
                            Rectangle().fill(Color.primary.opacity(0.08))
                        }.clipShape(RoundedRectangle(cornerRadius:5))
                    }.frame(height:16)
                    HStack(spacing:22) {
                        dotLegend("应用",color:accent); dotLegend("联动",color:palette.warning); dotLegend("压缩",color:palette.supporting)
                        Spacer()
                    }
                    Divider()
                    DetailRow(label:"应用内存",value:Readout.bytes(m.app))
                    DetailRow(label:"联动内存",value:Readout.bytes(m.wired))
                    DetailRow(label:"压缩内存",value:Readout.bytes(m.compressed))
                    DetailRow(label:"文件缓存",value:Readout.bytes(m.cached))
                    DetailRow(label:"交换使用",value:"\(Readout.bytes(m.swapUsed)) / \(Readout.bytes(m.swapTotal))")
                }
                rangePicker
                PanelSection(title:"内存使用趋势",subtitle:"当前 \(Readout.percent(m.percent))") {
                    MetricChart(points:model.visibleHistory,key:\.memory,color:palette.supporting,height:130)
                }
                Text("文件缓存可以被系统回收，不算入应用、联动和压缩内存之和。交换使用量是当前占用，不代表正在大量交换。")
                    .font(.system(size:11)).foregroundStyle(palette.secondaryInk).fixedSize(horizontal:false,vertical:true)
            } else { unavailable("内存数据暂时无法读取",symbol:"memorychip") }
        }
    }

    private var storage: some View {
        VStack(spacing:14) {
            sectionHeading("磁盘空间",detail:"显示本地数据卷和已挂载的外接卷")
            ForEach(s.disks) { disk in
                PanelSection(title:disk.name,subtitle:disk.internalDisk ? "内置磁盘" : "外接磁盘") {
                    HStack(alignment:.firstTextBaseline) {
                        Text("\(Readout.bytes(disk.available)) 可用").font(.system(size:24,weight:.medium,design:.rounded)).monospacedDigit()
                        Spacer(); Text("已用 \(Readout.percent(disk.percent))").font(.system(size:12)).foregroundStyle(palette.secondaryInk)
                    }
                    Meter(percent:disk.percent,color:disk.percent >= 90 ? palette.warning : accent,height:5)
                    DetailRow(label:"已使用",value:Readout.bytes(disk.used))
                    DetailRow(label:"总容量",value:Readout.bytes(disk.total))
                    HStack {
                        Text(disk.id).font(.system(size:10,design:.monospaced)).foregroundStyle(palette.secondaryInk).lineLimit(1).textSelection(.enabled)
                        Spacer()
                        Button("在 Finder 打开") { NSWorkspace.shared.open(URL(fileURLWithPath:disk.id)) }.font(.system(size:11))
                    }
                }
            }
            PanelSection(title:"磁盘读写",subtitle:"所有可读取的物理设备") {
                HStack { rateLabel("读取 · 实线",value:s.diskRead,symbol:"arrow.down",color:accent); Spacer(); rateLabel("写入 · 虚线",value:s.diskWrite,symbol:"arrow.up",color:palette.supporting) }
                if s.diskRead != nil {
                    MetricChart(points:model.visibleHistory,key:\.diskRead,color:accent,secondKey:\.diskWrite,percent:false,height:95)
                } else { Text("系统暂未提供设备读写速率").font(.system(size:11)).foregroundStyle(palette.secondaryInk) }
            }
            HStack(alignment:.top) {
                Text("可用空间为当前空闲容量，不包含可清除缓存；同一 APFS 容器中的卷共享空间。")
                    .font(.system(size:11)).foregroundStyle(palette.secondaryInk).fixedSize(horizontal:false,vertical:true)
                Spacer()
                Button("储存空间设置",action:model.openStorageSettings).font(.system(size:11))
            }
        }
    }

    private var network: some View {
        VStack(spacing:14) {
            sectionHeading("网络活动",detail:"主接口单独计量，避免与 VPN 隧道重复相加")
            rangePicker
            PanelSection(title:"主接口",subtitle:s.primaryNetwork?.id ?? "未检测到") {
                HStack { rateLabel("下载 · 实线",value:s.primaryNetwork?.download,symbol:"arrow.down",color:palette.transfer); Spacer(); rateLabel("上传 · 虚线",value:s.primaryNetwork?.upload,symbol:"arrow.up",color:palette.supporting) }
                MetricChart(points:model.visibleHistory,key:\.download,color:palette.transfer,secondKey:\.upload,percent:false,height:130)
            }
            PanelSection(title:"网络接口",subtitle:"\(s.networks.count) 个已启用") {
                ForEach(s.networks) { n in
                    VStack(spacing:8) {
                        HStack {
                            Image(systemName:n.id.hasPrefix("utun") ? "lock.shield" : "network").foregroundStyle(n.isPrimary ? accent : .secondary).frame(width:20)
                            Text(n.id).font(.system(size:12,weight:.semibold,design:.monospaced))
                            Text(n.isPrimary ? "主接口" : n.label).font(.system(size:10)).foregroundStyle(palette.secondaryInk)
                            Spacer()
                            Text(n.address.isEmpty ? "无 IPv4 地址" : n.address).font(.system(size:11,design:.monospaced)).foregroundStyle(palette.secondaryInk).textSelection(.enabled)
                        }
                        HStack {
                            Text("↓ \(Readout.rate(n.download))").foregroundStyle(palette.transfer)
                            Text("↑ \(Readout.rate(n.upload))").foregroundStyle(palette.supporting)
                            Spacer()
                            Text("累计 ↓ \(Readout.bytes(n.received)) · ↑ \(Readout.bytes(n.sent))").foregroundStyle(palette.secondaryInk)
                        }.font(.system(size:10)).monospacedDigit()
                    }
                    if n.id != s.networks.last?.id { Divider() }
                }
                if s.networks.isEmpty { unavailable("没有已启用的网络接口",symbol:"network.slash") }
            }
            Text("累计值来自接口计数器，接口重建或重启后可能归零；速率按各接口独立计算。")
                .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
        }
    }

    private var processes: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionHeading("进程活动",detail:"\(s.processes.count) 个可读取进程 · CPU 100% 代表占满一个核心")
            HStack(spacing:12) {
                HStack {
                    Image(systemName:"magnifyingglass").foregroundStyle(palette.secondaryInk)
                    TextField("搜索进程名称或 PID",text:$model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(palette.secondaryInk) }.buttonStyle(.plain) }
                }.font(.system(size:12)).padding(9).background(palette.surface,in:RoundedRectangle(cornerRadius:8))
                Picker("排序",selection:$model.processSort) { Text("按 CPU").tag("cpu"); Text("按内存").tag("memory") }.pickerStyle(.segmented).labelsHidden().frame(width:170)
            }
            VStack(spacing:0) {
                processHeader
                LazyVStack(spacing:0) {
                    ForEach(Array(model.filteredProcesses.prefix(300).enumerated()),id:\.element.id) { index,p in
                        HStack(spacing:10) {
                            if !compact {
                                Text("\(index+1)").foregroundStyle(palette.secondaryInk).frame(width:22,alignment:.trailing)
                                Image(systemName:p.name.contains("Helper") ? "square.stack.3d.up" : "app.dashed").foregroundStyle(palette.secondaryInk).frame(width:18)
                            }
                            VStack(alignment:.leading,spacing:3) {
                                Text(p.name).font(.system(size:12,weight:.medium)).lineLimit(1).help(p.name)
                                Text(verbatim:"PID \(p.id)").font(.system(size:9,design:.monospaced)).foregroundStyle(palette.secondaryInk)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Text(Readout.percent(p.cpu)).foregroundStyle((p.cpu ?? 0) >= 100 ? palette.warning : palette.ink).frame(width:62,alignment:.trailing)
                            Text(Readout.bytes(p.memory)).frame(width:90,alignment:.trailing)
                            if !compact { Text("\(p.threads)").foregroundStyle(palette.secondaryInk).frame(width:38,alignment:.trailing) }
                        }.font(.system(size:11)).monospacedDigit().padding(.horizontal,12).padding(.vertical,9)
                            .background(index.isMultiple(of:2) ? Color.primary.opacity(0.025) : .clear)
                    }
                }
                if model.filteredProcesses.isEmpty {
                    unavailable(model.search.isEmpty ? "暂无可读取的进程" : "没有匹配的进程",symbol:"magnifyingglass").padding(20)
                }
            }.glassCard().clipShape(RoundedRectangle(cornerRadius:12))
            HStack {
                Text("显示前 \(min(300,model.filteredProcesses.count)) 项。内存优先使用占用足迹，不可读时使用驻留内存。")
                    .font(.system(size:10)).foregroundStyle(palette.secondaryInk)
                Spacer()
                Button("管理进程…",action:model.openActivityMonitor).font(.system(size:11))
            }
        }
    }

    private var processHeader: some View {
        HStack(spacing:10) {
            Text("进程").frame(maxWidth:.infinity,alignment:.leading)
            Text("CPU").frame(width:62,alignment:.trailing)
            Text("内存").frame(width:90,alignment:.trailing)
            if !compact { Text("线程").frame(width:38,alignment:.trailing) }
        }.font(.system(size:10,weight:.medium)).foregroundStyle(palette.secondaryInk).padding(.horizontal,12).padding(.vertical,10)
    }

    private var system: some View {
        VStack(spacing:14) {
            sectionHeading("这台 Mac",detail:model.hardware.host)
            PanelSection(title:"硬件与系统",subtitle:"\(model.hardware.model)") {
                DetailRow(label:"处理器",value:model.hardware.chip)
                DetailRow(label:"逻辑核心",value:"\(model.hardware.cores)")
                DetailRow(label:"物理内存",value:Readout.bytes(model.hardware.memory))
                DetailRow(label:"操作系统",value:model.hardware.os)
                DetailRow(label:"开机时长",value:Readout.uptime(s.uptime))
            }
            PanelSection(title:"电源与散热") {
                DetailRow(label:"供电方式",value:s.power.source)
                if let battery = s.power.batteryPercent {
                    DetailRow(label:"电池电量",value:Readout.percent(battery))
                    DetailRow(label:"正在充电",value:s.power.charging ? "是" : "否")
                    if let remaining = s.power.minutesRemaining { DetailRow(label:"预计续航",value:"\(remaining / 60) 小时 \(remaining % 60) 分钟") }
                } else { DetailRow(label:"电池",value:"未检测到内置电池") }
                DetailRow(label:"低电量模式",value:s.lowPower ? "已开启" : "关闭")
                DetailRow(label:"散热状态",value:s.thermal,color:s.thermal == "正常" ? palette.positive : palette.warning)
                DetailRow(label:"温度读数",value:"暂不可用")
                DetailRow(label:"风扇转速",value:"暂不可用")
            }
            PanelSection(title:"本地监控") {
                DetailRow(label:"数据更新",value:s.date.formatted(date:.omitted,time:.standard))
                DetailRow(label:"历史样本",value:"\(model.history.count) 条")
                DetailRow(label:"历史保留",value:"本次运行，最近 1 小时")
                DetailRow(label:"网络上传",value:"无")
                DetailRow(label:"应用版本",value:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版")
            }
        }
    }

    private var settings: some View {
        VStack(spacing:14) {
            sectionHeading("按你的习惯监控",detail:"设置会自动保存")
            PanelSection(title:"菜单栏显示",subtitle:"按需选择，控制顶部占用宽度") {
                settingToggle("CPU 使用率",isOn:$model.showCPU)
                settingToggle("内存使用率",isOn:$model.showMemory)
                settingToggle("GPU 使用率",isOn:$model.showGPU)
                settingToggle("启动磁盘可用空间",isOn:$model.showDisk)
                settingToggle("网络下载 / 上传速率",isOn:$model.showNetwork)
                if !model.showCPU && !model.showMemory && !model.showGPU && !model.showDisk && !model.showNetwork {
                    Text("菜单栏仅显示 Piko 图标。点击图标仍可查看全部指标。")
                        .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
                }
            }.toggleStyle(.switch).font(.system(size:12))
            PanelSection(title:"顶栏字体",subtitle:"文字与数字分别设置") {
                fontSettingsRow("文字",style:$model.statusBarTypography.label)
                fontSettingsRow("数字",style:$model.statusBarTypography.value)
                Divider()
                HStack {
                    Text("实时预览").foregroundStyle(palette.secondaryInk)
                    Spacer()
                    HStack(alignment:.firstTextBaseline,spacing:CGFloat(model.statusBarTypography.label.size)/2) {
                        Text("CPU").font(Font(model.statusBarTypography.label.font()))
                        Text(Readout.percent(s.cpu)).font(Font(model.statusBarTypography.value.font(numeric:true)))
                            .foregroundStyle(Color(nsColor:StatusBarTitle.usageLevel(s.cpu).color))
                    }.frame(width:150,alignment:.trailing)
                }.frame(minHeight:24)
                Text("仅影响顶部菜单栏，修改立即生效并自动保存。")
                    .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
                Text("黄色：占用 ≥ 80% 或磁盘剩余 ≤ 15%；红色：占用 ≥ 90% 或磁盘剩余 ≤ 10%。内存压力异常时也会提示，网速不参与预警。")
                    .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
            }.font(.system(size:12))
            PanelSection(title:"采样与外观") {
                settingPicker("更新间隔",selection:$model.interval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                }
                settingPicker("外观",selection:$model.appearance) {
                    ForEach(MonitorAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Text("历史曲线保留最近一小时，只存在内存中，不持续写入硬盘。退出后清空。")
                    .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
            }.font(.system(size:12))
            PanelSection(title:"启动与操作") {
                settingToggle("登录时启动 Piko",isOn:Binding(get:{ model.loginStatus == .enabled || model.loginStatus == .requiresApproval },set:{ model.setLogin($0) }))
                if model.loginStatus == .requiresApproval {
                    Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                }
                Divider()
                DetailRow(label:"点击菜单栏",value:"展开监控面板")
                DetailRow(label:"右键菜单栏",value:"快捷操作与退出")
                DetailRow(label:"独立窗口",value:"面板右下角展开按钮")
            }.font(.system(size:12))
        }
    }

    private var rangePicker: some View {
        HStack {
            Text("历史趋势").font(.system(size:11)).foregroundStyle(palette.secondaryInk)
            Spacer()
            Picker("时间范围",selection:$model.range) { Text("2 分钟").tag(120.0); Text("10 分钟").tag(600.0); Text("1 小时").tag(3600.0) }
                .pickerStyle(.segmented).labelsHidden().frame(width:230)
        }
    }
    private func settingToggle(_ title: String,isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title,isOn:isOn).labelsHidden().toggleStyle(.switch).accessibilityLabel(title)
        }
    }
    private func settingPicker<Selection: Hashable, Options: View>(
        _ title: String,selection: Binding<Selection>,@ViewBuilder options: () -> Options
    ) -> some View {
        HStack(alignment:.center,spacing:16) {
            Text(title)
            Spacer(minLength:16)
            settingsPickerControl(title,selection:selection,options:options)
        }
    }
    private func settingsPickerControl<Selection: Hashable, Options: View>(
        _ title: String,selection: Binding<Selection>,width: CGFloat = 150,@ViewBuilder options: () -> Options
    ) -> some View {
        let picker = Picker(title,selection:selection,content:options)
            .labelsHidden().pickerStyle(.menu).controlSize(.regular)
        return Group {
            if #available(macOS 26.0, *) {
                // Tahoe controls otherwise keep their content-sized bezel inside the frame.
                picker.buttonSizing(.flexible)
            } else {
                picker
            }
        }.frame(width:width,alignment:.trailing)
    }
    private func fontSettingsRow(_ title: String,style: Binding<StatusBarFontStyle>) -> some View {
        HStack(alignment:.center,spacing:16) {
            Text(title)
            Spacer(minLength:16)
            HStack(spacing:12) {
                settingsPickerControl(title+"字体",selection:style.family) {
                    ForEach(StatusBarFontFamily.allCases) { family in
                        Text(family.title).tag(family)
                    }
                }
                settingsPickerControl(title+"字号",selection:style.size,width:80) {
                    ForEach(StatusBarFontStyle.sizes,id:\.self) { size in Text("\(size) pt").tag(size) }
                }
                Toggle("粗体",isOn:style.bold).toggleStyle(.checkbox)
                    .accessibilityLabel(title+"粗体").frame(width:60,alignment:.trailing)
            }
        }
    }
    private func sectionHeading(_ title: String,detail: String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.system(size:22,weight:.bold))
            Text(detail).font(.system(size:11)).foregroundStyle(palette.secondaryInk)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.bottom,2)
    }
    private func rateLabel(_ title: String,value: Double?,symbol: String,color: Color) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Label(title,systemImage:symbol).font(.system(size:10,weight:.medium)).foregroundStyle(color)
            Text(Readout.rate(value)).font(.system(size:23,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private func dotLegend(_ title: String,color: Color) -> some View {
        HStack(spacing:5) { Circle().fill(color).frame(width:6,height:6); Text(title).font(.system(size:10)).foregroundStyle(palette.secondaryInk) }
    }
    private func unavailable(_ text: String,symbol: String) -> some View {
        VStack(spacing:9) { Image(systemName:symbol).font(.system(size:25)); Text(text).font(.system(size:12)) }
            .foregroundStyle(palette.secondaryInk).frame(maxWidth:.infinity).padding(.vertical,20)
    }
}

import ServiceManagement
