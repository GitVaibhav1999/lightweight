import SwiftUI

/// Liquid Glass surfaces. Native `glassEffect` on iOS 26, with the design's 0.5 px rim and inner highlight on top.
extension View {
    func lwGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, rim: Double = 0.14, shadow: Bool = true) -> some View {
        self
            .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive(), in: shape)
            .overlay { shape.strokeBorder(LW.ink(rim), lineWidth: 0.5) }
            .shadow(color: shadow ? LW.shadow(0.5) : .clear, radius: 13, y: 10)
    }
}

/// Screen frame: black ground, sage glow at the top, 58/22 padding like every frame on the board.
/// Pager pages' main scroll — plain (original pre-glass behavior: content scrolls below the fixed header, never under it).
struct HeaderScroll<Content: View>: View {
    var page: Page
    var edit: Binding<Bool>? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(showsIndicators: false) { content }
    }
}

struct Screen<Content: View>: View {
    var top: CGFloat = LW.topPad
    var underBar: Bool = false   // pager pages: scroll content runs under the global header with the system's soft edge blur
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            LW.bg.ignoresSafeArea()
            RadialGradient(colors: [LW.accent(0.13), .clear], center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: 460).ignoresSafeArea()
            content.padding(.horizontal, LW.screenPad).padding(.top, top)
        }
        .foregroundStyle(LW.ink)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
}

/// Outlined sage pill button ("+ Add exercise", "Create custom exercise").
struct OutlinePill: View {
    let title: String; var height: CGFloat = 44; var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title).font(LWFont.body(13.5, weight: 600)).foregroundStyle(LW.accent)
                .frame(maxWidth: .infinity).frame(height: height)
                .overlay(Capsule().strokeBorder(LW.accent(0.5), lineWidth: 1)).contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier(title)
    }
}

struct Hairline: View { var body: some View { Rectangle().fill(LW.hairline).frame(height: 1) } }

/// Session verdict from the engine (PRD §6): BEST filled, UP sage, STALLED outlined with a pulse, HELD/DOWN quiet.
struct VerdictBadge: View {
    let state: SessionState?
    var body: some View {
        if let state {
            HStack(spacing: 5) {
                if state == .stalled { PulseDot() }
                Text(state.rawValue)
            }
            .font(LWFont.mono(9.5, semibold: true)).tracking(1)
            .foregroundStyle(fg(state))
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(state == .best ? LW.accent : .clear))
            .overlay(Capsule().strokeBorder(rim(state), lineWidth: 1))
            .accessibilityIdentifier("verdict.\(state.rawValue.lowercased())")
        }
    }
    private func fg(_ s: SessionState) -> Color { s == .best ? LW.inkOnAccent : (s == .up || s == .stalled) ? LW.accent : LW.ink(0.45) }
    private func rim(_ s: SessionState) -> Color { s == .best ? .clear : s == .stalled ? LW.accent : s == .up ? LW.accent(0.5) : LW.ink(0.25) }
}

struct PulseDot: View {
    var size: CGFloat = 5
    @State private var on = true
    var body: some View {
        Circle().fill(LW.accent).frame(width: size, height: size).opacity(on ? 1 : 0.25)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = false } }
    }
}

/// Pick-and-drop reordering for a fixed-row-height list: drag the dots, rows spring aside, `onMove` commits.
struct ReorderState { var from: Int; var offset: CGFloat; var target: Int }

struct ReorderHandle: View {
    @Environment(Router.self) private var router
    let index: Int; let count: Int; let rowHeight: CGFloat
    @Binding var drag: ReorderState?
    let onMove: (Int, Int) -> Void
    var body: some View {
        DragHandle().frame(width: 28, height: 40).contentShape(Rectangle())
            .accessibilityIdentifier("handle.\(index)").accessibilityLabel("Reorder")
            .highPriorityGesture(DragGesture(minimumDistance: 2)
                .onChanged { v in
                    let to = max(0, min(count - 1, index + Int((v.translation.height / rowHeight).rounded())))
                    if drag == nil { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }        // pick-up
                    else if drag?.target != to { UISelectionFeedbackGenerator().selectionChanged() }     // new slot
                    drag = ReorderState(from: index, offset: v.translation.height, target: to)
                }
                .onEnded { v in
                    let to = max(0, min(count - 1, index + Int((v.translation.height / rowHeight).rounded())))
                    if to != index {
                        onMove(index, to); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        drag = nil                      // instant: the re-sorted list already places the row — animating here ghosts
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = nil }
                    }
                })
    }
}

extension View {
    /// Offsets a row during a reorder drag: the dragged row lifts and follows the finger, the others spring aside.
    func reorderOffset(index: Int, drag: ReorderState?, rowHeight: CGFloat) -> some View {
        let lifted = drag?.from == index
        let shift: CGFloat = {
            guard let d = drag, d.from != index else { return 0 }
            if d.from < index && index <= d.target { return -rowHeight }
            if d.target <= index && index < d.from { return rowHeight }
            return 0
        }()
        return self
            .offset(y: lifted ? drag!.offset : shift)
            .scaleEffect(lifted ? 1.02 : 1)
            .shadow(color: lifted ? LW.shadow(0.45) : .clear, radius: 10, y: 6)
            .background(lifted ? LW.bg.opacity(0.98) : .clear)
            .zIndex(lifted ? 1 : 0)
            .animation(lifted ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: shift)
    }
}

/// Edit-trigger "Arrange" glyph (24×24 viewBox): three list rows + a lift arrow.
struct ArrangeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        for (y, w) in [(6.0, 10.0), (12.0, 7.0), (18.0, 10.0)] {
            p.move(to: CGPoint(x: 4 * s, y: y * s)); p.addLine(to: CGPoint(x: (4 + w) * s, y: y * s))
        }
        p.move(to: CGPoint(x: 19 * s, y: 16 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 8 * s))
        p.move(to: CGPoint(x: 19 * s, y: 8 * s)); p.addLine(to: CGPoint(x: 16.5 * s, y: 10.5 * s))
        p.move(to: CGPoint(x: 19 * s, y: 8 * s)); p.addLine(to: CGPoint(x: 21.5 * s, y: 10.5 * s))
        return p
    }
}

/// Workouts edit trigger: fixed 34×30 capsule slot, Arrange glyph → ✓ fill; pulses until first use.
struct EditTrigger: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var editing: Bool
    @State private var pulse = false
    private var used: Bool { UserDefaults.standard.bool(forKey: "edit.trigger.used") }
    var body: some View {
        Button {
            if reduceMotion { editing.toggle() } else { withAnimation(.easeOut(duration: 0.2)) { editing.toggle() } }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if editing { UserDefaults.standard.set(true, forKey: "edit.trigger.used") }
            AccessibilityNotification.Announcement(editing ? "Editing" : "Done editing").post()
        } label: {
            ZStack {
                if editing {
                    Icon(kind: .check, size: 13, color: LW.accent, weight: 2.6)
                } else {
                    ArrangeGlyph().stroke(LW.accent, style: StrokeStyle(lineWidth: 1.9 * 16 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: 34, height: 30)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay {
                if !editing, !used, !reduceMotion {
                    Capsule().stroke(LW.accent(0.5), lineWidth: 1.5)
                        .scaleEffect(pulse ? 1.55 : 1).opacity(pulse ? 0 : 0.7)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)
                        .onAppear { pulse = true }
                }
            }
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workouts.edit")
        .accessibilityLabel(editing ? "Done editing" : "Edit routine and workouts")
    }
}
