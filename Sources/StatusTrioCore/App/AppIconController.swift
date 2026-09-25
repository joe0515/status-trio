import AppKit
import Combine

@MainActor
protocol ApplicationDockIconApplying: AnyObject {
    func setApplicationIconImage(_ image: NSImage?)
}

extension NSApplication: ApplicationDockIconApplying {
    func setApplicationIconImage(_ image: NSImage?) {
        applicationIconImage = image
    }
}

@MainActor
final class AppIconController {
    typealias DockRenderer = (
        _ status: MenuBarStatus,
        _ options: BatteryIconOptions,
        _ connectionOptions: ConnectionIconOptions,
        _ volumeOptions: VolumeIconOptions,
        _ bluetoothAudioOptions: BluetoothAudioIconOptions,
        _ backgroundStyle: DockIconBackgroundStyle
    ) -> NSImage?

    static let snapshotDebounceInterval: TimeInterval = 0.5

    private let store: SystemStatusStore
    private let settings: SettingsStore
    private let activationPolicy: AppActivationPolicy
    private let application: any ApplicationDockIconApplying
    private let setMenuBarVisible: (Bool) -> Void
    private let renderDockIcon: DockRenderer
    private let theme: () -> SystemIconAppearanceTheme
    private let isDarkAppearance: () -> Bool
    private let monitor: SystemIconAppearanceMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var renderCache = DockIconRenderCache()
    private let imageCache = DockIconImageCache()
    private let renderCoalescer = IconRenderCoalescer()
    private var hasRenderedDockIcon = false
    private var currentPlacement: AppIconPlacement
    private var currentAppearance: StatusIconAppearance
    private var currentBackgroundPreference: DockIconBackgroundPreference
    private var isDockTileVisible: Bool
    private var isStarted = false

    init(
        store: SystemStatusStore,
        settings: SettingsStore,
        activationPolicy: AppActivationPolicy,
        application: any ApplicationDockIconApplying = NSApplication.shared,
        setMenuBarVisible: @escaping (Bool) -> Void,
        renderDockIcon: @escaping DockRenderer,
        theme: @escaping () -> SystemIconAppearanceTheme = {
            SystemIconAppearanceReader.current()
        },
        isDarkAppearance: @escaping () -> Bool = {
            NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.settings = settings
        self.activationPolicy = activationPolicy
        self.application = application
        self.setMenuBarVisible = setMenuBarVisible
        self.renderDockIcon = renderDockIcon
        self.theme = theme
        self.isDarkAppearance = isDarkAppearance
        self.monitor = SystemIconAppearanceMonitor(
            readTheme: theme,
            readIsDarkAppearance: isDarkAppearance,
            notificationCenter: notificationCenter
        )
        self.currentPlacement = settings.appIconPlacement
        self.currentAppearance = StatusIconAppearance(settings: settings)
        self.currentBackgroundPreference = settings.dockIconBackgroundPreference
        self.isDockTileVisible = activationPolicy.isRegularApp
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Adopt whatever the settings hold now: they can change between
        // construction and the first start.
        currentPlacement = settings.appIconPlacement
        currentAppearance = StatusIconAppearance(settings: settings)
        currentBackgroundPreference = settings.dockIconBackgroundPreference
        apply(currentPlacement)
        activationPolicy.$isRegularApp
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isRegular in
                // @Published emits before the stored value changes, so use the
                // value the publisher delivered.
                guard let self else { return }
                isDockTileVisible = isRegular
                dockTileVisibilityChanged()
            }
            .store(in: &cancellables)
        monitor.onChange = { [weak self] _ in
            self?.renderLatestDockIcon()
        }
        monitor.start()
        subscribeToPlacement()
        subscribeToSnapshot()
        subscribeToIconAppearance()
        subscribeToBackgroundStyle()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        renderCoalescer.cancel()
        monitor.onChange = nil
        monitor.stop()
        clearDockIcon()
    }

    private func dockTileVisibilityChanged() {
        guard isDockTileVisible else {
            clearDockIcon()
            return
        }
        renderLatestDockIcon()
    }

    private func clearDockIcon() {
        defer { renderCache.reset() }
        guard hasRenderedDockIcon else { return }
        application.setApplicationIconImage(nil)
        hasRenderedDockIcon = false
    }

    private func subscribeToPlacement() {
        settings.$appIconPlacement
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] placement in
                self?.apply(placement)
            }
            .store(in: &cancellables)
    }

    private func subscribeToSnapshot() {
        store.$snapshot
            .map { MenuBarStatus(snapshot: $0) }
            .removeDuplicates()
            .dropFirst()
            .debounce(
                for: .seconds(Self.snapshotDebounceInterval),
                scheduler: RunLoop.main
            )
            .sink { [weak self] _ in
                self?.renderLatestDockIcon()
            }
            .store(in: &cancellables)
    }

    private func subscribeToBackgroundStyle() {
        settings.$dockIconBackgroundPreference
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] preference in
                guard let self else { return }
                currentBackgroundPreference = preference
                renderLatestDockIcon()
            }
            .store(in: &cancellables)
    }

    private func subscribeToIconAppearance() {
        // One subscription carries every icon option, for the Dock and the menu
        // bar alike; `SettingsStore.iconAppearancePublisher` lists them once.
        //
        // @Published emits before the stored value changes, so the delivered
        // value is used instead of reading SettingsStore back.
        settings.iconAppearancePublisher
            .dropFirst()
            .sink { [weak self] appearance in
                guard let self else { return }
                currentAppearance = appearance
                renderCoalescer.submit { [weak self] in
                    self?.renderLatestDockIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func apply(_ placement: AppIconPlacement) {
        currentPlacement = placement

        if placement.showsDockIcon {
            let didActivate = activationPolicy.setDockIconVisible(true)
            isDockTileVisible = activationPolicy.isRegularApp
            guard didActivate else {
                // Never trade the Menu Bar away for a Dock tile AppKit refused.
                setMenuBarVisible(true)
                return
            }
            renderLatestDockIcon()
            setMenuBarVisible(placement.showsMenuBarIcon)
        } else {
            setMenuBarVisible(true)
            _ = activationPolicy.setDockIconVisible(false)
            isDockTileVisible = activationPolicy.isRegularApp
        }
    }

    private func renderLatestDockIcon() {
        guard isDockTileVisible else { return }

        let backgroundStyle = DockIconBackgroundResolver.style(
            for: currentBackgroundPreference,
            theme: theme(),
            isDarkAppearance: isDarkAppearance()
        )
        let status = MenuBarStatus(snapshot: store.snapshot)
        let key = DockIconRenderKey(
            status: status,
            options: currentAppearance.batteryOptions,
            connectionOptions: currentAppearance.connectionOptions,
            volumeOptions: currentAppearance.volumeOptions,
            bluetoothAudioOptions: currentAppearance.bluetoothAudioOptions,
            backgroundStyle: backgroundStyle
        )
        guard renderCache.shouldRender(key) else { return }

        if let cached = imageCache.image(for: key) {
            application.setApplicationIconImage(cached)
            hasRenderedDockIcon = true
            return
        }

        guard let image = renderDockIcon(
            status,
            currentAppearance.batteryOptions,
            currentAppearance.connectionOptions,
            currentAppearance.volumeOptions,
            currentAppearance.bluetoothAudioOptions,
            backgroundStyle
        ) else {
            if !hasRenderedDockIcon {
                application.setApplicationIconImage(nil)
            }
            return
        }

        imageCache.store(image, for: key)
        application.setApplicationIconImage(image)
        hasRenderedDockIcon = true
    }
}
