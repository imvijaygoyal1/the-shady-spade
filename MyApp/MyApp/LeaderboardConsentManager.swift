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
    private let disclosureVersionKey = "leaderboardConsentDisclosureVersion"
    private let currentDisclosureVersion = 2

    private(set) var state: LeaderboardConsentState = .undecided

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let s = LeaderboardConsentState(rawValue: raw) {
            state = s
        }

        let storedDisclosureVersion = UserDefaults.standard.integer(forKey: disclosureVersionKey)
        if state == .granted && storedDisclosureVersion < currentDisclosureVersion {
            state = .undecided
            UserDefaults.standard.set(state.rawValue, forKey: key)
        }
    }

    var isGranted: Bool { state == .granted }

    func grant() {
        state = .granted
        UserDefaults.standard.set(state.rawValue, forKey: key)
        UserDefaults.standard.set(currentDisclosureVersion, forKey: disclosureVersionKey)
        Task { await LeaderboardService.shared.syncPendingRecordsIfAllowed() }
    }

    func deny() {
        state = .denied
        UserDefaults.standard.set(state.rawValue, forKey: key)
        UserDefaults.standard.set(currentDisclosureVersion, forKey: disclosureVersionKey)
        LeaderboardService.shared.discardPendingRecords()
    }
}
