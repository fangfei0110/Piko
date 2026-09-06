import SwiftUI

struct MaintenanceNotice: View {
    @ObservedObject var model: MaintenanceModel
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        if let busy = model.busy {
            HStack {
                ProgressView().controlSize(.small)
                Text("正在\(busy.rawValue)…").font(.system(size:12))
                Spacer()
                if busy != .removal { Button("停止",action:model.cancel).controlSize(.small) }
            }.padding(12).glassCard()
        }
        if let notice = model.notice {
            Text(notice).font(.system(size:12)).foregroundStyle(palette.secondaryInk).textSelection(.enabled)
        }
        if let failure = model.failure {
            Label(failure,systemImage:"exclamationmark.circle")
                .font(.system(size:12)).foregroundStyle(palette.warning).textSelection(.enabled)
        }
    }
}

struct CleanupView: View {
    @ObservedObject var model: MaintenanceModel
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                WorkspaceHeading(title:"清理，从看清楚开始",detail:"缓存、日志和旧安装包。默认不勾选，始终由你决定。")
                Button(model.scannedCleanup ? "重新扫描" : "扫描可清理项目",action:model.scanCleanup)
                    .buttonStyle(.borderedProminent).disabled(model.busy != nil)
            }
            MaintenanceNotice(model:model)
            if model.scannedCleanup {
                HStack(spacing:22) {
                    Label("\(model.candidates.count) 个项目",systemImage:"doc.on.doc")
                    Text("已选 \(Readout.bytes(model.selectedBytes))").fontWeight(.semibold)
                    Spacer()
                    Button("取消选择") { model.selected = [] }.disabled(model.selected.isEmpty || model.busy != nil)
                    Button("移入废纸篓…",role:.destructive,action:model.prepareTrash)
                        .disabled(model.selectedItems.isEmpty || model.busy != nil)
                }.font(.system(size:12)).padding(14).glassCard()
                if model.candidates.isEmpty {
                    emptyPanel(title:"没有发现可检查的项目",detail:"这不代表磁盘没有占用。可以前往“分析”查看文件夹和大文件。",symbol:"checkmark.seal")
                }
                ForEach(["应用缓存","日志","旧安装包"],id:\.self) { category in
                    let items = model.candidates.filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment:.leading,spacing:0) {
                            HStack {
                                Text(category).font(.system(size:12,weight:.semibold))
                                Spacer()
                                Text(Readout.bytes(items.reduce(UInt64(0)) { $0 + $1.bytes })).font(.system(size:11)).foregroundStyle(palette.secondaryInk)
                            }.padding(14)
                            Divider()
                            ForEach(items) { item in
                                HStack(spacing:10) {
                                    Toggle("选择 \(item.url.lastPathComponent)",isOn:Binding(get:{ model.selected.contains(item.id) },set:{ selected in
                                        if selected { model.selected.insert(item.id) } else { model.selected.remove(item.id) }
                                    })).labelsHidden().toggleStyle(.checkbox).disabled(item.blockedReason != nil || model.busy != nil)
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(item.url.lastPathComponent).font(.system(size:12,weight:.medium)).lineLimit(1)
                                        Text(displayPath(item.url)).font(.system(size:10)).foregroundStyle(palette.secondaryInk).lineLimit(1).help(item.url.path)
                                        Text(item.blockedReason ?? "\(item.footprint.files) 个文件 · 最近修改 \(item.footprint.latest.formatted(date:.abbreviated,time:.omitted))")
                                            .font(.system(size:10)).foregroundStyle(item.blockedReason == nil ? palette.secondaryInk : palette.warning)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    Text("\(item.footprint.limited ? "≥ " : "")\(Readout.bytes(item.bytes))").font(.system(size:12)).monospacedDigit()
                                    Button { model.reveal(item.url) } label: { Image(systemName:"folder") }
                                        .buttonStyle(.plain).help("在 Finder 中查看").accessibilityLabel("在 Finder 查看 \(item.url.lastPathComponent)")
                                }.padding(.horizontal,14).padding(.vertical,10)
                                if item.id != items.last?.id { Divider().padding(.leading,40) }
                            }
                        }.glassCard()
                    }
                }
            } else if model.busy == nil {
                emptyPanel(title:"先扫描，不会修改任何文件",detail:"检查应用缓存与日志中的七天前内容，以及三十天前的安装包。系统、云盘、共享数据和游戏目录受到保护。",symbol:"externaldrive.badge.magnifyingglass")
            }
            Text("移入废纸篓不是永久删除，也不会立即释放空间。近期变化、正在占用或检查不完整的项目会被跳过。")
                .font(.system(size:11)).foregroundStyle(palette.secondaryInk)
        }
        .sheet(item:$model.pendingTrash) { request in
            TrashConfirmation(request:request,confirm:{ model.confirmTrash(request) },cancel:{ model.pendingTrash = nil })
                .environment(\.monitorPalette,palette)
        }
    }

    private func emptyPanel(title: String,detail: String,symbol: String) -> some View {
        HStack(alignment:.top,spacing:18) {
            Image(systemName:symbol).font(.system(size:28,weight:.light)).foregroundStyle(palette.brand)
            VStack(alignment:.leading,spacing:8) {
                Text(title).font(.system(size:16,weight:.semibold))
                Text(detail).font(.system(size:12)).foregroundStyle(palette.secondaryInk).fixedSize(horizontal:false,vertical:true)
            }
            Spacer()
        }.padding(24).frame(maxWidth:.infinity,minHeight:160,alignment:.leading).glassCard()
    }
    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of:model.home.path+"/",with:"~/")
    }
}

