import SwiftUI
import SwiftData
import FirebaseCore
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
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

    init() {
        _authVM = State(initialValue: AuthViewModel())
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            // didFinishLaunchingWithOptions has already run at this point,
            // so Firebase is configured and it is safe to start the auth listener.
            .task { authVM.start() }
        }
        .modelContainer(for: [Round.self, GameHistory.self, HistoryRound.self])
        .environment(authVM)
    }
}
