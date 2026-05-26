import SwiftUI
import SwiftData

private struct NamePromptRequest: Identifiable {
    let id = UUID()
    let mode: String
    let isOnline: Bool
}

struct ModeSelectionView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = GameViewModel()
    @State private var showingSolo = false
    @State private var showingOnline = false
    @State private var showingBluetooth = false
    @State private var showingJoinGame = false
    @State private var showingSettings = false
    @State private var showingLeaderboard = false
    @State private var showingPlayerCount = false
    @State private var selectedPlayerCount = 1
    @State private var namePromptRequest: NamePromptRequest? = nil
    @State private var pendingName = ""
    @State private var pendingAvatar = "🦁"
    @State private var nameConfirmed = false
    @State private var confirmedIsNewGame = false
    @State private var playerCountConfirmed = false
    @State private var confirmedIsBluetooth = false
    @State private var confirmedIsJoin = false
    @AppStorage("soloPlayerName") private var soloPlayerName = ""
    @AppStorage("soloPlayerAvatar") private var soloPlayerAvatar = "🦁"
    @State private var deepLink = DeepLinkManager.shared

    private var portraitBody: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            // Top bar — history (left) + settings (right)
            VStack {
                HStack {
                    Button {
                        HapticManager.impact(.light)
                        showingLeaderboard = true
                    } label: {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.masterGold)
                            .frame(width: 40, height: 40)
                            .background(Comic.black)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(
                                Comic.yellow, lineWidth: 2))
                    }
                    .padding(.leading, 20)

                    Spacer()

                    Button {
                        HapticManager.impact(.light)
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.white)
                            .frame(width: 40, height: 40)
                            .background(Comic.black)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Comic.black, lineWidth: 2))
                    }
                    .padding(.trailing, 20)
                }
                .padding(.top, 56)
                Spacer()
            }

            GeometryReader { geo in
                // PORTRAIT — original layout, untouched
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 14) {
                        Image(systemName: "suit.spade.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(Comic.yellow)
                            .shadow(color: Comic.black, radius: 0, x: 3, y: 3)
                        Text("The Shady Spade")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(Comic.textPrimary)
                            .shadow(color: Comic.black.opacity(0.18), radius: 0, x: 2, y: 2)
                        Text("Choose a game mode")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                    }
                    .padding(.bottom, 52)

                    VStack(spacing: 16) {
                        ModeCard(
                            icon: "play.circle.fill",
                            title: "New Game",
                            subtitle: "Play alone or invite friends — AI fills empty seats",
                            color: Comic.yellow,
                            iconBG: Comic.yellow
                        ) {
                            HapticManager.impact(.medium)
                            selectedPlayerCount = 1
                            pendingName = soloPlayerName
                            pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                            namePromptRequest = NamePromptRequest(mode: "New Game", isOnline: false)
                        }

                        ModeCard(
                            icon: "dot.radiowaves.left.and.right",
                            title: "Local / Bluetooth",
                            subtitle: "Play nearby — no internet needed",
                            color: Comic.red,
                            iconBG: Comic.red
                        ) {
                            HapticManager.impact(.medium)
                            pendingName = soloPlayerName
                            pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                            namePromptRequest = NamePromptRequest(mode: "Local / Bluetooth", isOnline: false)
                        }

                        ModeCard(
                            icon: "arrow.right.circle.fill",
                            title: "Join a Game",
                            subtitle: "Have a room code? Jump straight in",
                            color: Color(red: 0.09, green: 0.63, blue: 0.45),
                            iconBG: Color(red: 0.09, green: 0.63, blue: 0.45)
                        ) {
                            HapticManager.impact(.medium)
                            pendingName = soloPlayerName
                            pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                            namePromptRequest = NamePromptRequest(mode: "Join a Game", isOnline: false)
                        }
                    }
                    .adaptiveContentFrame()
                    .padding(.horizontal, 20)

                    Spacer()

                    Text("© 2026 Vijay Goyal. All rights reserved.")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.bottom, 20)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    var body: some View {
        AdaptiveLayout(
            portrait: {
                portraitBody
            },
            landscapeLeft: {
                BrandingPanel(
                    subtitle: "Choose a game mode",
                    showButtons: true,
                    onTrophy: {
                        HapticManager.impact(.light)
                        showingLeaderboard = true
                    },
                    onSettings: {
                        HapticManager.impact(.light)
                        showingSettings = true
                    }
                )
            },
            landscapeRight: {
                VStack(spacing: 10) {
                    ModeCard(
                        icon: "play.circle.fill",
                        title: "New Game",
                        subtitle: "Play alone or invite friends — AI fills empty seats",
                        color: Comic.yellow,
                        iconBG: Comic.yellow
                    ) {
                        HapticManager.impact(.medium)
                        selectedPlayerCount = 1
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        namePromptRequest = NamePromptRequest(mode: "New Game", isOnline: false)
                    }

                    ModeCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Local / Bluetooth",
                        subtitle: "Play nearby — no internet needed",
                        color: Comic.red,
                        iconBG: Comic.red
                    ) {
                        HapticManager.impact(.medium)
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        namePromptRequest = NamePromptRequest(mode: "Local / Bluetooth", isOnline: false)
                    }

                    ModeCard(
                        icon: "arrow.right.circle.fill",
                        title: "Join a Game",
                        subtitle: "Have a room code? Jump straight in",
                        color: Color(red: 0.09, green: 0.63, blue: 0.45),
                        iconBG: Color(red: 0.09, green: 0.63, blue: 0.45)
                    ) {
                        HapticManager.impact(.medium)
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        namePromptRequest = NamePromptRequest(mode: "Join a Game", isOnline: false)
                    }
                }
                .padding(12)
            }
        )
        .onAppear { vm.setup(with: modelContext) }
        .sheet(item: $namePromptRequest, onDismiss: {
            if nameConfirmed {
                nameConfirmed = false
                if confirmedIsJoin { showingJoinGame = true }
                else if confirmedIsNewGame { showingPlayerCount = true }
                else if confirmedIsBluetooth { showingBluetooth = true }
                else { showingSolo = true }
            }
        }) { request in
            NamePromptSheet(
                pendingName: $pendingName,
                pendingAvatar: $pendingAvatar,
                mode: request.mode
            ) {
                let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
                soloPlayerName = trimmed.isEmpty ? "Player" : trimmed
                soloPlayerAvatar = pendingAvatar
                confirmedIsJoin = request.mode == "Join a Game"
                confirmedIsNewGame = request.mode == "New Game"
                confirmedIsBluetooth = request.mode == "Local / Bluetooth"
                nameConfirmed = true
                namePromptRequest = nil
            }
        }
        .sheet(isPresented: $showingPlayerCount, onDismiss: {
            if playerCountConfirmed {
                playerCountConfirmed = false
                if selectedPlayerCount == 1 {
                    showingSolo = true
                } else {
                    showingOnline = true
                }
            }
        }) {
            PlayerCountSheet(selectedCount: $selectedPlayerCount) {
                playerCountConfirmed = true
                showingPlayerCount = false
            }
        }
        .fullScreenCover(isPresented: $showingSolo) {
            ComputerGameView(
                vm: vm,
                humanName: soloPlayerName.isEmpty ? "Player" : soloPlayerName,
                humanAvatar: soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
            )
            .environmentObject(themeManager)
        }
        .fullScreenCover(isPresented: $showingOnline) {
            OnlineEntryView(
                vm: vm,
                playerName: soloPlayerName.isEmpty ? "Player" : soloPlayerName,
                playerAvatar: soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
            )
            .environmentObject(themeManager)
        }
        .fullScreenCover(isPresented: $showingJoinGame) {
            OnlineEntryView(
                vm: vm,
                playerName: soloPlayerName.isEmpty ? "Player" : soloPlayerName,
                playerAvatar: soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar,
                autoShowJoin: true
            )
            .environmentObject(themeManager)
        }
        .fullScreenCover(isPresented: $showingBluetooth) {
            BTEntryView(
                playerName: soloPlayerName.isEmpty ? "Player" : soloPlayerName,
                playerAvatar: soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
            )
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showingLeaderboard) {
            LeaderboardView()
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(themeManager)
        }
        .onChange(of: deepLink.pendingJoinCode) { _, code in
            guard code != nil else { return }
            // Auto-navigate to the join screen when a deep link arrives
            showingJoinGame = true
        }
    }
}

