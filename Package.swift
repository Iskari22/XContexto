// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XContextoKit",
    defaultLocalization: "es",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "XContextoKit", targets: ["XCEngine", "XCUI"]),
        .executable(name: "xcx", targets: ["xcx"]),
    ],
    targets: [
        // Paquetes independientes: cada uno compila y se prueba por separado.
        .target(name: "XCCore"),
        .target(name: "XCSecurity", dependencies: ["XCCore"]),
        .target(name: "XCDiagnostics", dependencies: ["XCCore", "XCSecurity"]),
        .target(name: "XCClaude", dependencies: ["XCCore", "XCSecurity", "XCDiagnostics"]),
        .target(name: "XCResearch", dependencies: ["XCCore", "XCSecurity", "XCClaude", "XCDiagnostics"]),
        .target(name: "XCStyle", dependencies: ["XCCore"]),
        .target(name: "XCLearning", dependencies: ["XCCore"]),
        // Ensamblaje: une todos los paquetes.
        .target(name: "XCEngine", dependencies: [
            "XCCore", "XCSecurity", "XCDiagnostics", "XCClaude", "XCResearch", "XCStyle", "XCLearning",
        ]),
        .target(name: "XCUI", dependencies: ["XCEngine"]),
        .executableTarget(name: "xcx", dependencies: ["XCEngine"]),
        .testTarget(name: "XContextoKitTests", dependencies: ["XCEngine"]),
    ]
)
