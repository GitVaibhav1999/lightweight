import Foundation
import SwiftData

/// Exercise library seed (data/exercises.json, built from hasaneyldrm/exercises-dataset) and the Hevy alias map.
enum Seed {
    struct Record: Decodable { let id, name, bodyPart, target, equipment, loadType: String; let thumb: String? }
    struct Alias: Decodable { let id: String?; let name: String? }

    static func loadExercises() -> [Record] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }
    static func loadAliases() -> [String: Alias] {
        guard let url = Bundle.main.url(forResource: "hevy_aliases", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Alias].self, from: data)) ?? [:]
    }

    @MainActor static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard count == 0 else { return }
        for r in loadExercises() {
            context.insert(Exercise(id: r.id, name: r.name, bodyPart: r.bodyPart, target: r.target, equipment: r.equipment, loadType: r.loadType, thumb: r.thumb, source: "dataset"))
        }
        try? context.save()
    }
}
