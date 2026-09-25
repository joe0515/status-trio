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

    static let state = State(
        backgroundStyle: .dark,
        status: MenuBarStatus(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: false,
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
        ),
        bluetoothAudioOptions: BluetoothAudioIconOptions(
            replacesNetworkIcon: false,
            usesVolumeColor: true
        )
    )

    static func pngData() throws -> Data {
        let canvasSize: CGFloat = 1024
        let context = try SheetCanvas.makeContext(width: canvasSize, height: canvasSize, scale: 1)
        context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

        guard let image = DockIconRenderer.image(
            status: state.status,
            bluetoothAudioOptions: state.bluetoothAudioOptions,
            backgroundStyle: state.backgroundStyle
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

/// Renders the transparent glyph layers for the layered (macOS 26 Liquid
/// Glass) App Icon package in `Support/AppIcon.icon`.
///
/// Both layers draw the same approved glyph geometry that `DockIconRenderer`
/// composes onto its background — the `DockIconGlyphLayout` frame — without
/// any background or border, so the system-provided glass fill shows through
/// and adapts to the system appearance. Only the neutral ink color differs:
/// light mode draws dark ink (the light Dock palette foreground), dark mode
/// draws white ink; the charging green and Bluetooth blue stay colored.
@MainActor
enum AppIconLayeredPreview {
    static let layerCanvasSize: CGFloat = 1024

    /// The system's Liquid Glass rendering scales foreground layers to about
    /// 80.5% around the canvas center (measured: a 601×461 green arc in the
    /// source PNG renders at 484×371; the system-fill squircle is unaffected).
    /// Pre-scaling the glyph by the inverse keeps the layered icon's glyph at
    /// the same fraction of the squircle as the live Dock icon's (78.3%).
    static let systemForegroundScale: CGFloat = 0.805

    /// Glyph center in top-down canvas coordinates (same center as the 672px
    /// glyph frame, so the compensated glyph stays visually centered).
    static let glyphCenter = CGPoint(
        x: DockIconGlyphLayout.glyphSVGOrigin.x + DockIconGlyphLayout.glyphSVGSize / 2,
        y: DockIconGlyphLayout.glyphSVGOrigin.y + DockIconGlyphLayout.glyphSVGSize / 2
    )

    /// DockIconRenderer's `.light` palette foreground.
    static let lightInk = CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [29.0 / 255.0, 29.0 / 255.0, 31.0 / 255.0, 1]
    )!

    /// DockIconRenderer's `.dark` palette foreground.
    static let darkInk = CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [1, 1, 1, 1]
    )!

    static func layerPNGData(foreground: CGColor) throws -> Data {
        let context = try SheetCanvas.makeContext(
            width: layerCanvasSize,
            height: layerCanvasSize,
            scale: 1
        )
        context.clear(CGRect(x: 0, y: 0, width: layerCanvasSize, height: layerCanvasSize))

        let compensatedSize = DockIconGlyphLayout.glyphSVGSize / systemForegroundScale
        StatusIconRenderer.draw(
            menuBarStatus: AppIconPreview.state.status,
            bluetoothAudioOptions: AppIconPreview.state.bluetoothAudioOptions,
            foreground: foreground,
            in: context,
            origin: CGPoint(
                x: glyphCenter.x - compensatedSize / 2,
                y: DockIconGlyphLayout.designLength - glyphCenter.y - compensatedSize / 2
            ),
            size: compensatedSize
        )

        return try SheetCanvas.pngData(context)
    }
}
