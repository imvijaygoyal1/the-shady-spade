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

    var body: some View {
        NavigationStack {
            List {
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
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
