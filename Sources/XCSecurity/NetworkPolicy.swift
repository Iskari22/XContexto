import Foundation
import XCCore

/// Cortafuegos interno: toda la red de la app pasa por aquí.
///
/// Garantía de seguridad principal: la app **no puede publicar en X**.
/// - Solo se permite escribir (POST) en `api.anthropic.com`.
/// - Hacia X/Twitter solo se permite *leer* (GET) el endpoint público de oEmbed.
/// - No existe ningún token de X en la app: aunque alguien manipulara el código, no tendría credenciales.
public struct NetworkPolicy: Sendable {
    public var writeHosts: Set<String> = ["api.anthropic.com"]
    public var readHostSuffixes: [String] = ["api.anthropic.com", "publish.x.com", "publish.twitter.com", "wikipedia.org"]
    /// Únicos endpoints de X permitidos: lectura pública de oEmbed.
    public var xReadOnly: Set<String> = ["publish.x.com", "publish.twitter.com"]
    /// Hosts de X en los que jamás se permite nada salvo lectura de oEmbed.
    public var xHostSuffixes: [String] = ["x.com", "twitter.com", "twimg.com"]

    public init() {}

    public func check(_ request: URLRequest) throws {
        guard let url = request.url, let host = url.host?.lowercased() else {
            throw XCError.blockedByPolicy("petición sin destino")
        }
        guard url.scheme == "https" else { throw XCError.blockedByPolicy("solo se permite HTTPS (\(host))") }
        let method = (request.httpMethod ?? "GET").uppercased()

        let isX = xHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
        if isX {
            guard xReadOnly.contains(host), method == "GET", url.path == "/oembed" else {
                throw XCError.blockedByPolicy("la app nunca escribe ni llama a la API de X (\(method) \(host)\(url.path))")
            }
            return
        }

        if method == "GET" || method == "HEAD" {
            let ok = readHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
            guard ok else { throw XCError.blockedByPolicy("host no permitido: \(host)") }
            return
        }
        guard writeHosts.contains(host) else {
            throw XCError.blockedByPolicy("\(method) no permitido hacia \(host)")
        }
    }
}

/// Cliente HTTP que aplica `NetworkPolicy` antes de cada petición.
public struct GuardedHTTPClient: Sendable {
    public let session: URLSession
    public let policy: NetworkPolicy

    public init(session: URLSession = .shared, policy: NetworkPolicy = NetworkPolicy()) {
        self.session = session; self.policy = policy
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try policy.check(request)
        do {
            // Las redirecciones también pasan por el cortafuegos.
            let (data, resp) = try await session.data(for: request, delegate: RedirectGuard(policy: policy))
            guard let http = resp as? HTTPURLResponse else { throw XCError.network("respuesta no HTTP") }
            return (data, http)
        } catch let e as XCError {
            throw e
        } catch let e as URLError where e.code == .timedOut {
            throw XCError.network("tiempo de espera agotado")
        } catch {
            throw XCError.network(error.localizedDescription)
        }
    }
}

/// Revisa cada redirección contra la política; si no está permitida, la cancela.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let policy: NetworkPolicy
    init(policy: NetworkPolicy) { self.policy = policy }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        (try? policy.check(request)) == nil ? nil : request
    }
}
