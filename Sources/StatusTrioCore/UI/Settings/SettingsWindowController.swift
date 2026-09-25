import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: SettingsStore
    private let statusStore: SystemStatusStore
    private let chargingEffectClock: ChargingEffectClock
    private let localization: Localization
    private let activationPolicy: AppActivationPolicy
    private let showIconGuide: () -> Void
    private var localizationCancellable: AnyCancellable?
    private var authorizationCancellable: AnyCancellable?
    private var ownsActivationPolicy = false
    /// Last Bluetooth grant we saw, so we only re-surface Settings after a real
    /// permission decision (`.notDetermined` → granted/denied), never on launch
    /// or on a no-op refresh of an already-granted app.
    private var lastBluetoothAuthorization: BluetoothAuthorizationStatus = .notDetermined

    init(
        store: SettingsStore,
        statusStore: SystemStatusStore,
        localization: Localization,
        activationPolicy: AppActivationPolicy,
        showIconGuide: @escaping () -> Void,
        chargingEffectClock: ChargingEffectClock = ChargingEffectClock()
    ) {
        self.store = store
        self.statusStore = statusStore
        self.chargingEffectClock = chargingEffectClock
        self.localization = localization
        self.activationPolicy = activationPolicy
        self.showIconGuide = showIconGuide
        super.init(window: nil)

        localizationCancellable = localization.$resolvedLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                self?.applyLocalization(language: language)
            }

        // A system Bluetooth permission prompt steals focus and can dismiss or
        // background this window. Once the user decides, bring Settings back so
        // they land where they were instead of hunting for the window.
        authorizationCancellable = statusStore.bluetoothDevices.$authorizationStatus
            .dropFirst()
            .sink { [weak self] status in
                guard let self else { return }
                let wasUndetermined = self.lastBluetoothAuthorization == .notDetermined
                self.lastBluetoothAuthorization = status
                if wasUndetermined, status != .notDetermined {
                    self.resurface()
                }
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        statusStore.setSettingsVisible(true)
        applyLocalization()
        enterActivationPolicyIfNeeded()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        statusStore.setSettingsVisible(false)
        leaveActivationPolicyIfNeeded()
        window = nil
    }

    /// Brings Settings back to the front after a system dialog (such as the
    /// Bluetooth permission prompt) hid or dismissed it. Re-fronts the existing
    /// window when it survived, or rebuilds it when the dialog closed it — in
    /// the latter case the temporary regular-mode claim is re-entered so the
    /// rebuilt window is not hidden behind an accessory app.
    func resurface() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let window = makeWindow()
            self.window = window
            statusStore.setSettingsVisible(true)
            applyLocalization()
            enterActivationPolicyIfNeeded()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeWindow() -> NSWindow {
        let contentSize = NSSize(width: SettingsView.width, height: SettingsView.height)
        // `.miniaturizable` and `.resizable` are what make the two right-hand
        // traffic lights usable: AppKit disables the minimize button without the
        // former and the zoom/full-screen button without the latter, which is why
        // they shipped greyed out and inert.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let rootView = LocalizedRootView(localization: localization) {
            SettingsView(
                store: store,
                statusStore: statusStore,
                localization: localization,
                onShowIconGuide: showIconGuide
            )
            .environmentObject(chargingEffectClock)
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self
        window.isReleasedWhenClosed = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.setFrameAutosaveName("SettingsWindow.Sidebar.v1")
        window.center()
        window.setContentSize(contentSize)
        // The window opens at its designed size and may only grow: the sidebar is
        // a fixed 190 pt column, so a narrower window would squeeze the detail
        // pane below what the sections are laid out for.
        window.contentMinSize = contentSize
        // A resizable window is not automatically offered a full-screen space.
        window.collectionBehavior.insert(.fullScreenPrimary)
        return window
    }

    private func applyLocalization(language: AppLanguage? = nil) {
        let language = language ?? localization.resolvedLanguage
        window?.title = localization.string(.settingsTitle, language: language)
        window?.contentView?.userInterfaceLayoutDirection = language.nsLayoutDirection
    }

    private func enterActivationPolicyIfNeeded() {
        guard !ownsActivationPolicy else { return }
        ownsActivationPolicy = true
        activationPolicy.enterTemporaryRegularMode()
    }

    private func leaveActivationPolicyIfNeeded() {
        guard ownsActivationPolicy else { return }
        ownsActivationPolicy = false
        activationPolicy.leaveTemporaryRegularMode()
    }
}
