import Foundation
import Observation

struct Note: Identifiable, Hashable {
    let id: String
    let title: String
    let modified: Date
}

/// Apple Notes has no public API. Everything goes through osascript, which prompts once for Automation access.
@Observable final class Notes {
    var items: [Note] = []
    var error: String?

    func load(query: String = "") async {
        let spec = query.isEmpty ? "every note" : "(every note whose (name contains \(quote(query)) or plaintext contains \(quote(query))))"
        let script = """
        tell application "Notes"
            set noteIds to id of \(spec)
            set noteNames to name of \(spec)
            set noteDates to modification date of \(spec)
        end tell
        set rows to {}
        set rightNow to current date
        repeat with i from 1 to count noteIds
            set end of rows to (item i of noteIds) & tab & (item i of noteNames) & tab & ((rightNow - (item i of noteDates)) as integer)
        end repeat
        set AppleScript's text item delimiters to linefeed
        return rows as text
        """
        do {
            let text = try await Self.osascript(script)
            items = text.split(separator: "\n").compactMap { line -> Note? in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard f.count == 3, let age = Double(f[2]) else { return nil }
                return Note(id: String(f[0]), title: String(f[1]), modified: Date(timeIntervalSinceNow: -age))
            }
            .sorted { $0.modified > $1.modified }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func create(title: String, text: String) async throws -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "<div><br></div>" : "<div>\(html(String($0)))</div>" }
        let body = "<h1>\(html(title))</h1>" + lines.joined()
        return try await Self.osascript("""
        tell application "Notes"
            set n to make new note at default folder of default account with properties {body:\(quote(body))}
            return id of n
        end tell
        """).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func open(_ note: Note) {
        Task { try? await Self.osascript("tell application \"Notes\"\nshow note id \(quote(note.id))\nactivate\nend tell") }
    }

    private func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    nonisolated static func osascript(_ script: String) async throws -> String {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let input = Pipe(), output = Pipe(), errors = Pipe()
            p.standardInput = input
            p.standardOutput = output
            p.standardError = errors
            try p.run()
            input.fileHandleForWriting.write(Data(script.utf8))
            try input.fileHandleForWriting.close()
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw NotesError(message: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return String(decoding: out, as: UTF8.self)
        }.value
    }
}

struct NotesError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
