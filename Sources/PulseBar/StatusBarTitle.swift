import AppKit

enum StatusBarTitle {
    enum Level: Int {
        case normal, warning, critical

        var color: NSColor {
            switch self {
            case .normal: .labelColor
            case .warning: accent(light:ColorTone(0.53,0.11,90),dark:ColorTone(0.87,0.15,92))
            case .critical: accent(light:ColorTone(0.55,0.19,27),dark:ColorTone(0.78,0.13,25))
            }
        }
    }

    static func usageLevel(_ percent: Double?) -> Level {
        guard let percent, percent.isFinite else { return .normal }
        if percent >= 90 { return .critical }
        return percent >= 80 ? .warning : .normal
    }

    static func memoryLevel(_ memory: MemoryReading?) -> Level {
        guard let memory, memory.total > 0 else { return .normal }
        let usage = usageLevel(memory.percent)
        let pressure: Level = memory.pressure == 4 ? .critical : memory.pressure == 2 ? .warning : .normal
        return usage.rawValue >= pressure.rawValue ? usage : pressure
    }

    static func diskLevel(_ disk: DiskReading?) -> Level {
        guard let disk, disk.total > 0 else { return .normal }
        if disk.percent >= 90 { return .critical }
        return disk.percent >= 85 ? .warning : .normal
    }

    private static func accent(light: ColorTone, dark: ColorTone) -> NSColor {
        NSColor(name:nil) { appearance in
            appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark.native : light.native
        }
    }

    static func make(snapshot: Snapshot, showCPU: Bool, showMemory: Bool, showGPU: Bool,
                     showNetwork: Bool, showDisk: Bool, paused: Bool,
                     typography: StatusBarTypography = StatusBarTypography()) -> NSAttributedString {
        let labelFont = typography.label.font()
        let valueFont = typography.value.font(numeric:true)
        let separatorFont = NSFont.systemFont(ofSize:10,weight:.ultraLight)
        let capHeight = max(labelFont.capHeight,valueFont.capHeight)
        var groups: [NSAttributedString] = []

        func text(_ value: String, font: NSFont? = nil, color: NSColor = .labelColor,
                  baseline: CGFloat = 0) -> NSAttributedString {
            NSAttributedString(string:value,attributes:[.font:font ?? valueFont,
                .foregroundColor:color,.baselineOffset:baseline])
        }
        func metric(_ label: String, value: String, level: Level) -> NSMutableAttributedString {
            let group = NSMutableAttributedString(string:"")
            group.append(text(label,font:labelFont))
            group.append(text("\u{2002}",font:labelFont))
            group.append(text(value,color:level.color))
            return group
        }

        if showCPU { groups.append(metric("CPU",value:Readout.percent(snapshot.cpu),level:usageLevel(snapshot.cpu))) }
        if showMemory { groups.append(metric("MEM",value:Readout.percent(snapshot.memory?.percent),level:memoryLevel(snapshot.memory))) }
        if showGPU { groups.append(metric("GPU",value:Readout.percent(snapshot.gpu),level:usageLevel(snapshot.gpu))) }
        if showDisk {
            let available = snapshot.startupDisk.map { Readout.bytes($0.available,compact:true) } ?? "\u{2014}"
            let group = metric("DISK",value:available,level:diskLevel(snapshot.startupDisk))
            group.append(text("\u{2009}\u{53EF}\u{7528}",font:labelFont))
            groups.append(group)
        }
        if showNetwork {
            let group = NSMutableAttributedString(string:"")
            let down = snapshot.primaryNetwork?.download.map { Readout.bytes($0,compact:true) } ?? "\u{2014}"
            let up = snapshot.primaryNetwork?.upload.map { Readout.bytes($0,compact:true) } ?? "\u{2014}"
            group.append(text("\u{2193}",color:.secondaryLabelColor))
            group.append(text("\u{2009}" + down + "\u{2002}"))
            group.append(text("\u{2191}",color:.secondaryLabelColor))
            group.append(text("\u{2009}" + up))
            groups.append(group)
        }

        guard !groups.isEmpty else { return NSAttributedString(string:"") }
        let title = NSMutableAttributedString(attributedString:text("\u{2002}"))
        for (index,group) in groups.enumerated() {
            if index > 0 {
                title.append(text("\u{2002}\u{2502}\u{2002}",font:separatorFont,
                                  color:.tertiaryLabelColor,baseline:(capHeight-separatorFont.capHeight)/2))
            }
            title.append(group)
        }
        if paused { title.append(text("\u{2002}\u{2161}",color:.secondaryLabelColor)) }
        title.append(text("\u{2009}"))
        return title
    }
}
