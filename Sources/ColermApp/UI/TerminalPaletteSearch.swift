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
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
        guard !terms.isEmpty else { return items }

        return items.filter { item in
            let searchableText = "\(item.title) \(item.path)".lowercased()
            return terms.allSatisfy(searchableText.contains)
        }
    }
}
