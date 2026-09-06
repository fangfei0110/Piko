import SwiftUI
import Charts

struct MetricChart: View {
    let points: [TrendPoint]
    let key: KeyPath<TrendPoint,Double?>
    let color: Color
    var secondKey: KeyPath<TrendPoint,Double?>? = nil
    var secondColor: Color? = nil
    @Environment(\.monitorPalette) private var palette
    var percent = true
    var height: CGFloat = 112
    var small = false
    private var maximum: Double {
        if percent { return 100 }
        let values = points.flatMap { p -> [Double] in
            [p[keyPath:key], secondKey.flatMap { p[keyPath:$0] }].compactMap { $0 }
        }
        return max(1024,(values.max() ?? 0)*1.12)
    }
    var body: some View {
        Chart {
            ForEach(points) { point in
                if let value = point[keyPath:key] {
                    if secondKey == nil {
                        AreaMark(x:.value("时间",point.date),yStart:.value("起点",0),yEnd:.value("读数",value),series:.value("系列","primary"))
                            .foregroundStyle(LinearGradient(colors:[color.opacity(palette.isDark ? 0.12 : 0.075),color.opacity(0.005)],startPoint:.top,endPoint:.bottom))
                    }
                    LineMark(x:.value("时间",point.date),y:.value("读数",value),series:.value("系列","primary"))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth:small ? 1.15 : 1.5,lineCap:.round,lineJoin:.round))
                        .interpolationMethod(.linear)
                }
                if let secondKey, let value = point[keyPath:secondKey] {
                    LineMark(x:.value("时间",point.date),y:.value("读数",value),series:.value("系列","secondary"))
                        .foregroundStyle(secondColor ?? palette.supporting)
                        .lineStyle(StrokeStyle(lineWidth:small ? 1.1 : 1.35,lineCap:.round,lineJoin:.round,dash:[3,3]))
                        .interpolationMethod(.linear)
                }
            }
        }
        .chartYScale(domain:0...maximum,range:.plotDimension(startPadding:3,endPadding:3))
        .chartXScale(range:.plotDimension(startPadding:1,endPadding:1))
        .chartXAxis {
            if !small {
                AxisMarks(values:.automatic(desiredCount:4)) { _ in
                    AxisValueLabel().font(.system(size:9).monospacedDigit()).foregroundStyle(palette.secondaryInk)
                }
            }
        }
        .chartYAxis {
            if !small {
                AxisMarks(position:.leading,values:[0,maximum/2,maximum]) { value in
                    AxisGridLine(stroke:StrokeStyle(lineWidth:0.5,dash:[2,4])).foregroundStyle(palette.line)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(percent ? "\(Int(number))%" : Readout.bytes(number,compact:true))
                                .font(.system(size:9).monospacedDigit()).foregroundStyle(palette.secondaryInk)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height:height)
        .overlay {
            if points.filter({ $0[keyPath:key] != nil }).count < 2 {
                Text("正在积累样本…").font(.system(size:11)).foregroundStyle(palette.secondaryInk)
            }
        }
        .accessibilityLabel(percent ? "最近的使用率变化" : "最近的每秒传输量变化")
    }
}
