// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ios_in_app_purchase_kit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "IAPKit",
            targets: ["IAPKit"]
        )
    ],
    targets: [
        .target(
            name: "IAPKit",
            path: "Sources/InAppPurchaseKit",
            resources: [
                .process("Localizable")
            ]
        ),
        .testTarget(
            name: "IAPKitTests",
            dependencies: ["IAPKit"],
            path: "Tests/InAppPurchaseKitTests"
        )
    ]
)
