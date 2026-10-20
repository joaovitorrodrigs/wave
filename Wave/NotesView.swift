import SwiftUI

struct NotesPage: View {
    let notes: Notes
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Notes").rise()
            Heading(muted: "Everything you wrote down.", strong: summary).padding(.top, 20).rise(0.05)

            HStack(spacing: 10) {
                Icon("magnifying-glass", size: 15, color: Theme.ink.opacity(0.5))
                TextField("Search title and text, press Return", text: $query).textFieldStyle(.plain).font(.wave(14))
                    .onSubmit { Task { await notes.load(query: query) } }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: 420)
            .background(Theme.paper.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Theme.ink.opacity(0.1)))
            .padding(.top, 36).rise(0.1)
            .onChange(of: query) { if query.isEmpty { Task { await notes.load() } } }

            if let error = notes.error {
                Text(error).foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 48)
            } else if notes.items.isEmpty {
                Text(query.isEmpty ? "No notes yet." : "Nothing matches.").foregroundStyle(Theme.ink.opacity(0.6)).padding(.top, 48)
            } else {
                VStack(spacing: 6) {
                    ForEach(notes.items) { note in
                        NoteRow(note: note) { notes.open(note) }
                    }
                }
                .cardFrame()
                .padding(.top, 48).rise(0.15)
            }
        }
        .task { await notes.load() }
    }

    private var summary: String {
        notes.items.isEmpty ? "Nothing here yet." : "\(notes.items.count) note\(notes.items.count == 1 ? "" : "s")."
    }
}

/// The FAQ row: `rounded-[18px] bg-paper px-5 py-4`, with the services card's arrow on hover.
struct NoteRow: View {
    let note: Note
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 16) {
            Text(note.title).font(.wave(20, .medium)).tracking(-0.5).lineLimit(1)
            Spacer()
            Text(note.modified, format: .relative(presentation: .named)).foregroundStyle(Theme.ink.opacity(0.5))
            Icon(hover ? "arrow-up-right" : "plus", size: 18, color: Theme.ink.opacity(0.6))
                .frame(width: 22)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .cardBlock()
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusBlock).fill(Theme.ink.opacity(hover ? 0.04 : 0)).allowsHitTesting(false))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

struct NoteEditor: View {
    let notes: Notes
    @Environment(UI.self) private var ui
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle(text: "New note")
            TextField("Title", text: $title).waveField()
            TextEditor(text: $text).font(.wave(16)).scrollContentBackground(.hidden)
                .padding(16).frame(minHeight: 220)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            if let error { Text(error).font(.wave(13)).foregroundStyle(Theme.danger) }
            PanelButtons(primary: "Save to Notes", disabled: title.isEmpty, action: save)
        }
        .panel(width: 560)
    }

    private func save() {
        Task {
            do {
                try await notes.create(title: title, text: text)
                await notes.load()
                ui.close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
