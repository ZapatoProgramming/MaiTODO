import Foundation
import Combine

@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    private static let todosFilename = "todo.json"

    @Published private(set) var todos: [Todo] = []

    private var nextTodoId = 1

    private init() {}

    func load() throws {
        todos = try JSONRepository.read(Todo.self, from: Self.todosFilename)

        if todos.contains(where: { $0.order < 0 }) {
            todos = todos.enumerated().map { index, todo in
                guard todo.order < 0 else {
                    return todo
                }

                return Todo(id: todo.id, setId: todo.setId, content: todo.content, done: todo.done, order: Double(index))
            }

            try saveTodos()
        }

        nextTodoId = (todos.map(\.id).max() ?? 0) + 1
    }

    func addTodo(content: String, setId: Int? = nil, order: Double) throws {
        let newTodo = Todo(
            id: nextTodoId,
            setId: setId,
            content: content,
            done: false,
            order: order
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
            done: true,
            order: todos[index].order
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
            done: false,
            order: todos[index].order
        )

        try saveTodos()
    }

    func updateTodo(_ updatedTodo: Todo) throws {
        guard let index = todos.firstIndex(where: { $0.id == updatedTodo.id }) else {
            return
        }

        todos[index] = updatedTodo
        try saveTodos()
    }

    func moveTodo(draggedId: Int, toSetId: Int?, order: Double) throws {
        guard let index = todos.firstIndex(where: { $0.id == draggedId }) else {
            return
        }

        let draggedTodo = todos[index]
        todos[index] = Todo(id: draggedTodo.id, setId: toSetId, content: draggedTodo.content, done: draggedTodo.done, order: order)

        try saveTodos()
    }

    func deleteTodo(id: Int) throws {
        todos.removeAll { $0.id == id }
        try saveTodos()
    }

    private func saveTodos() throws {
        try JSONRepository.write(todos, to: Self.todosFilename)
    }
}
