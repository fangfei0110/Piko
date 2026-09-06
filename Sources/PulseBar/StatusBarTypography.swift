import AppKit

enum StatusBarFontFamily: String, CaseIterable, Identifiable, Sendable {
    case system, rounded, monospaced
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "系统"; case .rounded: "圆角"; case .monospaced: "等宽" }
    }
}

struct StatusBarFontStyle: Equatable, Sendable {
    static let sizes = Array(9...16)
    var family: StatusBarFontFamily = .system
    var size: Int
    var bold: Bool

    func font(numeric: Bool = false) -> NSFont {
        let pointSize = CGFloat(min(16,max(9,size)))
        let weight: NSFont.Weight = bold ? .semibold : .medium
        if family == .monospaced { return .monospacedSystemFont(ofSize:pointSize,weight:weight) }
        let base: NSFont = numeric ? .monospacedDigitSystemFont(ofSize:pointSize,weight:weight)
                                  : .systemFont(ofSize:pointSize,weight:weight)
        guard family == .rounded, let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor:descriptor,size:pointSize) ?? base
    }
}

struct StatusBarTypography: Equatable, Sendable {
    var label = StatusBarFontStyle(size:11,bold:false)
    var value = StatusBarFontStyle(size:12,bold:true)

    static func load(from defaults: UserDefaults) -> Self {
        func read(_ prefix: String, fallback: StatusBarFontStyle) -> StatusBarFontStyle {
            var result = fallback
            result.family = StatusBarFontFamily(rawValue:defaults.string(forKey:prefix+"FontFamily") ?? "") ?? fallback.family
            if let number = defaults.object(forKey:prefix+"FontSize") as? NSNumber {
                let size = number.doubleValue
                if size.isFinite, (9.0...16.0).contains(size), size.rounded() == size { result.size = Int(size) }
            }
            result.bold = defaults.object(forKey:prefix+"Bold") as? Bool ?? fallback.bold
            return result
        }
        let fallback = Self()
        return Self(label:read("statusBarLabel",fallback:fallback.label),
                    value:read("statusBarValue",fallback:fallback.value))
    }

    func save(to defaults: UserDefaults) {
        for (prefix,style) in [("statusBarLabel",label),("statusBarValue",value)] {
            defaults.set(style.family.rawValue,forKey:prefix+"FontFamily")
            defaults.set(style.size,forKey:prefix+"FontSize")
            defaults.set(style.bold,forKey:prefix+"Bold")
        }
    }
}
