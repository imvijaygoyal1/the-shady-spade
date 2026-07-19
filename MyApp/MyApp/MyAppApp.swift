import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAuth
import UIKit

@Observable final class DeepLinkManager {
    static let shared = DeepLinkManager()
    var pendingJoinCode: String? = nil
    var pendingScorekeeperCode: String? = nil
}

enum AppDeepLinkRoute: Equatable {
    case join(String)
    case scorekeeper(String)
}

enum AppDeepLinkRouter {
    static func route(for url: URL) -> AppDeepLinkRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        let rawParts = [components.host].compactMap { $0 } + components.path.split(separator: "/").map(String.init)
        let routeParts = rawParts.map { $0.lowercased() }

        if let join = code(after: "join", routeParts: routeParts, rawParts: rawParts) {
            return .join(join)
        }
        if let scorekeeper = code(after: "scorekeeper", routeParts: routeParts, rawParts: rawParts) {
            return .scorekeeper(scorekeeper)
        }
        return nil
    }

    private static func code(after route: String, routeParts: [String], rawParts: [String]) -> String? {
        guard let index = routeParts.firstIndex(of: route), index + 1 < rawParts.count else { return nil }
        let code = ScorekeeperSessionService.normalizedSessionCode(rawParts[index + 1])
        guard ScorekeeperSessionService.isValidSessionCode(code) else { return nil }
        return code
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        if !MyAppApp.isRunningUITests {
            signInAnonymouslyIfNeeded()
        }
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
    static let isRunningUITests = ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_UI_TESTING")

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        if Self.isRunningUITests {
            UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        }
        if ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS") {
            UserDefaults.standard.removeObject(forKey: "scorekeeper_active_game_v1")
        }
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
        // Handles:
        // shadyspade://join/ROOMCODE
        // shadyspade://scorekeeper/ROOMCODE
        // https://shadyspade-d6b84.web.app/shadyspade/join/ROOMCODE
        // https://shadyspade-d6b84.web.app/shadyspade/scorekeeper/ROOMCODE
        switch AppDeepLinkRouter.route(for: url) {
        case .join(let join):
            DeepLinkManager.shared.pendingJoinCode = join
            NotificationCenter.default.post(
                name: .joinRoomFromQR,
                object: nil,
                userInfo: ["roomCode": join]
            )
        case .scorekeeper(let scorekeeper):
            DeepLinkManager.shared.pendingScorekeeperCode = scorekeeper
        case nil:
            return
        }
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
            // so Firebase is configured and leaderboard listeners can attach.
            .task {
                if !Self.isRunningUITests {
                    LeaderboardService.shared.startListening()
                    TVDisplayManager.shared.startMonitoring()
                }
            }
            .onOpenURL { url in handleIncomingURL(url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    handleIncomingURL(url)
                }
            }
        }
        .modelContainer(for: [Round.self, GameHistory.self, HistoryRound.self])
    }
}
