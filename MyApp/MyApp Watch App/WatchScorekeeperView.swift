import SwiftUI

struct WatchScorekeeperView: View {
    @Bindable var viewModel: WatchScorekeeperViewModel
    @State private var showingRoundEntry = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.snapshot.statusMessage)
                            .font(.headline)
                        Text(viewModel.connectionStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(viewModel.syncStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.snapshot.isActive {
                    Section {
                        Button {
                            viewModel.resetDraft()
                            showingRoundEntry = true
                        } label: {
                            Label("Update Score", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Undo Last Round", role: .destructive) {
                            viewModel.undoLastRound()
                        }
                        .disabled(viewModel.snapshot.lastRoundSummary == nil)
                    }

                    Section("Round \(viewModel.snapshot.roundNumber)") {
                        ForEach(0..<viewModel.snapshot.playerNames.count, id: \.self) { index in
                            HStack {
                                Text(viewModel.snapshot.playerNames[index])
                                    .lineLimit(1)
                                Spacer()
                                Text("\(viewModel.snapshot.runningScores[safe: index] ?? 0)")
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }

                    if let lastRoundSummary = viewModel.snapshot.lastRoundSummary {
                        Section("Last Round") {
                            Text(lastRoundSummary)
                                .font(.caption)
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Open Real-Life Scorekeeper on the paired iPhone, enter the player names, then tap Start Scorecard.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Refresh from iPhone") {
                                viewModel.requestSnapshot()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scorekeeper")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.snapshot.isActive {
                        Button {
                            viewModel.resetDraft()
                            showingRoundEntry = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.requestSnapshot()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingRoundEntry) {
                WatchRoundEntryView(viewModel: viewModel) {
                    showingRoundEntry = false
                }
            }
            .onAppear {
                viewModel.requestSnapshot()
            }
        }
    }
}

private struct WatchRoundEntryView: View {
    @Bindable var viewModel: WatchScorekeeperViewModel
    let onDone: () -> Void
    @State private var calledCardSlot = 1
    @State private var showingCalledCardPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        calledCardButton("Called Card 1", slot: 1)
                        calledCardButton("Called Card 2", slot: 2)
                    }
                }

                Section("Players") {
                    Picker("Bidder", selection: $viewModel.draft.bidderIndex) {
                        ForEach(viewModel.eligibleBidderIndices, id: \.self) { index in
                            Text(viewModel.playerName(index)).tag(index)
                        }
                    }
                    Picker("Partner 1", selection: $viewModel.draft.partner1Index) {
                        ForEach(viewModel.eligiblePartner1Indices, id: \.self) { index in
                            Text(viewModel.playerName(index)).tag(index)
                        }
                    }
                    Picker("Partner 2", selection: $viewModel.draft.partner2Index) {
                        ForEach(viewModel.eligiblePartner2Indices, id: \.self) { index in
                            Text(viewModel.playerName(index)).tag(index)
                        }
                    }
                }

                Section("Bid") {
                    Stepper(value: $viewModel.draft.bidAmount, in: 130...240, step: 5) {
                        Text("\(viewModel.draft.bidAmount)")
                            .font(.headline.monospacedDigit())
                    }
                    Picker("Trump", selection: $viewModel.draft.trumpSuitRaw) {
                        ForEach(WatchScorekeeperViewModel.trumpSuits, id: \.raw) { suit in
                            Text(suit.name).tag(suit.raw)
                        }
                    }
                    Toggle("Bid Made", isOn: $viewModel.draft.bidMade)
                }

                Section {
                    Button("Confirm Round") {
                        viewModel.addRound()
                        onDone()
                    }
                    .disabled(viewModel.validationMessage != nil)

                    if let validationMessage = viewModel.validationMessage {
                        Text(validationMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Round")
            .sheet(isPresented: $showingCalledCardPicker) {
                WatchCalledCardSelectionSheet(
                    title: "Called Card \(calledCardSlot)",
                    selection: calledCardBinding(for: calledCardSlot),
                    cards: WatchScorekeeperViewModel.calledCards
                )
            }
        }
    }

    private func calledCardButton(_ title: String, slot: Int) -> some View {
        Button {
            calledCardSlot = slot
            showingCalledCardPicker = true
        } label: {
            VStack(spacing: 3) {
                Text(slot == 1 ? "Card 1" : "Card 2")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                WatchCalledCardBadge(cardID: slot == 1 ? viewModel.draft.calledCard1 : viewModel.draft.calledCard2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func calledCardBinding(for number: Int) -> Binding<String> {
        Binding(
            get: {
                number == 1 ? (viewModel.draft.calledCard1 ?? "") : (viewModel.draft.calledCard2 ?? "")
            },
            set: { value in
                if number == 1 { viewModel.draft.calledCard1 = value.isEmpty ? nil : value }
                else { viewModel.draft.calledCard2 = value.isEmpty ? nil : value }
            }
        )
    }
}

private struct WatchCalledCardSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selection: String
    let cards: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 7) {
                    Button("None") {
                        selection = ""
                        dismiss()
                    }
                    .font(.caption2.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)

                    ForEach(cards, id: \.self) { card in
                        Button {
                            selection = card
                            dismiss()
                        } label: {
                            WatchCalledCardBadge(cardID: card, isSelected: selection == card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WatchCalledCardBadge: View {
    let cardID: String?
    var isSelected = false

    private var suit: String? { cardID.map { String($0.suffix(1)) } }
    private var rank: String { cardID.map { String($0.dropLast()) } ?? "—" }
    private var color: Color {
        suit == "♥" || suit == "♦" ? .red : .primary
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(rank).font(.caption.bold())
            if let suit { Text(suit).font(.body.bold()) }
        }
        .foregroundStyle(suit == nil ? .secondary : color)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(.white, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? .yellow : color.opacity(0.35), lineWidth: isSelected ? 2 : 1))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
