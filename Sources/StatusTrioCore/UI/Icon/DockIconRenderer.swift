import AppKit
import CoreGraphics

enum DockIconGlyphLayout {
    static let designLength: CGFloat = 1024
    static let glyphSVGOrigin = CGPoint(x: 194.8, y: 171.84)
    static let glyphSVGSize: CGFloat = 672

    static func frame(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        return CGRect(
            x: bounds.minX + glyphSVGOrigin.x / designLength * bounds.width,
            y: bounds.minY
                + (designLength - glyphSVGOrigin.y - glyphSVGSize)
                / designLength
                * bounds.height,
            width: glyphSVGSize / designLength * bounds.width,
            height: glyphSVGSize / designLength * bounds.height
        )
    }
}

@MainActor
enum DockIconRenderer {
    static let logicalSize: CGFloat = 256
    static let pixelSize = 512

    // Geometry mirrors Support/AppIcon.svg, inset to the standard macOS icon
    // footprint. A 1024px app icon keeps the rounded square at 858px (≈83.8%,
    // ~83px margin) so the running Dock tile matches the size of every other
    // Dock icon — including this app's own layered (Liquid Glass) icon that the
    // system renders at the same footprint. The earlier 896px body (87.5%)
    // rendered noticeably larger than its neighbours.
    private static let bodyRect = CGRect(x: 83, y: 83, width: 858, height: 858)
    private static let bodyCornerRadius: CGFloat = 201
    private static let borderRect = CGRect(x: 84, y: 84, width: 856, height: 856)
    private static let borderCornerRadius: CGFloat = 200

    // Build colors in the bitmap's own space so AppIcon.svg's hex values survive
    // without a Generic RGB to Device RGB conversion.
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    private static func color(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1
    ) -> CGColor {
        CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, alpha]
        ) ?? CGColor(gray: 0, alpha: 1)
    }

    private struct Palette {
        let body: CGColor
        let border: CGColor
        let foreground: CGColor
    }

    private static func palette(for style: DockIconBackgroundStyle) -> Palette {
        switch style {
        case .dark:
            Palette(
                body: color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 23.0 / 255.0),
                border: color(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 61.0 / 255.0),
                foreground: color(red: 1, green: 1, blue: 1)
            )
        case .light:
            Palette(
                body: color(red: 1, green: 1, blue: 1),
                border: color(red: 210.0 / 255.0, green: 210.0 / 255.0, blue: 215.0 / 255.0),
                foreground: color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0)
            )
        case .clear:
            // Approximation of the system's "clear" glass: a translucent light
            // tile with a bright rim so the Dock shows through.
            Palette(
                body: color(red: 1, green: 1, blue: 1, alpha: 0.55),
                border: color(red: 1, green: 1, blue: 1, alpha: 0.8),
                foreground: color(red: 29.0 / 255.0, green: 29.0 / 255.0, blue: 31.0 / 255.0)
            )
        }
    }

    static func image(
        status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        backgroundStyle: DockIconBackgroundStyle = .dark
    ) -> NSImage? {
        let palette = palette(for: backgroundStyle)

        let canvasLength = CGFloat(pixelSize)
        guard let context = scratchContext() else { return nil }

        // Reuse one bitmap buffer across renders: the Dock icon is redrawn on
        // every status change, and allocating a fresh bitmap each time leaves the
        // freed pages in the process.
        context.saveGState()
        defer { context.restoreGState() }
        context.clear(CGRect(x: 0, y: 0, width: canvasLength, height: canvasLength))

        context.scaleBy(
            x: canvasLength / DockIconGlyphLayout.designLength,
            y: canvasLength / DockIconGlyphLayout.designLength
        )

        context.addPath(roundedRect(
            bodyRect,
            cornerRadius: bodyCornerRadius
        ))
        context.setFillColor(palette.body)
        context.fillPath()

        context.addPath(roundedRect(
            borderRect,
            cornerRadius: borderCornerRadius
        ))
        context.setStrokeColor(palette.border)
        context.setLineWidth(2)
        context.strokePath()

        StatusIconRenderer.draw(
            menuBarStatus: status,
            options: options,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            foreground: palette.foreground,
            in: context,
            origin: CGPoint(
                x: DockIconGlyphLayout.glyphSVGOrigin.x,
                y: DockIconGlyphLayout.designLength
                    - DockIconGlyphLayout.glyphSVGOrigin.y
                    - DockIconGlyphLayout.glyphSVGSize
            ),
            size: DockIconGlyphLayout.glyphSVGSize
        )

        guard let output = context.makeImage() else { return nil }

        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = NSSize(width: logicalSize, height: logicalSize)

        let image = NSImage(size: NSSize(width: logicalSize, height: logicalSize))
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }

    private static var reusedContext: CGContext?

    private static func scratchContext() -> CGContext? {
        if let reusedContext { return reusedContext }
        let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: pixelSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        reusedContext = context
        return context
    }

    private static func roundedRect(_ rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}
