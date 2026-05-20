// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WechatLongPicGUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WechatLongPicGUI",
            path: "macOS"
        )
    ]
)
