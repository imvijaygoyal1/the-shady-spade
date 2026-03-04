import SwiftUI

// MARK: - Add Round View

struct AddRoundView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        dealerSection
                        bidderSection
                        bidSection
                        callCardsSection
                        partnersSection
                        pointsSection
                        submitButton
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Round \(vm.nextRoundNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Dealer

    private var dealerSection: some View {
        playerPickerSection(
            title: "🎴  Dealer",
            selectedIndex: $vm.dealerIndex
        )
    }

    // MARK: - Bidder

    private var bidderSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "🏆  Bidder")
            HStack(spacing: 0) {
                ForEach(0..<6) { idx in
                    let selected = vm.bidderIndex == idx
                    Button {
                        HapticManager.impact(.light)
                        vm.bidderIndex = idx
                        // Reset partners when bidder changes
                        if vm.partner1Index == idx { vm.partner1Index = nil }
                        if vm.partner2Index == idx { vm.partner2Index = nil }
                    } label: {
                        playerCell(idx: idx, selected: selected, color: .offenseBlue)
                    }
                    .buttonStyle(BouncyButton())
                    .accessibilityLabel(vm.playerNames[idx] + (selected ? ", selected" : ""))
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    // MARK: - Bid Amount + Trump Suit

    private var bidSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "🏷️  Bid & Trump")

            VStack(spacing: 16) {
                // Bid slider
                VStack(spacing: 8) {
                    HStack {
                        Text("Bid Amount").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(vm.bidAmount))")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(.offenseBlue)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: vm.bidAmount)
                    }
                    Slider(value: $vm.bidAmount, in: 130...250, step: 5)
                        .tint(.offenseBlue)
                    HStack {
                        Text("Min 130").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("Max 250").font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Trump suit
                HStack(spacing: 10) {
                    ForEach(TrumpSuit.allCases, id: \.rawValue) { suit in
                        let sel = vm.trumpSuit == suit
                        Button {
                            HapticManager.impact(.light)
                            vm.trumpSuit = suit
                        } label: {
                            VStack(spacing: 6) {
                                Text(suit.rawValue)
                                    .font(.system(size: 26))
                                    .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.35))
                                Text(suit.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(sel ? .white : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(sel ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(sel ? suit.displayColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
                                    }
                            }
                        }
                        .buttonStyle(BouncyButton())
                        .accessibilityLabel(suit.displayName + (sel ? ", selected" : ""))
                    }
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    // MARK: - Call Cards

    private var callCardsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "📣  Call Cards (Bidder calls 2 cards)")

            VStack(spacing: 14) {
                callCardRow(label: "Card 1",
                            rank: $vm.callCard1Rank,
                            suit: $vm.callCard1Suit)
                Divider().overlay(Color.white.opacity(0.08))
                callCardRow(label: "Card 2",
                            rank: $vm.callCard2Rank,
                            suit: $vm.callCard2Suit)

                if vm.callCard1 == vm.callCard2 && !vm.callCard1Rank.isEmpty {
                    Label("Cards must be different", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.defenseRose)
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    private func callCardRow(label: String, rank: Binding<String>, suit: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            // Rank picker
            Menu {
                ForEach(cardRanks, id: \.self) { r in
                    Button(r) { rank.wrappedValue = r }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(rank.wrappedValue.isEmpty ? "Rank" : rank.wrappedValue)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Suit buttons
            HStack(spacing: 8) {
                ForEach(cardSuits, id: \.self) { s in
                    let isRed = s == "♥" || s == "♦"
                    let selected = suit.wrappedValue == s
                    Button {
                        HapticManager.impact(.light)
                        suit.wrappedValue = s
                    } label: {
                        Text(s)
                            .font(.title3)
                            .foregroundStyle(isRed ? Color.defenseRose : Color.white)
                            .padding(8)
                            .background(selected ? Color.white.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected ? (isRed ? Color.defenseRose : Color.white).opacity(0.6) : Color.clear, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(BouncyButton())
                    .accessibilityLabel((s == "♠" ? "Spades" : s == "♥" ? "Hearts" : s == "♦" ? "Diamonds" : "Clubs") + (selected ? ", selected" : ""))
                }
            }

            Spacer()

            // Preview
            if !rank.wrappedValue.isEmpty && !suit.wrappedValue.isEmpty {
                Text(rank.wrappedValue + suit.wrappedValue)
                    .font(.headline.bold())
                    .foregroundStyle(["♥","♦"].contains(suit.wrappedValue) ? Color.defenseRose : .white)
            }
        }
    }

    // MARK: - Partners Reveal

    private var partnersSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "🤝  Reveal Partners (select 2)")

            let selected = [vm.partner1Index, vm.partner2Index].compactMap { $0 }

            VStack(spacing: 0) {
                ForEach(0..<6) { idx in
                    if idx != vm.bidderIndex {
                        Button {
                            HapticManager.impact(.light)
                            vm.togglePartner(idx)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(vm.isPartner(idx) ? Color.offenseBlue.opacity(0.2) : Color.white.opacity(0.06))
                                        .frame(width: 36, height: 36)
                                    Text(String(vm.playerNames[idx].prefix(1)).uppercased())
                                        .font(.subheadline.bold())
                                        .foregroundStyle(vm.isPartner(idx) ? .offenseBlue : .white)
                                }
                                Text(vm.playerNames[idx])
                                    .foregroundStyle(.white)
                                Spacer()
                                if vm.isPartner(idx) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.offenseBlue)
                                        .font(.title3)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(BouncyButton())
                        .accessibilityLabel(vm.playerNames[idx] + (vm.isPartner(idx) ? ", selected as partner" : ""))
                        .accessibilityHint("Toggle as partner")

                        if idx < 5 { Divider().overlay(Color.white.opacity(0.07)) }
                    }
                }
            }
            .glassmorphic(cornerRadius: 18)

            if selected.count == 2 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.offenseBlue)
                    Text("Partners: \(vm.playerNames[selected[0]]) & \(vm.playerNames[selected[1]])")
                        .font(.caption)
                        .foregroundStyle(.offenseBlue)
                }
            } else {
                Text("Select exactly 2 partners")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Points

    private var pointsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "📊  Points Caught")

            HStack(spacing: 12) {
                pointCounter(label: "Bidding Team", points: vm.offensePoints, color: .offenseBlue, isOffense: true)
                pointCounter(label: "Defense", points: vm.defensePoints, color: .defenseRose, isOffense: false)
            }

            let total = vm.totalPointsEntered
            HStack(spacing: 6) {
                Image(systemName: total > 250 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text("Total: \(total) / 250")
                    .font(.caption)
            }
            .foregroundStyle(total > 250 ? Color.defenseRose : Color.offenseBlue)
            .animation(.easeInOut, value: total)
        }
    }

    private func pointCounter(label: String, points: Int, color: Color, isOffense: Bool) -> some View {
        VStack(spacing: 10) {
            Text(label).font(.headline).foregroundStyle(color)
            Text("\(points)")
                .font(.system(size: 50, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: points)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    pointBtn("+10", color: color, isOffense: isOffense, delta:  10)
                    pointBtn("+5",  color: color, isOffense: isOffense, delta:   5)
                }
                HStack(spacing: 6) {
                    pointBtn("−5",  color: color, isOffense: isOffense, delta:  -5)
                    pointBtn("−10", color: color, isOffense: isOffense, delta: -10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassmorphic(cornerRadius: 18)
    }

    private func pointBtn(_ label: String, color: Color, isOffense: Bool, delta: Int) -> some View {
        Button { vm.adjustPoints(offense: isOffense, delta: delta) } label: {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(BouncyButton())
        .accessibilityLabel("\(delta > 0 ? "Add" : "Subtract") \(abs(delta)) \(isOffense ? "offense" : "defense") points")
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button { Task { vm.addRound() } } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                Text("Record Round").fontWeight(.bold)
            }
            .font(.title3)
            .foregroundStyle(vm.isFormValid ? Color.black : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(vm.isFormValid
                          ? AnyShapeStyle(LinearGradient(
                                colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                                startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.white.opacity(0.09)))
            }
        }
        .disabled(!vm.isFormValid)
        .buttonStyle(BouncyButton())
        .padding(.top, 4)
        .accessibilityLabel("Record round")
        .accessibilityHint(vm.isFormValid ? "" : "Complete all required fields first")
    }

    // MARK: - Reusable player cell

    private func playerPickerSection(title: String, selectedIndex: Binding<Int>) -> some View {
        VStack(spacing: 12) {
            SectionHeader(title: title)
            HStack(spacing: 0) {
                ForEach(0..<6) { idx in
                    let selected = selectedIndex.wrappedValue == idx
                    Button {
                        HapticManager.impact(.light)
                        selectedIndex.wrappedValue = idx
                    } label: {
                        playerCell(idx: idx, selected: selected, color: .masterGold)
                    }
                    .buttonStyle(BouncyButton())
                    .accessibilityLabel(vm.playerNames[idx] + (selected ? ", selected" : ""))
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    private func playerCell(idx: Int, selected: Bool, color: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(selected
                          ? AnyShapeStyle(color)
                          : AnyShapeStyle(Color.white.opacity(0.09)))
                    .frame(width: 44, height: 44)
                Text(String(vm.playerNames[idx].prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(selected ? Color.black : Color.white)
            }
            Text(String(vm.playerNames[idx].prefix(4)))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(selected ? color : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
