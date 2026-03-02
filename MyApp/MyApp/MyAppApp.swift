import SwiftUI
import SwiftData
import FirebaseCore

@main
struct MyAppApp: App {
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
        .modelContainer(for: Round.self)
        .environment(authVM)
    }
}
