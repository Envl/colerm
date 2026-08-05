import Foundation

struct RuntimeMetadataUpdate: Equatable {
    var runtime: RuntimeMetadata?
}

enum RuntimeMetadataParser {
    static let maximumPayloadBytes = 4 * 1024

    static func decodeBase64(_ encoded: String) -> RuntimeMetadataUpdate? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> RuntimeMetadataUpdate? {
        guard data.count <= maximumPayloadBytes else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(string.utf8)) else {
            return nil
        }
        guard let root = object as? [String: Any], Set(root.keys) == ["runtime"] else {
            return nil
        }
        if root["runtime"] is NSNull {
            return RuntimeMetadataUpdate(runtime: nil)
        }
        guard let runtime = root["runtime"] as? [String: Any],
              Set(runtime.keys).isSubset(of: ["name", "path", "version"]),
              let nameValue = runtime["name"] as? String,
              !nameValue.isEmpty
        else {
            return nil
        }

        let sanitizedName = sanitize(nameValue)
        guard !sanitizedName.isEmpty else { return nil }

        var version: String?
        if let versionValue = runtime["version"] as? String {
            let sanitizedVersion = sanitize(versionValue)
            guard !sanitizedVersion.isEmpty else { return nil }
            version = sanitizedVersion
        }

        var path: URL?
        if let pathValue = runtime["path"] as? String {
            let sanitizedPath = sanitize(pathValue)
            guard sanitizedPath.hasPrefix("/"), !sanitizedPath.contains("://") else {
                return nil
            }
            path = URL(fileURLWithPath: sanitizedPath)
        }

        return RuntimeMetadataUpdate(
            runtime: RuntimeMetadata(
                name: sanitizedName,
                path: path,
                version: version
            )
        )
    }

    private static func sanitize(_ value: String) -> String {
        String(value.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F
        })
    }
}
