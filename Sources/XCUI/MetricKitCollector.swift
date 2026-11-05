import Foundation
import XCEngine
#if canImport(MetricKit)
import MetricKit
#endif

/// Recoge los informes de cierres inesperados y bloqueos que da el sistema y los guarda en el registro de diagnóstico.
public final class MetricKitCollector: NSObject, @unchecked Sendable {
    public static let shared = MetricKitCollector()
    private var started = false

    public func start() {
        #if canImport(MetricKit)
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        #endif
    }
}

#if canImport(MetricKit)
extension MetricKitCollector: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let crashes = p.crashDiagnostics?.count ?? 0
            let hangs = p.hangDiagnostics?.count ?? 0
            let summary = "Informe del sistema: \(crashes) cierres, \(hangs) bloqueos"
            let json = String(data: p.jsonRepresentation(), encoding: .utf8)?.prefix(4000) ?? ""
            Task { await DiagLog.shared.log(crashes > 0 ? .error : .warning, "crash", "\(summary)\n\(json)") }
        }
    }
}
#endif
