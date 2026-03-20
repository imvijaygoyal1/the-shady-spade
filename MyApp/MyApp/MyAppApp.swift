import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        signInAnonymouslyIfNeeded()
        return true
    }

    private func signInAnonymouslyIfNeeded() {
        guard Auth.auth().currentUser == nil else { return }
        Auth.auth().signInAnonymously { _, error in
            if let error {
                print("Anonymous auth error: \(error)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return [.portrait, .landscapeLeft, .landscapeRight]
    }
}

@main
struct MyAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var authVM: AuthViewModel
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        _authVM = State(initialValue: AuthViewModel())
        ThemeManager.shared.loadSavedTheme()
    }

    private func handleIncomingURL(_ url: URL) {
        // Handles shadyspade://join/ROOMCODE
        // and https://imvijaygoyal1.github.io/shadyspade/join/ROOMCODE
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let joinIndex = parts.firstIndex(of: "join"), joinIndex + 1 < parts.count else { return }
        let roomCode = parts[joinIndex + 1]
        guard !roomCode.isEmpty else { return }
        NotificationCenter.default.post(
            name: .joinRoomFromQR,
            object: nil,
            userInfo: ["roomCode": roomCode]
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedSetup {
                    ModeSelectionView()
                } else {
                    SplashView {
                        hasCompletedSetup = true
                    }
                }
            }
            .preferredColorScheme(themeManager.preferredColorScheme)
            .environmentObject(themeManager)
            // didFinishLaunchingWithOptions has already run at this point,
            // so Firebase is configured and it is safe to start the auth listener.
            .task { authVM.start() }
            .onOpenURL { url in handleIncomingURL(url) }
        }
        .modelContainer(for: [Round.self, GameHistory.self, HistoryRound.self])
        .environment(authVM)
    }
}
