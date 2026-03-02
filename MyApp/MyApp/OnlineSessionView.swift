import SwiftUI

struct OnlineSessionView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Bindable var vm: GameViewModel
    @State private var sessionVM = OnlineSessionViewModel()
    @Environment(\.dismiss) private var dismiss

    /// When non-nil: called with (myIndex, isHost, sessionCode, playerNames) to launch the full game engine.
    /// When nil: falls back to legacy `vm.enterOnlineMode` score-tracker flow.
    var onGameReady: ((Int, Bool, String, [String]) -> Void)? = nil

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            if sessionVM.sessionCode == nil {
                CreateOrJoinView(sessionVM: sessionVM, authVM: authVM)
            } else {
                SessionLobbyView(sessionVM: sessionVM, vm: vm, onGameReady: onGameReady) {
                    vm.enterOnlineMode(sessionVM)
                    dismiss()
                }
            }
        }
        .onChange(of: sessionVM.status) { _, newStatus in
            if newStatus == .playing && onGameReady == nil {
                vm.enterOnlineMode(sessionVM)
                dismiss()
            }
        }
    }
}

// MARK: - Create or Join

private struct CreateOrJoinView: View {
    var sessionVM: OnlineSessionViewModel
    var authVM: AuthViewModel
    @State private var showingJoin = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 56))
                    .foregroundStyle(.masterGold)
                Text("Online Game")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                Text("Create a new game or join friends with a code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                Button {
                    HapticManager.impact(.medium)
                    let uid = authVM.user?.uid ?? ""
                    let name = authVM.user?.displayName ?? authVM.user?.email ?? "Player"
                    Task { await sessionVM.createSession(uid: uid, name: String(name.prefix(20))) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Game").fontWeight(.bold)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.masterGold)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButton())

                Button {
                    HapticManager.impact(.medium)
                    showingJoin = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Join Game").fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButton())
            }

            if let error = sessionVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.defenseRose)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingJoin) {
            JoinByCodeView(sessionVM: sessionVM, authVM: authVM)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Join By Code

private struct JoinByCodeView: View {
    var sessionVM: OnlineSessionViewModel
    var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var joinError: String? = nil

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Enter Room Code")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    TextField("e.g. SPADE4", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.masterGold)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let error = joinError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.defenseRose)
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                Button {
                    HapticManager.impact(.medium)
                    joinSession()
                } label: {
                    Group {
                        if isJoining {
                            ProgressView().tint(.black)
                        } else {
                            Text("Join Game").fontWeight(.bold)
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(code.count == 6 ? Color.masterGold : Color.masterGold.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButton())
                .disabled(code.count < 6 || isJoining)
            }
            .padding()
        }
    }

    private func joinSession() {
        let uid = authVM.user?.uid ?? ""
        let name = authVM.user?.displayName ?? authVM.user?.email ?? "Player"
        isJoining = true
        joinError = nil
        Task {
            do {
                try await sessionVM.joinSession(
                    code: code.uppercased(),
                    uid: uid,
                    name: String(name.prefix(20))
                )
                dismiss()
            } catch {
                joinError = "Room not found or is full."
            }
            isJoining = false
        }
    }
}

// MARK: - Session Lobby

private struct SessionLobbyView: View {
    var sessionVM: OnlineSessionViewModel
    var vm: GameViewModel
    var onGameReady: ((Int, Bool, String, [String]) -> Void)? = nil
    var onGameStart: () -> Void
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var codeCopied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header row
                HStack {
                    Button {
                        Task { await sessionVM.leaveSession() }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Leave lobby")
                    Spacer()
                    Text("Game Lobby")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.top, 8)

                // Room code card
                VStack(spacing: 8) {
                    Text("Room Code")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text(sessionVM.sessionCode ?? "------")
                            .font(.system(size: 36, weight: .black, design: .monospaced))
                            .foregroundStyle(.masterGold)
                        Button {
                            UIPasteboard.general.string = sessionVM.sessionCode
                            HapticManager.success()
                            codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                codeCopied = false
                            }
                        } label: {
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(codeCopied ? .offenseBlue : .masterGold)
                                .font(.title3)
                        }
                        .accessibilityLabel(codeCopied ? "Code copied" : "Copy room code")
                    }
                    Text("Share this code with 5 friends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                // Player slots
                VStack(alignment: .leading, spacing: 12) {
                    Text("Players (\(sessionVM.playerSlots.filter(\.joined).count)/6)")
                        .font(.headline)
                        .foregroundStyle(.masterGold)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                              spacing: 12) {
                        ForEach(0..<6, id: \.self) { i in
                            PlayerSlotCard(index: i, slot: sessionVM.playerSlots[i], vm: vm)
                        }
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                // Start / waiting
                if sessionVM.isHost {
                    VStack(spacing: 8) {
                        Button {
                            HapticManager.impact(.heavy)
                            Task { await sessionVM.startGame() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("Start Game").fontWeight(.bold)
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(sessionVM.allSlotsJoined
                                        ? Color.masterGold
                                        : Color.masterGold.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(BouncyButton())
                        .disabled(!sessionVM.allSlotsJoined)

                        if !sessionVM.allSlotsJoined {
                            Text("Waiting for all 6 players to join…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView().tint(.masterGold)
                        Text("Waiting for host to start…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .onChange(of: sessionVM.status) { _, newStatus in
            if newStatus == .playing, let onGameReady {
                let myUID = authVM.user?.uid ?? ""
                let myIndex = sessionVM.playerSlots.firstIndex(where: { $0.uid == myUID }) ?? 0
                let names = sessionVM.playerSlots.map { slot in
                    slot.name.isEmpty ? "Player \(slot.slotIndex + 1)" : slot.name
                }
                onGameReady(myIndex, sessionVM.isHost, sessionVM.sessionCode ?? "", names)
            }
        }
    }
}

// MARK: - Player Slot Card

private struct PlayerSlotCard: View {
    let index: Int
    let slot: SessionPlayer
    let vm: GameViewModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(slot.joined
                          ? Color.offenseBlue.opacity(0.18)
                          : Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)
                if slot.joined {
                    Image(systemName: vm.playerAvatars[index])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.offenseBlue)
                } else {
                    Image(systemName: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.joined ? slot.name : "Empty")
                    .font(.subheadline.weight(slot.joined ? .semibold : .regular))
                    .foregroundStyle(slot.joined ? .white : .secondary)
                    .lineLimit(1)
                Text("Slot \(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if slot.joined {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.offenseBlue)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(slot.joined ? Color.offenseBlue.opacity(0.06) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(slot.joined
                              ? Color.offenseBlue.opacity(0.30)
                              : Color.white.opacity(0.08),
                              lineWidth: 1)
        }
    }
}
