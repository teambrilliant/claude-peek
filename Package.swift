// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudePeek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudePeek",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Info.plist"]),
            ]
        ),
    ]
)
