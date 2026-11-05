import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCUI
import XCEngine

/// Extensión de Compartir: en la app de X, pulsa Compartir → XContexto y el panel aparece encima.
final class ShareViewController: UIViewController {
    private let model = AppModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.isUnlocked = true // la extensión se abre desde un gesto tuyo; el bloqueo aplica a la app principal
        let root = NavigationStack {
            ContextPanelView(model: model)
                .navigationTitle("XContexto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { [weak self] in self?.close() }
                    }
                }
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await loadSharedItem() }
    }

    private func loadSharedItem() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var url: URL?
        var text: String?
        for item in items {
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
                }
            }
        }
        // X a veces comparte el enlace como texto.
        if url == nil, let t = text, let found = t.split(separator: " ").compactMap({ URL(string: String($0)) }).first(where: { PostURL($0) != nil }) {
            url = found; text = nil
        }
        await model.analyze(PostInput(url: url, text: url == nil ? text : nil))
    }

    private func close() {
        if let r = model.result { Task { await model.engine.record(.dismissed, result: r) } }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
