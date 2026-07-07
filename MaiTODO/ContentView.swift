//
//  ContentView.swift
//  MaiTODO
//
//  Created by Daniel Martínez Maimone on 06/07/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var setStore = SetStore.shared
    @StateObject private var todoStore = TodoStore.shared
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
            SetUI(sets: setStore.sets, todos: todoStore.todos)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 12)
        .padding()
        .sheet(isPresented: $isCreateSetModalPresented) {
            CreateSetModal()
        }
        .onAppear {
            do {
                try setStore.load()
                try todoStore.load()
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

private enum DragPayload {
    private static let todoPrefix = "todo-"
    private static let setPrefix = "set-"

    static func todo(id: Int) -> String {
        todoPrefix + String(id)
    }

    static func set(id: Int) -> String {
        setPrefix + String(id)
    }

    static func todoId(from payload: String) -> Int? {
        guard payload.hasPrefix(todoPrefix) else {
            return nil
        }

        return Int(payload.dropFirst(todoPrefix.count))
    }

    static func setId(from payload: String) -> Int? {
        guard payload.hasPrefix(setPrefix) else {
            return nil
        }

        return Int(payload.dropFirst(setPrefix.count))
    }
}

/// A todo or a set, ordered against each other so a set can render between two todos.
private enum OrderedChild: Identifiable {
    case todo(Todo)
    case set(Set)

    var id: String {
        switch self {
        case .todo(let todo): return DragPayload.todo(id: todo.id)
        case .set(let set): return DragPayload.set(id: set.id)
        }
    }

    var order: Double {
        switch self {
        case .todo(let todo): return todo.order
        case .set(let set): return set.order
        }
    }

    var todoId: Int? {
        if case .todo(let todo) = self {
            return todo.id
        }

        return nil
    }

    var setId: Int? {
        if case .set(let set) = self {
            return set.id
        }

        return nil
    }
}

/// Combines the not-done todos and child sets that live directly under `parentId` into one ordered list.
/// `parentId == nil` means top-level; a set whose declared parent no longer exists is treated as top-level too.
private func combinedChildren(sets: [Set], todos: [Todo], parentId: Int?) -> [OrderedChild] {
    let childTodos = todos.filter { $0.setId == parentId && !$0.done }

    let childSets: [Set]
    if let parentId {
        childSets = sets.filter { $0.subsetId == parentId }
    } else {
        let setIds = Swift.Set(sets.map(\.id))
        childSets = sets.filter { set in
            guard let subsetId = set.subsetId else {
                return true
            }

            return !setIds.contains(subsetId)
        }
    }

    return (childTodos.map(OrderedChild.todo) + childSets.map(OrderedChild.set))
        .sorted { $0.order < $1.order }
}

/// A fractional order key that sorts immediately before `target`, without needing to renumber any siblings.
private func orderForInsertion(before target: OrderedChild, siblings: [OrderedChild]) -> Double {
    guard let targetIndex = siblings.firstIndex(where: { $0.id == target.id }), targetIndex > 0 else {
        return target.order - 1
    }

    return (siblings[targetIndex - 1].order + target.order) / 2
}

private func orderForAppend(after siblings: [OrderedChild]) -> Double {
    (siblings.map(\.order).max() ?? -1) + 1
}

private enum DropIndicator: Equatable {
    case before(String)
    case insideSet(Int?)
}

/// Handles an imprecise drop anywhere in a set's body (or the Inbox): nests a dragged set as a child,
/// or assigns a dragged todo to it, appending it after the scope's current last item.
private struct SetDropDelegate: DropDelegate {
    let targetSetId: Int?
    let sets: [Set]
    let todos: [Todo]
    let setStore: SetStore
    let todoStore: TodoStore
    @Binding var dropIndicator: DropIndicator?

    func dropEntered(info: DropInfo) {
        dropIndicator = .insideSet(targetSetId)
    }

    func dropExited(info: DropInfo) {
        if dropIndicator == .insideSet(targetSetId) {
            dropIndicator = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        dropIndicator = nil

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let payload = reading as? String else {
                return
            }

            DispatchQueue.main.async {
                let siblings = combinedChildren(sets: sets, todos: todos, parentId: targetSetId)
                let newOrder = orderForAppend(after: siblings)

                if let draggedTodoId = DragPayload.todoId(from: payload) {
                    do {
                        try todoStore.moveTodo(draggedId: draggedTodoId, toSetId: targetSetId, order: newOrder)
                    } catch {
                        print("Failed to move todo: \(error)")
                    }
                } else if let draggedSetId = DragPayload.setId(from: payload) {
                    do {
                        try setStore.moveSet(draggedId: draggedSetId, toSubsetId: targetSetId, order: newOrder)
                    } catch {
                        print("Failed to move set: \(error)")
                    }
                }
            }
        }

        return true
    }
}

/// Handles a precise drop onto a specific todo or set: positions the dragged item immediately
/// before `target`, adopting target's parent scope. Works for any combination of dragged/target kinds,
/// which is what lets a set land between two todos (or vice versa).
private struct ReorderDropDelegate: DropDelegate {
    let target: OrderedChild
    let siblings: [OrderedChild]
    let sets: [Set]
    let todos: [Todo]
    let setStore: SetStore
    let todoStore: TodoStore
    @Binding var dropIndicator: DropIndicator?

    private var targetParentId: Int? {
        switch target {
        case .todo(let todo): return todo.setId
        case .set(let set): return set.subsetId
        }
    }

    func dropEntered(info: DropInfo) {
        dropIndicator = .before(target.id)
    }

    func dropExited(info: DropInfo) {
        if dropIndicator == .before(target.id) {
            dropIndicator = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        dropIndicator = nil

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let payload = reading as? String else {
                return
            }

            DispatchQueue.main.async {
                let newOrder = orderForInsertion(before: target, siblings: siblings)

                if let draggedTodoId = DragPayload.todoId(from: payload) {
                    guard draggedTodoId != target.todoId else {
                        return
                    }

                    do {
                        try todoStore.moveTodo(draggedId: draggedTodoId, toSetId: targetParentId, order: newOrder)
                    } catch {
                        print("Failed to reorder todo: \(error)")
                    }
                } else if let draggedSetId = DragPayload.setId(from: payload) {
                    guard draggedSetId != target.setId else {
                        return
                    }

                    do {
                        try setStore.moveSet(draggedId: draggedSetId, toSubsetId: targetParentId, order: newOrder)
                    } catch {
                        print("Failed to reorder set: \(error)")
                    }
                }
            }
        }

        return true
    }
}

struct AddTodoUI: View {
    @ObservedObject private var setStore = SetStore.shared
    private let todoStore = TodoStore.shared
    @State private var todoContent: String = ""
    @State private var selectedSetId: Int? = nil

    private var availableSets: [Set] {
        setStore.sets
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
            let siblings = combinedChildren(sets: setStore.sets, todos: todoStore.todos, parentId: selectedSetId)

            try todoStore.addTodo(
                content: trimmedContent,
                setId: selectedSetId,
                order: orderForAppend(after: siblings)
            )

            todoContent = ""
        } catch {
            print("Failed to create todo \(error)")
        }
    }
}

struct SetUI: View {
    private let setStore = SetStore.shared
    private let todoStore = TodoStore.shared
    let sets: [Set]
    let todos: [Todo]

    @State private var collapsedSetIds: Swift.Set<Int> = []
    @State private var isDoneCollapsed = false
    @State private var dropIndicator: DropIndicator?

    private var topLevelChildren: [OrderedChild] {
        combinedChildren(sets: sets, todos: todos, parentId: nil)
    }

    private var doneTodos: [Todo] {
        todos.filter(\.done)
    }

    private var doneChildren: [OrderedChild] {
        doneTodos.map(OrderedChild.todo).sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Inbox")
                    .font(.headline)

                ForEach(topLevelChildren) { child in
                    switch child {
                    case .todo(let todo):
                        TodoUI(todo: todo, todos: todos, siblings: topLevelChildren, dropIndicator: $dropIndicator)
                    case .set(let set):
                        SetSectionView(set: set, sets: sets, todos: todos, siblings: topLevelChildren, indentLevel: 0, collapsedSetIds: $collapsedSetIds, dropIndicator: $dropIndicator)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(dropIndicator == .insideSet(nil) ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.15), value: dropIndicator)
            .onDrop(of: [.text], delegate: SetDropDelegate(targetSetId: nil, sets: sets, todos: todos, setStore: setStore, todoStore: todoStore, dropIndicator: $dropIndicator))

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
                    TodoUI(todo: todo, todos: todos, siblings: doneChildren, dropIndicator: $dropIndicator)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "#34C759").opacity(0.55), lineWidth: 2)
        }
    }
}

