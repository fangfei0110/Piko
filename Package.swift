// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Piko",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Piko", targets: ["PulseBar"])],
    targets: [
        .target(name: "SystemProbe", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "PulseBar", dependencies: ["SystemProbe"], linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("SystemConfiguration")]),
        .testTarget(name: "PulseBarTests", dependencies: ["PulseBar"])
    ]
)
