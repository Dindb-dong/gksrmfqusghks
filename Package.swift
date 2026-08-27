// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "HanKey",
  defaultLocalization: "ko",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "HanKeyCore", targets: ["HanKeyCore"]),
    .library(name: "HanKeyPlatformMac", targets: ["HanKeyPlatformMac"]),
    .executable(name: "HanKeyApp", targets: ["HanKeyApp"]),
  ],
  targets: [
    .target(name: "HanKeyCore"),
    .target(
      name: "HanKeyPlatformMac",
      dependencies: ["HanKeyCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("UserNotifications"),
      ]
    ),
    .executableTarget(
      name: "HanKeyApp",
      dependencies: ["HanKeyCore", "HanKeyPlatformMac"]
    ),
    .testTarget(
      name: "HanKeyCoreTests",
      dependencies: ["HanKeyCore"]
    ),
    .testTarget(
      name: "HanKeyPlatformMacTests",
      dependencies: ["HanKeyPlatformMac"]
    ),
  ]
)
