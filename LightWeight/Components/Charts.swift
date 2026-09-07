import SwiftUI

/// 56×15 trend line with an accent end dot (session cards).
struct Sparkline: View {
    let values: [Double]
    var lastIsBest = false          // the latest point goes bright when that session set a record
    var body: some View {
        GeometryReader { _ in
            let pts = points()
            ZStack {
                if pts.count > 1 {
                    Path { p in p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) } }
                        .stroke(LW.ink(0.45), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
                if let last = pts.last {
                    Circle().fill(lastIsBest ? LW.accentBright : LW.accent).frame(width: 5.2, height: 5.2).position(last)
                }
            }
        }.frame(width: 46, height: 16)
    }
    private func points() -> [CGPoint] {
        let v = values.suffix(6); guard v.count > 1, let lo = v.min(), let hi = v.max() else { return values.isEmpty ? [] : [CGPoint(x: 40, y: 8)] }
        let span = max(hi - lo, 1)
        return v.enumerated().map { i, y in CGPoint(x: 3 + CGFloat(i) * 40 / CGFloat(v.count - 1), y: 13 - CGFloat((y - lo) / span) * 10) }
    }
}

/// The board's 300×128 progression chart: 3 grid lines, right-edge y labels, area fill, faint line, dots, accent end dot with ring, axis captions.
struct ProgressionChart: View {
    let values: [Double]
    var labelLeft = "", labelRight = "", caption = ""
    var format: (Double) -> String = { v in v >= 1000 ? String(format: "%.1fk", v / 1000) : String(format: "%.0f", v) }
    var fixedHeight: CGFloat? = nil        // explicit height (compact pinned charts); nil = 300:128 aspect

    var body: some View {
        if let fixedHeight { core.frame(height: fixedHeight).frame(maxWidth: .infinity) }
        else { core.aspectRatio(300 / 128, contentMode: .fit) }
    }
    private var core: some View {
        GeometryReader { g in
            let sx = g.size.width / 300, sy = g.size.height / 128
            let pts = points(sx: sx, sy: sy)
            let (lo, hi) = range()
            ZStack(alignment: .topLeading) {
                ForEach([30, 65, 100], id: \.self) { y in
                    Path { p in p.move(to: CGPoint(x: 10 * sx, y: CGFloat(y) * sy)); p.addLine(to: CGPoint(x: 290 * sx, y: CGFloat(y) * sy)) }.stroke(LW.ink(0.07), lineWidth: 1)
                }
                ForEach(Array([(30.0, hi), (65.0, (lo + hi) / 2), (100.0, lo)].enumerated()), id: \.offset) { _, e in
                    Text(format(e.1)).font(LWFont.mono(8)).foregroundStyle(LW.ink(0.3))
                        .position(x: 290 * sx - 12, y: CGFloat(e.0) * sy - 3)
                }
                if pts.count > 1 {
                    Path { p in p.move(to: CGPoint(x: pts[0].x, y: 112 * sy)); p.addLine(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; p.addLine(to: CGPoint(x: pts.last!.x, y: 112 * sy)); p.closeSubpath() }
                        .fill(LW.accent(0.09))
                    Path { p in p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) } }
                        .stroke(LW.ink(0.35), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    ForEach(Array(pts.dropLast().enumerated()), id: \.offset) { _, q in Circle().fill(LW.ink(0.4)).frame(width: fixedHeight != nil ? 2 : 4, height: fixedHeight != nil ? 2 : 4).position(q) }
                }
                if let last = pts.last {
                    Circle().fill(LW.accent).frame(width: fixedHeight != nil ? 5 : 7, height: fixedHeight != nil ? 5 : 7).position(last)
                    if fixedHeight == nil { Circle().stroke(LW.accent(0.4), lineWidth: 1).frame(width: 13, height: 13).position(last) }
                }
                Group {
                    Text(labelLeft).position(x: 10 * sx + 14, y: 121 * sy)
                    Text(caption).position(x: 150 * sx, y: 121 * sy)
                    Text(labelRight).position(x: 290 * sx - 16, y: 121 * sy)
                }.font(LWFont.mono(8.5)).foregroundStyle(LW.ink(0.35))
            }
        }
    }
    private func range() -> (Double, Double) {
        guard let lo = values.min(), let hi = values.max() else { return (0, 1) }
        return lo == hi ? (lo * 0.9, hi * 1.1) : (lo, hi)
    }
    private func points(sx: CGFloat, sy: CGFloat) -> [CGPoint] {
        let (lo, hi) = range(); let n = values.count
        guard n > 0 else { return [] }
        return values.enumerated().map { i, v in
            CGPoint(x: (n == 1 ? 290 : 10 + CGFloat(i) * 280 / CGFloat(n - 1)) * sx, y: (100 - CGFloat((v - lo) / (hi - lo)) * 70) * sy)
        }
    }
}
