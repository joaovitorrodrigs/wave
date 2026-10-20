import SwiftData
import Foundation

@Model final class Note {
    var title: String
    var text: String            // plain, for search, CLI, snippets
    var rich: Data?             // RTF from the editor; nil when written by the CLI or Siri
    var created = Date.now
    var modified = Date.now

    init(title: String, text: String = "") {
        self.title = title
        self.text = text
    }

    var firstLine: String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    static func fetch(_ context: ModelContext, query: String = "", limit: Int? = nil) -> [Note] {
        var descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.modified, order: .reverse)])
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            descriptor.predicate = #Predicate { $0.title.localizedStandardContains(q) || $0.text.localizedStandardContains(q) }
        }
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
