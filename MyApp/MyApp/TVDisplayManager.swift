import SwiftUI
import UIKit

// MARK: - TVDisplayManager
//
// Manages the secondary UIWindow shown on an externally connected TV
// (via AirPlay or USB-C/HDMI adapter). When a BT game is in progress
// and a screen is connected, TVGameView is presented on that screen
// while the normal game runs on the device screen.
//
// Usage:
//   - Call `startMonitoring()` once at app launch.
//   - Set `activeGame` when a BT game starts; nil it when the game ends.

@MainActor
@Observable
final class TVDisplayManager {
    static let shared = TVDisplayManager()

    /// True when at least one external screen is connected.
    private(set) var isExternalScreenConnected = false

    /// Assign the active BT game ViewModel here. The TV window is
    /// created/destroyed automatically as this changes.
    var activeGame: BluetoothGameViewModel? {
        didSet { refreshTVWindow() }
    }

    private var externalWindow: UIWindow?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: - Start

    func startMonitoring() {
        isExternalScreenConnected = hasExternalScreen()

        // UIScene.willConnectNotification fires for all new scene connections;
        // filter to external-screen scenes only.
        let connectObs = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene,
                  scene.screen !== UIScreen.main else { return }
            Task { @MainActor [weak self] in
                self?.isExternalScreenConnected = true
                self?.refreshTVWindow()
            }
        }

        let disconnectObs = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene,
                  scene.screen !== UIScreen.main else { return }
            Task { @MainActor [weak self] in
                self?.isExternalScreenConnected = self?.hasExternalScreen() ?? false
                if !(self?.isExternalScreenConnected ?? false) {
                    self?.tearDownTVWindow()
                }
            }
        }

        observers = [connectObs, disconnectObs]

        // If a screen is already connected when the app launches, create the window
        // as soon as a game becomes active (handled by the activeGame didSet).
        if isExternalScreenConnected { refreshTVWindow() }
    }

    // MARK: - Window Lifecycle

    private func refreshTVWindow() {
        tearDownTVWindow()

        guard isExternalScreenConnected, let game = activeGame else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.screen !== UIScreen.main }) else { return }

        let window = UIWindow(windowScene: scene)

        let content = TVGameView(game: game)
            .environmentObject(ThemeManager.shared)
        let hostingController = UIHostingController(rootView: AnyView(content))
        hostingController.view.backgroundColor = .black

        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        externalWindow = window
    }

    private func tearDownTVWindow() {
        externalWindow?.isHidden = true
        externalWindow = nil
    }

    // MARK: - Helpers

    private func hasExternalScreen() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen !== UIScreen.main }
    }
}
