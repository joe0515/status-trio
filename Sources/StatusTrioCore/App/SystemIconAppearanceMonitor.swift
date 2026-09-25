import AppKit
import Foundation

@MainActor
final class SystemIconAppearanceMonitor {
    /// Undocumented but exported by AppKit; registered by name so the app never
    /// links against a private symbol.
    static let didChangeNotificationName = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification"
    )
    /// Posted on the distributed notification center when the system light/dark
    /// appearance toggles. This is what lets the Dock icon switch promptly
    /// instead of waiting for the next poll.
    static let appleInterfaceThemeChangedName = Notification.Name(
        "AppleInterfaceThemeChangedNotification"
    )

    private let readTheme: () -> SystemIconAppearanceTheme
    private let readIsDarkAppearance: () -> Bool
    private let notificationCenter: NotificationCenter
    private let pollingInterval: TimeInterval
    private var lastTheme: SystemIconAppearanceTheme
    private var lastIsDarkAppearance: Bool
    private var observers: [NSObjectProtocol] = []
    private var distributedObserver: (any NSObjectProtocol)?
    private var pollTimer: Timer?

    var onChange: ((SystemIconAppearanceTheme) -> Void)?

    init(
        readTheme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        readIsDarkAppearance: @escaping () -> Bool = {
            NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        },
        notificationCenter: NotificationCenter = .default,
        pollingInterval: TimeInterval = 2
    ) {
        self.readTheme = readTheme
        self.readIsDarkAppearance = readIsDarkAppearance
        self.notificationCenter = notificationCenter
        self.pollingInterval = pollingInterval
        self.lastTheme = readTheme()
        self.lastIsDarkAppearance = readIsDarkAppearance()
    }

    func start() {
        guard observers.isEmpty, distributedObserver == nil, pollTimer == nil else { return }
        observe(Self.didChangeNotificationName)
        observe(NSApplication.didBecomeActiveNotification)
        observeInterfaceThemeChanges()

        // The system neither posts a usable change notification nor updates the
        // WindowServer configuration promptly, but it does write the preference
        // right away, so poll it. A cached preferences read is very cheap. The
        // poll also covers the light/dark appearance for OS versions where the
        // interface-theme notification is absent.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stop() {
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Re-reads both the system icon style and the light/dark appearance, and
    /// reports the change when either one actually moved. A `.system` Dock
    /// background under the `.automatic` icon appearance depends on the
    /// light/dark value, so a system appearance toggle must re-render even when
    /// the icon-style preference string is unchanged.
    func refresh() {
        let theme = readTheme()
        let isDark = readIsDarkAppearance()
        guard theme != lastTheme || isDark != lastIsDarkAppearance else { return }
        lastTheme = theme
        lastIsDarkAppearance = isDark
        onChange?(theme)
    }

    private func observe(_ name: Notification.Name) {
        observers.append(notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        })
    }

    private func observeInterfaceThemeChanges() {
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.appleInterfaceThemeChangedName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }
}
