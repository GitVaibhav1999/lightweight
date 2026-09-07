import SwiftUI

/// Stroke icons traced from the design board's SVGs (24-grid unless noted).
struct IconShape: Shape {
    enum Kind { case arrowUp, arrowDown, held, home, dumbbell, list, more, calendar, check, close, chevronLeft, chevronRight, chevronDown, chevronUp, search, edit, trash, minusCircle, bolt, arrowRight }
    let kind: Kind
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = r.width / (kind == .arrowUp || kind == .arrowDown || kind == .held ? 14 : 24)
        func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: r.minX + x * s, y: r.minY + y * s)) }
        func l(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: CGPoint(x: r.minX + x * s, y: r.minY + y * s)) }
        switch kind {
        case .arrowUp: m(4, 10); l(10, 4); m(10, 4); l(5.4, 4); m(10, 4); l(10, 8.6)
        case .arrowDown: m(4, 4); l(10, 10); m(10, 10); l(5.4, 10); m(10, 10); l(10, 5.4)
        case .held: m(5, 3.5); l(5, 10.5); m(9, 3.5); l(9, 10.5)
        case .home: m(3, 11); l(12, 4); l(21, 11); m(5, 10); l(5, 20); l(19, 20); l(19, 10)
        case .dumbbell:
            m(2, 12); l(5, 12); m(19, 12); l(22, 12); m(8, 12); l(16, 12)
            p.addRoundedRect(in: CGRect(x: r.minX + 5 * s, y: r.minY + 8 * s, width: 3 * s, height: 8 * s), cornerSize: CGSize(width: s, height: s))
            p.addRoundedRect(in: CGRect(x: r.minX + 16 * s, y: r.minY + 8 * s, width: 3 * s, height: 8 * s), cornerSize: CGSize(width: s, height: s))
        case .more:
            for x in [6.0, 12.0, 18.0] { m(x, 12); l(x + 0.01, 12) }
        case .list:
            m(5, 6);  l(5.01, 6);  m(10, 6);  l(20, 6)
            m(5, 12); l(5.01, 12); m(10, 12); l(20, 12)
            m(5, 18); l(5.01, 18); m(10, 18); l(20, 18)
        case .calendar:
            p.addRoundedRect(in: CGRect(x: r.minX + 4 * s, y: r.minY + 5 * s, width: 16 * s, height: 15 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            m(8, 3); l(8, 7); m(16, 3); l(16, 7); m(4, 11); l(20, 11)
        case .check: m(5, 12); l(10, 17); l(19, 7)
        case .close: m(6, 6); l(18, 18); m(18, 6); l(6, 18)
        case .chevronLeft: m(15, 5); l(8, 12); l(15, 19)
        case .chevronRight: m(9, 5); l(16, 12); l(9, 19)
        case .chevronDown: m(6, 9); l(12, 15); l(18, 9)
        case .chevronUp: m(6, 15); l(12, 9); l(18, 15)
        case .search: p.addEllipse(in: CGRect(x: r.minX + 4 * s, y: r.minY + 4 * s, width: 14 * s, height: 14 * s)); m(20, 20); l(16.5, 16.5)
        case .edit: m(12, 20); l(21, 20); m(16.5, 3.5); l(20, 7); l(7, 20); l(3, 21); l(4, 17); l(16.5, 3.5)
        case .trash: m(3, 6); l(21, 6); m(8, 6); l(8, 4); l(16, 4); l(16, 6); m(19, 6); l(18, 20); l(6, 20); l(5, 6)
        case .minusCircle: p.addEllipse(in: CGRect(x: r.minX + 3 * s, y: r.minY + 3 * s, width: 18 * s, height: 18 * s)); m(8, 12); l(16, 12)
        case .arrowRight: m(4, 12); l(18, 12); m(13, 6); l(19, 12); l(13, 18)
        case .bolt: break
        }
        return p
    }
}

struct Icon: View {
    let kind: IconShape.Kind
    var size: CGFloat = 17
    var color: Color = LW.ink(0.4)
    var weight: CGFloat = 1.8
    var body: some View {
        IconShape(kind: kind)
            .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// Filled bolt used on the slide-to-start thumb (16×24 grid).
struct BoltShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 16
        var p = Path()
        let pts: [(CGFloat, CGFloat)] = [(9, 1), (3, 12), (7, 12), (5, 23), (13, 9), (8, 9), (11, 1)]
        p.move(to: CGPoint(x: r.minX + pts[0].0 * s, y: r.minY + pts[0].1 * s))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: r.minX + q.0 * s, y: r.minY + q.1 * s)) }
        p.closeSubpath(); return p
    }
}

/// The LIGHT WEIGHT mark: two plates each side and a jagged bar (32×18 grid).
struct LogoMark: View {
    var width: CGFloat = 24
    var color: Color = LW.accent
    var body: some View {
        let s = width / 32
        ZStack(alignment: .topLeading) {
            ForEach([(0.5, 5.0, 2.5, 8.0), (4.5, 2.0, 3.0, 14.0), (24.5, 2.0, 3.0, 14.0), (29.0, 5.0, 2.5, 8.0)], id: \.0) { x, y, w, h in
                RoundedRectangle(cornerRadius: s).fill(color).frame(width: w * s, height: h * s).offset(x: x * s, y: y * s)
            }
            Path { p in
                let pts: [(CGFloat, CGFloat)] = [(7.5, 10), (13, 6.5), (16, 11), (19.5, 6.5), (24.5, 10)]
                p.move(to: CGPoint(x: pts[0].0 * s, y: pts[0].1 * s)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0 * s, y: q.1 * s)) }
            }.stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: 18 * s, alignment: .topLeading)
    }
}

/// Drag handle: 2×3 dots (12×16 grid).
struct DragHandle: View {
    var body: some View {
        VStack(spacing: 2.6) { ForEach(0..<3, id: \.self) { _ in HStack(spacing: 3.2) { Circle().frame(width: 2.8, height: 2.8); Circle().frame(width: 2.8, height: 2.8) } } }
            .foregroundStyle(LW.ink(0.3)).frame(width: 11, height: 15)
    }
}

/// 180×180 dataset thumbnail (© Gym visual), shown in a rounded tile; dashed placeholder for customs.
struct ExerciseThumb: View {
    let exercise: Exercise?
    var size: CGFloat = 38
    var body: some View {
        if let t = exercise?.thumb, let url = Bundle.main.url(forResource: (t as NSString).deletingPathExtension, withExtension: (t as NSString).pathExtension, subdirectory: "Thumbs"), let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: size * 0.24)).opacity(0.92)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(LW.ink(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: size, height: size)
        }
    }
}

struct VerdictIcon: View {
    let verdict: ExerciseVerdict?
    var size: CGFloat = 13
    var body: some View {
        switch verdict {
        case .best: Icon(kind: .arrowUp, size: size, color: LW.accentBright, weight: 2.6)
        case .up: Icon(kind: .arrowUp, size: size, color: LW.accent, weight: 2.6)
        case .held: Icon(kind: .held, size: size, color: LW.ink(0.5), weight: 2.6)
        case .down: Icon(kind: .arrowDown, size: size, color: LW.ink(0.45), weight: 2.6)
        case nil: Color.clear.frame(width: size, height: size)
        }
    }
}
