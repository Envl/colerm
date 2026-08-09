import Foundation

struct TerminalPaletteItem: Identifiable, Equatable {
    let id: TerminalSessionID
    let index: Int
    let title: String
    let path: String
}

enum TerminalPaletteSearch {
    static func filter(
        _ items: [TerminalPaletteItem],
        query: String
    ) -> [TerminalPaletteItem] {
        let terms = query
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return items }

        return items
            .enumerated()
            .filter { _, item in
                terms.allSatisfy { term in
                    [item.title, item.path].contains { value in
                        SearchTextMatcher.matches(value, term: term)
                    }
                }
            }
            .sorted { lhs, rhs in
                let lhsTitleMatches = titleMatchCount(lhs.element, terms: terms)
                let rhsTitleMatches = titleMatchCount(rhs.element, terms: terms)
                guard lhsTitleMatches == rhsTitleMatches else {
                    return lhsTitleMatches > rhsTitleMatches
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func titleMatchCount(
        _ item: TerminalPaletteItem,
        terms: [String]
    ) -> Int {
        terms.reduce(into: 0) { count, term in
            if SearchTextMatcher.matches(item.title, term: term) {
                count += 1
            }
        }
    }
}

private enum SearchTextMatcher {
    static func matches(_ value: String, term: String) -> Bool {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return true }

        if value.localizedStandardContains(trimmedTerm) {
            return true
        }

        let normalizedTerm = normalized(trimmedTerm)
        guard !normalizedTerm.isEmpty else {
            return value.localizedStandardContains(trimmedTerm)
        }

        let normalizedValue = normalized(value)
        return normalizedValue.contains(normalizedTerm)
            || isSubsequence(normalizedTerm, in: normalizedValue)
    }

    private static func normalized(_ string: String) -> String {
        String(
            string
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .unicodeScalars
                .filter(CharacterSet.alphanumerics.contains)
        )
    }

    private static func isSubsequence(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }

        var needleIndex = needle.startIndex
        for character in haystack {
            guard character == needle[needleIndex] else { continue }
            needleIndex = needle.index(after: needleIndex)
            if needleIndex == needle.endIndex {
                return true
            }
        }
        return false
    }
}
