import SwiftUI
import SwiftData

/// Notes live in Wave: list on the left, editor on the right, saved as you type.
struct NotesPage: View {
    @Environment(\.modelContext) private var context
    @Environment(UI.self) private var ui
    @State private var notes: [Note] = []
    @State private var query = ""
    @State private var selected: Note?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Notes").rise()
            Heading(muted: "Everything you wrote down.", strong: notes.isEmpty && query.isEmpty ? "Nothing here yet." : "\(notes.count) note\(notes.count == 1 ? "" : "s").")
                .padding(.top, 20).rise(0.05)

            HStack(spacing: 10) {
                Icon("magnifying-glass", size: 15, color: Theme.ink.opacity(0.5))
                TextField("Search title and text", text: $query).textFieldStyle(.plain).font(.wave(14))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: 420)
            .background(Theme.paper.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Theme.ink.opacity(0.1)))
            .padding(.top, 36).rise(0.1)

            if notes.isEmpty, query.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Write the first one.").font(.wave(20, .medium)).tracking(-0.5)
                    Text("Notes stay in Wave, saved as you type. You can also bring your Apple Notes over once, from Settings.")
                        .foregroundStyle(Theme.ink.opacity(0.6)).lineSpacing(4)
                    PrimaryButton(title: "New note", icon: "plus", large: true) { create() }
                }
                .padding(32).frame(maxWidth: 560, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusBig))
                .padding(.top, 48).rise(0.15)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 6) {
                        ForEach(notes) { note in
                            NoteRow(note: note, selected: note == selected) { selected = note }
                        }
                        if notes.isEmpty {
                            Text("Nothing matches.").foregroundStyle(Theme.ink.opacity(0.5)).padding(16)
                        }
                    }
                    .frame(width: 400)
                    .cardFrame()

                    if let note = selected {
                        NoteEditor(note: note, onDelete: { delete(note) }).id(note.persistentModelID)
                    } else {
                        Text("Pick a note, or make a new one.").foregroundStyle(Theme.ink.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: 400)
                            .cardBlock().cardFrame()
                    }
                }
                .padding(.top, 48).rise(0.15)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: query) { reload() }
        .onChange(of: ui.noteRequest) { create() }
        .onChange(of: ui.noteToOpen) { if let n = ui.noteToOpen { selected = n; ui.noteToOpen = nil; reload() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        notes = Note.fetch(context, query: query)
        if let n = ui.noteToOpen { selected = n; ui.noteToOpen = nil }
        if let selected, !notes.contains(selected), query.isEmpty { self.selected = notes.first }
        if selected == nil { selected = notes.first }
    }

    private func create() {
        let note = Note(title: "")
        context.insert(note)
        query = ""
        reload()
        selected = note
    }

    private func delete(_ note: Note) {
        context.delete(note)
        selected = nil
        reload()
    }
}

/// FAQ-style row: title, when it changed, the first line.
struct NoteRow: View {
    let note: Note
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.title.isEmpty ? "Untitled" : note.title).font(.wave(18, .medium)).tracking(-0.4).lineLimit(1)
                    Spacer()
                    Text(note.modified, format: .relative(presentation: .named)).font(.wave(13))
                        .foregroundStyle(selected ? Theme.paper.opacity(0.6) : Theme.ink.opacity(0.5))
                }
                if !note.firstLine.isEmpty {
                    Text(note.firstLine).font(.wave(14)).foregroundStyle(selected ? Theme.paper.opacity(0.7) : Theme.ink.opacity(0.6)).lineLimit(1)
                }
            }
            .foregroundStyle(selected ? Theme.paper : Theme.ink)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.ink : Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusBlock))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusBlock).fill(Theme.ink.opacity(hover && !selected ? 0.04 : 0)).allowsHitTesting(false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.2), value: hover)
    }
}

/// Title field and a plain text body, saved on every change.
struct NoteEditor: View {
    @Bindable var note: Note
    let onDelete: () -> Void
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                TextField("Title", text: $note.title).textFieldStyle(.plain).font(.wave(26, .medium)).focused($titleFocused)
                HoldButton(compact: true, action: onDelete)
            }
            TextEditor(text: $note.text)
                .font(.wave(16)).lineSpacing(5)
                .scrollContentBackground(.hidden).scrollIndicators(.never)
                .frame(minHeight: 480)
            Text("Edited \(note.modified, format: .relative(presentation: .named))").font(.wave(13)).foregroundStyle(Theme.ink.opacity(0.4))
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardBlock()
        .cardFrame()
        .onChange(of: note.title) { note.modified = .now }
        .onChange(of: note.text) { note.modified = .now }
        .onAppear { if note.title.isEmpty { titleFocused = true } }
    }
}
