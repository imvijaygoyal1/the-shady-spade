import SwiftUI
import SwiftData

struct ModeSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = GameViewModel()
    @State private var showingSolo = false
    @State private var showingOnline = false
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingNamePrompt = false
    @State private var pendingName = ""
    @State private var pendingAvatar = "🦁"
    @State private var nameConfirmed = false
    @State private var isOnlineNamePrompt = false
    @State private var showingCustomSetup = false
    @AppStorage("soloPlayerName") private var soloPlayerName = ""
    @AppStorage("soloPlayerAvatar") private var soloPlayerAvatar = "🦁"

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            // Top bar — history (left) + settings (right)
            VStack {
                HStack {
                    Button {
                        HapticManager.impact(.light)
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.adaptiveSecondary)
                            .frame(width: 40, height: 40)
                            .background(Color.adaptiveSubtle)
                            .clipShape(Circle())
                    }
                    .padding(.top, 56)
                    .padding(.leading, 20)

                    Spacer()

                    Button {
                        HapticManager.impact(.light)
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.adaptiveSecondary)
                            .frame(width: 40, height: 40)
                            .background(Color.adaptiveSubtle)
                            .clipShape(Circle())
                    }
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.masterGold)
                    Text("The Shady Spade")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.adaptivePrimary)
                    Text("Choose a game mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 52)

                VStack(spacing: 16) {
                    ModeCard(
                        icon: "person.fill.badge.plus",
                        title: "Play Solo",
                        subtitle: "Face 5 AI opponents in a fully simulated game",
                        color: .masterGold
                    ) {
                        HapticManager.impact(.medium)
                        isOnlineNamePrompt = false
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        showingNamePrompt = true
                    }

                    ModeCard(
                        icon: "person.wave.2.fill",
                        title: "Play Online",
                        subtitle: "6 real players over Wi-Fi or internet",
                        color: .teal
                    ) {
                        HapticManager.impact(.medium)
                        isOnlineNamePrompt = true
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        showingNamePrompt = true
                    }

                    ModeCard(
                        icon: "person.3.fill",
                        title: "Custom Game",
                        subtitle: "2–5 humans online + AI fills empty seats",
                        color: Color(red: 0.55, green: 0.35, blue: 0.85)
                    ) {
                        HapticManager.impact(.medium)
                        showingCustomSetup = true
                    }
                }
                .adaptiveContentFrame()
                .padding(.horizontal, 20)

                Spacer()

                Text("© 2026 Vijay Goyal. All rights reserved.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.bottom, 20)
            }
        }
        .onAppear { vm.setup(with: modelContext) }
        .sheet(isPresented: $showingNamePrompt, onDismiss: {
            if nameConfirmed {
                nameConfirmed = false
                if isOnlineNamePrompt { isOnlineNamePrompt = false; showingOnline = true }
                else { showingSolo = true }
            } else {
                isOnlineNamePrompt = false
            }
        }) {
            NamePromptSheet(
                pendingName: $pendingName,
                pendingAvatar: $pendingAvatar,
                mode: isOnlineNamePrompt ? "Online Game" : "Solo Game"
            ) {
                let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
                soloPlayerName = trimmed.isEmpty ? "Player" : trimmed
                soloPlayerAvatar = pendingAvatar
                nameConfirmed = true
                showingNamePrompt = false
            }
        }
        .fullScreenCover(isPresented: $showingSolo) {
            ComputerGameView(
                vm: vm,
                humanName: soloPlayerName.isEmpty ? "Player" : soloPlayerName,
                humanAvatar: soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
            )
        }
        .fullScreenCover(isPresented: $showingOnline) {
            OnlineEntryView(
                vm: vm,
                playerName: soloPlayerName.isEmpty ? "Player" : soloPlayerName,
                playerAvatar: soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
            )
        }
        .sheet(isPresented: $showingHistory) {
            GameHistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingCustomSetup) {
            CustomGameSetupView(vm: vm)
        }
    }
}

// MARK: - Online Entry

private struct OnlineEntryView: View {
    @Bindable var vm: GameViewModel
    let playerName: String
    let playerAvatar: String
    @State private var onlineGame: OnlineGameViewModel? = nil

