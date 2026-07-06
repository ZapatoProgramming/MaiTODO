//
//  ContentView.swift
//  MaiTODO
//
//  Created by Daniel Martínez Maimone on 06/07/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var todoService = TodoService.shared
    @State private var isCreateSetModalPresented = false
    
    var body: some View {
        VStack {
            HStack {
                Button("New Set") {
                    isCreateSetModalPresented = true
                }

                Spacer()
            }
            .padding(.horizontal)

            AddTodoUI()
            SetUI(sets: todoService.sets, todos: todoService.todos)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 12)
        .padding()
        .sheet(isPresented: $isCreateSetModalPresented) {
            CreateSetModal()
        }
        .onAppear {
            do {
                try todoService.load()
            } catch {
                print("Failed to load todos: \(error)")
            }
        }
    }
}

struct AddTodoUI: View {
    @StateObject private var todoService = TodoService.shared
    @State private var todoContent: String = ""
    @State private var selectedSetId: Int? = nil

    private var availableSets: [Set] {
        todoService.sets
            .filter { $0.id != -1 }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        HStack {
            TextField("...", text: $todoContent)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addTodo()
                }

            Picker("Set", selection: $selectedSetId) {
                Text("Inbox")
                    .tag(nil as Int?)

                ForEach(availableSets) { set in
                    Text(setPath(for: set))
                        .tag(set.id as Int?)
                }
            }
            .frame(width: 220)

            Button("Add new todo") {
                addTodo()
            }
            .disabled(todoContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func addTodo() {
        let trimmedContent = todoContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedContent.isEmpty else {
            return
        }

        do {
            try todoService.addTodo(
                content: trimmedContent,
                setId: selectedSetId
            )

            todoContent = ""
        } catch {
            print("Failed to create todo \(error)")
        }
    }

    private func setPath(for set: Set) -> String {
        var names = [set.name]
        var currentParentId = set.subsetId

        while let parentId = currentParentId,
              let parentSet = availableSets.first(where: { $0.id == parentId }) {
            names.insert(parentSet.name, at: 0)
            currentParentId = parentSet.subsetId
        }

        return names.joined(separator: " - ")
    }
}

struct SetUI: View {
    let sets: [Set]
    let todos: [Todo]

    private var doneSet: Set? {
        sets.first { $0.id == -1 }
    }

    private var normalSets: [Set] {
        sets.filter { $0.id != -1 }
    }

    private var normalSetIds: Swift.Set<Int> {
        Swift.Set(normalSets.map(\.id))
    }

    private var topLevelSets: [Set] {
        normalSets
            .filter { set in
                guard let subsetId = set.subsetId else {
                    return true
                }

                return !normalSetIds.contains(subsetId)
            }
            .sorted { $0.id < $1.id }
    }

    private var todosWithoutSet: [Todo] {
        todos.filter { $0.setId == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !todosWithoutSet.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inbox")
                        .font(.headline)

                    ForEach(todosWithoutSet) { todo in
                        TodoUI(todo: todo)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(topLevelSets) { set in
                setSection(for: set, indentLevel: 0)
            }

            if let doneSet {
                setSection(for: doneSet, indentLevel: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setSection(for set: Set, indentLevel: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                setHeader(for: set)

                ForEach(todos.filter { $0.setId == set.id }) { todo in
                    TodoUI(todo: todo)
                }

                ForEach(childSets(of: set)) { childSet in
                    setSection(for: childSet, indentLevel: indentLevel + 1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: set.color ?? "#D1D1D6").opacity(0.55), lineWidth: 2)
            }
            .padding(.leading, CGFloat(indentLevel) * 24)
        )
    }

    private func childSets(of set: Set) -> [Set] {
        normalSets
            .filter { $0.subsetId == set.id }
            .sorted { $0.id < $1.id }
    }

    @ViewBuilder
    private func setHeader(for set: Set) -> some View {
        if set.id == -1 {
            Text(set.name)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: set.color ?? "#34C759"))
                .clipShape(Capsule())
        } else {
            Text(set.name)
                .font(.headline)
        }
    }
}

struct TodoUI: View {
    @ObservedObject private var todoService = TodoService.shared
    let todo: Todo
    private var isDone: Bool {
        todo.setId == -1
    }

    var body: some View {
        HStack {
            Button {
                markTodoAsDone()
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color(hex: "#34C759") : .secondary)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(isDone)
            .accessibilityLabel(isDone ? "Todo completed" : "Mark todo as done")

            Text(todo.content)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                do {
                    try todoService.deleteTodo(id: todo.id)
                } catch {
                    print("Failed to delete todo: \(error)")
                }

            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete todo")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func markTodoAsDone() {
        do {
            try todoService.markTodoAsDone(id: todo.id)
        } catch {
            print("Failed to mark todo as done: \(error)")
        }
    }

}


extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }

    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

#Preview {
    ContentView()
}


struct CreateSetModal: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var todoService = TodoService.shared

    @State private var setName = ""
    @State private var parentSetId: Int? = nil
    @State private var selectedColor = Color(hex: "#007AFF")

    private var availableParentSets: [Set] {
        todoService.sets.filter { $0.id != -1 }
    }

    private var isSetNameEmpty: Bool {
        setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Set")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Set name", text: $setName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    createSet()
                }

            Picker("Parent", selection: $parentSetId) {
                Text("No parent")
                    .tag(nil as Int?)

                ForEach(availableParentSets) { set in
                    Text(set.name)
                        .tag(set.id as Int?)
                }
            }

            ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Create") {
                    createSet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSetNameEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func createSet() {
        guard !isSetNameEmpty else {
            return
        }

        do {
            _ = try todoService.addSet(
                name: setName.trimmingCharacters(in: .whitespacesAndNewlines),
                color: selectedColor.toHex() ?? "#007AFF",
                subsetId: parentSetId
            )
            dismiss()
        } catch {
            print("Failed to create set: \(error)")
        }
    }
}
