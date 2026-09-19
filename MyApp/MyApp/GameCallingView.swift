import SwiftUI

/// What the shared multiplayer calling screen needs from a game.
///
/// Inherits `Observable` because this screen *writes* back — the bidder's trump
/// and called-card choices live on the view model and are edited through
/// `@Bindable`, unlike the read-only round-summary and playing protocols.
///
/// The two copies were 372 and 366 lines and differed by **15 behavioural
/// lines**: the `private` keyword, the name of the confirm method, and one
/// blocked-suit treatment (SPADE-02).
@MainActor
protocol MultiplayerCallingState: AnyObject, Observable {
    var myPlayerIndex: Int { get }
    var highBidderIndex: Int { get }
    var highBid: Int { get }
    var myHand: [Card] { get }
    var myHandSorted: [Card] { get }
    var trumpSuit: TrumpSuit { get }
    var calledCard1: String { get }
    var calledCard2: String { get }
    var callingValid: Bool { get }

    // Edited by the bidder on this screen.
    var trumpSuitSelection: TrumpSuit { get set }
    var calledCard1Rank: String { get set }
    var calledCard1Suit: String { get set }
    var calledCard2Rank: String { get set }
    var calledCard2Suit: String { get set }

    func playerName(_ index: Int) -> String
    func confirmCalling() async
}

extension OnlineGameViewModel: MultiplayerCallingState {}

extension BluetoothGameViewModel: MultiplayerCallingState {
    /// Bluetooth spells the same action `callTrumpAndCards`. Bridged here
    /// rather than passed as a closure, so the screen stays value-free.
    func confirmCalling() async { await callTrumpAndCards() }
}

/// The trump-and-called-cards screen for the two multiplayer modes.
///
/// Solo keeps `CallingCardsView`: 121 of its 296 presentation lines differ —
/// it drives an async continuation rather than a view model method, and has no
/// waiting branch because the human is always the one calling when this screen
/// appears.
struct GameCallingView<Game: MultiplayerCallingState>: View {
    @Bindable var game: Game
    @State private var isBlinking = false
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var isMyCall: Bool { game.myPlayerIndex == game.highBidderIndex }

    private func isCardTrump(_ card: Card) -> Bool { card.suit == game.trumpSuit.rawValue }
    private func isCardCalled(_ card: Card) -> Bool { card.id == game.calledCard1 || card.id == game.calledCard2 }

    var body: some View {
        if isMyCall {
            GameAdaptiveLayout {
                portraitCalling
            } landscape: {
                landscapeCalling
            }
        } else {
            waitingForBidder
        }
    }

    // MARK: - Bidder, portrait

    private var portraitCalling: some View {
        ScrollView {
            VStack(spacing: vSizeClass == .compact ? 14 : 22) {
                VStack(spacing: 6) {
                    Text("You won the bid!")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid) — call trump and 2 cards")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, vSizeClass == .compact ? 16 : 44)

                VStack(spacing: 12) {
                    SectionHeader(title: "Trump Suit")
                    trumpRow(spacing: 10, glyph: 26, label: 10, vPad: 10, innerSpacing: 6)
                }
                .padding().comicContainer(cornerRadius: 18)

                calledCardsBox()

                VStack(spacing: 10) {
                    SectionHeader(title: "Your Hand")
                    handRow(highlighting: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
            .adaptiveContentFrame()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                confirmButton(font: 20, height: 56)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .background(Comic.bg)
        }
    }

    // MARK: - Bidder, landscape

    private var landscapeCalling: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("You won the bid!")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                VStack(spacing: 10) {
                    SectionHeader(title: "Trump Suit")
                    trumpRow(spacing: 8, glyph: 22, label: 9, vPad: 8, innerSpacing: 4)
                }
                .padding()
                .comicContainer(cornerRadius: 18)

                Spacer()

                confirmButton(font: 18, height: 50)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Comic.containerBG)

            Rectangle().fill(Comic.containerBorder).frame(width: 1)

            ScrollView {
                VStack(spacing: 14) {
                    calledCardsBox()

                    VStack(spacing: 10) {
                        SectionHeader(title: "Your Hand")
                        handRow(highlighting: false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity)
            .background(Comic.bg)
        }
    }

    // MARK: - Not the bidder

    private var waitingForBidder: some View {
        ScrollView {
            VStack(spacing: vSizeClass == .compact ? 14 : 22) {
                VStack(spacing: 6) {
                    Text("\(game.playerName(game.highBidderIndex)) won the bid")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid) — calling trump and cards…")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, vSizeClass == .compact ? 16 : 44)

                Text("\(game.playerName(game.highBidderIndex)) is choosing trump and cards…")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.yellow)
                    .multilineTextAlignment(.center)
                    .opacity(isBlinking ? 1.0 : 0.2)
                    .animation(MyAppApp.isRunningUITests ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isBlinking)
                    .onAppear { isBlinking = true }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .comicContainer(cornerRadius: 20)
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    SectionHeader(title: "Your Hand")
                    handRow(highlighting: false)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
            .adaptiveContentFrame()
        }
    }

    // MARK: - Pieces

    private func trumpRow(spacing: CGFloat, glyph: CGFloat, label: CGFloat,
                          vPad: CGFloat, innerSpacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(TrumpSuit.allCases, id: \.rawValue) { suit in
                let sel = game.trumpSuitSelection == suit
                Button {
                    HapticManager.impact(.light)
                    game.trumpSuitSelection = suit
                } label: {
                    VStack(spacing: innerSpacing) {
                        Text(suit.rawValue).font(.system(size: glyph))
                            .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.55))
                        Text(suit.displayName).font(.system(size: label, weight: .black))
                            .foregroundStyle(sel ? Comic.textPrimary : Comic.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, vPad)
                    .background(sel ? Comic.yellow : Comic.containerBG)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(sel ? Comic.black : Comic.containerBorder,
                                          lineWidth: sel ? Comic.borderWidth : 1.5)
                    }
                }
                .buttonStyle(BouncyButton())
            }
        }
    }

