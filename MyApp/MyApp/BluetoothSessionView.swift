import SwiftUI
import MultipeerConnectivity

// MARK: - Bluetooth Session Entry

struct BluetoothSessionView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let playerName: String
    let playerAvatar: String
    var onGameReady: ((BluetoothGameViewModel) -> Void)? = nil

    @State private var vm = BluetoothGameViewModel()
    @State private var showHostLobby = false
    @State private var showClientLobby = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            if showHostLobby {
                BTHostLobbyView(vm: vm, onGameReady: onGameReady)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if showClientLobby {
                BTClientLobbyView(vm: vm, onGameReady: onGameReady)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                BTModePickerView(
                    playerName: playerName,
                    playerAvatar: playerAvatar,
                    onHost: {
                        HapticManager.impact(.medium)
                        vm.startHosting(playerName: playerName, avatar: playerAvatar)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showHostLobby = true
                        }
                    },
                    onJoin: {
                        HapticManager.impact(.medium)
                        vm.startBrowsing(playerName: playerName, avatar: playerAvatar)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showClientLobby = true
                        }
                    }
                )
            }

            // Back button
            VStack {
                HStack {
                    Button {
                        HapticManager.impact(.light)
                        if showHostLobby || showClientLobby {
                            // LOW-11: only call cleanup() from the lobby — if the session is
                            // already playing, cleanup tears down peers without notifying them.
                            if vm.sessionState != .playing {
                                vm.cleanup()
                            }
                            withAnimation {
                                showHostLobby = false
                                showClientLobby = false
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Comic.white)
                            .frame(width: 32, height: 32)
                            .background(Comic.black)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Comic.white, lineWidth: 2))
                    }
                    .padding(.top, 16)
                    .padding(.leading, 16)
                    Spacer()
                }
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showHostLobby)
        .animation(.easeInOut(duration: 0.3), value: showClientLobby)
    }
}

// MARK: - Mode Picker (Host or Join)

private struct BTModePickerView: View {
    let playerName: String
    let playerAvatar: String
    let onHost: () -> Void
    let onJoin: () -> Void

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

            VStack(spacing: 8) {
                // Title
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.masterGold)
                    Text("Local / Bluetooth")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.masterGold)
                }
                Text("Find friends nearby — no internet needed")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                // Host a Game
                Button(action: onHost) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.15)).frame(width: 44, height: 44)
                            Image(systemName: "wifi.router").font(.title3)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Host a Game").font(.headline.bold())
                            Text("Create a session and invite friends nearby")
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
                Button(action: onJoin) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.adaptiveSubtle).frame(width: 44, height: 44)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3).foregroundStyle(.masterGold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join a Game").font(.headline.bold()).foregroundStyle(.adaptivePrimary)
                            Text("Find nearby hosts and join their game")
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
            .adaptiveContentFrame()
            .padding(.horizontal, 20)

            Spacer()
        }
    }
}

// MARK: - Host Lobby

