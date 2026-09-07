import Foundation
import SwiftData

/// A movement. Seeded from the exercises-dataset or created by the user.
@Model final class Exercise {
    @Attribute(.unique) var id: String          // dataset id ("0025") or "custom-<uuid>"
    var name: String
    var bodyPart: String
    var target: String
    var equipment: String
    var loadType: String                        // weight+reps | bodyweight+reps | time
    var thumb: String?
    var source: String                          // dataset | custom
    var createdAt: Date

    init(id: String, name: String, bodyPart: String, target: String, equipment: String, loadType: String, thumb: String? = nil, source: String) {
        self.id = id; self.name = name; self.bodyPart = bodyPart; self.target = target; self.equipment = equipment
        self.loadType = loadType; self.thumb = thumb; self.source = source; self.createdAt = .now
    }
    var isBodyweight: Bool { loadType == "bodyweight+reps" }
}

/// A template: ordered slots. Standalone; many.
@Model final class Workout {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSlot.workout) var slots: [WorkoutSlot]

    init(name: String) { id = UUID(); self.name = name; createdAt = .now; slots = [] }
    var orderedSlots: [WorkoutSlot] { slots.sorted { $0.order < $1.order } }
}

@Model final class WorkoutSlot {
    var order: Int
    var exerciseID: String
    var exerciseName: String
    var sets: Int
    var repLo: Int
    var repHi: Int
    var workout: Workout?

    init(order: Int, exerciseID: String, exerciseName: String, sets: Int, repLo: Int, repHi: Int) {
        self.order = order; self.exerciseID = exerciseID; self.exerciseName = exerciseName
        self.sets = sets; self.repLo = repLo; self.repHi = repHi
    }
}

/// An ordered loop of workouts. Exactly one is active; it holds the pointer.
@Model final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String
    var isActive: Bool
    var pointer: Int
    var cyclesCompleted: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \RoutineEntry.routine) var entries: [RoutineEntry]

    init(name: String, isActive: Bool) { id = UUID(); self.name = name; self.isActive = isActive; pointer = 0; entries = [] }
    var orderedEntries: [RoutineEntry] { entries.sorted { $0.order < $1.order } }
}

@Model final class RoutineEntry {
    var order: Int
    var workoutID: UUID
    var routine: Routine?
    init(order: Int, workoutID: UUID) { self.order = order; self.workoutID = workoutID }
}

/// A performed workout. From a template (workoutID) or fresh.
@Model final class Session {
    @Attribute(.unique) var id: UUID
    var workoutID: UUID?
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var source: String                          // app | hevy
    @Attribute(.unique) var hevyKey: String?    // "\(title)|\(start_time)" — idempotent import
    var isDraft: Bool
    var isStarted: Bool = false      // a draft that has actually begun (timer running) — the "live" session
    var rpe: Int? = nil              // coach ask: 1 easy · 2 about right · 3 brutal
    var edited: Bool = false         // numbers corrected after finishing (Session Updates §4)
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session) var exercises: [SessionExercise]

    init(title: String, workoutID: UUID?, startedAt: Date, source: String) {
        id = UUID(); self.title = title; self.workoutID = workoutID; self.startedAt = startedAt
        self.source = source; isDraft = source == "app"; exercises = []
    }
    var orderedExercises: [SessionExercise] { exercises.sorted { $0.order < $1.order } }
    var durationMinutes: Int { Int(((endedAt ?? .now).timeIntervalSince(startedAt)) / 60) }
    /// Sessions are compared against the previous session of the same workout; imported ones group by title.
    var groupKey: String { workoutID?.uuidString ?? title }
}

@Model final class SessionExercise {
    var order: Int
    var exerciseID: String
    var exerciseName: String
    var session: Session?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise) var sets: [SetLog]

    init(order: Int, exerciseID: String, exerciseName: String) {
        self.order = order; self.exerciseID = exerciseID; self.exerciseName = exerciseName; sets = []
    }
    var orderedSets: [SetLog] { sets.sorted { $0.index < $1.index } }
}

@Model final class SetLog {
    var index: Int
    var type: String                            // normal | warmup | failure | dropset
    var kg: Double?
    var reps: Int?
    var seconds: Int?
    var done: Bool
    var isPR: Bool = false
    var exercise: SessionExercise?

    init(index: Int, type: String = "normal", kg: Double?, reps: Int?, seconds: Int? = nil, done: Bool = true) {
        self.index = index; self.type = type; self.kg = kg; self.reps = reps; self.seconds = seconds; self.done = done
    }
}

enum Schema {
    static let all: [any PersistentModel.Type] = [Exercise.self, Workout.self, WorkoutSlot.self, Routine.self, RoutineEntry.self, Session.self, SessionExercise.self, SetLog.self, CoachNote.self]
}
