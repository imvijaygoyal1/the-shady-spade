import SwiftUI
import SwiftData

struct ModeSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authVM
    @State private var vm = GameViewModel()
    @State private var showingSolo = false
    @State private var showingOnline = false
    @State private var showingAuth = false
    @State private var showingSettings = false
    @State private var showingNamePrompt = false
    @State private var pendingName = ""
    @State private var pendingAvatar = "🦁"
    @State private var nameConfirmed = false
    @AppStorage("soloPlayerName") private var soloPlayerName = ""
    @AppStorage("soloPlayerAvatar") private var soloPlayerAvatar = "🦁"

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            // Settings button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        HapticManager.impact(.light)
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.1))
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
                        .foregroundStyle(.white)
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
                        if authVM.isEmailVerified {
                            showingOnline = true
                        } else {
                            showingAuth = true
                        }
                    }
                }
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
            if nameConfirmed { nameConfirmed = false; showingSolo = true }
        }) {
            NamePromptSheet(pendingName: $pendingName, pendingAvatar: $pendingAvatar) {
                let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
                soloPlayerName = trimmed.isEmpty ? "Player" : trimmed
                soloPlayerAvatar = pendingAvatar
                nameConfirmed = true
                showingNamePrompt = false
            }
        }
        .fullScreenCover(isPresented: $showingSolo) {
            ComputerGameView(vm: vm, humanName: soloPlayerName.isEmpty ? "Player" : soloPlayerName)
        }
        .fullScreenCover(isPresented: $showingAuth, onDismiss: {
            if authVM.isEmailVerified { showingOnline = true }
        }) {
            AuthView()
                .environment(authVM)
        }
        .fullScreenCover(isPresented: $showingOnline) {
            OnlineEntryView(vm: vm)
                .environment(authVM)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(vm: vm)
                .environment(authVM)
        }
    }
}

// MARK: - Online Entry

private struct OnlineEntryView: View {
    @Bindable var vm: GameViewModel
    @Environment(AuthViewModel.self) private var authVM
    @State private var onlineGame: OnlineGameViewModel? = nil

    var body: some View {
        if let game = onlineGame {
            OnlineGameView(game: game)
        } else {
            OnlineSessionView(vm: vm, onGameReady: { myIndex, isHostVal, code, names in
                onlineGame = OnlineGameViewModel(
                    myPlayerIndex: myIndex,
                    isHost: isHostVal,
                    sessionCode: code,
                    playerNames: names,
                    dealerIndex: 0,
                    roundNumber: 1
                )
            })
            .environment(authVM)
        }
    }
}

private struct NamePromptSheet: View {
    @Binding var pendingName: String
    @Binding var pendingAvatar: String
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
                    ZStack(alignment: .bottomTrailing) {
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
                        // Edit badge
                        ZStack {
                            Circle()
                                .fill(Color.masterGold)
                                .frame(width: 28, height: 28)
                                .shadow(color: Color.masterGold.opacity(0.5), radius: 6)
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .offset(x: 2, y: 2)
                    }
                    .padding(.top, 28)

                    // Title & subtitle
                    VStack(spacing: 6) {
                        Text("Solo Game")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
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
                                                      : Color.white.opacity(0.07))
                                                .frame(width: 64, height: 64)
                                                .overlay(
                                                    Circle()
                                                        .stroke(
                                                            isSelected ? Color.masterGold : Color.white.opacity(0.12),
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
                                    ? AnyShapeStyle(Color.white.opacity(0.12))
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
                        .foregroundStyle(.white)
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