    private func calledCardsBox() -> some View {
        VStack(spacing: 14) {
            SectionHeader(title: "Call Cards (must not be in your hand)")
            let handIds = Set(game.myHand.map(\.id))
            callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit, handIds: handIds)
            Divider().overlay(Comic.containerBorder)
            callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit, handIds: handIds)

            if !game.callingValid {
                let c1 = game.calledCard1Rank + game.calledCard1Suit
                let c2 = game.calledCard2Rank + game.calledCard2Suit
                Label(
                    c1 == c2 ? "Cards must be different" : "Cards must not be in your hand",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.defenseRose)
            }
        }
        .padding().comicContainer(cornerRadius: 18)
    }

    /// The bidder's own hand. Portrait marks trump and called cards; the
    /// landscape and waiting layouts show plain cards, as both copies did.
    private func handRow(highlighting: Bool) -> some View {
        let cards = game.myHandSorted
        return GeometryReader { geo in
            let cardW = GameCardSizing.cardWidth(available: geo.size.width, count: cards.count)
            let sp = cards.count > 1
                ? (geo.size.width - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                : 0
            HStack(spacing: sp) {
                ForEach(cards) { card in
                    if highlighting {
                        HandCardView(card: card, width: cardW,
                                     isTrump: isCardTrump(card), isCalled: isCardCalled(card))
                    } else {
                        HandCardView(card: card, width: cardW)
                    }
                }
            }
        }
        .frame(height: 106)
    }

    private func confirmButton(font: CGFloat, height: CGFloat) -> some View {
        Button {
            HapticManager.success()
            Task { await game.confirmCalling() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                Text("Confirm").fontWeight(.black)
            }
            .font(.system(size: font, weight: .heavy, design: .rounded))
            .foregroundStyle(game.callingValid ? Comic.black : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(ComicButtonStyle(
            bg: game.callingValid ? Comic.yellow : Comic.containerBG,
            fg: game.callingValid ? Comic.black : .secondary,
            borderColor: Comic.black
        ))
        .disabled(!game.callingValid)
    }

    private func callCardRow(label: String, rank: Binding<String>, suit: Binding<String>,
                             handIds: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Menu {
                    // Ranks whose combination with the current suit is already
                    // in the bidder's hand cannot be called.
                    ForEach(cardRanks.filter { !handIds.contains($0 + suit.wrappedValue) }, id: \.self) { r in
                        Button(r) { rank.wrappedValue = r }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rank.wrappedValue.isEmpty ? "Rank" : rank.wrappedValue)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.adaptivePrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.adaptiveDivider)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                let combined = rank.wrappedValue + suit.wrappedValue
                if !combined.isEmpty {
                    Text(combined)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(CardInk.onDark(suit: suit.wrappedValue).color)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.adaptiveDivider)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Suit row — full width so suits are never cropped.
            HStack(spacing: 8) {
                ForEach(cardSuits, id: \.self) { s in
                    let ink = CardInk.onDark(suit: s).color
                    let selected = suit.wrappedValue == s
                    let blocked = handIds.contains(rank.wrappedValue + s)
                    Button {
                        HapticManager.impact(.light)
                        suit.wrappedValue = s
                    } label: {
                        VStack(spacing: 3) {
                            Text(s)
                                .font(.system(size: 28))
                                .foregroundStyle(ink.opacity(blocked ? 0.25 : 1.0))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        // Owner's call (2026-09-19): the glyph fades and the
                        // plate lightens, rather than fading the whole control.
                        .background(blocked
                                    ? Color.adaptiveDivider.opacity(0.4)
                                    : (selected ? Color.adaptiveSubtle : Color.adaptiveDivider))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? ink.opacity(0.65) : Color.clear, lineWidth: 1.5)
                        }
                        .scaleEffect(selected ? 1.04 : 1.0)
                    }
                    .buttonStyle(BouncyButton())
                    .disabled(blocked)
                }
            }
        }
    }
}
