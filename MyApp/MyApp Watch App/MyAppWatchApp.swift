import SwiftUI

@main
struct MyAppWatchApp: App {
    @State private var viewModel = WatchScorekeeperViewModel()

    var body: some Scene {
        WindowGroup {
            WatchScorekeeperView(viewModel: viewModel)
        }
    }
}
