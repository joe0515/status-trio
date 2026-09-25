import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct SystemIconAppearanceMonitorTests {
    @Test func reportsOnlyRealThemeChanges() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            readIsDarkAppearance: { false },
            notificationCenter: center
        )
        defer { monitor.stop() }
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reported.isEmpty)

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        theme = clearTheme
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reported == [clearTheme])
    }

    @Test func reReadsWhenTheAppBecomesActive() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            readIsDarkAppearance: { false },
            notificationCenter: center
        )
        defer { monitor.stop() }
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        let darkTheme = SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark)
        theme = darkTheme
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(reported == [darkTheme])
    }

    @Test func stopsReportingAfterStop() {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            readIsDarkAppearance: { false },
            notificationCenter: center
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()
        monitor.stop()

        theme = SystemIconAppearanceTheme(style: .clear, appearance: .light)
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)

        #expect(reported.isEmpty)
    }

    @Test func pollsUntilStopped() async throws {
        let center = NotificationCenter()
        var theme = SystemIconAppearanceTheme.default
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { theme },
            readIsDarkAppearance: { false },
            notificationCenter: center,
            pollingInterval: 0.05
        )
        var reported: [SystemIconAppearanceTheme] = []
        monitor.onChange = { reported.append($0) }
        monitor.start()

        let clearTheme = SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        theme = clearTheme
        try await Task.sleep(for: .milliseconds(600))

        #expect(reported == [clearTheme])

        monitor.stop()
        theme = SystemIconAppearanceTheme(style: .tinted, appearance: .dark)
        try await Task.sleep(for: .milliseconds(300))
        #expect(reported == [clearTheme])
    }

    @Test func reportsWhenOnlyTheLightDarkAppearanceChanges() {
        // The icon-style preference stays "automatic"; only the resolved
        // light/dark appearance flips. A `.system` Dock background depends on
        // that value, so the Dock icon must re-render even though the theme is
        // byte-for-byte unchanged.
        let center = NotificationCenter()
        var isDark = false
        let monitor = SystemIconAppearanceMonitor(
            readTheme: { .default },
            readIsDarkAppearance: { isDark },
            notificationCenter: center
        )
        defer { monitor.stop() }
        var reportCount = 0
        monitor.onChange = { _ in reportCount += 1 }
        monitor.start()
        #expect(reportCount == 0)

        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reportCount == 0)

        isDark = true
        center.post(name: SystemIconAppearanceMonitor.didChangeNotificationName, object: nil)
        #expect(reportCount == 1)
    }
}
