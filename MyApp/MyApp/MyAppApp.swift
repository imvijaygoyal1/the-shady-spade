import SwiftUI
import SwiftData
import FirebaseCore
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
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

    init() {
        FirebaseApp.configure()          // must happen first
        _authVM = State(initialValue: AuthViewModel())
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedSetup {
                ModeSelectionView()
                    .preferredColorScheme(.dark)
            } else {
                SplashView {
                    hasCompletedSetup = true
                }
                .preferredColorScheme(.dark)
            }
        }
        .modelContainer(for: [Round.self, GameHistory.self, HistoryRound.self])
        .environment(authVM)
    }
}
