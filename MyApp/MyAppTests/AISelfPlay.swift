//
//  AISelfPlay.swift
//  MyAppTests
//
//  A headless game, so bot changes can be measured instead of played.
//
//  `AIEngine` is 31 static functions importing only Foundation — no view model, no UI, no state —
//  so a full hand can be dealt, bid, called, played and scored without a simulator or a person.
//  That is the whole point: the owner should not have to sit through hands to find out whether a
//  heuristic helped.
//
//  ## The metric that matters
//
//  `pointsFedToOpponents` — every point card a bot discards into a trick the *other* side wins.
//  This is the number that would have caught AI-01 without anyone playing: a defender treated every
//  unknown player as a teammate, so with 3 v 3 teams and two hidden partners, roughly half of its
//  "throw points to my teammate" decisions fed the opposition.
//
//  ## Determinism
//
//  Deals come from a seeded SplitMix64, not `SystemRandomNumberGenerator`, so a run is reproducible
//  and two configurations can be compared over the *same* deals. The receipt benchmark taught this
//  the hard way: a baseline that moves between runs cannot tell you whether a change helped or the
//  dice did, and there the dice were louder than the change.
//

import XCTest
@testable import MyApp

// MARK: - Seeded RNG

/// SplitMix64 — small, fast, and seedable, which `SystemRandomNumberGenerator` is not.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - One hand

enum AISelfPlay {

    struct HandResult {
        let seed: UInt64
        let bidderIndex: Int
        let highBid: Int
        let offenseSeats: Set<Int>
        let offensePoints: Int
        var bidMade: Bool { offensePoints >= highBid }

        /// Point cards played into a trick the other side won, per seat — **including cards the
        /// bot had no choice about**. Following suit with nothing but point cards is not a mistake.
        let pointsFedToOpponents: [Int]
        /// Point cards played into a trick your own side won — the good kind of feeding.
        let pointsFedToTeammates: [Int]
        /// The metric that actually means something: point cards given to the opposition **when a
        /// zero-point legal alternative was in hand**. A forced discard is not a misplay; this is.
        let avoidableMisfeeds: [Int]
        /// Trick points captured per seat — the other half of the ledger. A style that gives away
        /// less but also wins less is not obviously better.
        let pointsWon: [Int]
        /// The trick (1-based) on which each called card was played, i.e. when that partner became
        /// public. `nil` means the card was never played this hand.
        ///
        /// This is what decides when the **defence** becomes known: `resolveAvatarRole` only labels
        /// anyone defence once **both** partners are revealed, so an early second reveal exposes the
        /// whole table. `AIEngine` has deliberate reveal logic (`hiddenPartnerRevealCard`,
        /// `partnerRevealIntent`), so this measures whether that logic is firing too eagerly.
        let partnerRevealTricks: [Int?]
        /// The trick on which the **last** partner revealed — the moment the defence is exposed.
        var defenceExposedOnTrick: Int? {
            let known = partnerRevealTricks.compactMap { $0 }
            return known.count == partnerRevealTricks.count ? known.max() : nil
        }
        /// A bot returning nil or an illegal card. Should always be zero; if it is not, every other
        /// number here is describing a different game from the one the app plays.
        let illegalPlays: Int
    }

    struct Options {
        /// AI-05: a bot bidder is normally handed `actualPartnerIndices` outright, while a human
        /// bidder sees only revealed partners. Set false to take that knowledge away and measure
        /// what it is worth.
        var bidderKnowsPartners = true

        /// AI-04: personality is normally `styles[seat % 5]`. Set this to give **every** seat the
        /// same style, which is how one personality's cost is isolated from the table it sits at.
        var personalityOverride: AIEngine.BotPersonality?
    }

