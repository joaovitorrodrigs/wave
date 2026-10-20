import SwiftUI

struct NotesView: View {
    @State private var notes = Notes()
    @State private var query = ""
    @State private var adding = false

    var body: some View {
        List(notes.items) { note in
            VStack(alignment: .leading) {
                Text(note.title)
                Text(note.modified, format: .relative(presentation: .named)).font(.waveCaption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { notes.open(note) }
        }
        .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Search title and text, press Return")
        .onSubmit(of: .search) { Task { await notes.load(query: query) } }
        .onChange(of: query) { if query.isEmpty { Task { await notes.load() } } }
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { NoteEditor(notes: notes) }
        .task { await notes.load() }
        .overlay {
            if let error = notes.error {
                ContentUnavailableView("Can't reach Notes", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if notes.items.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No notes" : "No results", systemImage: "note.text")
            }
        }
    }
}

struct NoteEditor: View {
    let notes: Notes
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Title", text: $title).font(.waveTitle3)
            TextEditor(text: $text).font(.waveBody).frame(minHeight: 220)
            if let error { Text(error).font(.waveCaption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(title.isEmpty).buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .padding()
        .frame(width: 480)
    }

    private func save() {
        Task {
            do {
                try await notes.create(title: title, text: text)
                await notes.load()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