private struct SetSectionView: View {
    private let setStore = SetStore.shared
    private let todoStore = TodoStore.shared
    let set: Set
    let sets: [Set]
    let todos: [Todo]
    let siblings: [OrderedChild]
    let indentLevel: Int
    @Binding var collapsedSetIds: Swift.Set<Int>
    @Binding var dropIndicator: DropIndicator?

    private var isCollapsed: Bool {
        collapsedSetIds.contains(set.id)
    }

    private var children: [OrderedChild] {
        combinedChildren(sets: sets, todos: todos, parentId: set.id)
    }

    private var showsReorderSeparator: Bool {
        dropIndicator == .before(DragPayload.set(id: set.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsReorderSeparator {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .padding(.leading, CGFloat(indentLevel) * 24)
            }

            sectionBox
        }
        .animation(.easeInOut(duration: 0.15), value: dropIndicator)
    }

    private var sectionBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    toggleCollapsed()
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "Expand set" : "Collapse set")

                Text(set.name)
                    .font(.headline)
                    .onDrag {
                        NSItemProvider(object: DragPayload.set(id: set.id) as NSString)
                    }
                    .onDrop(of: [.text], delegate: ReorderDropDelegate(target: .set(set), siblings: siblings, sets: sets, todos: todos, setStore: setStore, todoStore: todoStore, dropIndicator: $dropIndicator))

