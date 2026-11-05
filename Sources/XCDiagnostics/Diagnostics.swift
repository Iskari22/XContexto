import Foundation
import os
import XCCore
import XCSecurity

public enum DiagLevel: String, Codable, Sendable { case debug, info, warning, error }

public struct DiagEvent: Codable, Sendable, Hashable {
    public var date: Date
    public var level: DiagLevel
    public var category: String
    public var message: String
    public var remedy: String?
}

/// Registro de fallos: guarda los últimos eventos en disco (JSONL) y en el log del sistema.
/// Todo pasa por `Redactor`, así que nunca se guardan claves.
public actor DiagLog {
    public static let shared = DiagLog()

    private let osLog = Logger(subsystem: "com.xcontexto", category: "app")
    private var events: [DiagEvent] = []
    private let maxEvents = 500
    private let url: URL

    public init(url: URL = AppStorage.file("diagnostics.jsonl")) {
        self.url = url
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            events = text.split(separator: "\n").suffix(maxEvents).compactMap { try? dec.decode(DiagEvent.self, from: Data($0.utf8)) }
        }
    }

    public func log(_ level: DiagLevel, _ category: String, _ message: String, remedy: String? = nil) {
        let e = DiagEvent(date: Date(), level: level, category: category, message: Redactor.redact(message), remedy: remedy)
        events.append(e)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        switch level {
        case .debug: osLog.debug("[\(category, privacy: .public)] \(e.message, privacy: .public)")
        case .info: osLog.info("[\(category, privacy: .public)] \(e.message, privacy: .public)")
        case .warning: osLog.warning("[\(category, privacy: .public)] \(e.message, privacy: .public)")
        case .error: osLog.error("[\(category, privacy: .public)] \(e.message, privacy: .public)")
        }
        persist()
    }

    public func recent(_ n: Int = 100) -> [DiagEvent] { Array(events.suffix(n)) }

    public func errorCounts(lastHours: Double = 24) -> [String: Int] {
        let since = Date().addingTimeInterval(-lastHours * 3600)
        return events.filter { $0.level == .error && $0.date >= since }.reduce(into: [:]) { $0[$1.category, default: 0] += 1 }
    }

    public func clear() { events.removeAll(); persist() }

    private func persist() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let lines = events.compactMap { try? enc.encode($0) }.compactMap { String(data: $0, encoding: .utf8) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Reparación automática: para cada tipo de fallo, qué hace la app sola y qué te sugiere a ti.
public enum Remedy: Sendable, Equatable {
    case retry(after: Double)
    case switchModel(to: String)
    case continueWithoutWebSearch
    case askUserForKey
    case askUserToPasteText
    case giveUp(String)

    public var description: String {
        switch self {
        case .retry(let s): return String(format: "Reintento automático en %.1f s", s)
        case .switchModel(let m): return "Cambio automático al modelo \(m)"
        case .continueWithoutWebSearch: return "Sigo solo con Wikipedia"
        case .askUserForKey: return "Revisa tu clave de la API en Ajustes"
        case .askUserToPasteText: return "Pega el texto del post manualmente"
        case .giveUp(let s): return s
        }
    }

    public static func forError(_ error: XCError, attempt: Int, fallbackModel: String?) -> Remedy {
        let backoff = min(30, pow(2, Double(attempt)) * 1.5)
        switch error {
        case .rateLimited(let after): return .retry(after: after ?? backoff)
        case .overloaded:
            if attempt >= 2, let m = fallbackModel { return .switchModel(to: m) }
            return .retry(after: backoff)
        case .network, .truncated, .decoding: return attempt < 3 ? .retry(after: backoff) : .giveUp("Fallo persistente")
        case .unauthorized, .missingAPIKey: return .askUserForKey
        case .postUnavailable, .invalidPostURL: return .askUserToPasteText
        default: return .giveUp(error.localizedDescription)
        }
    }
}

/// Ejecuta una operación con reintentos y registra cada fallo y su arreglo.
public func withRecovery<T: Sendable>(
    _ category: String,
    maxAttempts: Int = 4,
    log: DiagLog = .shared,
    fallbackModel: String? = nil,
    operation: @Sendable (_ model: String?) async throws -> T
) async throws -> T {
    var attempt = 0
    var model: String? = nil
    while true {
        do {
            return try await operation(model)
        } catch let error as XCError {
            attempt += 1
            let remedy = Remedy.forError(error, attempt: attempt, fallbackModel: fallbackModel)
            await log.log(.error, category, error.localizedDescription, remedy: remedy.description)
            guard attempt < maxAttempts else { throw error }
            switch remedy {
            case .retry(let s): try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
            case .switchModel(let m): model = m
            default: throw error
            }
        }
    }
}

public struct HealthItem: Codable, Sendable, Hashable {
    public var name: String
    public var ok: Bool
    public var detail: String
    public var fix: String?
    public init(name: String, ok: Bool, detail: String, fix: String?) {
        self.name = name; self.ok = ok; self.detail = detail; self.fix = fix
    }
}

/// Informe exportable para depurar (sin claves). Se lo puedes pasar a Claude Code para que arregle el fallo.
public struct DiagnosticReport: Codable, Sendable {
    public var generatedAt: Date
    public var appVersion: String
    public var os: String
    public var health: [HealthItem]
    public var errorCounts24h: [String: Int]
    public var recentEvents: [DiagEvent]

    public static func build(health: [HealthItem], log: DiagLog = .shared) async -> DiagnosticReport {
        DiagnosticReport(
            generatedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            health: health,
            errorCounts24h: await log.errorCounts(),
            recentEvents: await log.recent(200)
        )
    }

    public func writeToDisk() throws -> URL {
        let url = AppStorage.file("diagnostico-\(Int(generatedAt.timeIntervalSince1970)).json")
        try JSONFile.save(self, to: url)
        return url
    }
}