struct TrashConfirmation: View {
    let request: TrashRequest
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("确认移入废纸篓",systemImage:"trash").font(.system(size:20,weight:.semibold))
            Text("\(request.items.count) 项 · \(Readout.bytes(request.bytes))。执行前会重新检查路径、修改情况和进程占用。")
                .font(.system(size:12)).foregroundStyle(palette.secondaryInk)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(request.items) { item in
                        VStack(alignment:.leading,spacing:4) {
                            HStack { Text(item.url.lastPathComponent).fontWeight(.medium); Spacer(); Text(Readout.bytes(item.bytes)) }
                            Text(item.url.path).font(.system(size:10,design:.monospaced)).foregroundStyle(palette.secondaryInk).textSelection(.enabled)
                        }.font(.system(size:12))
                    }
                }
            }.frame(maxHeight:230)
            Text("你可以从废纸篓恢复。只有清空废纸篓后才会释放空间，Piko 不会自动清空。")
                .font(.system(size:11)).foregroundStyle(palette.warning)
            HStack {
                Spacer()
                Button("取消",action:cancel).keyboardShortcut(.cancelAction)
                Button("确认移入废纸篓",role:.destructive,action:confirm)
            }
        }.padding(24).frame(width:520).foregroundStyle(palette.ink).background(palette.card)
    }
}

