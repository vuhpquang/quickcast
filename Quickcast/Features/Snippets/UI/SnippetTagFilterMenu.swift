import Foundation

/// Quickcast fork: the Search Snippets header filter, opened by its button or ⌘P.
@MainActor
enum SnippetTagFilterMenu {
    static let allTagsSymbol = "tag"
    static let tagSymbol = "number"

    /// Tags on enabled snippets only, since the browser lists nothing else.
    static func tags(in store: SnippetsStore) -> [String] {
        SnippetTags.inUse(store.snippets.filter { $0.snippet.isEnabled }.map(\.snippet))
    }

    static func title(for tag: String?) -> String {
        tag ?? String(localized: "All Tags")
    }

    static func systemImage(for tag: String?) -> String {
        tag == nil ? allTagsSymbol : tagSymbol
    }

    /// The row the menu opens on: All Tags is row 0, each tag follows in `tags` order.
    static func row(of selected: String?, in tags: [String]) -> Int {
        guard let active = SnippetTags.activeFilter(selected, in: tags) else { return 0 }
        return (tags.firstIndex(of: active) ?? -1) + 1
    }

    static func content(tags: [String], select: @escaping (String?) -> Void) -> PopoverMenuContent {
        let all = PopoverMenuItem(title: title(for: nil), systemImage: allTagsSymbol) { select(nil) }
        let rows = tags.enumerated().map { index, tag in
            PopoverMenuItem(title: tag, systemImage: tagSymbol, startsSection: index == 0) {
                select(tag)
            }
        }
        return PopoverMenuContent(items: [all] + rows)
    }
}
