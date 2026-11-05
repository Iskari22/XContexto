import Foundation
import XCCore

/// Fuentes reputadas a las que se limita la búsqueda web (máximo 64 dominios por petición).
/// Edita esta lista para ajustarla a tu criterio.
public enum TrustedSources {
    public static let domains: [String] = [
        // Agencias y servicio público
        "reuters.com", "apnews.com", "efe.com", "europapress.es", "afp.com", "bbc.com", "rtve.es", "dw.com", "france24.com",
        // Prensa de referencia
        "elpais.com", "elmundo.es", "lavanguardia.com", "abc.es", "elconfidencial.com", "eldiario.es", "expansion.com",
        "theguardian.com", "nytimes.com", "washingtonpost.com", "ft.com", "economist.com", "wsj.com", "lemonde.fr",
        "politico.eu", "aljazeera.com", "bloomberg.com", "npr.org",
        // Análisis y geopolítica
        "foreignaffairs.com", "cfr.org", "crisisgroup.org", "sipri.org", "chathamhouse.org", "brookings.edu",
        "realinstitutoelcano.org", "csis.org", "iiss.org",
        // Instituciones y datos
        "un.org", "europa.eu", "nato.int", "worldbank.org", "imf.org", "oecd.org", "who.int", "ine.es", "bde.es",
        "boe.es", "lamoncloa.gob.es", "congreso.es", "ourworldindata.org",
        // Verificación
        "maldita.es", "newtral.es", "efe.com", "factcheck.org", "politifact.com", "fullfact.org", "snopes.com",
        // Enciclopedias
        "wikipedia.org", "britannica.com",
    ]

    public static var deduplicated: [String] {
        var seen = Set<String>()
        return Array(domains.filter { seen.insert($0).inserted }.prefix(64))
    }

    public static func kind(for url: String) -> SourceKind {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        if host.hasSuffix("wikipedia.org") { return .wikipedia }
        if ["maldita.es", "newtral.es", "factcheck.org", "politifact.com", "fullfact.org", "snopes.com"].contains(where: { host.hasSuffix($0) }) {
            return .factCheck
        }
        if [".int", ".gob.es", ".europa.eu", "un.org", "worldbank.org", "imf.org", "oecd.org", "who.int", "ine.es", "bde.es", "boe.es", "congreso.es"]
            .contains(where: { host.hasSuffix($0) }) { return .institution }
        if deduplicated.contains(where: { host.hasSuffix($0) }) { return .news }
        return .other
    }

    public static func publisher(for url: String) -> String {
        var host = URL(string: url)?.host?.lowercased() ?? url
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
