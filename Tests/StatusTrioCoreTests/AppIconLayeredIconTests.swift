import AppKit
import XCTest
@testable import StatusTrioCore

/// Pins the layered (macOS 26 Liquid Glass) App Icon package that ships in
/// `Support/AppIcon.icon`.
///
/// The package is compiled by `scripts/build-app.sh` with `actool` into the
/// bundle's `Assets.car`, where macOS 26+ resolves it as appearance-aware
/// `IconImageStack` renditions; macOS 15–25 keep the flat `AppIcon.icns`
/// fallback. The specialization key is `hidden-specializations` — the
/// `is-hidden-specializations` spelling is silently dropped by actool, which
/// is exactly how the 1.3.3 appearance-following attempt failed.
final class AppIconLayeredIconTests: XCTestCase {
    private let packageURL = URL(fileURLWithPath: "Support/AppIcon.icon")
    private let manifestURL = URL(fileURLWithPath: "Support/AppIcon.icon/icon.json")
    private let lightLayerURL = URL(fileURLWithPath: "Support/AppIcon.icon/Assets/light.png")
    private let darkLayerURL = URL(fileURLWithPath: "Support/AppIcon.icon/Assets/dark.png")

    func testPackageFilesExist() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lightLayerURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: darkLayerURL.path))
    }

    func testManifestUsesHiddenSpecializationsToSwitchLayersByAppearance() throws {
        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "icon.json must be a JSON object."
        )

        // The system-provided glass fill: no baked-in background, so the fill
        // adapts to light, dark, and tinted appearances on its own.
        let fill = try XCTUnwrap(manifest["fill"] as? [String: Any])
        XCTAssertNotNil(fill["automatic-gradient"])

        let groups = try XCTUnwrap(manifest["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        let layers = try XCTUnwrap(groups[0]["layers"] as? [[String: Any]])
        XCTAssertEqual(layers.count, 2)

        let lightLayer = try XCTUnwrap(
            layers.first { ($0["name"] as? String) == "Light" }
        )
        let darkLayer = try XCTUnwrap(
            layers.first { ($0["name"] as? String) == "Dark" }
        )

        // Light artwork is hidden in dark appearance; dark artwork is hidden
        // in light and tinted appearances. Same structure FaceGate ships.
        XCTAssertEqual(
            try hiddenAppearances(lightLayer),
            ["dark"],
            "The light layer must only be hidden for the dark appearance."
        )
        XCTAssertEqual(
            try hiddenAppearances(darkLayer),
            ["light", "tinted"],
            "The dark layer must be hidden for light and tinted appearances."
        )

        XCTAssertEqual(try XCTUnwrap(lightLayer["image-name"] as? String), "light.png")
        XCTAssertEqual(try XCTUnwrap(darkLayer["image-name"] as? String), "dark.png")
    }

    func testLayersAreSquare1024PixelTransparentPNGs() throws {
        for (url, name) in [(lightLayerURL, "light"), (darkLayerURL, "dark")] {
            let data = try Data(contentsOf: url)
            let image = try XCTUnwrap(NSImage(data: data), "\(name).png must decode.")
            let representation = try XCTUnwrap(image.representations.first)
            XCTAssertEqual(representation.pixelsWide, 1024, "\(name).png must be 1024px wide.")
            XCTAssertEqual(representation.pixelsHigh, 1024, "\(name).png must be 1024px high.")

            let cgImage = try XCTUnwrap(
                image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            )
            let alphaInfo = cgImage.alphaInfo
            XCTAssertTrue(
                alphaInfo == .premultipliedLast || alphaInfo == .last,
                "\(name).png must keep its alpha channel: the glass fill shows through."
            )
        }
    }

    func testLayersRenderDifferentInk() throws {
        let lightData = try Data(contentsOf: lightLayerURL)
        let darkData = try Data(contentsOf: darkLayerURL)
        XCTAssertNotEqual(
            lightData, darkData,
            "Light and dark layers must be distinct renditions, not duplicates."
        )
    }

    private func hiddenAppearances(_ layer: [String: Any]) throws -> [String] {
        let specializations = try XCTUnwrap(
            layer["hidden-specializations"] as? [[String: Any]],
            "Layers must switch via hidden-specializations."
        )
        return specializations.compactMap { $0["appearance"] as? String }
    }
}
