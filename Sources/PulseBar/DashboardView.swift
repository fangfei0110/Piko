import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    var compact = false
    var detach: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var palette: Palette { model.appearance.palette }

    var body: some View {
        VStack(spacing:0) {
            if compact { compactHeader } else { navigation }
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if let message = model.message {
                        HStack(alignment:.top) {
                            Text(message).font(.system(size:12)).textSelection(.enabled)
                            Spacer()
                            Button { model.message = nil } label: { Image(systemName:"xmark") }
                                .buttonStyle(.plain).help("关闭提示")
                        }.padding(10).background(palette.brand.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
                    }
                    if compact {
                        StatusDashboard(model:model,compact:true,openDetail:openDetail,openSection:openSection)
                    } else {
                        desktopContent
                    }
                }.padding(compact ? 12 : 20)
            }
            footer
        }
        .frame(minWidth:compact ? 380 : 760,minHeight:compact ? 360 : 520)
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .background {
            ZStack {
                if !reduceTransparency { FrostedBackdrop() }
                palette.shell.opacity(reduceTransparency ? 1 : 0.97)
            }.ignoresSafeArea()
        }
        .foregroundStyle(palette.ink).tint(palette.brand)
        .environment(\.monitorPalette,palette)
    }

    private var compactHeader: some View {
        HStack(spacing:9) {
            Image(systemName:"waveform.path.ecg")
                .font(.system(size:15,weight:.medium)).foregroundStyle(palette.brand)
                .frame(width:30,height:30)
                .background(palette.brand.opacity(0.08),in:RoundedRectangle(cornerRadius:9))
                .accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3) {
                Text("Piko").font(.system(size:13,weight:.semibold))
                Text("\(model.hardware.chip) · \(Readout.bytes(model.hardware.memory))")
                    .font(.system(size:10)).foregroundStyle(palette.secondaryInk)
            }
            Spacer(minLength:8)
            VStack(alignment:.trailing,spacing:4) {
                HStack(spacing:4) {
                    Circle().fill(model.paused || model.loading ? palette.secondaryInk : palette.positive).frame(width:4,height:4)
                    Text(model.paused ? "已暂停" : model.loading ? "读取中" : "实时")
                }.font(.system(size:10,weight:.medium)).foregroundStyle(palette.secondaryInk)
                Text(model.stateTitle).font(.system(size:10,weight:.medium))
                    .foregroundStyle(model.paused || model.loading ? palette.secondaryInk : model.concerns.isEmpty ? palette.secondaryInk : palette.warning)
            }
            appearanceButton
        }
        .lineLimit(1).padding(.horizontal,14).padding(.vertical,12)
        .background(palette.card.opacity(palette.isDark ? 0.4 : 0.65))
        .overlay(alignment:.bottom) { Rectangle().fill(palette.line).frame(height:0.5) }
        .help("已运行 \(Readout.uptime(model.snapshot.uptime))")
    }

    private var navigation: some View {
        HStack(spacing:10) {
            Image(systemName:"waveform.path.ecg").font(.system(size:17,weight:.semibold)).foregroundStyle(palette.brand)
                .accessibilityLabel("Piko")
            Spacer(minLength:8)
            HStack(spacing:3) {
                ForEach(WorkspaceSection.allCases.filter { $0 != .settings }) { section in
                    Button {
                        model.section = section
                        model.tab = .overview
                    } label: {
                        Text(section.title).font(.system(size:12,weight:model.section == section ? .semibold : .medium))
                            .padding(.horizontal,18).frame(height:30)
                            .foregroundStyle(model.section == section ? palette.ink : palette.secondaryInk)
                            .background(model.section == section ? palette.card : .clear,in:Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }.padding(4).background(palette.ink.opacity(0.045),in:Capsule())
            Spacer(minLength:8)
            appearanceButton
            Button { openSection(.settings) } label: { Image(systemName:"gearshape") }
                .buttonStyle(.plain).frame(width:28,height:28).help("设置").accessibilityLabel("设置")
        }.padding(.horizontal,22).padding(.top,12).padding(.bottom,4)
    }

    private var appearanceButton: some View {
        Button { model.appearance = model.appearance.next } label: {
            Image(systemName:model.appearance.symbol)
                .font(.system(size:12,weight:.medium))
                .foregroundStyle(palette.brand)
                .frame(width:28,height:28)
                .background(palette.brand.opacity(0.07),in:Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("当前\(model.appearance.title)，点击切换为\(model.appearance.next.title)")
        .accessibilityLabel("切换配色")
        .accessibilityValue(model.appearance.title)
    }

    @ViewBuilder private var desktopContent: some View {
        switch model.section {
        case .status:
            if model.tab == .overview {
                StatusDashboard(model:model,compact:false,openDetail:openDetail,openSection:openSection)
            } else {
                Button { model.tab = .overview } label: { Label("返回状态",systemImage:"chevron.left") }
                    .buttonStyle(.plain).font(.system(size:12)).foregroundStyle(palette.secondaryInk)
                MetricDetailsView(model:model)
            }
        case .cleanup: CleanupView(model:model.maintenance)
        case .apps: ApplicationsView(model:model.maintenance)
        case .analysis: DiskAnalysisView(model:model.maintenance)
        case .tools: ToolsView(model:model)
        case .settings: MetricDetailsView(model:model)
        }
    }

    private var footer: some View {
        HStack(spacing:12) {
            Circle().fill(model.paused ? palette.secondaryInk : palette.positive).frame(width:5,height:5)
            Text(model.paused ? "已暂停" : "\(Int(model.interval)) 秒更新").font(.system(size:10)).monospacedDigit()
            Spacer()
            if compact {
                Button { openSection(.cleanup) } label: { Label("清理",systemImage:"sparkles") }
                Button { openSection(.analysis) } label: { Label("分析",systemImage:"chart.pie") }
                Button { openSection(.settings) } label: { Image(systemName:"gearshape") }.accessibilityLabel("设置")
            } else {
                Button { model.exportSnapshot() } label: { Label("导出快照",systemImage:"square.and.arrow.up") }
            }
            Button { model.togglePause() } label: { Image(systemName:model.paused ? "play" : "pause") }
                .help("暂停或恢复监控").accessibilityLabel(model.paused ? "继续监控" : "暂停监控")
            Button(action:detach) { Image(systemName:compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }
                .help(compact ? "打开主窗口" : "收回菜单栏").accessibilityLabel(compact ? "打开主窗口" : "收回菜单栏")
        }.font(.system(size:11)).buttonStyle(.plain).foregroundStyle(palette.secondaryInk)
            .padding(.horizontal,compact ? 14 : 22).frame(height:36)
            .background(palette.card.opacity(0.5))
    }

    private func openDetail(_ tab: MonitorTab) {
        model.section = .status
        model.tab = tab
        if compact { detach() }
    }
    private func openSection(_ section: WorkspaceSection) {
        model.section = section
        model.tab = section == .settings ? .settings : .overview
        if compact { detach() }
    }
}