    var body: some View {
        if let game = onlineGame {
            OnlineGameView(game: game)
        } else {
            OnlineSessionView(
                vm: vm,
                playerName: playerName,
                playerAvatar: playerAvatar,
                onGameReady: { myIndex, isHostVal, code, names in
                    onlineGame = OnlineGameViewModel(
                        myPlayerIndex: myIndex,
                        isHost: isHostVal,
                        sessionCode: code,
                        playerNames: names,
                        dealerIndex: 0,
                        roundNumber: 1
                    )
                }
            )
        }
    }
}

private struct NamePromptSheet: View {
    @Binding var pendingName: String
    @Binding var pendingAvatar: String
    var mode: String = "Solo Game"
    let onStart: () -> Void

    private let avatarOptions = [
        "🦁", "🐯", "🦊", "🐺", "🦅", "🐻", "🦈", "🐉",
        "🧙", "🥷", "🤴", "👸", "🦸", "🎩"
    ]
    private var trimmed: String { pendingName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Large avatar preview with gold edit badge
                    ZStack {
                        Circle()
                            .fill(Color.masterGold.opacity(0.12))
                            .frame(width: 104, height: 104)
                            .overlay(
                                Circle()
                                    .stroke(Color.masterGold.opacity(0.35), lineWidth: 2)
                            )
                            .shadow(color: Color.masterGold.opacity(0.25), radius: 14)
                        Text(pendingAvatar)
                            .font(.system(size: 58))
                            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: pendingAvatar)
                    }
                    .padding(.top, 28)

                    // Title & subtitle
                    VStack(spacing: 6) {
                        Text(mode)
                            .font(.title2.bold())
                            .foregroundStyle(.adaptivePrimary)
                        Text("Pick a name for your avatar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Avatar Name")
                            .font(.caption.bold())
                            .foregroundStyle(.masterGold)
                            .padding(.leading, 4)
                        TextField("Enter avatar name...", text: $pendingName)
                            .textFieldStyle(.plain)
                            .font(.title3.bold())
                            .foregroundStyle(.adaptivePrimary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                            .background(Color.adaptiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .submitLabel(.go)
                            .onSubmit(onStart)
                    }
                    .padding(.horizontal, 28)

                    // Avatar picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose Your Avatar")
                            .font(.caption.bold())
                            .foregroundStyle(.masterGold)
                            .padding(.leading, 28)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(avatarOptions, id: \.self) { emoji in
                                    let isSelected = pendingAvatar == emoji
                                    Button {
                                        HapticManager.impact(.light)
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                            pendingAvatar = emoji
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(isSelected
                                                      ? Color.masterGold.opacity(0.18)
                                                      : Color.adaptiveSubtle)
                                                .frame(width: 64, height: 64)
                                                .overlay(
                                                    Circle()
                                                        .stroke(
                                                            isSelected ? Color.masterGold : Color.adaptiveDivider,
                                                            lineWidth: isSelected ? 2.5 : 1
                                                        )
                                                )
                                                .shadow(
                                                    color: isSelected ? Color.masterGold.opacity(0.45) : .clear,
                                                    radius: 10
                                                )
                                            Text(emoji)
                                                .font(.system(size: 34))
                                        }
                                    }
                                    .buttonStyle(BouncyButton())
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 6)
                        }
                    }

                    // Start Game button
                    Button(action: onStart) {
                        Text("Start Game")
                            .font(.headline.bold())
                            .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                trimmed.isEmpty
                                    ? AnyShapeStyle(Color.adaptiveDivider)
                                    : AnyShapeStyle(Color.masterGold)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())
                    .disabled(trimmed.isEmpty)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.darkBG)
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.adaptivePrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(color.opacity(0.6))
            }
            .padding(20)
            .glassmorphic(cornerRadius: 20)
        }
        .buttonStyle(BouncyButton())
    }
}

// MARK: - Custom Game Setup (Firestore multi-device with AI auto-play)

