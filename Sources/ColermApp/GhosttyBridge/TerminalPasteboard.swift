import AppKit
import Foundation
import UniformTypeIdentifiers

enum TerminalPasteboard {
    static let supportedDragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .png,
        .tiff,
        .string
    ]

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let shellEscapeCharacters = Set("\\ ()[]{}<>\"'`!#$&;|*?\t")
    private static let staleImageLifetime: TimeInterval = 24 * 60 * 60

    static var defaultImageDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("colerm-clipboard", isDirectory: true)
    }

    static func canRead(from pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types, !types.isEmpty else { return false }
        if types.contains(.fileURL) || types.contains(.string) || types.contains(.png) || types.contains(.tiff) {
            return true
        }
        return types.contains { rawType in
            UTType(rawType.rawValue)?.conforms(to: .image) == true
        }
    }

    static func extractPasteText(
        from pasteboard: NSPasteboard,
        imageDirectory: URL = defaultImageDirectory,
        fileManager: FileManager = .default
    ) -> String? {
        // 1. Prefer file URLs first (Finder copies put bare filenames in .string and file icons in .tiff).
        let filePaths = (pasteboard.pasteboardItems ?? []).compactMap { item -> String? in
            guard let url = fileURL(from: item) else { return nil }
            return shellEscape(url.path)
        }
        if !filePaths.isEmpty {
            return filePaths.joined(separator: " ")
        }

        // 2. Plain text content (handles normal text copies as well as rich-text apps that include .tiff previews).
        let textItems = (pasteboard.pasteboardItems ?? []).compactMap { item -> String? in
            guard let value = item.string(forType: .string), !value.isEmpty else {
                return nil
            }
            return value
        }
        if !textItems.isEmpty {
            return textItems.joined(separator: "\n")
        }
        if let fallbackText = pasteboard.string(forType: .string), !fallbackText.isEmpty {
            return fallbackText
        }

        // 3. Raw image content (screenshots, Copy Image from browsers/Preview) -> materialize to a temp PNG path.
        guard let pngData = extractPNGData(from: pasteboard), !pngData.isEmpty else {
            return nil
        }
        guard let savedURL = writeTemporaryPNG(
            pngData,
            directory: imageDirectory,
            fileManager: fileManager
        ) else {
            return nil
        }

        return shellEscape(savedURL.path)
    }

    static func shellEscape(_ path: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(path.count)
        for character in path {
            if shellEscapeCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        if let plist = item.propertyList(forType: .fileURL),
           let url = NSURL(pasteboardPropertyList: plist, ofType: .fileURL) as URL?,
           url.isFileURL {
            return ((url as NSURL).filePathURL ?? url).standardizedFileURL
        }
        if let rawString = item.string(forType: .fileURL),
           let url = URL(string: rawString),
           url.isFileURL {
            return ((url as NSURL).filePathURL ?? url).standardizedFileURL
        }
        return nil
    }

    private static func extractPNGData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png),
           pngData.starts(with: pngSignature) {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let pngData = encodePNG(fromImageData: tiffData) {
            return pngData
        }

        if let types = pasteboard.types {
            for type in types {
                guard let utType = UTType(type.rawValue),
                      utType.conforms(to: .image),
                      let rawData = pasteboard.data(forType: type),
                      let pngData = encodePNG(fromImageData: rawData)
                else {
                    continue
                }
                return pngData
            }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let pngData = encodePNG(fromImageData: tiffData) {
            return pngData
        }

        return nil
    }

    private static func encodePNG(fromImageData data: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func writeTemporaryPNG(
        _ data: Data,
        directory: URL,
        fileManager: FileManager
    ) -> URL? {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneStaleImages(in: directory, fileManager: fileManager)

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let token = UUID().uuidString.prefix(8).lowercased()
            let fileURL = directory.appendingPathComponent("clipboard-\(timestamp)-\(token).png")
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            return nil
        }
    }

    private static func pruneStaleImages(in directory: URL, fileManager: FileManager) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-staleImageLifetime)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff
            else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }
}
