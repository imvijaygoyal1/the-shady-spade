import SwiftUI
import CoreImage.CIFilterBuiltins
import FirebaseAuth

// MARK: - Online Session View

struct OnlineSessionView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var vm: GameViewModel
    var playerName: String = "Player"
    var playerAvatar: String = "🦁"
    /// When provided, skip CreateOrJoinView and go straight to lobby with this pre-created session
    var prebuiltSessionVM: OnlineSessionViewModel? = nil
    var prebuiltPlayerUID: String? = nil
    /// When true, automatically open the join-by-code sheet on first appear
    var autoShowJoin: Bool = false
    var onGameReady: ((Int, Bool, String, [String], [String]) -> Void)? = nil

    @State private var ownedSessionVM = OnlineSessionViewModel()
    @State private var ownedPlayerUID = Auth.auth().currentUser?.uid ?? UUID().uuidString
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
                    playerUID: playerUID,
                    autoShowJoin: autoShowJoin
                )
                .overlay(alignment: .topLeading) {
                    Button {
                        HapticManager.impact(.light)
                        dismiss()
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
                }
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
    var autoShowJoin: Bool = false

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
                    sessionVM.prepareLocalSession(
                        uid: playerUID,
                        name: playerName,
                        avatar: playerAvatar,
                        aiSeats: [1, 2, 3, 4, 5],
                        sessionType: "multiplayer"
                    )
                    Task { await sessionVM.writeSessionToFirebase() }
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
        .onAppear {
            if autoShowJoin { showingJoin = true }
            // Handle deep link cold-start: code stored before this view existed
            if DeepLinkManager.shared.pendingJoinCode != nil {
                showingJoin = true
            }
        }
        .sheet(isPresented: $showingJoin) {
            JoinByCodeView(
                sessionVM: sessionVM,
                playerUID: playerUID,
                playerName: playerName,
                playerAvatar: playerAvatar,
                initialCode: {
                    let code = DeepLinkManager.shared.pendingJoinCode
                    DeepLinkManager.shared.pendingJoinCode = nil
                    return code
                }()
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
    var initialCode: String? = nil

    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var joinError: String? = nil
    @State private var showScanner = false
    @State private var scanError: String? = nil
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

                Button {
                    HapticManager.impact(.light)
                    showScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan QR Code").fontWeight(.semibold)
                    }
                    .foregroundStyle(.adaptivePrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.adaptiveSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButton())
            }
            .padding()
        }
        .onAppear {
            fieldFocused = true
            if let c = initialCode {
                code = String(c.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6).uppercased())
            }
        }
        .sheet(isPresented: $showScanner) {
            VStack(spacing: 0) {
                QRScannerView { scannedCode in
                    // Issue #1 fix: QR encodes the full universal link URL
                    // (https://shadyspade-d6b84.web.app/shadyspade/join/ABCD12).
                    // The old code did .prefix(6) on the raw URL, yielding "HTTPS:"
                    // instead of the room code. Parse the path component after "join".
                    let extracted = Self.extractRoomCode(from: scannedCode)
                    let isValid = extracted.count == 6 &&
                        extracted.allSatisfy { $0.isLetter || $0.isNumber }
                    guard isValid else {
                        // Issue #5 fix: reject scan → QRScannerView auto-restarts camera
                        scanError = "Couldn't read a valid room code. Try again."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { scanError = nil }
                        return false
                    }
                    scanError = nil
                    code = extracted
                    showScanner = false
                    return true   // accept — scanner stops
                }

                // Issue #5 fix: brief error banner inside the scanner sheet
                if let err = scanError {
                    Text(err)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.defenseRose.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: scanError)
                }
            }
            .presentationDetents([.large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .joinRoomFromQR)) { notification in
            if let incomingCode = notification.userInfo?["roomCode"] as? String {
                code = String(incomingCode.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6).uppercased())
                // Don't auto-join — let the player verify and tap Join
            }
        }
    }

    /// Issue #1 fix: QR codes encode the full universal link URL
    /// (https://shadyspade-d6b84.web.app/shadyspade/join/ABCD12).
    /// This extracts the 6-char room code from the path segment after "join",
    /// mirroring the logic in MyAppApp.handleIncomingURL.
    /// Falls back to treating the raw string as a code (future plain-code QRs).
    private static func extractRoomCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            // Lowercase the path before splitting — generateQRCode calls .uppercased()
            // on the full URL before encoding, so the QR contains
            // "HTTPS://…/JOIN/ABCD12" not "https://…/join/ABCD12".
            // Case-insensitive search ensures "JOIN" matches "join".
            let parts = comps.path.lowercased().split(separator: "/").map(String.init)
            if let joinIdx = parts.firstIndex(of: "join"), joinIdx + 1 < parts.count {
                // Extract from the original (non-lowercased) path so the room code
                // retains its original casing, then uppercase for normalisation.
                let originalParts = comps.path.split(separator: "/").map(String.init)
                return String(originalParts[joinIdx + 1].prefix(6).uppercased())
            }
        }
        return String(trimmed.prefix(6).uppercased())
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
            } catch let error as URLError
                where error.code == .resourceUnavailable {
                joinError = "Room is full."
            } catch let error as URLError {
                joinError = "Room not found. Check the code."
                print("Join error: \(error)")
            } catch {
                joinError = "Connection error. Check your " +
                    "internet and try again."
                print("Join error: \(error)")
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
    var onGameReady: ((Int, Bool, String, [String], [String]) -> Void)? = nil
    var onGameStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var codeCopied = false
    @State private var showQRCode = false
    @State private var newlyJoinedSlots: Set<Int> = []
    @State private var wasRemoved = false

    private func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.uppercased().utf8)
        filter.correctionLevel = "H"
        guard let outputImage = filter.outputImage else { return UIImage() }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }

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
                        Text("Share this code with friends to join")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        let buttonWidth = (geo.size.width - 20) / 3
                        HStack(spacing: 10) {
                            ShareLink(
                                item: """
Join my Shady Spade game! 🃏
Room Code: \(sessionVM.sessionCode ?? "")
Tap to join: https://shadyspade-d6b84.web.app/shadyspade/join/\(sessionVM.sessionCode ?? "")
""",
                                preview: SharePreview(
                                    "Shady Spade — Room \(sessionVM.sessionCode ?? "")"
                                )
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName:
                                        "square.and.arrow.up")
                                        .font(.subheadline.bold())
                                    Text("Share")
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(sessionVM.isConnecting
                                    ? Color.secondary : .black)
                                .frame(width: buttonWidth,
                                    height: 44)
                                .background(sessionVM.isConnecting
                                    ? Color.masterGold.opacity(0.4)
                                    : Color.masterGold)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous))
                            }
                            .disabled(sessionVM.isConnecting)

                            Button {
                                UIPasteboard.general.string =
                                    sessionVM.sessionCode
                                HapticManager.success()
                                codeCopied = true
                                DispatchQueue.main.asyncAfter(
                                    deadline: .now() + 2) {
                                    codeCopied = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: codeCopied
                                        ? "checkmark"
                                        : "doc.on.doc")
                                        .font(.subheadline.bold())
                                    Text(codeCopied
                                        ? "Copied!" : "Copy")
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(codeCopied
                                    ? .masterGold
                                    : Color.adaptivePrimary)
                                .frame(width: buttonWidth,
                                    height: 44)
                                .background(Color.adaptiveSubtle)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous))
                            }
                            .disabled(sessionVM.isConnecting)

                            Button {
                                HapticManager.impact(.light)
                                showQRCode = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "qrcode")
                                        .font(.subheadline.bold())
                                    Text("QR")
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(
                                    Color.adaptivePrimary)
                                .frame(width: buttonWidth,
                                    height: 44)
                                .background(Color.adaptiveSubtle)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous))
                            }
                            .disabled(sessionVM.isConnecting
                                || sessionVM.sessionCode == nil)
                        }
                    }
                    .frame(height: 44)
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
                let humanCount = (0..<6).filter { !sessionVM.aiSeats.contains($0) && sessionVM.playerSlots[$0].joined }.count
                let aiCount = sessionVM.aiSeats.count
                let isMultiplayer = sessionVM.sessionType == "multiplayer"
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Players (\(humanCount + aiCount)/6)")
                            .font(.headline)
                            .foregroundStyle(.masterGold)
                        Text("\(humanCount) human\(humanCount == 1 ? "" : "s") · \(aiCount) AI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isMultiplayer && aiCount == 0 {
                            Text("Room Full")
                                .font(.caption.bold())
                                .foregroundStyle(.defenseRose)
                        }
                    }

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(0..<6, id: \.self) { i in
                            let slot = sessionVM.playerSlots[i]
                            let isAI = sessionVM.aiSeats.contains(i)
                            let canRemove = sessionVM.isHost && i != 0 && slot.joined
                            PlayerSlotCard(
                                index: i,
                                slot: slot,
                                isAI: isAI,
                                isHost: i == 0 && slot.joined && !isAI,
                                isNew: newlyJoinedSlots.contains(i),
                                canRemove: canRemove,
                                onRemove: { Task { await sessionVM.removePlayer(atSlot: i) } }
                            )
                            .id("\(i)-\(isAI)")
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sessionVM.aiSeats)
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                // Start / waiting
                let humanSlots2 = (0..<6).filter { !sessionVM.aiSeats.contains($0) }
                let humanJoined2 = humanSlots2.filter { sessionVM.playerSlots[$0].joined }.count
                let canStart = isMultiplayer || (sessionVM.aiSeats.isEmpty ? sessionVM.allSlotsJoined : sessionVM.humanSlotsFull)
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

                        if isMultiplayer {
                            Text("Share the code to invite more friends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !canStart {
                            let needed = humanSlots2.count - humanJoined2
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
        .onChange(of: sessionVM.aiSeats) { oldAI, newAI in
            let joined = Set(oldAI).subtracting(Set(newAI))
            for slot in joined {
                withAnimation { newlyJoinedSlots.insert(slot) }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { newlyJoinedSlots.remove(slot) }
                }
            }
            // Detect if this player was removed by host
            if !sessionVM.isHost {
                let mySlotIndex = sessionVM.playerSlots
                    .first(where: { $0.uid == playerUID })?.slotIndex ?? -1
                if mySlotIndex >= 0 && Set(newAI).contains(mySlotIndex) &&
                   !Set(oldAI).contains(mySlotIndex) {
                    wasRemoved = true
                }
            }
        }
        .alert("Removed from Game", isPresented: $wasRemoved) {
            Button("OK") { dismiss() }
        } message: {
            Text("The host removed you from the game.")
        }
        .onChange(of: sessionVM.status) { _, newStatus in
            if newStatus == .playing, let onGameReady {
                let myIndex = sessionVM.playerSlots.firstIndex(where: { $0.uid == playerUID }) ?? 0
                let names = sessionVM.playerSlots.map { slot in
                    slot.name.isEmpty ? "Player \(slot.slotIndex + 1)" : slot.name
                }
                let avatars = sessionVM.playerSlots.map { $0.avatar }
                onGameReady(myIndex, sessionVM.isHost, sessionVM.sessionCode ?? "", names, avatars)
            }
        }
        .sheet(isPresented: $showQRCode) {
            if let code = sessionVM.sessionCode {
                QRCodeSheetView(
                    roomCode: code,
                    qrImage: generateQRCode(from: "https://shadyspade-d6b84.web.app/shadyspade/join/\(code)")
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - QR Code Sheet

struct QRCodeSheetView: View {
    let roomCode: String
    let qrImage: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Scrollable top section
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Title
                        Text("Scan to Join")
                            .font(.title2.bold())
                            .foregroundStyle(.adaptivePrimary)
                            .padding(.top, 8)

                        // Room code — large mono display
                        Text(roomCode)
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundStyle(.masterGold)
                            .tracking(8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 8)

                        // QR code — fixed size, no GeometryReader
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.masterGold.opacity(0.5), lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)

                        // Hint
                        VStack(spacing: 4) {
                            Text("Scan with your iPhone camera")
                                .font(.subheadline)
                                .foregroundStyle(.adaptivePrimary)
                            Text("or tap \"Join a Game\" and enter the code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                // Buttons — always pinned at bottom, never scroll away
                Divider().background(Color.adaptiveDivider)

                VStack(spacing: 10) {
                    ShareLink(
                        item: Image(uiImage: qrImage),
                        preview: SharePreview(
                            "Join my Shady Spade game — Room: \(roomCode)",
                            image: Image(uiImage: qrImage)
                        )
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share QR Code").fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.masterGold)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())

                    ShareLink(
                        item: """
Join my Shady Spade game! 🃏
Room Code: \(roomCode)
Tap to join: https://shadyspade-d6b84.web.app/shadyspade/join/\(roomCode)
""",
                        preview: SharePreview(
                            "Shady Spade — Room \(roomCode)",
                            image: Image(uiImage: qrImage)
                        )
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.bubble")
                            Text("Share Room Code").fontWeight(.bold)
                        }
                        .foregroundStyle(.adaptivePrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.adaptiveSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .background(Color.darkBG)
            }
        }
    }
}

// MARK: - Deep link notification name

extension Notification.Name {
    static let joinRoomFromQR = Notification.Name("joinRoomFromQR")
}

// MARK: - Player Slot Card

private struct PlayerSlotCard: View {
    let index: Int
    let slot: SessionPlayer
    var isAI: Bool = false
    var isHost: Bool = false
    var isNew: Bool = false
    var canRemove: Bool = false
    var onRemove: (() -> Void)? = nil
    @State private var showRemoveConfirm = false

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
                } else if isNew {
                    Text("NEW")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.offenseBlue)
                        .clipShape(Capsule())
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

            if isNew {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.offenseBlue)
                    .font(.caption)
            } else if isAI {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(Color.adaptiveSecondary)
                    .font(.caption)
            } else if slot.joined {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isHost ? Color.masterGold : .offenseBlue)
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
                    isNew ? Color.offenseBlue.opacity(0.5) :
                    isHost ? Color.masterGold.opacity(0.4) :
                    isAI ? Color.adaptiveSubtle :
                    slot.joined ? Color.offenseBlue.opacity(0.30) : Color.adaptiveSubtle,
                    lineWidth: isHost || isNew ? 1.5 : 1
                )
        }
        .opacity(isAI ? 0.85 : 1.0)
        .onTapGesture {
            if canRemove { showRemoveConfirm = true }
        }
        .confirmationDialog(
            isAI ? "Remove \(slot.name) (AI)?" : "Remove \(slot.name)?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(isAI ? "Remove AI Bot" : "Remove Player", role: .destructive) { onRemove?() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(isAI
                 ? "This slot will open for a human player to join."
                 : "They will be replaced by an AI bot.")
        }
    }
}
