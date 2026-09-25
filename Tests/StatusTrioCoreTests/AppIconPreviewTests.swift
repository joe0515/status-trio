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

    /// The bundle ships one tile per appearance so the Finder, Launchpad and the
    /// Dock (while the app is not running) follow the system's light/dark icon
    /// style instead of staying on the dark tile forever.
    func testEveryAppearanceVariantDrawsTheSameArtworkOnItsOwnTile() throws {
        let variants = AppIconPreview.appearanceVariants

        XCTAssertEqual(
            variants.map(\.style),
            [.light, .dark],
            "The asset catalog expects the light tile first, then the default dark tile."
        )
        XCTAssertEqual(
            variants.map(\.filename),
            ["AppIcon-Light.png", "AppIcon.png"],
            "Each variant must name the PNG the build reads out of Support/."
        )

        var rendered: [DockIconBackgroundStyle: Data] = [:]
        for variant in variants {
            let data = try AppIconPreview.pngData(for: variant.style)
            let image = try XCTUnwrap(NSImage(data: data))
            let representation = try XCTUnwrap(image.representations.first)

            XCTAssertEqual(representation.pixelsWide, 1024, "\(variant.filename) must be 1024 px wide.")
            XCTAssertEqual(representation.pixelsHigh, 1024, "\(variant.filename) must be 1024 px tall.")
            rendered[variant.style] = data
        }

        XCTAssertNotEqual(
            rendered[.light],
            rendered[.dark],
            "A light tile that matches the dark one byte for byte would not change with the system."
        )
    }

    func testBundledLightAppIconMatchesTheApprovedLightPreview() throws {
        let lightIconURL = URL(fileURLWithPath: "Support/AppIcon-Light.png")
        let approvedPreviewURL = URL(fileURLWithPath: "screenshots/status-trio-app-icon-light-preview.png")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lightIconURL.path),
            "The light appearance variant must be committed as Support/AppIcon-Light.png."
        )
        guard FileManager.default.fileExists(atPath: lightIconURL.path) else { return }

        XCTAssertEqual(
            try Data(contentsOf: lightIconURL),
            try Data(contentsOf: approvedPreviewURL),
            "The bundled light App Icon must exactly match the approved light preview."
        )
    }

    /// The Finder, Launchpad and the Dock (while the app is not running) read the
    /// themed icon out of `Assets.car`, which `scripts/build-app-icon.sh`
    /// compiles from `Support/AppIcon.icon`. A legacy `.icns` cannot express an
    /// appearance, which is why those surfaces used to stay on the dark tile.
    ///
    /// This pins the wiring rather than the artwork: the manifest must name a
    /// dark rendition distinct from the light one, and both files must be there.
    func testThemedIconManifestDeclaresBothAppearances() throws {
        let manifestURL = URL(fileURLWithPath: "Support/AppIcon.icon/icon.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "The themed icon document must be committed as Support/AppIcon.icon."
        )
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }

        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        let root = try XCTUnwrap(manifest as? [String: Any])

        let groups = try XCTUnwrap(root["groups"] as? [[String: Any]], "icon.json must declare groups.")
        let layers = try XCTUnwrap(
            groups.first?["layers"] as? [[String: Any]],
            "The icon document must declare at least one layer."
        )
        let layer = try XCTUnwrap(layers.first)

        let lightImage = try XCTUnwrap(layer["image-name"] as? String)
        let specializations = try XCTUnwrap(
            layer["image-name-specializations"] as? [[String: Any]],
            "The layer must specialize its image per appearance."
        )

        let darkImage = try XCTUnwrap(
            specializations.first { $0["appearance"] as? String == "dark" }?["value"] as? String,
            "The layer must name a dark rendition."
        )

        XCTAssertNotEqual(
            lightImage,
            darkImage,
            "A dark rendition that reuses the light file would not change with the system."
        )

        for image in [lightImage, darkImage] {
            let path = "Support/AppIcon.icon/Assets/\(image)"
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path),
                "\(path) must exist; actool resolves layer images out of Assets/ (capital A)."
            )
        }

        let catalog = URL(fileURLWithPath: "Support/Assets.car")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: catalog.path),
            "Run scripts/build-app-icon.sh to compile Support/Assets.car."
        )
        XCTAssertGreaterThan(
            (try? Data(contentsOf: catalog).count) ?? 0,
            10_000,
            "Support/Assets.car looks empty; regenerate it with scripts/build-app-icon.sh."
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

    /// Writes every appearance variant into one directory:
    ///
    /// ```bash
    /// STATUS_TRIO_APP_ICON_VARIANTS_DIR=/tmp/app-icons \
    ///   swift test --filter AppIconPreviewTests
    /// ```
    func testWritesEveryAppearanceVariantWhenDirectoryIsSet() throws {
        guard let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_APP_ICON_VARIANTS_DIR"] else {
            throw XCTSkip("Set STATUS_TRIO_APP_ICON_VARIANTS_DIR to write every App Icon variant.")
        }

        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        for variant in AppIconPreview.appearanceVariants {
            let data = try AppIconPreview.pngData(for: variant.style)
            let url = URL(fileURLWithPath: directory).appendingPathComponent(variant.filename)
            try data.write(to: url)
            XCTAssertGreaterThan(data.count, 10_000)
            print("Wrote \(data.count) bytes to \(url.path)")
        }
    }
}
