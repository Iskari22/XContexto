import Foundation

/// Precios de la API (USD por millón de tokens) para estimar cuánto llevas gastado de tus créditos.
/// Estimación: la cifra exacta está en console.anthropic.com → Usage.
public enum Pricing {
    public struct Rate: Sendable { public let input, output, cacheRead, cacheWrite: Double }

    public static let rates: [String: Rate] = [
        "claude-opus-5-5": Rate(input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5),
        "claude-sonnet-5-5": Rate(input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.5),
        "claude-haiku-5-5": Rate(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
    ]

    /// Búsqueda web del servidor: 10 USD por cada 1.000 búsquedas.
    public static let webSearchPerRequest = 0.01

    public static func cost(of u: TokenUsage) -> Double {
        let r = rates[u.model] ?? rates["claude-opus-5-5"]!
        let m = 1_000_000.0
        return Double(u.inputTokens) / m * r.input
            + Double(u.outputTokens) / m * r.output
            + Double(u.cacheReadTokens) / m * r.cacheRead
            + Double(u.cacheWriteTokens) / m * r.cacheWrite
            + Double(u.webSearches) * webSearchPerRequest
    }
}
