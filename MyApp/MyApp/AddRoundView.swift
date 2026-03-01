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
                        trumpSuitSection
                        biddingSection
                        pointsSection
                        shadySpadeSection
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
        VStack(spacing: 12) {
            SectionHeader(title: "🎴  Select Dealer")

            HStack(spacing: 0) {
                ForEach(0..<6) { idx in
                    let player  = Player(index: idx)
                    let selected = vm.dealerIndex == idx

                    Button {
                        HapticManager.impact(.light)
                        vm.dealerIndex = idx
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                // Solid team color — ensures black text always meets 4.5:1+ on both teams
                                Circle()
                                    .fill(selected
                                          ? AnyShapeStyle(player.team.color)
                                          : AnyShapeStyle(Color.white.opacity(0.09)))
                                    .frame(width: 46, height: 46)
                                    .neonGlow(color: selected ? player.team.color : .clear, intensity: 0.7)

                                Text(player.initial)
                                    .font(.caption.bold())
                                    .foregroundStyle(selected ? Color.black : Color.white)
                            }

                            Text(player.team.shortName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(player.team.color)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BouncyButton())
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    // MARK: - Trump Suit

    private var trumpSuitSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "🂡  Trump Suit")

            HStack(spacing: 10) {
                ForEach(TrumpSuit.allCases, id: \.rawValue) { suit in
                    let selected = vm.trumpSuit == suit

                    Button {
                        HapticManager.impact(.light)
                        vm.trumpSuit = suit
                    } label: {
                        VStack(spacing: 6) {
                            Text(suit.rawValue)
                                .font(.system(size: 28))
                                .foregroundStyle(selected ? suit.displayColor : suit.displayColor.opacity(0.35))
                            Text(suit.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(selected ? .white : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(selected ? suit.displayColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
                                }
                        }
                        .neonGlow(color: selected ? suit.displayColor : .clear, intensity: 0.35)
                    }
                    .buttonStyle(BouncyButton())
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    // MARK: - Bidding

    private var biddingSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "🏷️  Bidding Team & Amount")

            VStack(spacing: 16) {
                // Team toggle
                HStack(spacing: 4) {
                    ForEach(Team.allCases, id: \.rawValue) { team in
                        let selected = vm.biddingTeam == team
                        Button {
                            HapticManager.impact(.light)
                            vm.biddingTeam = team
                        } label: {
                            Text(team.displayName)
                                .font(.subheadline.bold())
                                // Selected: black on solid team color (6.5:1 A, 9.4:1 B) ✓
                                // Unselected: full-opacity team color on darkBG (5.9:1 A, 8.4:1 B) ✓
                                .foregroundStyle(selected ? Color.black : team.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(team.color)
                                            .neonGlow(color: team.color, intensity: 0.5)
                                    }
                                }
                        }
                        .buttonStyle(BouncyButton())
                    }
                }
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }

                // Bid slider
                VStack(spacing: 8) {
                    HStack {
                        Text("Bid Amount")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(vm.bidAmount))")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(vm.biddingTeam.color)
                            .neonGlow(color: vm.biddingTeam.color, intensity: 0.5)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: vm.bidAmount)
                    }

                    Slider(value: $vm.bidAmount, in: 130...250, step: 5)
                        .tint(vm.biddingTeam.color)

                    HStack {
                        Text("Min 130").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("Max 250").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    // MARK: - Points

    private var pointsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "📊  Points Caught")

            HStack(spacing: 12) {
                teamPointCounter(team: .a)
                teamPointCounter(team: .b)
            }

            // Running total indicator
            let total = vm.totalPointsEntered
            HStack(spacing: 6) {
                Image(systemName: total > 250 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text("Total entered: \(total) / 250")
                    .font(.caption)
            }
            .foregroundStyle(total > 250 ? Color.red : Color.green.opacity(0.85))
            .padding(.horizontal, 2)
            .animation(.easeInOut, value: total)
        }
    }

    @ViewBuilder
    private func teamPointCounter(team: Team) -> some View {
        let points = team == .a ? vm.teamAPoints : vm.teamBPoints

        VStack(spacing: 10) {
            Text(team.displayName)
                .font(.headline)
                .foregroundStyle(team.color)

            Text("\(points)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: points)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    pointBtn("+10", team: team, delta:  10)
                    pointBtn("+5",  team: team, delta:   5)
                }
                HStack(spacing: 6) {
                    pointBtn("−5",  team: team, delta:  -5)
                    pointBtn("−10", team: team, delta: -10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassmorphic(cornerRadius: 18)
    }

    private func pointBtn(_ label: String, team: Team, delta: Int) -> some View {
        Button { vm.adjustPoints(team: team, delta: delta) } label: {
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(team.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(team.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(team.color.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(BouncyButton())
    }

    // MARK: - Shady Spade

    private var shadySpadeSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "♠  The Shady Spade  ·  30 pts")

            VStack(spacing: 14) {
                Text("3♠")
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(.shadyGold)
                    .neonGlow(color: .shadyGold)

                HStack(spacing: 10) {
                    shadyOption(label: "None", isSelected: vm.shadySpadeTeam == nil, team: nil) {
                        vm.shadySpadeTeam = nil
                    }
                    ForEach(Team.allCases, id: \.rawValue) { team in
                        shadyOption(label: team.displayName, isSelected: vm.shadySpadeTeam == team, team: team) {
                            vm.shadySpadeTeam = team
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .glassmorphic(cornerRadius: 18)
        }
    }

    private func shadyOption(
        label: String,
        isSelected: Bool,
        team: Team?,
        action: @escaping () -> Void
    ) -> some View {
        let accentColor: Color = team?.color ?? .shadyGold

        return Button {
            HapticManager.impact(.medium)
            action()
        } label: {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? Color.black : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? accentColor : Color.white.opacity(0.08))
                )
                .neonGlow(color: isSelected ? accentColor : .clear, intensity: 0.6)
        }
        .buttonStyle(BouncyButton())
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button { vm.addRound() } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                Text("Record Round")
                    .fontWeight(.bold)
            }
            .font(.title3)
            .foregroundStyle(vm.isFormValid ? Color.black : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(vm.isFormValid
                          ? AnyShapeStyle(LinearGradient(
                                colors: [.shadyGold, Color(red: 1, green: 0.65, blue: 0)],
                                startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.white.opacity(0.09)))
            }
            .neonGlow(color: .shadyGold, intensity: vm.isFormValid ? 0.9 : 0)
        }
        .disabled(!vm.isFormValid)
        .buttonStyle(BouncyButton())
        .padding(.top, 4)
    }
}