struct ApplicationsView: View {
    @ObservedObject var model: MaintenanceModel
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                WorkspaceHeading(title:"软件占用",detail:"应用本体与可明确归属的关联数据分开显示")
                Button(model.scannedApps ? "重新统计" : "统计已安装应用",action:model.scanApps)
                    .buttonStyle(.borderedProminent).disabled(model.busy != nil)
            }
            MaintenanceNotice(model:model)
            HStack {
                Image(systemName:"magnifyingglass").foregroundStyle(palette.secondaryInk)
                TextField("搜索应用名称",text:$model.appSearch).textFieldStyle(.plain)
                Spacer()
                Text("\(model.filteredApps.count) 个应用").font(.system(size:11)).foregroundStyle(palette.secondaryInk)
            }.font(.system(size:12)).padding(12).glassCard()
            if !model.scannedApps && model.busy == nil {
                PanelSection(title:"先看应用，再看文件",symbol:"square.grid.2x2",color:palette.supporting) {
                    Text("统计 /Applications 和个人 Applications 目录，展开应用可查看版本、路径与关联文件。本页仅查看，不会卸载或修改应用。")
                        .font(.system(size:12)).foregroundStyle(palette.secondaryInk)
                }
            }
            LazyVStack(spacing:8) {
                ForEach(model.filteredApps) { app in
                    VStack(alignment:.leading,spacing:0) {
                        Button { model.expandedApp = model.expandedApp == app.id ? nil : app.id } label: {
                            HStack(spacing:12) {
                                Image(nsImage:NSWorkspace.shared.icon(forFile:app.url.path)).resizable().frame(width:30,height:30)
                                VStack(alignment:.leading,spacing:4) {
                                    HStack(spacing:7) {
                                        Text(app.name).font(.system(size:13,weight:.semibold))
                                        if model.runningBundleIDs.contains(app.bundleID) {
                                            Text("运行中").font(.system(size:9,weight:.medium)).foregroundStyle(palette.positive)
                                        }
                                    }
                                    Text("\(app.version) · \(app.bundleID)").font(.system(size:10)).foregroundStyle(palette.secondaryInk).lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment:.trailing,spacing:4) {
                                    Text("\(app.footprint.limited || app.footprint.skipped > 0 ? "≥ " : "")\(Readout.bytes(app.bytes))").font(.system(size:13,weight:.medium)).monospacedDigit()
                                    Text("已识别关联 \(Readout.bytes(app.relatedBytes))").font(.system(size:10)).foregroundStyle(palette.secondaryInk)
                                }
                                Image(systemName:model.expandedApp == app.id ? "chevron.down" : "chevron.right").font(.system(size:10)).foregroundStyle(palette.secondaryInk)
                            }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if model.expandedApp == app.id {
                            Divider()
                            VStack(alignment:.leading,spacing:10) {
                                relatedRow("应用",url:app.url,bytes:app.bytes)
                                ForEach(app.related) { item in relatedRow(relatedTitle(item.url),url:item.url,bytes:item.bytes) }
                                if app.related.isEmpty {
                                    Text("没有发现可明确归属的关联目录；这不代表不存在其他共享数据。").font(.system(size:11)).foregroundStyle(palette.secondaryInk)
                                }
                                if app.footprint.skipped > 0 || app.footprint.limited {
                                    Text("部分内容未能统计，显示的大小是不完整结果。").font(.system(size:11)).foregroundStyle(palette.warning)
                                }
                            }.padding(14)
                        }
                    }.glassCard()
                }
            }
            if model.scannedApps && model.filteredApps.isEmpty {
                Text(model.appSearch.isEmpty ? "没有发现可读取的应用。" : "没有匹配的应用。").foregroundStyle(palette.secondaryInk).font(.system(size:12)).padding()
            }
        }
    }
    private func relatedRow(_ title: String,url: URL,bytes: UInt64) -> some View {
        HStack(spacing:12) {
            Text(title).font(.system(size:11,weight:.medium)).frame(width:100,alignment:.leading)
            Text(url.path).font(.system(size:10,design:.monospaced)).foregroundStyle(palette.secondaryInk).textSelection(.enabled).lineLimit(2)
            Spacer(minLength:0)
            Text(Readout.bytes(bytes)).font(.system(size:11)).monospacedDigit()
            Button { model.reveal(url) } label: { Image(systemName:"folder") }.buttonStyle(.plain).help("在 Finder 中查看").accessibilityLabel("在 Finder 查看\(title)")
        }
    }
    private func relatedTitle(_ url: URL) -> String {
        switch url.deletingLastPathComponent().lastPathComponent {
        case "Caches": "缓存"; case "Logs": "日志"; case "Application Support": "应用数据"
        case "Preferences": "偏好设置"; default: "关联文件"
        }
    }
}

struct DiskAnalysisView: View {
    @ObservedObject var model: MaintenanceModel
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                WorkspaceHeading(title:"空间去了哪里",detail:"按实际占用统计，点击方块进入目录。云盘和不可读取内容会跳过。")
                Button("选择目录…",action:model.chooseFolder).disabled(model.busy != nil)
                Button("分析主目录") { model.analyze(model.home) }.buttonStyle(.borderedProminent).disabled(model.busy != nil)
            }
            MaintenanceNotice(model:model)
            if let report = model.folder {
                HStack {
                    Button { model.analyze(report.root.deletingLastPathComponent()) } label: { Image(systemName:"arrow.up") }
                        .disabled(report.root.path == "/" || model.busy != nil).help("上一级")
                    Text(report.root.path).font(.system(size:11,design:.monospaced)).textSelection(.enabled).lineLimit(1)
                    Spacer()
                    Text("已统计 \(Readout.bytes(report.bytes))").font(.system(size:12,weight:.medium))
                    Button { model.analyze(report.root) } label: { Image(systemName:"arrow.clockwise") }.disabled(model.busy != nil).help("重新分析")
                }.buttonStyle(.plain)
                if report.skipped > 0 {
                    Label("\(report.skipped) 项内容被跳过或达到扫描上限，以下不是完整磁盘总量。",systemImage:"info.circle")
                        .font(.system(size:11)).foregroundStyle(palette.warning)
                }
                let largest = Array(report.items.filter { $0.bytes > 0 }.prefix(12))
                if !largest.isEmpty {
                    DiskTreemap(items:largest,open:open).frame(height:240)
                    Text("方块面积对应前 \(largest.count) 项占用；完整列表在下方。").font(.system(size:10)).foregroundStyle(palette.secondaryInk)
                }
                VStack(spacing:0) {
                    ForEach(report.items) { item in
                        Button { open(item) } label: {
                            HStack(spacing:10) {
                                Image(systemName:item.stamp.isDirectory ? "folder" : "doc").foregroundStyle(palette.supporting)
                                Text(item.url.lastPathComponent).font(.system(size:12)).lineLimit(1)
                                Spacer()
                                if item.footprint.skipped > 0 || item.footprint.limited {
                                    Text("部分统计").font(.system(size:10)).foregroundStyle(palette.warning)
                                }
                                Text(Readout.bytes(item.bytes)).font(.system(size:12)).monospacedDigit().frame(width:85,alignment:.trailing)
                                Image(systemName:item.stamp.isDirectory ? "chevron.right" : "arrow.up.right").font(.system(size:9)).foregroundStyle(palette.secondaryInk)
                            }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.busy != nil)
                            .contextMenu { Button("在 Finder 中查看") { model.reveal(item.url) } }
                        if item.id != report.items.last?.id { Divider() }
                    }
                }.glassCard()
                if report.items.isEmpty { Text("目录为空或没有可读取项目。").font(.system(size:12)).foregroundStyle(palette.secondaryInk) }
            } else if model.busy == nil {
                PanelSection(title:"从熟悉的目录开始",symbol:"chart.pie",color:palette.supporting) {
                    Text("只读取本地文件的元数据，不读取文件内容、不上传数据、不删除文件。选择“下载”“项目”或主目录，查看哪些文件夹占用最大。")
                        .font(.system(size:12)).foregroundStyle(palette.secondaryInk)
                    HStack(spacing:12) {
                        Button("下载目录") { model.analyze(model.home.appendingPathComponent("Downloads")) }
                        Button("应用目录") { model.analyze(URL(fileURLWithPath:"/Applications")) }
                        Button("资源库") { model.analyze(model.home.appendingPathComponent("Library")) }
                    }
                }
            }
        }
    }
    private func open(_ item: ScannedPath) {
        guard model.busy == nil else { return }
        if item.stamp.isDirectory && item.url.pathExtension != "app" { model.analyze(item.url) }
        else { model.reveal(item.url) }
    }
}

