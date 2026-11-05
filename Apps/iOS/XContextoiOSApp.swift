import SwiftUI
import XCUI
import XCEngine

@main
struct XContextoiOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL { model.handle(url: $0) }
                .task { MetricKitCollector.shared.start() }
        }
    }
}