private struct CustomGameSetupView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var humanCount = 2
    @State private var playerName = ""
    @State private var playerAvatar = "🦁"
    @State private var playerUID = UUID().uuidString
    @State private var sessionVM = OnlineSessionViewModel()
    @State private var showingLobby = false
    @State private var isCreating = false

    private static let seatsByCount: [[Int]] = [
        [0], [0, 3], [0, 2, 4], [0, 1, 3, 4], [0, 1, 2, 3, 4]
    ]
    private var humanSeats: [Int] { Self.seatsByCount[humanCount - 1] }
    private var aiSeats: [Int] { (0..<6).filter { !humanSeats.contains($0) } }

    private let avatarOptions = [
        "🦁", "🐯", "🦊", "🐺", "🦅", "🐻", "🦈", "🐉", "🧙", "🥷", "🤴", "👸", "🦸", "🎩"
    ]
    private var trimmed: String { playerName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        humanCountSection
                        hostIdentitySection
                        startButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Custom Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fullScreenCover(isPresented: $showingLobby) {
            CustomOnlineEntryView(
                vm: vm,
                playerName: trimmed.isEmpty ? "Player" : trimmed,
                playerAvatar: playerAvatar,
                playerUID: playerUID,
                sessionVM: sessionVM
            )
        }
    }

    private var humanCountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Number of Human Players")
                .font(.headline)
                .foregroundStyle(.masterGold)
            Text("Remaining seats are filled by AI opponents")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(2...5, id: \.self) { n in
                    Button {
                        HapticManager.impact(.light)
                        humanCount = n
                    } label: {
                        Text("\(n)")
                            .font(.title3.bold())
                            .foregroundStyle(humanCount == n ? .black : .adaptivePrimary)
                            .frame(width: 48, height: 48)
                            .background(humanCount == n ? Color.masterGold : Color.adaptiveSubtle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(BouncyButton())
                }
                Spacer()
            }
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private var hostIdentitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Name & Avatar")
                .font(.headline)
                .foregroundStyle(.masterGold)

            TextField("Enter your name...", text: $playerName)
                .textFieldStyle(.plain)
                .font(.title3.bold())
                .foregroundStyle(.adaptivePrimary)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.adaptiveSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(avatarOptions, id: \.self) { emoji in
                        let isSelected = playerAvatar == emoji
                        Button {
                            HapticManager.impact(.light)
                            playerAvatar = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 48, height: 48)
                                .background(isSelected ? Color.masterGold.opacity(0.2) : Color.adaptiveSubtle)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(isSelected ? Color.masterGold : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(BouncyButton())
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private var startButton: some View {
        Button {
            guard !isCreating && !trimmed.isEmpty else { return }
            HapticManager.impact(.medium)
            isCreating = true
            createAndShowLobby()
        } label: {
            HStack(spacing: 10) {
                if isCreating {
                    ProgressView().tint(.black).scaleEffect(0.85)
                }
                Text(isCreating ? "Creating…" : "Create Lobby")
                    .font(.title3.bold())
                    .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(trimmed.isEmpty ? Color.masterGold.opacity(0.35) : Color.masterGold)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(BouncyButton())
        .disabled(trimmed.isEmpty || isCreating)
    }

    /// Instantly shows lobby (synchronous local prep) then writes to Firebase in background.
    private func createAndShowLobby() {
        playerUID = UUID().uuidString
        sessionVM = OnlineSessionViewModel()
        // 1. Prepare local state synchronously — lobby can show immediately
        sessionVM.prepareLocalSession(
            uid: playerUID,
            name: trimmed.isEmpty ? "Player" : trimmed,
            avatar: playerAvatar,
            aiSeats: aiSeats,
            sessionType: "custom"
        )
        // 2. Show lobby right away (session code is already set)
        showingLobby = true
        isCreating = false
        // 3. Write to Firebase in background
        Task { await sessionVM.writeSessionToFirebase() }
    }
}

// MARK: - Custom Online Entry (host-driven Firestore game with AI seats)

private struct CustomOnlineEntryView: View {
    @Bindable var vm: GameViewModel
    let playerName: String
    let playerAvatar: String
    let playerUID: String
    var sessionVM: OnlineSessionViewModel
    @State private var onlineGame: OnlineGameViewModel? = nil

    var body: some View {
        if let game = onlineGame {
            OnlineGameView(game: game)
        } else {
            OnlineSessionView(
                vm: vm,
                playerName: playerName,
                playerAvatar: playerAvatar,
                prebuiltSessionVM: sessionVM,
                prebuiltPlayerUID: playerUID,
                onGameReady: { myIndex, isHostVal, code, names in
                    onlineGame = OnlineGameViewModel(
                        myPlayerIndex: myIndex,
                        isHost: isHostVal,
                        sessionCode: code,
                        playerNames: names,
                        dealerIndex: 0,
                        roundNumber: 1,
                        aiSeats: sessionVM.aiSeats
                    )
                }
            )
        }
    }
}
