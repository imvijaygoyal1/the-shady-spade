import Foundation

enum MultiplayerActionValidation: Equatable {
    case accepted
    case rejected(MultiplayerActionRejection)
}

enum MultiplayerActionRejection: Equatable {
    case invalidPlayerIndex(Int)
    case wrongTurn(expected: Int, actual: Int)
    case invalidBid(amount: Int, minimum: Int, maximum: Int)
    case duplicateCalledCards(String)
    case invalidCalledCard(String)
    case bidderOwnedCalledCard(String)
    case invalidCardID(String)
    case cardNotInHand(String)
    case illegalCardPlay(String)
}

enum MultiplayerActionValidator {
    static func validateTurn(playerIndex: Int, currentActionPlayer: Int) -> MultiplayerActionValidation {
        guard GameFlowRules.isValidSeat(playerIndex) else {
            return .rejected(.invalidPlayerIndex(playerIndex))
        }

        guard playerIndex == currentActionPlayer else {
            return .rejected(.wrongTurn(expected: currentActionPlayer, actual: playerIndex))
        }

        return .accepted
    }

    static func validateBid(
        playerIndex: Int,
        amount: Int,
        currentActionPlayer: Int,
        highBid: Int
    ) -> MultiplayerActionValidation {
        let turnValidation = validateTurn(playerIndex: playerIndex, currentActionPlayer: currentActionPlayer)
        guard turnValidation == .accepted else { return turnValidation }

        guard GameFlowRules.isValidBid(amount, highBid: highBid) else {
            return .rejected(.invalidBid(
                amount: amount,
                minimum: GameFlowRules.minimumBid(after: highBid),
                maximum: GameFlowRules.maximumBid
            ))
        }

        return .accepted
    }

    static func validatePass(playerIndex: Int, currentActionPlayer: Int) -> MultiplayerActionValidation {
        validateTurn(playerIndex: playerIndex, currentActionPlayer: currentActionPlayer)
    }

    static func validateCalledCards(
        playerIndex: Int,
        currentActionPlayer: Int,
        calledCard1: String,
        calledCard2: String,
        bidderHand: [Card]
    ) -> MultiplayerActionValidation {
        let turnValidation = validateTurn(playerIndex: playerIndex, currentActionPlayer: currentActionPlayer)
        guard turnValidation == .accepted else { return turnValidation }

        guard calledCard1 != calledCard2 else {
            return .rejected(.duplicateCalledCards(calledCard1))
        }

        let deckIds = Set(AIEngine.fullDeck.map(\.id))
        guard deckIds.contains(calledCard1) else {
            return .rejected(.invalidCalledCard(calledCard1))
        }
        guard deckIds.contains(calledCard2) else {
            return .rejected(.invalidCalledCard(calledCard2))
        }

        let bidderHandIds = Set(bidderHand.map(\.id))
        if bidderHandIds.contains(calledCard1) {
            return .rejected(.bidderOwnedCalledCard(calledCard1))
        }
        if bidderHandIds.contains(calledCard2) {
            return .rejected(.bidderOwnedCalledCard(calledCard2))
        }

        return .accepted
    }

    static func validateCardPlay(
        playerIndex: Int,
        currentActionPlayer: Int,
        cardId: String,
        hand: [Card],
        currentTrick: [(playerIndex: Int, card: Card)]
    ) -> MultiplayerActionValidation {
        let turnValidation = validateTurn(playerIndex: playerIndex, currentActionPlayer: currentActionPlayer)
        guard turnValidation == .accepted else { return turnValidation }

        let deckIds = Set(AIEngine.fullDeck.map(\.id))
        guard deckIds.contains(cardId) else {
            return .rejected(.invalidCardID(cardId))
        }

        guard hand.contains(where: { $0.id == cardId }) else {
            return .rejected(.cardNotInHand(cardId))
        }

        guard GameFlowRules.validCardsToPlay(hand: hand, currentTrick: currentTrick).contains(cardId) else {
            return .rejected(.illegalCardPlay(cardId))
        }

        return .accepted
    }
}
