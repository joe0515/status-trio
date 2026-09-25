import AppKit
import CoreGraphics
import Foundation
@testable import StatusTrioCore

/// Produces the proposed App Icon without changing the bundled icon.
///
/// The center glyph remains Wi-Fi while the volume dots use the renderer's
/// Bluetooth blue, matching the requested variation of the first Dock state.
@MainActor
enum AppIconPreview {
    struct State {
        let backgroundStyle: DockIconBackgroundStyle
        let status: MenuBarStatus
        let bluetoothAudioOptions: BluetoothAudioIconOptions
    }

    /// The approved App Icon artwork: a charging battery, connected Wi-Fi, and
    /// the Bluetooth-colored volume dots. Shared by both appearance variants so
    /// the light and dark tiles can never drift into two different drawings.
    static let status = MenuBarStatus(
        battery: BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        ),
        wifi: WiFiStatus(state: .connected, rssi: -52),
        connection: .wifi,
        volume: MenuBarVolumeStatus(
            scalar: 0.6,
            isMuted: false,
            deviceName: SheetFixtures.bluetoothDevice.name,
            currentDevice: SheetFixtures.bluetoothDevice
        )
    )

    static let bluetoothAudioOptions = BluetoothAudioIconOptions(
        replacesNetworkIcon: false,
        usesVolumeColor: true
    )

    static func makeState(for backgroundStyle: DockIconBackgroundStyle) -> State {
        State(
            backgroundStyle: backgroundStyle,
            status: status,
            bluetoothAudioOptions: bluetoothAudioOptions
        )
    }

    /// The dark tile, which the bundle ships as its default App Icon.
    static let state = makeState(for: .dark)

    /// The tiles the bundle ships as the App Icon's appearance variants, in the
    /// order the asset catalog lists them. `filename` names the PNG under
    /// `Support/` that the build reads.
    static let appearanceVariants: [(style: DockIconBackgroundStyle, filename: String)] = [
        (.light, "AppIcon-Light.png"),
        (.dark, "AppIcon.png")
    ]

    static func pngData() throws -> Data {
        try pngData(for: .dark)
    }

    static func pngData(for backgroundStyle: DockIconBackgroundStyle) throws -> Data {
        let canvasSize: CGFloat = 1024
        let context = try SheetCanvas.makeContext(width: canvasSize, height: canvasSize, scale: 1)
        context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

        guard let image = DockIconRenderer.image(
            status: state.status,
            bluetoothAudioOptions: state.bluetoothAudioOptions,
            backgroundStyle: backgroundStyle
        ) else {
            throw PreviewError.iconUnavailable
        }

        var proposed = CGRect(origin: .zero, size: image.size)
        guard let tile = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw PreviewError.iconUnavailable
        }

        context.interpolationQuality = .high
        context.draw(tile, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
        return try SheetCanvas.pngData(context)
    }

    enum PreviewError: Error {
        case iconUnavailable
    }
}
