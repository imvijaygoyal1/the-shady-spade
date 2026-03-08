import SwiftUI

// MARK: - Share Sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Online Session View

struct OnlineSessionView: View {
    @Bindable var vm: GameViewModel
    var playerName: String = "Player"
    var playerAvatar: String = "🦁"
    /// When provided, skip CreateOrJoinView and go straight to lobby with this pre-created session
    var prebuiltSessionVM: OnlineSessionViewModel? = nil
    var prebuiltPlayerUID: String? = nil
    var onGameReady: ((Int, Bool, String, [String]) -> Void)? = nil

    @State private var ownedSessionVM = OnlineSessionViewModel()
    @State private var ownedPlayerUID = UUID().uuidString
    @Environment(\.dismiss) private var dismiss

    private var sessionVM: OnlineSessionViewModel { prebuiltSessionVM ?? ownedSessionVM }
    private var playerUID: String { prebuiltPlayerUID ?? ownedPlayerUID }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            if sessionVM.sessionCode == nil {
                CreateOrJoinView(
                    sessionVM: sessionVM,
                    playerName: playerName,
                    playerAvatar: playerAvatar,
                    playerUID: playerUID
                )
            } else {
                SessionLobbyView(
                    sessionVM: sessionVM,
                    vm: vm,
                    playerUID: playerUID,
                    onGameReady: onGameReady
                ) {
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
    let playerName: String
    let playerAvatar: String
    let playerUID: String

    @State private var showingJoin = false

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            // Player identity
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.masterGold.opacity(0.12))
                        .frame(width: 88, height: 88)
                        .overlay(Circle().stroke(Color.masterGold.opacity(0.4), lineWidth: 1.5))
                    Text(playerAvatar)
                        .font(.system(size: 48))
                }
                Text("Playing as")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(playerName)
                    .font(.title3.bold())
                    .foregroundStyle(.adaptivePrimary)
            }

            VStack(spacing: 14) {
                // Host a Game
                Button {
                    HapticManager.impact(.medium)
                    Task {
                        await sessionVM.createSession(uid: playerUID, name: playerName, avatar: playerAvatar)
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.15)).frame(width: 44, height: 44)
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Host a Game").font(.headline.bold())
                            Text("Create a room and share the code")
                                .font(.caption).opacity(0.75)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .foregroundStyle(.black)
                    .padding(18)
                    .background(Color.masterGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(BouncyButton())

                // Join a Game
                Button {
                    HapticManager.impact(.medium)
                    showingJoin = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.adaptiveSubtle).frame(width: 44, height: 44)
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3).foregroundStyle(.masterGold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join a Game").font(.headline.bold()).foregroundStyle(.adaptivePrimary)
                            Text("Enter the 6-letter room code")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color.adaptiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .adaptiveContentFrame()
        .padding()
        .sheet(isPresented: $showingJoin) {
            JoinByCodeView(
                sessionVM: sessionVM,
                playerUID: playerUID,
                playerName: playerName,
                playerAvatar: playerAvatar
            )
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Join By Code (OTP-style)

private struct JoinByCodeView: View {
    var sessionVM: OnlineSessionViewModel
    let playerUID: String
    let playerName: String
    let playerAvatar: String

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var joinError: String? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Enter Room Code")
                    .font(.title2.bold())
                    .foregroundStyle(.adaptivePrimary)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    // OTP-style 6-box code entry
                    ZStack {
                        // Visual character boxes (non-interactive overlay)
                        HStack(spacing: 10) {
                            ForEach(0..<6, id: \.self) { i in
                                let c: String = code.count > i
                                    ? String(code[code.index(code.startIndex, offsetBy: i)])
                                    : ""
                                let filled = i < code.count
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(filled ? Color.adaptiveSubtle : Color.adaptiveDivider)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(
                                                    filled ? Color.masterGold : Color.adaptiveDivider,
                                                    lineWidth: filled ? 2 : 1
                                                )
                                        )
                                    Text(c)
                                        .font(.system(size: 26, weight: .black, design: .monospaced))
                                        .foregroundStyle(.masterGold)
                                }
                                .frame(width: 46, height: 60)
                            }
                        }
                        .allowsHitTesting(false)

                        // Invisible TextField captures all keyboard input
                        TextField("", text: $code)
                            .opacity(0.01)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($fieldFocused)
                            .onChange(of: code) { _, new in
                                code = String(new.prefix(6).uppercased())
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 64)
                    .contentShape(Rectangle())
                    .onTapGesture { fieldFocused = true }

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
                    .background(code.count == 6 ? Color.masterGold : Color.masterGold.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButton())
                .disabled(code.count < 6 || isJoining)
            }
            .padding()
        }
        .onAppear { fieldFocused = true }
    }

    private func joinSession() {
        isJoining = true
        joinError = nil
        Task {
            do {
                try await sessionVM.joinSession(
                    code: code.uppercased(),
                    uid: playerUID,
                    name: playerName,
                    avatar: playerAvatar
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
    let playerUID: String
    var onGameReady: ((Int, Bool, String, [String]) -> Void)? = nil
    var onGameStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var codeCopied = false
    @State private var showingShare = false

    private var gridColumns: [GridItem] {
        let count = hSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Button {
                        Task { await sessionVM.leaveSession() }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.adaptiveSubtle)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Leave lobby")
                    Spacer()
                    Text("Game Lobby")
                        .font(.headline.bold())
                        .foregroundStyle(.adaptivePrimary)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.top, 8)

                // Room code card
                VStack(spacing: 12) {
                    Text("ROOM CODE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)

                    // Individual character boxes
                    HStack(spacing: 6) {
                        ForEach(Array((sessionVM.sessionCode ?? "------").enumerated()), id: \.offset) { _, ch in
                            Text(String(ch))
                                .font(.system(size: 36, weight: .black, design: .monospaced))
                                .foregroundStyle(.masterGold)
                                .frame(minWidth: 30)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.masterGold.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.masterGold.opacity(0.45), lineWidth: 1.5)
                    )

                    // Connecting / error state
                    if sessionVM.isConnecting {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8).tint(.secondary)
                            Text("Connecting to server…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let err = sessionVM.errorMessage {
                        VStack(spacing: 8) {
                            Text(err)
                                .font(.caption).foregroundStyle(.defenseRose)
                                .multilineTextAlignment(.center)
                            Button {
                                sessionVM.errorMessage = nil
                                sessionVM.isConnecting = true
                                Task { await sessionVM.writeSessionToFirebase() }
                            } label: {
                                Text("Retry")
                                    .font(.caption.bold()).foregroundStyle(.masterGold)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(Color.masterGold.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text(sessionVM.sessionType == "custom"
                             ? "Share this code with friends to join"
                             : "Share this code with 5 friends")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        // Share button → native share sheet
                        Button {
                            HapticManager.impact(.medium)
                            showingShare = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up").font(.subheadline.bold())
                                Text("Share Code").font(.subheadline.bold())
                            }
                            .foregroundStyle(sessionVM.isConnecting ? Color.secondary : .black)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(sessionVM.isConnecting ? Color.masterGold.opacity(0.4) : Color.masterGold)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(sessionVM.isConnecting)

                        // Copy button with toast
                        Button {
                            UIPasteboard.general.string = sessionVM.sessionCode
                            HapticManager.success()
                            codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { codeCopied = false }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                Text(codeCopied ? "Copied!" : "Copy").font(.subheadline.bold())
                            }
                            .foregroundStyle(codeCopied ? .masterGold : Color.adaptivePrimary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.adaptiveSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .accessibilityLabel(codeCopied ? "Code copied" : "Copy room code")
                        .disabled(sessionVM.isConnecting)
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 20)
                .task(id: sessionVM.isConnecting) {
                    guard sessionVM.isConnecting else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if sessionVM.isConnecting {
                        sessionVM.errorMessage = "Connection is taking too long. Please retry."
                        sessionVM.isConnecting = false
                    }
                }

                // Player slots
                let humanSlots = (0..<6).filter { !sessionVM.aiSeats.contains($0) }
                let humanJoined = humanSlots.filter { sessionVM.playerSlots[$0].joined }.count
                VStack(alignment: .leading, spacing: 12) {
                    Text(sessionVM.aiSeats.isEmpty
                         ? "Players (\(sessionVM.playerSlots.filter(\.joined).count)/6)"
                         : "Players (\(humanJoined)/\(humanSlots.count) humans + \(sessionVM.aiSeats.count) AI)")
                        .font(.headline)
                        .foregroundStyle(.masterGold)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(0..<6, id: \.self) { i in
                            PlayerSlotCard(index: i, slot: sessionVM.playerSlots[i],
                                           isAI: sessionVM.aiSeats.contains(i))
                        }
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                // Start / waiting
                let canStart = sessionVM.aiSeats.isEmpty ? sessionVM.allSlotsJoined : sessionVM.humanSlotsFull
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
                            .background(canStart ? Color.masterGold : Color.masterGold.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(BouncyButton())
                        .disabled(!canStart)

                        if !canStart {
                            let needed = humanSlots.count - humanJoined
                            Text("Waiting for \(needed) more player\(needed == 1 ? "" : "s") to join…")
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
            .adaptiveContentFrame()
            .padding()
        }
        .onChange(of: sessionVM.status) { _, newStatus in
            if newStatus == .playing, let onGameReady {
                let myIndex = sessionVM.playerSlots.firstIndex(where: { $0.uid == playerUID }) ?? 0
                let names = sessionVM.playerSlots.map { slot in
                    slot.name.isEmpty ? "Player \(slot.slotIndex + 1)" : slot.name
                }
                onGameReady(myIndex, sessionVM.isHost, sessionVM.sessionCode ?? "", names)
            }
        }
        .sheet(isPresented: $showingShare) {
            if let code = sessionVM.sessionCode {
                let isCustom = sessionVM.sessionType == "custom"
                let text = isCustom
                    ? "Join my Shady Spade Custom Game! Code: \(code) in the app. shadyspade://join/\(code)"
                    : "Join my Shady Spade game! Use code: \(code) in the app. shadyspade://join/\(code)"
                ShareSheetView(items: [text])
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Player Slot Card

private struct PlayerSlotCard: View {
    let index: Int
    let slot: SessionPlayer
    var isAI: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isAI
                          ? Color.adaptiveSubtle
                          : slot.joined
                              ? Color.offenseBlue.opacity(0.18)
                              : Color.adaptiveDivider)
                    .frame(width: 36, height: 36)
                if isAI {
                    Text("🤖").font(.system(size: 20))
                } else if slot.joined {
                    if !slot.avatar.isEmpty {
                        Text(slot.avatar).font(.system(size: 20))
                    } else {
                        Text(String(slot.name.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.offenseBlue)
                    }
                } else {
                    Image(systemName: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isAI ? slot.name : (slot.joined ? slot.name : "Empty"))
                    .font(.subheadline.weight((slot.joined || isAI) ? .semibold : .regular))
                    .foregroundStyle(isAI ? Color.adaptiveSecondary : (slot.joined ? Color.adaptivePrimary : .secondary))
                    .lineLimit(1)
                Text(isAI ? "AI Player" : "Slot \(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isAI {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(Color.adaptiveSecondary)
                    .font(.caption)
            } else if slot.joined {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.offenseBlue)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isAI
                    ? Color.adaptiveDivider
                    : slot.joined ? Color.offenseBlue.opacity(0.06) : Color.adaptiveDivider)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isAI
                              ? Color.adaptiveSubtle
                              : slot.joined ? Color.offenseBlue.opacity(0.30) : Color.adaptiveSubtle,
                              lineWidth: 1)
        }
    }
}
