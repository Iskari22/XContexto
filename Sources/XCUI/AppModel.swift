import Foundation
import SwiftUI
import XCEngine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Estado de la app compartido por macOS e iOS.
@MainActor @Observable
public final class AppModel {
    public let engine: XContextoEngine
    public var stage: AnalysisStage?
    public var result: AnalysisResult?
    public var errorMessage: String?
    public var lastInput: PostInput?
    public var isUnlocked: Bool
    public var lockEnabled: Bool { didSet { UserDefaults.standard.set(lockEnabled, forKey: "lockEnabled") } }
    public var spend = SpendTracker.State()
    public var prefs = PreferenceModel()
    public var health: [HealthItem] = []
    public var style = StyleStore.load()
    public var hasAPIKey = KeychainStore.load() != nil

    public init(engine: XContextoEngine = XContextoEngine()) {
        self.engine = engine
        let lock = UserDefaults.standard.object(forKey: "lockEnabled") as? Bool ?? true
        lockEnabled = lock
        isUnlocked = !lock
        Task { await refreshMetrics() }
    }

    public var isBusy: Bool { stage != nil && stage != .done }

    // MARK: Análisis

    public func analyze(_ input: PostInput, force: Bool = false) async {
        lastInput = input
        errorMessage = nil
        result = nil
        stage = .fetchingPost
        do {
            let r = try await engine.analyze(input, force: force) { s in
                Task { @MainActor [weak self] in self?.stage = s }
            }
            result = r
            await engine.record(.opened, result: r)
        } catch {
            errorMessage = error.localizedDescription
            await DiagLog.shared.log(.error, "ui", error.localizedDescription)
        }
        stage = nil
        await refreshMetrics()
    }

    public func regenerate() async {
        guard let r = result else { return }
        stage = .drafting
        do { result = try await engine.regenerateDrafts(for: r) } catch { errorMessage = error.localizedDescription }
        stage = nil
        await refreshMetrics()
    }

    /// Abre la app desde la extensión del navegador o el menú Compartir: xcontexto://analyze?url=…&text=…
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard url.scheme == "xcontexto", url.host == "analyze",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        func q(_ n: String) -> String? { items.first { $0.name == n }?.value }
        let input = PostInput(url: q("url").flatMap(URL.init(string:)), text: q("text"), authorName: q("author"), handle: q("handle"))
        guard input.url != nil || input.text != nil else { return false }
        Task { await analyze(input) }
        return true
    }

    // MARK: Uso de borradores (alimenta el aprendizaje)

    public func copy(_ draft: ReplyDraft, finalText: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(finalText, forType: .string)
        #else
        UIPasteboard.general.string = finalText
        #endif
        track(.copied, draft, finalText)
    }

    /// URL que abre la ventana de respuesta de X con el texto escrito. Publicar lo haces tú en X.
    public func composeURL(_ draft: ReplyDraft, finalText: String) -> URL {
        track(.composed, draft, finalText)
        return PostingGuard.composeURL(reply: finalText, inReplyTo: result?.post.id)
    }

    public func rate(_ draft: ReplyDraft, up: Bool) { track(up ? .thumbsUp : .thumbsDown, draft, nil) }
    public func dismiss() { if let r = result { Task { await engine.record(.dismissed, result: r) } }; result = nil }
    public func openedSource() { if let r = result { Task { await engine.record(.viewedSources, result: r) } } }

    private func track(_ kind: InteractionKind, _ draft: ReplyDraft, _ finalText: String?) {
        guard let r = result else { return }
        Task {
            if let f = finalText, f != draft.text { await engine.record(.edited, result: r, draft: draft, finalText: f) }
            await engine.record(kind, result: r, draft: draft, finalText: finalText)
            await refreshMetrics()
        }
    }

    // MARK: Ajustes, métricas y diagnóstico

    public func saveAPIKey(_ key: String) -> String? {
        do { try KeychainStore.save(key); hasAPIKey = true; return nil } catch { return error.localizedDescription }
    }

    public func setSpendLimit(_ usd: Double) async { await SpendTracker.shared.setLimit(usd); await refreshMetrics() }

    public func importArchive(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let samples = try ArchiveImporter.importFile(at: url)
            style = StyleProfile.build(from: samples, manualNotes: style.manualNotes)
            try StyleStore.save(style)
            return "Importados \(style.sampleCount) posts tuyos."
        } catch { return error.localizedDescription }
    }

    public func saveStyleNotes(_ notes: String) {
        style.manualNotes = notes
        try? StyleStore.save(style)
    }

    public func refreshMetrics() async {
        spend = await SpendTracker.shared.snapshot()
        prefs = await LearningStore.shared.current()
    }

    public func runHealthCheck() async { health = await engine.healthCheck() }

    public func exportDiagnostics() async -> URL? {
        if health.isEmpty { await runHealthCheck() }
        return try? await DiagnosticReport.build(health: health).writeToDisk()
    }

    public func unlock() async {
        guard lockEnabled else { isUnlocked = true; return }
        isUnlocked = await AppLock.unlock()
    }
}
