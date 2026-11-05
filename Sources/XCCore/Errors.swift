import Foundation

public enum XCError: Error, Sendable, Equatable, LocalizedError {
    case missingAPIKey
    case invalidPostURL(String)
    case postUnavailable(String)
    case network(String)
    case unauthorized
    case rateLimited(retryAfter: Double?)
    case overloaded(status: Int)
    case api(status: Int, message: String)
    case refusal(category: String?)
    case truncated
    case decoding(String)
    case blockedByPolicy(String)
    case budgetExceeded(spent: Double, limit: Double)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Falta tu clave de la API de Anthropic. Añádela en Ajustes."
        case .invalidPostURL(let s): return "No reconozco esa URL como un post de X: \(s)"
        case .postUnavailable(let s): return "No pude leer el post (\(s)). Prueba a copiar el texto."
        case .network(let s): return "Error de red: \(s)"
        case .unauthorized: return "La clave de la API no es válida o se revocó."
        case .rateLimited: return "Demasiadas peticiones seguidas. Reintentando en unos segundos."
        case .overloaded(let st): return "La API está saturada (\(st)). Reintentando."
        case .api(let st, let m): return "La API devolvió \(st): \(m)"
        case .refusal(let c): return "El modelo declinó esta petición\(c.map { " (\($0))" } ?? "")."
        case .truncated: return "La respuesta se cortó antes de terminar."
        case .decoding(let s): return "Respuesta con formato inesperado: \(s)"
        case .blockedByPolicy(let s): return "Bloqueado por la política de seguridad: \(s)"
        case .budgetExceeded(let s, let l):
            return String(format: "Has alcanzado tu límite de gasto (%.2f de %.2f USD).", s, l)
        }
    }

    /// Errores transitorios que merece la pena reintentar.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .network, .truncated, .decoding: return true
        default: return false
        }
    }
}