    /// Plays one complete hand and reports what happened.
    ///
    /// Assumptions, stated because they are the harness's and not the app's: the bidder leads the
    /// first trick, and the dealer is forced to bid if everyone passes. Both match the common rules
    /// for this game shape; if the app disagrees, the *relative* comparisons here still hold,
    /// because every configuration plays under the same assumption.
    static func playHand(seed: UInt64, options: Options = Options()) -> HandResult {
        var rng = SplitMix64(seed: seed)
        var deck = AIEngine.fullDeck
        deck.shuffle(using: &rng)

        var hands: [[Card]] = (0..<6).map { seat in
            Array(deck[(seat * 8)..<((seat + 1) * 8)])
        }
        let dealer = Int(rng.next() % 6)

        // ── Bidding ───────────────────────────────────────────────────────────
        var bidHistory: [(playerIndex: Int, amount: Int)] = []
        var highBid = 0
        var highBidder = -1
        var passed = Set<Int>()

        var seat = (dealer + 1) % 6
        var safety = 0
        while passed.count < 5 && safety < 60 {
            safety += 1
            if !passed.contains(seat) {
                let bid = AIEngine.computeBid(
                    seat: seat, hand: hands[seat], dealerIndex: dealer,
                    highBid: highBid, canPass: true,
                    personality: options.personalityOverride ?? AIEngine.BotPersonality.forSeat(seat),
                    bidHistory: bidHistory)
                if bid == 0 {
                    passed.insert(seat)
                } else {
                    bidHistory.append((playerIndex: seat, amount: bid))
                    highBid = bid
                    highBidder = seat
                }
            }
            seat = (seat + 1) % 6
        }

        if highBidder < 0 {
            // Everyone passed: the dealer must take it.
            highBidder = dealer
            highBid = AIEngine.computeBid(
                seat: dealer, hand: hands[dealer], dealerIndex: dealer,
                highBid: 0, canPass: false,
                personality: options.personalityOverride ?? .forSeat(dealer), bidHistory: bidHistory)
            bidHistory.append((playerIndex: dealer, amount: highBid))
        }

        // ── Calling ───────────────────────────────────────────────────────────
        let call = AIEngine.computeCalling(
            hand: hands[highBidder], seat: highBidder, dealerIndex: dealer,
            bidHistory: bidHistory,
            personality: options.personalityOverride ?? .forSeat(highBidder))
        let trump = call.trump
        let calledIds: Set<String> = [call.c1, call.c2]

        let partners = Set((0..<6).filter { s in
            s != highBidder && hands[s].contains { calledIds.contains($0.id) }
        })
        let offense = partners.union([highBidder])

        // ── Play ──────────────────────────────────────────────────────────────
        var completed: [[(playerIndex: Int, card: Card)]] = []
        var wonPoints = Array(repeating: 0, count: 6)
        var revealed = Set<Int>()
        var fedOpponents = Array(repeating: 0, count: 6)
        var fedTeammates = Array(repeating: 0, count: 6)
        var avoidable = Array(repeating: 0, count: 6)
        var revealTricks: [String: Int] = [:]
        var hadZeroPointAlternative = Array(repeating: false, count: 6)
        var illegal = 0
        var leader = highBidder

        for trickNumber in 0..<8 {
            var trick: [(playerIndex: Int, card: Card)] = []
            for offset in 0..<6 {
                let s = (leader + offset) % 6
                let legal = legalCards(hand: hands[s], trick: trick, trump: trump)

                let chosenID = AIEngine.computeCard(
                    seat: s,
                    hand: hands[s],
                    actualPartnerIndices: partnerKnowledge(
                        seat: s, highBidder: highBidder, partners: partners, options: options),
                    revealedPartnerIndices: revealed,
                    calledCardIds: calledIds,
                    highBidderIndex: highBidder,
                    trumpSuit: trump,
                    currentTrick: trick,
                    completedTricks: completed,
                    wonPointsPerPlayer: wonPoints,
                    highBid: highBid,
                    trickNumber: trickNumber,
                    personality: options.personalityOverride ?? .forSeat(s),
                    bidHistory: bidHistory)

                let card: Card
                if let chosenID, let picked = legal.first(where: { $0.id == chosenID }) {
                    card = picked
                } else {
                    illegal += 1
                    card = legal[0]
                }

                // Recorded before the card leaves the hand: could this bot have played a
                // worthless card instead of a valuable one?
                hadZeroPointAlternative[s] = card.pointValue > 0 && legal.contains { $0.pointValue == 0 }

                hands[s].removeAll { $0.id == card.id }
                trick.append((playerIndex: s, card: card))
                if calledIds.contains(card.id) && s != highBidder {
                    revealed.insert(s)
                    revealTricks[card.id] = trickNumber + 1   // 1-based, as a player would count
                }
            }

            let winner = AIEngine.trickWinnerIndex(trick: trick, trumpSuit: trump)
            let trickPoints = trick.map(\.card.pointValue).reduce(0, +)
            wonPoints[winner] += trickPoints
            completed.append(trick)

            let winnerIsOffense = offense.contains(winner)
            for entry in trick where entry.playerIndex != winner && entry.card.pointValue > 0 {
                let playerIsOffense = offense.contains(entry.playerIndex)
                if playerIsOffense == winnerIsOffense {
                    fedTeammates[entry.playerIndex] += entry.card.pointValue
                } else {
                    fedOpponents[entry.playerIndex] += entry.card.pointValue
                    if hadZeroPointAlternative[entry.playerIndex] {
                        avoidable[entry.playerIndex] += entry.card.pointValue
                    }
                }
            }
            leader = winner
        }

        let offensePoints = offense.reduce(0) { $0 + wonPoints[$1] }
        return HandResult(
            seed: seed, bidderIndex: highBidder, highBid: highBid,
            offenseSeats: offense, offensePoints: offensePoints,
            pointsFedToOpponents: fedOpponents, pointsFedToTeammates: fedTeammates,
            avoidableMisfeeds: avoidable, pointsWon: wonPoints,
            partnerRevealTricks: [revealTricks[call.c1], revealTricks[call.c2]],
            illegalPlays: illegal)
    }

