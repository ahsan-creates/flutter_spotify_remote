// swift-tools-version: 5.9
// SPM stub — not the active integration path.
// Use CocoaPods: ios/flutter_spotify_remote.podspec

import PackageDescription

let package = Package(
    name: "flutter_spotify_remote",
    platforms: [.iOS("14.0")],
    products: [
        .library(name: "flutter-spotify-remote", targets: ["flutter_spotify_remote"])
    ],
    targets: [
        .target(name: "flutter_spotify_remote")
    ]
)
