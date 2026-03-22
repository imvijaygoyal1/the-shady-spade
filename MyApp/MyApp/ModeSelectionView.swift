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
    @State private var showingSettings = false
    @State private var showingLeaderboard = false
    @State private var namePromptRequest: NamePromptRequest? = nil
    @State private var pendingName = ""
    @State private var pendingAvatar = "🦁"
    @State private var nameConfirmed = false
    @State private var confirmedIsOnline = false
    @AppStorage("soloPlayerName") private var soloPlayerName = ""
    @AppStorage("soloPlayerAvatar") private var soloPlayerAvatar = "🦁"

    var body: some View {
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
                    .padding(.top, 56)
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
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                }
                Spacer()
            }

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
                        icon: "person.fill.badge.plus",
                        title: "Play Solo",
                        subtitle: "Face 5 AI opponents in a fully simulated game",
                        color: Comic.yellow,
                        iconBG: Comic.yellow
                    ) {
                        HapticManager.impact(.medium)
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        namePromptRequest = NamePromptRequest(mode: "Solo Game", isOnline: false)
                    }

                    ModeCard(
                        icon: "person.3.fill",
                        title: "Multiplayer",
                        subtitle: "Play with friends — mix humans and AI",
                        color: Comic.blue,
                        iconBG: Comic.blue
                    ) {
                        HapticManager.impact(.medium)
                        pendingName = soloPlayerName
                        pendingAvatar = soloPlayerAvatar.isEmpty ? "🦁" : soloPlayerAvatar
                        namePromptRequest = NamePromptRequest(mode: "Multiplayer", isOnline: true)
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
        }
        .onAppear { vm.setup(with: modelContext) }
        .sheet(item: $namePromptRequest, onDismiss: {
            if nameConfirmed {
                nameConfirmed = false
                if confirmedIsOnline { showingOnline = true }
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
                confirmedIsOnline = request.isOnline
                nameConfirmed = true
                namePromptRequest = nil
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
        .sheet(isPresented: $showingLeaderboard) {
            LeaderboardView()
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(themeManager)
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
                onGameReady: { myIndex, isHostVal, code, names, avatars in
                    onlineGame = OnlineGameViewModel(
                        myPlayerIndex: myIndex,
                        isHost: isHostVal,
                        sessionCode: code,
                        playerNames: names,
                        playerAvatars: avatars,
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

