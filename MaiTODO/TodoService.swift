import Foundation
import Combine

@MainActor
final class TodoService: ObservableObject {
    static let shared = TodoService()

    private static let setsFilename = "sets.json"
    private static let todosFilename = "todo.json"
    private static let legacyDoneSetId = -1

    @Published private(set) var sets: [Set] = []
    @Published private(set) var todos: [Todo] = []

    private var nextSetId = 1
    private var nextTodoId = 1

    private init() {}

    func load() throws {
        sets = try JSONRepository.read(Set.self, from: Self.setsFilename)
        todos = try JSONRepository.read(Todo.self, from: Self.todosFilename)

        if sets.contains(where: { $0.id == Self.legacyDoneSetId }) {
            sets.removeAll { $0.id == Self.legacyDoneSetId }
            try saveSets()
        }

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
            content: content,
            done: false
        )

        nextTodoId += 1
        todos.append(newTodo)

        try saveTodos()
    }

    func markTodoAsDone(id: Int) throws {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }

        todos[index] = Todo(
            id: todos[index].id,
            setId: todos[index].setId,
            content: todos[index].content,
            done: true
        )

        try saveTodos()
    }

    func undoTodo(id: Int) throws {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }

        todos[index] = Todo(
            id: todos[index].id,
            setId: todos[index].setId,
            content: todos[index].content,
            done: false
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

    func moveTodo(draggedId: Int, beforeId: Int) throws {
        guard draggedId != beforeId,
              let draggedIndex = todos.firstIndex(where: { $0.id == draggedId }),
              let targetSetId = todos.first(where: { $0.id == beforeId })?.setId else {
            return
        }

        var draggedTodo = todos[draggedIndex]
        todos.remove(at: draggedIndex)

        if draggedTodo.setId != targetSetId {
            draggedTodo = Todo(id: draggedTodo.id, setId: targetSetId, content: draggedTodo.content, done: draggedTodo.done)
        }

        let insertionIndex = todos.firstIndex(where: { $0.id == beforeId }) ?? todos.count
        todos.insert(draggedTodo, at: insertionIndex)

        try saveTodos()
    }

    func moveTodo(draggedId: Int, toSetId: Int?) throws {
        guard let index = todos.firstIndex(where: { $0.id == draggedId }) else {
            return
        }

        var draggedTodo = todos[index]

        guard draggedTodo.setId != toSetId else {
            return
        }

        todos.remove(at: index)
        draggedTodo = Todo(id: draggedTodo.id, setId: toSetId, content: draggedTodo.content, done: draggedTodo.done)
        todos.append(draggedTodo)

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

    private func saveSets() throws {
        try JSONRepository.write(sets, to: Self.setsFilename)
    }

    private func saveTodos() throws {
        try JSONRepository.write(todos, to: Self.todosFilename)
    }
}
