import SwiftUI

/// First-run empty states (Empty States Handoff): nothing fake, one primary action per screen.
struct EmptyHome: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let hasWorkouts = !store.workouts().isEmpty
        VStack(alignment: .leading, spacing: 0) {
            // ghost preview: the app's own populated home, dissolving into the page
            ZStack(alignment: .bottomLeading) {
                Image("GhostHome").resizable().scaledToFit()
                    .opacity(0.55)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.45), .init(color: .clear, location: 0.92)],
                                         startPoint: .top, endPoint: .bottom))
                Text("YOUR HOME ONCE THE LOOP RUNS").font(LWFont.mono(9.5)).tracking(0.8)
                    .foregroundStyle(LW.ink(0.3)).padding(.bottom, 26)
            }
            .frame(maxHeight: 330, alignment: .top).clipped()
            (Text("A ").foregroundStyle(LW.ink) + Text("routine").foregroundStyle(LW.accent) + Text(" is your workouts, on repeat").foregroundStyle(LW.ink))
                .font(LWFont.body(24, weight: 700)).tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            HStack(spacing: 9) {
                ForEach(Array(["Legs", "Push", "Back"].enumerated()), id: \.offset) { i, w in
                    if i > 0 { Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium)).foregroundStyle(LW.ink(0.4)) }
                    Text(w).font(LWFont.body(13, weight: 500)).foregroundStyle(LW.ink(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(LW.ink(0.3), lineWidth: 1))
                }
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)).foregroundStyle(LW.accent).padding(.leading, 3)
            }
            .padding(.top, 14).accessibilityIdentifier("empty.home.loop")
            Text("Finish one workout and the next is queued — with last time's weights and reps waiting as your target.")
                .font(LWFont.body(13)).foregroundStyle(LW.ink(0.55)).lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            (Text("swipe over to ").foregroundStyle(LW.ink(0.4))
             + Text(hasWorkouts ? "add them to a routine" : "build yours").foregroundStyle(LW.accent)
             + Text("  →").foregroundStyle(LW.accent))
                .font(LWFont.mono(11)).padding(.top, 20)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("empty.home")
    }
}

struct EmptyRoutineSlots: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(["1 · Your first workout goes here", "2 · Then the next…"].enumerated()), id: \.offset) { i, t in
                Text(t).font(LWFont.mono(11.5)).foregroundStyle(LW.ink(i == 0 ? 0.45 : 0.28))
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 44).padding(.horizontal, 12)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(LW.ink(i == 0 ? 0.2 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            Text("A routine is a loop — finish one workout and the next is queued automatically. Build 2–4 and order them.")
                .font(LWFont.mono(10)).foregroundStyle(LW.ink(0.35)).lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain).accessibilityIdentifier("empty.workouts.slots")
    }
}

struct EmptyWorkoutsCard: View {
    let onNew: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogoMark(width: 30, color: LW.ink(0.3))
            Text("No workouts yet. A workout is a list of exercises with sets × reps — build one in a minute.")
                .font(LWFont.body(12.5)).foregroundStyle(LW.ink(0.55)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onNew) {
                Text("+ NEW WORKOUT").font(LWFont.mono(11, semibold: true)).tracking(1).foregroundStyle(LW.inkOnAccent)
                    .padding(.horizontal, 18).frame(height: 38)
                    .background(Capsule().fill(LW.accent)).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("empty.workouts.new")
            Text("or import from Hevy — workouts rebuild from your titles")
                .font(LWFont.mono(9.5)).foregroundStyle(LW.ink(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LW.ink(0.15), lineWidth: 1))
        .padding(.top, 10)
        .accessibilityElement(children: .contain).accessibilityIdentifier("empty.workouts.card")
    }
}

struct EmptyCalendarCard: View {
    let onImport: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trained days get a dot; every session lands in this list. Your history can start today — or years ago.")
                .font(LWFont.body(12.5)).foregroundStyle(LW.ink(0.55)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onImport) {
                Text("IMPORT FROM HEVY").font(LWFont.mono(11, semibold: true)).tracking(1).foregroundStyle(LW.inkOnAccent)
                    .padding(.horizontal, 18).frame(height: 38)
                    .background(Capsule().fill(LW.accent)).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("empty.calendar.import")
            Text("pick your Hevy CSV export · re-import is safe, nothing duplicates")
                .font(LWFont.mono(9.5)).foregroundStyle(LW.ink(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LW.ink(0.15), lineWidth: 1))
        .padding(.top, 16)
        .accessibilityElement(children: .contain).accessibilityIdentifier("empty.calendar")
    }
}
