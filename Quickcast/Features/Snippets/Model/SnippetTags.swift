import Foundation

/// Quickcast fork: free-text labels on a snippet, and the browser's filter over them.
enum SnippetTags {
    /// Trimmed, non-empty, first spelling kept for case-insensitive duplicates, in input order.
    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// The editor's comma-separated field, which is why a tag can never carry a comma itself.
    static func parse(_ field: String) -> [String] {
        normalized(field.split(separator: ",").map(String.init))
    }

    static func field(for tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    /// Every tag in use, sorted for the filter menu, spelled as the first snippet carrying it.
    static func inUse(_ snippets: [Snippet]) -> [String] {
        normalized(snippets.flatMap(\.tags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A tag no longer in use resolves to no filter, so an edit can never strand an empty list.
    static func activeFilter(_ selected: String?, in available: [String]) -> String? {
        guard let selected else { return nil }
        return available.first { $0.caseInsensitiveCompare(selected) == .orderedSame }
    }

    static func matches(_ snippet: Snippet, tag: String?) -> Bool {
        guard let tag else { return true }
        return snippet.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    static func matches(_ snippet: Snippet, query: String) -> Bool {
        snippet.name.localizedCaseInsensitiveContains(query)
            || snippet.keyword?.localizedCaseInsensitiveContains(query) == true
            || snippet.tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
