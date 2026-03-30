// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ios_in_app_purchase_kit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "InAppPurchaseKitCore",
            targets: ["InAppPurchaseKitCore"]
        )
    ],
    targets: [
        .target(
            name: "InAppPurchaseKitCore",
            path: "Sources/InAppPurchaseKitCore",
            resources: [
                .process("Localizable")
            ]
        ),
        .testTarget(
            name: "InAppPurchaseKitCoreTests",
            dependencies: ["InAppPurchaseKitCore"],
            path: "Tests/InAppPurchaseKitTests"
        )
    ]
)
