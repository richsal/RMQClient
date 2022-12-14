// swift-tools-version:5.1


import PackageDescription

let package = Package(
    name: "RMQClient",
    products: [
        .library(name: "RMQClient", targets: ["RMQClient"])
        ],
    dependencies: [
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket.git", from: "7.6.3"),
        .package(url: "https://github.com/richsal/JKVValue.git", from: "1.3.4")
    ],
    targets: [
        .target(
            name: "RMQClient",
            dependencies: ["JKVValue", "CocoaAsyncSocket"],
            path: "RMQClient",
            publicHeadersPath: "include"
            )
        ]
)