struct BTHostLobbyView: View {
    @Bindable var vm: BluetoothGameViewModel
    var onGameReady: ((BluetoothGameViewModel) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var tvManager = TVDisplayManager.shared
    @State private var qrCode: UIImage? = nil

    private var gridColumns: [GridItem] {
        let count = hSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private var connectedHumanCount: Int {
        vm.connectedPlayerSlots.filter { $0.joined && !vm.aiSeats.contains($0.slotIndex) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Hosting Game")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    HStack(spacing: 6) {
                        LiveDot()
                        Text("Nearby players can find and join your game")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if tvManager.isExternalScreenConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "tv.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.green)
                            Text("TV Connected — game board will show on screen")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 60)

                // Player count
                VStack(spacing: 6) {
                    Text("PLAYERS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                    Text("\(connectedHumanCount)/6")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("connected")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .glassmorphic(cornerRadius: 20)
                .padding(.horizontal, 16)

                // TV Dashboard section
                if !vm.localServerURL.isEmpty {
                    VStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "tv.and.mediabox")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.masterGold)
                            Text("TV Dashboard")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.masterGold)
                        }

                        if let qr = qrCode {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Text(vm.localServerURL)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Open this URL in your TV's browser")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .glassmorphic(cornerRadius: 20)
                    .padding(.horizontal, 16)
                    .onChange(of: vm.localServerURL) { _, url in
                        qrCode = url.isEmpty ? nil : LocalGameServer.makeQRCode(from: url, size: 280)
                    }
                    .onAppear {
                        if !vm.localServerURL.isEmpty {
                            qrCode = LocalGameServer.makeQRCode(from: vm.localServerURL, size: 280)
                        }
                    }
                }

                // Player slots
                VStack(alignment: .leading, spacing: 12) {
                    Text("Players")
                        .font(.headline)
                        .foregroundStyle(.masterGold)
                        .padding(.leading, 4)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(0..<6, id: \.self) { i in
                            BTPlayerSlotCard(
                                index: i,
                                slot: vm.connectedPlayerSlots[i],
                                isAI: vm.aiSeats.contains(i),
                                isHost: i == 0
                            )
                        }
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 20)
                .padding(.horizontal, 16)

                // Start button
                VStack(spacing: 8) {
                    Button {
                        HapticManager.impact(.heavy)
                        // startGame() is called by BluetoothGameView's .task{} when it appears.
                        // Calling it here too causes a double-deal race condition.
                        if let onGameReady { onGameReady(vm) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text("Start Game").fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(connectedHumanCount >= 2 ? Color.masterGold : Color.masterGold.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())
                    .disabled(connectedHumanCount < 2)

                    if connectedHumanCount < 2 {
                        Text("Need at least 2 human players to start")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Empty slots will be filled with AI bots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.defenseRose)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - Client Lobby

struct BTClientLobbyView: View {
    @Bindable var vm: BluetoothGameViewModel
    var onGameReady: ((BluetoothGameViewModel) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Find a Game")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    HStack(spacing: 6) {
                        LiveDot()
                        Text("Looking for nearby games…")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 60)

                if vm.sessionState == .connecting {
                    // Invitation sent — waiting for host to accept
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.4).tint(.masterGold)
                        Text("Connecting…")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.adaptivePrimary)
                        Text("Waiting for the host to accept")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .glassmorphic(cornerRadius: 20)
                    .padding(.horizontal, 16)
                } else if vm.sessionState == .connected {
                    // Joined — show lobby info
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.offenseBlue)

                        Text("Connected!")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.adaptivePrimary)

                        Text("Waiting for the host to start the game…")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        ProgressView().tint(.masterGold)

                        // Show player list
                        if !vm.playerNames.filter({ !$0.isEmpty }).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Players in Lobby")
                                    .font(.headline)
                                    .foregroundStyle(.masterGold)

                                ForEach(0..<6, id: \.self) { i in
                                    if !vm.playerNames[i].isEmpty {
                                        BTPlayerSlotCard(
                                            index: i,
                                            slot: vm.connectedPlayerSlots[i],
                                            isAI: vm.aiSeats.contains(i),
                                            isHost: i == 0
                                        )
                                    }
                                }
                            }
                            .padding()
                            .glassmorphic(cornerRadius: 20)
                            .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // Browsing — show found sessions
                    if vm.foundSessions.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.4).tint(.masterGold)
                            Text("Scanning for nearby games…")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("Make sure the host has started their session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .glassmorphic(cornerRadius: 20)
                        .padding(.horizontal, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Nearby Games")
                                .font(.headline)
                                .foregroundStyle(.masterGold)
                                .padding(.leading, 4)

                            ForEach(vm.foundSessions, id: \.peerID) { session in
                                BTFoundSessionRow(
                                    hostName: session.info["hostName"] ?? session.peerID.displayName,
                                    avatar: session.info["avatar"] ?? "🃏",
                                    onJoin: {
                                        HapticManager.impact(.medium)
                                        vm.connectTo(peerID: session.peerID)
                                    }
                                )
                            }
                        }
                        .padding()
                        .glassmorphic(cornerRadius: 20)
                        .padding(.horizontal, 16)
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.defenseRose)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer().frame(height: 40)
            }
        }
        .onChange(of: vm.sessionState) { _, newState in
            if newState == .playing {
                if let onGameReady { onGameReady(vm) }
            }
        }
    }
}

// MARK: - Found Session Row

private struct BTFoundSessionRow: View {
    let hostName: String
    let avatar: String
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.offenseBlue.opacity(0.18))
                    .frame(width: 44, height: 44)
                Text(avatar)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(hostName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.adaptivePrimary)
                Text("Hosting nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onJoin) {
                Text("Join")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.masterGold)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButton())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Player Slot Card

private struct BTPlayerSlotCard: View {
    let index: Int
    let slot: BTPlayerSlot
    var isAI: Bool = false
    var isHost: Bool = false

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

            VStack(alignment: .leading, spacing: 4) {
                Text(isAI ? slot.name : (slot.joined ? slot.name : "Empty"))
                    .font(.subheadline.weight((slot.joined || isAI) ? .semibold : .regular))
                    .foregroundStyle(isAI ? Color.adaptiveSecondary : (slot.joined ? Color.adaptivePrimary : .secondary))
                    .lineLimit(1)

                if isHost {
                    Text("HOST")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.masterGold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.masterGold.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.masterGold.opacity(0.4), lineWidth: 1))
                } else if isAI {
                    Text("AI")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.adaptiveDivider)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if slot.joined && !isAI {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isHost ? Color.masterGold : .offenseBlue)
                    .font(.caption)
            } else if isAI {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(Color.adaptiveSecondary)
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
                .strokeBorder(
                    isHost ? Color.masterGold.opacity(0.4) :
                    isAI ? Color.adaptiveSubtle :
                    slot.joined ? Color.offenseBlue.opacity(0.30) : Color.adaptiveSubtle,
                    lineWidth: isHost ? 1.5 : 1
                )
        }
        .opacity(isAI ? 0.85 : 1.0)
    }
}
