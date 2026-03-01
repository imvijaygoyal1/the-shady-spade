import SwiftUI
import SwiftData
import Observation

// MARK: - Game View Model

@Observable
final class GameViewModel {

    // MARK: Persisted data
    var rounds: [Round] = []

    // MARK: Add-Round form state
    var dealerIndex: Int      = 0
    var biddingTeam: Team     = .a
    var bidAmount: Double     = 130
    var teamAPoints: Int      = 0
    var teamBPoints: Int      = 0
    var shadySpadeTeam: Team? = nil
    var trumpSuit: TrumpSuit  = .spades

    // MARK: Navigation
    var showingAddRound: Bool = false

    // MARK: Private
    private var context: ModelContext?

    // MARK: - Setup

    func setup(with context: ModelContext) {
        self.context = context
        fetchRounds()
    }

    // MARK: - CRUD

    func fetchRounds() {
        guard let context else { return }
        let descriptor = FetchDescriptor<Round>(
            sortBy: [SortDescriptor(\.roundNumber, order: .reverse)]
        )
        rounds = (try? context.fetch(descriptor)) ?? []
    }

    func addRound() {
        guard let context else { return }

        let round = Round(
            roundNumber:       nextRoundNumber,
            dealerIndex:       dealerIndex,
            biddingTeam:       biddingTeam,
            bidAmount:         Int(bidAmount),
            teamAPointsCaught: teamAPoints,
            teamBPointsCaught: teamBPoints,
            shadySpadeTeam:    shadySpadeTeam,
            trumpSuit:         trumpSuit
        )
        context.insert(round)
        try? context.save()

        // Haptics based on outcome
        if round.isSet { HapticManager.error() } else { HapticManager.success() }

        fetchRounds()
        advanceDealer()
        resetFormFields()
        showingAddRound = false
    }

    func deleteRound(_ round: Round) {
        guard let context else { return }
        context.delete(round)
        try? context.save()
        fetchRounds()
    }

    // MARK: - Point helpers (called from UI)

    func adjustPoints(team: Team, delta: Int) {
        HapticManager.impact(.light)
        if team == .a {
            teamAPoints = max(0, min(250, teamAPoints + delta))
        } else {
            teamBPoints = max(0, min(250, teamBPoints + delta))
        }
    }

    // MARK: - Computed

    var teamATotal: Int      { rounds.reduce(0) { $0 + $1.teamAScore } }
    var teamBTotal: Int      { rounds.reduce(0) { $0 + $1.teamBScore } }
    var nextRoundNumber: Int { (rounds.map(\.roundNumber).max() ?? 0) + 1 }

    var totalPointsEntered: Int { teamAPoints + teamBPoints }
    var isFormValid: Bool {
        teamAPoints >= 0 && teamBPoints >= 0 && totalPointsEntered <= 250
    }

    // MARK: - Private helpers

    private func advanceDealer() { dealerIndex = (dealerIndex + 1) % 6 }

    private func resetFormFields() {
        biddingTeam     = .a
        bidAmount       = 130
        teamAPoints     = 0
        teamBPoints     = 0
        shadySpadeTeam  = nil
        trumpSuit       = .spades
    }
}
