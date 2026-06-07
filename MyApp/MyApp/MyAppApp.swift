import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth
import UIKit

@Observable final class DeepLinkManager {
    static let shared = DeepLinkManager()
    var pendingJoinCode: String? = nil
}

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
    @Environment(\.colorScheme) private var colorScheme
    @State private var authVM: AuthViewModel
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        _authVM = State(initialValue: AuthViewModel())
        ThemeManager.shared.loadSavedTheme()
        Self.migrateUserDefaultsIfNeeded()
    }

    private static func migrateUserDefaultsIfNeeded() {
        // Increment currentSchemaVersion whenever PendingGameRecord's Codable layout changes.
        // On a schema bump, records that can't be decoded with the new layout are cleared
        // rather than crashing; records are persisted for reliability, not correctness.
        let currentSchemaVersion = 1
        let storedVersion = UserDefaults.standard.integer(forKey: "leaderboard_schema_version")
        guard storedVersion < currentSchemaVersion else { return }

        if let data = UserDefaults.standard.data(forKey: "leaderboard_pending_records_v1"),
           (try? JSONDecoder().decode([PendingGameRecord].self, from: data)) == nil {
            UserDefaults.standard.removeObject(forKey: "leaderboard_pending_records_v1")
        }

        UserDefaults.standard.set(currentSchemaVersion, forKey: "leaderboard_schema_version")
    }

    private func handleIncomingURL(_ url: URL) {
        // Handles shadyspade://join/ROOMCODE
        // and https://shadyspade-d6b84.web.app/shadyspade/join/ROOMCODE
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let joinIndex = parts.firstIndex(of: "join"), joinIndex + 1 < parts.count else { return }
        let roomCode = parts[joinIndex + 1]
        guard !roomCode.isEmpty else { return }
        guard roomCode.count == 6,
              roomCode.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return }
        // Store for cold-start deep link (CreateOrJoinView reads this on appear)
        DeepLinkManager.shared.pendingJoinCode = roomCode
        // Also notify in case CreateOrJoinView is already mounted (foreground tap)
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
            .onAppear {
                themeManager.updateSystemColorScheme(colorScheme)
            }
            .onChange(of: colorScheme) { _, newScheme in
                themeManager.updateSystemColorScheme(newScheme)
            }
            // didFinishLaunchingWithOptions has already run at this point,
            // so Firebase is configured and it is safe to start the auth listener.
            .task {
                authVM.start()
                LeaderboardService.shared.startListening()
                TVDisplayManager.shared.startMonitoring()
            }
            .onOpenURL { url in handleIncomingURL(url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    handleIncomingURL(url)
                }
            }
        }
        .modelContainer(for: [Round.self, GameHistory.self, HistoryRound.self])
        .environment(authVM)
    }
}
