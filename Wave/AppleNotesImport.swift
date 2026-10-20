import Foundation
import SwiftData

/// One-shot copy of Apple Notes into Wave. Reads title and plain text through osascript; Apple Notes is not changed.
enum AppleNotesImport {
    static func run(into context: ModelContext) async throws -> Int {
        let script = """
        set sep to character id 30
        set rowSep to character id 29
        tell application "Notes"
            set noteNames to name of every note
            set noteTexts to plaintext of every note
            set noteDates to modification date of every note
        end tell
        set rows to {}
        set rightNow to current date
        repeat with i from 1 to count noteNames
            set end of rows to (item i of noteNames) & sep & (item i of noteTexts) & sep & ((rightNow - (item i of noteDates)) as integer)
        end repeat
        set AppleScript's text item delimiters to rowSep
        return rows as text
        """
        let output = try await osascript(script)
        var count = 0
        for row in output.split(separator: "\u{1D}") {
            let f = row.split(separator: "\u{1E}", omittingEmptySubsequences: false)
            guard f.count == 3, let age = Double(f[2]) else { continue }
            let title = String(f[0])
            var text = String(f[1])
            if text.hasPrefix(title) { text = String(text.dropFirst(title.count)).trimmingCharacters(in: .newlines) }
            let note = Note(title: title, text: text)
            note.modified = Date(timeIntervalSinceNow: -age)
            note.created = note.modified
            context.insert(note)
            count += 1
        }
        try context.save()
        return count
    }

    private static func osascript(_ script: String) async throws -> String {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let input = Pipe(), output = Pipe(), errors = Pipe()
            p.standardInput = input; p.standardOutput = output; p.standardError = errors
            try p.run()
            input.fileHandleForWriting.write(Data(script.utf8))
            try input.fileHandleForWriting.close()
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw GmailError(String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return String(decoding: out, as: UTF8.self)
        }.value
    }
}