struct DiskTreemap: View {
    let items: [ScannedPath]
    let open: (ScannedPath) -> Void
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
            let rects = TreemapLayout.rectangles(weights:items.map { Double($0.bytes) },in:CGRect(origin:.zero,size:geometry.size))
            ZStack(alignment:.topLeading) {
                ForEach(Array(items.enumerated()),id:\.element.id) { index,item in
                    let rect = rects[index].insetBy(dx:2,dy:2)
                    let color = [palette.brand,palette.supporting,palette.transfer,palette.warning][index % 4]
                    Button { open(item) } label: {
                        VStack(alignment:.leading,spacing:5) {
                            if rect.width > 65 && rect.height > 38 {
                                Text(item.url.lastPathComponent).font(.system(size:12,weight:.semibold)).lineLimit(2)
                                if rect.height > 60 { Text(Readout.bytes(item.bytes)).font(.system(size:10)).monospacedDigit() }
                            }
                        }.padding(rect.width > 65 ? 10 : 0)
                            .frame(width:max(0,rect.width),height:max(0,rect.height),alignment:.topLeading)
                            .foregroundStyle(palette.ink).background(color.opacity(0.10 + Double(index % 3)*0.045),in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain).offset(x:rect.minX,y:rect.minY).help("\(item.url.lastPathComponent) · \(Readout.bytes(item.bytes))")
                        .accessibilityLabel("\(item.url.lastPathComponent)，\(Readout.bytes(item.bytes))")
                }
            }
        }
    }
}

enum TreemapLayout {
    static func rectangles(weights: [Double],in bounds: CGRect) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        var result = [CGRect](repeating:.zero,count:weights.count)
        let safe = weights.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        func split(_ range: Range<Int>,_ rect: CGRect) {
            if range.count == 1 { result[range.lowerBound] = rect; return }
            let total = safe[range].reduce(0,+)
            var middle = range.lowerBound + 1, subtotal = safe[range.lowerBound]
            while middle < range.upperBound - 1 && subtotal < total/2 {
                subtotal += safe[middle]; middle += 1
            }
            let share = total > 0 ? subtotal / total : Double(middle-range.lowerBound) / Double(range.count)
            if rect.width >= rect.height {
                let width = rect.width * share
                split(range.lowerBound..<middle,CGRect(x:rect.minX,y:rect.minY,width:width,height:rect.height))
                split(middle..<range.upperBound,CGRect(x:rect.minX+width,y:rect.minY,width:rect.width-width,height:rect.height))
            } else {
                let height = rect.height * share
                split(range.lowerBound..<middle,CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:height))
                split(middle..<range.upperBound,CGRect(x:rect.minX,y:rect.minY+height,width:rect.width,height:rect.height-height))
            }
        }
        split(0..<weights.count,bounds)
        return result
    }
}
