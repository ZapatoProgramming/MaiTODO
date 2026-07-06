//
//  ContentView.swift
//  MaiTODO
//
//  Created by Daniel Martínez Maimone on 06/07/26.
//

import SwiftUI
import UniformTypeIdentifiers

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

private func setPath(for set: Set, in sets: [Set]) -> String {
    var names = [set.name]
    var currentParentId = set.subsetId

    while let parentId = currentParentId,
          let parentSet = sets.first(where: { $0.id == parentId }) {
        names.insert(parentSet.name, at: 0)
        currentParentId = parentSet.subsetId
    }

    return names.joined(separator: " - ")
}

private struct TodoReorderDropDelegate: DropDelegate {
    let targetTodoId: Int
    let todoService: TodoService

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let idString = reading as? String, let draggedId = Int(idString) else {
                return
            }

            DispatchQueue.main.async {
                do {
                    try todoService.moveTodo(draggedId: draggedId, beforeId: targetTodoId)
                } catch {
                    print("Failed to reorder todo: \(error)")
                }
            }
        }

        return true
    }
}

private struct TodoSetDropDelegate: DropDelegate {
    let setId: Int?
    let todoService: TodoService

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let idString = reading as? String, let draggedId = Int(idString) else {
                return
            }

            DispatchQueue.main.async {
                do {
                    try todoService.moveTodo(draggedId: draggedId, toSetId: setId)
                } catch {
                    print("Failed to move todo: \(error)")
                }
            }
        }

        return true
    }
}

struct AddTodoUI: View {
    @StateObject private var todoService = TodoService.shared
    @State private var todoContent: String = ""
    @State private var selectedSetId: Int? = nil

    private var availableSets: [Set] {
        todoService.sets
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
                    Text(setPath(for: set, in: availableSets))
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
}

struct SetUI: View {
    @ObservedObject private var todoService = TodoService.shared
    let sets: [Set]
    let todos: [Todo]

    @State private var collapsedSetIds: Swift.Set<Int> = []
    @State private var isDoneCollapsed = false

    private var setIds: Swift.Set<Int> {
        Swift.Set(sets.map(\.id))
    }

    private var topLevelSets: [Set] {
        sets
            .filter { set in
                guard let subsetId = set.subsetId else {
                    return true
                }

                return !setIds.contains(subsetId)
            }
            .sorted { $0.id < $1.id }
    }

    private var todosWithoutSet: [Todo] {
        todos.filter { $0.setId == nil && !$0.done }
    }

    private var doneTodos: [Todo] {
        todos.filter(\.done)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Inbox")
                    .font(.headline)

                ForEach(todosWithoutSet) { todo in
                    TodoUI(todo: todo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onDrop(of: [.text], delegate: TodoSetDropDelegate(setId: nil, todoService: todoService))

            ForEach(topLevelSets) { set in
                setSection(for: set, indentLevel: 0)
            }

            if !doneTodos.isEmpty {
                doneSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    isDoneCollapsed.toggle()
                } label: {
                    Image(systemName: isDoneCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDoneCollapsed ? "Expand Done" : "Collapse Done")

                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#34C759"))
                    .clipShape(Capsule())
            }

            if !isDoneCollapsed {
                ForEach(doneTodos) { todo in
                    TodoUI(todo: todo)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "#34C759").opacity(0.55), lineWidth: 2)
        }
    }

    private func setSection(for set: Set, indentLevel: Int) -> AnyView {
        let isCollapsed = collapsedSetIds.contains(set.id)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        toggleCollapsed(set.id)
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed ? "Expand set" : "Collapse set")

                    Text(set.name)
                        .font(.headline)

                    Spacer()

                    Menu {
                        Button("Delete", role: .destructive) {
                            deleteSet(set.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Set options")
                }

                if !isCollapsed {
                    ForEach(todos.filter { $0.setId == set.id && !$0.done }) { todo in
                        TodoUI(todo: todo)
                    }

                    ForEach(childSets(of: set)) { childSet in
                        setSection(for: childSet, indentLevel: indentLevel + 1)
                    }
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
            .onDrop(of: [.text], delegate: TodoSetDropDelegate(setId: set.id, todoService: todoService))
        )
    }

    private func childSets(of set: Set) -> [Set] {
        sets
            .filter { $0.subsetId == set.id }
            .sorted { $0.id < $1.id }
    }

    private func deleteSet(_ id: Int) {
        do {
            try todoService.deleteSet(id: id)
        } catch {
            print("Failed to delete set: \(error)")
        }
    }

    private func toggleCollapsed(_ id: Int) {
        if collapsedSetIds.contains(id) {
            collapsedSetIds.remove(id)
        } else {
            collapsedSetIds.insert(id)
        }
    }
}

struct TodoUI: View {
    @ObservedObject private var todoService = TodoService.shared
    let todo: Todo

    @State private var isEditing = false
    @State private var editedContent = ""
    @FocusState private var isContentFocused: Bool

    private var availableSets: [Set] {
        todoService.sets.sorted { $0.id < $1.id }
    }

    var body: some View {
        HStack {
            Button {
                toggleDone()
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.done ? Color(hex: "#34C759") : .secondary)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.done ? "Undo todo" : "Mark todo as done")

            if isEditing {
                TextField("Content", text: $editedContent)
                    .textFieldStyle(.roundedBorder)
                    .focused($isContentFocused)
                    .onSubmit {
                        commitEdit()
                    }
                    .onChange(of: isContentFocused) { _, focused in
                        if !focused {
                            commitEdit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(todo.content)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
                    .onDrag {
                        NSItemProvider(object: String(todo.id) as NSString)
                    }
                    .onDrop(of: [.text], delegate: TodoReorderDropDelegate(targetTodoId: todo.id, todoService: todoService))
            }

            if todo.setId == nil, !availableSets.isEmpty {
                Menu {
                    ForEach(availableSets) { set in
                        Button(setPath(for: set, in: availableSets)) {
                            assignToSet(set.id)
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Assign todo to a set")
            }

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

    private func toggleDone() {
        do {
            if todo.done {
                try todoService.undoTodo(id: todo.id)
            } else {
                try todoService.markTodoAsDone(id: todo.id)
            }
        } catch {
            print("Failed to update todo: \(error)")
        }
    }

    private func assignToSet(_ setId: Int) {
        do {
            try todoService.updateTodo(
                Todo(id: todo.id, setId: setId, content: todo.content, done: todo.done)
            )
        } catch {
            print("Failed to assign todo to set: \(error)")
        }
    }

    private func startEditing() {
        editedContent = todo.content
        isEditing = true
        isContentFocused = true
    }

    private func commitEdit() {
        guard isEditing else {
            return
        }

        isEditing = false

        let trimmedContent = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedContent.isEmpty, trimmedContent != todo.content else {
            return
        }

        do {
            try todoService.updateTodo(
                Todo(id: todo.id, setId: todo.setId, content: trimmedContent, done: todo.done)
            )
        } catch {
            print("Failed to update todo content: \(error)")
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
        todoService.sets.sorted { $0.id < $1.id }
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
                    Text(setPath(for: set, in: availableParentSets))
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
