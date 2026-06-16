import Foundation
import Observation

enum LeaderboardConsentState: String {
    case undecided
    case granted
    case denied
}

@Observable
@MainActor
final class LeaderboardConsentManager {
    static let shared = LeaderboardConsentManager()

    private let key = "leaderboardConsentState"

    private(set) var state: LeaderboardConsentState = .undecided

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let s = LeaderboardConsentState(rawValue: raw) {
            state = s
        }
    }

    var isGranted: Bool { state == .granted }

    func grant() {
        state = .granted
        UserDefaults.standard.set(state.rawValue, forKey: key)
    }

    func deny() {
        state = .denied
        UserDefaults.standard.set(state.rawValue, forKey: key)
    }
}