    /// What the engine is told about partner identities.
    ///
    /// `knownOffenseSet` hands `actualPartnerIndices` straight to the bidder, so a bot bidder plays
    /// from trick 1 knowing its partners while a human bidder does not (AI-05). Making that a knob
    /// is how the edge gets a number attached instead of an opinion.
    private static func partnerKnowledge(
        seat: Int, highBidder: Int, partners: Set<Int>, options: Options
    ) -> Set<Int> {
        guard options.bidderKnowsPartners || seat != highBidder else { return [] }
        return partners
    }

    /// Follow suit if you can. The engine has its own legality filter; this is the referee, so a
    /// bug there shows up as `illegalPlays` rather than as a quietly different game.
    private static func legalCards(
        hand: [Card], trick: [(playerIndex: Int, card: Card)], trump: TrumpSuit
    ) -> [Card] {
        guard let led = trick.first?.card.suit else { return hand }
        let following = hand.filter { $0.suit == led }
        return following.isEmpty ? hand : following
    }
}

// MARK: - Batch + report

extension AISelfPlay {

    struct Summary {
        let hands: Int
        let bidMadeRate: Double
        let avgOffensePoints: Double
        let avgFedToOpponentsPerHand: Double
        let avgFedToTeammatesPerHand: Double
        let avgAvoidableMisfeedsPerHand: Double
        /// Per seat, so the seat-assigned personality can be attributed directly.
        let avoidableMisfeedsBySeat: [Double]
        let pointsWonBySeat: [Double]
        let illegalPlays: Int
        /// Fed-to-opponents as a share of all point cards deliberately released into a trick
        /// somebody else won. The cleanest read on "does this bot know whose trick it is".
        var misfeedShare: Double {
            let total = avgFedToOpponentsPerHand + avgFedToTeammatesPerHand
            return total == 0 ? 0 : avgFedToOpponentsPerHand / total
        }
    }

    static func run(hands: Int, firstSeed: UInt64 = 1, options: Options = Options()) -> Summary {
        var made = 0, offensePts = 0, fedOpp = 0, fedMate = 0, avoidable = 0, illegal = 0
        var avoidableSeat = Array(repeating: 0, count: 6)
        var wonSeat = Array(repeating: 0, count: 6)
        for i in 0..<hands {
            let r = playHand(seed: firstSeed &+ UInt64(i), options: options)
            for s in 0..<6 {
                avoidableSeat[s] += r.avoidableMisfeeds[s]
                wonSeat[s] += r.pointsWon[s]
            }
            if r.bidMade { made += 1 }
            offensePts += r.offensePoints
            fedOpp += r.pointsFedToOpponents.reduce(0, +)
            fedMate += r.pointsFedToTeammates.reduce(0, +)
            avoidable += r.avoidableMisfeeds.reduce(0, +)
            illegal += r.illegalPlays
        }
        let n = Double(hands)
        return Summary(
            hands: hands,
            bidMadeRate: Double(made) / n,
            avgOffensePoints: Double(offensePts) / n,
            avgFedToOpponentsPerHand: Double(fedOpp) / n,
            avgFedToTeammatesPerHand: Double(fedMate) / n,
            avgAvoidableMisfeedsPerHand: Double(avoidable) / n,
            avoidableMisfeedsBySeat: avoidableSeat.map { Double($0) / n },
            pointsWonBySeat: wonSeat.map { Double($0) / n },
            illegalPlays: illegal)
    }
}
