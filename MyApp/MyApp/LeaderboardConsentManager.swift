import Foundation
import Observation

enum LeaderboardConsentState: String {
    case undecided
    case granted
    case denied

    var allowsLeaderboardUpload: Bool {
        self == .granted
    }

    static func resolvedStoredState(
        rawValue: String?,
        storedDisclosureVersion: Int,
        currentDisclosureVersion: Int
    ) -> LeaderboardConsentState {
        let storedState = rawValue.flatMap(LeaderboardConsentState.init(rawValue:)) ?? .undecided
        if storedState == .granted && storedDisclosureVersion < currentDisclosureVersion {
            return .undecided
        }
        return storedState
    }
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
        let raw = UserDefaults.standard.string(forKey: key)
        let storedDisclosureVersion = UserDefaults.standard.integer(forKey: disclosureVersionKey)
        state = LeaderboardConsentState.resolvedStoredState(
            rawValue: raw,
            storedDisclosureVersion: storedDisclosureVersion,
            currentDisclosureVersion: currentDisclosureVersion
        )
        UserDefaults.standard.set(state.rawValue, forKey: key)
    }

    var isGranted: Bool { state.allowsLeaderboardUpload }

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
