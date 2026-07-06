import Foundation
import Combine

@MainActor
final class TodoService: ObservableObject {
    static let shared = TodoService()

    private static let setsFilename = "sets.json"
    private static let todosFilename = "todo.json"
    private static let doneSetId = -1
    private static let doneSetName = "Done"
    private static let doneSetColor = "#34C759"

    @Published private(set) var sets: [Set] = []
    @Published private(set) var todos: [Todo] = []

    private var nextSetId = 1
    private var nextTodoId = 1

    private init() {}

    func load() throws {
        sets = try JSONRepository.read(Set.self, from: Self.setsFilename)
        todos = try JSONRepository.read(Todo.self, from: Self.todosFilename)

        try ensureDoneSetExists()

        nextSetId = max((sets.map(\.id).max() ?? 0) + 1, 1)
        nextTodoId = (todos.map(\.id).max() ?? 0) + 1
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

    func addTodo(content: String, setId: Int? = nil) throws {
        let newTodo = Todo(
            id: nextTodoId,
            setId: setId,
            content: content
        )

        nextTodoId += 1
        todos.append(newTodo)

        try saveTodos()
    }

    func markTodoAsDone(id: Int) throws {
        try ensureDoneSetExists()

        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }

        todos[index] = Todo(
            id: todos[index].id,
            setId: Self.doneSetId,
            content: todos[index].content
        )

        try saveTodos()
    }

    func updateSet(_ updatedSet: Set) throws {
        guard let index = sets.firstIndex(where: { $0.id == updatedSet.id }) else {
            return
        }

        sets[index] = updatedSet
        try saveSets()
    }

    func updateTodo(_ updatedTodo: Todo) throws {
        guard let index = todos.firstIndex(where: { $0.id == updatedTodo.id }) else {
            return
        }

        todos[index] = updatedTodo
        try saveTodos()
    }

    func deleteSet(id: Int) throws {
        sets.removeAll { $0.id == id }
        try saveSets()
    }

    func deleteTodo(id: Int) throws {
        todos.removeAll { $0.id == id }
        try saveTodos()
    }

    private func ensureDoneSetExists() throws {
        guard !sets.contains(where: { $0.id == Self.doneSetId }) else {
            return
        }

        let doneSet = Set(
            id: Self.doneSetId,
            color: Self.doneSetColor,
            subsetId: nil,
            name: Self.doneSetName
        )

        sets.insert(doneSet, at: 0)
        try saveSets()
    }

    private func saveSets() throws {
        try JSONRepository.write(sets, to: Self.setsFilename)
    }

    private func saveTodos() throws {
        try JSONRepository.write(todos, to: Self.todosFilename)
    }
}
