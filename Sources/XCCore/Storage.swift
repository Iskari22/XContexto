import Foundation

/// Carpeta de datos locales. Con App Group, la app y sus extensiones comparten los mismos datos.
public enum AppStorage {
    public static let appGroup = "group.com.xcontexto.shared"

    public static func directory() -> URL {
        let fm = FileManager.default
        let base: URL
        if let env = ProcessInfo.processInfo.environment["XCONTEXTO_DATA_DIR"] {
            base = URL(fileURLWithPath: env)
        } else if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            base = group
        } else {
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("XContexto")
        }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static func file(_ name: String) -> URL { directory().appendingPathComponent(name) }
}

/// Persistencia sencilla en JSON, escritura atómica.
public enum JSONFile {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(value).write(to: url, options: [.atomic])
    }
}
