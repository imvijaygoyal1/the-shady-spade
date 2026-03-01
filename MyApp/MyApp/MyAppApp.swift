import SwiftUI
import SwiftData

@main
struct MyAppApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(for: Round.self)
    }
}