                Spacer()

                Menu {
                    Button("Delete", role: .destructive) {
                        deleteSet()
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
                ForEach(children) { child in
                    switch child {
                    case .todo(let todo):
                        TodoUI(todo: todo, todos: todos, siblings: children, dropIndicator: $dropIndicator)
                    case .set(let childSet):
                        SetSectionView(set: childSet, sets: sets, todos: todos, siblings: children, indentLevel: indentLevel + 1, collapsedSetIds: $collapsedSetIds, dropIndicator: $dropIndicator)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDropTarget ? Color.accentColor : Color(hex: set.color ?? "#D1D1D6").opacity(0.55), lineWidth: isDropTarget ? 3 : 2)
        }
        .animation(.easeInOut(duration: 0.15), value: dropIndicator)
        .padding(.leading, CGFloat(indentLevel) * 24)
        .onDrop(of: [.text], delegate: SetDropDelegate(targetSetId: set.id, sets: sets, todos: todos, setStore: setStore, todoStore: todoStore, dropIndicator: $dropIndicator))
    }

    private var isDropTarget: Bool {
        dropIndicator == .insideSet(set.id)
    }

    private func deleteSet() {
        do {
            try setStore.deleteSet(id: set.id)
        } catch {
            print("Failed to delete set: \(error)")
        }
    }

    private func toggleCollapsed() {
        if collapsedSetIds.contains(set.id) {
            collapsedSetIds.remove(set.id)
        } else {
            collapsedSetIds.insert(set.id)
        }
    }
}

struct TodoUI: View {
    @ObservedObject private var setStore = SetStore.shared
    private let todoStore = TodoStore.shared
    let todo: Todo
    let todos: [Todo]
    fileprivate let siblings: [OrderedChild]
    @Binding fileprivate var dropIndicator: DropIndicator?

    @State private var isEditing = false
    @State private var editedContent = ""
    @FocusState private var isContentFocused: Bool

    private var availableSets: [Set] {
        setStore.sets.sorted { $0.id < $1.id }
    }

    private var showsDropSeparator: Bool {
        dropIndicator == .before(DragPayload.todo(id: todo.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsDropSeparator {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }

            todoRow
        }
        .animation(.easeInOut(duration: 0.15), value: dropIndicator)
    }

    private var todoRow: some View {
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
                        NSItemProvider(object: DragPayload.todo(id: todo.id) as NSString)
                    }
                    .onDrop(of: [.text], delegate: ReorderDropDelegate(target: .todo(todo), siblings: siblings, sets: setStore.sets, todos: todos, setStore: setStore, todoStore: todoStore, dropIndicator: $dropIndicator))
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
                    try todoStore.deleteTodo(id: todo.id)
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
                try todoStore.undoTodo(id: todo.id)
            } else {
                try todoStore.markTodoAsDone(id: todo.id)
            }
        } catch {
            print("Failed to update todo: \(error)")
        }
    }

    private func assignToSet(_ setId: Int) {
        do {
            let scopeSiblings = combinedChildren(sets: setStore.sets, todos: todos, parentId: setId)

            try todoStore.updateTodo(
                Todo(id: todo.id, setId: setId, content: todo.content, done: todo.done, order: orderForAppend(after: scopeSiblings))
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
            try todoStore.updateTodo(
                Todo(id: todo.id, setId: todo.setId, content: trimmedContent, done: todo.done, order: todo.order)
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
    @ObservedObject private var setStore = SetStore.shared

    @State private var setName = ""
    @State private var parentSetId: Int? = nil
    @State private var selectedColor = Color(hex: "#007AFF")

    private var availableParentSets: [Set] {
        setStore.sets.sorted { $0.id < $1.id }
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
            let siblings = combinedChildren(sets: setStore.sets, todos: TodoStore.shared.todos, parentId: parentSetId)

            _ = try setStore.addSet(
                name: setName.trimmingCharacters(in: .whitespacesAndNewlines),
                color: selectedColor.toHex() ?? "#007AFF",
                subsetId: parentSetId,
                order: orderForAppend(after: siblings)
            )
            dismiss()
        } catch {
            print("Failed to create set: \(error)")
        }
    }
}
