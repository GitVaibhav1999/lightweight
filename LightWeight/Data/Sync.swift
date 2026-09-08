import Foundation
import SwiftData
import Supabase

/// Push local training data to Postgres.
///
/// One direction for now. Pull is the harder half — it needs conflict resolution and the
/// tombstones the schema already carries — and pushing first is what proves the schema
/// holds real data at real scale.
///
/// Two properties make this safe to run repeatedly:
///   - Primary keys are minted on the client, so an upsert on `id` is idempotent. Running
///     it twice changes nothing; running it after a crash resumes rather than duplicates.
///   - Every row carries `user_id` from the live session, which is what RLS checks. A row
///     with the wrong owner is rejected by Postgres, not merely by convention.
@MainActor enum Sync {
    struct Report: Sendable {
        var workouts = 0, slots = 0, routines = 0, entries = 0
        var sessions = 0, sessionExercises = 0, setLogs = 0, exercises = 0
        var seconds: Double = 0
        var summary: String {
            "\(workouts) workouts · \(slots) slots · \(routines) routines · \(entries) entries · "
            + "\(sessions) sessions · \(sessionExercises) exercises · \(setLogs) sets · "
            + "\(exercises) custom · \(String(format: "%.1f", seconds))s"
        }
    }

    enum Failure: LocalizedError {
        case notSignedIn
        var errorDescription: String? { "Sign in before syncing — every row is fenced by its owner." }
    }

    /// PostgREST takes the whole array in one request body; 500 keeps that request a sane
    /// size while still making 6,000 set logs a handful of round trips rather than 6,000.
    private static let batch = 500

    static func pushAll(_ store: AppStore, progress: (@MainActor (String) -> Void)? = nil) async throws -> Report {
        guard let user = try? await Supa.client.auth.session.user else { throw Failure.notSignedIn }
        let uid = user.id.uuidString.lowercased()
        let t0 = Date()
        var r = Report()

        func fetch<T: PersistentModel>(_: T.Type) -> [T] {
            (try? store.context.fetch(FetchDescriptor<T>())) ?? []
        }
        func send(_ table: String, _ rows: [some Encodable & Sendable]) async throws {
            guard !rows.isEmpty else { return }
            for chunk in stride(from: 0, to: rows.count, by: batch).map({ Array(rows[$0..<min($0 + batch, rows.count)]) }) {
                _ = try await Supa.client.from(table)
                    .upsert(chunk, onConflict: "id", returning: .minimal).execute()
            }
            progress?("\(table): \(rows.count)")
        }

        // Custom exercises only. The shipped catalog is user_id null and writable by no one,
        // so pushing it as this user would be rejected — and it is the same for everybody.
        let customs = fetch(Exercise.self).filter { $0.source == "custom" }
        try await send("exercises", customs.map { ExerciseRow($0, uid) })
        r.exercises = customs.count

        // Parents before children: every child carries a foreign key to the row above it.
        let workouts = fetch(Workout.self)
        try await send("workouts", workouts.map { WorkoutRow($0, uid) })
        r.workouts = workouts.count

        let slots = workouts.flatMap { w in w.orderedSlots.map { SlotRow($0, w, uid) } }
        try await send("workout_slots", slots)
        r.slots = slots.count

        let routines = fetch(Routine.self)
        try await send("routines", routines.map { RoutineRow($0, uid) })
        r.routines = routines.count

        let entries = routines.flatMap { rt in rt.orderedEntries.map { EntryRow($0, rt, uid) } }
        try await send("routine_entries", entries)
        r.entries = entries.count

        let sessions = fetch(Session.self)
        try await send("sessions", sessions.map { SessionRow($0, uid) })
        r.sessions = sessions.count

        let ses = sessions.flatMap { s in s.orderedExercises.map { SessionExerciseRow($0, s, uid) } }
        try await send("session_exercises", ses)
        r.sessionExercises = ses.count

        let logs = sessions.flatMap { s in s.orderedExercises.flatMap { se in se.orderedSets.map { SetRow($0, se, uid) } } }
        try await send("set_logs", logs)
        r.setLogs = logs.count

        r.seconds = Date().timeIntervalSince(t0)
        return r
    }

    // ── row shapes ───────────────────────────────────────────────────────────
    // Written by hand rather than derived, because the column names are the contract
    // (see supabase/SCHEMA.md): `order`/`index` become `position`, `type` becomes `kind`,
    // and `source` is not a column at all — user_id null vs set carries it.

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated private static func s(_ d: Date?) -> String? { d.map { iso.string(from: $0) } }
    nonisolated private static func id(_ u: UUID) -> String { u.uuidString.lowercased() }

