import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var vm: GameViewModel
    @Environment(AuthViewModel.self) private var authVM
    @State private var showingAuth = false
    @State private var pickerTarget: PlayerPickerTarget? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        accountCard
                        playersCard
                        resetButton
                        aboutCard
                    }
                    .adaptiveContentFrame()
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .sheet(item: $pickerTarget) { target in
            AvatarPickerSheet(current: vm.playerAvatars[target.id]) { symbol in
                vm.updatePlayerAvatar(symbol, at: target.id)
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Account Card

    @ViewBuilder
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account")
                .font(.headline)
                .foregroundStyle(.masterGold)

            if let user = authVM.user {
                // Signed in
                HStack(spacing: 14) {
                    avatarCircle(symbol: "person.fill", color: .offenseBlue, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        if let name = user.displayName, !name.isEmpty {
                            Text(name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        Text(user.email ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if authVM.isEmailVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.offenseBlue)
                            .font(.title3)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.masterGold)
                            .font(.title3)
                    }
                }

                if !authVM.isEmailVerified {
                    HStack(spacing: 8) {
                        Text("Email not verified")
                            .font(.caption)
                            .foregroundStyle(.masterGold)
                        Spacer()
                        Button("Resend") {
                            Task { await authVM.sendVerificationEmail() }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.masterGold)
                    }
                    .padding(.horizontal, 4)
                }

                Divider().overlay(Color.white.opacity(0.08))

                Button {
                    HapticManager.impact(.medium)
                    if vm.isOnlineMode {
                        Task {
                            await vm.onlineSessionVM?.leaveSession()
                            vm.exitOnlineMode()
                        }
                    }
                    authVM.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.defenseRose)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Signed out
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not signed in")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Sign in to play online with friends")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign In") {
                        HapticManager.impact(.medium)
                        showingAuth = true
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.masterGold)
                }
            }
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Player Names")
                .font(.headline)
                .foregroundStyle(.masterGold)

            ForEach(0..<6, id: \.self) { idx in
                HStack(spacing: 12) {
                    Button {
                        HapticManager.impact(.light)
                        pickerTarget = PlayerPickerTarget(id: idx)
                    } label: {
                        avatarCircle(symbol: vm.playerAvatars[idx],
                                     color: vm.avatarColor(for: idx), size: 40)
                    }
                    .accessibilityLabel("Avatar for \(vm.playerNames[idx])")
                    .accessibilityHint("Tap to change avatar")

                    TextField("Player \(idx + 1)", text: Binding(
                        get: { vm.playerNames[idx] },
                        set: { vm.updatePlayerName($0, at: idx) }
                    ))
                    .tint(.offenseBlue)
                    .foregroundStyle(.white)
                    .font(.body)
                }

                if idx < 5 {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About")
                .font(.headline)
                .foregroundStyle(.masterGold)

            HStack(spacing: 14) {
                Text("♠")
                    .font(.system(size: 36))
                    .foregroundStyle(.masterGold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The Shady Spade")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider().overlay(Color.white.opacity(0.08))

            Link(destination: URL(string: "https://example.com/privacy-policy")!) {
                HStack(spacing: 6) {
                    Text("Privacy Policy")
                        .font(.caption)
                        .foregroundStyle(.offenseBlue)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.offenseBlue)
                }
            }

            Text("© 2026 Vijay Goyal. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private var resetButton: some View {
        Button {
            HapticManager.impact(.medium)
            for i in 0..<6 {
                vm.updatePlayerName("Player \(i + 1)", at: i)
            }
        } label: {
            Text("Reset Names to Defaults")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(BouncyButton())
    }

}

// MARK: - Helpers

private struct PlayerPickerTarget: Identifiable {
    let id: Int
}

private func avatarCircle(symbol: String, color: Color, size: CGFloat) -> some View {
    ZStack {
        Circle().fill(color.opacity(0.15)).frame(width: size, height: size)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
    }
}

private struct AvatarPickerSheet: View {
    let current: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Choose Avatar")
                    .font(.headline).foregroundStyle(.white).padding(.top, 20)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(GameViewModel.avatarCatalog, id: \.symbol) { entry in
                        Button {
                            HapticManager.impact(.light)
                            onSelect(entry.symbol)
                            dismiss()
                        } label: {
                            avatarCircle(symbol: entry.symbol, color: entry.color, size: 56)
                                .overlay(
                                    current == entry.symbol
                                        ? Circle().stroke(Color.masterGold, lineWidth: 2.5)
                                        : nil
                                )
                        }
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
        }
    }
}
