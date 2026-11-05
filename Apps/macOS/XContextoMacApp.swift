import SwiftUI
import XCUI
import XCEngine

@main
struct XContextoMacApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("XContexto", id: "main") {
            RootView(model: model)
                .frame(minWidth: 560, minHeight: 640)
                .onOpenURL { url in
                    model.handle(url: url)
                    NSApp.activate()
                }
                .task { MetricKitCollector.shared.start() }
        }
        .handlesExternalEvents(matching: ["analyze"])

        // Acceso rápido desde la barra de menú.
        MenuBarExtra("XContexto", systemImage: "text.magnifyingglass") {
            Button("Analizar el enlace copiado") {
                if let s = NSPasteboard.general.string(forType: .string), let u = URL(string: s) {
                    openWindow(id: "main")
                    Task { await model.analyze(PostInput(url: u)) }
                    NSApp.activate()
                }
            }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Abrir XContexto") { openWindow(id: "main"); NSApp.activate() }
            Divider()
            Text(String(format: "Gastado: %.2f / %.0f USD", model.spend.totalUSD, model.spend.limitUSD))
            Button("Salir") { NSApp.terminate(nil) }
        }
    }
}