    /// Children of a soft-deletable parent get a deterministic id from the parent plus
    /// position: SwiftData does not give these rows an identity of their own, and a random
    /// one per push would insert duplicates on every run instead of updating.
    nonisolated private static func childID(_ parent: UUID, _ position: Int, _ salt: String) -> String {
        uuidV5Like("\(parent.uuidString)-\(salt)-\(position)")
    }
    /// Deterministic UUID from a string. Not RFC 4122 v5 (no SHA-1 dependency), but stable,
    /// which is the only property that matters here.
    nonisolated private static func uuidV5Like(_ s: String) -> String {
        var h1: UInt64 = 0xcbf29ce484222325, h2: UInt64 = 0x9e3779b97f4a7c15
        for b in s.utf8 {
            h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
            h2 = (h2 &+ UInt64(b)) &* 0xff51afd7ed558ccd
            h2 ^= h2 >> 33
        }
        let hex = String(format: "%016lx%016lx", h1, h2)
        let p = Array(hex)
        return "\(String(p[0..<8]))-\(String(p[8..<12]))-\(String(p[12..<16]))-\(String(p[16..<20]))-\(String(p[20..<32]))"
    }

    private struct ExerciseRow: Encodable, Sendable {
        let id: String, user_id: String, name: String, body_part: String?, target: String?
        let equipment: String?, load_type: String, thumb: String?
        init(_ e: Exercise, _ uid: String) {
            id = e.id; user_id = uid; name = e.name; body_part = e.bodyPart; target = e.target
            equipment = e.equipment; load_type = e.loadType; thumb = e.thumb
        }
    }
    private struct WorkoutRow: Encodable, Sendable {
        let id: String, user_id: String, name: String, created_at: String?
        init(_ w: Workout, _ uid: String) { id = Sync.id(w.id); user_id = uid; name = w.name; created_at = Sync.s(w.createdAt) }
    }
    private struct SlotRow: Encodable, Sendable {
        let id: String, workout_id: String, user_id: String, position: Int
        let exercise_id: String, exercise_name: String, sets: Int, rep_lo: Int, rep_hi: Int
        init(_ sl: WorkoutSlot, _ w: Workout, _ uid: String) {
            id = Sync.childID(w.id, sl.order, "slot"); workout_id = Sync.id(w.id); user_id = uid
            position = sl.order; exercise_id = sl.exerciseID; exercise_name = sl.exerciseName
            sets = sl.sets; rep_lo = sl.repLo; rep_hi = sl.repHi
        }
    }
    private struct RoutineRow: Encodable, Sendable {
        let id: String, user_id: String, name: String, is_active: Bool, pointer: Int, cycles_completed: Int
        init(_ r: Routine, _ uid: String) {
            id = Sync.id(r.id); user_id = uid; name = r.name
            is_active = r.isActive; pointer = r.pointer; cycles_completed = r.cyclesCompleted
        }
    }
    private struct EntryRow: Encodable, Sendable {
        let id: String, routine_id: String, user_id: String, position: Int, workout_id: String
        init(_ e: RoutineEntry, _ r: Routine, _ uid: String) {
            id = Sync.childID(r.id, e.order, "entry"); routine_id = Sync.id(r.id); user_id = uid
            position = e.order; workout_id = Sync.id(e.workoutID)
        }
    }
    private struct SessionRow: Encodable, Sendable {
        let id: String, user_id: String, workout_id: String?, title: String
        let started_at: String, ended_at: String?, source: String, hevy_key: String?
        let is_draft: Bool, is_started: Bool, rpe: Int?, srpe: Int?, prs: Int?
        let edited: Bool, description: String?
        init(_ s: Session, _ uid: String) {
            id = Sync.id(s.id); user_id = uid; workout_id = s.workoutID.map(Sync.id); title = s.title
            started_at = Sync.s(s.startedAt)!; ended_at = Sync.s(s.endedAt); source = s.source
            hevy_key = s.hevyKey; is_draft = s.isDraft; is_started = s.isStarted
            rpe = s.rpe; srpe = s.srpe; prs = s.prs; edited = s.edited; description = s.note
        }
    }
    private struct SessionExerciseRow: Encodable, Sendable {
        let id: String, session_id: String, user_id: String, position: Int
        let exercise_id: String, exercise_name: String, notes: String?
        init(_ se: SessionExercise, _ s: Session, _ uid: String) {
            id = Sync.childID(s.id, se.order, "sex"); session_id = Sync.id(s.id); user_id = uid
            position = se.order; exercise_id = se.exerciseID; exercise_name = se.exerciseName; notes = se.note
        }
    }
    private struct SetRow: Encodable, Sendable {
        let id: String, session_exercise_id: String, user_id: String, position: Int
        let kind: String, kg: Double?, reps: Int?, seconds: Int?
        let done: Bool, is_pr: Bool, skipped: Bool, distance_km: Double?
        init(_ l: SetLog, _ se: SessionExercise, _ uid: String) {
            let parent = se.session?.id ?? UUID()
            session_exercise_id = Sync.childID(parent, se.order, "sex")
            id = Sync.uuidV5Like("\(parent.uuidString)-set-\(se.order)-\(l.index)")
            user_id = uid; position = l.index; kind = l.type
            kg = l.kg; reps = l.reps; seconds = l.seconds
            done = l.done; is_pr = l.isPR; skipped = l.skipped; distance_km = l.distanceKm
        }
    }
}