// MARK: - Bluetooth Entry

private struct BTEntryView: View {
    let playerName: String
    let playerAvatar: String
    @State private var btGame: BluetoothGameViewModel? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let game = btGame {
            BluetoothGameView(game: game)
        } else {
            BluetoothSessionView(
                playerName: playerName,
                playerAvatar: playerAvatar,
                onGameReady: { vm in
                    btGame = vm
                    TVDisplayManager.shared.activeGame = vm
                }
            )
            .onDisappear {
                TVDisplayManager.shared.activeGame = nil
            }
        }
    }
}

// MARK: - Online Entry

private struct OnlineEntryView: View {
    @Bindable var vm: GameViewModel
    let playerName: String
    let playerAvatar: String
    var autoShowJoin: Bool = false
    @State private var onlineGame: OnlineGameViewModel? = nil

    var body: some View {
        if let game = onlineGame {
            OnlineGameView(game: game)
        } else {
            OnlineSessionView(
                vm: vm,
                playerName: playerName,
                playerAvatar: playerAvatar,
                autoShowJoin: autoShowJoin,
                onGameReady: { myIndex, isHostVal, code, names, avatars, aiSeats in
                    onlineGame = OnlineGameViewModel(
                        myPlayerIndex: myIndex,
                        isHost: isHostVal,
                        sessionCode: code,
                        playerNames: names,
                        playerAvatars: avatars,
                        dealerIndex: 0,
                        roundNumber: 1,
                        aiSeats: aiSeats
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

    private let avatarOptions = Comic.comicCharacters.map { $0.emoji }
    private var trimmed: String { pendingName.trimmingCharacters(in: .whitespaces) }
    private var isProfane: Bool { ProfanityFilter.isProfane(trimmed) }
    private var canStart: Bool { !trimmed.isEmpty && !isProfane }

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Large avatar preview card
                    AvatarPickerCard(
                        emoji: pendingAvatar,
                        name: Comic.characterName(for: pendingAvatar),
                        isSelected: true,
                        width: 100,
                        height: 132
                    )
                    .padding(.top, 28)
                    .animation(.spring(response: 0.3,
                        dampingFraction: 0.65), value: pendingAvatar)

                    // Title & subtitle
                    VStack(spacing: 6) {
                        Text(mode)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.adaptivePrimary)
                        Text("Pick a name for your avatar")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Avatar Name")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                            .padding(.leading, 4)
                        TextField("Enter avatar name...", text: $pendingName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(isProfane ? Color.defenseRose : Comic.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 14)
                            .comicContainer(cornerRadius: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isProfane ? Color.defenseRose : Color.clear,
                                                  lineWidth: 1.5)
                            )
                            .submitLabel(.go)
                            .onSubmit { if canStart { onStart() } }
                        if isProfane {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                Text("Inappropriate name — please choose another")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color.defenseRose)
                            .padding(.leading, 4)
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: isProfane)
                    .padding(.horizontal, 28)

                    // Avatar picker — rectangular cards
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose Your Avatar")
                            .font(.system(size: 13, weight: .heavy,
                                design: .rounded))
                            .foregroundStyle(.masterGold)
                            .padding(.leading, 28)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(avatarOptions, id: \.self) { emoji in
                                    let isSelected = pendingAvatar == emoji
                                    Button {
                                        HapticManager.impact(.light)
                                        withAnimation(.spring(response: 0.25,
                                            dampingFraction: 0.6)) {
                                            pendingAvatar = emoji
                                        }
                                    } label: {
                                        AvatarPickerCard(
                                            emoji: emoji,
                                            name: Comic.characterName(
                                                for: emoji),
                                            isSelected: isSelected,
                                            width: 62,
                                            height: 84
                                        )
                                    }
                                    .buttonStyle(BouncyButton())
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                        }
                    }

                    // Start Game button
                    Button(action: onStart) {
                        Text("Start Game")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(canStart ? Comic.black : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(ComicButtonStyle(
                        bg: canStart ? Comic.yellow : Comic.containerBG,
                        fg: canStart ? Comic.black : .secondary,
                        borderColor: Comic.black
                    ))
                    .disabled(!canStart)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Comic.bg)
    }
}

private struct PlayerCountSheet: View {
    @Binding var selectedCount: Int
    let onConfirm: () -> Void

    private var description: String {
        switch selectedCount {
        case 1: return "Just you vs 5 AI opponents.\nStarts instantly — no internet needed."
        case 6: return "Full table — 6 humans, no AI.\nAn online room will be created."
        default:
            let others = selectedCount - 1
            let ai = 6 - selectedCount
            return "You + \(others) friend\(others > 1 ? "s" : ""). AI fills \(ai) seat\(ai > 1 ? "s" : "").\nAn online room will be created."
        }
    }

    private var buttonLabel: String { selectedCount == 1 ? "Start Now" : "Create Room" }

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Icon + title
                VStack(spacing: 10) {
                    Image(systemName: selectedCount == 1 ? "person.fill" : "person.3.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Comic.yellow)
                        .shadow(color: Comic.black, radius: 0, x: 3, y: 3)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedCount)
                        .padding(.top, 36)
                    Text("How many players?")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                    Text("AI fills any empty seats")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                }
                .padding(.bottom, 28)

                // Count selector — 6 circles
                HStack(spacing: 8) {
                    ForEach(1...6, id: \.self) { count in
                        Button {
                            HapticManager.impact(.light)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                selectedCount = count
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedCount == count ? Comic.yellow : Comic.containerBG)
                                    .frame(width: 50, height: 50)
                                    .overlay(Circle().strokeBorder(Comic.black, lineWidth: Comic.borderWidth))
                                    .shadow(color: Comic.black.opacity(selectedCount == count ? 0.85 : 0.25),
                                            radius: 0, x: 2, y: 2)
                                Text("\(count)")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(selectedCount == count ? Comic.black : Comic.textSecondary)
                            }
                        }
                        .buttonStyle(BouncyButton())
                    }
                }
                .padding(.bottom, 24)

                // Description
                Text(description)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .frame(minHeight: 48)
                    .animation(.easeInOut(duration: 0.18), value: selectedCount)
                    .padding(.bottom, 36)

                Spacer()

                // Action button
                Button(action: onConfirm) {
                    Text(buttonLabel)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .animation(.easeInOut(duration: 0.18), value: selectedCount)
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Comic.bg)
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    /// Solid icon-background colour
    var iconBG: Color = Comic.yellow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(iconBG)
                        .frame(width: 56, height: 56)
                        .overlay(Circle().strokeBorder(Comic.black, lineWidth: Comic.borderWidth))
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Comic.white)
                }
                .shadow(color: Comic.black.opacity(0.85), radius: 0, x: 3, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
            }
            .padding(20)
            .comicContainer(cornerRadius: 20)
        }
        .buttonStyle(BouncyButton())
    }
}

