import SwiftUI

struct ColorTone: Sendable {
    let lightness, chroma, hue: Double
    init(_ lightness: Double,_ chroma: Double,_ hue: Double) {
        self.lightness = lightness; self.chroma = chroma; self.hue = hue
    }
    var rgb: (Double,Double,Double) {
        let a = chroma * cos(hue * .pi / 180), b = chroma * sin(hue * .pi / 180)
        let l = pow(lightness + 0.3963377774*a + 0.2158037573*b,3)
        let m = pow(lightness - 0.1055613458*a - 0.0638541728*b,3)
        let s = pow(lightness - 0.0894841775*a - 1.2914855480*b,3)
        func gamma(_ x: Double) -> Double { min(1,max(0,x <= 0.0031308 ? 12.92*x : 1.055*pow(x,1/2.4)-0.055)) }
        return (gamma(4.0767416621*l-3.3077115913*m+0.2309699292*s),
                gamma(-1.2684380046*l+2.6097574011*m-0.3413193965*s),
                gamma(-0.0041960863*l-0.7034186147*m+1.7076147010*s))
    }
    var native: NSColor {
        let (r,g,b) = rgb
        return NSColor(srgbRed:r,green:g,blue:b,alpha:1)
    }
    var color: Color { Color(nsColor:native) }
}

enum MonitorAppearance: String, CaseIterable, Identifiable {
    case cold, warm, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .cold: "冷色"; case .warm: "暖色"; case .dark: "深色" }
    }
    var symbol: String {
        switch self { case .cold: "snowflake"; case .warm: "sun.max"; case .dark: "moon" }
    }
    var next: Self {
        switch self { case .cold: .warm; case .warm: .dark; case .dark: .cold }
    }
    var palette: Palette {
        switch self { case .cold: .cold; case .warm: .warm; case .dark: .dark }
    }
    var nativeAppearanceName: NSAppearance.Name { self == .dark ? .darkAqua : .aqua }

    static func load(from defaults: UserDefaults) -> Self {
        // Legacy light/system settings migrate to cold; existing dark stays dark.
        let appearance = Self(rawValue:defaults.string(forKey:"appearance") ?? "") ?? .cold
        defaults.set(appearance.rawValue,forKey:"appearance")
        return appearance
    }
}

struct Palette: Sendable {
    let brandTone, supportingTone, transferTone, warningTone, positiveTone: ColorTone
    let inkTone, secondaryInkTone, shellTone, cardTone, onTintTone: ColorTone

    static let cold = Palette(
        brandTone:ColorTone(0.51,0.15,257),supportingTone:ColorTone(0.51,0.085,60),
        transferTone:ColorTone(0.50,0.075,190),warningTone:ColorTone(0.53,0.135,43),positiveTone:ColorTone(0.48,0.095,166),
        inkTone:ColorTone(0.26,0.012,250),secondaryInkTone:ColorTone(0.48,0.014,250),
        shellTone:ColorTone(0.973,0.004,255),cardTone:ColorTone(0.999,0.001,255),onTintTone:ColorTone(1,0,0))
    static let warm = Palette(
        brandTone:ColorTone(0.50,0.115,42),supportingTone:ColorTone(0.51,0.09,250),
        transferTone:ColorTone(0.49,0.065,185),warningTone:ColorTone(0.50,0.17,28),positiveTone:ColorTone(0.47,0.075,151),
        inkTone:ColorTone(0.27,0.012,52),secondaryInkTone:ColorTone(0.47,0.014,52),
        shellTone:ColorTone(0.974,0.006,72),cardTone:ColorTone(0.998,0.002,72),onTintTone:ColorTone(1,0,0))
    static let dark = Palette(
        brandTone:ColorTone(0.76,0.095,166),supportingTone:ColorTone(0.76,0.08,250),
        transferTone:ColorTone(0.75,0.07,199),warningTone:ColorTone(0.78,0.105,43),positiveTone:ColorTone(0.76,0.095,166),
        inkTone:ColorTone(0.95,0.008,166),secondaryInkTone:ColorTone(0.76,0.012,166),
        shellTone:ColorTone(0.19,0.016,166),cardTone:ColorTone(0.27,0.015,166),onTintTone:ColorTone(0.15,0.015,166))

    var brand: Color { brandTone.color }
    var supporting: Color { supportingTone.color }
    var transfer: Color { transferTone.color }
    var warning: Color { warningTone.color }
    var positive: Color { positiveTone.color }
    var ink: Color { inkTone.color }
    var secondaryInk: Color { secondaryInkTone.color }
    var shell: Color { shellTone.color }
    var card: Color { cardTone.color }
    var onTint: Color { onTintTone.color }
    var isDark: Bool { shellTone.lightness < 0.5 }
    var surface: Color { ink.opacity(0.035) }
    var line: Color { ink.opacity(0.08) }
}

private struct MonitorPaletteKey: EnvironmentKey {
    static let defaultValue = Palette.cold
}

extension EnvironmentValues {
    var monitorPalette: Palette {
        get { self[MonitorPaletteKey.self] }
        set { self[MonitorPaletteKey.self] = newValue }
    }
}

struct FrostedBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView,context: Context) {}
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 12
    var tint: Color? = nil
    @Environment(\.monitorPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if palette.isDark && !reduceTransparency {
                        RoundedRectangle(cornerRadius:radius,style:.continuous).fill(.regularMaterial)
                    }
                    RoundedRectangle(cornerRadius:radius,style:.continuous)
                        .fill(palette.card.opacity(palette.isDark && !reduceTransparency ? 0.94 : 1))
                    if palette.isDark, let tint {
                        RoundedRectangle(cornerRadius:radius,style:.continuous)
                            .fill(tint.opacity(0.025))
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(palette.line.opacity(0.55),lineWidth:0.5))
    }
}

extension View {
    func glassCard(radius: CGFloat = 12,tint: Color? = nil) -> some View { modifier(GlassCard(radius:radius,tint:tint)) }
}

struct GlyphTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        Image(systemName:symbol)
            .font(.system(size:size*0.48,weight:.semibold))
            .foregroundStyle(palette.onTint)
            .frame(width:size,height:size)
            .background(LinearGradient(colors:[color,color.opacity(0.78)],startPoint:.topLeading,endPoint:.bottomTrailing),
                        in:RoundedRectangle(cornerRadius:size*0.28,style:.continuous))
            .accessibilityHidden(true)
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var color: Color? = nil
    @Environment(\.monitorPalette) private var palette
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:9) {
                if let symbol { GlyphTile(symbol:symbol,color:color ?? palette.supporting,size:25) }
                Text(title).font(.system(size:13,weight:.semibold))
                Spacer()
                if let subtitle { Text(subtitle).font(.system(size:11,weight:.medium)).foregroundStyle(palette.secondaryInk) }
            }
            content
        }.padding(18).glassCard(tint:symbol == nil ? nil : color ?? palette.supporting)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color? = nil
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        HStack(alignment:.firstTextBaseline,spacing:14) {
            Text(label).foregroundStyle(palette.secondaryInk)
            Spacer(minLength:12)
            Text(value).monospacedDigit().foregroundStyle(color ?? palette.ink).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size:12)).padding(.vertical,2)
    }
}

struct Meter: View {
    let percent: Double
    let color: Color
    var height: CGFloat = 4
    @Environment(\.monitorPalette) private var palette
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment:.leading) {
                Capsule().fill(palette.ink.opacity(0.055))
                Capsule().fill(color).frame(width:geo.size.width * min(1,max(0,percent/100)))
            }
        }.frame(height:height).accessibilityLabel("使用率 \(Readout.percent(percent))")
    }
}
