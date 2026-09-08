import SwiftUI
import Observation

/// The four swipeable pages, left to right.
enum Page: Hashable, CaseIterable { case home, workouts, calendar }

enum PickerTarget: Hashable { case workout(UUID), session(UUID) }

/// Screens presented over the pager.
enum Route: Hashable {
    case session(UUID), summary(UUID), exercise(String), workoutEdit(UUID), picker(PickerTarget), account
}

@MainActor @Observable final class Router {
    var page: Page = .home
    var stack: [Route] = []            // screens over the pager, last on top
    var splash: String? = nil          // workout name shown on the start splash
    var pagingLocked = false           // true while a slider is being dragged
    var workoutsEditing = false        // Workouts page edit mode; toggled from the fixed header
    var startSheet = false
    var slotPicker = false             // "+ Add slot" → pick the workout the new slot holds
    var startRequest: UUID?          // Home's START button → StartLayer raises the splash
    var heroNameFrame: CGRect = .zero   // the card's workout name, in global space — the splash flies from here
    var finishSplash: UUID?             // covers the summary while the engine catches up             // 3b: the detached + circle asks — saved workout or fresh
    func show(_ p: Page) { withAnimation(.easeOut(duration: 0.3)) { page = p } }
    func push(_ r: Route) { withAnimation(.easeOut(duration: 0.22)) { stack.append(r) } }
    func pop() { withAnimation(.easeOut(duration: 0.22)) { _ = stack.popLast() } }
    func present(_ r: Route) { withAnimation(.easeOut(duration: 0.22)) { stack = [r] } }
    func home() { withAnimation(.easeOut(duration: 0.22)) { stack = []; page = .home } }
    /// The page mark opens the account page from the left, and it leaves the same way.
    func openAccount() { withAnimation(.easeOut(duration: 0.32)) { stack.append(.account) } }
    func closeAccount() { withAnimation(.easeOut(duration: 0.32)) { if stack.last == .account { _ = stack.popLast() } } }
}
