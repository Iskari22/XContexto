import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Bloqueo con Face ID / Touch ID (o el código del dispositivo) para abrir la app.
public enum AppLock {
    public static func unlock(reason: String = "Desbloquear XContexto") async -> Bool {
        #if canImport(LocalAuthentication)
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        #else
        return true
        #endif
    }
}
