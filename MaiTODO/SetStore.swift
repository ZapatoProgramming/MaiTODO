import Foundation
import Combine

@MainActor
final class SetStore: ObservableObject {
    static let shared = SetStore()

    private static let setsFilename = "sets.json"
    private static let legacyDoneSetId = -1

    @Published private(set) var sets: [Set] = []

    private var nextSetId = 1

    private init() {}

    func load() throws {
        sets = try JSONRepository.read(Set.self, from: Self.setsFilename)

        if sets.contains(where: { $0.id == Self.legacyDoneSetId }) {
            sets.removeAll { $0.id == Self.legacyDoneSetId }
            try saveSets()
        }

        nextSetId = max((sets.map(\.id).max() ?? 0) + 1, 1)
    }

    func addSet(name: String, color: String? = nil, subsetId: Int? = nil) throws -> Int {
        let createdSetId = nextSetId

        let newSet = Set(
            id: createdSetId,
            color: color,
            subsetId: subsetId,
            name: name
        )

        nextSetId += 1
        sets.append(newSet)

        try saveSets()
        return createdSetId
    }

    func updateSet(_ updatedSet: Set) throws {
        guard let index = sets.firstIndex(where: { $0.id == updatedSet.id }) else {
            return
        }

        sets[index] = updatedSet
        try saveSets()
    }

    func deleteSet(id: Int) throws {
        sets.removeAll { $0.id == id }
        try saveSets()
    }

    private func saveSets() throws {
        try JSONRepository.write(sets, to: Self.setsFilename)
    }
}
