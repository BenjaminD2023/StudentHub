import SwiftUI

/// Bottom-sheet inspector for a single task. Uses `.medium` and
/// `.large` detents so users can keep the list as context.
struct IPhoneTaskInspectorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let taskID: UUID

    @State private var draft: HubTask?
    @State private var newSubtaskTitle: String = ""

    private var task: HubTask? { appState.tasks.first(where: { $0.id == taskID }) }

    private var subtasks: [HubTask] {
        appState.tasks.filter { $0.parentTaskID == taskID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section("Title") {
                            TextField("Task title", text: Binding(
                                get: { draft.title },
                                set: { newValue in
                                    var d = draft
                                    d.title = newValue
                                    self.draft = d
                                }
                            ))
                        }

                        Section("Space") {
                            Picker("Space", selection: Binding(
                                get: { draft.course },
                                set: { newValue in
                                    var d = draft
                                    d.course = newValue
                                    self.draft = d
                                }
                            )) {
                                ForEach(appState.spaces) { space in
                                    Text(space.title).tag(space)
                                }
                            }
                        }

                        Section("Due") {
                            DatePicker("Due", selection: Binding(
                                get: { draft.dueDate },
                                set: { newValue in
                                    var d = draft
                                    d.dueDate = newValue
                                    self.draft = d
                                }
                            ), displayedComponents: [.date, .hourAndMinute])
                        }

                        Section("Details") {
                            TextField("Notes", text: Binding(
                                get: { draft.details },
                                set: { newValue in
                                    var d = draft
                                    d.details = newValue
                                    self.draft = d
                                }
                            ), axis: .vertical)
                            .lineLimit(3...8)
                        }

                        if !subtasks.isEmpty {
                            Section("Subtasks") {
                                ForEach(subtasks) { sub in
                                    HStack {
                                        Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(sub.isCompleted ? HubPalette.success : HubPalette.hubAccent)
                                        Text(sub.title)
                                            .strikethrough(sub.isCompleted)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { appState.toggleComplete(sub.id) }
                                }
                            }
                        }

                        Section {
                            HStack {
                                TextField("Add subtask", text: $newSubtaskTitle)
                                Button {
                                    let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    _ = appState.addTask(
                                        title: trimmed,
                                        course: draft.course,
                                        dueDate: draft.dueDate,
                                        parentTaskID: draft.id
                                    )
                                    newSubtaskTitle = ""
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } header: {
                            Text("New subtask")
                        }

                        Section {
                            Button(role: .destructive) {
                                appState.deleteTask(draft.id)
                                dismiss()
                            } label: {
                                Label("Delete task", systemImage: "trash")
                                    .foregroundStyle(HubPalette.red)
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Task not found",
                        message: "It may have been deleted from another device."
                    )
                }
            }
            .navigationTitle("Task")
            #if os(iOS)
            #if os(iOS)

            .navigationBarTitleDisplayMode(.inline)

            #endif
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let draft { appState.updateTask(draft) }
                        dismiss()
                    }
                    .disabled(draft == nil)
                }
            }
            .onAppear {
                if draft == nil { draft = task }
            }
            .onChange(of: taskID) { _, _ in
                draft = task
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
