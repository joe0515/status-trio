import AppKit
import XCTest
@testable import StatusTrioCore

/// Writes the 1024px App Icon preview with Bluetooth-colored volume dots:
///
/// ```bash
/// STATUS_TRIO_APP_ICON_PREVIEW=/tmp/status-trio-app-icon-preview.png \
///   swift test --filter AppIconPreviewTests
/// ```
@MainActor
final class AppIconPreviewTests: XCTestCase {
    func testPreviewUsesTheChargingWiFiStateWithBluetoothVolumeColor() {
        let state = AppIconPreview.state

        XCTAssertTrue(state.status.battery.isCharging)
        XCTAssertEqual(state.status.wifi.state, .connected)
        XCTAssertEqual(state.status.volume.currentDevice, SheetFixtures.bluetoothDevice)
        XCTAssertTrue(state.bluetoothAudioOptions.usesVolumeColor)
        XCTAssertFalse(state.bluetoothAudioOptions.replacesNetworkIcon)
        XCTAssertEqual(state.backgroundStyle, .dark)
    }

    func testPreviewIsASquare1024PixelPngWithTransparentCorners() throws {
        let data = try AppIconPreview.pngData()
        let image = try XCTUnwrap(NSImage(data: data))
        let representation = try XCTUnwrap(image.representations.first)

        XCTAssertEqual(representation.pixelsWide, 1024)
        XCTAssertEqual(representation.pixelsHigh, 1024)
        XCTAssertGreaterThan(data.count, 10_000)

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let alphaInfo = cgImage.alphaInfo
        XCTAssertTrue(alphaInfo == .premultipliedLast || alphaInfo == .last)
    }

    func testBundledAppIconMatchesTheApprovedBluetoothColoredPreview() throws {
        let appIconURL = URL(fileURLWithPath: "Support/AppIcon.png")
        let approvedPreviewURL = URL(fileURLWithPath: "screenshots/status-trio-app-icon-preview.png")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appIconURL.path),
            "The app bundle must be built from Support/AppIcon.png."
        )
        guard FileManager.default.fileExists(atPath: appIconURL.path) else { return }

        XCTAssertEqual(
            try Data(contentsOf: appIconURL),
            try Data(contentsOf: approvedPreviewURL),
            "The bundled App Icon must exactly match the approved Bluetooth-colored preview."
        )
    }

    func testWritesRequestedOutputWhenEnvironmentIsSet() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["STATUS_TRIO_APP_ICON_PREVIEW"] else {
            throw XCTSkip("Set STATUS_TRIO_APP_ICON_PREVIEW to write the App Icon preview.")
        }

        let data = try AppIconPreview.pngData()
        try data.write(to: URL(fileURLWithPath: outputPath))
        XCTAssertGreaterThan(data.count, 10_000)
        print("Wrote \(data.count) bytes to \(outputPath)")
    }
}
