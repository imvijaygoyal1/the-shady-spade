import Foundation

struct ScorekeeperGameState: Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var playerNames: [String]
    var rounds: [ScorekeeperRoundEntry]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        playerNames: [String],
        rounds: [ScorekeeperRoundEntry] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.playerNames = Self.normalizedPlayerNames(playerNames)
        self.rounds = rounds
    }

    var runningScores: [Int] {
        rounds.reduce(Array(repeating: 0, count: 6)) { scores, round in
            zip(scores, round.scoreDeltas).map(+)
        }
    }

    var nextDealerIndex: Int {
        rounds.count % 6
    }

    var nextRoundNumber: Int {
        rounds.count + 1
    }

    var winnerIndex: Int {
        let scores = runningScores
        return scores.indices.max { scores[$0] < scores[$1] } ?? 0
    }

    func name(for index: Int) -> String {
        playerNames[safe: index] ?? "Player \(index + 1)"
    }

    mutating func appendRound(_ draft: ScorekeeperRoundDraft) {
        rounds.append(ScorekeeperRoundEntry(draft: draft, roundNumber: nextRoundNumber))
    }

    mutating func replaceLastRound(with draft: ScorekeeperRoundDraft) {
        guard let last = rounds.last else { return }
        rounds[rounds.count - 1] = ScorekeeperRoundEntry(draft: draft, roundNumber: last.roundNumber)
    }

    mutating func deleteLastRound() {
        guard !rounds.isEmpty else { return }
        rounds.removeLast()
    }

    mutating func updatePlayerNames(_ names: [String]) {
        playerNames = Self.normalizedPlayerNames(names)
    }

    static func normalizedPlayerNames(_ names: [String]) -> [String] {
        (0..<6).map { index in
            let trimmed = (names[safe: index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        }
    }
}

struct ScorekeeperRoundEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var roundNumber: Int
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuit: TrumpSuit
    var partner1Index: Int
    var partner2Index: Int
    var offensePointsCaught: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        roundNumber: Int,
        dealerIndex: Int,
        bidderIndex: Int,
        bidAmount: Int,
        trumpSuit: TrumpSuit,
        partner1Index: Int,
        partner2Index: Int,
        offensePointsCaught: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.roundNumber = roundNumber
        self.dealerIndex = dealerIndex
        self.bidderIndex = bidderIndex
        self.bidAmount = bidAmount
        self.trumpSuit = trumpSuit
        self.partner1Index = partner1Index
        self.partner2Index = partner2Index
        self.offensePointsCaught = offensePointsCaught
        self.createdAt = createdAt
    }

    init(draft: ScorekeeperRoundDraft, roundNumber: Int) {
        self.init(
            roundNumber: roundNumber,
            dealerIndex: draft.dealerIndex,
            bidderIndex: draft.bidderIndex,
            bidAmount: draft.bidAmount,
            trumpSuit: draft.trumpSuit,
            partner1Index: draft.partner1Index,
            partner2Index: draft.partner2Index,
            offensePointsCaught: draft.generatedOffensePointsCaught
        )
    }

    var offenseIndices: Set<Int> {
        [bidderIndex, partner1Index, partner2Index]
    }

    var bidMade: Bool {
        offensePointsCaught >= bidAmount
    }

    var defensePointsCaught: Int {
        max(0, 250 - offensePointsCaught)
    }

    var scoreDeltas: [Int] {
        ScoringEngine.calculateRoundScores(
            bidAmount: bidAmount,
            bidderIndex: bidderIndex,
            offenseIndices: offenseIndices,
            bidMade: bidMade
        ).playerDeltas
    }
}

struct ScorekeeperRoundDraft: Equatable {
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuit: TrumpSuit
    var partner1Index: Int
    var partner2Index: Int
    var bidMade: Bool

    init(nextDealerIndex: Int = 0) {
        self.dealerIndex = nextDealerIndex
        self.bidderIndex = Self.bidStarterIndex(afterDealer: nextDealerIndex)
        self.bidAmount = 130
        self.trumpSuit = .spades
        self.partner1Index = Self.nextIndex(after: bidderIndex)
        self.partner2Index = Self.nextIndex(after: partner1Index)
        self.bidMade = true
    }

    init(round: ScorekeeperRoundEntry) {
        self.dealerIndex = round.dealerIndex
        self.bidderIndex = round.bidderIndex
        self.bidAmount = round.bidAmount
        self.trumpSuit = round.trumpSuit
        self.partner1Index = round.partner1Index
        self.partner2Index = round.partner2Index
        self.bidMade = round.bidMade
    }

    var generatedOffensePointsCaught: Int {
        bidMade ? bidAmount : max(0, bidAmount - 5)
    }

    var bidStarterIndex: Int {
        Self.bidStarterIndex(afterDealer: dealerIndex)
    }

    var validationMessage: String? {
        guard (0..<6).contains(dealerIndex),
              (0..<6).contains(bidderIndex),
              (0..<6).contains(partner1Index),
              (0..<6).contains(partner2Index) else {
            return "Choose valid players."
        }

        guard (130...240).contains(bidAmount) else {
            return "Bid must be between 130 and 240."
        }

        guard bidderIndex != dealerIndex else {
            return "Dealer cannot be the bidder."
        }

        guard partner1Index != bidderIndex,
              partner2Index != bidderIndex else {
            return "Partners cannot be the bidder."
        }

        guard partner1Index != partner2Index else {
            return "Partners must be two different players."
        }

        return nil
    }

    private static func bidStarterIndex(afterDealer dealerIndex: Int) -> Int {
        nextIndex(after: dealerIndex)
    }

    private static func nextIndex(after index: Int) -> Int {
        (index + 1) % 6
    }
}

@Observable final class ScorekeeperStore {
    private static let storageKey = "scorekeeper_active_game_v1"
    private let defaults: UserDefaults

    var activeGame: ScorekeeperGameState?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults == .standard, Self.shouldResetForUITests {
            defaults.removeObject(forKey: Self.storageKey)
        }
        self.activeGame = Self.load(from: defaults)
    }

    func start(playerNames: [String]) {
        activeGame = ScorekeeperGameState(playerNames: playerNames)
        persist()
    }

    func updatePlayerNames(_ names: [String]) {
        activeGame?.updatePlayerNames(names)
        persist()
    }

    func addRound(_ draft: ScorekeeperRoundDraft) {
        guard draft.validationMessage == nil else { return }
        if activeGame == nil {
            activeGame = ScorekeeperGameState(playerNames: [])
        }
        activeGame?.appendRound(draft)
        persist()
    }

    func replaceLastRound(with draft: ScorekeeperRoundDraft) {
        guard draft.validationMessage == nil else { return }
        activeGame?.replaceLastRound(with: draft)
        persist()
    }

    func deleteLastRound() {
        activeGame?.deleteLastRound()
        persist()
    }

    func clearActiveGame() {
        activeGame = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let activeGame,
              let data = try? JSONEncoder().encode(activeGame) else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> ScorekeeperGameState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ScorekeeperGameState.self, from: data)
    }

    private static var shouldResetForUITests: Bool {
        let process = ProcessInfo.processInfo
        return process.arguments.contains("-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS")
            || process.environment["SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS"] == "1"
    }
}
