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

        if sets.contains(where: { $0.order < 0 }) {
            sets = sets.enumerated().map { index, set in
                guard set.order < 0 else {
                    return set
                }

                return Set(id: set.id, color: set.color, subsetId: set.subsetId, name: set.name, order: Double(index))
            }

            try saveSets()
        }

        nextSetId = max((sets.map(\.id).max() ?? 0) + 1, 1)
    }

    func addSet(name: String, color: String? = nil, subsetId: Int? = nil, order: Double) throws -> Int {
        let createdSetId = nextSetId

        let newSet = Set(
            id: createdSetId,
            color: color,
            subsetId: subsetId,
            name: name,
            order: order
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

    func moveSet(draggedId: Int, toSubsetId: Int?, order: Double) throws {
        guard let index = sets.firstIndex(where: { $0.id == draggedId }) else {
            return
        }

        if let toSubsetId, isSet(toSubsetId, descendantOfOrEqualTo: draggedId) {
            return
        }

        let draggedSet = sets[index]
        sets[index] = Set(id: draggedSet.id, color: draggedSet.color, subsetId: toSubsetId, name: draggedSet.name, order: order)

        try saveSets()
    }

    private func isSet(_ candidateId: Int, descendantOfOrEqualTo ancestorId: Int) -> Bool {
        var currentId: Int? = candidateId

        while let id = currentId {
            if id == ancestorId {
                return true
            }

            currentId = sets.first(where: { $0.id == id })?.subsetId
        }

        return false
    }

    private func saveSets() throws {
        try JSONRepository.write(sets, to: Self.setsFilename)
    }
}
